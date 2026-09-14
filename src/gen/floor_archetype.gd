## The overall plan of one floor (docs 5.1 #1): hub-and-spoke, a long winding path, a ring
## loop, a tight grid-like complex or an irregular cavern. One archetype is rolled per floor
## from the seed, weighted by the biome, the desktop theme's geometry levers and the music,
## so two floors of one run read as different places rather than as one plan re-rolled.
##
## Every knob the rest of the pipeline reads off an archetype lives here as data: how long the
## spine is, where branch rooms attach, how many loops are added on top of the theme's own
## count, how the layout steers each room away from its parent, how far apart rooms sit, what
## sizes and shapes a room prefers, and how often a corridor is widened or given a chamber.
## `FloorGraph`, `FloorLayout`, `RoomShape` and `CorridorDressing` only ever ask; nothing here
## touches a tile.
class_name FloorArchetype
extends RefCounted

const HUB := &"hub"
const WINDING := &"winding"
const RING := &"ring"
const GRID := &"grid"
const CAVERN := &"cavern"
const ALL: Array[StringName] = [HUB, WINDING, RING, GRID, CAVERN]

## Placement steering styles (`FloorLayout` reads `dir_style`).
const DIR_UNIFORM := &"uniform"
const DIR_SNAKE := &"snake"
const DIR_CURL := &"curl"
const DIR_SPOKE := &"spoke"

## Branch attachment rules (`FloorGraph` reads `branch_style`).
const BRANCH_ANY := &"any"
const BRANCH_SPINE := &"spine"
const BRANCH_HUB := &"hub"

## Degree cap of the hub room: four sides, one of them doubled.
const HUB_MAX_DEGREE := 5
## How hard the wallpaper's hue spread tilts the roll. Larger than `MUSIC_TILT` and smaller
## than `THEME_TILT`: the desktop picture is a deliberate choice the player made and a floor
## plan is where it should show, but the theme still has the loudest say in its own dungeon.
const WALLPAPER_TILT := 0.75
## How hard the theme levers tilt the archetype roll. 1.0 = a full-range lever doubles or
## halves the archetypes it speaks for; the roll is a bias, never a rule, so every archetype
## stays possible under every desktop (docs 3.3).
const THEME_TILT := 1.5
const MUSIC_TILT := 0.4
## Per-biome multipliers on the base weight 1.0: a biome has a characteristic plan without
## owning it.
const BIOME_WEIGHTS := {
	&"crypt": {WINDING: 1.4, GRID: 1.3, CAVERN: 0.8},
	&"forge": {HUB: 1.5, GRID: 1.2, RING: 1.1},
	&"frost": {CAVERN: 1.5, RING: 1.3, GRID: 0.7},
	&"library": {GRID: 1.6, HUB: 1.2, RING: 1.1, CAVERN: 0.6},
	&"void": {CAVERN: 1.6, RING: 1.3, WINDING: 1.1, GRID: 0.6},
}

## Debug hook for captures: a non-empty id here is copied into every `GenParams.build()` as
## its `archetype`, so a scenario can ask for one plan on every floor. Never set by the game.
static var forced: StringName = &""

var id: StringName = GRID
## Share of the rooms that lie on the guaranteed start -> exit spine (clamped to 3..n-2).
var spine_share: float = 0.4
var branch_style: StringName = BRANCH_ANY
## Deepest a branch may hang below the spine (`RoomVertex.branch_depth`).
var max_branch_depth: int = 3
## True when one spine room becomes a big central hub with up to `HUB_MAX_DEGREE` exits.
var has_hub: bool = false
## Added to `GenParams.extra_loops` (the theme's own count), clamped by `FloorGraph`.
var loop_delta: int = 0
## True when one loop is spent closing the spine back on the start's neighbourhood.
var closes_ring: bool = false
## Farthest apart two rooms may be for a loop corridor.
var loop_max_gap: int = 14
var dir_style: StringName = DIR_UNIFORM
## Added to the theme's room spacing (`GenParams.room_gap_extra`); negative packs rooms.
var gap_delta: int = 0
## Size-class multipliers (`FloorLayout.SIZE_CLASSES` order), 1.0 = the theme's own odds.
var size_weights: Dictionary = {}
## Chance a room is turned on its side (a wide hall becomes a tall gallery).
var transpose_chance: float = 0.3
## Shape multipliers (`RoomShape` ids), 1.0 = the base odds.
var shape_weights: Dictionary = {}
## Shares of corridors that are widened / given a mid-way chamber / a side alcove.
var wide_share: float = 0.2
var chamber_share: float = 0.2
var alcove_share: float = 0.2


## The archetype with `wanted` id (a valid id only; `by_id(&"")` is null).
static func by_id(wanted: StringName) -> FloorArchetype:
	match wanted:
		HUB:
			return _hub()
		WINDING:
			return _winding()
		RING:
			return _ring()
		GRID:
			return _grid()
		CAVERN:
			return _cavern()
		_:
			return null


## Rolls the archetype for a floor: `params.archetype` when it names one, else a weighted
## draw over `ALL` from `weights(params)`. One rng draw either way, so forcing an archetype
## in a capture spends the stream exactly as a free roll does.
static func resolve(params: GenParams, rng: RandomNumberGenerator) -> FloorArchetype:
	var roll := rng.randf()
	var wanted := by_id(params.archetype)
	if wanted != null:
		return wanted
	var w := weights(params)
	var total := 0.0
	for id: StringName in ALL:
		total += float(w[id])
	var cursor := roll * total
	for id: StringName in ALL:
		cursor -= float(w[id])
		if cursor < 0.0:
			return by_id(id)
	return by_id(ALL[ALL.size() - 1])


## Roll weights per archetype for these inputs. Biome first, then the theme: an open theme
## (positive `room_size_bias`) leans to hubs and caverns and a tight one to grids and winding
## paths; a winding theme (`corridor_wiggle` above 0.5) leans to winding paths and caverns,
## a straight one to grids and rings. Music: a fast track favours the looping plans, a loud
## one the hub. Wallpaper: a picture of many hues favours the irregular plans, a monochrome
## one the ordered plans. Every weight stays above zero.
static func weights(params: GenParams) -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in ALL:
		out[id] = 1.0
	var biome: Dictionary = BIOME_WEIGHTS.get(params.biome, {})
	for id: StringName in biome:
		out[id] = float(out[id]) * float(biome[id])
	var open := clampf(params.room_size_bias / ThemeProfile.ROOM_SIZE_BIAS_MAX, -1.0, 1.0)
	_tilt(out, [HUB, CAVERN], open * THEME_TILT)
	_tilt(out, [GRID, WINDING], -open * THEME_TILT)
	var wind := clampf((params.corridor_wiggle - 0.5) * 2.0, -1.0, 1.0)
	_tilt(out, [WINDING, CAVERN], wind * THEME_TILT)
	_tilt(out, [GRID, RING], -wind * THEME_TILT)
	if params.music_tempo > 0.0:
		var levers := MusicLevers.shared()
		var pace := clampf(
			(params.music_tempo - levers.slow_bpm) / maxf(levers.fast_bpm - levers.slow_bpm, 1.0),
			0.0,
			1.0
		)
		_tilt(out, [RING, GRID], (pace - 0.5) * 2.0 * MUSIC_TILT)
	_tilt(out, [HUB], (params.music_energy - 0.5) * 2.0 * MUSIC_TILT)
	# The wallpaper's own axis, and deliberately not the same one as `room_size_bias` above:
	# that asks how *open* the floor is, this asks how *ordered* it is. A picture holding one
	# colour builds the tidy plans, a picture holding colours all round the circle builds the
	# irregular ones. It is the largest say the wallpaper has in a floor now that it has no
	# say at all in the colours (docs/GAME_DESIGN.md, decisions log).
	_tilt(out, [CAVERN, WINDING], (params.wallpaper_variety - 0.5) * 2.0 * WALLPAPER_TILT)
	_tilt(out, [GRID, RING], -(params.wallpaper_variety - 0.5) * 2.0 * WALLPAPER_TILT)
	for id: StringName in ALL:
		out[id] = maxf(float(out[id]), 0.05)
	return out


## Multiplies the weights of `ids` by 2^amount (so -amount exactly undoes +amount).
static func _tilt(weights_out: Dictionary, ids: Array[StringName], amount: float) -> void:
	var factor := pow(2.0, amount)
	for id: StringName in ids:
		weights_out[id] = float(weights_out[id]) * factor


## Size-class multiplier for `size_class`, 1.0 when the archetype says nothing about it.
func size_weight(size_class: StringName) -> float:
	return float(size_weights.get(size_class, 1.0))


## Shape multiplier for `shape`, 1.0 when the archetype says nothing about it.
func shape_weight(shape: StringName) -> float:
	return float(shape_weights.get(shape, 1.0))


static func _hub() -> FloorArchetype:
	var a := FloorArchetype.new()
	a.id = HUB
	a.spine_share = 0.35
	a.branch_style = BRANCH_HUB
	a.max_branch_depth = 2
	a.has_hub = true
	a.loop_delta = 0
	a.dir_style = DIR_SPOKE
	a.gap_delta = 1
	a.size_weights = {&"large": 1.2, &"hall": 1.3, &"closet": 1.2}
	a.transpose_chance = 0.3
	a.shape_weights = {&"cross": 1.3, &"octagon": 1.2}
	a.wide_share = 0.35
	a.chamber_share = 0.25
	a.alcove_share = 0.2
	return a


static func _winding() -> FloorArchetype:
	var a := FloorArchetype.new()
	a.id = WINDING
	a.spine_share = 0.85
	a.branch_style = BRANCH_SPINE
	a.max_branch_depth = 1
	a.loop_delta = -1
	a.dir_style = DIR_SNAKE
	a.gap_delta = 0
	a.size_weights = {&"gallery": 3.0, &"hall": 1.5, &"closet": 1.2}
	a.transpose_chance = 0.4
	a.shape_weights = {&"l_shape": 1.6, &"rect": 1.1, &"cross": 0.6}
	a.wide_share = 0.25
	a.chamber_share = 0.3
	a.alcove_share = 0.35
	return a


static func _ring() -> FloorArchetype:
	var a := FloorArchetype.new()
	a.id = RING
	a.spine_share = 0.6
	a.branch_style = BRANCH_SPINE
	a.max_branch_depth = 1
	a.loop_delta = 1
	a.closes_ring = true
	a.loop_max_gap = 26
	a.dir_style = DIR_CURL
	a.gap_delta = 0
	a.size_weights = {&"medium": 1.3, &"closet": 1.3}
	a.transpose_chance = 0.35
	a.shape_weights = {&"octagon": 1.4, &"t_shape": 1.2}
	a.wide_share = 0.2
	a.chamber_share = 0.2
	a.alcove_share = 0.25
	return a


static func _grid() -> FloorArchetype:
	var a := FloorArchetype.new()
	a.id = GRID
	a.spine_share = 0.4
	a.branch_style = BRANCH_ANY
	a.max_branch_depth = 4
	a.loop_delta = 2
	a.loop_max_gap = 10
	a.dir_style = DIR_UNIFORM
	a.gap_delta = -2
	a.size_weights = {&"closet": 2.0, &"small": 1.5, &"large": 0.6, &"hall": 0.3}
	a.transpose_chance = 0.25
	a.shape_weights = {&"rect": 1.5, &"cross": 1.3, &"l_shape": 0.6, &"octagon": 0.4}
	a.wide_share = 0.1
	a.chamber_share = 0.1
	a.alcove_share = 0.1
	return a


static func _cavern() -> FloorArchetype:
	var a := FloorArchetype.new()
	a.id = CAVERN
	a.spine_share = 0.45
	a.branch_style = BRANCH_ANY
	a.max_branch_depth = 2
	a.loop_delta = 0
	a.loop_max_gap = 18
	a.dir_style = DIR_UNIFORM
	a.gap_delta = 2
	a.size_weights = {&"large": 1.5, &"closet": 1.5, &"medium": 0.8}
	a.transpose_chance = 0.35
	a.shape_weights = {&"octagon": 2.2, &"l_shape": 1.5, &"rect": 0.5, &"t_shape": 1.3}
	a.wide_share = 0.5
	a.chamber_share = 0.35
	a.alcove_share = 0.35
	return a
