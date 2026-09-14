#!/usr/bin/env bash
# Runs the game inside headless sway for one test scenario and leaves a screenshot in tests/out/.
# Usage: tools/run-scenario.sh <scenario> [theme-fixture] [extra game args...]
# Scenarios (src/core/test_scenarios.gd): boot, class_select, floor, combat, chest,
#   loot_drop (kills a pack for real and writes loot_drop_before.png - the drops on the floor -
#   then collects them, tears the floor down and shoots the rebuilt one), pause,
#   theme_swap (writes theme_swap_before.png too), theme_swap_midfight (same, over a live
#   fight), summary, new_run_confirm.
# Every scenario asserts that the state it claims to capture is actually on screen; one that
# cannot reach it exits 2 and writes no PNG, so a broken scenario can no longer look like a
# passing one. This script checks the other half: the expected PNG is deleted before the run
# and has to exist, non-empty, afterwards, so "exit 0" can never mean "the file from the last
# run is still lying there". That is not hypothetical - a capture into an unwritable directory
# used to print an error, leave yesterday's picture in place and exit 0.
# Concurrency: two captures at once corrupted each other (4 of 18 failed, with exit codes
# indistinguishable from a real regression), so the nested-compositor part is serialised on a
# lock file. SCENARIO_LOCK=0 opts out; SCENARIO_LOCK_WAIT (default 600 s) bounds the wait and
# exits 3, which is deliberately not 2: "the machine was busy" is not "the game regressed".
# Theme fixtures: tests/fixtures/omarchy/<name> (tokyo-night, catppuccin, gruvbox, nord, white, ...).
# theme_swap and theme_swap_midfight pin their own before/after pair and refuse a theme argument
# (exit 4) rather than label a capture with a theme it does not show; see the case below.
# Output name: tests/out/<scenario>.png for the default theme, tests/out/<scenario>_<theme>.png for
# any other, so two themes of the same scenario no longer overwrite each other. Override the
# suffix with SCENARIO_SUFFIX=... (SCENARIO_SUFFIX= forces the bare name).
# SCENARIO_TIMEOUT (default 240 s) is a hard deadline on the whole capture, KILL included: a
# hang fails loudly with the compositor log kept, instead of stalling the caller.
# Every capture also gets its own `user://` ($XDG_DATA_HOME, see tools/test.sh), so a capture
# and a test run at the same time cannot write each other's save files or fixtures, and a
# capture never leaves anything in the player's real data directory.
# OMADUNGEON_KEEP_USER_DIR=1 opts out and uses the real one.
set -euo pipefail
cd "$(dirname "$0")/.."
default_theme="tokyo-night"
scenario="${1:-boot}"; shift || true
# Only a bare word is a theme: `tools/run-scenario.sh floor --scenario-floor 3` used to take
# `--scenario-floor` as the theme fixture and stamp it into the output filename.
theme_given=0
theme="$default_theme"
if [[ $# -gt 0 && "$1" != -* ]]; then
  theme_given=1
  theme="$1"
  shift
fi
# `theme_swap` and `theme_swap_midfight` pin their own pair of themes: src/core/test_scenarios.gd
# builds the "before" state dir from `tokyo-night` and links the "after" one to `white`, whatever
# theme the caller named. The palette in the pair therefore never matched the theme argument,
# while this script still stamped that argument into the filename - so
# `theme_swap_catppuccin-latte.png` was a `white` capture wearing a latte label, and "every
# scenario under a dark and a light theme" quietly produced two palette-identical pairs. A
# filename that claims something the picture does not show is the exact failure this script
# exists to prevent, so the argument is refused instead of honoured in name only.
# SCENARIO_ALLOW_THEME=1 lifts the refusal for whoever teaches the scenarios to read it.
case "$scenario" in
  theme_swap | theme_swap_midfight)
    if ((theme_given)) && [[ "${SCENARIO_ALLOW_THEME:-0}" != "1" ]]; then
      echo "run-scenario: '$scenario' pins its own themes ($default_theme -> white) in" >&2
      echo "run-scenario: src/core/test_scenarios.gd and ignores a theme argument, so a" >&2
      echo "run-scenario: '$theme' in the filename would be a claim the picture does not" >&2
      echo "run-scenario: support. Run it with no theme, or set SCENARIO_ALLOW_THEME=1 once" >&2
      echo "run-scenario: the scenario actually honours the argument." >&2
      exit 4
    fi
    ;;
esac
# Only the non-default theme earns a suffix, so existing tests/out/<scenario>.png names keep working.
if [[ -z "${SCENARIO_SUFFIX+x}" ]]; then
  if [[ "$theme" == "$default_theme" ]]; then
    SCENARIO_SUFFIX=""
  else
    SCENARIO_SUFFIX="_${theme}"
  fi
fi
# A fixture name that does not exist used to be accepted in silence: OMADUNGEON_OMARCHY_STATE_DIR
# was pointed at the missing path, Desktop fell through to whatever desktop theming the machine
# happens to be wearing, and the run exited 0 with a PNG named after a fixture it never used.
# That is the same "a filename claiming something the picture does not show" failure the
# theme_swap refusal above exists to prevent, and a worse case of it: `run-scenario.sh floor
# no-such-theme` wrote floor_no-such-theme.png showing this developer's own live desktop colours.
# Checked here rather than beside the export below, so a typo costs nothing instead of a 1 GB
# rsync and a nested compositor.
if [[ ! -d "tests/fixtures/omarchy/$theme/state" ]]; then
  echo "run-scenario: no theme fixture '$theme' under tests/fixtures/omarchy." >&2
  echo "run-scenario: fixtures are:" $(ls tests/fixtures/omarchy 2>/dev/null) >&2
  exit 4
fi
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
project="$PWD"
out_dir="$PWD/tests/out"
mkdir -p "$out_dir"
# Sweep sandboxes left behind by dead runs before making another one. The EXIT trap below
# cleans up a normal exit, but it cannot fire on SIGKILL or on a deadline kill, and each
# leftover is a 700 MB-1.1 GB rsync of the project. On a tmpfs copy root they accumulate until
# the quota is gone, and the harness then fails in ways that look like project bugs but are
# not. Which leftovers belong to nobody is tools/sandbox-lib.sh's problem: not the pid in the
# directory name on its own, because that pid is the harness *shell* and the Godot child
# outlives a shell that is killed while still reading the copy. Safe to call while other
# agents are capturing or testing, which is the point of it.
source "$PWD/tools/sandbox-lib.sh"
SANDBOX_SWEEP_ROOTS=("${OMADUNGEON_COPY_DIR:-}" "${TMPDIR:-}" /var/tmp /tmp)
sandbox_sweep omadungeon-test- omadungeon-scenario- omadungeon-userdata- omadungeon-testlog-
# Disk-backed by default: $TMPDIR is a RAM tmpfs on a developer box, and two agents rsyncing
# the project into it pushed the machine into swap and produced short copies that imported
# clean and then failed every suite. Point OMADUNGEON_COPY_DIR (or TMPDIR) elsewhere to move it.
copy_root="${OMADUNGEON_COPY_DIR:-${TMPDIR:-/var/tmp}}"
cleanup_paths=()
cleanup() {
  local path
  for path in "${cleanup_paths[@]-}"; do
    [[ -n "$path" ]] && rm -rf -- "$path"
  done
}
trap cleanup EXIT
# A per-run user:// directory, the same rule tools/test.sh uses and for the same reason: the
# rsync copy isolates res:// only, and `user://` is $XDG_DATA_HOME/omadungeon for every copy
# of the project alike. Without this a capture and a test run share the player's profile.json,
# gdUnit4's user://tmp and every fixed user:// fixture - and a capture left its sandbox in the
# real data directory. The compositor part of a capture is serialised on a lock, but the
# import and the game's own writes are not.
if [[ "${OMADUNGEON_KEEP_USER_DIR:-0}" != "1" ]]; then
  user_root="$copy_root/omadungeon-userdata-$$"
  mkdir -p "$user_root"
  sandbox_claim "$user_root"
  cleanup_paths+=("$user_root")
  export XDG_DATA_HOME="$user_root"
  export OMADUNGEON_TEST_USER_DIR="$user_root"
fi
# OMADUNGEON_TEST_COPY=1 runs against an rsync'd copy (safe when several agents run scenarios).
if [[ "${OMADUNGEON_TEST_COPY:-0}" == "1" ]]; then
  copy="$copy_root/omadungeon-scenario-$$"
  mkdir -p "$copy"
  sandbox_claim "$copy"
  rsync -a --delete --exclude .godot --exclude .git --exclude reports --exclude tests/out \
    --exclude export --exclude dist "$PWD/" "$copy/"
  cleanup_paths+=("$copy")
  project="$copy"
  # A half-imported copy screenshots the wrong screen and still exits 0, so a failed import
  # aborts the capture (set -e) instead of producing a picture nobody can trust.
  tools/godot-import.sh "$copy" "$out_dir"
fi
# The exit code the game asked for, written by `QuitGuard.request` before it arms its watchdog
# (src/core/quit_guard.gd). A watchdog kill ends the process with SIGTERM, so it exits 143 and
# the code the run asked for is gone; this file is how the verdict survives the hang. Without
# it this harness guessed, and guessed "pass" - a capture that printed FAIL rows and asked to
# exit 2 was recorded ok once the engine wedged.
exit_file="$copy_root/omadungeon-exit-$$"
rm -f "$exit_file"
cleanup_paths+=("$exit_file")
export OMADUNGEON_EXIT_FILE="$exit_file"
export OMADUNGEON_OMARCHY_STATE_DIR="$project/tests/fixtures/omarchy/$theme/state"
# The in-game watchdog (TestScenarios.TIMEOUT_SECONDS) only fires once the main loop is up. A
# startup hang - a wedged GL context, a compositor that answered but never drew - happens
# before that and used to stall until the *caller's* timeout killed the job, which in CI reads
# as a hung job rather than a failed one. So the harness carries its own hard deadline:
# `-k` follows the TERM with a KILL, because a process stuck in driver init ignores TERM and
# plain `timeout` then waits for it forever. SCENARIO_TIMEOUT stays the knob.
export SWAY_KEEP_LOG_ON_FAILURE=1
# The file this run claims to produce. Removed first so a capture that never happens cannot be
# mistaken for one that did: a stale PNG with an old mtime reads exactly like a fresh result.
shot="$out_dir/${scenario}${SCENARIO_SUFFIX}.png"
capture() {
  local status=0
  # Inside the lock, so a queued run cannot delete the output of the one still holding it.
  rm -f "$shot" "$out_dir/${scenario}_before${SCENARIO_SUFFIX}.png"
  # --audio-driver Dummy: the nested compositor has no PipeWire, and without the flag Godot's
  # ALSA driver probes alsa-lib's pipewire plugin, whose failed connect can sit in
  # `pw_thread_loop_stop` -> `pthread_join` for minutes (measured 2026-09-14: main thread in
  # `snd_pcm_open` 110 s after launch, no main loop yet, so no in-game watchdog can fire);
  # the run then reads as "never reached its subject". Every capture ended up on the dummy
  # driver anyway ("All audio drivers failed, falling back to the dummy driver").
  tools/headless-sway.sh timeout -k 15 "${SCENARIO_TIMEOUT:-240}" "$GODOT_BIN" --path "$project" --rendering-driver opengl3 --audio-driver Dummy \
    -- --test-scenario "$scenario" --screenshot-dir "$out_dir" --screenshot-suffix "$SCENARIO_SUFFIX" "$@" || status=$?
  return "$status"
}
status=0
# One nested compositor at a time. Concurrent captures used to fail each other at random and
# report exit 2 ("the subject was never on screen"), which is the code a genuine regression
# returns, so a reviewer running two themes at once could not tell a bug from a busy machine.
if [[ "${SCENARIO_LOCK:-1}" == "1" ]] && command -v flock >/dev/null 2>&1; then
  # Beside the output, not in $TMPDIR: agents sharing this checkout have their own
  # TMPDIRs, and a per-agent lock serialises nothing.
  lock="$out_dir/.scenario.lock"
  exec {lock_fd}>"$lock"
  if ! flock -w "${SCENARIO_LOCK_WAIT:-600}" "$lock_fd"; then
    echo "run-scenario: another capture held $lock for ${SCENARIO_LOCK_WAIT:-600}s; giving up." >&2
    exit 3
  fi
  capture "$@" || status=$?
  flock -u "$lock_fd"
else
  capture "$@" || status=$?
fi
# 143 is SIGTERM from the game's own quit watchdog (src/core/quit_guard.gd): the engine did not
# come down on its own and the watchdog ended it. The run's real verdict is in $exit_file, written
# before the watchdog was armed, so it is read back here rather than assumed. No file means the
# process died before it could say what it wanted, and an unknown verdict is not a passing one.
if ((status == 143)); then
  recorded=""
  if [[ -s "$exit_file" ]]; then
    recorded=$(tr -cd '0-9' <"$exit_file" | head -c 3)
  fi
  if [[ -z "$recorded" ]]; then
    echo "run-scenario: the quit watchdog ended the run (exit 143) and no exit code reached" >&2
    echo "run-scenario: $exit_file, so what the run wanted is unknown. Failing: an unknown" >&2
    echo "run-scenario: verdict is not a pass." >&2
    status=1
  else
    status="$recorded"
    if ((status == 0)); then
      echo "run-scenario: '$scenario' ($theme) wrote its screenshot, then the engine hung on exit and the quit" >&2
      echo "run-scenario: watchdog ended it (Godot 4.7.1 Wayland reader race; see" >&2
      echo "run-scenario: src/core/quit_guard.gd). The run itself asked for 0, so it passes." >&2
    else
      echo "run-scenario: the engine hung on exit and the watchdog ended it, but the run had" >&2
      echo "run-scenario: already asked to exit $status. Reporting that, not the signal." >&2
    fi
  fi
fi
if ((status == 124 || status == 137)); then
  echo "run-scenario: '$scenario' ($theme) did not finish within ${SCENARIO_TIMEOUT:-240}s; killed." >&2
  echo "run-scenario: compositor log kept under $out_dir (sway-failed-*.log)." >&2
  # Say which half hung. A capture that wrote its PNG and then failed to shut down (seen once
  # on `summary` under heavy load: the log ends at "screenshot ... (OK, 28252 bytes)" and
  # nothing follows) looks identical, from the exit code alone, to one that never drew
  # anything - and they want opposite responses. This is still a failure: the process would
  # not exit and that is worth knowing. It is not "the picture is wrong".
  if [[ -s "$shot" ]]; then
    shot_age=$(( $(date +%s) - $(stat -c %Y "$shot") ))
    echo "run-scenario: the screenshot did land: $shot," >&2
    echo "run-scenario: $(stat -c %s "$shot") bytes, written ${shot_age}s before the kill." >&2
    echo "run-scenario: so what hung was the shutdown, not the capture. Re-run before" >&2
    echo "run-scenario: treating this as a rendering regression." >&2
  else
    echo "run-scenario: no screenshot was written, so the run never reached its subject." >&2
  fi
fi
# The honesty check. The driver exits 2 when it could not reach its subject and now also when
# the PNG did not land; this catches everything upstream of the driver - a compositor that
# never came up, a killed process, a game that quit 0 without ever running a scenario.
if ((status == 0)) && [[ ! -s "$shot" ]]; then
  echo "run-scenario: '$scenario' ($theme) exited 0 but wrote no screenshot at $shot." >&2
  status=2
fi
exit "$status"
