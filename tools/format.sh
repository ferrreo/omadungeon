#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
# `tools` is in the sweep as well as `src` and `tests`, because tools/lint.sh checks it:
# without it `tools/format.sh && tools/lint.sh` could still fail on a tools/*.gd this
# script had never formatted.
mapfile -t files < <(find src tests tools -name '*.gd')
gdformat "${files[@]}"
