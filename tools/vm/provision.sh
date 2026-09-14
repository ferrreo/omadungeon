#!/usr/bin/env bash
# One-time headless-QA setup inside the installed VM. Everything here exists
# because the machine has no human at its keyboard; none of it touches the game.
#
#   * SDDM autologin, so a reboot lands straight in the real Hyprland session
#     instead of parking on the greeter with nobody to type the password.
#   * A fixed virtual monitor mode, so screenshots have a stable size.
#   * A writable screenshot directory.
#
#   tools/vm/provision.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

say "configuring autologin for $VM_USER"
autologin_conf="# Headless QA VM: nobody is at the greeter, so log the test user straight in.
[Autologin]
User=$VM_USER
Session=hyprland
Relogin=true"
vm_ssh "cat > /tmp/99-omadungeon-autologin.conf" <<<"$autologin_conf"
vm_sudo 'mkdir -p /etc/sddm.conf.d &&
	install -m 644 /tmp/99-omadungeon-autologin.conf /etc/sddm.conf.d/99-omadungeon-autologin.conf &&
	cat /etc/sddm.conf.d/99-omadungeon-autologin.conf' 

say "pinning the virtual monitor to ${VM_WIDTH}x${VM_HEIGHT}"
vm_ssh "mkdir -p ~/.config/hypr && printf 'monitor=,%dx%d@60,0x0,1\n' $VM_WIDTH $VM_HEIGHT > ~/.config/hypr/monitors.conf"

vm_ssh "mkdir -p ~/omadungeon-shots"
say "restarting sddm to pick the autologin up"
vm_sudo "systemctl restart sddm" || true
say "waiting for the Hyprland session"
for _ in $(seq 60); do
	if vm_ssh 'ls /run/user/1000/hypr/*/.socket.sock' >/dev/null 2>&1; then
		say "session up: $(vm_desktop 'hyprctl version | head -1')"
		exit 0
	fi
	sleep 2
done
die "no Hyprland session after 120s"
