#!/usr/bin/env bash
# Blocks until the installed machine answers on ssh. Used to wait out the
# unattended install (which reboots itself when it finishes) and every reboot
# after it.
#   tools/vm/wait-ssh.sh [seconds]   default 2400
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
timeout="${1:-2400}"
say "waiting up to ${timeout}s for sshd on 127.0.0.1:$VM_SSH_PORT"
if vm_wait_ssh "$timeout"; then
	say "up: $(vm_ssh 'echo $(hostname) $(uname -r)')"
else
	die "no ssh after ${timeout}s — screenshot the console with tools/vm/console-shot.sh"
fi
