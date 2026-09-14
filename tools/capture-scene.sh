#!/usr/bin/env bash
# Runs one of the capture *scenes* inside headless sway and leaves its PNGs in tests/out/.
# Usage: tools/capture-scene.sh <scene-id> [theme-fixture] [extra game args...]
#
# Scene ids come from tools/checks.json ("capture_scenes"): prop_frame, feel_tell, ui_stats,
# ui_trade. They are main scenes rather than gdUnit suites because what they measure only
# exists once something has been rendered, and tier 1 runs --headless, where the dummy driver
# returns no viewport image at all (docs/TESTING.md tier 2).
#
# Why this script exists: until now nothing ran them. `tests/unit/rooms/prop_frame_capture` is
# not a picture-taker - it reads its own PNG back and exits 2 when a prop is under
# Prop.READABLE_CONTRAST or has lost its interior ladder - and it had been exiting 2 on the
# default theme while the release gate reported green, because the only way to run it was to
# type the `tools/headless-sway.sh godot --path . ...` line out of the doc comment by hand.
# A check nobody runs is worse than no check. `tools/run-checks.sh rendered` runs every one of
# them; this is the single-capture entry point underneath it.
#
# It carries the same four guards as tools/run-scenario.sh, for the same reasons:
#   * the theme fixture must exist (exit 4), so a PNG can never be named after a fixture the
#     run did not read - otherwise Desktop falls through to the machine's own desktop theming;
#   * the expected PNGs are deleted first and must come back non-empty and newer than the run
#     (exit 2), so "exit 0" can never mean "last run's pictures are still lying there";
#   * one nested compositor at a time, on tests/out/.scenario.lock (exit 3 on timeout, which
#     is deliberately not 2: "the machine was busy" is not "the render regressed");
#   * a hard deadline with a follow-up KILL, because a process wedged in GL init ignores TERM.
# The scene's own exit code is passed through untouched: prop_frame's 2 is the finding.
#
# Environment: CAPTURE_TIMEOUT (default 300 s), CAPTURE_LOCK / CAPTURE_LOCK_WAIT (as
# SCENARIO_LOCK / SCENARIO_LOCK_WAIT), CAPTURE_SUFFIX (override the theme suffix in the output
# names), OMADUNGEON_TEST_COPY=1 (run against an rsync'd copy; the PNGs are copied back),
# OMADUNGEON_KEEP_USER_DIR=1 (use the real user:// instead of a per-run one).
set -euo pipefail
cd "$(dirname "$0")/.."
default_theme="tokyo-night"
scene_id="${1:-}"
if [[ -z "$scene_id" ]]; then
  echo "capture-scene: usage: tools/capture-scene.sh <scene-id> [theme-fixture]" >&2
  echo "capture-scene: ids are:" $(python3 tools/checks.py scene-ids) >&2
  exit 4
fi
shift
theme="$default_theme"
if [[ $# -gt 0 && "$1" != -* ]]; then
  theme="$1"
  shift
fi
# The register is the single source of truth for which scenes exist and what each one must
# leave behind, so this script and tests/unit/tools/check_registry_test.gd cannot drift apart.
scene_path="$(python3 tools/checks.py scene-path "$scene_id" || true)"
if [[ -z "$scene_path" ]]; then
  echo "capture-scene: no capture scene '$scene_id' in tools/checks.json." >&2
  echo "capture-scene: ids are:" $(python3 tools/checks.py scene-ids) >&2
  exit 4
fi
if [[ ! -f "${scene_path#res://}" ]]; then
  echo "capture-scene: tools/checks.json names $scene_path, which is not on disk." >&2
  exit 4
fi
if [[ ! -d "tests/fixtures/omarchy/$theme/state" ]]; then
  echo "capture-scene: no theme fixture '$theme' under tests/fixtures/omarchy." >&2
  echo "capture-scene: fixtures are:" $(ls tests/fixtures/omarchy 2>/dev/null) >&2
  exit 4
fi
# The default theme keeps the bare name; every other fixture earns a suffix, so two themes of
# the same scene never overwrite each other. Same rule as tools/run-scenario.sh.
if [[ -z "${CAPTURE_SUFFIX+x}" ]]; then
  if [[ "$theme" == "$default_theme" ]]; then
    CAPTURE_SUFFIX=""
  else
    CAPTURE_SUFFIX="_${theme}"
  fi
fi
mapfile -t expected < <(python3 tools/checks.py scene-outputs "$scene_id" "$CAPTURE_SUFFIX")
# A scene with no declared outputs has nothing this harness can check, and a run that checks
# nothing must not be able to print "ok" - that is the failure this whole register exists to
# end. `death_soak` is the one such scene: it is a soak, not a capture, and `tools/soak.sh`
# owns the process boundary its finding (a crash rate) needs.
if ((${#expected[@]} == 0)); then
  echo "capture-scene: '$scene_id' declares no outputs in tools/checks.json, so there would be" >&2
  echo "capture-scene: nothing here to verify and 'ok' would mean nothing. Run it through the" >&2
  echo "capture-scene: check that owns it - see 'tools/run-checks.sh list'." >&2
  exit 4
fi

GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
project="$PWD"
out_dir="$PWD/tests/out"
mkdir -p "$out_dir"
# Sweep the sandboxes of runs that are over on the way in. An EXIT trap cannot fire on a KILL,
# and each leftover is a ~1 GB rsync of the project; tools/sandbox-lib.sh owns the rule for
# what "over" means (not "the pid in the name is gone" - that pid is this shell, and Godot
# outlives a killed shell while still reading the copy).
source "$PWD/tools/sandbox-lib.sh"
SANDBOX_SWEEP_ROOTS=("${OMADUNGEON_COPY_DIR:-}" "${TMPDIR:-}" /var/tmp /tmp)
sandbox_sweep omadungeon-test- omadungeon-scenario- omadungeon-capture- omadungeon-userdata- \
  omadungeon-testlog-
copy_root="${OMADUNGEON_COPY_DIR:-${TMPDIR:-/var/tmp}}"
cleanup_paths=()
cleanup() {
  local path
  for path in "${cleanup_paths[@]-}"; do
    [[ -n "$path" ]] && rm -rf -- "$path"
  done
}
trap cleanup EXIT
# A per-run user:// - the half of "isolated run" an rsync of res:// never gives, because
# project.godot sets use_custom_user_dir and user:// is $XDG_DATA_HOME/omadungeon for every
# copy of the project alike. Without it a capture and a gate run share profile.json.
if [[ "${OMADUNGEON_KEEP_USER_DIR:-0}" != "1" ]]; then
  user_root="$copy_root/omadungeon-userdata-$$"
  mkdir -p "$user_root"
  sandbox_claim "$user_root"
  cleanup_paths+=("$user_root")
  export XDG_DATA_HOME="$user_root"
  export OMADUNGEON_TEST_USER_DIR="$user_root"
fi
copy=""
if [[ "${OMADUNGEON_TEST_COPY:-0}" == "1" ]]; then
  copy="$copy_root/omadungeon-capture-$$"
  mkdir -p "$copy"
  sandbox_claim "$copy"
  rsync -a --delete --exclude .godot --exclude .git --exclude reports --exclude tests/out \
    --exclude export --exclude dist "$PWD/" "$copy/"
  cleanup_paths+=("$copy")
  project="$copy"
  # A half-imported copy renders the wrong thing and still exits 0, so a failed import aborts
  # the capture (set -e) rather than producing a picture nobody can trust.
  tools/godot-import.sh "$copy" "$out_dir"
  mkdir -p "$copy/tests/out"
fi
export OMADUNGEON_OMARCHY_STATE_DIR="$project/tests/fixtures/omarchy/$theme/state"
export SWAY_KEEP_LOG_ON_FAILURE=1
# The capture scenes write to res://tests/out, so in copy mode they write into the copy. The
# PNGs are brought back afterwards; the checks below are made against the real tests/out, which
# is the directory a reviewer opens.
scene_out="$project/tests/out"
# The exit code the scene asked for, written by `QuitGuard.request` before it arms its watchdog
# (src/core/quit_guard.gd). A watchdog kill ends the process with SIGTERM, so it exits 143 and the
# code the scene asked for is gone; this file is how the verdict survives the hang. Outside the
# project tree, so a copy-mode run does not have to carry it back.
exit_file="$copy_root/omadungeon-exit-$$"
rm -f "$exit_file"
cleanup_paths+=("$exit_file")
export OMADUNGEON_EXIT_FILE="$exit_file"

capture() {
  local status=0
  local name
  # Inside the lock, so a queued run cannot delete the output of the one still holding it.
  for name in "${expected[@]}"; do
    rm -f "$out_dir/$name" "$scene_out/$name"
  done
  # Deleted inside the lock too, so a stale verdict can never answer for this run.
  rm -f "$exit_file"
  # --audio-driver Dummy: see tools/run-scenario.sh - alsa-lib's pipewire plugin can hang the
  # launch for minutes in a compositor with no PipeWire, and the dummy driver is what every
  # capture fell back to anyway.
  #
  # The comments used to sit *between* the continuation and the command, which a shell reads as
  # "run timeout with no command" followed by a separate, undeadlined godot: every capture ran
  # with no deadline at all and printed `Try 'timeout --help'` on the way past. Nothing may come
  # between the backslash and the argument it continues.
  tools/headless-sway.sh timeout -k 15 "${CAPTURE_TIMEOUT:-300}" \
    "$GODOT_BIN" --path "$project" --rendering-driver opengl3 --audio-driver Dummy \
    "$scene_path" "$@" || status=$?
  if [[ -n "$copy" ]]; then
    for name in "${expected[@]}"; do
      # An `if`, not `[[ ... ]] && cp`: a missing file would make the AND-list the last failing
      # command of the function and trip `set -e` before the real exit code is returned.
      if [[ -s "$scene_out/$name" ]]; then
        cp -f "$scene_out/$name" "$out_dir/$name"
      fi
    done
  fi
  return "$status"
}

run_start=$(date +%s)
status=0
if [[ "${CAPTURE_LOCK:-1}" == "1" ]] && command -v flock >/dev/null 2>&1; then
  # Beside the output and shared with tools/run-scenario.sh and tools/ui-gallery.sh: one
  # nested compositor at a time on this machine, whichever harness wants it.
  lock="$out_dir/.scenario.lock"
  exec {lock_fd}>"$lock"
  if ! flock -w "${CAPTURE_LOCK_WAIT:-600}" "$lock_fd"; then
    echo "capture-scene: another capture held $lock for ${CAPTURE_LOCK_WAIT:-600}s; giving up." >&2
    exit 3
  fi
  capture "$@" || status=$?
  flock -u "$lock_fd"
else
  capture "$@" || status=$?
fi
if ((status == 124 || status == 137)); then
  echo "capture-scene: '$scene_id' ($theme) did not finish within ${CAPTURE_TIMEOUT:-300}s; killed." >&2
  echo "capture-scene: compositor log kept under $out_dir (sway-failed-*.log)." >&2
fi
# The honesty check, and the reason a green exit means something. A scene that printed an error
# and quit 0, a compositor that never came up, a save_png() into an unwritable directory: all of
# them look like a pass from the exit code alone.
missing=()
for name in "${expected[@]}"; do
  if [[ ! -s "$out_dir/$name" ]]; then
    missing+=("$name")
  elif (($(stat -c %Y "$out_dir/$name") < run_start)); then
    missing+=("$name (older than this run)")
  fi
done
if ((${#missing[@]} > 0)); then
  echo "capture-scene: '$scene_id' ($theme) did not write:" >&2
  printf 'capture-scene:   tests/out/%s\n' "${missing[@]}" >&2
  if ((status == 0)); then
    status=2
  fi
fi
# 143 is SIGTERM from the game's quit watchdog (src/core/quit_guard.gd, for scenes that exit
# through QuitGuard.request): the engine hung in its own teardown after every PNG had landed and
# the watchdog ended it. Named every time, never folded into an "ok" in silence.
#
# The exit code the scene asked for dies with the process when that happens, so the PNGs landing
# is NOT evidence of a pass. Folding 143 to 0 on that evidence alone is how `pickup_frame` on
# catppuccin-latte printed four FAIL contrast rows, asked to exit 2, wedged on the way out and
# was recorded ok - and the rate of that false green is the rate of the hang, so it is a standing
# licence for a red rendered check to read green. `$exit_file` is read back instead of assumed.
# No file means the run died before it could say what it found, and an unknown verdict is not a
# pass either.
if ((status == 143)); then
  recorded=""
  if [[ -s "$exit_file" ]]; then
    recorded=$(tr -cd '0-9' <"$exit_file" | head -c 3)
  fi
  echo "capture-scene: '$scene_id' ($theme) was ended by the quit watchdog (exit 143, Godot" >&2
  echo "capture-scene: 4.7.1 Wayland reader race; see src/core/quit_guard.gd)." >&2
  if [[ -z "$recorded" ]]; then
    echo "capture-scene: no exit code reached $exit_file, so what the scene found is unknown." >&2
    echo "capture-scene: failing - an unknown verdict is not a pass." >&2
    status=2
  else
    status="$recorded"
    if ((status == 0)); then
      echo "capture-scene: the scene itself asked for 0, so it passes; the pictures are valid." >&2
    else
      echo "capture-scene: the scene had already asked to exit $status. Reporting that, not the" >&2
      echo "capture-scene: signal: the hang does not excuse the finding." >&2
    fi
  fi
fi
if ((status == 0)); then
  echo "capture-scene: $scene_id ($theme) ok - ${#expected[@]} PNG(s) under tests/out. Now look at them."
fi
exit "$status"
