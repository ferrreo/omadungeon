## Authoring ramp for environment tiles and the mapping from ramp indices to live theme
## colours (docs §10). The art agent paints tiles with exactly these eight colours; the
## palette-swap shader replaces each by the colour returned from `target_colors()`.
class_name TileRamp
extends RefCounted

## Palette variants rolled per room (docs §10): base, accent-shift, warm/cool push, inverted.
enum Variant { BASE, ACCENT_SHIFT, WARM_COOL, INVERTED }

## Ramp indices holding the room's four environment surfaces: wall, floor, floor detail, cap.
const ENVIRONMENT_RUNGS: Array[int] = [2, 3, 4, 5]
## How far the "inverted lighting" variant re-exposes a room, as a contrast ratio against the
## floor the rest of the level is drawn at. Bounded on purpose: two rooms of one dungeon seen
## through an open doorway are two rooms, and 1.35 is a room that is noticeably brighter rather
## than a room that looks like the renderer failed.
const INVERTED_LIFT := 1.35

const RAMP_SIZE := 8
## Index 0 transparent (unused), 1 outline, 2 dark, 3 mid, 4 light, 5 highlight,
## 6 accent A, 7 accent B.
const RAMP: Array[Color] = [
	Color(0.0, 0.0, 0.0, 0.0),
	Color("#101010"),
	Color("#303030"),
	Color("#505050"),
	Color("#707070"),
	Color("#909090"),
	Color("#b00000"),
	Color("#0000b0"),
]
## Minimum contrast each rung keeps against the floor rung (index 3) once a variant has pushed
## it around. These are the lighting model's own structural minimums restated per ramp index:
## 1 is the outline, which is the surround on a dark theme; 2 the wall face; 4 floor detail;
## 5 the wall cap. Index 0 is transparent and 3 is the floor itself, so neither moves; 6 and 7
## are accents, guarded separately at 2.0.
const RUNG_FLOOR_RATIOS: PackedFloat32Array = [1.0, 1.35, 1.40, 1.0, 1.12, 1.50, 2.0, 2.0]
## Contrast an accent rung keeps against the floor rung it is drawn on.
const ACCENT_FLOOR_RATIO := 2.0
## HSV saturation below which a pool colour has no hue to make an accent out of. A theme's
## `background` and `muted` keys sit here on most themes, and a biome that narrows its pool to
## them (crypt, void - docs §10) would otherwise paint every prop and torch flame in a grey.
const ACCENT_MIN_HUE := 0.12
## How far round the hue circle (in turns, so 0.07 is 25 degrees) an accent has to sit from the
## room's own floor, wall and wall cap before it counts as an accent at all.
##
## Saturation alone does not make a second colour. Every dark theme in the fixture set authors
## `background`, `dark_background` and `muted` at one hue - tokyo-night puts all three inside
## two degrees of each other - so a biome whose pool is those keys clears `ACCENT_MIN_HUE`
## while being, to the eye, the wall again: a lavender room with lavender pots in it. A pool
## colour that fails this is dropped, which is what lets `ACCENT_FALLBACK_ROLES` top the pool
## up with the theme's own fire, blood and gold instead.
const ACCENT_MIN_HUE_DISTANCE := 0.06
## Saturation an environment role needs before it *has* a hue to collide with. gruvbox's wall
## cap is a brown-grey at 0.18 and its floor a pure grey: a saturated orange next to either
## reads as orange, not as more wall, so a near-neutral surface claims no part of the circle.
## Without this the check throws away the warm half of a warm-neutral theme's palette.
const ENV_HUE_SATURATION := 0.25
## Roles an accent has to stand apart from: everything the room itself is painted in.
const ENVIRONMENT_ROLES: Array[StringName] = [&"floor", &"wall", &"wall_top"]
## Saturation an accent rung is lifted to. Accents are the only saturated colour in the
## dungeon: a crypt torch and a cracked urn are what carry the theme's palette into the level,
## and a rung re-exposed for contrast without this loses most of its chroma on the way. It sits
## well above `ThemePalette.ROOM_CAST_SATURATION` on purpose: now that the room itself carries
## real colour, an accent at the room's own chroma is one more shade of wall.
const ACCENT_SATURATION := 0.62
## How strongly an accent roll favours the pool's most saturated colours: the weight of a pool
## entry is `1 + ACCENT_CHROMA_BIAS * saturation`, so at 3.0 a fully saturated accent is rolled
## four times as often as a grey one. Every entry can still come up - a theme whose brightest
## colour is its only colour would otherwise paint every urn the same - but the props reach for
## the theme's brightest chroma first, which is what makes catppuccin's pink and gruvbox's
## orange the thing you notice on the floor.
const ACCENT_CHROMA_BIAS := 3.0
## Smallest usable accent pool. Below it the theme's own tell colours are added, so a biome
## whose keys are all greys still gets accents rather than two more shades of wall.
const ACCENT_POOL_MIN := 2
## Chroma - the spread between an accent's brightest and dimmest channel - that a rung has to
## keep once the contrast guard has finished with it. Saturation alone is not enough: a
## near-black navy is 35% saturated and still renders as black, and a bright floor (the
## "inverted lighting" variant) lets an accent clear its contrast target while being exactly
## that. Chroma is restored at the rung's own luminance, so the contrast is untouched.
const ACCENT_MIN_CHROMA := 0.14
## Theme roles topped into an accent pool that cannot fill itself, in the order they are
## tried: the fire, blood and gold a dungeon is lit and looted by first (docs §3.2).
const ACCENT_FALLBACK_ROLES: Array[StringName] = [
	&"heat", &"danger", &"loot", &"magic", &"cold", &"heal", &"earth", &"accent"
]

## Ramp indices a flame is drawn in: the body (accent A) and the hot core (accent B).
const FLAME_A := 6
const FLAME_B := 7
## Contrast a flame keeps against the floor it lights.
const FLAME_FLOOR_RATIO := 3.0
## Chroma a flame rung keeps, above the `ACCENT_MIN_CHROMA` every other accent is held to. A
## torch is the one thing in a dark room the player should read as *hot*, and re-exposing a
## theme's `heat` up to 3:1 over a near-black floor is what washes it toward cream on the way.
## Restored at the rung's own luminance, so the contrast above is untouched.
const FLAME_MIN_CHROMA := 0.32

const SHADER: Shader = preload("res://src/desktop/palette_swap.gdshader")
const RETINT_SECONDS := 0.6
## Metadata key holding the crossfade tween currently driving a material's `blend`.
const RETINT_META := &"tile_ramp_retint"


## Rolls a palette variant with the docs §10 weights (60/20/15/5). Deterministic per rng.
static func roll_variant(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.60:
		return Variant.BASE
	if r < 0.80:
		return Variant.ACCENT_SHIFT
	if r < 0.95:
		return Variant.WARM_COOL
	return Variant.INVERTED


## Maps the ramp to theme colours for one room. `room_rng_seed` makes accent picks stable
## for a given room: the same (variant, seed) always yields the same colours for a palette.
static func target_colors(palette: ThemePalette, variant: int, room_rng_seed: int) -> Array[Color]:
	var out: Array[Color] = []
	out.resize(RAMP_SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = RunRng.hash_combine(room_rng_seed, variant + 1)
	var pool := _prop_pool(palette)
	var accent_a: Color = pool[pick_accent(pool, rng)]
	var accent_b: Color = pool[pick_accent(pool, rng)]
	if pool.size() > 1 and accent_b.is_equal_approx(accent_a):
		accent_b = pool[(pool.find(accent_a) + 1) % pool.size()]
	out[0] = Color(0.0, 0.0, 0.0, 0.0)
	# Index 1 is the outline, not the surround: on a light theme `void` has to stay a mid tone
	# for the HUD plate, so the ink comes from the palette's outline instead.
	out[1] = palette.outline_color()
	out[2] = palette.get_color(&"wall")
	out[3] = palette.get_color(&"floor")
	out[4] = palette.get_color(&"floor_alt")
	out[5] = palette.get_color(&"wall_top")
	out[6] = accent_a
	out[7] = accent_b
	match variant:
		Variant.ACCENT_SHIFT:
			# Accents pick other pool colours than the base roll would have.
			var shift := 1 + rng.randi_range(0, maxi(pool.size() - 2, 0))
			out[6] = pool[(pool.find(accent_a) + shift) % pool.size()]
			out[7] = pool[(pool.find(accent_b) + shift) % pool.size()]
		Variant.WARM_COOL:
			var warm := rng.randf() < 0.5
			var toward := palette.get_color(&"heat") if warm else palette.get_color(&"cold")
			out[3] = temper(out[3], toward, 0.12)
			out[4] = temper(out[4], toward, 0.16)
			out[2] = temper(out[2], toward, 0.08)
			out[5] = temper(out[5], toward, 0.1)
		Variant.INVERTED:
			# One room lit differently, not one room made of a different material. Every
			# environment rung is re-exposed by the same ratio, so the floor/wall/cap
			# relationships inside the room are bit for bit the ones the lighting model gave
			# it and only the room's own exposure moves.
			#
			# It used to lerp the floor 35% and the wall cap 60% of the way to `text_bright`,
			# on top of a palette that had *already* been through `light_environment`. On nord
			# that put a near-white room across an open doorway from a mid-grey one and
			# squashed the floor up against the cap: it read as a lighting fault rather than
			# as variety, which is the opposite of what a palette variant is for.
			var lift := INVERTED_LIFT if not palette.is_light else 1.0 / INVERTED_LIFT
			for i: int in ENVIRONMENT_RUNGS:
				var lum := ThemePalette.relative_luminance(out[i])
				var target := lift * (lum + 0.05) - 0.05
				out[i] = ThemePalette.with_luminance(out[i], clampf(target, 0.0, 1.0))
	_keep_accents_off_the_floor(out, pool, palette)
	_guard_contrast(out, palette.get_color(&"void"))
	return out


## The accent pool was filtered against the *palette's* floor (`is_accent_candidate`), but a
## `WARM_COOL` variant has just moved this room's floor toward `heat` or `cold` - so an accent
## that stood off the theme's blue can land on the variant's blue-cyan. Each accent rung that
## no longer differs in hue from the floor it is drawn on is swapped for the next pool entry
## that does, and when the whole pool sits on that hue (nord's frost pool is a cyan and a blue
## over a slate floor pushed toward cyan) for the first of the theme's own tell colours that
## does - fire and blood rather than two more shades of wall, as `_prop_pool` does.
static func _keep_accents_off_the_floor(
	out: Array[Color], pool: Array[Color], palette: ThemePalette
) -> void:
	for i: int in [FLAME_A, FLAME_B]:
		if differs_in_hue(out[i], out[3]):
			continue
		var start := maxi(pool.find(out[i]), 0)
		var replaced := false
		for step in range(1, pool.size()):
			var candidate := pool[(start + step) % pool.size()]
			if differs_in_hue(candidate, out[3]):
				out[i] = candidate
				replaced = true
				break
		if replaced:
			continue
		for role: StringName in ACCENT_FALLBACK_ROLES:
			var candidate := as_accent(palette.get_color(role))
			if candidate.s >= ACCENT_MIN_HUE and differs_in_hue(candidate, out[3]):
				out[i] = candidate
				break


## Builds a ShaderMaterial for a Sprite2D/TileMapLayer authored in the ramp.
static func make_material(
	palette: ThemePalette, variant: int, room_rng_seed: int
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	var targets := target_colors(palette, variant, room_rng_seed)
	mat.set_shader_parameter(&"ramp", PackedColorArray(RAMP))
	mat.set_shader_parameter(&"target_colors", PackedColorArray(targets))
	mat.set_shader_parameter(&"previous_colors", PackedColorArray(targets))
	mat.set_shader_parameter(&"blend", 1.0)
	mat.set_shader_parameter(&"tolerance", 0.02)
	return mat


## Colours a material shows right now: previous_colors and target_colors mixed by `blend`.
## Used as the starting point of a new crossfade so retinting mid-fade never pops.
static func current_colors(mat: ShaderMaterial) -> PackedColorArray:
	var target: Variant = mat.get_shader_parameter(&"target_colors")
	if not (target is PackedColorArray):
		return PackedColorArray()
	var targets := target as PackedColorArray
	var previous: Variant = mat.get_shader_parameter(&"previous_colors")
	var blend_value: Variant = mat.get_shader_parameter(&"blend")
	var t := float(blend_value) if blend_value is float or blend_value is int else 1.0
	if not (previous is PackedColorArray) or t >= 1.0:
		return targets
	var prev := previous as PackedColorArray
	var out := PackedColorArray()
	out.resize(targets.size())
	for i in range(targets.size()):
		out[i] = (prev[i] if i < prev.size() else targets[i]).lerp(targets[i], t)
	return out


## Crossfades a material to a new palette over RETINT_SECONDS. `host` owns the tween. Any
## crossfade still running on the material is killed and its visible colours are the start.
static func retint(
	mat: ShaderMaterial, palette: ThemePalette, variant: int, room_rng_seed: int, host: Node
) -> Tween:
	# has_meta first: reading an absent key with a NIL default is an engine error, and the key
	# is absent on the very first retint of every material.
	if mat.has_meta(RETINT_META):
		var running := mat.get_meta(RETINT_META) as Tween
		if running != null and running.is_valid():
			running.kill()
		mat.remove_meta(RETINT_META)
	var displayed := current_colors(mat)
	var targets := target_colors(palette, variant, room_rng_seed)
	if not displayed.is_empty():
		mat.set_shader_parameter(&"previous_colors", displayed)
	mat.set_shader_parameter(&"target_colors", PackedColorArray(targets))
	mat.set_shader_parameter(&"blend", 0.0)
	if host == null or not host.is_inside_tree():
		mat.set_shader_parameter(&"blend", 1.0)
		return null
	var tween := host.create_tween()
	tween.tween_method(
		func(v: float) -> void: mat.set_shader_parameter(&"blend", v), 0.0, 1.0, RETINT_SECONDS
	)
	mat.set_meta(RETINT_META, tween)
	return tween


## The live Desktop palette when the autoload exists (it always does in-game), else fallback.
static func live_palette() -> ThemePalette:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null:
		var desktop: Node = loop.root.get_node_or_null(^"Desktop")
		if desktop != null:
			var pal: Variant = desktop.get("palette")
			if pal is ThemePalette:
				return pal
	return ThemePalette.fallback()


static func shader() -> Shader:
	return SHADER


## Index of one accent rolled from `pool`, weighted toward its most saturated entries
## (`ACCENT_CHROMA_BIAS`). One `rng` draw per call, so a room's roll stays stable per seed.
static func pick_accent(pool: Array[Color], rng: RandomNumberGenerator) -> int:
	if pool.is_empty():
		return 0
	var weights := PackedFloat32Array()
	for c: Color in pool:
		weights.append(1.0 + ACCENT_CHROMA_BIAS * clampf(c.s, 0.0, 1.0))
	return maxi(GenUtil.weighted_index(weights, rng), 0)


## Nearest ramp index for an authored colour (helper for tests and proc sprites).
static func index_of(c: Color) -> int:
	if c.a < 0.5:
		return 0
	var best := 1
	var best_d := 10.0
	for i in range(1, RAMP_SIZE):
		var d := Vector3(c.r, c.g, c.b).distance_to(Vector3(RAMP[i].r, RAMP[i].g, RAMP[i].b))
		if d < best_d:
			best_d = d
			best = i
	return best


## `c` tempered `t` of the way toward `toward`, taking that mix's chroma and light but keeping
## `c`'s own hue. This is what makes a `WARM_COOL` room a *different room* rather than a
## different theme.
##
## It used to be a plain `lerp`, and a plain lerp toward `heat` is a hue rotation. On the
## owner's sage-green desktop it swung the floor from 75 degrees to 51 and the wall cap to 27,
## a worst gap of 57 degrees from their accent - so one room in seven rendered tan on a palette
## with no tan in it. That is the same complaint the wallpaper cast produced, one layer further
## down, and it has the same answer: the theme owns hue and chroma, the room variant owns value
## and contrast (docs/GAME_DESIGN.md, decisions log). An achromatic rung - a greyscale theme's
## wall, a white wall cap - has no hue to keep, so it takes the mix as it stands.
static func temper(c: Color, toward: Color, t: float) -> Color:
	var mixed := c.lerp(toward, t)
	if c.s <= 0.0:
		return mixed
	var lum := ThemePalette.relative_luminance(mixed)
	return ThemePalette.with_luminance(Color.from_hsv(c.h, mixed.s, maxf(mixed.v, 0.04), c.a), lum)


## `c` with its chroma lifted to `ACCENT_SATURATION`, kept at its own hue and luminance. An
## achromatic colour has no hue to lift and is returned untouched - inventing one would paint a
## grey theme's crypt in a colour the theme does not contain.
static func as_accent(c: Color) -> Color:
	if c.s >= ACCENT_SATURATION or c.s <= 0.0:
		return c
	var lifted := Color.from_hsv(c.h, ACCENT_SATURATION, maxf(c.v, 0.04), c.a)
	return ThemePalette.with_luminance(lifted, ThemePalette.relative_luminance(c))


## The colours this palette's accent rungs may be rolled from: the biome's own subset
## (`palette.prop_pool`, narrowed by `ThemePalette.derive_environment`), keeping only the
## entries that are a colour the room is not already painted in (`is_accent_candidate`) and
## lifting each to a chroma that survives the contrast guard. When the subset offers no such
## colour at all the theme's own tell colours are used instead, so a biome whose keys collapse
## onto the wall gets fire and blood rather than two more shades of wall.
static func _prop_pool(palette: ThemePalette) -> Array[Color]:
	var pool: Array[Color] = []
	for c: Color in palette.prop_pool:
		if is_accent_candidate(c, palette):
			pool.append(as_accent(c))
	if not pool.is_empty():
		# The biome's own keys carry a colour the room is not already painted in. That is the
		# whole point of a biome subset, so it is used as it stands - a one-colour pool is a
		# crypt whose urns are all the same brown, not a crypt whose urns are the wall.
		return pool
	for role: StringName in ACCENT_FALLBACK_ROLES:
		var c := palette.get_color(role)
		if not is_accent_candidate(c, palette) or _has_color(pool, c):
			continue
		pool.append(as_accent(c))
	if pool.size() < ACCENT_POOL_MIN:
		# Nothing in the theme stands off this room. Keep whatever hue the biome's own keys
		# do carry rather than dropping to grey.
		for c: Color in palette.prop_pool:
			if c.s >= ACCENT_MIN_HUE and not _has_color(pool, c):
				pool.append(as_accent(c))
	if pool.size() < ACCENT_POOL_MIN:
		# A theme with no chroma anywhere (a greyscale theme is a legitimate Omarchy theme) has
		# nothing to lift. Keep its own keys, greys and all, so the biomes still differ from
		# each other rather than collapsing onto one shared fallback.
		for c: Color in palette.prop_pool:
			if not _has_color(pool, c):
				pool.append(c)
	if pool.is_empty():
		pool = [palette.get_color(&"accent"), palette.get_color(&"magic")]
	return pool


## Whether `c` can serve as one of a room's accents: it has a hue at all, and that hue is not
## the hue the room is already painted in (see `ACCENT_MIN_HUE_DISTANCE`). An environment role
## with no chroma of its own - a greyscale theme's wall - cannot collide with anything, so it
## is not consulted.
static func is_accent_candidate(c: Color, palette: ThemePalette) -> bool:
	if c.s < ACCENT_MIN_HUE:
		return false
	for role: StringName in ENVIRONMENT_ROLES:
		if not differs_in_hue(c, palette.get_color(role)):
			return false
	return true


## Whether `c` reads as a different *colour* from `surface` rather than a different value of
## it. A surface with no chroma of its own claims no part of the hue circle, so anything with
## a hue stands off it; a surface that does have one is only cleared at
## `ACCENT_MIN_HUE_DISTANCE` away.
static func differs_in_hue(c: Color, surface: Color) -> bool:
	if surface.s < ENV_HUE_SATURATION:
		return true
	return hue_distance(c.h, surface.h) >= ACCENT_MIN_HUE_DISTANCE


## Shortest distance between two hues on the colour circle, in turns (0.0 - 0.5).
static func hue_distance(a: float, b: float) -> float:
	var d := absf(fposmod(a, 1.0) - fposmod(b, 1.0))
	return minf(d, 1.0 - d)


## `c` with enough chroma to read as a colour, at exactly the luminance it arrives with - so
## it cannot undo the contrast the guard just gave it. An achromatic colour has no hue to
## stretch and is returned as it is.
static func ensure_chroma(c: Color, min_chroma: float = ACCENT_MIN_CHROMA) -> Color:
	if chroma(c) >= min_chroma or c.s <= 0.0:
		return c
	var lum := ThemePalette.relative_luminance(c)
	var out := c
	for _i in range(12):
		var s := minf(out.s * 1.3 + 0.06, 1.0)
		out = ThemePalette.with_luminance(Color.from_hsv(out.h, s, out.v, c.a), lum)
		if chroma(out) >= min_chroma or s >= 1.0:
			break
	return out


## Spread between a colour's brightest and dimmest channel. A grey measures 0 at any
## brightness, which is exactly what an accent may not be.
static func chroma(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


static func _has_color(pool: Array[Color], c: Color) -> bool:
	for existing: Color in pool:
		if existing.is_equal_approx(c):
			return true
	return false


## A room's drawn ramp with the two accent rungs replaced by the palette's own fire colours.
## A flame is a flame on every theme: the torch atlas paints its body in accent A and its core
## in accent B, and leaving those to the room's accent roll is how a crypt came to be lit by
## grey torches. Everything else in `base` is left exactly as it is.
## `floor_c` is the colour the flame is judged against - the *room's* floor rung, not `base`'s,
## because `base` is normally the prop tint, whose own floor rung has already been pushed off
## the tile it stands on.
static func flame_colors(
	base: PackedColorArray, palette: ThemePalette, floor_c: Color = Color.TRANSPARENT
) -> PackedColorArray:
	var out := PackedColorArray(base)
	if out.size() < RAMP_SIZE:
		return out
	var against := floor_c if floor_c.a > 0.0 else out[3]
	for pair: Array in [[FLAME_A, &"heat"], [FLAME_B, &"loot"]]:
		var role: Color = palette.get_color(pair[1] as StringName)
		var lit := ThemePalette.separate(role, against, FLAME_FLOOR_RATIO)
		out[int(pair[0])] = ensure_chroma(lit, FLAME_MIN_CHROMA)
	return out


## Keeps a room readable after a variant has pushed its colours around: the floor must stand
## off the surround the room is cut out of, prop accents must stand off the floor they sit on,
## and no two environment rungs may collapse into each other (a light theme's "inverted
## lighting" variant can otherwise land the highlight on top of the floor, which reads as no
## wall at all). The floor is repaired first and the rest in ramp order against it.
##
## Separation is measured as contrast ratio, not as the gamma-encoded luminance gap
## `ThemePalette.push_apart` uses: two near-black rungs can be a whole gap apart and still
## render as one material. A palette that has been through `ThemePalette.light_environment`
## already clears this by construction, so the guard only ever moves what a variant broke.
static func _guard_contrast(colors: Array[Color], surround: Color) -> void:
	var gap := ThemePalette.ENV_LIT_DETAIL_RATIO
	# The surround is painted by FloorRoot, not by this ramp, so it is the one colour here that
	# cannot move: a variant that walks its room's floor into it has to give ground instead.
	colors[3] = ThemePalette.separate(colors[3], surround, ThemePalette.ENV_LIT_FLOOR_VOID_RATIO)
	for i: int in [FLAME_A, FLAME_B]:
		# `separate`, not `ensure_contrast`: the latter lerps toward white, and lerping a dark
		# theme accent far enough to clear the floor leaves a grey. This re-exposes the colour
		# instead, so the rung arrives at the same contrast with its hue and chroma intact.
		colors[i] = ThemePalette.separate(colors[i], colors[3], ACCENT_FLOOR_RATIO)
		colors[i] = ensure_chroma(colors[i])
	# Two passes: repairing a rung against the floor can walk it back into a neighbour.
	for _pass in range(2):
		for i: int in [4, 2, 5, 1]:
			for j: int in [3, 4, 2, 5]:
				if j == i:
					break
				var need := RUNG_FLOOR_RATIOS[i] if j == 3 else gap
				colors[i] = ThemePalette.separate(colors[i], colors[j], need)
