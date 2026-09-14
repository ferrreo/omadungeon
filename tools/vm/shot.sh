#!/usr/bin/env bash
# Screenshots the VM's desktop from inside the VM with grim (the guest's own
# wlroots screencopy), then copies the PNG back to tests/out/vm/.
#   tools/vm/shot.sh <name>   -> tests/out/vm/<name>.png
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
name="${1:?usage: $0 <name>}"
mkdir -p "$VM_OUT"
vm_desktop "mkdir -p ~/omadungeon-shots && grim ~/omadungeon-shots/$name.png && ls -l ~/omadungeon-shots/$name.png" >/dev/null
vm_scp "$VM_USER@127.0.0.1:omadungeon-shots/$name.png" "$VM_OUT/$name.png" >/dev/null
say "$VM_OUT/$name.png"
