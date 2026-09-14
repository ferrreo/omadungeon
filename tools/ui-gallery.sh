#!/usr/bin/env bash
# Renders every UI screen with fake data inside headless sway and writes
# tests/out/ui_<screen>.png. Usage: tools/ui-gallery.sh [theme-fixture] [--only <screen>]
# Always runs against an rsync'd copy so concurrent agents never share .godot/.
#
# This is the harness a reviewer uses to look at every UI screen, so it owes the same three
# honesty guards tools/run-scenario.sh has, and used to have none of them:
#   * the expected PNGs are deleted before the run and have to exist, non-empty and newer than
#     the run, afterwards. Before, a capture that failed left the previous build's pictures on
#     disk and the script exited 0 - a reviewer would have been looking at the old build and
#     calling it this one. src/ui/ui_gallery.gd trusts `image.save_png()`'s return code, which
#     a missing image or a short write can still pass, so the file is checked here instead;
#   * the nested compositor runs under the same tests/out/.scenario.lock flock, because two
#     captures at once corrupt each other (4 of 18 failed once, with exit codes
#     indistinguishable from a real regression);
#   * the copy goes to OMADUNGEON_COPY_DIR / $TMPDIR / /var/tmp like the other two scripts, not
#     to /tmp: a ~1 GB copy in a RAM tmpfs pushes the machine into swap and produces short
#     copies that import clean and then fail everything.
# GALLERY_LOCK=0 opts out of the lock; GALLERY_LOCK_WAIT (default 600 s) bounds the wait and
# exits 3, deliberately not 2: "the machine was busy" is not "the UI regressed".
#
# Output name: tests/out/ui_<screen>.png for the default tokyo-night theme, and
# tests/out/ui_<screen>_<theme>.png for any other - the same rule tools/run-scenario.sh uses,
# and for the same reason. It used to write the bare name whatever theme it was given, so
# `tools/ui-gallery.sh catppuccin-latte` reported "24 screens captured" straight over the dark
# set and nothing in tests/out said which theme a ui_*.png was. GALLERY_SUFFIX=... overrides it
# (GALLERY_SUFFIX= forces the bare name).
#
# Every run also gets its own `user://` ($XDG_DATA_HOME), the same rule tools/test.sh uses: the
# rsync copy isolates res:// only, so without it a gallery run and a test run share the
# player's profile.json, gdUnit4's user://tmp and every fixed user:// fixture.
# OMADUNGEON_KEEP_USER_DIR=1 opts out and uses the real one.
set -euo pipefail
cd "$(dirname "$0")/.."
default_theme="tokyo-night"
# Only a bare word is a theme. `tools/ui-gallery.sh --only run_summary` used to consume
# `--only` as the theme name, which silently pointed OMADUNGEON_OMARCHY_STATE_DIR at a fixture
# that does not exist and - once the theme reached the filename - wrote 24 `ui_<screen>_--only`
# pictures over nothing anybody asked for.
theme="$default_theme"
if [[ $# -gt 0 && "$1" != -* ]]; then
  theme="$1"
  shift
fi
# Only a non-default theme earns a suffix, so the existing tests/out/ui_<screen>.png names keep
# working and a second theme can no longer overwrite the first.
if [[ -z "${GALLERY_SUFFIX+x}" ]]; then
  if [[ "$theme" == "$default_theme" ]]; then
    GALLERY_SUFFIX=""
  else
    GALLERY_SUFFIX="_${theme}"
  fi
fi
# A fixture name that does not exist used to be accepted in silence: OMADUNGEON_OMARCHY_STATE_DIR
# was pointed at the missing path, Desktop fell through to whatever desktop theming the machine
# happens to be wearing, and the run exited 0 with 24 PNGs named after a fixture none of them
# showed. Same rule as tools/run-scenario.sh, and checked before the 1 GB rsync rather than
# after it.
if [[ ! -d "tests/fixtures/omarchy/$theme/state" ]]; then
  echo "ui-gallery: no theme fixture '$theme' under tests/fixtures/omarchy." >&2
  echo "ui-gallery: fixtures are:" $(ls tests/fixtures/omarchy 2>/dev/null) >&2
  exit 4
fi
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
out_dir="$PWD/tests/out"
mkdir -p "$out_dir"
# The screens this run is expected to produce. Parsed out of the gallery's own SCREENS list so
# there is one source of truth; `--only <screen>` narrows it to that one.
only=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--only" ]]; then
    only="$arg"
  fi
  prev="$arg"
done
mapfile -t screens < <(
  sed -n '/^const SCREENS/,/^]/p' src/ui/ui_gallery.gd | grep -oE '"[a-z_0-9]+"' | tr -d '"'
)
if ((${#screens[@]} == 0)); then
  echo "ui-gallery: could not read SCREENS out of src/ui/ui_gallery.gd; refusing to run blind." >&2
  exit 4
fi
if [[ -n "$only" ]]; then
  screens=("$only")
fi
# Sweep sandboxes left behind by dead runs, same rule as tools/test.sh - and the rule is
# tools/sandbox-lib.sh's, not "is the pid in the name still in /proc": that pid is the harness
# *shell*, and the Godot child outlives a shell that is killed while still reading the copy.
# `.gallery-<pid>` is the per-run staging directory a suffixed run captures into; the EXIT trap
# removes it, but a KILL leaves it behind next to the screenshots.
source "$PWD/tools/sandbox-lib.sh"
SANDBOX_SWEEP_ROOTS=("${OMADUNGEON_COPY_DIR:-}" "${TMPDIR:-}" /var/tmp /tmp "$out_dir")
sandbox_sweep omadungeon-gallery- omadungeon-userdata- .gallery-
copy_root="${OMADUNGEON_COPY_DIR:-${TMPDIR:-/var/tmp}}"
cleanup_paths=()
cleanup() {
  local path
  for path in "${cleanup_paths[@]-}"; do
    [[ -n "$path" ]] && rm -rf -- "$path"
  done
}
trap cleanup EXIT
if [[ "${OMADUNGEON_KEEP_USER_DIR:-0}" != "1" ]]; then
  user_root="$copy_root/omadungeon-userdata-$$"
  mkdir -p "$user_root"
  sandbox_claim "$user_root"
  cleanup_paths+=("$user_root")
  export XDG_DATA_HOME="$user_root"
  export OMADUNGEON_TEST_USER_DIR="$user_root"
fi
copy="$copy_root/omadungeon-gallery-$$"
mkdir -p "$copy"
sandbox_claim "$copy"
rsync -a --delete --exclude .godot --exclude .git --exclude reports --exclude tests/out \
  --exclude export --exclude dist "$PWD/" "$copy/"
cleanup_paths+=("$copy")
# The gallery names its own files `ui_<screen>.png` and takes no suffix argument, so a suffixed
# run captures into a scratch directory of its own and the files are renamed on the way out.
# Capturing straight into tests/out under the bare names would delete the default theme's set
# before this run had produced anything - which is the bug being fixed, not a fix for it.
shot_dir="$out_dir"
if [[ -n "$GALLERY_SUFFIX" ]]; then
  shot_dir="$out_dir/.gallery-$$"
  rm -rf "$shot_dir"
  mkdir -p "$shot_dir"
  sandbox_claim "$shot_dir"
  cleanup_paths+=("$shot_dir")
fi
# A failed import would render half the gallery against missing textures and still exit 0.
tools/godot-import.sh "$copy" "$out_dir"
# The exit code the gallery asked for, written by `QuitGuard.request` before it arms its
# watchdog (src/core/quit_guard.gd). A watchdog kill ends the process with SIGTERM, so it exits
# 143 and the code the run asked for is gone; this file is how the verdict survives the hang.
# Without it this harness folded 143 straight to 0, so a gallery that found failures and asked
# to exit 1 was recorded as a pass whenever the engine wedged on the way out.
exit_file="$copy_root/omadungeon-exit-$$"
rm -f "$exit_file"
cleanup_paths+=("$exit_file")
export OMADUNGEON_EXIT_FILE="$exit_file"
export OMADUNGEON_OMARCHY_STATE_DIR="$copy/tests/fixtures/omarchy/$theme/state"
# Same hard deadline as tools/run-scenario.sh (240 s): `-k` follows the TERM with a KILL, because a
# process wedged in driver init ignores TERM and plain `timeout` then waits for it forever.
export SWAY_KEEP_LOG_ON_FAILURE=1
run_start=$(date +%s)
capture() {
  local status=0 screen
  # Inside the lock, so a queued run cannot delete the output of the one still holding it.
  for screen in "${screens[@]}"; do
    rm -f "$out_dir/ui_${screen}${GALLERY_SUFFIX}.png"
    rm -f "$shot_dir/ui_$screen.png"
  done
  tools/headless-sway.sh timeout -k 15 "${SCENARIO_TIMEOUT:-240}" "$GODOT_BIN" --path "$copy" \
    --rendering-driver opengl3 --audio-driver Dummy res://src/ui/ui_gallery.tscn \
    -- --screenshot-dir "$shot_dir" "$@" || status=$?
  # Into their final names before the freshness check below, which is what "exit 0 means every
  # picture this run claims is on disk" rests on. A screen the gallery never drew has nothing
  # to move and is reported missing, exactly as before.
  if [[ "$shot_dir" != "$out_dir" ]]; then
    for screen in "${screens[@]}"; do
      [[ -s "$shot_dir/ui_$screen.png" ]] || continue
      mv -f "$shot_dir/ui_$screen.png" "$out_dir/ui_${screen}${GALLERY_SUFFIX}.png"
    done
  fi
  return "$status"
}
status=0
if [[ "${GALLERY_LOCK:-1}" == "1" ]] && command -v flock >/dev/null 2>&1; then
  # Beside the output and shared with run-scenario.sh: one nested compositor at a time on this
  # machine, whichever harness started it.
  lock="$out_dir/.scenario.lock"
  exec {lock_fd}>"$lock"
  if ! flock -w "${GALLERY_LOCK_WAIT:-600}" "$lock_fd"; then
    echo "ui-gallery: another capture held $lock for ${GALLERY_LOCK_WAIT:-600}s; giving up." >&2
    exit 3
  fi
  capture "$@" || status=$?
  flock -u "$lock_fd"
else
  capture "$@" || status=$?
fi
if ((status == 124 || status == 137)); then
  echo "ui-gallery: the gallery ($theme) did not finish within ${SCENARIO_TIMEOUT:-240}s; killed." >&2
  echo "ui-gallery: compositor log kept under $out_dir (sway-failed-*.log)." >&2
fi
# 143 is SIGTERM from the game's own quit watchdog (src/core/quit_guard.gd): the gallery asked
# to quit and the engine's Wayland teardown hung (Godot 4.7.1 reader race, see docs/TESTING.md).
# The code it asked for is in $exit_file, written before the watchdog was armed, so it is read
# back rather than assumed. This used to fold to 0 unconditionally, which meant every failure
# the gallery found was erased whenever the engine wedged - and the freshness check below cannot
# see those, because a gallery that renders a broken screen still writes a fresh PNG of it.
# No file means the run died before it could say what it wanted, and that is not a pass either.
if ((status == 143)); then
  recorded=""
  if [[ -s "$exit_file" ]]; then
    recorded=$(tr -cd '0-9' <"$exit_file" | head -c 3)
  fi
  if [[ -z "$recorded" ]]; then
    echo "ui-gallery: the quit watchdog ended the run (exit 143) and no exit code reached" >&2
    echo "ui-gallery: $exit_file, so what the gallery found is unknown. Failing: an unknown" >&2
    echo "ui-gallery: verdict is not a pass." >&2
    status=1
  else
    status="$recorded"
    if ((status == 0)); then
      echo "ui-gallery: the gallery passed, then the engine hung on exit and the watchdog" >&2
      echo "ui-gallery: ended it. The run itself asked for 0, so it passes; pictures still checked." >&2
    else
      echo "ui-gallery: the engine hung on exit, but the gallery had already asked to exit" >&2
      echo "ui-gallery: $status. Reporting that, not the signal." >&2
    fi
  fi
fi
# The honesty check: exit 0 has to mean "every picture this run claims to have taken is on disk
# and is this run's". A missing, empty or stale file is a failed capture even when the gallery
# said nothing, which is exactly the case that used to pass.
missing=()
for screen in "${screens[@]}"; do
  shot="$out_dir/ui_${screen}${GALLERY_SUFFIX}.png"
  if [[ ! -s "$shot" ]] || (($(stat -c %Y "$shot" 2>/dev/null || echo 0) < run_start)); then
    missing+=("ui_${screen}${GALLERY_SUFFIX}.png")
  fi
done
if ((${#missing[@]} > 0)); then
  echo "ui-gallery: ${#missing[@]} of ${#screens[@]} screens produced no fresh PNG:" >&2
  printf 'ui-gallery:   %s\n' "${missing[@]}" >&2
  if ((status == 0)); then
    status=2
  fi
fi
if ((status == 0)); then
  echo "ui-gallery: ${#screens[@]} screens captured to $out_dir as ui_<screen>${GALLERY_SUFFIX}.png"
fi
exit "$status"
