#!/usr/bin/env bash
# Exports the Linux build. Usage: tools/export.sh [preset]   (default "Linux x86_64")
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-$(command -v godot)}"
# An explicitly empty argument is a caller bug, not a request for the default:
# "${1:-...}" would silently turn tools/export.sh "" into a full export and
# overwrite a good build. Only a wholly absent argument means "the default".
if [[ $# -gt 0 && -z "$1" ]]; then
  echo "export.sh: empty preset name; pass a preset or no argument at all" >&2
  exit 2
fi
preset="${1-Linux x86_64}"
case "$preset" in
  *lite*) out="export/linux-lite/omadungeon" ;;
  *) out="export/linux/omadungeon" ;;
esac
mkdir -p "$(dirname "$out")"
# Exporting a half-imported project ships broken assets, so a failed import aborts here too.
tools/godot-import.sh "$PWD" "$PWD/tests/out"
"$GODOT_BIN" --headless --path . --export-release "$preset" "$PWD/$out"
chmod +x "$out"
ls -lh "$out"
