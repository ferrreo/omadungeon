## How far the music is allowed to move a floor (docs §10.2), as data
## (`data/music/music_levers.tres`).
##
## The owner's report was that the music "doesn't have enough of an impact", and the numbers
## bear it out: the only levers the radio had were ±15% on the enemy count and a vignette
## that pulsed on the beat. The pulse is gone (a rhythmic brightness change is a
## photosensitivity risk, and the same report asked for none), so everything the music does
## to the game now goes through the *floor* - how many enemies it holds, how keen they are,
## how many traps it hides, how much light it has, how its rooms are shaped - and every one of
## those is a number in this file. Every lever is a function of the `MusicProfile` sampled
## when the floor was generated, so the same seed and the same profile still build the same
## floor, and `FloorRestore` puts the results back on resume.
##
## Read the ranges as "energy 0 -> calm value, energy 1 -> loud value", lerped between.
class_name MusicLevers
extends Resource

const PATH := "res://data/music/music_levers.tres"

static var _cached: MusicLevers

## --- density ------------------------------------------------------------------------------
## Multiplier on enemy spawn points and the spawner's budget at energy 0 and 1.
@export var foes_calm: float = 0.7
@export var foes_loud: float = 1.3
## Multiplier on prop density at energy 0 and 1.
@export var props_calm: float = 0.7
@export var props_loud: float = 1.3
## How far a calm track raises `trap_density` (and a loud one lowers it): the shift at
## energy 0 is `+trap_push`, at energy 1 `-trap_push`.
@export var trap_push: float = 0.3
## Multiplier on the pack size of TRAP rooms - the ambush - at energy 0 and 1. A calm track
## makes the quiet rooms the dangerous ones.
@export var ambush_calm: float = 1.4
@export var ambush_loud: float = 0.6
## --- light --------------------------------------------------------------------------------
## Multiplier on the floor's ambient light at energy 0 and 1. The product is still clamped to
## the wallpaper band (`WallpaperAnalyzer.AMBIENT_MIN..MAX`) the prop readability ladder is
## guaranteed across - so with no wallpaper a loud track is full light and a calm one is
## 0.6 of it - and a light desktop theme keeps its pinned full light (docs §3.2).
##
## Every pair here straddles 1.0 at energy 0.5, which is what silence reads as: a floor built
## with the radio off is the theme's own floor, moved by nothing.
@export var light_calm: float = 0.6
@export var light_loud: float = 1.4
## --- shape --------------------------------------------------------------------------------
## Shift on `room_size_bias` (band 0..0.5) from energy: loud tracks open the rooms up.
@export var room_energy_push: float = 0.15
## Shift on `room_size_bias` from tempo: fast tracks tighten them.
@export var room_tempo_push: float = 0.1
## Share of a floor's props drawn as the track's own signature kind. The track hash picks one
## of the biome's prop kinds and this fraction of every room's props is that kind, so two
## tracks furnish the same biome differently at a glance.
@export var accent_share: float = 0.4
## --- aggression ---------------------------------------------------------------------------
## Multiplier on every regular enemy's sight range at energy 0 and 1.
@export var sight_calm: float = 0.75
@export var sight_loud: float = 1.25
## Multiplier on every regular enemy's attack cooldown at energy 0 and 1 (lower = faster).
@export var cadence_calm: float = 1.3
@export var cadence_loud: float = 0.7
## Multiplier on the gold regular enemies drop at energy 0 and 1.
@export var loot_calm: float = 0.8
@export var loot_loud: float = 1.2
## --- live ---------------------------------------------------------------------------------
## How far the *current* track's mood may push the enemies of the next room the player
## enters, applied once per enemy the moment that room wakes (`MusicManager._on_room_entered`,
## docs 10.2): the multiplier on sight range and move speed is `1 - live_push` under the
## calmest track and `1 + live_push` under the loudest; the attack cooldown is divided by the
## same number. Never mid-fight.
@export var live_push: float = 0.1
## --- words --------------------------------------------------------------------------------
## Energy below which a floor is "sparse"/"dim", and above which it is "dense"/"bright".
@export var word_low: float = 0.35
@export var word_high: float = 0.65
## Tempo (BPM) below which a floor is "slow" and at or above which it is "fast".
@export var slow_bpm: float = 100.0
@export var fast_bpm: float = 130.0


## The shipped levers, loaded once; a default-valued set when the resource is missing.
static func shared() -> MusicLevers:
	if _cached != null:
		return _cached
	if ResourceLoader.exists(PATH):
		_cached = load(PATH) as MusicLevers
	if _cached == null:
		_cached = MusicLevers.new()
	return _cached


func foes_scale(energy: float) -> float:
	return lerpf(foes_calm, foes_loud, clampf(energy, 0.0, 1.0))


func props_scale(energy: float) -> float:
	return lerpf(props_calm, props_loud, clampf(energy, 0.0, 1.0))


## Signed shift on trap density: positive for a calm track.
func trap_shift(energy: float) -> float:
	return (0.5 - clampf(energy, 0.0, 1.0)) * 2.0 * trap_push


func ambush_scale(energy: float) -> float:
	return lerpf(ambush_calm, ambush_loud, clampf(energy, 0.0, 1.0))


func light_scale(energy: float) -> float:
	return lerpf(light_calm, light_loud, clampf(energy, 0.0, 1.0))


## Signed shift on room size from both music levers: energy opens rooms, tempo tightens them.
## `tempo_normalized` is `MusicProfile.tempo_normalized()`, 0.5 when the tempo is unknown.
func room_shift(energy: float, tempo_normalized: float) -> float:
	var open := (clampf(energy, 0.0, 1.0) - 0.5) * 2.0 * room_energy_push
	var tight := (clampf(tempo_normalized, 0.0, 1.0) - 0.5) * 2.0 * room_tempo_push
	return open - tight


func sight_scale(energy: float) -> float:
	return lerpf(sight_calm, sight_loud, clampf(energy, 0.0, 1.0))


func cadence_scale(energy: float) -> float:
	return lerpf(cadence_calm, cadence_loud, clampf(energy, 0.0, 1.0))


func loot_scale(energy: float) -> float:
	return lerpf(loot_calm, loot_loud, clampf(energy, 0.0, 1.0))


## The live aggression multiplier for a track mood of `energy`: 1 - live_push .. 1 + live_push.
func live_aggression(energy: float) -> float:
	return 1.0 + (clampf(energy, 0.0, 1.0) - 0.5) * 2.0 * live_push


## Enemy-count change as a signed whole percentage, the number the summary quotes.
func foes_percent(energy: float) -> int:
	return int(round((foes_scale(energy) - 1.0) * 100.0))


## "sparse" / "steady" / "dense": the enemy density in one word.
func density_word(energy: float) -> String:
	if energy < word_low:
		return "sparse"
	if energy > word_high:
		return "dense"
	return "steady"


## "dim" / "lit" / "bright": the floor light in one word.
func light_word(energy: float) -> String:
	if energy < word_low:
		return "dim"
	if energy > word_high:
		return "bright"
	return "lit"


## "slow" / "fast", or "" for a tempo that is unknown or unremarkable.
func pace_word(tempo: float) -> String:
	if tempo <= 0.0:
		return ""
	if tempo < slow_bpm:
		return "slow"
	if tempo >= fast_bpm:
		return "fast"
	return ""


## The floor-start banner: "Built to Super Space - dense, fast and bright", or
## "Built in silence - a steady floor" when nothing was playing. Short on purpose: the HUD
## banner is centred and a long sentence reaches back over the HP plate.
func banner(title: String, energy: float, tempo: float, playing: bool) -> String:
	if not playing:
		return "Built in silence - a steady floor"
	var words: PackedStringArray = [density_word(energy)]
	var pace := pace_word(tempo)
	if not pace.is_empty():
		words.append(pace)
	words.append(light_word(energy))
	var head := "Built to %s" % _short_title(title)
	return "%s - %s" % [head, _join_words(words)]


## One run-summary line per floor: "Floor 3 - Rm -rf: dense and bright, 26% more enemies,
## fewer traps". A floor built in silence says so.
func floor_line(
	floor_number: int, title: String, energy: float, tempo: float, playing: bool
) -> String:
	if not playing:
		return "Floor %d - silence: the usual floor" % floor_number
	var words: PackedStringArray = [density_word(energy)]
	var pace := pace_word(tempo)
	if not pace.is_empty():
		words.append(pace)
	words.append(light_word(energy))
	var effects: PackedStringArray = [_foes_words(energy)]
	var traps := trap_shift(energy)
	if traps > trap_push * 0.5:
		effects.append("more traps")
	elif traps < -trap_push * 0.5:
		effects.append("fewer traps")
	return (
		"Floor %d - %s: %s, %s"
		% [floor_number, _short_title(title), _join_words(words), ", ".join(effects)]
	)


func _foes_words(energy: float) -> String:
	var percent := foes_percent(energy)
	if percent == 0:
		return "the usual number of enemies"
	if percent > 0:
		return "%d%% more enemies" % percent
	return "%d%% fewer enemies" % -percent


## "a, b and c" / "a and b" / "a".
static func _join_words(words: PackedStringArray) -> String:
	if words.size() <= 1:
		return "".join(words)
	var head: PackedStringArray = words.slice(0, words.size() - 1)
	return "%s and %s" % [", ".join(head), words[words.size() - 1]]


## A track title cut to fit a banner. 28 characters keeps the longest bundled title whole.
static func _short_title(title: String) -> String:
	if title.length() <= 28:
		return title
	return title.substr(0, 27).strip_edges() + "…"
