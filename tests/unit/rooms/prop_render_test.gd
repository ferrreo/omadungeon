## What a prop looks like *in a frame*, not in the colour model.
##
## `prop_tint_test` asserts the ladder `Prop.accent_colors()` computes, and `floor_lighting_test`
## measures a prop's drawn pixels against the drawn floor - but both stop at the material. The
## room then lights itself with additive `PointLight2D` torches, and addition is invisible to a
## contrast model: the same value lands on the prop and on the tile beside it, so every ratio in
## the ramp is pulled toward 1 and the brightest rungs clip into one another. The owner's
## verifier photographed exactly that (a prop measuring 1.87 against its floor where the model
## says 2.2, with the four interior shades reading as one), and nothing in the suite could see
## it, because nothing measured a prop with the room's own light on it.
##
## Two further gaps this closes: props are drawn with the *accent* material
## (`FloorRoot.prop_accent_material_for_room`), which no drawn-pixel test covered - the existing
## one measures `prop_material_for_room`, which is what a chest wears - and the atlases measured
## were only the crypt's.
class_name PropRenderTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const LEVELS: PackedFloat32Array = [WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX]
## Every prop atlas: the catalogue is small now (`Prop.KIND_COUNT` a biome), so every cell the
## game can put on screen is measured here, on every fixture.
const BIOMES: Array[StringName] = Biome.ALL_IDS
## Contrast the *edge* of a prop keeps against the floor: the ink ring of a solid, the outer
## pixels of a flat. This is what a silhouette is, and it is judged on the drawn colours under
## the room's own light like everything else here. 2.0 rather than the ladder's 2.2, for the
## same reason `floor_lighting_test.PROP_CONTRAST` is: the floor it is measured against is the
## *drawn* floor tile (grout and all), not the ramp colour the ladder was placed against.
const EDGE_CONTRAST := 2.0
## Share of a prop's drawn pixels that must clear the floor. Not all of them: the two accent
## rungs are decals (a coffin's cross, a candle's flame) and carry the theme's own colour, which
## is guarded for chroma elsewhere and is allowed to sit anywhere on the luminance scale.
const BODY_COVERAGE := 0.90
## Slack for "the ladder landed a rung exactly on its minimum".
const EPSILON := 0.002

## Floors built by the current test. Freed in `after_test()` so one case's floor is never
## counted against the next one's orphan check (`auto_free` defers to suite teardown).
var _floors: Array[FloorRoot] = []
var _atlas: Image


func before() -> void:
	_atlas = Image.load_from_file(RoomsTestFixtures.ATLAS)


func after_test() -> void:
	for root: FloorRoot in _floors:
		if is_instance_valid(root):
			root.clear_floor()
			root.free()
	_floors.clear()
	# Flush anything the floor queued rather than freed outright, so a leak here is a real leak
	# and not this suite's own teardown showing up in the next test's orphan count.
	await get_tree().process_frame
	await get_tree().process_frame


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _wallpaper(ambient: float) -> WallpaperAnalyzer.Result:
	var result := WallpaperAnalyzer.Result.new()
	result.ambient = ambient
	result.source_path = "res://synthetic-%.2f.png" % ambient
	return result


## A real floor for `theme`, lit at `ambient`, with the wallpaper's other levers neutral.
func _floor(theme: String, ambient: float) -> FloorRoot:
	var root := FloorRoot.new()
	_floors.append(root)
	add_child(root)
	root.build_with_biome(
		RoomsTestFixtures.three_rooms(), Biome.load_by_id(&"crypt"), null, _palette(theme)
	)
	root.set_wallpaper(_wallpaper(ambient))
	return root


## Exactly what `palette_swap.gdshader` does: nearest ramp entry by RGB distance, taken only
## when it is inside the tolerance the material carries.
static func _swap(src: Color, targets: PackedColorArray) -> Color:
	var best := 1e9
	var best_index := -1
	for i in range(TileRamp.RAMP_SIZE):
		var ramp := TileRamp.RAMP[i]
		var distance := Vector3(src.r, src.g, src.b).distance_to(Vector3(ramp.r, ramp.g, ramp.b))
		if distance < best:
			best = distance
			best_index = i
	if best_index < 0 or best >= 0.02:
		return src
	var target := targets[best_index]
	return Color(target.r, target.g, target.b, src.a * target.a)


## The drawn colour of the pixels that *bound* a prop: its ink for a solid, its outermost body
## pixels for a flat (the ones with a transparent 4-neighbour). Modal, so a lone highlight on
## the rim cannot answer for the outline.
func _edge(image: Image, col: int, targets: PackedColorArray, solid: bool) -> Dictionary:
	var out: Dictionary = {}
	for y in range(Layers.TILE):
		for x in range(Layers.TILE):
			var src := image.get_pixel(col * Layers.TILE + x, y)
			if src.a < 0.5:
				continue
			var on_edge := false
			if solid:
				on_edge = TileRamp.index_of(src) == Prop.INK_RUNG
			else:
				for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var nx := x + d.x
					var ny := y + d.y
					if nx < 0 or ny < 0 or nx >= Layers.TILE or ny >= Layers.TILE:
						on_edge = true
					elif image.get_pixel(col * Layers.TILE + nx, ny).a < 0.5:
						on_edge = true
			if not on_edge:
				continue
			var drawn := _swap(src, targets)
			var key := Color(drawn.r, drawn.g, drawn.b, 1.0)
			out[key] = int(out.get(key, 0)) + 1
	return out


## Drawn pixels of one 16x16 cell: colour -> count. Transparent pixels are whatever is behind.
func _cell(image: Image, col: int, targets: PackedColorArray, row: int = 0) -> Dictionary:
	var out: Dictionary = {}
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
	for colour: Color in drawn:
		if int(drawn[colour]) > best_count:
			best_count = int(drawn[colour])
			best = colour
	return best


## The light this floor's own torches lay over a prop, as far out as the ladder is guaranteed:
## the per-channel gain of `Prop.bloom_for`, which is the same band the rendered check excuses
## past. It is not the torch's own energy any more - a lit pixel is drawn at
## `surface * (1 + gain)`, so the light a prop takes depends on the prop as well as the torch.
static func _bloom(root: FloorRoot) -> Color:
	var tiles := Prop.ramp_targets(root.material_for_room(0))
	if tiles.size() < TileRamp.RAMP_SIZE:
		return Color.BLACK
	# Resolved the way the material under test resolved it: `prop_accent_material_for_room` calls
	# `Prop.accent_material(base)` with no palette, so the torch colour comes from the live theme
	# re-guarded against this floor. Handing `root.lit_palette()` in here instead measured the
	# prop against a torch the material was never built for - which in this suite, where the floor
	# is built from a fixture while `Desktop` is pinned to `tokyo-night`, is a different torch.
	return Prop.bloom_for(tiles[Prop.FLOOR_RAMP_INDEX])


## Share of `drawn` whose contrast against `other` reaches `ratio` once `bloom` has landed on
## both - which is the only comparison a player ever actually makes.
static func _lit_coverage(drawn: Dictionary, other: Color, ratio: float, bloom: Color) -> float:
	var total := 0
	var clear := 0
	var background := Prop.under_light(other, bloom)
	for colour: Color in drawn:
		var count := int(drawn[colour])
		total += count
		var lit := Prop.under_light(colour, bloom)
		if ThemePalette.contrast_ratio(lit, background) >= ratio - EPSILON:
			clear += count
	return float(clear) / float(maxi(total, 1))


func test_the_prop_atlases_this_suite_measures_are_real() -> void:
	assert_object(_atlas).is_not_null()
	for biome: StringName in BIOMES:
		var sheet := Image.load_from_file("%s%s.png" % [Prop.PROPS_DIR, biome])
		assert_object(sheet).override_failure_message("no atlas for %s" % biome).is_not_null()
		assert_int(sheet.get_width()).is_greater_equal(Prop.KIND_COUNT * Layers.TILE)


## The guarantee measured the way the player meets it: a placed prop's own pixels, through the
## material a prop really wears, against the floor tile's own pixels, with the room's light on
## both. This is the number the verifier read off a capture as 1.87.
func test_a_drawn_prop_stands_off_its_drawn_floor_under_the_rooms_own_light() -> void:
	for theme: String in THEMES:
		for level: float in LEVELS:
			var root := _floor(theme, level)
			var tiles := Prop.ramp_targets(root.material_for_room(0))
			var floor_body := _modal(_cell(_atlas, 0, tiles, FloorBuilder.ROW_FLOOR))
			var accent := Prop.ramp_targets(root.prop_accent_material_for_room(0))
			assert_int(accent.size()).is_equal(TileRamp.RAMP_SIZE)
			var bloom := _bloom(root)
			for biome: StringName in BIOMES:
				var sheet := Image.load_from_file("%s%s.png" % [Prop.PROPS_DIR, biome])
				for kind in range(Prop.KIND_COUNT):
					var drawn := _cell(sheet, kind, accent)
					var target: float = Prop.readable_contrast()[Prop.BODY_RUNGS[0]]
					var covered := _lit_coverage(drawn, floor_body, target, bloom)
					(
						assert_float(covered)
						. override_failure_message(
							(
								(
									"%s @ %.2f: only %.0f%% of the %s %s reads against the floor "
									+ "once the room's own torches have lit both"
								)
								% [
									theme,
									level,
									covered * 100.0,
									biome,
									Prop.kind_names(biome)[kind]
								]
							)
						)
						. is_greater_equal(BODY_COVERAGE)
					)
			root.clear_floor()


## The interior detail. The four body rungs are the shadow, the body, the lit face and the
## highlight of the drawn object; under the light field the top pair used to arrive at the same
## pixel value, which is a coffin rendering as a two-tone slab with a couple of coloured dots.
func test_the_body_rungs_of_a_prop_stay_apart_under_the_rooms_own_light() -> void:
	for theme: String in THEMES:
		for level: float in LEVELS:
			var root := _floor(theme, level)
			var accent := Prop.ramp_targets(root.prop_accent_material_for_room(0))
			var bloom := _bloom(root)
			for i in range(1, Prop.BODY_RUNGS.size()):
				var below: Color = accent[Prop.BODY_RUNGS[i - 1]]
				var rung: Color = accent[Prop.BODY_RUNGS[i]]
				var step := ThemePalette.contrast_ratio(
					Prop.under_light(rung, bloom), Prop.under_light(below, bloom)
				)
				(
					assert_float(step)
					. override_failure_message(
						(
							(
								"%s @ %.2f: prop rungs %d and %d render %.2f apart under the "
								+ "room's own light - the object has no interior left"
							)
							% [theme, level, Prop.BODY_RUNGS[i - 1], Prop.BODY_RUNGS[i], step]
						)
					)
					. is_greater_equal(Prop.LIT_BODY_STEP - EPSILON)
				)
			# ... and the rim survives it too: the ink is what makes a prop an object.
			var ink: Color = accent[Prop.INK_RUNG]
			for rung_index: int in Prop.BODY_RUNGS:
				var body: Color = accent[rung_index]
				var rim := ThemePalette.contrast_ratio(
					Prop.under_light(body, bloom), Prop.under_light(ink, bloom)
				)
				(
					assert_float(rim)
					. override_failure_message(
						(
							"%s @ %.2f: rung %d lost its outline under the light (%.2f)"
							% [theme, level, rung_index, rim]
						)
					)
					. is_greater_equal(Prop.LIT_BODY_STEP - EPSILON)
				)
			root.clear_floor()


## The silhouette test. The owner's finding on the third round was not "too dark" but "cannot
## tell what things are", and the first thing a shape needs is an edge: the ink ring of a solid
## and the outer pixels of a flat have to stand off the floor on every fixture, light and dark,
## under the room's own torches. Measured on the shipped sheet of every biome through the real
## prop material, so a kind whose outline vanishes into a floor fails here by name.
func test_every_kind_has_an_edge_against_the_floor_on_every_fixture() -> void:
	for theme: String in THEMES:
		for level: float in LEVELS:
			var root := _floor(theme, level)
			var tiles := Prop.ramp_targets(root.material_for_room(0))
			var floor_body := _modal(_cell(_atlas, 0, tiles, FloorBuilder.ROW_FLOOR))
			var accent := Prop.ramp_targets(root.prop_accent_material_for_room(0))
			var bloom := _bloom(root)
			for biome: StringName in BIOMES:
				var sheet := Image.load_from_file("%s%s.png" % [Prop.PROPS_DIR, biome])
				var names: Array = Prop.kind_names(biome)
				for kind in range(Prop.KIND_COUNT):
					var solid := Prop.is_solid(StringName(names[kind]))
					var edge := _edge(sheet, kind, accent, solid)
					(
						assert_int(edge.size())
						. override_failure_message(
							"%s %s draws no edge at all" % [biome, names[kind]]
						)
						. is_greater(0)
					)
					var rim := _modal(edge)
					var dry := ThemePalette.contrast_ratio(rim, floor_body)
					var lit := ThemePalette.contrast_ratio(
						Prop.under_light(rim, bloom), Prop.under_light(floor_body, bloom)
					)
					(
						assert_float(minf(dry, lit))
						. override_failure_message(
							(
								(
									"%s @ %.2f: the edge of the %s %s reads %.2f dry / %.2f lit "
									+ "against the floor (%s on %s)"
								)
								% [
									theme,
									level,
									biome,
									names[kind],
									dry,
									lit,
									rim.to_html(false),
									floor_body.to_html(false),
								]
							)
						)
						. is_greater_equal(EDGE_CONTRAST - EPSILON)
					)
			root.clear_floor()


## The three numbers the prop guarantee actually is, bounded by a literal.
##
## Every other assertion in this suite and in `prop_tint_test` measures against
## `Prop.readable_contrast()`, `Prop.LIT_BODY_STEP` and `Prop.BLOOM_MAX` - which is right, since
## those are what the code places rungs with. It also means the assertion and the code under
## test read the same number, so moving that number moves the goalposts and the ball together.
## Proven by mutation: halving `READABLE_CONTRAST`, dropping `LIT_BODY_STEP` to 1.001 and
## cutting `BLOOM_MAX` to 0.01 each left every ladder test in this repository green.
##
## The mechanism is well covered - a dead contrast guard, a collapsed rung spread and an
## untreated ink rung all fail those tests - so what is missing is only this: nothing stops a
## red readability check being turned green by editing the bar instead of the art. These are the
## bars, taken from docs 3.2 rather than from today's values, and they are read through
## `readable_contrast()` so the `rooms_content.tres` override is bounded too.
##
## Directions differ. Contrast and the interior step are *floors*: lowering one weakens the
## guarantee. `BLOOM_MAX` is a *ceiling*: it is the light level past which the rendered check
## stops asking for an interior at all, so raising it excuses more blow-out.
func test_the_readability_numbers_are_guarantees_not_variables() -> void:
	var contrast := Prop.readable_contrast()
	assert_int(contrast.size()).is_equal(TileRamp.RAMP_SIZE)
	for rung: int in Prop.BODY_RUNGS:
		(
			assert_float(contrast[rung])
			. override_failure_message(
				(
					(
						"rung %d must clear the floor by 2.2:1; the ladder is set to %.2f, and "
						+ "every readability test in the repo measures against that same number"
					)
					% [rung, contrast[rung]]
				)
			)
			. is_greater_equal(2.2)
		)
	for rung: int in [6, 7]:
		(
			assert_float(contrast[rung])
			. override_failure_message(
				(
					"accent rung %d is set to %.2f, under the 2.6:1 it is guaranteed at"
					% [rung, contrast[rung]]
				)
			)
			. is_greater_equal(2.6)
		)
	(
		assert_float(Prop.LIT_BODY_STEP)
		. override_failure_message(
			(
				(
					"LIT_BODY_STEP is %.3f: under 1.12 the two brightest rungs of a lit prop "
					+ "are allowed to close up and the object loses its interior"
				)
				% Prop.LIT_BODY_STEP
			)
		)
		. is_greater_equal(1.12)
	)
	(
		assert_float(Prop.BLOOM_MAX)
		. override_failure_message(
			(
				(
					"BLOOM_MAX is %.3f: it is a ceiling, and raising it excuses more of the "
					+ "frame from the interior guarantee rather than less"
				)
				% Prop.BLOOM_MAX
			)
		)
		. is_less_equal(0.13)
	)
