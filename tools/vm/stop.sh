#!/usr/bin/env bash
# Shuts the VM down: ACPI powerdown first, SIGKILL after the grace period.
#   tools/vm/stop.sh [grace-seconds]   (default 45; 0 kills immediately)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

grace="${1:-45}"
vm_running || { say "not running"; exit 0; }
pid="$(cat "$VM_PIDFILE")"

if (( grace > 0 )); then
	# A desktop session often swallows the ACPI button event, so ask the guest
	# itself first and keep the monitor powerdown as the fallback.
	vm_sudo "systemctl poweroff" >/dev/null 2>&1 || vm_monitor system_powerdown >/dev/null
	for (( i = 0; i < grace; i++ )); do
		vm_running || { say "powered down"; exit 0; }
		sleep 1
	done
	say "still up after ${grace}s, killing"
fi
kill -9 "$pid" 2>/dev/null || true
rm -f "$VM_PIDFILE" "$VM_MONITOR"
say "stopped"
