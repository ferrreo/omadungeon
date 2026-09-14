class_name TileRampTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const VARIANT_THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]


func test_ramp_is_exact() -> void:
	assert_int(TileRamp.RAMP.size()).is_equal(8)
	assert_float(TileRamp.RAMP[0].a).is_equal(0.0)
	assert_str(TileRamp.RAMP[1].to_html(false)).is_equal("101010")
	assert_str(TileRamp.RAMP[2].to_html(false)).is_equal("303030")
	assert_str(TileRamp.RAMP[3].to_html(false)).is_equal("505050")
	assert_str(TileRamp.RAMP[4].to_html(false)).is_equal("707070")
	assert_str(TileRamp.RAMP[5].to_html(false)).is_equal("909090")
	assert_str(TileRamp.RAMP[6].to_html(false)).is_equal("b00000")
	assert_str(TileRamp.RAMP[7].to_html(false)).is_equal("0000b0")


## A floor builds its materials from a *lit* palette (`ThemePalette.light_environment`), whose
## rungs already clear the readability guard, so the ramp maps the roles straight through and
## the room shows the theme's own colours. That the guard is a no-op here is the assertion.
func test_base_variant_maps_roles() -> void:
	var p := ThemePalette.fallback().light_environment(WallpaperAnalyzer.AMBIENT_MAX)
	var c := TileRamp.target_colors(p, TileRamp.Variant.BASE, 7)
	assert_int(c.size()).is_equal(8)
	assert_bool(c[1].is_equal_approx(p.get_color(&"void"))).is_true()
	assert_bool(c[2].is_equal_approx(p.get_color(&"wall"))).is_true()
	assert_bool(c[3].is_equal_approx(p.get_color(&"floor"))).is_true()
	assert_bool(c[4].is_equal_approx(p.get_color(&"floor_alt"))).is_true()
	assert_bool(c[5].is_equal_approx(p.get_color(&"wall_top"))).is_true()
	assert_bool(p.prop_pool.has(c[6]) or c[6] != c[3]).is_true()


## ... and it is not a no-op on a raw theme palette, which is the reason the guard exists. A
## dark Omarchy theme packs background, dark_background and darker_background inside 1.15:1 of
## each other, so a ramp built straight off one paints wall, floor and surround as one value.
## Near black the guard cannot reach every rung's full target - there is no room below the
## floor to put one - but it must still pull every pair off every other pair.
func test_the_guard_repairs_a_raw_theme_palette() -> void:
	var raw := ThemePalette.fallback()
	var before := ThemePalette.contrast_ratio(raw.get_color(&"wall"), raw.get_color(&"floor"))
	(
		assert_float(before)
		. override_failure_message("the fixture stopped being the collapsed case: %.3f" % before)
		. is_less(ThemePalette.ENV_LIT_DETAIL_RATIO)
	)
	var c := TileRamp.target_colors(raw, TileRamp.Variant.BASE, 7)
	for i: int in [1, 2, 3, 4, 5]:
		for j: int in [1, 2, 3, 4, 5]:
			if i == j:
				continue
			var got := ThemePalette.contrast_ratio(c[i], c[j])
			(
				assert_float(got)
				. override_failure_message("rungs %d and %d render at %.3f:1" % [i, j, got])
				. is_greater_equal(ThemePalette.ENV_LIT_DETAIL_RATIO - 0.01)
			)


func test_variants_are_deterministic_per_seed() -> void:
	var p := ThemePalette.fallback()
	for variant in range(4):
		var a := TileRamp.target_colors(p, variant, 123)
		var b := TileRamp.target_colors(p, variant, 123)
		for i in range(8):
			assert_bool(a[i].is_equal_approx(b[i])).is_true()
	var diff_seed := false
	for seed_value in range(1, 20):
		var x := TileRamp.target_colors(p, TileRamp.Variant.ACCENT_SHIFT, seed_value)
		var y := TileRamp.target_colors(p, TileRamp.Variant.ACCENT_SHIFT, seed_value + 100)
		if not x[6].is_equal_approx(y[6]) or not x[7].is_equal_approx(y[7]):
			diff_seed = true
	assert_bool(diff_seed).is_true()


func test_variants_differ_from_base() -> void:
	var p := ThemePalette.fallback()
	var base := TileRamp.target_colors(p, TileRamp.Variant.BASE, 5)
	var warm := TileRamp.target_colors(p, TileRamp.Variant.WARM_COOL, 5)
	var inverted := TileRamp.target_colors(p, TileRamp.Variant.INVERTED, 5)
	assert_bool(warm[3].is_equal_approx(base[3])).is_false()
	assert_bool(inverted[3].is_equal_approx(base[3])).is_false()
	assert_bool(inverted[5].is_equal_approx(base[5])).is_false()


func test_roll_variant_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var counts := [0, 0, 0, 0]
	for _i in range(2000):
		counts[TileRamp.roll_variant(rng)] += 1
	assert_int(counts[0]).is_between(1100, 1300)
	assert_int(counts[1]).is_between(320, 480)
	assert_int(counts[2]).is_between(230, 370)
	assert_int(counts[3]).is_between(60, 140)


func test_material_and_retint() -> void:
	var p := ThemePalette.fallback().light_environment(WallpaperAnalyzer.AMBIENT_MAX)
	var mat := TileRamp.make_material(p, TileRamp.Variant.BASE, 1)
	assert_object(mat.shader).is_not_null()
	var ramp: PackedColorArray = mat.get_shader_parameter(&"ramp")
	assert_int(ramp.size()).is_equal(8)
	assert_float(float(mat.get_shader_parameter(&"blend"))).is_equal(1.0)
	var host: Node = auto_free(Node.new())
	add_child(host)
	var tween := TileRamp.retint(mat, p, TileRamp.Variant.INVERTED, 1, host)
	assert_object(tween).is_not_null()
	assert_float(float(mat.get_shader_parameter(&"blend"))).is_equal(0.0)
	var prev: PackedColorArray = mat.get_shader_parameter(&"previous_colors")
	var target: PackedColorArray = mat.get_shader_parameter(&"target_colors")
	assert_bool(prev[3].is_equal_approx(p.get_color(&"floor"))).is_true()
	assert_bool(target[3].is_equal_approx(prev[3])).is_false()
	tween.kill()


## The first retint of a material has no stored tween. Reading that meta must not touch the
## engine's "no default given" path, and a second retint must replace, not stack, the tween.
func test_retint_handles_a_material_with_no_stored_tween() -> void:
	var p := ThemePalette.fallback()
	var mat := TileRamp.make_material(p, TileRamp.Variant.BASE, 1)
	assert_bool(mat.has_meta(TileRamp.RETINT_META)).is_false()
	var host: Node = auto_free(Node.new())
	add_child(host)
	var first := TileRamp.retint(mat, p, TileRamp.Variant.INVERTED, 1, host)
	assert_object(first).is_not_null()
	assert_bool(mat.has_meta(TileRamp.RETINT_META)).is_true()
	var second := TileRamp.retint(mat, p, TileRamp.Variant.BASE, 1, host)
	assert_object(second).is_not_null()
	assert_bool(first.is_valid()).is_false()
	assert_object(mat.get_meta(TileRamp.RETINT_META)).is_same(second)
	second.kill()


func test_index_of_nearest() -> void:
	assert_int(TileRamp.index_of(Color("#515151"))).is_equal(3)
	assert_int(TileRamp.index_of(Color("#b00000"))).is_equal(6)
	assert_int(TileRamp.index_of(Color(0, 0, 0, 0))).is_equal(0)


func _lit(theme: String, ambient: float) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme).light_environment(ambient)


## Two rooms of one dungeon seen through an open doorway are two rooms. The inverted-lighting
## variant used to lerp a room's floor 35% and its cap 60% of the way to `text_bright` on top
## of an already-lit palette, and on nord's floor 6 that put a near-white room directly beside
## the mid-grey one the player was standing in - which reads as a lighting fault, not variety.
## The lift is now a bounded re-exposure, so an inverted room is brighter and still the same
## dungeon. Every variant is measured, because any of them could grow the same problem.
func test_no_palette_variant_puts_a_room_a_world_away_from_its_neighbour() -> void:
	for theme: String in VARIANT_THEMES:
		for ambient: float in [WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX]:
			var palette := _lit(theme, ambient)
			var base := TileRamp.target_colors(palette, TileRamp.Variant.BASE, 11)
			for variant in range(4):
				var other := TileRamp.target_colors(palette, variant, 11)
				for i: int in TileRamp.ENVIRONMENT_RUNGS:
					var ratio := ThemePalette.contrast_ratio(other[i], base[i])
					(
						assert_float(ratio)
						. override_failure_message(
							(
								"%s variant %d: rung %d is %.2f:1 from the same rung next door"
								% [theme, variant, i, ratio]
							)
						)
						. is_less_equal(TileRamp.INVERTED_LIFT + 0.05)
					)


## The guard for what the variant is *for*: re-exposing a room may not flatten the ladder
## inside it. A floor that has been walked up against its own wall cap has traded the room's
## depth for the room's brightness, which is the bug the old lerp actually shipped.
func test_an_inverted_room_keeps_its_own_floor_wall_ladder() -> void:
	for theme: String in VARIANT_THEMES:
		var palette := _lit(theme, WallpaperAnalyzer.AMBIENT_MAX)
		var base := TileRamp.target_colors(palette, TileRamp.Variant.BASE, 11)
		var inverted := TileRamp.target_colors(palette, TileRamp.Variant.INVERTED, 11)
		for pair: Array in [[3, 2], [3, 5]]:
			var want := ThemePalette.contrast_ratio(base[pair[0]], base[pair[1]])
			var got := ThemePalette.contrast_ratio(inverted[pair[0]], inverted[pair[1]])
			(
				assert_float(got)
				. override_failure_message(
					(
						"%s: inverted rungs %d/%d read %.2f:1 where the base room reads %.2f:1"
						% [theme, pair[0], pair[1], got, want]
					)
				)
				. is_greater_equal(want * 0.8)
			)
