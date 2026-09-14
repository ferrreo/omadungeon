## What the dungeon actually looks like, measured on rendered pixels rather than on palette
## roles. Every pixel of every tile is run through the substitution `palette_swap.gdshader`
## performs - nearest ramp colour inside the material's tolerance, replaced by that material's
## target colour - and composited over the surround the floor paints. The assertions are then
## the ones a tester made by hand with a histogram: what colour is most of this room, and does
## it stand off the colour outside the room.
##
## This is the guard the blocker needed. The palette-only check passed the entire time the
## floor rendered at the void's exact pixel value, because the transform that destroyed the
## relationship ran after the palette had been measured.
class_name FloorLightingTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const LEVELS: PackedFloat32Array = [WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX]
const PROPS_ATLAS := "res://assets/sprites/props/crypt.png"
## Share of a region's drawn pixels that must clear the ratio being asked of it. Not all of
## them: a floor tile's grout is painted in the wall colour and a wall's mortar in the outline,
## so a fraction of any tile is deliberately some other rung. What must not happen is the
## *body* of the surface reading as the thing next to it.
const ROOM_COVERAGE := 0.60
const WALL_COVERAGE := 0.80
const PROP_COVERAGE := 0.90
## Contrast a prop's own pixels keep against the floor they stand on. `Prop.READABLE_CONTRAST`
## asks for 2.6 and up per rung; this is that promise measured on the drawn sprite.
const PROP_CONTRAST := 2.0
## A dark dungeon may be moody; it may not be black. Lowest mean luminance a lit floor tile is
## allowed to render at, at the darkest ambient. The floor that shipped measured 0.0037.
const FLOOR_MIN_RENDERED_LUMINANCE := 0.030
## Slack for "the guard put this rung exactly on its minimum" (see `_coverage`).
const EPSILON := 0.002
## Chroma (max channel minus min channel) an accent rung has to keep once the readable tint has
## pushed it off the floor. The dungeon's only saturated colour is its accents: a tester
## scanned a whole floor capture and found three saturated colours in it, all three in the HUD
## and none anywhere in the world, which is what a crypt lit by grey torches measures as.
const ACCENT_MIN_CHROMA := 0.10
## Pixels standing off the floor a torch cell must draw before it counts as having a flame.
const FLAME_MIN_PIXELS := 8
## Contrast a flame keeps against the floor it lights (`TileRamp.FLAME_FLOOR_RATIO`).
const FLAME_FLOOR_CONTRAST := TileRamp.FLAME_FLOOR_RATIO

var _atlas: Image
var _props: Image
## Floors built by the current test. Freed in after_test() so a floor from one case is never
## counted against the next one's orphan check (auto_free defers to suite teardown).
var _floors: Array[FloorRoot] = []


func before() -> void:
	_atlas = Image.load_from_file(RoomsTestFixtures.ATLAS)
	_props = Image.load_from_file(PROPS_ATLAS)


func after_test() -> void:
	for root: FloorRoot in _floors:
		if is_instance_valid(root):
			root.clear_floor()
			root.free()
	_floors.clear()
	# Flush anything the floor queued rather than freed outright, so a leak here is a real
	# leak and not this suite's own teardown showing up in the next test's orphan count.
	await get_tree().process_frame
	await get_tree().process_frame


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _wallpaper(ambient: float) -> WallpaperAnalyzer.Result:
	var r := WallpaperAnalyzer.Result.new()
	r.ambient = ambient
	r.source_path = "res://synthetic-%.2f.png" % ambient
	return r


## A floor built for `theme` and lit at `ambient`, with the wallpaper's other levers neutral.
func _floor(theme: String, ambient: float, data: FloorData = null) -> FloorRoot:
	var root := FloorRoot.new()
	_floors.append(root)
	add_child(root)
	var layout := data if data != null else RoomsTestFixtures.three_rooms()
	root.build_with_biome(layout, Biome.load_by_id(&"crypt"), null, _palette(theme))
	root.set_wallpaper(_wallpaper(ambient))
	return root


## Exactly what the shader does: nearest ramp entry by RGB distance, taken only when it is
## inside the tolerance the material carries.
static func _swap(src: Color, targets: PackedColorArray) -> Color:
	var best := 1e9
	var best_index := -1
	for i in range(TileRamp.RAMP_SIZE):
		var ramp := TileRamp.RAMP[i]
		var d := Vector3(src.r, src.g, src.b).distance_to(Vector3(ramp.r, ramp.g, ramp.b))
		if d < best:
			best = d
			best_index = i
	if best_index < 0 or best >= 0.02:
		return src
	var target := targets[best_index]
	return Color(target.r, target.g, target.b, src.a * target.a)


## Rendered pixels of `cols` atlas cells on `row`: colour -> how many pixels are drawn in it.
## Pixels the sprite leaves transparent are not counted - they are whatever is behind, and the
## question this suite asks is about what the tile itself puts on screen.
func _drawn(
	image: Image, row: int, cols: int, targets: PackedColorArray, start_col: int = 0
) -> Dictionary:
	var out: Dictionary = {}
	for col in range(start_col, start_col + cols):
		for y in range(Layers.TILE):
			for x in range(Layers.TILE):
				var src := image.get_pixel(col * Layers.TILE + x, row * Layers.TILE + y)
				var drawn := _swap(src, targets)
				if drawn.a < 0.5:
					continue
				var key := Color(drawn.r, drawn.g, drawn.b, 1.0)
				out[key] = int(out.get(key, 0)) + 1
	return out


## The colour most of a region is painted in - the number a tester reads off a histogram.
static func _modal(drawn: Dictionary) -> Color:
	var best := Color.MAGENTA
	var best_count := -1
	for c: Color in drawn:
		var n := int(drawn[c])
		if n > best_count:
			best_count = n
			best = c
	return best


## Share of a region's drawn pixels whose contrast against `other` reaches `ratio`. The
## tolerance matters: the guard lands rungs *exactly* on their minimum, and a colour a
## ten-thousandth short of it is not a thing anyone can see.
static func _coverage(drawn: Dictionary, other: Color, ratio: float) -> float:
	var total := 0
	var clear := 0
	for c: Color in drawn:
		var n := int(drawn[c])
		total += n
		if ThemePalette.contrast_ratio(c, other) >= ratio - EPSILON:
			clear += n
	return float(clear) / float(maxi(total, 1))


## Mean rendered luminance of a region, averaged in linear light.
static func _mean_luminance(drawn: Dictionary) -> float:
	var total := 0
	var sum := 0.0
	for c: Color in drawn:
		var n := int(drawn[c])
		total += n
		sum += ThemePalette.relative_luminance(c) * n
	return sum / float(maxi(total, 1))


func _floor_pixels(root: FloorRoot, room_id: int) -> Dictionary:
	var targets := Prop.ramp_targets(root.material_for_room(room_id))
	return _drawn(_atlas, FloorBuilder.ROW_FLOOR, 8, targets)


func _wall_pixels(root: FloorRoot, room_id: int) -> Dictionary:
	var targets := Prop.ramp_targets(root.material_for_room(room_id))
	return _drawn(_atlas, FloorBuilder.ROW_WALL, 16, targets)


func test_the_atlases_this_suite_measures_are_real() -> void:
	assert_object(_atlas).is_not_null()
	assert_object(_props).is_not_null()
	assert_int(_atlas.get_width()).is_greater_equal(FloorBuilder.ATLAS_COLS * Layers.TILE)
	assert_int(_atlas.get_height()).is_greater_equal(FloorBuilder.ATLAS_ROWS * Layers.TILE)
	assert_int(_props.get_width()).is_greater_equal(Prop.KIND_COUNT * Layers.TILE)


## The blocker itself: the room the player is standing in, against the nothing outside it, on
## every fixture at both ends of the ambient clamp.
func test_the_room_reads_against_the_void_on_every_fixture_and_level() -> void:
	for theme: String in THEMES:
		for level: float in LEVELS:
			var root := _floor(theme, level)
			var surround := root.void_color()
			var pixels := _floor_pixels(root, 0)
			var body := _modal(pixels)
			var where := "%s @ ambient %.2f" % [theme, level]
			var got := ThemePalette.contrast_ratio(body, surround)
			(
				assert_float(got)
				. override_failure_message(
					(
						"%s: the floor renders %s against a %s surround - %.3f:1"
						% [where, body.to_html(false), surround.to_html(false), got]
					)
				)
				. is_greater_equal(ThemePalette.ENV_LIT_FLOOR_VOID_RATIO - EPSILON)
			)
			var covered := _coverage(pixels, surround, ThemePalette.ENV_LIT_FLOOR_VOID_RATIO)
			(
				assert_float(covered)
				. override_failure_message(
					"%s: only %.0f%% of the floor stands off the void" % [where, covered * 100.0]
				)
				. is_greater_equal(ROOM_COVERAGE)
			)
			root.clear_floor()


## Walls against the floor they border. The wall row is brick over mortar, so its body is the
## wall-cap rung rather than the wall rung - which is precisely why this is measured on drawn
## pixels and not on the role called "wall".
func test_the_walls_read_against_the_floor_on_every_fixture_and_level() -> void:
	for theme: String in THEMES:
		for level: float in LEVELS:
			var root := _floor(theme, level)
			var floor_body := _modal(_floor_pixels(root, 0))
			var wall := _wall_pixels(root, 0)
			var where := "%s @ ambient %.2f" % [theme, level]
			var got := ThemePalette.contrast_ratio(_modal(wall), floor_body)
			(
				assert_float(got)
				. override_failure_message(
					(
						"%s: wall renders %s on a %s floor - %.3f:1"
						% [where, _modal(wall).to_html(false), floor_body.to_html(false), got]
					)
				)
				. is_greater_equal(ThemePalette.ENV_LIT_FLOOR_WALL_RATIO - EPSILON)
			)
			var covered := _coverage(wall, floor_body, ThemePalette.ENV_LIT_FLOOR_WALL_RATIO)
			(
				assert_float(covered)
				. override_failure_message(
					"%s: only %.0f%% of the wall stands off the floor" % [where, covered * 100.0]
				)
				. is_greater_equal(WALL_COVERAGE)
			)
			root.clear_floor()


## Moody, not underexposed. The floor that shipped rendered at a mean luminance of 0.0037 -
## black to within a pixel value - on the default theme at the darkest wallpaper.
func test_the_floor_is_never_rendered_underexposed() -> void:
	for theme: String in THEMES:
		var root := _floor(theme, WallpaperAnalyzer.AMBIENT_MIN)
		var lum := _mean_luminance(_floor_pixels(root, 0))
		(
			assert_float(lum)
			. override_failure_message(
				"%s at the darkest wallpaper renders a floor of luminance %.4f" % [theme, lum]
			)
			. is_greater_equal(FLOOR_MIN_RENDERED_LUMINANCE)
		)
		root.clear_floor()


## Props, hazards and interactables are drawn in a material derived from the room's own tiles.
## A candle rendering in the wall's colour is this same bug seen from the other side, and the
## tester found exactly that: props at #242839, identical to the wall.
func test_props_stand_off_the_floor_they_are_drawn_on() -> void:
	for theme: String in THEMES:
		for level: float in LEVELS:
			var root := _floor(theme, level)
			var floor_body := _modal(_floor_pixels(root, 0))
			var prop_targets := Prop.ramp_targets(root.prop_material_for_room(0))
			assert_int(prop_targets.size()).is_equal(TileRamp.RAMP_SIZE)
			for kind in range(Prop.KIND_COUNT):
				var drawn := _drawn_cell(_props, kind, prop_targets)
				var covered := _coverage(drawn, floor_body, PROP_CONTRAST)
				(
					assert_float(covered)
					. override_failure_message(
						(
							"%s @ %.2f: only %.0f%% of prop %d stands off the floor"
							% [theme, level, covered * 100.0, kind]
						)
					)
					. is_greater_equal(PROP_COVERAGE)
				)
			root.clear_floor()


## Every room rolls its own palette variant (docs §10). A variant that walks its room's floor
## into the surround is still a room the player cannot find the edges of.
func test_every_palette_variant_keeps_its_room_readable() -> void:
	for variant in range(4):
		for theme: String in THEMES:
			var data := RoomsTestFixtures.three_rooms()
			for room: FloorData.Room in data.rooms:
				room.palette_variant = variant
			var root := _floor(theme, WallpaperAnalyzer.AMBIENT_MIN, data)
			var surround := root.void_color()
			for room: FloorData.Room in data.rooms:
				var pixels := _floor_pixels(root, room.id)
				var body := _modal(pixels)
				var where := "%s variant %d room %d" % [theme, variant, room.id]
				(
					assert_float(ThemePalette.contrast_ratio(body, surround))
					. override_failure_message(
						"%s: floor %s on void" % [where, body.to_html(false)]
					)
					. is_greater_equal(ThemePalette.ENV_LIT_FLOOR_VOID_RATIO - EPSILON)
				)
				(
					assert_float(_coverage(pixels, surround, ThemePalette.ENV_LIT_FLOOR_VOID_RATIO))
					. override_failure_message("%s: the room merged into the void" % where)
					. is_greater_equal(ROOM_COVERAGE)
				)
				var wall := _wall_pixels(root, room.id)
				(
					assert_float(_coverage(wall, body, ThemePalette.ENV_LIT_FLOOR_WALL_RATIO))
					. override_failure_message("%s: the walls merged into the floor" % where)
					. is_greater_equal(WALL_COVERAGE)
				)
			root.clear_floor()


## The floor paints its own surround, at its own light level. The engine clear colour is a
## global that knows nothing about this floor, and leaving the void to it is what put an
## undimmed `void` behind a dimmed dungeon.
func test_the_floor_paints_its_own_surround_and_lights_it() -> void:
	var root := _floor("tokyo-night", WallpaperAnalyzer.AMBIENT_MAX)
	var backdrop := root.get_node_or_null(^"Void") as Polygon2D
	assert_object(backdrop).is_not_null()
	assert_that(backdrop.color).is_equal(root.void_color())
	assert_int(backdrop.z_index).is_less(0)
	var covered := Rect2(backdrop.polygon[0], backdrop.polygon[2] - backdrop.polygon[0])
	assert_bool(covered.encloses(root.camera_limits().grow(FloorRoot.VOID_MARGIN * 0.5))).is_true()
	var bright := root.void_color()
	root.set_wallpaper(_wallpaper(WallpaperAnalyzer.AMBIENT_MIN))
	assert_that(backdrop.color).is_equal(root.void_color())
	(
		assert_float(ThemePalette.relative_luminance(root.void_color()))
		. override_failure_message("a darker wallpaper left the surround alone")
		. is_less(ThemePalette.relative_luminance(bright))
	)


## The environment is lit through the palette its materials carry, not by dimming what is
## drawn: a `modulate` on the tile layers is the transform that collapsed the ladder.
func test_the_environment_is_not_dimmed_by_modulate() -> void:
	var root := _floor("tokyo-night", WallpaperAnalyzer.AMBIENT_MIN)
	assert_float(root.ambient_level()).is_equal_approx(WallpaperAnalyzer.AMBIENT_MIN, 0.001)
	var seen := 0
	for node: CanvasItem in root.environment_nodes():
		(
			assert_that(node.modulate)
			. override_failure_message("%s is dimmed by modulate" % node.name)
			. is_equal(Color.WHITE)
		)
		seen += 1
	assert_int(seen).is_greater(4)
	var lit := root.lit_palette()
	assert_object(lit).is_not_null()
	var full := root.environment_palette().light_environment(WallpaperAnalyzer.AMBIENT_MAX)
	(
		assert_float(ThemePalette.relative_luminance(lit.get_color(&"floor")))
		. override_failure_message("a dark wallpaper did not darken the lit floor")
		. is_less(ThemePalette.relative_luminance(full.get_color(&"floor")))
	)


func _drawn_cell(image: Image, col: int, targets: PackedColorArray) -> Dictionary:
	var out: Dictionary = {}
	for y in range(Layers.TILE):
		for x in range(Layers.TILE):
			var src := image.get_pixel(col * Layers.TILE + x, y)
			var drawn := _swap(src, targets)
			if drawn.a < 0.5:
				continue
			var key := Color(drawn.r, drawn.g, drawn.b, 1.0)
			out[key] = int(out.get(key, 0)) + 1
	return out


## Chroma a colour carries, as the spread between its brightest and dimmest channel. A grey
## measures 0 whatever its brightness, which is exactly the failure being guarded against.
static func _chroma(c: Color) -> float:
	return TileRamp.chroma(c)


## Whether a theme has any colour in it at all. The `white` fixture is authored entirely in
## greys - a legitimate Omarchy theme - and no amount of tinting can find a hue that is not
## there; asking it for a coloured accent would only be asking the code to invent one.
func _has_hue(palette: ThemePalette) -> bool:
	for key: String in palette.source:
		if (palette.source[key] as Color).s >= TileRamp.ACCENT_MIN_HUE:
			return true
	return false


## Every room paints its accent rungs in a colour with hue in it. The biome narrows the accent
## pool to its own theme keys (docs §10) and a crypt's are `background`/`muted`, so without a
## floor on this the level's only two colour slots resolve to two more shades of wall - and on
## a grey theme, to grey. Measured per fixture, per biome, per palette variant.
func test_every_room_paints_its_accents_in_a_colour() -> void:
	for theme: String in THEMES:
		var raw := _palette(theme)
		if not _has_hue(raw):
			continue
		for biome_id: StringName in Biome.ALL_IDS:
			var palette := raw.derive_environment(Biome.load_by_id(biome_id).palette_keys)
			var lit := palette.light_environment(WallpaperAnalyzer.AMBIENT_MIN)
			for variant in range(4):
				var room := PackedColorArray(TileRamp.target_colors(lit, variant, 991))
				var props := Prop.readable_colors(room)
				var best := maxf(_chroma(props[6]), _chroma(props[7]))
				(
					assert_float(best)
					. override_failure_message(
						(
							"%s/%s variant %d: accents render %s and %s - both greys"
							% [
								theme,
								biome_id,
								variant,
								props[6].to_html(false),
								props[7].to_html(false)
							]
						)
					)
					. is_greater_equal(ACCENT_MIN_CHROMA)
				)


## A flame is warm on every theme. The torch cells are painted in the two accent rungs, and
## `TileRamp.flame_colors` puts the palette's own `heat` and `loot` on them, so the sconce
## burns in the theme's fire colour instead of whatever accent its room happened to roll.
func test_torches_burn_in_the_theme_fire_colour() -> void:
	for theme: String in THEMES:
		var root := _floor(theme, WallpaperAnalyzer.AMBIENT_MIN)
		var targets := Prop.ramp_targets(root.torch_material_for_room(0))
		assert_int(targets.size()).is_equal(TileRamp.RAMP_SIZE)
		var lit := root.lit_palette()
		for pair: Array in [[TileRamp.FLAME_A, &"heat"], [TileRamp.FLAME_B, &"loot"]]:
			var drawn: Color = targets[int(pair[0])]
			var role: Color = lit.get_color(pair[1] as StringName)
			(
				assert_float(absf(drawn.h - role.h))
				. override_failure_message(
					(
						"%s: flame rung %d renders %s, not the theme's %s (%s)"
						% [theme, int(pair[0]), drawn.to_html(false), pair[1], role.to_html(false)]
					)
				)
				. is_less(0.02)
			)
			if _has_hue(_palette(theme)):
				(
					assert_float(_chroma(drawn))
					. override_failure_message(
						(
							"%s: flame rung %d renders %s, a grey"
							% [theme, int(pair[0]), drawn.to_html(false)]
						)
					)
					. is_greater_equal(ACCENT_MIN_CHROMA)
				)
		# ...and it is actually drawn: the atlas has to still paint the flame in those rungs.
		var floor_body := _modal(_floor_pixels(root, 0))
		for col: int in [FloorBuilder.SPECIAL_TORCH_A, FloorBuilder.SPECIAL_TORCH_B]:
			var drawn := _drawn(_atlas, FloorBuilder.ROW_SPECIAL, 1, targets, col)
			var flame := 0
			for c: Color in drawn:
				if ThemePalette.contrast_ratio(c, floor_body) >= FLAME_FLOOR_CONTRAST:
					flame += int(drawn[c])
			(
				assert_int(flame)
				. override_failure_message(
					"%s: torch column %d draws %d flame pixels" % [theme, col, flame]
				)
				. is_greater_equal(FLAME_MIN_PIXELS)
			)
		# The flame stands off the floor it lights, like every other prop rung.
		for rung: int in [TileRamp.FLAME_A, TileRamp.FLAME_B]:
			var got := ThemePalette.contrast_ratio(targets[rung], floor_body)
			(
				assert_float(got)
				. override_failure_message(
					(
						"%s: flame rung %d renders %s on a %s floor - %.3f:1"
						% [
							theme,
							rung,
							targets[rung].to_html(false),
							floor_body.to_html(false),
							got
						]
					)
				)
				. is_greater_equal(FLAME_FLOOR_CONTRAST - EPSILON)
			)
		root.clear_floor()


## ...and it still burns in the fire colour after a live retint. This is the half that shipped
## broken: `torch_material_for_room()` and `_retint_layers()` are two different code paths onto
## the same material, the old test only ever read the first, and `EventBus.palette_changed` is
## the game's central mechanic (docs §3.5, "applied immediately, mid-level, always") - it also
## fires on every F5 and every wallpaper reload, so a flame that survives only the initial build
## is a flame the player almost never sees.
func test_torches_still_burn_in_the_fire_colour_after_a_palette_change() -> void:
	for theme: String in THEMES:
		var root := _floor("tokyo-night", WallpaperAnalyzer.AMBIENT_MIN)
		var before := Prop.ramp_targets(root.torch_material_for_room(0))
		assert_int(before.size()).is_equal(TileRamp.RAMP_SIZE)
		EventBus.palette_changed.emit(_palette(theme))
		await get_tree().process_frame
		var after := Prop.ramp_targets(root.torch_material_for_room(0))
		var lit := root.lit_palette()
		for pair: Array in [[TileRamp.FLAME_A, &"heat"], [TileRamp.FLAME_B, &"loot"]]:
			var drawn: Color = after[int(pair[0])]
			var role: Color = lit.get_color(pair[1] as StringName)
			(
				assert_float(TileRamp.hue_distance(drawn.h, role.h))
				. override_failure_message(
					(
						"retint to %s: flame rung %d renders %s, not the theme's %s (%s)"
						% [theme, int(pair[0]), drawn.to_html(false), pair[1], role.to_html(false)]
					)
				)
				. is_less(0.02)
			)
		root.clear_floor()


## A torch is a light source, not a surface a light falls on. The additive PointLight2D the
## floor hangs on each sconce used to be composited over the sconce itself, which clips the two
## warm rungs the line above just guaranteed: nord rendered (255, 255, 235) and gruvbox pure
## white in the captured frame while this suite's palette-only checks all passed. Asserting on
## the ramp colours can never see that, so assert the thing that makes them reach the screen.
func test_a_torch_sconce_is_not_lit_by_its_own_light() -> void:
	var root := _floor("nord", WallpaperAnalyzer.AMBIENT_MAX)
	var lights := root.torch_lights()
	assert_int(lights.size()).is_greater(0)
	for light: PointLight2D in lights:
		var sconce := light.get_parent() as CanvasItem
		assert_object(sconce).is_not_null()
		(
			assert_int(sconce.light_mask & light.range_item_cull_mask)
			. override_failure_message(
				(
					(
						"sconce %s is inside its own light's cull mask; an additive light over a "
						+ "flame clips it to white"
					)
					% sconce.name
				)
			)
			. is_equal(0)
		)


## ...and the other half of that: taking the sconce out of the light must not take the *room*
## out of it. A torch that lights nothing is the same bug from the other side - the warm pool
## on the wall and floor is what a dark dungeon's atmosphere is made of.
func test_a_torch_light_still_reaches_the_tiles_around_it() -> void:
	var root := _floor("nord", WallpaperAnalyzer.AMBIENT_MAX)
	var lights := root.torch_lights()
	assert_int(lights.size()).is_greater(0)
	assert_float(root.torch_light_energy()).is_greater(0.0)
	var ground := root.built_layers.ground as CanvasItem
	for light: PointLight2D in lights:
		(
			assert_int(ground.light_mask & light.range_item_cull_mask)
			. override_failure_message("the floor is outside the torch lights' cull mask")
			. is_not_equal(0)
		)
		assert_that(light.blend_mode).is_equal(Light2D.BLEND_MODE_ADD)
	root.clear_floor()


## The dungeon is not monochrome. Three testers in a row reported floor 1 as "a lavender grid
## with lavender pots in it": every shipped theme authors `background`, `dark_background` and
## `muted` at one hue, the crypt drew its accents from two of them, and the prop atlas paints
## its bodies in the environment rungs - so nothing in the room was a different *colour* from
## the room. This is that measured on the colours a prop is actually drawn in.
func test_props_are_a_different_colour_from_the_room_they_stand_in() -> void:
	for theme: String in THEMES:
		var palette := _palette(theme)
		if not _has_hue(palette):
			continue
		var root := _floor(theme, WallpaperAnalyzer.AMBIENT_MIN)
		for room_id: int in [0, 1, 2]:
			var tiles := Prop.ramp_targets(root.material_for_room(room_id))
			var props := Prop.ramp_targets(root.prop_accent_material_for_room(room_id))
			assert_int(props.size()).is_equal(TileRamp.RAMP_SIZE)
			for i: int in [2, 3, 4, 5]:
				(
					assert_bool(TileRamp.differs_in_hue(props[i], tiles[Prop.FLOOR_RAMP_INDEX]))
					. override_failure_message(
						(
							"%s room %d: prop rung %d renders %s, the floor's own hue (%s)"
							% [
								theme,
								room_id,
								i,
								props[i].to_html(false),
								tiles[Prop.FLOOR_RAMP_INDEX].to_html(false)
							]
						)
					)
					. is_true()
				)
				(
					assert_float(_chroma(props[i]))
					. override_failure_message(
						(
							"%s room %d: prop rung %d renders %s, a grey"
							% [theme, room_id, i, props[i].to_html(false)]
						)
					)
					. is_greater_equal(ACCENT_MIN_CHROMA)
				)
		root.clear_floor()


## ...and it survives a live retint, for the same reason the flame has to.
func test_props_keep_their_own_colour_after_a_palette_change() -> void:
	var root := _floor("tokyo-night", WallpaperAnalyzer.AMBIENT_MIN)
	var mat := root.prop_accent_material_for_room(0)
	EventBus.palette_changed.emit(_palette("gruvbox"))
	await get_tree().process_frame
	var tiles := Prop.ramp_targets(root.material_for_room(0))
	var props := Prop.ramp_targets(mat)
	for i: int in [2, 3, 4, 5]:
		(
			assert_bool(TileRamp.differs_in_hue(props[i], tiles[Prop.FLOOR_RAMP_INDEX]))
			. override_failure_message(
				(
					"after a retint, prop rung %d renders %s, the floor's own hue (%s)"
					% [i, props[i].to_html(false), tiles[Prop.FLOOR_RAMP_INDEX].to_html(false)]
				)
			)
			. is_true()
		)
	root.clear_floor()


## The surround is not one flat colour any more. It deepens with distance from the nearest
## built tile and carries a fine grain, because at 480x270 with 16 px tiles a floor-1 room
## fills about a third of the frame and the rest of it used to be an untextured block - a light
## theme's `void` role especially, which is bright.
##
## What is asserted here is the *other* half, the one the change could have destroyed: it can
## only ever darken. Every contrast in this suite is measured against `root.void_color()`, so a
## surround that is never drawn brighter than that colour makes all of them lower bounds. The
## shader is a multiply by two factors, each of them in [0, 1], and both halves of that claim
## are checked rather than assumed.
func test_the_surround_is_shaded_and_can_only_darken_the_void_colour() -> void:
	for theme: String in ["tokyo-night", "catppuccin-latte"]:
		var root := _floor(theme, WallpaperAnalyzer.AMBIENT_MAX)
		var backdrop := root.get_node_or_null(^"Void") as Polygon2D
		assert_object(backdrop).is_not_null()
		assert_that(backdrop.color).is_equal(root.void_color())
		var mat := backdrop.material as ShaderMaterial
		(
			assert_object(mat)
			. override_failure_message("%s: the surround is painted flat again" % theme)
			. is_not_null()
		)
		assert_str(mat.shader.resource_path).is_equal(FloorRoot.SURROUND_SHADER)
		(
			assert_bool(mat.shader.code.contains("COLOR.rgb *="))
			. override_failure_message(
				(
					"the surround shader no longer composes by multiplying, so it can brighten"
					+ " the void and every contrast this suite measures stops being a bound"
				)
			)
			. is_true()
		)
		for name: String in ["depth_drop", "grain"]:
			var value := float(mat.get_shader_parameter(name))
			(
				assert_float(value)
				. override_failure_message("%s: surround %s is %.2f" % [theme, name, value])
				. is_between(0.0, 1.0)
			)
		var field := mat.get_shader_parameter("depth_map") as Texture2D
		assert_object(field).is_not_null()
		assert_int(field.get_width()).is_equal(root.data.width)
		assert_int(field.get_height()).is_equal(root.data.height)
		root.clear_floor()


## The field the shader reads: 1 on a tile the generator built something on, falling to 0 a
## room's width away from the nearest one. A field that came back uniform would leave the
## surround exactly as flat as it was, and the test above could not tell the difference.
func test_the_surround_field_falls_away_from_the_dungeon() -> void:
	const SIDE := 40
	const FALLOFF := 7.0
	var data := FloorData.new()
	data.width = SIDE
	data.height = SIDE
	data.tiles.resize(SIDE * SIDE)
	data.tiles.fill(FloorData.Tile.VOID)
	data.set_tile(20, 20, FloorData.Tile.FLOOR)
	var image := FloorRoot.surround_field(data, FALLOFF).get_image()
	assert_int(image.get_width()).is_equal(SIDE)
	(
		assert_float(image.get_pixel(20, 20).r)
		. override_failure_message("the dungeon itself is not at full depth in the field")
		. is_equal_approx(1.0, 0.01)
	)
	var last := 1.01
	for step in range(1, 8):
		var value := image.get_pixel(20 + step, 20).r
		(
			assert_float(value)
			. override_failure_message(
				(
					"the field is flat: %d tiles out reads %.2f, %d tiles out read %.2f"
					% [step, value, step - 1, last]
				)
			)
			. is_less(last)
		)
		assert_float(value).is_equal_approx(maxf(0.0, 1.0 - float(step) / FALLOFF), 0.02)
		last = value
	(
		assert_float(image.get_pixel(0, 0).r)
		. override_failure_message("the far corner of the grid is still haloed")
		. is_equal_approx(0.0, 0.01)
	)
