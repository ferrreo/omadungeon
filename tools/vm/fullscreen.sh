#!/usr/bin/env bash
# Owner report 12, proved where it can only be proved: a real Hyprland session.
#
# The claim under test is that the game's Fullscreen checkbox follows a fullscreen the
# *compositor* made, which nothing in Godot's Wayland API can see (see
# src/desktop/compositor_window.gd). So the fullscreen here is made by Hyprland, with the game
# told nothing, and the evidence is two screenshots of the game's own Video page.
#
#   tools/vm/fullscreen.sh state           what Hyprland says about the game's window
#   tools/vm/fullscreen.sh bind            run the SUPER+F bind against the game
#   tools/vm/fullscreen.sh current         fail unless the installed binary is the local .deb's
#   tools/vm/fullscreen.sh prove [name]    the whole proof -> tests/out/vm/<name>_{before,after}.png
#
# Why the bind is dispatched rather than typed: Hyprland does not run keybinds for input from
# `wtype`'s virtual keyboard. Measured, not assumed - `wtype -M logo -k f -m logo` leaves
# `fullscreen: 0`, and so does SUPER+T (float/tile), while the same wtype reaches the game's own
# key handling perfectly well. So what is dispatched is the *bind's own action*, quoted from
# Omarchy's `hypr/bindings/tiling.lua`:
#
#   o.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
#
# Same dispatcher, same window, same absence of any word to the game. The one thing the game
# could have learned from and did not is a key press it never sees either way.
#
# `prove` refuses to produce evidence it does not believe in. Round after round of this issue
# was signed off on a stale build and on two screenshots that turned out to be the same file,
# so it checks the binary under test first and the two PNGs afterwards, and exits non-zero
# rather than leaving a passing-looking pair behind.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

GAME_BIN=/usr/lib/omadungeon/omadungeon
GAME_FILTER='.[] | select((.class // "") | test("omadungeon"; "i"))'
SETTLE_SECONDS="${SETTLE_SECONDS:-3}"

## One line of Hyprland's own words about the game's window.
game_window() {
	vm_desktop "hyprctl clients -j | jq -c '[$GAME_FILTER] | .[0] // empty'"
}

## Hyprland's fullscreen mode for the game's window: 0 none, 1 maximised, 2 fullscreen.
## Empty when there is no game window, which every caller treats as a failure.
game_fullscreen() {
	vm_desktop "hyprctl clients -j | jq -r '[$GAME_FILTER] | .[0].fullscreen // empty'"
}

## Blocks until Hyprland reports mode $1 for the game window, or fails after 20 s.
wait_for_mode() {
	local want="$1" i seen
	for i in $(seq 40); do
		seen="$(game_fullscreen || true)"
		[[ $seen == "$want" ]] && return 0
		sleep 0.5
	done
	die "Hyprland still reports fullscreen=$(game_fullscreen) for the game, wanted $want"
}

## Fail unless the binary installed in the guest is the one in the newest local .deb. The
## previous round's evidence for this issue was captured against a build that predated the
## fix, which is a way of proving nothing at all, slowly.
assert_current() {
	local deb guest want
	# $DEB pins the artefact when someone else may be rebuilding dist/ underneath this run -
	# the point is to know *which* build is under test, not to race the newest one.
	deb="${DEB:-$(ls -1t "$REPO_ROOT"/dist/omadungeon_*_amd64.deb 2>/dev/null | head -1 || true)}"
	[[ -n $deb && -f $deb ]] || die "no dist/omadungeon_*.deb to compare against; run tools/deb.sh full"
	need bsdtar
	say "checking the guest runs $(basename "$deb")"
	want="$(bsdtar -xOf "$deb" 'data.tar.*' | bsdtar -xOf - ".$GAME_BIN" | md5sum | cut -d' ' -f1)"
	guest="$(vm_ssh "md5sum $GAME_BIN" | cut -d' ' -f1)"
	[[ -n $want ]] || die "could not read $GAME_BIN out of $(basename "$deb")"
	[[ $want == "$guest" ]] || die \
		"the guest is running a different build ($guest) from $(basename "$deb") ($want); run tools/vm/install-game.sh"
	say "binary under test matches the package: $want"
}

## Run the SUPER+F bind against the game: the dispatcher Omarchy binds that key to, aimed at
## the focused window, which is checked first because the dispatcher takes no target. The game
## is told nothing by any of this, which is the entire point.
FULLSCREEN_DISPATCH='hl.dsp.window.fullscreen({ mode = "fullscreen" })'
press_fullscreen_bind() {
	local active
	active="$(vm_desktop 'hyprctl activewindow -j | jq -r ".class // \"\""')"
	[[ $active =~ [Oo]madungeon ]] || die "the focused window is '$active', not the game"
	vm_desktop "hyprctl dispatch '$FULLSCREEN_DISPATCH'" >/dev/null
}

cmd="${1:-state}"; shift || true

case "$cmd" in
state)
	game_window
	;;
bind)
	press_fullscreen_bind
	sleep 1
	game_window
	;;
current)
	assert_current
	;;
prove)
	name="${1:-vm_fullscreen}"
	need md5sum
	assert_current
	[[ -n "$(game_fullscreen || true)" ]] || die "no game window; start it with tools/vm/game.sh start"
	wait_for_mode 0
	say "before: $(game_window)"
	"$(dirname "${BASH_SOURCE[0]}")/shot.sh" "${name}_before" >/dev/null
	press_fullscreen_bind
	wait_for_mode 2
	# The game learns about this from a poll, not from an event: give the query and the
	# settings page the time the profile says they need before photographing the answer.
	sleep "$SETTLE_SECONDS"
	say "after:  $(game_window)"
	"$(dirname "${BASH_SOURCE[0]}")/shot.sh" "${name}_after" >/dev/null
	before="$VM_OUT/${name}_before.png"
	after="$VM_OUT/${name}_after.png"
	for f in "$before" "$after"; do
		[[ -s $f ]] || die "no screenshot at $f"
	done
	if [[ "$(md5sum <"$before" | cut -d' ' -f1)" == "$(md5sum <"$after" | cut -d' ' -f1)" ]]; then
		die "the two screenshots are byte-identical: nothing was captured twice over"
	fi
	say "$before"
	say "$after"
	;;
*)
	die "usage: $0 state|bind|current|prove [name]"
	;;
esac
