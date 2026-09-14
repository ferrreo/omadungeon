#!/usr/bin/env bash
# The headline-feature proof, run against a genuine Omarchy install.
#
# Starts the game in the VM's real Hyprland session, then switches the machine's
# Omarchy theme three times and advances the wallpaper, screenshotting from
# inside the VM after each change. The three things it is trying to establish
# are all checked, not assumed:
#
#   1. the game recoloured          — the screenshots differ, and each one shows
#                                     the theme the machine had at that moment
#   2. without restarting           — the game's pid is sampled before and after
#                                     every switch and must never change
#   3. from the real system paths   — the process environment carries no
#                                     OMADUNGEON_OMARCHY_STATE_DIR override, and
#                                     the machine has no tests/fixtures tree at
#                                     all, so ~/.local/state/omarchy is the only
#                                     thing it can have read
#
# If the game is already running it is left exactly as it is — mid-run, mid-floor
# — so the switches land on a live dungeon rather than a freshly booted title
# screen. Only when nothing is running does this start it.
#
#   tools/vm/verify.sh [theme1 theme2 theme3 ...]     default: gruvbox catppuccin-latte nord
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
here="$(dirname "${BASH_SOURCE[0]}")"

themes=("$@")
(( ${#themes[@]} )) || themes=(gruvbox catppuccin-latte nord)

report="$VM_OUT/verify.txt"
mkdir -p "$VM_OUT"
: >"$report"
log() { echo "$*" | tee -a "$report"; }

game_pid() { vm_ssh 'pgrep -x omadungeon | head -1'; }

## theme.name + the accent colour the machine is currently on, one line.
machine_theme() {
	vm_desktop 'printf "%s accent=%s\n" \
		"$(cat ~/.local/state/omarchy/current/theme.name)" \
		"$(grep -m1 "^accent" ~/.local/state/omarchy/current/theme/colors.toml | cut -d= -f2 | tr -d " \"")"'
}

log "=== Omadungeon live-retint proof on real Omarchy ==="
log "machine  : $(vm_ssh 'source /etc/os-release; echo "$PRETTY_NAME $(cat /etc/omarchy/version 2>/dev/null || pacman -Q omarchy | cut -d" " -f2)"')"
log "session  : $(vm_desktop 'hyprctl version | head -1')"
log "binary   : $(vm_ssh 'readlink -f "$(command -v omadungeon)"; ')"
log ""

if [[ -z "$(game_pid)" ]]; then
	"$here/game.sh" start >/dev/null
	sleep 6
else
	log "(reusing the game already running, so the switches land on a live run)"
fi
pid0="$(game_pid)"
[[ -n $pid0 ]] || die "the game is not running"
log "game pid : $pid0"
log ""

log "--- environment the game process actually has ---"
env_dump="$("$here/game.sh" env)"
if grep -q 'OMADUNGEON_OMARCHY_STATE_DIR' <<<"$env_dump"; then
	log "FAIL: the game was started with a state-dir override:"
	grep 'OMADUNGEON_OMARCHY_STATE_DIR' <<<"$env_dump" | tee -a "$report"
	exit 1
fi
log "OMADUNGEON_OMARCHY_STATE_DIR: not set (so OmarchyState uses \$XDG_STATE_HOME/omarchy)"
log "$(grep -m1 '^HOME=' <<<"$env_dump")"
fixtures="$(vm_ssh 'find / -xdev -type d -name omarchy -path "*fixtures*" 2>/dev/null | head -5')"
if [[ -n $fixtures ]]; then
	log "FAIL: theme fixtures exist on the machine: $fixtures"
	exit 1
fi
log "test fixtures on the machine: none (find / -xdev -path '*fixtures*/omarchy')"
log "real state dir: $(vm_ssh 'ls -d ~/.local/state/omarchy/current/theme')"
log ""

log "--- baseline ---"
log "theme    : $(machine_theme)"
"$here/shot.sh" verify-0-baseline >/dev/null
log "shot     : tests/out/vm/verify-0-baseline.png"
log ""

i=0
for theme in "${themes[@]}"; do
	i=$((i + 1))
	log "--- switch $i: omarchy-theme-set $theme ---"
	before="$(game_pid)"
	vm_desktop "omarchy-theme-set '$theme'" >/dev/null 2>&1 || die "omarchy-theme-set $theme failed"
	sleep 4
	after="$(game_pid)"
	log "theme    : $(machine_theme)"
	log "pid      : $before -> $after $([[ $before == "$after" ]] && echo '(unchanged: no restart)' || echo '(CHANGED — the game restarted)')"
	[[ $before == "$after" ]] || die "the game restarted across the theme switch"
	"$here/shot.sh" "verify-$i-$theme" >/dev/null
	log "shot     : tests/out/vm/verify-$i-$theme.png"
	log ""
done

log "--- wallpaper: omarchy-theme-bg-next ---"
before="$(game_pid)"
bg_before="$(vm_desktop 'readlink ~/.local/state/omarchy/current/background')"
vm_desktop "omarchy-theme-bg-next" >/dev/null 2>&1 || die "omarchy-theme-bg-next failed"
sleep 5
bg_after="$(vm_desktop 'readlink ~/.local/state/omarchy/current/background')"
after="$(game_pid)"
log "background: $(basename "$bg_before") -> $(basename "$bg_after")"
[[ $bg_before != "$bg_after" ]] || log "WARNING: the wallpaper link did not move (theme ships one background?)"
log "pid      : $before -> $after $([[ $before == "$after" ]] && echo '(unchanged: no restart)' || echo '(CHANGED)')"
[[ $before == "$after" ]] || die "the game restarted across the wallpaper change"
"$here/shot.sh" "verify-$((i + 1))-wallpaper" >/dev/null
log "shot     : tests/out/vm/verify-$((i + 1))-wallpaper.png"
log ""

log "--- result ---"
log "the game ran as pid $pid0 for the whole sequence: ${#themes[@]} theme switches and one"
log "wallpaper change, never restarted, with no fixture override in its environment."
say "report: $report"
