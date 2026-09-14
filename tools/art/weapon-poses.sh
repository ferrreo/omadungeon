#!/usr/bin/env bash
# Captures the weapon-anchoring pose sheets: every weapon family, every facing, one PNG per
# beat of an attack, into tests/out/weapon_pose_<beat>.png.
#
# Usage: tools/art/weapon-poses.sh [theme-fixture]
#
# Why it exists: "the weapon looks held" is not a claim a unit test can make. The unit tests in
# tests/unit/player/weapon_anchor_test.gd drive a real controller and assert where the grip and
# the tip are; this puts the same thing in front of an eye, all eight facings side by side, so a
# facing anchored differently from its neighbours is visible instead of needing eight captures
# compared from memory. Then actually look at the PNGs.
#
# Same rules as tools/ui-gallery.sh: runs against an rsync'd copy so concurrent agents never
# share .godot/, inside a nested headless sway (never the real session), with its own
# $XDG_DATA_HOME, and the expected PNGs are deleted first and must come back non-empty - so
# "exit 0" can never mean "last run's pictures are still lying there".
# POSE_SUFFIX=... renames the outputs (used to keep a before/after pair side by side).
set -euo pipefail
cd "$(dirname "$0")/../.."
default_theme="tokyo-night"
theme="${1:-$default_theme}"
if [[ ! -d "tests/fixtures/omarchy/$theme/state" ]]; then
  echo "weapon-poses: no theme fixture '$theme' under tests/fixtures/omarchy." >&2
  exit 4
fi
BEATS=(rest wind impact recover dodge)
suffix="${POSE_SUFFIX:-}"
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
copy_root="${OMADUNGEON_COPY_DIR:-${TMPDIR:-/var/tmp}}"
copy="$copy_root/omadungeon-pose-$$"
userdir="$copy_root/omadungeon-posedata-$$"
shot_dir="$copy/tests/out"
out_dir="$PWD/tests/out"
mkdir -p "$out_dir" "$userdir"
cleanup() { rm -rf "$copy" "$userdir"; }
trap cleanup EXIT
export XDG_DATA_HOME="$userdir"
export OMADUNGEON_TEST_USER_DIR="$userdir"
export OMADUNGEON_OMARCHY_STATE_DIR="$PWD/tests/fixtures/omarchy/$theme/state"
rsync -a --delete --exclude .godot --exclude .git --exclude reports --exclude tests/out \
  --exclude export --exclude dist "$PWD/" "$copy/"
mkdir -p "$shot_dir"
tools/godot-import.sh "$copy" "$out_dir"
for beat in "${BEATS[@]}"; do rm -f "$out_dir/weapon_pose_${beat}${suffix}.png"; done
status=0
tools/headless-sway.sh timeout -k 15 "${SCENARIO_TIMEOUT:-240}" "$GODOT_BIN" --path "$copy" \
  --rendering-driver opengl3 res://src/player/weapon_pose_gallery.tscn \
  -- --screenshot-dir "$shot_dir" || status=$?
for beat in "${BEATS[@]}"; do
  src="$shot_dir/weapon_pose_$beat.png"
  [[ -s "$src" ]] && cp -f "$src" "$out_dir/weapon_pose_${beat}${suffix}.png"
done
missing=()
for beat in "${BEATS[@]}"; do
  [[ -s "$out_dir/weapon_pose_${beat}${suffix}.png" ]] || missing+=("weapon_pose_${beat}${suffix}.png")
done
if ((${#missing[@]})); then
  echo "weapon-poses: missing captures: ${missing[*]}" >&2
  exit 2
fi
echo "weapon-poses: ${#BEATS[@]} sheets captured to $out_dir as weapon_pose_<beat>${suffix}.png"
exit "$status"
