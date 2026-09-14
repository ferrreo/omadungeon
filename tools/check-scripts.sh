#!/usr/bin/env bash
# The compile gate: every project .gd is re-parsed and must compile.
#
# This used to be `godot --headless --path . --import` and a grep for SCRIPT ERROR, which was
# not a compile check at all: the importer does not re-parse a script whose cache it believes
# is current, so the check printed "scripts ok" and exited 0 over a tree holding a hard parse
# error - a commit could pass the documented compile gate with a project that cannot load a
# single class. The parse now comes from the parser: tools/check_scripts.gd loads every .gd
# with CACHE_MODE_IGNORE inside a real main loop (so the autoloads exist) and fails on any
# file that does not compile. The --import pass is kept for what it actually verifies, the
# asset cache.
#
# Like the other three harnesses it also gets its own `user://`. Both Godot passes below bring
# up every autoload, so `SaveManager` loads - and without this the compile gate wrote the
# player's real profile.json, pruned `user://test` underneath whatever gate was using it, and
# moved the mtime on the real log directory. `SaveManager.SANDBOX_ARG_MARKERS` does not cover
# it: it looks for `gdUnit4`, `--test-scenario` and `--screenshot-dir`, and this passes none of
# them. Moving $XDG_DATA_HOME moves the whole of `user://` at once, Godot's own log directory
# included, which the save sandbox alone would not.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
source "$PWD/tools/sandbox-lib.sh"
SANDBOX_SWEEP_ROOTS=("${OMADUNGEON_COPY_DIR:-}" "${TMPDIR:-}" /var/tmp /tmp)
sandbox_sweep omadungeon-userdata-
if [[ "${OMADUNGEON_KEEP_USER_DIR:-0}" != "1" ]]; then
  user_root="${OMADUNGEON_COPY_DIR:-${TMPDIR:-/var/tmp}}/omadungeon-userdata-$$"
  mkdir -p "$user_root"
  sandbox_claim "$user_root"
  trap 'rm -rf -- "$user_root"' EXIT
  export XDG_DATA_HOME="$user_root"
  export OMADUNGEON_TEST_USER_DIR="$user_root"
fi
# Step 1: the asset import. Its exit status is kept: a crashed import compiles only part of the
# tree, and any verdict over a half-imported project is a lie.
status=0
out=$("$GODOT_BIN" --headless --path . --import 2>&1) || status=$?
if ((status != 0)); then
  echo "check-scripts: godot --import exited $status; nothing was verified" >&2
  tail -n 20 <<<"$out" >&2
  exit "$status"
fi
# Step 2: the actual compile. The script's own exit code is the verdict; its stderr carries the
# parse/compile errors, which are the useful part of the message, so they are shown either way.
status=0
out=$("$GODOT_BIN" --headless --path . -s res://tools/check_scripts.gd 2>&1) || status=$?
if ((status != 0)); then
  grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|^\s+at:' <<<"$out" || true
  grep -E '^check_scripts:' <<<"$out" >&2 || true
  echo "check-scripts: compile check exited $status" >&2
  exit "$status"
fi
# A run that parsed nothing is not a pass; check_scripts.gd exits 6 in that case, but the count
# is echoed here too so "scripts ok" is always backed by a number a reader can check.
summary=$(grep -E '^check_scripts: [0-9]+ scripts parsed' <<<"$out" || true)
if [[ -z "$summary" ]]; then
  echo "check-scripts: the compile check printed no summary; refusing to report success." >&2
  tail -n 20 <<<"$out" >&2
  exit 6
fi
echo "scripts ok - $summary"
