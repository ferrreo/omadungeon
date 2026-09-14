#!/usr/bin/env bash
# Screenshots the VM's own framebuffer through the QEMU monitor, without any
# VNC client and without touching the host session. This is how the install is
# watched: it works before the guest has networking, sshd or a desktop.
#   tools/vm/console-shot.sh [name]    -> tests/out/vm/console-<name>.png
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

need socat
need magick
name="${1:-$(date +%H%M%S)}"
mkdir -p "$VM_OUT"
ppm="$(mktemp --suffix=.ppm)"
trap 'rm -f "$ppm"' EXIT
vm_monitor "screendump $ppm" >/dev/null
# The monitor returns before the file is fully written on a large framebuffer.
for _ in $(seq 20); do
	[[ -s $ppm ]] && break
	sleep 0.2
done
[[ -s $ppm ]] || die "screendump produced nothing (is the VM up?)"
out="$VM_OUT/console-$name.png"
magick "$ppm" "$out"
say "$out"
