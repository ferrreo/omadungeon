#!/usr/bin/env bash
# Installs the game into the VM from the .deb this repo builds.
#
# Omarchy is Arch, so there is no dpkg to run the package through; what is
# installed is the package's own payload, unpacked with bsdtar (libarchive reads
# the ar + tar.xz a .deb is made of) exactly as dpkg would lay it out, straight
# into /. The point of the exercise is that the artefact users download is the
# artefact that runs, so nothing is rebuilt or re-exported for the VM.
#
#   tools/vm/install-game.sh [dist/omadungeon_0.1.0-1_amd64.deb]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

deb="${1:-}"
if [[ -z $deb ]]; then
	deb="$(ls -1t "$REPO_ROOT"/dist/omadungeon_*_amd64.deb 2>/dev/null | head -1 || true)"
fi
[[ -n $deb && -f $deb ]] || die "no .deb found; build one with tools/deb.sh"
say "installing $(basename "$deb") ($(du -h "$deb" | cut -f1))"

vm_ssh "rm -rf ~/omadungeon-pkg && mkdir -p ~/omadungeon-pkg"
vm_scp "$deb" "$VM_USER@127.0.0.1:omadungeon-pkg/game.deb" >/dev/null

# Split the .deb apart as the user, then unpack the payload at / as root.
vm_ssh 'set -e
cd ~/omadungeon-pkg
bsdtar -xf game.deb
ls -1 data.tar.* >/dev/null'
vm_sudo 'set -e
cd /home/'"$VM_USER"'/omadungeon-pkg
payload="$(ls data.tar.* | head -1)"
[ -n "$payload" ] || { echo "no data member in the .deb" >&2; exit 1; }
bsdtar -xpf "$payload" -C /
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true'
vm_ssh 'set -e
command -v omadungeon >/dev/null || { echo "omadungeon not on PATH after install" >&2; exit 1; }
echo "installed: $(command -v omadungeon) -> $(readlink -f "$(command -v omadungeon)")"
ls -l /usr/share/applications/omadungeon.desktop
du -h /usr/lib/omadungeon/omadungeon'

say "done"
