#!/usr/bin/env bash
# Brings a real Omarchy machine up from nothing and puts the game on it.
#
#   tools/vm/create.sh [--fresh] [path/to/omadungeon_*.deb]
#
# Steps, each of which is also runnable on its own:
#   1. cidata.sh       build the unattended-install drive (and the VM's ssh key)
#   2. boot.sh install boot the ISO; Omarchy's own autoinstaller does the rest
#                      and reboots into the installed system when it is done
#   3. wait-ssh.sh     wait for the installed machine's sshd
#   4. boot.sh run     reboot with the install media detached
#   5. provision.sh    autologin, so a real Hyprland session is running
#   6. install-game.sh unpack the .deb's payload onto the machine
#
# --fresh throws the existing disk image and UEFI variables away first, so the
# install starts from a blank machine. Without it, an existing disk is reused.
#
# Nothing here is ever shown on the host session: see boot.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
here="$(dirname "${BASH_SOURCE[0]}")"

fresh=0
deb=""
for arg in "$@"; do
	case "$arg" in
	--fresh) fresh=1 ;;
	*) deb="$arg" ;;
	esac
done

[[ -f $VM_ISO ]] || die "ISO missing: run tools/vm/fetch-iso.sh"

if vm_running; then
	say "a VM is already running; stopping it first"
	"$here/stop.sh" >/dev/null
fi

if (( fresh )); then
	say "discarding $VM_DISK and $VM_VARS"
	rm -f "$VM_DISK" "$VM_VARS"
fi

"$here/cidata.sh"
"$here/boot.sh" install
say "unattended install running — watch it with tools/vm/console-shot.sh"
"$here/wait-ssh.sh" "${VM_INSTALL_TIMEOUT:-3600}"
say "installed; rebooting with the install media detached"
"$here/stop.sh" >/dev/null
sleep 3
"$here/boot.sh" run
"$here/wait-ssh.sh" 600
"$here/provision.sh"
if [[ -n $deb ]]; then
	"$here/install-game.sh" "$deb"
else
	"$here/install-game.sh"
fi
say "ready. tools/vm/game.sh start, tools/vm/shot.sh <name>, tools/vm/verify.sh"
