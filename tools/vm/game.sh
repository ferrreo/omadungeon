#!/usr/bin/env bash
# Drives the installed game inside the VM's real Hyprland session.
#
#   tools/vm/game.sh start [game args...]  launch it (logs to ~/omadungeon.log in the VM);
#                                          extra args go after Godot's `--`, so they reach
#                                          GameState.cli_args (e.g. --starting-passive)
#   tools/vm/game.sh key <keys...>     tap keys into the game (wtype, X keysym names)
#   tools/vm/game.sh hold <key> <ms>   hold one key down for a while (walking)
#   tools/vm/game.sh status            window class/title/size/pid, or nothing
#   tools/vm/game.sh env               the game process's own environment (proof of what it reads)
#   tools/vm/game.sh log               the game's stdout/stderr from the VM
#   tools/vm/game.sh stop              kill it
#
# `start` deliberately passes no --theme-state: the game reads the VM's own
# ~/.local/state/omarchy, which is what this whole tier exists to prove.
#
# Note on pkill: the pattern is matched against the process *name* (-x), never
# the full command line. `pkill -f /usr/lib/omadungeon/omadungeon` would also
# match the ssh command carrying that string and kill the shell issuing it.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cmd="${1:-status}"; shift || true
GAME_CLASS_FILTER='.[] | select((.class // "") | test("omadungeon"; "i"))'

case "$cmd" in
start)
	# Godot only exposes arguments after a bare `--` through
	# OS.get_cmdline_user_args(), which is where GameState reads ours from.
	# Not `(( $# )) && ...`: a false (( )) is a failing command, and under
	# `set -e` that ends the script before anything is launched.
	user_args=""
	if (( $# )); then
		user_args="-- $*"
	fi
	vm_desktop "
		pkill -x omadungeon 2>/dev/null || true
		sleep 1
		rm -f ~/omadungeon.log
		setsid --fork omadungeon --rendering-driver opengl3 $user_args >~/omadungeon.log 2>&1 </dev/null
		echo launched
	"
	for _ in $(seq 60); do
		if vm_desktop "hyprctl -j clients | jq -e '[$GAME_CLASS_FILTER] | length > 0'" >/dev/null 2>&1; then
			say "game window up: $(vm_desktop "hyprctl -j clients | jq -r '$GAME_CLASS_FILTER | \"\(.class) \(.title) \(.size[0])x\(.size[1]) pid=\(.pid)\"'")"
			exit 0
		fi
		sleep 1
	done
	say "no game window after 60s; last log lines:"
	vm_ssh "tail -40 ~/omadungeon.log" || true
	exit 1
	;;
key|hold)
	# wtype drives a virtual keyboard, which reaches whichever window Hyprland
	# has focused — so check that that is the game before typing into it, rather
	# than firing keys at the desktop and calling it a pass.
	active="$(vm_desktop 'hyprctl activewindow -j | jq -r ".class // \"\""')"
	[[ $active =~ [Oo]madungeon ]] || die "the focused window is '$active', not the game"
	if [[ $cmd == hold ]]; then
		vm_desktop "wtype -P '${1:?key}' -s '${2:-500}' -p '${1}'"
	else
		for k in "$@"; do
			vm_desktop "wtype -k '$k'"
			sleep 0.4
		done
	fi
	;;
status)
	vm_desktop "hyprctl -j clients | jq -r '$GAME_CLASS_FILTER | \"\(.class) | \(.title) | \(.size[0])x\(.size[1]) | pid=\(.pid)\"'"
	;;
env)
	vm_ssh 'pid=$(pgrep -x omadungeon | head -1); [ -n "$pid" ] || { echo "not running" >&2; exit 1; }
		echo "pid $pid"; tr "\0" "\n" < /proc/$pid/environ | sort'
	;;
log)  vm_ssh "cat ~/omadungeon.log" ;;
stop) vm_desktop "pkill -x omadungeon || true; echo stopped" ;;
*)    die "usage: $0 start|key|hold|status|env|log|stop" ;;
esac
