#!/usr/bin/env bash
# Drives the VM's real Omarchy theme/wallpaper, the same way a user would.
#   tools/vm/theme.sh list              installed themes
#   tools/vm/theme.sh set <name>        omarchy-theme-set <name>
#   tools/vm/theme.sh bg-next           omarchy-theme-bg-next
#   tools/vm/theme.sh state             what the state dir now says
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

case "${1:-state}" in
list)   vm_desktop 'omarchy-theme-list 2>/dev/null | tr "[:upper:]" "[:lower:]" | tr " " "-"' ;;
set)    vm_desktop "omarchy-theme-set '${2:?theme name}'"; sleep 2; vm_desktop "cat ~/.local/state/omarchy/current/theme.name" ;;
bg-next) vm_desktop "omarchy-theme-bg-next"; sleep 2; vm_desktop "readlink -f ~/.local/state/omarchy/current/background" ;;
state)
	vm_desktop 'printf "state dir : %s\n" ~/.local/state/omarchy
		printf "theme.name: %s\n" "$(cat ~/.local/state/omarchy/current/theme.name 2>/dev/null)"
		printf "theme link: %s\n" "$(readlink -f ~/.local/state/omarchy/current/theme 2>/dev/null)"
		printf "background: %s\n" "$(readlink -f ~/.local/state/omarchy/current/background 2>/dev/null)"
		printf "light mode: %s\n" "$([ -e ~/.local/state/omarchy/current/theme/light.mode ] && echo yes || echo no)"
		echo "--- colors.toml ---"
		cat ~/.local/state/omarchy/current/theme/colors.toml 2>/dev/null' ;;
*) die "usage: $0 list|set <name>|bg-next|state" ;;
esac
