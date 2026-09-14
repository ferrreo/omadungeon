#!/usr/bin/env bash
# Runs gdUnit4 tests headless.
# Usage: tools/test.sh [gdUnit args, e.g. -c -a res://tests/unit/rooms]
# With no -a of your own the whole res://tests tree runs; pass one or more -a to narrow it
# (a caller's -a replaces the default rather than adding to it, which is what makes a subset
# run a subset).
# Set OMADUNGEON_TEST_COPY=1 to run against an rsync'd copy of the project (safe when
# several agents test concurrently; the shared .godot/ cache is never touched).
# Every run - copy mode or not - also gets its own `user://` directory and, outside copy mode,
# its own gdUnit report directory, so two runs at once cannot write each other's save files,
# fixtures or reports. OMADUNGEON_KEEP_USER_DIR=1 opts out of the first and uses the real
# $XDG_DATA_HOME/omadungeon (useful when you want to look at what a run wrote).
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
export OMADUNGEON_OMARCHY_STATE_DIR="${OMADUNGEON_OMARCHY_STATE_DIR:-$PWD/tests/fixtures/omarchy/tokyo-night/state}"
# Where the results ledger is, in the *real* checkout. tests/unit/tools/check_registry_test.gd
# fails the gate when a check outside tier 1 has no recent passing record there, and copy mode
# rsyncs res:// without `reports/` - so a gate running inside a copy would look for the ledger
# in a directory the rsync never made and report that nothing in tiers 2-4 has ever been run.
export OMADUNGEON_CHECK_RESULTS_DIR="${OMADUNGEON_CHECK_RESULTS_DIR:-$root/reports/checks}"
project="$PWD"
# Sweep sandboxes left behind by dead runs before making another one. The EXIT trap below
# cleans up a normal exit, but it cannot fire on SIGKILL or on a deadline kill, and each
# leftover is a 700 MB-1.1 GB rsync of the project. On a tmpfs copy root they accumulate until
# the quota is gone, and the harness then fails in ways that look like project bugs but are
# not: "Could not find type GdUnitTestCIRunner" with zero tests run (the class cache could not
# be written), "Disk quota exceeded" out of rsync, or a SIGPIPE mid-run when the log write
# fails. Every root either harness has ever used is swept, not just the one this run picked.
#
# What counts as "belongs to a dead run" is tools/sandbox-lib.sh's problem, and it is not the
# pid in the directory name on its own any more: that pid is the harness *shell*, and the Godot
# child outlives a shell that is killed, still reading the copy. See the header of that file
# for the orphan this produced and the three liveness rules that replaced it. Safe to call
# while other agents are testing, which is the whole point of it.
source "$PWD/tools/sandbox-lib.sh"
SANDBOX_SWEEP_ROOTS=("${OMADUNGEON_COPY_DIR:-}" "${TMPDIR:-}" /var/tmp /tmp)
sandbox_sweep omadungeon-test- omadungeon-scenario- omadungeon-userdata- omadungeon-testlog-
# Same copy root as tools/run-scenario.sh: $TMPDIR is a RAM tmpfs on a developer box, and a
# ~1 GB copy of the project in it competes with the machine. OMADUNGEON_COPY_DIR overrides.
copy_root="${OMADUNGEON_COPY_DIR:-${TMPDIR:-/var/tmp}}"
cleanup_paths=()
cleanup() {
  local path
  for path in "${cleanup_paths[@]-}"; do
    [[ -n "$path" ]] && rm -rf -- "$path"
  done
}
trap cleanup EXIT
# A per-run user:// directory, which is the half of "isolated run" the rsync never gave us.
# project.godot sets use_custom_user_dir, so user:// is $XDG_DATA_HOME/omadungeon - one
# directory shared by every copy of the project, because the copy isolates res:// and nothing
# else. Every fixed user:// path anything writes is therefore shared by every concurrent run:
# gdUnit's own user://tmp scratch, the music and otter-wallpaper fixtures, and - the one that
# actually bit - a work directory whose after_test() deleted it out from under the other run.
# The result is a red gate naming suites that are perfectly healthy, which is worse than a red
# gate: it is one that lies about why. $XDG_DATA_HOME is what Godot resolves user:// from, so
# moving it moves every user:// path at once, including the ones in suites nobody has fixed.
# Swept by the same dead-pid rule as the copies, since an EXIT trap cannot fire on a KILL.
if [[ "${OMADUNGEON_KEEP_USER_DIR:-0}" != "1" ]]; then
  user_root="$copy_root/omadungeon-userdata-$$"
  mkdir -p "$user_root"
  sandbox_claim "$user_root"
  cleanup_paths+=("$user_root")
  export XDG_DATA_HOME="$user_root"
  # tests/unit/tools/user_dir_isolation_test.gd reads this and fails the run when user:// is
  # not inside it. That is the guard that stops this from being quietly dropped again.
  export OMADUNGEON_TEST_USER_DIR="$user_root"
fi
if [[ "${OMADUNGEON_TEST_COPY:-0}" == "1" ]]; then
  copy="$copy_root/omadungeon-test-$$"
  mkdir -p "$copy"
  sandbox_claim "$copy"
  rsync -a --delete --exclude .godot --exclude .git --exclude reports --exclude tests/out "$PWD/" "$copy/"
  cleanup_paths+=("$copy")
  project="$copy"
  export OMADUNGEON_OMARCHY_STATE_DIR="$copy/tests/fixtures/omarchy/tokyo-night/state"
fi
cd "$project"
mkdir -p tests/out
# A failed import is not a test result. tools/godot-import.sh retries once and then aborts
# (set -e carries that out) with the import log kept, rather than letting a half-imported
# project report a wall of "Parse Error" failures that a re-run makes vanish.
"$root/tools/godot-import.sh" "$project" "$root/tests/out"
# A global class cache that could not be written is not an import failure by godot-import.sh's
# markers, but it makes every `class_name` in the project vanish. The run then dies with
# `Parse Error: Could not find type "GdUnitTestCIRunner"`, reports zero tests and exits 1 -
# which reads as a project failure and is not one. A full copy root is the usual cause.
class_cache="$project/.godot/global_script_class_cache.cfg"
if [[ ! -s "$class_cache" ]] || ! grep -q 'GdUnitTestCIRunner' "$class_cache"; then
  echo "test.sh: $class_cache is missing or incomplete - the import could not write the" >&2
  echo "test.sh: global class cache (a full copy root is the usual cause). Refusing to run:" >&2
  echo "test.sh: every class_name would be missing and the result would be meaningless." >&2
  df -h "$project" >&2 || true
  exit 4
fi
# Only add the whole-tree selector when the caller did not pass one of their own.
selector=(-a res://tests)
for arg in "$@"; do
  if [[ "$arg" == "-a" || "$arg" == "--add" ]]; then
    selector=()
    break
  fi
done
# Where gdUnit4 writes its report. It is the second piece of shared mutable state a second
# run collides on: gdUnit4 numbers reports report_<last+1> within one directory, so two runs
# sharing `reports/` can pick the same index, and the "newest report" resolution below can
# then read the *other* run's results and report its failures, or its pass, as this one's.
# In copy mode the copy has its own `reports/` (the rsync excludes it) and there is nothing to
# do. Outside copy mode the runs share the checkout, so each takes `reports/run-<pid>/`.
# A caller's own -rd always wins, and is honoured here too - before this, a -rd run read the
# wrong directory entirely and the zero-case guard fired on a perfectly good run.
report_dir="reports"
report_args=()
prev_arg=""
for arg in "$@"; do
  if [[ "$prev_arg" == "-rd" || "$prev_arg" == "--report-directory" ]]; then
    report_dir="${arg#res://}"
  fi
  prev_arg="$arg"
done
if [[ "$report_dir" == "reports" && "${OMADUNGEON_TEST_COPY:-0}" != "1" ]]; then
  report_dir="reports/run-$$"
  report_args=(-rd "res://$report_dir")
  # Keep the directory from growing without bound: gdUnit4's own "keep the newest N reports"
  # rule only prunes inside one directory, and per-run directories defeat it. A run whose pid
  # is gone is finished, so its reports are history; the newest few are kept to be read.
  if [[ -d reports ]]; then
    mapfile -t stale < <(
      for d in reports/run-*; do
        [[ -d "$d" ]] || continue
        pid="${d##*-}"
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [[ -d "/proc/$pid" ]] && continue
        printf '%s\n' "$d"
      done | xargs -r ls -1dt 2>/dev/null || true
    )
    if ((${#stale[@]} > ${KEEP_RUN_REPORTS:-5})); then
      rm -rf -- "${stale[@]:${KEEP_RUN_REPORTS:-5}}"
    fi
  fi
fi
set +e
# The clock this run started on. The report check below refuses anything older: a report from a
# previous run is not evidence about this one.
run_start=$(date +%s)
# Godot is started as a background child and waited on, rather than run as the left-hand side of
# a foreground pipeline, for one reason: a trap. Bash defers every signal handler until the
# foreground command returns, so a TERM to this shell used to be delivered to nobody until the
# gate finished on its own - and if the shell was killed outright, the gate carried on headless
# with no shell left to wait for it. That orphan is the one observed at 2h36m of CPU in
# tools/sandbox-lib.sh's header. `wait` is interruptible, so the same TERM now reaches the
# child. Unlike the capture harnesses, this one has no `timeout` around its child to bound it.
# The log filter runs on the other end of a fifo instead of in a pipeline, so its pid is known
# and the ordering of "every line Godot printed" against the summary below is still exact.
log_root="$copy_root/omadungeon-testlog-$$"
mkdir -p "$log_root"
sandbox_claim "$log_root"
cleanup_paths+=("$log_root")
log_fifo="$log_root/gdunit.fifo"
mkfifo "$log_fifo"
grep -vE 'update_scripts_classes|^\s*$' <"$log_fifo" &
filter_pid=$!
"$GODOT_BIN" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
  res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode "${selector[@]}" \
  "${report_args[@]}" "$@" >"$log_fifo" 2>&1 &
godot_pid=$!
# TERM first, KILL after a grace period: a Godot that is wedged in shutdown must not keep this
# shell (and the EXIT trap that removes the copy) waiting forever.
terminate_godot() {
  local waited=0
  kill -TERM "$godot_pid" 2>/dev/null || return 0
  while kill -0 "$godot_pid" 2>/dev/null && ((waited < 100)); do
    sleep 0.1
    waited=$((waited + 1))
  done
  kill -KILL "$godot_pid" 2>/dev/null || true
  wait "$godot_pid" 2>/dev/null || true
}
trap 'echo "test.sh: interrupted; stopping the gate (pid $godot_pid)." >&2; terminate_godot; exit 143' INT TERM HUP
wait "$godot_pid"
code=$?
wait "$filter_pid" 2>/dev/null
trap - INT TERM HUP
set -e
# Find the report *this* run produced. gdUnit4 keeps 20 reports and writes report_<last+1>
# (GdUnitConstants.DEFAULT_REPORT_HISTORY_COUNT, GdUnitTestSessionRunner), so reports/report_1
# is this run's only on the very first run in a fresh checkout - and report_1 was what both the
# failure dump and the case count used to read. In a checkout that had been tested before, the
# guard that exists to catch "this run executed nothing" was answered by an old run's numbers,
# and from run 22 on report_1 is deleted and the guard fired on a perfectly good run. Resolution
# is numeric, not lexicographic: sorted() puts report_9 after report_22.
report=$(python3 - "$report_dir" <<'REPORT_PY'
import glob, os, re, sys

best = None
for path in glob.glob(os.path.join(sys.argv[1], "report_*/results.xml")):
    match = re.search(r"report_(\d+)/results\.xml$", path)
    if match is None:
        continue
    index = int(match.group(1))
    if best is None or index > best[0]:
        best = (index, path)
print(best[1] if best else "")
REPORT_PY
)
# "The run produced nothing" looks like this: no report at all, or a newest report older than
# the run. Either way there is no evidence here to report a pass with.
if [[ -z "$report" || ! -f "$report" ]]; then
  echo "test.sh: the run wrote no gdUnit report under $project/$report_dir - not a pass." >&2
  echo "test.sh: selector was: ${selector[*]-} $*" >&2
  if ((code == 0)); then
    code=5
  fi
  exit "$code"
fi
if (($(stat -c %Y "$report") < run_start)); then
  echo "test.sh: the newest report ($report) predates this run; the run produced nothing." >&2
  echo "test.sh: selector was: ${selector[*]-} $*" >&2
  if ((code == 0)); then
    code=5
  fi
  exit "$code"
fi
python3 - "$report" <<'FAIL_PY'
import sys
import xml.etree.ElementTree as ET

for tc in ET.parse(sys.argv[1]).iter("testcase"):
    for kind in ("failure", "error"):
        e = tc.find(kind)
        if e is not None:
            head = (e.get("message") or "")[:800]
            body = (e.text or "")[:1200]
            print(f"\n{kind.upper()} {tc.get('classname')}.{tc.get('name')}\n{head}\n{body}")
FAIL_PY
# Zero tests is not a pass. A run that selected nothing, or whose runner failed to load, used
# to exit 0 and read as green; it now fails loudly with the selector that produced it.
cases=$(grep -o '<testcase ' "$report" | wc -l)
if ((cases == 0)); then
  echo "test.sh: the run reported 0 test cases - that is not a pass ($report)." >&2
  echo "test.sh: selector was: ${selector[*]-} $*" >&2
  if ((code == 0)); then
    code=5
  fi
  exit "$code"
fi
echo "test.sh: $cases test cases reported from $report; exit $code"
exit "$code"
