#!/usr/bin/env bash
# gdlint + gdformat check on project scripts (addons excluded).
# `tools` is in the sweep as well as `src` and `tests`: tools/check_scripts.gd *is* the compile
# gate ARCHITECTURE §1 names, and it was the one .gd in the project the style gate could not see.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
mapfile -t files < <(find src tests tools -name '*.gd')
gdformat --check "${files[@]}"
gdlint "${files[@]}"
