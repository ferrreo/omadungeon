#!/usr/bin/env bash
# Downloads the Omarchy ISO into ~/.cache/omadungeon-vm and verifies its sha256.
#
# The download resumes (-C -) and lands on the final name only after the
# checksum passes, so an interrupted fetch can never be mistaken for a good ISO.
#   tools/vm/fetch-iso.sh [version]        default: $OMARCHY_VER (4.0.3)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need curl
need sha256sum
ver="${1:-$OMARCHY_VER}"
iso="$VM_DIR/omarchy-$ver.iso"
sums="$iso.sha256"
base="https://iso.omarchy.org"

mkdir -p "$VM_DIR"
say "fetching $base/omarchy-$ver.iso.sha256"
curl -fsSL -o "$sums" "$base/omarchy-$ver.iso.sha256"

if [[ -f $iso ]] && (cd "$VM_DIR" && sha256sum -c "$(basename "$sums")" >/dev/null 2>&1); then
	say "already have a verified $iso"
	exit 0
fi

say "downloading $base/omarchy-$ver.iso (about 6 GB)"
curl -fL -C - -o "$iso.part" "$base/omarchy-$ver.iso"
mv -f "$iso.part" "$iso"

say "verifying"
(cd "$VM_DIR" && sha256sum -c "$(basename "$sums")")
say "ok: $iso"
