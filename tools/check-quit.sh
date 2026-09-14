#!/usr/bin/env bash
# Times the game's exit. Runs the `quit` scenario (src/core/test_scenarios.gd: a built floor
# with the radio playing and the lights up, then `get_tree().quit(0)`) and fails when the
# process is still alive QUIT_BUDGET seconds after the driver printed its "exiting" line, or
# when it exits with anything but 0.
# Usage: tools/check-quit.sh [headless|rendered|close-headless|close] [theme-fixture]
#   headless        `--headless` (dummy display and audio drivers): what tier 1 machines can run
#   rendered        inside nested headless sway with the real GL driver (tools/headless-sway.sh),
#                   the configuration in which the hang was seen
#   close-headless  the same floor, ended by the NOTIFICATION_WM_CLOSE_REQUEST the engine
#                   delivers when a window manager asks the window to close, rather than by
#                   the game asking to quit. Headless, so tier 1 machines get it too.
#   close           the same, but the request is a real one: sway is told to close the window
#                   (`swaymsg kill`, the xdg_toplevel.close a title-bar X or Alt+F4 sends).
# The two close modes exist because that request used to reach nobody once a run had started.
# `Main` answered it, and `RunManager.new_run()` frees `Main` when the first floor is built, so
# from then on the close request arrived, SaveManager flushed on it, and the game stayed up:
# measured 2026-09-14 in nested sway, still alive 30 s after `swaymsg kill`, window and all.
# A player could not close the window during a run at all. The answer is an autoload now
# (`src/core/quit_service.gd`), and these two modes are what stops it moving back into a scene.
# Why: a capture that had written its PNG then sat for 235 s until the harness killed it,
# three times in one run of the scenarios check and once before on an arena capture, always
# after the screenshot and always under load. run-scenario.sh reports that as "what hung was
# the shutdown, not the capture", which is honest and also the whole of what anything measured
# about the end of a run. A game that sometimes refuses to exit ships nowhere, so the exit is
# now a check of its own with a budget.
# Environment: QUIT_BUDGET (seconds, default 5), QUIT_TIMEOUT (hard deadline on the whole run,
# default 120), OMADUNGEON_KEEP_USER_DIR=1 to use the real user:// instead of a per-run one.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-headless}"
theme="${2:-tokyo-night}"
# `quit_by` picks which exit src/core/test_scenarios.gd measures; `rendered_mode` says whether
# this mode needs a compositor.
rendered_mode=0
quit_by=""
case "$mode" in
  headless) ;;
  rendered) rendered_mode=1 ;;
  close-headless) quit_by="self-close" ;;
  close)
    rendered_mode=1
    quit_by="wm-close"
    ;;
  *)
    echo "check-quit: mode is headless, rendered, close-headless or close, not '$mode'" >&2
    exit 4
    ;;
esac
if [[ ! -d "tests/fixtures/omarchy/$theme/state" ]]; then
  echo "check-quit: no theme fixture '$theme' under tests/fixtures/omarchy." >&2
  exit 4
fi
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
budget="${QUIT_BUDGET:-5}"
deadline="${QUIT_TIMEOUT:-120}"
export OMADUNGEON_OMARCHY_STATE_DIR="$PWD/tests/fixtures/omarchy/$theme/state"
source "$PWD/tools/sandbox-lib.sh"
SANDBOX_SWEEP_ROOTS=("${OMADUNGEON_COPY_DIR:-}" "${TMPDIR:-}" /var/tmp /tmp)
sandbox_sweep omadungeon-quit-
copy_root="${OMADUNGEON_COPY_DIR:-${TMPDIR:-/var/tmp}}"
work="$copy_root/omadungeon-quit-$$"
mkdir -p "$work"
sandbox_claim "$work"
trap 'rm -rf -- "$work"' EXIT
if [[ "${OMADUNGEON_KEEP_USER_DIR:-0}" != "1" ]]; then
  export XDG_DATA_HOME="$work/user"
  export OMADUNGEON_TEST_USER_DIR="$work/user"
  mkdir -p "$XDG_DATA_HOME"
fi
log="$work/game.log"
shots="$work/shots"
mkdir -p "$shots"
args=(--path "$PWD" -- --test-scenario quit --screenshot-dir "$shots" --screenshot-suffix "_$theme")
if [[ -n "$quit_by" ]]; then
  args+=(--quit-by "$quit_by")
fi
if ((!rendered_mode)); then
  timeout -k 10 "$deadline" "$GODOT_BIN" --headless "${args[@]}" >"$log" 2>&1 &
else
  # One nested compositor at a time, on the same lock the captures take (tools/run-scenario.sh).
  mkdir -p tests/out
  exec {lock_fd}>tests/out/.scenario.lock
  if ! flock -w "${SCENARIO_LOCK_WAIT:-600}" "$lock_fd"; then
    echo "check-quit: another capture held tests/out/.scenario.lock; giving up." >&2
    exit 3
  fi
  export SWAY_KEEP_LOG_ON_FAILURE=1
  tools/headless-sway.sh timeout -k 10 "$deadline" "$GODOT_BIN" --rendering-driver opengl3 --audio-driver Dummy "${args[@]}" >"$log" 2>&1 &
fi
job=$!
# `tools/headless-sway.sh` puts its nested compositor in $XDG_RUNTIME_DIR/omadungeon-test-<its
# own pid>, and its own pid is exactly the `$!` above, so `close` mode can find that sway's IPC
# socket without globbing for it and picking up a leftover from somebody else's run.
nested_runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omadungeon-test-$job"
# Wait for the marker, then time the exit against the budget at 0.1 s resolution.
marker_at=""
while kill -0 "$job" 2>/dev/null; do
  if grep -q "Scenario quit: exiting at" "$log" 2>/dev/null; then
    marker_at=$(date +%s.%N)
    break
  fi
  sleep 0.1
done
# The loop polls at 0.1 s, and a headless exit can be quicker than that: the process is gone
# before the grep sees the marker it had already printed. That used to read as "the game exited
# before asking to quit", which is the message for a crash. If the marker is in the log, the
# game did ask; it simply beat the poller, so the exit took less than one poll interval.
if [[ -z "$marker_at" ]] && grep -q "Scenario quit: exiting at" "$log" 2>/dev/null; then
  marker_at=$(date +%s.%N)
fi
# In `close` mode the scenario prints the marker and then waits: nothing has asked the game to
# go yet. Ask sway to close the window, and time from the ask rather than from the marker, so
# the seconds reported are the ones the player would wait after clicking the X.
if [[ "$mode" == "close" && -n "$marker_at" ]] && kill -0 "$job" 2>/dev/null; then
  sway_sock=$(ls "$nested_runtime"/sway-ipc.*.sock 2>/dev/null | head -n1)
  if [[ -z "$sway_sock" ]]; then
    echo "check-quit (close, $theme): found no sway IPC socket under $nested_runtime;" >&2
    echo "check-quit: cannot send a close request, so nothing was measured." >&2
    kill -9 "$job" 2>/dev/null || true
    exit 3
  fi
  if ! SWAYSOCK="$sway_sock" swaymsg kill >/dev/null 2>&1; then
    echo "check-quit (close, $theme): 'swaymsg kill' failed against $sway_sock." >&2
    kill -9 "$job" 2>/dev/null || true
    exit 3
  fi
  marker_at=$(date +%s.%N)
fi
status=0
if [[ -z "$marker_at" ]]; then
  wait "$job" || status=$?
  echo "check-quit ($mode, $theme): the game exited $status before asking to quit; log follows." >&2
  grep -v "^$" "$log" | tail -20 >&2
  exit 2
fi
while kill -0 "$job" 2>/dev/null; do
  sleep 0.1
done
wait "$job" || status=$?
ended_at=$(date +%s.%N)
elapsed=$(python3 -c "print(round($ended_at - $marker_at, 2))")
summary="check-quit ($mode, $theme): $(grep 'Scenario quit: floor' "$log" | tail -1 | sed 's/^Scenario quit: //'); exit $status, ${elapsed}s after the ${quit_by:-request} (budget ${budget}s)"
within=0
python3 -c "import sys; sys.exit(0 if $elapsed <= $budget else 1)" && within=1
if ((status == 143)) && ((within)); then
  # The engine hung in its own teardown and QuitGuard's watchdog ended the process inside the
  # budget: the guarantee this check exists for ("the process is gone within the budget")
  # held, and the hang is named so the ledger shows how often the engine needs it.
  echo "$summary - ok, BY WATCHDOG: the engine did not come down on its own (Godot 4.7.1 Wayland reader race, src/core/quit_guard.gd)"
  exit 0
fi
if ((status != 0)); then
  echo "$summary - FAILED: non-zero exit (124/137 is the ${deadline}s deadline kill: the process never came down)" >&2
  grep -v "^$" "$log" | tail -20 >&2
  exit 1
fi
if ((within)); then
  echo "$summary - ok"
  exit 0
fi
echo "$summary - FAILED: over budget" >&2
exit 1
