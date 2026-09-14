#!/usr/bin/env bash
# Shared settings and helpers for the real-Omarchy VM tier. Sourced, never run.
#
# Everything here is loopback-only by construction: QEMU's display is a VNC
# server bound to 127.0.0.1, SSH is a user-mode NAT forward from 127.0.0.1, and
# the QEMU monitor is a unix socket. Nothing is ever shown on the host session.

set -euo pipefail

OMARCHY_VER="${OMARCHY_VER:-4.0.3}"
VM_NAME="${VM_NAME:-omadungeon-omarchy}"
VM_DIR="${VM_DIR:-$HOME/.cache/omadungeon-vm}"
VM_ISO="${VM_ISO:-$VM_DIR/omarchy-$OMARCHY_VER.iso}"
VM_DISK="${VM_DISK:-$VM_DIR/$VM_NAME.qcow2}"
VM_DISK_SIZE_GIB="${VM_DISK_SIZE_GIB:-40}"
VM_CIDATA="${VM_CIDATA:-$VM_DIR/cidata.iso}"
VM_VARS="${VM_VARS:-$VM_DIR/OVMF_VARS.fd}"
VM_MONITOR="${VM_MONITOR:-$VM_DIR/monitor.sock}"
VM_PIDFILE="${VM_PIDFILE:-$VM_DIR/qemu.pid}"
VM_LOG="${VM_LOG:-$VM_DIR/qemu.log}"

VM_MEM="${VM_MEM:-8192}"
VM_CPUS="${VM_CPUS:-4}"
# VNC display number N means TCP 5900+N, bound to loopback only.
VM_VNC_DISPLAY="${VM_VNC_DISPLAY:-99}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"
VM_WIDTH="${VM_WIDTH:-1920}"
VM_HEIGHT="${VM_HEIGHT:-1080}"

VM_USER="${VM_USER:-omadungeon}"
VM_PASSWORD="${VM_PASSWORD:-omadungeon}"
VM_HOSTNAME="${VM_HOSTNAME:-omadungeon-vm}"
VM_TIMEZONE="${VM_TIMEZONE:-UTC}"
VM_KEYMAP="${VM_KEYMAP:-us}"
VM_FULL_NAME="${VM_FULL_NAME:-Omadungeon QA}"
VM_EMAIL="${VM_EMAIL:-qa@omadungeon.local}"
VM_SSH_KEY="${VM_SSH_KEY:-$VM_DIR/id_ed25519}"

# Firmware. Debian/PikaOS ship the split 4 MB OVMF build; the single-file
# /usr/share/qemu/OVMF.fd is the fallback for distros that only have that.
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-/usr/share/OVMF/OVMF_VARS_4M.fd}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VM_OUT="${VM_OUT:-$REPO_ROOT/tests/out/vm}"

die() { echo "vm: $*" >&2; exit 1; }
say() { echo "vm: $*"; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

## True while the QEMU process recorded in the pidfile is alive.
vm_running() {
	[[ -f $VM_PIDFILE ]] || return 1
	local pid
	pid="$(cat "$VM_PIDFILE" 2>/dev/null || true)"
	[[ -n $pid ]] || return 1
	kill -0 "$pid" 2>/dev/null
}

## Send one HMP command to the running QEMU and print the reply.
vm_monitor() {
	[[ -S $VM_MONITOR ]] || die "no QEMU monitor socket at $VM_MONITOR (is the VM up?)"
	printf '%s\n' "$1" | socat - "UNIX-CONNECT:$VM_MONITOR" 2>/dev/null || true
}

## ssh into the guest over the loopback forward. Extra args are the remote command.
vm_ssh() {
	ssh -p "$VM_SSH_PORT" -i "$VM_SSH_KEY" \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR -o ConnectTimeout=10 \
		"$VM_USER@127.0.0.1" "$@"
}

## Run one command as root in the guest. The QA VM's password is ours (we set it
## in cidata.sh), so nothing here needs an interactive terminal.
vm_sudo() {
	vm_ssh "sudo -S -p '' bash -c $(printf '%q' "$*")" <<<"$VM_PASSWORD"
}

vm_scp() {
	scp -P "$VM_SSH_PORT" -i "$VM_SSH_KEY" \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR "$@"
}

## Block until sshd in the guest answers, or fail after $1 seconds (default 900).
vm_wait_ssh() {
	local deadline=$(( SECONDS + ${1:-900} ))
	while (( SECONDS < deadline )); do
		if vm_ssh true 2>/dev/null; then
			return 0
		fi
		sleep 5
	done
	return 1
}

# Shell preamble that attaches an ssh session to the desktop session already
# running on the VM's tty1 (Hyprland under uwsm). Without it hyprctl/grim have
# no idea which compositor to talk to. Prepended to every remote command that
# touches the desktop.
read -r -d '' VM_SESSION_ENV <<'PREAMBLE' || true
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="$(cd "$XDG_RUNTIME_DIR" 2>/dev/null && ls -1 wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | head -1)"
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
PREAMBLE

## Run a command inside the guest's desktop session.
vm_desktop() {
	vm_ssh "bash -lc $(printf '%q' "$VM_SESSION_ENV
$*")"
}
