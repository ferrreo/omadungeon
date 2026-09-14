#!/usr/bin/env bash
# ssh into the VM over the loopback forward, with the VM's own key.
#   tools/vm/ssh.sh                 interactive shell
#   tools/vm/ssh.sh <command...>    run one command
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
if (( $# == 0 )); then
	exec ssh -p "$VM_SSH_PORT" -i "$VM_SSH_KEY" \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		"$VM_USER@127.0.0.1"
fi
vm_ssh "$@"
