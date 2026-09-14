#!/usr/bin/env bash
# Boots the Omarchy VM under QEMU/KVM, headless.
#
#   tools/vm/boot.sh install    first boot: attaches the Omarchy ISO and the
#                               cidata autoinstall drive, disk first in the boot
#                               order so the machine falls through to the CD
#                               while the disk is blank and boots itself once
#                               Limine is on it.
#   tools/vm/boot.sh run        normal boot of the installed system (default).
#
# The display is a VNC server on 127.0.0.1:<5900+VM_VNC_DISPLAY> and the machine
# has no access to the host's Wayland session at all: no -display gtk/sdl, no
# host socket passed in. SSH is a user-mode NAT forward, also bound to 127.0.0.1.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mode="${1:-run}"

need qemu-system-x86_64
need qemu-img
[[ -r /dev/kvm ]] || die "/dev/kvm is not readable by $(id -un); add yourself to the kvm group"
[[ -f $OVMF_CODE ]] || die "UEFI firmware not found at $OVMF_CODE (install the ovmf package)"

if vm_running; then
	die "already running (pid $(cat "$VM_PIDFILE")); stop it with tools/vm/stop.sh"
fi

mkdir -p "$VM_DIR"
[[ -f $VM_DISK ]] || {
	say "creating ${VM_DISK_SIZE_GIB}G disk $VM_DISK"
	qemu-img create -f qcow2 "$VM_DISK" "${VM_DISK_SIZE_GIB}G" >/dev/null
}
[[ -f $VM_VARS ]] || cp "$OVMF_VARS_TEMPLATE" "$VM_VARS"
rm -f "$VM_MONITOR"

args=(
	-name "$VM_NAME"
	-machine q35,accel=kvm
	-cpu host
	-smp "$VM_CPUS"
	-m "$VM_MEM"
	-rtc base=utc
	-drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
	-drive "if=pflash,format=raw,unit=1,file=$VM_VARS"
	-drive "if=none,id=hd0,file=$VM_DISK,format=qcow2,cache=writeback,discard=unmap"
	-device virtio-blk-pci,drive=hd0,bootindex=1
	-netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$VM_SSH_PORT-:22"
	-device virtio-net-pci,netdev=net0
	-device "virtio-vga,xres=$VM_WIDTH,yres=$VM_HEIGHT"
	-display none
	-vnc "127.0.0.1:$VM_VNC_DISPLAY"
	-audiodev none,id=snd0
	-device intel-hda
	-device hda-duplex,audiodev=snd0
	-device virtio-rng-pci
	-monitor "unix:$VM_MONITOR,server,nowait"
	-pidfile "$VM_PIDFILE"
	-daemonize
)

if [[ $mode == install ]]; then
	[[ -f $VM_ISO ]] || die "ISO missing: run tools/vm/fetch-iso.sh"
	[[ -f $VM_CIDATA ]] || die "autoinstall drive missing: run tools/vm/cidata.sh"
	args+=(
		-drive "if=none,id=cd0,file=$VM_ISO,format=raw,media=cdrom,readonly=on"
		-device ide-cd,drive=cd0,bus=ide.0,bootindex=2
		-drive "if=none,id=cd1,file=$VM_CIDATA,format=raw,media=cdrom,readonly=on"
		-device ide-cd,drive=cd1,bus=ide.1
	)
fi

say "starting $VM_NAME ($mode): ${VM_CPUS} vCPU, ${VM_MEM}M, VNC 127.0.0.1:$((5900 + VM_VNC_DISPLAY)), ssh 127.0.0.1:$VM_SSH_PORT"
qemu-system-x86_64 "${args[@]}" >"$VM_LOG" 2>&1 || {
	cat "$VM_LOG" >&2
	die "QEMU failed to start"
}
sleep 1
vm_running || { cat "$VM_LOG" >&2; die "QEMU exited immediately"; }
say "pid $(cat "$VM_PIDFILE"); console: tools/vm/console-shot.sh, log $VM_LOG"
