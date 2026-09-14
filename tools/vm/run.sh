#!/usr/bin/env bash
# Runs one of the game's own rendered-check scenarios (src/core/test_scenarios.gd)
# inside the VM's real Hyprland session, against the machine's real Omarchy
# theme, and copies the screenshot back to tests/out/vm/.
#
# This is the same driver tools/run-scenario.sh uses under nested headless sway,
# so a capture here and a capture there are directly comparable — the difference
# between them is exactly "real Omarchy vs. theme fixture".
#
#   tools/vm/run.sh <scenario> [extra game args...]
#     scenarios: boot class_select floor combat chest pause summary theme_swap
#   -> tests/out/vm/scenario-<scenario>-<machine theme>.png  (the game's own
#        screenshot) and ...-desktop.png (the whole desktop around it). The
#        machine's current theme is in the name so two themes never collide.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
here="$(dirname "${BASH_SOURCE[0]}")"

scenario="${1:?usage: $0 <scenario> [args...]}"; shift || true
mkdir -p "$VM_OUT"
theme="$(vm_ssh 'cat ~/.local/state/omarchy/current/theme.name 2>/dev/null' | tr -d '\r')"
tag="$scenario${theme:+-$theme}"

vm_ssh "rm -rf ~/omadungeon-scenario && mkdir -p ~/omadungeon-scenario"
vm_desktop "
	pkill -x omadungeon 2>/dev/null || true
	sleep 1
	setsid --fork omadungeon --rendering-driver opengl3 \
		-- --test-scenario '$scenario' --screenshot-dir \"\$HOME/omadungeon-scenario\" $* \
		>~/omadungeon-scenario.log 2>&1 </dev/null
	echo started
"

# Capture the desktop while the scenario is still on screen, then wait it out.
deadline=$(( SECONDS + ${VM_SCENARIO_TIMEOUT:-180} ))
shot_taken=0
while (( SECONDS < deadline )); do
	if (( ! shot_taken )) && vm_ssh 'pgrep -x omadungeon >/dev/null'; then
		sleep "${VM_SCENARIO_SETTLE:-12}"
		if vm_ssh 'pgrep -x omadungeon >/dev/null'; then
			"$here/shot.sh" "scenario-$tag-desktop" >/dev/null || true
			shot_taken=1
		fi
	fi
	vm_ssh 'pgrep -x omadungeon >/dev/null' || break
	sleep 2
done

if vm_ssh "test -f ~/omadungeon-scenario/$scenario.png"; then
	vm_scp "$VM_USER@127.0.0.1:omadungeon-scenario/$scenario.png" "$VM_OUT/scenario-$tag.png" >/dev/null
	say "$VM_OUT/scenario-$tag.png"
else
	say "the scenario left no screenshot; its log:"
	vm_ssh "cat ~/omadungeon-scenario.log" || true
	exit 1
fi
if [[ -f $VM_OUT/scenario-$tag-desktop.png ]]; then
	say "$VM_OUT/scenario-$tag-desktop.png"
else
	say "(no desktop capture: the scenario finished before the settle window)"
fi
