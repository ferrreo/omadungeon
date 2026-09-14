#!/usr/bin/env bash
# Imports every asset of a Godot project and FAILS LOUDLY when the import did not succeed.
# Usage: tools/godot-import.sh <project-dir> [log-dir]
#
# Why this exists instead of `godot --headless --path . --import || true`: the import crashes
# now and then (it is load-dependent - two Godot processes racing the same asset cache), and a
# swallowed crash leaves a *half-imported* project behind. Everything downstream then reports
# nonsense that looks like a real result: a wall of "Parse Error" / "Failed loading resource"
# test failures that vanish on a re-run, or a rendered check that screenshots the wrong screen
# and still prints (OK). Neither is a test result, so neither may be reported as one.
#
# The rule here: retry once (the crash is not deterministic), then abort with the import log
# kept and its last lines on stderr. A run whose import failed produces no test result and no
# screenshot at all. An import that hangs rather than crashing is bounded by IMPORT_TIMEOUT
# (300 s) and counts as a failed attempt.
#
# Failure is judged on two things, because the import can fail both ways:
#   * a non-zero exit (segfault, abort), and
#   * the marker lines a half-imported *asset cache* prints while exiting 0
#     ("Failed loading resource: res://assets/...png", "Unable to open file:
#     res://.godot/imported/glyphs.png-*.ctex").
# Two things that look like failures on purpose are not markers here:
#   * "ERROR: N resources still in use at exit" - a perfectly good import prints it every time;
#   * "SCRIPT ERROR: Parse Error" in a .gd file - that is a broken script, not a broken import.
#     tools/check-scripts.sh is what reports those, and a script that does not compile fails its
#     own tests honestly and legibly. Treating it as an import failure would also mean one
#     person mid-edit aborts everybody else's harness.
set -euo pipefail
project="${1:?godot-import.sh: project directory required}"
# Every import gets a deadline. Measured this round, with several agents capturing at once: a
# `godot --headless --import` sat for 14 minutes on 3 seconds of CPU, blocked in futex_wait,
# after another harness's sandbox sweep deleted the project directory out from under it (its
# own `.sandbox.lock` showed as `(deleted)` in /proc/<pid>/fd). Nothing here bounded it, and
# every harness in the tree calls this script before it does anything else - so one wedged
# import stops the gate, a capture tier or a soak for as long as anybody is prepared to wait,
# with no output and nothing to read. A deadline turns that into a failed attempt with a log.
import_timeout="${IMPORT_TIMEOUT:-300}"
log_dir="${2:-$project/tests/out}"
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
attempts="${IMPORT_ATTEMPTS:-2}"
markers='Failed loading resource|Unable to open file|Failed to load resource'
mkdir -p "$log_dir"
# Keep only the newest few failure logs, the way tools/headless-sway.sh does, so the screenshot
# directory stays readable. No pipeline: an empty glob makes ls exit non-zero, and `pipefail`
# would turn that into a failed run of the whole harness.
mapfile -t old_logs < <(ls -1t "$log_dir"/import-failed-*.log 2>/dev/null || true)
if ((${#old_logs[@]} > ${KEEP_FAILED_LOGS:-5})); then
  rm -f -- "${old_logs[@]:${KEEP_FAILED_LOGS:-5}}"
fi
# Named plainly while it is being written, and only *renamed* to import-failed-* when the
# import really did fail: a live run should not leave something called "failed" lying in the
# screenshot directory for anyone who lists it mid-import.
#
# A failed attempt's log is kept even when the retry succeeds, and the retry is said out loud.
# It used to be discarded, which made the one failure mode nobody can explain invisible: a
# gallery run printed `godot --import exited 134 (attempt 1/2)` - 134 is SIGABRT - succeeded on
# attempt 2 and reported 24 screens, and the only evidence of *why* the abort happened went
# with the log. Whether that is load-related or a real import bug is a question the next person
# should be able to answer from the logs rather than by reproducing it.
log="$log_dir/import-$$.log"
attempt_logs=()
status=0
for attempt in $(seq 1 "$attempts"); do
  status=0
  timeout -k 15 "$import_timeout" "$GODOT_BIN" --headless --path "$project" --import \
    >"$log" 2>&1 || status=$?
  reason=""
  if ((status == 124 || status == 137)); then
    # 124 is the deadline, 137 the follow-up KILL for a process that ignored the TERM.
    reason="godot --import made no progress in ${import_timeout}s and was killed"
  elif ((status != 0)); then
    reason="godot --import exited $status"
  elif grep -qE "$markers" "$log"; then
    reason="godot --import exited 0 but the project is half-imported"
  fi
  if [[ -z "$reason" ]]; then
    # The import is sound. Scripts that do not compile are somebody else's problem, but they
    # are not going to be a surprise either, so say so on the way past.
    if grep -qE 'SCRIPT ERROR' "$log"; then
      echo "godot-import: note: this project has script errors; tools/check-scripts.sh lists them:" >&2
      grep -E 'SCRIPT ERROR' "$log" | head -n 3 >&2
    fi
    rm -f "$log"
    if ((${#attempt_logs[@]} > 0)); then
      echo "godot-import: imported on attempt $attempt/$attempts after ${#attempt_logs[@]} retry/retries" >&2
      echo "godot-import: for $project; the failed attempt's log is kept:" >&2
      printf 'godot-import:   %s\n' "${attempt_logs[@]}" >&2
    fi
    exit 0
  fi
  kept="$log_dir/import-failed-$$-attempt$attempt.log"
  mv -f "$log" "$kept"
  attempt_logs+=("$kept")
  echo "godot-import: $reason (attempt $attempt/$attempts) for $project; log kept at $kept" >&2
done
log="${attempt_logs[-1]}"
echo "godot-import: import failed after $attempts attempt(s); refusing to run against a" >&2
echo "godot-import: half-imported project." >&2
echo "godot-import: full log at $log; last lines:" >&2
grep -E "$markers" "$log" | head -n 10 >&2 || true
tail -n 20 "$log" >&2
exit 3
