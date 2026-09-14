## Generation biases derived from a ThemePalette. See docs/GAME_DESIGN.md §3.3.
## Values are clamped so any theme stays fun.
class_name ThemeProfile
extends RefCounted

enum BiomeOrder { WARM, COLD, NEUTRAL }

## Trap density a theme-neutral run uses, and the swing a theme may add on top of it.
## Docs §3.3: "theme never changes difficulty beyond ±10% trap density", so a fully muted
## theme lands on 0.55 and a fully vivid one on 0.45 — the flavour stays, the ceiling holds.
const TRAP_DENSITY_MID := 0.5
const TRAP_DENSITY_SWING := 0.05

## Room-size levers. Docs §3.3 gives a light theme the open floor plan; on top of that the
## dominant hue and the warm/cool balance decide how open any theme's rooms are. Those two
## statistics are deliberately *not* saturation: saturation already drives corridor wiggle and
## both densities, and three of the shipped dark themes agree on it to within 0.09, so every
## geometry lever hung off that one scalar renders them the same dungeon - which is exactly
## what docs §5.1 forbids.
## The bias is signed. It used to run 0..0.5 with every theme on the "bigger" side of the
## generator's default, so the tightest desktop still got the default dungeon and the
## difference between themes was how much *larger* than default the others were: about 14
## tiles of mean room area between the light and the dark fixtures against a per-floor
## standard deviation of 19, which docs §3.3 honestly called "below perception". A warm,
## tight theme now pulls rooms *smaller* than default and a cool, open one pushes them larger,
## so the swing is centred instead of one-sided; brightness is the bigger of the two levers
## because it is the one a player already knows their desktop has.
const ROOM_SIZE_LIGHT_BONUS := 0.35
const ROOM_SIZE_OPENNESS_SWING := 0.22
const ROOM_SIZE_BIAS_MIN := -0.25
const ROOM_SIZE_BIAS_MAX := 0.5
## How `openness` splits between the two statistics it is made of.
const OPENNESS_HUE_WEIGHT := 0.55

## Corridor wiggle is built from *two* statistics for the same reason every other geometry
## lever is: mean accent saturation puts catppuccin and nord within 0.005 of each other, so a
## wiggle derived from it alone cannot tell them apart - and docs §3.3 forbids exactly that.
## The second input is `env_chroma`, how much colour the theme paints its own surfaces in,
## which is independent of the accents by construction: gruvbox authors vivid accents over a
## pure grey background (0.06) while nord authors calmer ones over a blue-grey one (0.28).
## The gains are set so the shipped fixtures use the whole band: a vivid theme over coloured
## backgrounds (tokyo-night) winds every corridor and loops the floor three times, a muted
## theme over grey (white) lays straight halls and one loop.
const WIGGLE_MID := 0.5
const WIGGLE_SAT_MID := 0.42
const WIGGLE_SAT_GAIN := 2.2
const WIGGLE_ENV_MID := 0.20
const WIGGLE_ENV_GAIN := 1.6
## Clamp on the result: corridors are never a ruler line and never a maze.
const WIGGLE_MIN := 0.10
const WIGGLE_MAX := 0.90

## How much the favoured faction outweighs the other two (docs §7). At 1.5 a warm desktop
## met clowns in 43% of its packs against 33% on a neutral one, a difference nobody read;
## at 2.0 it is half of every pack, and every floor still mixes all three.
const FACTION_FAVOURED := 2.0
## How far warmth tilts the *kind* of hazard a floor lays (never how many - trap density is
## the documented difficulty band and this does not touch it). A fully warm theme rolls fire
## vents and spikes at `1 + HAZARD_TILT` against 1 for the rest; a fully cold one ice and pits;
## a neutral one plates, arrows and lasers. Every kind the biome allows can still turn up.
const HAZARD_TILT := 1.5
const HAZARD_WARM_KINDS: Array[StringName] = [&"fire_vent", &"spike_floor"]
const HAZARD_COLD_KINDS: Array[StringName] = [&"ice_slide", &"pit"]
const HAZARD_NEUTRAL_KINDS: Array[StringName] = [&"pressure_plate", &"arrow_wall", &"laser_grid"]

var theme_hash: int = 0
var hue_dominant: float = 0.0
var saturation: float = 0.5
## Mean saturation of the theme's own five environment surfaces: how much colour the desktop
## paints its *backgrounds* in, as opposed to its accents. Drives corridor wiggle alongside
## `saturation`, and is the statistic `ThemePalette.apply_room_cast` reads to decide whether
## the dungeon needs the theme's colour handed to it (docs §3.2, §3.3).
var env_chroma: float = 0.0
var warmth: float = 0.0
var brightness: float = 0.0
## 0 = tight, blocky floors; 1 = open, sprawling ones. Hue position and warmth only.
var openness: float = 0.5
var corridor_wiggle: float = 0.5
var room_size_bias: float = 0.0
var trap_density: float = 0.5
var prop_density: float = 0.5
var biome_order: BiomeOrder = BiomeOrder.NEUTRAL
var faction_weights: Dictionary = {"clowns": 1.0, "greybeards": 1.0, "tinkerers": 1.0}
## Trap kind -> weight multiplier, from `warmth` (see `HAZARD_TILT`). Kinds absent roll at 1.
var hazard_weights: Dictionary = {}


static func from_palette(p: ThemePalette) -> ThemeProfile:
	var t := ThemeProfile.new()
	t.theme_hash = hash(p.name)
	var chroma_keys: PackedStringArray = ["red", "yellow", "green", "cyan", "blue", "magenta"]
	var sx := 0.0
	var sy := 0.0
	var sat_sum := 0.0
	var count := 0
	var warm := 0.0
	var cold := 0.0
	for key: String in chroma_keys:
		if not p.source.has(key):
			continue
		var c: Color = p.source[key]
		var angle := c.h * TAU
		sx += cos(angle) * c.s
		sy += sin(angle) * c.s
		sat_sum += c.s
		count += 1
	if count > 0:
		t.hue_dominant = fmod(rad_to_deg(atan2(sy, sx)) + 360.0, 360.0)
		t.saturation = clampf(sat_sum / count, 0.0, 1.0)
	for key: String in ["red", "orange", "yellow"]:
		if p.source.has(key):
			warm += (p.source[key] as Color).s
	for key: String in ["blue", "cyan"]:
		if p.source.has(key):
			cold += (p.source[key] as Color).s
	if warm + cold > 0.0:
		t.warmth = clampf((warm / 3.0 - cold / 2.0) * 2.0, -1.0, 1.0)
	t.brightness = 1.0 if p.is_light else 0.0
	t.env_chroma = p.environment_saturation()
	t.corridor_wiggle = wiggle_of(t.saturation, t.env_chroma)
	t.openness = openness_of(t.hue_dominant, t.warmth)
	t.room_size_bias = room_size_bias_of(t.brightness, t.openness)
	t.trap_density = clampf(
		TRAP_DENSITY_MID + (1.0 - t.saturation - 0.5) * 2.0 * TRAP_DENSITY_SWING,
		TRAP_DENSITY_MID - TRAP_DENSITY_SWING,
		TRAP_DENSITY_MID + TRAP_DENSITY_SWING
	)
	t.prop_density = clampf(0.3 + t.saturation * 0.5, 0.3, 0.8)
	if t.warmth > 0.2:
		t.biome_order = BiomeOrder.WARM
	elif t.warmth < -0.2:
		t.biome_order = BiomeOrder.COLD
	else:
		t.biome_order = BiomeOrder.NEUTRAL
	t.faction_weights = _faction_weights(t.hue_dominant)
	t.hazard_weights = hazard_weights_of(t.warmth)
	return t


## The room-size bias for a theme, `ROOM_SIZE_BIAS_MIN..ROOM_SIZE_BIAS_MAX`: light themes get
## the documented bonus, and `openness` swings every theme either side of the generator's
## default sizes.
static func room_size_bias_of(brightness: float, openness: float) -> float:
	return clampf(
		ROOM_SIZE_LIGHT_BONUS * brightness + (openness - 0.5) * 2.0 * ROOM_SIZE_OPENNESS_SWING,
		ROOM_SIZE_BIAS_MIN,
		ROOM_SIZE_BIAS_MAX
	)


## Per-kind trap weights for a theme of `warmth` (-1..1). Continuous, so a theme between two
## temperaments gets a mix rather than a bucket.
static func hazard_weights_of(warmth: float) -> Dictionary:
	var warm := clampf(warmth, 0.0, 1.0)
	var cold := clampf(-warmth, 0.0, 1.0)
	var neutral := 1.0 - clampf(absf(warmth), 0.0, 1.0)
	var out: Dictionary = {}
	for kind: StringName in HAZARD_WARM_KINDS:
		out[kind] = 1.0 + HAZARD_TILT * warm
	for kind: StringName in HAZARD_COLD_KINDS:
		out[kind] = 1.0 + HAZARD_TILT * cold
	for kind: StringName in HAZARD_NEUTRAL_KINDS:
		out[kind] = 1.0 + HAZARD_TILT * neutral
	return out


## How winding a theme lays its corridors, 0..1: vivid accents wind them, and so does a
## desktop that paints its own surfaces in a colour. Two inputs rather than one, because the
## shipped themes agree on the first often enough for it to be no lever at all.
static func wiggle_of(saturation_mean: float, env_chroma_mean: float) -> float:
	return clampf(
		(
			WIGGLE_MID
			+ (saturation_mean - WIGGLE_SAT_MID) * WIGGLE_SAT_GAIN
			+ (env_chroma_mean - WIGGLE_ENV_MID) * WIGGLE_ENV_GAIN
		),
		WIGGLE_MIN,
		WIGGLE_MAX
	)


## How open a theme lays its floors out, 0..1. Cool hues open the plan up, warm hues tighten
## it; the hue term is a cosine so it stays continuous across the 0/360 seam. Independent of
## saturation by construction - see ROOM_SIZE_OPENNESS_SWING.
static func openness_of(hue: float, warmth: float) -> float:
	var hue_term := 0.5 - 0.5 * cos(deg_to_rad(hue))
	var warmth_term := 0.5 - warmth * 0.5
	return clampf(
		OPENNESS_HUE_WEIGHT * hue_term + (1.0 - OPENNESS_HUE_WEIGHT) * warmth_term, 0.0, 1.0
	)


## Warm hues favour clowns, cool hues favour greybeards, green/purple tinkerers.
static func _faction_weights(hue: float) -> Dictionary:
	var w := {"clowns": 1.0, "greybeards": 1.0, "tinkerers": 1.0}
	if hue < 60.0 or hue >= 330.0:
		w["clowns"] = FACTION_FAVOURED
	elif hue < 180.0:
		w["tinkerers"] = FACTION_FAVOURED
	elif hue < 270.0:
		w["greybeards"] = FACTION_FAVOURED
	else:
		w["tinkerers"] = 1.0 + (FACTION_FAVOURED - 1.0) * 0.6
		w["clowns"] = 1.0 + (FACTION_FAVOURED - 1.0) * 0.4
	return w


func biome_middle_id() -> StringName:
	match biome_order:
		BiomeOrder.WARM:
			return &"forge"
		BiomeOrder.COLD:
			return &"frost"
		_:
			return &"library"
