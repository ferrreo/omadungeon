## Inputs for one floor's generation: the desktop ThemeProfile, the wallpaper analysis and
## the MusicProfile of the track playing at generation time, plus the floor index
## (docs/GAME_DESIGN.md 3.3, 3.4, 5.1, 10.2).
## Pure data: build one, hand it to FloorGenerator together with an RNG.
##
## Generation is a pure function of (these parameters, RNG) - but *these parameters are not a
## pure function of the run seed*. `music_energy` is a relative loudness and `music_tempo` a
## live BPM estimate, both read at the instant the floor is built, so the same seed on the
## same desktop lays out differently depending on where in the track generation happened.
## That is the documented contract (docs 5.1): a seed fixes the rolls, `gen_params` fixes the
## dungeon, and `RunState.gen_params` is what makes a resumed floor come back identical. Any
## UI that offers to "replay a seed" must say the same - see `Title.seed_hint_text` and
## `RunSummary.RETRY_LABEL`.
##
## The music levers (docs 10.2) and their sizes all live in `MusicLevers`
## (`data/music/music_levers.tres`): the enemy count, the prop density, the trap density, the
## ambush size of trap rooms, the floor light, the room size, the track's signature prop, and
## the three runtime scalars `FloorPopulator` hands every regular enemy - sight, attack
## cadence and gold. Same seed and same `MusicProfile` is still the same floor.
class_name GenParams
extends RefCounted

## Rooms per floor, indexed by floor (docs 5.1 #1).
const ROOM_COUNTS: PackedInt32Array = [7, 8, 9, 10, 11, 12, 12, 13, 13]
## 0-based floor indices that end with a boss arena.
const BOSS_FLOORS: PackedInt32Array = [2, 5, 8]
const LAST_FLOOR := 8
## How far the track's tempo shifts corridor wiggle away from the theme's own value. It is an
## *offset*, not a lerp toward the tempo: a lerp drags every theme toward one shared number
## and erases the difference between them, which is how three shipped themes came to generate
## the same floor plan (docs §5.1). A tempo swing of the full range therefore moves wiggle by
## 2 * TEMPO_PUSH whatever the theme, and the gap between two themes survives it intact.
const TEMPO_PUSH := 0.2
## Scale from corridor wiggle to the extra loop edges added on top of the spanning tree. Set
## so a full tempo swing (2 * TEMPO_PUSH) is exactly one loop.
const LOOP_SCALE := 2.5
## The same scale on a boss floor, and the ceiling on what it may produce there.
##
## A boss floor used to pin `extra_loops` to 1 for every theme. Docs §5.1 asks a boss floor to
## be "linear-ish", and that is a property of the *spine*: `FloorGraph` keeps the arena out of
## every loop and caps branch depth, so a loop edge on a boss floor can only ever join two
## side rooms. Pinning the count did not buy the linearity - the graph already guarantees it -
## it only took the theme off the three floors the run is remembered for, and left
## `room_size_bias` as the single surviving geometry lever there. Three of the four dark
## fixtures derive that to within 0.01 of each other, so floors 3, 6 and 9 came out as the
## same dungeon under different paint. The theme now chooses here too, in a band half the open
## floors' width, so a climax floor is still tighter than the floor before it on every theme.
const BOSS_LOOP_SCALE := 1.25
const BOSS_MAX_LOOPS := 2
## How the two geometry levers weigh into the room spacing `FloorLayout` may leave between
## rooms. Two inputs, not one: a single scalar is what let three themes share a floor plan.
const GAP_WIGGLE_SCALE := 2.5
const GAP_OPENNESS_SCALE := 3.0
## Ceiling on that spacing, so no theme can spread a floor past the grid.
const MAX_GAP_EXTRA := 5
## Range of the per-template weight multiplier the tie-break hash produces. A template is
## never ruled out, only made more or less likely, so every floor stays possible under every
## desktop and every track.
const TEMPLATE_BIAS_MIN := 0.75
const TEMPLATE_BIAS_MAX := 1.35
## How far the wallpaper's hue spread opens the floor's rooms out, either side of the theme's
## own `room_size_bias`. An *offset*, for the same reason `TEMPO_PUSH` is one: a lerp toward a
## shared number erases the difference between two themes, and the whole point of a desktop
## lever is that two desktops build different dungeons. A picture holding one colour tightens
## the floor into cells and corridors; one holding colours all round the circle opens it into
## halls and caverns, because `FloorArchetype.weights` reads this number too.
const WALLPAPER_OPENNESS_PUSH := 0.12
## The same shape for the wallpaper's chroma against `trap_density`: a vivid desktop lays a
## more hazardous floor, a washed-out one a quieter one. Half the openness push - hazards are
## the lever a player feels in the health bar, so a desktop may colour the danger of a floor
## but never dominate the theme's own say in it.
const WALLPAPER_HAZARD_PUSH := 0.06
## Floor under `prop_density` after every lever has been applied (docs §3.3).
##
## The levers are all multiplicative or subtractive, so a greyscale theme (`ThemeProfile`
## derives prop density from saturation) playing a quiet track under a flat wallpaper could
## stack down to 0.105, and its rooms came out as empty tiled halls with a coffin in them. The
## theme still moves the number - the range above this floor is the whole of the documented
## band's top half - it just cannot take the dungeon below "somewhere worth being".
const PROP_DENSITY_MIN := 0.45

var floor_index: int = 0
var room_count: int = 7
## 0 = straight corridors, 1 = winding corridors and more loops.
var corridor_wiggle: float = 0.5
## 0 = default room sizes, negative = tighter rooms, positive = bigger, more open ones
## (`ThemeProfile.ROOM_SIZE_BIAS_MIN..MAX`). Light themes get the documented bonus; the
## theme's `openness` swings every theme either side of the default.
var room_size_bias: float = 0.0
var trap_density: float = 0.5
var prop_density: float = 0.5
var biome: StringName = &"crypt"
var is_boss_floor: bool = false
## Extra edges added on top of the spanning tree (1..3).
var extra_loops: int = 1
## Multiplier on enemy spawn counts (music energy, `MusicLevers.foes_calm..foes_loud`).
var enemy_count_scale: float = 1.0
## Multiplier on the pack size of TRAP rooms (music energy; a calm track ambushes).
var ambush_scale: float = 1.0
## Multiplier on the floor's ambient light (music energy), applied by `FloorRoot`.
var light_scale: float = 1.0
## Multipliers `FloorPopulator` gives every regular enemy on the floor (music energy).
var sight_scale: float = 1.0
var cadence_scale: float = 1.0
var loot_scale: float = 1.0
## Index into the biome's prop kinds of the track's signature prop, -1 for none (silence).
var accent_prop: int = -1
var music_energy: float = 0.5
## BPM of the track playing when the floor was generated (0 = unknown/silent).
var music_tempo: float = 0.0
## Stable hash of that track, folded into the fill-template tie-break (docs 10.2).
var track_hash: int = 0
## Hash of the wallpaper's file path, folded into the same tie-break (docs 3.4).
var wallpaper_seed: int = 0
## The wallpaper's hue spread (0..1) after `WALLPAPER_OPENNESS_PUSH` has been applied to
## `room_size_bias`; kept for `FloorArchetype.weights` and for the HUD's desktop readout.
var wallpaper_variety: float = 0.5
## Floor light level from the wallpaper's top-third luminance, inside the documented clamp.
var ambient: float = 1.0
## Stable theme hash, used as a tie-break for fill template choice.
var theme_hash: int = 0
## theme_hash combined with the wallpaper seed and the track hash: the value RoomFiller
## breaks fill-template ties with, so theme, wallpaper and track each move the choice.
var fill_bias_hash: int = 0
## Trap kind -> weight the filler rolls kinds with (`ThemeProfile.hazard_weights`). Which
## hazards a floor lays, never how many: the count is `trap_density`, the documented band.
var hazard_weights: Dictionary = {}
## Floor plan to force (`FloorArchetype` ids), or empty to roll one from the seed, the biome
## and the levers (docs 5.1 #1). Only captures set it (`FloorArchetype.forced`); saved with
## the rest so a forced floor resumes as the floor it was.
var archetype: StringName = &""


## Derives parameters for `floor_index` from the three live inputs: the desktop ThemeProfile,
## the MusicProfile of the track playing right now (null = silence) and the wallpaper analysis
## (null = no wallpaper, or the player turned wallpaper influence off).
##
## Music levers (docs 10.2): energy scales enemy count and prop density, tempo shifts corridor
## wiggle around the theme's own value, the track hash breaks fill-template ties.
##
## Wallpaper levers (docs 3.4). The wallpaper shapes the run and never colours it: edge density
## shifts prop density by at most +-0.15, hue spread opens or tightens the rooms (and through
## `room_size_bias` tilts the archetype roll), chroma shifts the hazard density, the image-path
## hash joins the fill-template tie-break, and the top-third luminance becomes the floor's
## ambient light. Which colour any of it is drawn in is the theme's answer alone.
static func build(
	profile: ThemeProfile,
	floor_index: int,
	music: MusicProfile = null,
	wallpaper: WallpaperAnalyzer.Result = null
) -> GenParams:
	var track := music if music != null else MusicProfile.silent()
	var levers := MusicLevers.shared()
	var p := GenParams.new()
	# Silence reads as energy 0.5 (`MusicProfile.silent`), which is the middle of every lever:
	# a floor built with the radio off is the theme's own floor.
	var energy := clampf(track.energy, 0.0, 1.0)
	p.floor_index = maxi(floor_index, 0)
	p.theme_hash = profile.theme_hash
	p.room_count = room_count_for(p.floor_index)
	p.corridor_wiggle = clampf(_wiggle(profile.corridor_wiggle, track), 0.0, 1.0)
	# The wallpaper's two colour statistics are generation levers and nothing else: they say
	# how the floor is *shaped*, never what colour it is (docs/GAME_DESIGN.md decisions log).
	var variety := wallpaper.hue_spread() if wallpaper != null else 0.5
	var vivid := wallpaper.colour_energy() if wallpaper != null else 0.5
	p.wallpaper_variety = variety
	p.room_size_bias = clampf(
		(
			profile.room_size_bias
			+ levers.room_shift(energy, track.tempo_normalized())
			+ (variety - 0.5) * 2.0 * WALLPAPER_OPENNESS_PUSH
		),
		ThemeProfile.ROOM_SIZE_BIAS_MIN,
		ThemeProfile.ROOM_SIZE_BIAS_MAX
	)
	p.hazard_weights = profile.hazard_weights.duplicate()
	p.archetype = FloorArchetype.forced
	p.trap_density = clampf(
		(
			profile.trap_density
			+ levers.trap_shift(energy)
			+ (vivid - 0.5) * 2.0 * WALLPAPER_HAZARD_PUSH
		),
		0.0,
		1.0
	)
	var props := profile.prop_density * levers.props_scale(energy)
	if wallpaper != null:
		props += wallpaper.prop_density_delta()
	p.prop_density = clampf(props, PROP_DENSITY_MIN, 1.0)
	p.biome = biome_for_floor(profile, p.floor_index)
	p.is_boss_floor = is_boss_floor_index(p.floor_index)
	p.extra_loops = (
		clampi(
			1 + p.dithered_int(p.corridor_wiggle * BOSS_LOOP_SCALE, &"boss_loops"),
			1,
			BOSS_MAX_LOOPS
		)
		if p.is_boss_floor
		else clampi(1 + p.dithered_int(p.corridor_wiggle * LOOP_SCALE, &"loops"), 1, 3)
	)
	p.enemy_count_scale = levers.foes_scale(energy)
	p.ambush_scale = levers.ambush_scale(energy)
	p.light_scale = levers.light_scale(energy)
	p.sight_scale = levers.sight_scale(energy)
	p.cadence_scale = levers.cadence_scale(energy)
	p.loot_scale = levers.loot_scale(energy)
	p.accent_prop = accent_prop_for(track.track_hash)
	p.music_energy = energy
	p.music_tempo = maxf(track.tempo, 0.0)
	p.track_hash = track.track_hash
	if wallpaper != null:
		p.wallpaper_seed = wallpaper.seed_hash
		p.ambient = wallpaper.ambient_level(profile.brightness >= 1.0)
	p.refresh_fill_bias()
	return p


## Convenience for callers that only know the music energy (tests, resumed runs).
static func from_profile(
	profile: ThemeProfile, floor_index: int, music_energy: float = 0.5
) -> GenParams:
	var music := MusicProfile.new()
	music.energy = clampf(music_energy, 0.0, 1.0)
	return build(profile, floor_index, music, null)


## Which of the biome's prop kinds is the track's signature: a stable pick from the track
## hash, or -1 in silence. An index rather than a kind name because the biome is not known
## until the floor is filled, and it is folded modulo the kind count there (`RoomFiller`).
static func accent_prop_for(track_hash: int) -> int:
	if track_hash == 0:
		return -1
	return absi(RunRng.hash_combine(track_hash, hash(&"accent_prop")) % 1024)


## Recomputes `fill_bias_hash` from the three hashes. Call after restoring saved fields.
## A zero hash (no wallpaper, silence) is left out, so a run with neither still breaks ties
## on the theme alone exactly as it did before those levers existed.
func refresh_fill_bias() -> void:
	fill_bias_hash = theme_hash
	if wallpaper_seed != 0:
		fill_bias_hash = RunRng.hash_combine(fill_bias_hash, wallpaper_seed)
	if track_hash != 0:
		fill_bias_hash = RunRng.hash_combine(fill_bias_hash, track_hash)


## Weight multiplier for one fill template, derived from `fill_bias_hash`. Deterministic, so
## the same desktop and track always prefer the same interiors; a different theme, wallpaper
## or track reshuffles the whole set instead of flipping one bucket in three (docs 3.4, 10.2).
func template_bias(template_id: StringName) -> float:
	var h := absi(RunRng.hash_combine(fill_bias_hash, hash(template_id)))
	var t := float(h % 1024) / 1023.0
	return lerpf(TEMPLATE_BIAS_MIN, TEMPLATE_BIAS_MAX, t)


## Roll weight of one trap kind, from `hazard_weights`; 1 for a kind the theme says nothing
## about, and never below a floor so every kind the biome allows can still turn up.
func trap_kind_weight(kind: StringName) -> float:
	return maxf(float(hazard_weights.get(kind, 1.0)), 0.1)


## Extra tiles of spacing the layout may leave between two rooms, on top of the mandatory
## minimum (`FloorLayout.MIN_GAP`). Fed by two levers rather than one - how winding the theme
## is *and* how open it lays its rooms out - and dithered, so two themes that happen to agree
## on one of them still space their rooms differently.
func room_gap_extra() -> int:
	return clampi(
		dithered_int(
			corridor_wiggle * GAP_WIGGLE_SCALE + room_size_bias * GAP_OPENNESS_SCALE, &"gap"
		),
		0,
		MAX_GAP_EXTRA
	)


## Rounds `value` to an int using the theme's own dither rather than always rounding to
## nearest. Across themes the expected result is still `value` - "more wiggle means more
## loops" holds - but two themes whose scalars differ by less than one step no longer land on
## the same integer, which is what collapsed the loop count and the room spacing onto one
## value for every dark theme (docs §5.1).
func dithered_int(value: float, key: StringName) -> int:
	var base := floori(value)
	return base + (1 if value - float(base) > _dither(key) else 0)


## Deterministic 0..1 dither for one rounding decision. Theme hash only, never the wallpaper
## or the track: a resumed floor has to round the way it rounded the first time, and
## `theme_hash` is the one identity a save records.
func _dither(key: StringName) -> float:
	return float(absi(RunRng.hash_combine(theme_hash, hash(key)) % 1024)) / 1024.0


## Corridor wiggle after the tempo lever. A silent or un-analysed track (tempo 0) leaves the
## theme's value alone; a real BPM shifts it by up to TEMPO_PUSH either way around the theme's
## own value, so fast tracks wind the corridors and add loops without flattening the themes
## into each other.
static func _wiggle(theme_wiggle: float, music: MusicProfile) -> float:
	if music.tempo <= 0.0:
		return theme_wiggle
	return theme_wiggle + (music.tempo_normalized() - 0.5) * 2.0 * TEMPO_PUSH


static func room_count_for(floor_index: int) -> int:
	var i := clampi(floor_index, 0, ROOM_COUNTS.size() - 1)
	return ROOM_COUNTS[i]


static func is_boss_floor_index(floor_index: int) -> bool:
	return floor_index in BOSS_FLOORS


## Floors 0-2 crypt, 3-5 the profile's middle biome (forge/frost/library), 6+ void.
static func biome_for_floor(profile: ThemeProfile, floor_index: int) -> StringName:
	if floor_index <= 2:
		return &"crypt"
	if floor_index <= 5:
		return profile.biome_middle_id()
	return &"void"
