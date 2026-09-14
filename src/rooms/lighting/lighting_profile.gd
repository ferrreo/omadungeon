## Tuning for the dynamic lighting layer (docs 10, "Lighting"): the dark a floor sits in, the
## wall lanterns hung on the generator's anchors, the occluders the walls and props cast shadows
## with, and the table of light emitters gameplay attaches to swings, shots, spells and fixtures.
## `DungeonLight` (`data/rooms/dungeon_light.tres`) keeps owning the door torches and the
## surround; this resource owns everything the lighting round added on top.
##
## **Every lit pixel has a source you can point at.** That is the owner's rule and it is the one
## this file is arranged around: there is no ambient level here, no per-theme exposure, no lift
## over a cleared room and nothing the music may turn up to brighten a room from nowhere. What
## is left is `unlit_floor` - a dark so near black it exists only to stop 8-bit crush - and the
## lights. A torch, a lantern, the player's own pool and every emitter burn at
## `1 - unlit_floor`, which is exactly the dark undone: at a pool's centre a surface comes back
## to the level the theme authored it at, and one step outside the pool it is gone.
##
## Every number here is a *scalar on the theme*: no colour is authored in this file. A light's
## colour is a palette role (`LightEmitter.role`) resolved through the live `ThemePalette` and
## the music mood, so a theme swap mid-run retints every light from the same source the tiles
## use. A missing file is not an error: `resolve()` hands back a fresh resource with the same
## defaults, so a test that never touches `data/` lights its floor the same way.
class_name LightingProfile
extends Resource

## Quality levels the settings row cycles (`lighting_quality`). OFF is the look before this
## layer existed: no dark, no lanterns, no occluders, no emitters. LOW is everything but
## shadows; HIGH casts them.
enum Quality { OFF, LOW, HIGH }

const PATH := "res://data/rooms/lighting.tres"

const SETTING_QUALITY := "lighting_quality"
const SETTING_SHADOWS := "lighting_shadows"

## Lantern sprite kinds a biome may hang (`lantern_kind_for`), by tile atlas column on row 4.
const LANTERN_KINDS: Dictionary = {
	&"torch": FloorBuilder.SPECIAL_TORCH_A,
	&"lantern": FloorBuilder.SPECIAL_LANTERN,
	&"brazier": FloorBuilder.SPECIAL_BRAZIER,
	&"candle": FloorBuilder.SPECIAL_CANDLE,
	&"crystal": FloorBuilder.SPECIAL_CRYSTAL,
}

@export_group("The dark")
## What a surface keeps of itself where no light reaches it, on every theme.
##
## This is not an ambient level and it is not a lever. There used to be one - 0.32 on a dark
## theme, 0.92 on a light one, and the music moved it - and the owner's ruling deleted the idea
## rather than the number: "TORCHES SHOULD CAST THE LIGHT, THERE SHOULD BE NO OTHER LIGHT OTHER
## THAN PARTICLE EFFECTS, TORCHES ETC". A floor that is 32% lit with nothing lighting it is a
## room lit from nowhere, and no amount of pool on top of it makes the pool the thing you see.
##
## What is left is the smallest number that is still not black. The mix happens on sRGB values,
## so a dark theme's floor (about 0.28 per channel) draws at 0.017 - four of the 255 code points
## a channel has, and about 0.0012 in linear luminance, roughly a sixtieth of the same floor lit.
## A player reads unlit ground as shape and not as surface, which is the point; at 0.0 the frame
## would band to flat #000000 across the whole room and the dungeon's geometry would disappear
## into it, along with any chance of seeing a doorway you have not lit yet.
##
## Bodies do **not** get a gentler dark than the floor they stand on. They had one for a round
## (`prop_exposure_power`, which left a crate at 0.85 over a floor at 0.32), and at a floor this
## dark the same exponent would have put every prop, chest and enemy in the dungeon at 0.65 of
## itself with nothing lighting them - the ambient wash back again, wearing a prop's clothes.
## One dark, one pool, one rule (`LightRig.LIT_MASK`).
@export_range(0.0, 0.25) var unlit_floor: float = 0.06
## How far a room nobody has entered is mixed toward black on top of that (sRGB), floor, walls
## and bodies alike. It only ever *darkens*, so it cannot light anything; it is the tell that
## says "you have not been in there", and with the room's own lanterns already burning inside it
## it is read on those rather than on the floor.
@export_range(0.0, 0.6) var unexplored_shade: float = 0.12
## Seconds the shade takes to leave a room the player walks into.
@export var shade_fade_seconds: float = 0.6

@export_group("Lanterns")
## Energy of one wall lantern's pool: the dark *undone*, never more.
##
## `unlit_floor + lantern_energy = 1`, and `lighting_rig_test` pins the sum. At the centre of a
## pool the floor comes back to the level the theme authored it at and no further, so no surface
## is ever pushed past the exposure the readability ladders were measured at, and a pool is a
## pocket rather than a haze - outside it there is nothing to come back from.
##
## One light, not two. A lantern carried a second, weaker light for bodies while bodies stood
## under a gentler dark than the floor; they no longer do (see `unlit_floor`), so one pool on
## `LightRig.LIT_MASK` lights the floor and the crate standing on it by the same amount.
@export var lantern_energy: float = 0.94
## Radius as a multiple of the 96 px light texture, before the music mood scales it
## (`DungeonLight.torch_radius_scale`). Read it together with `DungeonLight.FALLOFF_POWER`:
## the nominal radius is about seven tiles, but a 2.5 power falloff is down to a quarter by half
## of it and to a twentieth by three quarters, so what a player sees is a pool about four tiles
## across with an edge a person can point at.
@export var lantern_texture_scale: float = 1.9
## Pixels the light sits in from the wall's open face, so it is never inside the wall's own
## occluder (a light inside a closed occluder polygon lights nothing at all).
@export var lantern_lip_px: float = 5.0
## Most lanterns one floor may light. Past it the sprite still hangs, unlit.
@export var lantern_max_lights: int = 220
## Which sprite each biome hangs. A biome not listed hangs a torch.
@export var lantern_kind_by_biome: Dictionary = {
	&"crypt": &"torch",
	&"forge": &"brazier",
	&"frost": &"lantern",
	&"library": &"candle",
	&"void": &"crystal",
}
## Palette role each lantern kind burns in, before the torch accent turn (`DungeonLight`).
## A crystal is the theme's magic, not its fire.
@export var lantern_role_by_kind: Dictionary = {
	&"torch": &"heat",
	&"lantern": &"loot",
	&"brazier": &"heat",
	&"candle": &"loot",
	&"crystal": &"magic",
}

@export_group("Carried light")
## The motes a living thing carries and the glow they give (`EntitySparks`). The owner's own fix
## for a room too dark to fight in: "the player and enemies are particles from both should
## illuminate a bit". The player's own energy and radius are the `player` row of the emitter
## table, so the light a player sees by has one definition; these are how many motes carry it and
## how far they drift around the body.
@export var player_motes: int = 16
@export var spark_spread_px: float = 5.0
## How far the light the motes throw is paled toward white against the motes' own colour
## (`EntitySparks.glow_of`). The motes stay fully tinted - they are the thing you see, and the
## four classes are told apart by them - but a saturated *light* multiplies a sprite channel for
## channel and turns it into a monochrome of its own flame. The bar the owner set is that within
## about a tile the sprite draws close to the colours the artist authored, and this is the number
## that decides whether it does.
@export_range(0.0, 1.0) var player_glow_paleness: float = 0.6
## Enemies are paled far less: their glow is a *tell* before it is a light, and a clown and a
## greybeard arriving out of the dark have to be two different colours.
@export_range(0.0, 1.0) var enemy_glow_paleness: float = 0.2
## What an enemy carries: fainter than the player, but enough that a thing coming at you out of
## the dark announces itself a moment before it arrives - you see the glow, then the enemy.
@export var enemy_spark_energy: float = 0.5
@export var enemy_spark_radius: float = 1.1
@export var enemy_motes: int = 7
## An enemy that has noticed you burns brighter, which is a tell as well as a light. An elite or
## a boss brighter again, for the same two reasons.
@export var enemy_alert_scale: float = 1.5
@export var elite_spark_scale: float = 1.7
@export var boss_spark_scale: float = 2.3
## Most motes a body may carry under reduce-motion. The light keeps `EntitySparks`'
## `REDUCED_MOTION_FLOOR` of itself whatever this does to the count: an accessibility setting may
## make the dungeon calmer, it may not make it unplayable.
@export var reduced_motion_motes: int = 4

@export_group("Shadows")
## Shadow-casting lights kept live at once: the nearest to the camera. Every other light
## still shines, without shadows. Eight is the cap the llvmpipe budget was measured against.
@export var shadow_casters: int = 8
## Shadow opacity: 1 is a hard black cut, lower lets the light through under the shadow. A
## shadow dims, it never blacks out - and with the pool the only light in the room, "never
## blacks out" costs more than it did. At 0.45 over a 0.32 ambient a shadowed tile still had the
## ambient under it; over a 0.06 dark it has nothing, and `lighting_frame` measured a shadowed
## tile at 34% of what the falloff alone predicts there against a 40% line. 0.32 is what puts it
## back over the line: a wall's shadow takes a third of the light out rather than two thirds.
@export_range(0.0, 1.0) var shadow_alpha: float = 0.32
## Softness of every cast shadow (`PointLight2D.shadow_filter_smooth`, PCF13).
@export var shadow_smooth: float = 4.0
## Whether props cast at all (0 = never): they shadow from the player's own light only, one
## short soft blob that turns with the player, never from a lantern - a lantern's pool
## shadowed by the crate beside it left the crate's floor dark under a lit crate
## (`prop_frame`). Walls shadow from every caster.
@export var prop_shadow_casters: int = 1
## Pixels a wall's occluder stands in from every face that touches walkable ground, so the
## wall's own lip is lit and the shadow starts behind it.
@export var occluder_inset_px: float = 5.0
## Half-size of the shadow blob laid under the player and every enemy, and its alpha.
@export var blob_size: Vector2 = Vector2(6.0, 2.5)
@export_range(0.0, 1.0) var blob_alpha: float = 0.3

@export_group("Emitters")
## Lights in the pool before the first fight; the pool grows past it and never shrinks.
@export var emitter_prewarm: int = 24
## Most emitter lights alight at once; a request past the cap is dropped (never queued, so a
## barrage cannot store up light for later).
@export var emitter_max: int = 64
## The emitter table: kind -> {role, energy, radius (light texture scale), fade (seconds the
## light takes to go out, 0 = lives with its host), shadow (may cast)}. `LightEmitter` reads
## it; `tests/unit/rooms/lighting_emitter_test.gd` pins every kind gameplay asks for.

##
## The energies are read against `lantern_energy`: a fixture that is *meant* to light the ground
## it stands on (a chest, an altar, the stairs, a fire, the player's own pool) burns near the
## dark-undone level, and a one-shot that is meant to be a flash of colour over a fight burns
## under it. Nothing is scaled down per theme any more - there is no bright floor left for an
## additive pool to blow out, because there is no ambient to make one.
@export var emitters: Dictionary = {
	&"swing": {"role": &"accent", "energy": 0.6, "radius": 0.6, "fade": 0.18, "shadow": false},
	&"shot": {"role": &"accent", "energy": 0.55, "radius": 0.5, "fade": 0.0, "shadow": false},
	&"enemy_shot": {"role": &"danger", "energy": 0.55, "radius": 0.5, "fade": 0.0, "shadow": false},
	&"enemy_burst":
	{"role": &"danger", "energy": 0.75, "radius": 1.0, "fade": 0.35, "shadow": false},
	&"fire": {"role": &"heat", "energy": 0.94, "radius": 0.9, "fade": 0.0, "shadow": true},
	&"frost": {"role": &"cold", "energy": 0.85, "radius": 1.2, "fade": 0.4, "shadow": false},
	&"shock": {"role": &"cold", "energy": 0.85, "radius": 0.8, "fade": 0.25, "shadow": false},
	&"arcane": {"role": &"magic", "energy": 0.8, "radius": 1.0, "fade": 0.35, "shadow": false},
	&"explosion": {"role": &"heat", "energy": 1.3, "radius": 1.8, "fade": 0.45, "shadow": true},
	&"heal": {"role": &"heal", "energy": 0.7, "radius": 0.9, "fade": 0.4, "shadow": false},
	&"danger": {"role": &"danger", "energy": 0.75, "radius": 1.0, "fade": 0.35, "shadow": false},
	&"chest": {"role": &"loot", "energy": 0.6, "radius": 0.8, "fade": 0.0, "shadow": false},
	&"altar": {"role": &"magic", "energy": 0.7, "radius": 1.0, "fade": 0.0, "shadow": false},
	&"shrine": {"role": &"heal", "energy": 0.7, "radius": 1.0, "fade": 0.0, "shadow": false},
	&"stairs": {"role": &"text_bright", "energy": 0.6, "radius": 0.9, "fade": 0.0, "shadow": false},
	&"player": {"role": &"accent", "energy": 0.94, "radius": 3.6, "fade": 0.0, "shadow": true},
}


## The project's lighting resource, or null when it has not been authored.
static func load_default() -> LightingProfile:
	if not ResourceLoader.exists(PATH):
		return null
	return load(PATH) as LightingProfile


## `profile` when given, else the shipped resource, else a fresh one with the same defaults.
static func resolve(profile: LightingProfile = null) -> LightingProfile:
	if profile != null:
		return profile
	var shipped := load_default()
	return shipped if shipped != null else LightingProfile.new()


## The quality the player chose (`lighting_quality`, default HIGH).
static func quality() -> Quality:
	var value: Variant = GameState.settings.get(SETTING_QUALITY, Quality.HIGH)
	return clampi(int(value), Quality.OFF, Quality.HIGH) as Quality


## Whether shadows are on: the quality is HIGH and the `lighting_shadows` switch is on.
static func shadows_enabled() -> bool:
	if quality() != Quality.HIGH:
		return false
	return bool(GameState.settings.get(SETTING_SHADOWS, true))


## Whether the layer does anything at all.
static func enabled() -> bool:
	return quality() != Quality.OFF


## What an unlit surface keeps of itself. One number, every theme, never a lever: the argument
## is on `unlit_floor` and the whole of it is that a dungeon is dark unless something is
## lighting it.
func unlit_level() -> float:
	return clampf(unlit_floor, 0.0, 1.0)


## The lantern sprite kind a biome hangs.
func lantern_kind_for(biome: StringName) -> StringName:
	var kind: Variant = lantern_kind_by_biome.get(biome, &"torch")
	return kind if kind is StringName and LANTERN_KINDS.has(kind) else &"torch"


## The palette role a lantern kind burns in.
func lantern_role_for(kind: StringName) -> StringName:
	var role: Variant = lantern_role_by_kind.get(kind, &"heat")
	return role if role is StringName else &"heat"


## The atlas column of a lantern kind on the special row.
static func lantern_column(kind: StringName) -> int:
	return int(LANTERN_KINDS.get(kind, FloorBuilder.SPECIAL_TORCH_A))


## One emitter's row of the table, with every field present (a kind not in the table is a
## plain accent glow that lives with its host).
func emitter_spec(kind: StringName) -> Dictionary:
	var spec: Dictionary = emitters.get(kind, {})
	return {
		"role": spec.get("role", &"accent"),
		"energy": float(spec.get("energy", 0.5)),
		"radius": float(spec.get("radius", 0.6)),
		"fade": float(spec.get("fade", 0.0)),
		"shadow": bool(spec.get("shadow", false)),
	}


## Every kind the table names.
func emitter_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in emitters.keys():
		out.append(StringName(key))
	return out
