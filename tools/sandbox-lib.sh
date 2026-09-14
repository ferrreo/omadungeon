#!/usr/bin/env bash
# Shared sandbox bookkeeping for tools/test.sh, tools/run-scenario.sh and tools/ui-gallery.sh.
# Sourced, never executed.
#
# Each harness rsyncs the project to `<copy root>/omadungeon-<kind>-<pid>` and points
# $XDG_DATA_HOME at `<copy root>/omadungeon-userdata-<pid>`, and each sweeps the leftovers of
# runs that died before their EXIT trap could fire (a KILL, a deadline, a full disk). The sweep
# used to decide a run was finished by looking the *harness shell's* pid up in /proc - and the
# shell is only half of a run. Godot outlives a shell that is killed: a caller timeout, a
# Ctrl-C, a runner killing the process-group leader. Observed on this machine: a
# `godot --headless -s GdUnitCmdTool.gd` reparented to init with 2h36m of CPU, its cwd reading
# `/var/tmp/omadungeon-test-2455577 (deleted)`, while four concurrent runs' directories were
# untouched - the next harness in had rm -rf'd exactly the one whose shell had died. Both
# halves of that are bad: the orphan never exits and burns a core, and a deletion that lands
# mid-run makes a healthy suite fail for reasons that read as project regressions.
#
# So liveness is asked of the sandbox, not of a pid parsed out of its name. Three answers, any
# one of which means "leave it alone":
#
#   * **The lock is held.** `sandbox_claim` takes an flock on `<dir>/.sandbox.lock` and keeps
#     the descriptor open for the life of the harness. Godot inherits that descriptor, and an
#     flock belongs to the open file description rather than to a process, so the lock stays
#     held for exactly as long as the shell *or any child it started* is alive - which is the
#     property "is this sandbox still in use" actually wants. It is released by the kernel when
#     the last of them exits, KILL included, so nothing has to be cleaned up for it to be
#     right.
#   * **It is some live process's working directory.** The backstop for sandboxes made before
#     this file existed, for a machine with no flock(1), and for anything that chdir'd in
#     without claiming.
#   * **The pid in its name is alive.** The original rule, kept: it is what covers a sandbox
#     whose owner has not started a child yet.
#
# Every check fails safe. "I cannot tell" is answered with "in use", because a sandbox left
# behind costs disk and a sandbox deleted from under a live run costs a red gate that lies
# about why.

## Name of the per-sandbox lock file. Inside the sandbox, so it goes away with it.
SANDBOX_LOCK_NAME=".sandbox.lock"
## Roots `sandbox_sweep` walks. Set by the caller before calling it.
SANDBOX_SWEEP_ROOTS=()
## Descriptors `sandbox_claim` is holding, kept so nothing closes them by accident.
SANDBOX_LOCK_FDS=()

## Takes the in-use lock on sandbox `$1`, which must already exist.
##
## Never fails the caller: a machine without flock(1), or a directory that cannot be written,
## falls back to the other two liveness rules rather than refusing to run.
sandbox_claim() {
  local dir="${1:?sandbox_claim: directory required}" fd
  [[ -d "$dir" ]] || return 0
  command -v flock >/dev/null 2>&1 || return 0
  # The braces matter. `exec {fd}>... 2>/dev/null` is an `exec` with no command, so *both* of
  # its redirections are permanent: the harness's own stderr was sent to /dev/null for the rest
  # of the run, by the first sandbox it claimed. Every diagnostic every harness wrote after that
  # point went nowhere - tools/test.sh's "the run wrote no gdUnit report", its class-cache
  # refusal, tools/soak.sh's fleet minima, the scenario harnesses' failure lines. Found by a
  # `soak: the whole fleet saw 0 item drop(s)` message that set the exit code and printed
  # nothing. A redirection on a group applies to the group and is undone when it ends.
  { exec {fd}>"$dir/$SANDBOX_LOCK_NAME"; } 2>/dev/null || return 0
  if ! flock -n "$fd"; then
    exec {fd}>&-
    return 0
  fi
  SANDBOX_LOCK_FDS+=("$fd")
  return 0
}

## True when sandbox `$1`'s lock is held by a live process (or when that cannot be determined).
sandbox_lock_held() {
  local lock="${1%/}/$SANDBOX_LOCK_NAME"
  [[ -e "$lock" ]] || return 1
  command -v flock >/dev/null 2>&1 || return 0
  # A non-zero exit is "busy" or "something went wrong", and both mean "do not delete this".
  flock -n "$lock" -c true >/dev/null 2>&1 && return 1
  return 0
}

## True when some live process is working inside directory `$1`.
##
## A deleted directory still reads back through /proc as `<path> (deleted)`, which is precisely
## the state the orphaned gate was found in, so the suffix is stripped before comparing.
sandbox_dir_in_use() {
  local dir="${1%/}" link cwd
  [[ -d /proc ]] || return 0
  for link in /proc/[0-9]*/cwd; do
    cwd=$(readlink "$link" 2>/dev/null) || continue
    cwd="${cwd% (deleted)}"
    [[ "$cwd" == "$dir" || "$cwd" == "$dir"/* ]] && return 0
  done
  return 1
}

## True when sandbox `$1` belongs to nobody and may be removed.
##
## False for anything this rule cannot account for - a name with no pid in it, this run's own
## sandbox, a live owner, a held lock, a live process inside it.
sandbox_is_stale() {
  local dir="${1%/}" pid
  [[ -d "$dir" ]] || return 1
  pid="${dir##*-}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  ((pid == $$)) && return 1
  [[ -d "/proc/$pid" ]] && return 1
  sandbox_lock_held "$dir" && return 1
  sandbox_dir_in_use "$dir" && return 1
  return 0
}

## Removes every stale sandbox named `<root>/<prefix>*` for each root in SANDBOX_SWEEP_ROOTS
## and each prefix given as an argument.
sandbox_sweep() {
  local root prefix dir
  [[ -d /proc ]] || return 0
  for root in "${SANDBOX_SWEEP_ROOTS[@]-}"; do
    [[ -n "$root" && -d "$root" ]] || continue
    for prefix in "$@"; do
      for dir in "$root/$prefix"*; do
        sandbox_is_stale "$dir" || continue
        rm -rf -- "$dir" 2>/dev/null || true
      done
    done
  done
  return 0
}
