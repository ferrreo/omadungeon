#!/usr/bin/env bash
# Starts a nested headless sway in an isolated runtime dir and runs a command inside it.
# Never touches the user's real session. Usage: tools/headless-sway.sh <command...>
# The compositor log lives inside the runtime dir and goes away with it; it is copied to
# tests/out/sway-failed-<pid>.log when sway fails to start, and - with SWAY_KEEP_LOG_ON_FAILURE=1 -
# when the inner command is killed by a deadline (exit 124/137). Copies are pruned to the
# newest KEEP_FAILED_LOGS.
set -euo pipefail
cd "$(dirname "$0")/.."
out_dir="tests/out"
keep_failed="${KEEP_FAILED_LOGS:-5}"
mkdir -p "$out_dir"
# Historical per-pid logs from before the log moved into the runtime dir.
rm -f "$out_dir"/sway-[0-9]*.log
# Keep only the newest few failure logs so the screenshot directory stays readable.
# No pipeline here: an empty glob makes ls exit non-zero, which `set -o pipefail` would turn
# into a failed run of the whole harness.
mapfile -t failed_logs < <(ls -1t "$out_dir"/sway-failed-*.log 2>/dev/null || true)
if ((${#failed_logs[@]} > keep_failed)); then
  rm -f -- "${failed_logs[@]:keep_failed}"
fi
real_runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$real_runtime/omadungeon-test-$$"
mkdir -p -m 0700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER="${WLR_RENDERER:-pixman}"
unset WAYLAND_DISPLAY DISPLAY SWAYSOCK
log="$XDG_RUNTIME_DIR/sway.log"
sway -V -c tools/sway-headless.conf >"$log" 2>&1 &
sway_pid=$!
cleanup() {
  kill "$sway_pid" 2>/dev/null || true
  wait "$sway_pid" 2>/dev/null || true
  rm -rf "$XDG_RUNTIME_DIR"
}
trap cleanup EXIT
socket=""
for _ in $(seq 1 100); do
  socket=$(sed -n "s/.*Running compositor on wayland display '\([^']*\)'.*/\1/p" "$log" | head -n1)
  [[ -n "$socket" && -S "$XDG_RUNTIME_DIR/$socket" ]] && break
  sleep 0.1
done
if [[ -z "$socket" || ! -S "$XDG_RUNTIME_DIR/$socket" ]]; then
  kept="$out_dir/sway-failed-$$.log"
  cp "$log" "$kept" 2>/dev/null || true
  echo "sway failed to start; see $kept" >&2
  # ...and say why here as well. The kept copy is worth nothing on a CI runner, where the
  # log is not an artifact and the container is gone by the time anyone reads the failure:
  # "sway failed to start" on its own cost a full round trip to learn it was a missing seat
  # manager. The compositor's own words are short and they are the whole diagnosis.
  echo "--- sway log ---" >&2
  tail -n 40 "$log" >&2 || true
  echo "--- end sway log ---" >&2
  exit 1
fi
export WAYLAND_DISPLAY="$socket"
# The log normally dies with the runtime dir. Keep it when the inner command was killed by a
# deadline (124 from `timeout`, 137 from its follow-up KILL) as well as when sway itself never
# came up: a startup hang leaves no other evidence at all.
status=0
"$@" || status=$?
if [[ "${SWAY_KEEP_LOG_ON_FAILURE:-0}" == "1" ]] && ((status == 124 || status == 137)); then
  kept="$out_dir/sway-failed-$$.log"
  cp "$log" "$kept" 2>/dev/null || true
  echo "command exited $status; compositor log kept at $kept" >&2
fi
exit "$status"
