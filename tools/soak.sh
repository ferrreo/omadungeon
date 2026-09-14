#!/usr/bin/env bash
# Soaks the death, drop and teardown path (tests/unit/tools/death_soak.gd), headless, many
# times over, and reports how many processes died.
#
# Usage: tools/soak.sh [--processes N] [--runs N] [--floors N] [--seed N] [--mortal]
#   --processes  how many godot processes to launch, one after another (default 10)
#   --runs       whole game runs inside each process (default 3)
#   --floors     floors per run (default 4)
#   --seed       first run seed; process p run i uses seed + p*1000 + i (default 20250913)
#   --mortal     let the player die rather than making them invulnerable
#   SOAK_MIN_DROPS / SOAK_MIN_ITEMS  fleet minima (default 1 each; see below)
#
# Why processes and not one long run: the failure this exists to catch is a segmentation
# fault, which takes the whole process with it. A crash rate is "how many of N processes
# died", so the harness has to own the process boundary. Each process gets its own seed block,
# so a reproduction can be replayed with `--processes 1 --seed <the one that died>`.
#
# Output: one line per process, then a summary with the crash count and the exit codes seen.
# Exit 0 when every process exited 0 and the fleet cleared its minima, 1 when any process failed
# or the fleet was too quiet to be evidence, 2 when any of them died on a signal (the crash this
# is hunting).
#
# Two layers of minimum, because they answer different questions. Each *process* asserts what a
# process must always do - kills per floor, a homing pickup per floor, both teardowns, and no
# item drop walked up to and left behind - and fails itself (tests/unit/tools/death_soak.gd,
# `_check_minima`). The *fleet* asserts the one thing a single seed block honestly cannot
# promise: item drops come from elites only, so a block can see none. Measured with
# `--processes 4 --runs 2 --floors 3`: 2, 0, 3 and 1 item drops across the four blocks. So "at
# least one item drop was seen, and at least one was taken" is summed over the whole soak
# (SOAK_MIN_DROPS, SOAK_MIN_ITEMS - both 1), rather than demanded of every process, because a
# per-process rule there would be a flaky check, which is its own kind of lie.
#
# Before this the soak asserted nothing at all: a process that killed nothing, saw no drop and
# took no item printed the same "SOAK done" line, exited 0, and read as coverage of the death,
# drop and teardown path.
#
# Isolation follows the other harnesses (tools/test.sh): its own $XDG_DATA_HOME per process,
# an optional rsync'd res:// under OMADUNGEON_TEST_COPY=1, and the shared sandbox sweep on the
# way in. Never opens a window: --headless, no compositor.
set -uo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
export OMADUNGEON_OMARCHY_STATE_DIR="${OMADUNGEON_OMARCHY_STATE_DIR:-$PWD/tests/fixtures/omarchy/tokyo-night/state}"
# The soak writes save files; keep them out of the player's real profile.json the way every
# other harness does. SaveManager reads this one as a sandbox marker.
export OMADUNGEON_SAVE_SANDBOX=1
processes=10
runs=3
floors=4
seed=20250913
mortal=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --processes) processes="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --floors) floors="$2"; shift 2 ;;
    --seed) seed="$2"; shift 2 ;;
    --mortal) mortal=1; shift ;;
    -h|--help) sed -n '2,39p' "$0"; exit 0 ;;
    *) echo "soak: unknown argument '$1'" >&2; exit 64 ;;
  esac
done
source "$PWD/tools/sandbox-lib.sh"
SANDBOX_SWEEP_ROOTS=("${OMADUNGEON_COPY_DIR:-}" "${TMPDIR:-}" /var/tmp /tmp)
sandbox_sweep omadungeon-test- omadungeon-scenario- omadungeon-userdata- omadungeon-soak-
copy_root="${OMADUNGEON_COPY_DIR:-${TMPDIR:-/var/tmp}}"
cleanup_paths=()
cleanup() {
  local path
  for path in "${cleanup_paths[@]-}"; do
    [[ -n "$path" ]] && rm -rf -- "$path"
  done
}
trap cleanup EXIT
project="$PWD"
if [[ "${OMADUNGEON_TEST_COPY:-0}" == "1" ]]; then
  copy="$copy_root/omadungeon-soak-$$"
  mkdir -p "$copy"
  sandbox_claim "$copy"
  rsync -a --delete --exclude .godot --exclude .git --exclude reports --exclude tests/out "$PWD/" "$copy/"
  cleanup_paths+=("$copy")
  project="$copy"
  export OMADUNGEON_OMARCHY_STATE_DIR="$copy/tests/fixtures/omarchy/tokyo-night/state"
  "$root/tools/godot-import.sh" "$copy" "$root/tests/out"
fi
log_dir="${SOAK_LOG_DIR:-$root/tests/out/soak}"
mkdir -p "$log_dir"
crashes=0
failures=0
codes=""
total_kills=0
total_drops=0
total_items=0
# One `key=value` out of a process's SOAK done line, or 0 when the process never printed one.
soak_value() {
  local key="$1" line="$2" value
  value="$(sed -n "s/.*[[:space:]]$key=\([0-9]\+\).*/\1/p" <<<"$line")"
  echo "${value:-0}"
}
for ((p = 0; p < processes; p++)); do
  user_root="$copy_root/omadungeon-userdata-soak-$$-$p"
  mkdir -p "$user_root"
  sandbox_claim "$user_root"
  log="$log_dir/soak-$$-$p.log"
  args=(--soak-runs "$runs" --soak-floors "$floors" --soak-seed "$((seed + p * 1000))")
  ((mortal)) && args+=(--soak-mortal)
  XDG_DATA_HOME="$user_root" OMADUNGEON_TEST_USER_DIR="$user_root" \
    timeout -k 15 "${SOAK_TIMEOUT:-900}" "$GODOT_BIN" --headless --path "$project" \
      res://tests/unit/tools/death_soak.tscn -- "${args[@]}" >"$log" 2>&1
  status=$?
  # Read before the log is deleted: the fleet minima below are summed out of these lines, and a
  # process that printed none contributes nothing, which is exactly what it did.
  summary="$(grep -m1 '^SOAK done' "$log" || true)"
  rm -rf -- "$user_root"
  codes="$codes $status"
  if ((status > 128)); then
    crashes=$((crashes + 1))
    echo "soak: process $p DIED on signal $((status - 128)) (seed block $((seed + p * 1000))); log: $log"
    tail -n 25 "$log" | sed 's/^/soak|   /'
  elif ((status != 0)); then
    failures=$((failures + 1))
    echo "soak: process $p exited $status (seed block $((seed + p * 1000))); log: $log"
    tail -n 15 "$log" | sed 's/^/soak|   /'
  else
    echo "soak: process $p ok - ${summary:-no summary line}"
    rm -f "$log"
  fi
  total_kills=$((total_kills + $(soak_value kills "$summary")))
  total_drops=$((total_drops + $(soak_value drops_seen "$summary")))
  total_items=$((total_items + $(soak_value items_taken "$summary")))
done
echo "soak: $processes processes, $crashes crashed, $failures failed; exit codes:$codes"
echo "soak: fleet totals: kills=$total_kills drops_seen=$total_drops items_taken=$total_items"
quiet=0
if ((total_drops < ${SOAK_MIN_DROPS:-1})); then
  echo "soak: the whole fleet saw $total_drops item drop(s), wanted ${SOAK_MIN_DROPS:-1}." >&2
  echo "soak: item drops come from elites, so this is a soak that never reached the drop" >&2
  echo "soak: path at all - give it more floors or more processes, or check the loot roll." >&2
  quiet=1
fi
if ((total_items < ${SOAK_MIN_ITEMS:-1})); then
  echo "soak: the whole fleet equipped $total_items drop(s), wanted ${SOAK_MIN_ITEMS:-1}." >&2
  echo "soak: the pickup, equip and displaced-item path did not run in any process." >&2
  quiet=1
fi
if ((crashes > 0)); then
  exit 2
elif ((failures > 0 || quiet > 0)); then
  exit 1
fi
exit 0
