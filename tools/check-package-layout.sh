#!/usr/bin/env bash
# Unpacks the built .deb variants without installing them, checks that everything the desktop
# integration needs is really inside, and runs the binary once in an empty environment.
#
# Usage: tools/check-package-layout.sh [variant ...]     (default: omadungeon omadungeon-lite)
#   DIST_DIR=dist            where to look for <variant>_*_amd64.deb
#   SMOKE_QUIT_AFTER=120     frames the smoke run is given before it quits itself
#
# Why this is a tool and not six lines of YAML. Both assertions below were real ones - a layout
# the .desktop file and the icon theme depend on, and a run with no Omarchy state, no otter
# shell and an empty HOME, which is the state every plain Debian or Ubuntu machine is in - and
# both of them lived only inside .github/workflows/ci.yml. Nothing in the repository could run
# them, they were in no register, and the gate's colour said nothing about them: exactly the
# shape of "a check nobody runs" that tools/checks.json exists to end. CI now calls this file,
# and so can anyone with a .deb in dist/.
#
# The smoke run is judged by its log, not by its exit status: Godot's push_error() writes
# "ERROR:" to stderr and still exits 0, so a bare --quit-after passed a package whose every
# colour came out magenta. It is headless throughout - it must never open a window, here or on
# a runner.
#
# Exit: 0 when every variant is complete and starts clean, 2 when a .deb is missing (build
# them with tools/deb.sh both), 1 when a file is missing or the run logged an engine error.
set -uo pipefail
cd "$(dirname "$0")/.."
dist="${DIST_DIR:-dist}"
quit_after="${SMOKE_QUIT_AFTER:-120}"
variants=("$@")
((${#variants[@]})) || variants=(omadungeon omadungeon-lite)

# Every path a fresh install has to contain. The icons are the ones
# usr/share/applications/omadungeon.desktop names by theme lookup, so a missing size is a
# launcher with no picture rather than an error anybody would see.
required_files=(
  usr/lib/omadungeon/omadungeon
  usr/share/applications/omadungeon.desktop
  usr/share/metainfo/org.omadungeon.Omadungeon.metainfo.xml
)
icon_sizes=(16 32 48 64 128 256)

fail=0
work=""
cleanup() { [[ -n "$work" ]] && rm -rf -- "$work"; }
trap cleanup EXIT

for variant in "${variants[@]}"; do
  deb=$(ls -1t "$dist/${variant}"_*_amd64.deb 2>/dev/null | head -n 1)
  if [[ -z "$deb" ]]; then
    echo "package-layout: no $dist/${variant}_*_amd64.deb - build it with tools/deb.sh both" >&2
    exit 2
  fi
  work="$(mktemp -d)"
  root="$work/root"
  mkdir -p "$root"
  if ! dpkg-deb -x "$deb" "$root"; then
    echo "package-layout: $deb could not be unpacked" >&2
    fail=1
    continue
  fi
  missing=()
  for path in "${required_files[@]}"; do
    [[ -e "$root/$path" ]] || missing+=("$path")
  done
  [[ -x "$root/usr/lib/omadungeon/omadungeon" ]] ||
    missing+=("usr/lib/omadungeon/omadungeon (not executable)")
  [[ -L "$root/usr/bin/omadungeon" ]] || missing+=("usr/bin/omadungeon (not a symlink)")
  for size in "${icon_sizes[@]}"; do
    [[ -f "$root/usr/share/icons/hicolor/${size}x${size}/apps/omadungeon.png" ]] ||
      missing+=("usr/share/icons/hicolor/${size}x${size}/apps/omadungeon.png")
  done
  for doc in copyright CREDITS.md changelog.Debian.gz; do
    [[ -f "$root/usr/share/doc/$variant/$doc" ]] || missing+=("usr/share/doc/$variant/$doc")
  done
  if ((${#missing[@]})); then
    printf 'package-layout: %s is missing %s\n' "$variant" "${missing[@]}" >&2
    fail=1
  fi

  # The empty-environment smoke test: no HOME of ours, no XDG directories anybody has written,
  # and a state dir that does not exist, so the built-in fallback palette is the path under
  # test rather than the developer's own theme.
  smoke="$work/smoke"
  mkdir -p "$smoke"
  if ! env -i PATH="$PATH" HOME="$smoke" \
    XDG_CONFIG_HOME="$smoke/config" XDG_STATE_HOME="$smoke/state" \
    XDG_DATA_HOME="$smoke/data" XDG_CACHE_HOME="$smoke/cache" \
    XDG_RUNTIME_DIR="$smoke/run" \
    OMADUNGEON_OMARCHY_STATE_DIR="$smoke/no-such-theme" \
    "$root/usr/lib/omadungeon/omadungeon" \
    --headless --quit-after "$quit_after" >"$work/$variant.log" 2>&1; then
    echo "package-layout: $variant exited non-zero running headless with no desktop theme" >&2
    fail=1
  fi
  # Two engine lines are shutdown bookkeeping rather than anything this check is asking about,
  # and both appear on runs that are otherwise perfectly clean - the same distinction
  # tools/godot-import.sh makes about "N resources still in use at exit". They are printed as a
  # note and do not fail the packages: this check exists to answer "does the built-in fallback
  # palette carry a machine with no Omarchy and no otter shell", and a leaked resource at exit
  # is a different question with a different owner. Everything else still fails.
  benign='resources still in use at exit|ObjectDB instances were leaked at exit'
  if grep -qE '^(ERROR|SCRIPT ERROR|USER ERROR):' "$work/$variant.log"; then
    grep -nE '^(ERROR|SCRIPT ERROR|USER ERROR):' "$work/$variant.log" |
      grep -vE "$benign" >"$work/$variant.errors" || true
    if [[ -s "$work/$variant.errors" ]]; then
      echo "package-layout: $variant logged an engine error with no desktop theme present:" >&2
      head -n 20 "$work/$variant.errors" >&2
      fail=1
    else
      echo "package-layout: $variant note: engine shutdown bookkeeping only, not a failure:"
      grep -nE "$benign" "$work/$variant.log" | head -n 5
    fi
  fi
  if ((fail == 0)); then
    echo "package-layout: $variant ok - layout complete, starts clean with an empty HOME"
  fi
  rm -rf -- "$work"
  work=""
done
exit "$fail"
