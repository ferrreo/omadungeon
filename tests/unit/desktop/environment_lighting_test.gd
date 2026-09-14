## The dungeon's lighting model: `ThemePalette.light_environment()` measured on every shipped
## theme fixture at both ends of the documented ambient clamp.
##
## The bug this suite exists for: the floor light level used to be a `modulate` multiply over
## the tile layers while the surround kept the undimmed `void`, so on a theme whose
## `darker_background` is `background x 0.55` - which is the Omarchy convention - the dungeon
## floor rendered at *exactly* the void's pixel value and the room lost its outline. The older
## guard could not see it, because it measures a gamma-encoded luminance gap on the palette
## *before* the transform, and near black a gap it accepts is a contrast of 1.05:1.
class_name EnvironmentLightingTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const DARK_THEMES: PackedStringArray = ["tokyo-night", "gruvbox", "catppuccin", "nord"]
## Both ends of the clamp plus the middle, so nothing can pass by tuning one endpoint.
const LEVELS: PackedFloat32Array = [0.55, 0.7, 0.85, 1.0]


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _required(a: String, b: String) -> float:
	if not (ThemePalette.ENV_STRUCTURE.has(a) and ThemePalette.ENV_STRUCTURE.has(b)):
		return ThemePalette.ENV_LIT_DETAIL_RATIO
	var pair := [a, b]
	if pair.has("floor") and pair.has("void"):
		return ThemePalette.ENV_LIT_FLOOR_VOID_RATIO
	if pair.has("floor") and pair.has("wall"):
		return ThemePalette.ENV_LIT_FLOOR_WALL_RATIO
	return ThemePalette.ENV_LIT_MIN_RATIO


## The contract: floor, wall, wall cap and void are separable on every fixture at every light
## level, and floor detail never merges into any of them either.
func test_every_lit_surface_pair_stays_apart_on_every_fixture_and_level() -> void:
	for theme: String in THEMES:
		var raw := _palette(theme)
		for level: float in LEVELS:
			var lit := raw.light_environment(level)
			for i in range(ThemePalette.ENV_ROLES.size()):
				for j in range(i + 1, ThemePalette.ENV_ROLES.size()):
					var a := ThemePalette.ENV_ROLES[i]
					var b := ThemePalette.ENV_ROLES[j]
					var want := _required(a, b)
					var got := ThemePalette.contrast_ratio(
						lit.get_color(StringName(a)), lit.get_color(StringName(b))
					)
					(
						assert_float(got)
						. override_failure_message(
							(
								"%s @ ambient %.2f: %s/%s is %.3f:1, needs %.2f:1"
								% [theme, level, a, b, got, want]
							)
						)
						. is_greater_equal(want - 0.001)
					)


## Proof the guard above can fail: run the transform that shipped - every environment colour
## multiplied by the ambient while the surround keeps the palette's own `void` - and the floor
## lands inside a hair of the void on every dark fixture.
func test_the_shipped_uniform_dim_collapses_the_floor_into_the_void() -> void:
	for theme: String in DARK_THEMES:
		var raw := _palette(theme)
		var k := WallpaperAnalyzer.AMBIENT_MIN
		var floor_c := raw.get_color(&"floor")
		var dimmed := Color(floor_c.r * k, floor_c.g * k, floor_c.b * k, 1.0)
		var got := ThemePalette.contrast_ratio(dimmed, raw.get_color(&"void"))
		(
			assert_float(got)
			. override_failure_message(
				"%s: the old uniform dim reads %.3f:1 - it is supposed to be broken" % [theme, got]
			)
			. is_less(ThemePalette.ENV_LIT_FLOOR_VOID_RATIO)
		)
		# ... and the walls went with it.
		var wall := raw.get_color(&"wall")
		var wall_dim := Color(wall.r * k, wall.g * k, wall.b * k, 1.0)
		assert_float(ThemePalette.contrast_ratio(dimmed, wall_dim)).is_less(
			ThemePalette.ENV_LIT_FLOOR_WALL_RATIO
		)


## And the same proof one level up: the raw theme palette is not a lighting model. Every dark
## Omarchy theme packs background, dark_background and darker_background into a range whose
## real contrast runs 1.07:1 to 1.37:1, which is why the model exposes the floor and places the
## rest of the ladder off it instead of painting the theme's own three near-blacks.
func test_the_raw_theme_palette_cannot_carry_the_dungeon() -> void:
	for theme: String in DARK_THEMES:
		var raw := _palette(theme)
		var floor_c := raw.get_color(&"floor")
		var to_void := ThemePalette.contrast_ratio(floor_c, raw.get_color(&"void"))
		var to_wall := ThemePalette.contrast_ratio(floor_c, raw.get_color(&"wall"))
		(
			assert_float(to_wall)
			. override_failure_message("%s raw floor/wall is %.3f:1" % [theme, to_wall])
			. is_less(ThemePalette.ENV_LIT_FLOOR_WALL_RATIO)
		)
		(
			assert_float(to_void)
			. override_failure_message("%s raw floor/void is %.3f:1" % [theme, to_void])
			. is_less(1.5)
		)
		# The lit palette is what repairs it.
		var lit := raw.light_environment(WallpaperAnalyzer.AMBIENT_MIN)
		(
			assert_float(
				ThemePalette.contrast_ratio(lit.get_color(&"floor"), lit.get_color(&"void"))
			)
			. is_greater(to_void)
		)


## Lowering the light level darkens the room; it does not flatten it. Ratios between rungs are
## identical at both ends of the clamp - that is the whole point of placing the ladder by
## contrast rather than scaling the pixels.
func test_the_light_level_darkens_without_flattening() -> void:
	for theme: String in DARK_THEMES:
		var raw := _palette(theme)
		var dark := raw.light_environment(WallpaperAnalyzer.AMBIENT_MIN)
		var bright := raw.light_environment(WallpaperAnalyzer.AMBIENT_MAX)
		var dark_floor := ThemePalette.relative_luminance(dark.get_color(&"floor"))
		var bright_floor := ThemePalette.relative_luminance(bright.get_color(&"floor"))
		(
			assert_float(dark_floor)
			. override_failure_message("%s: a dark wallpaper did not darken the floor" % theme)
			. is_less(bright_floor)
		)
		for role: String in ["void", "wall", "wall_top", "floor_alt"]:
			var key := StringName(role)
			var a := ThemePalette.contrast_ratio(dark.get_color(key), dark.get_color(&"floor"))
			var b := ThemePalette.contrast_ratio(bright.get_color(key), bright.get_color(&"floor"))
			(
				assert_float(a)
				. override_failure_message(
					"%s: %s/floor is %.3f dark but %.3f bright" % [theme, role, a, b]
				)
				. is_equal_approx(b, 0.02)
			)


## Nothing the model produces is underexposed: the lit floor always lands in the documented
## band on a dark theme, and a light theme keeps its paper.
func test_the_lit_floor_is_never_underexposed() -> void:
	for theme: String in THEMES:
		var raw := _palette(theme)
		for level: float in LEVELS:
			var lit := raw.light_environment(level)
			var lum := ThemePalette.relative_luminance(lit.get_color(&"floor"))
			var floor_min := (
				ThemePalette.LIT_FLOOR_LUMINANCE_LIGHT_MIN
				if raw.is_light
				else ThemePalette.LIT_FLOOR_LUMINANCE_MIN
			)
			(
				assert_float(lum)
				. override_failure_message(
					(
						"%s @ %.2f: lit floor luminance %.4f below %.3f"
						% [theme, level, lum, floor_min]
					)
				)
				. is_greater_equal(floor_min - 0.0005)
			)
			# The raw theme floor is near black on every dark theme; the model has to lift it.
			if not raw.is_light:
				assert_float(lum).is_greater(
					ThemePalette.relative_luminance(raw.get_color(&"floor"))
				)


## The ladder keeps a fixed reading order, so a wall never reads as floor and the surround is
## always the darkest thing on a dark theme (docs 3.2: light mode flips the model).
func test_the_depth_ladder_keeps_its_order() -> void:
	for theme: String in THEMES:
		var raw := _palette(theme)
		var lit := raw.light_environment(WallpaperAnalyzer.AMBIENT_MAX)
		var order: PackedStringArray = (
			["wall", "wall_top", "void", "floor_alt", "floor"]
			if raw.is_light
			else ["void", "wall", "floor", "floor_alt", "wall_top"]
		)
		for i in range(1, order.size()):
			var lower := ThemePalette.relative_luminance(lit.get_color(StringName(order[i - 1])))
			var upper := ThemePalette.relative_luminance(lit.get_color(StringName(order[i])))
			(
				assert_float(upper)
				. override_failure_message(
					"%s: %s is not above %s" % [theme, order[i], order[i - 1]]
				)
				. is_greater(lower)
			)


## Foreground roles are re-guarded against the *lit* surfaces, so accents and tell colours keep
## reading once the floor has been exposed.
func test_guards_are_reapplied_against_the_lit_surfaces() -> void:
	for theme: String in THEMES:
		var lit := _palette(theme).light_environment(WallpaperAnalyzer.AMBIENT_MAX)
		for role: String in ThemePalette.ROLE_GUARDS:
			var guard: Array = ThemePalette.ROLE_GUARDS[role]
			for surface: String in guard[0] as PackedStringArray:
				var ratio := ThemePalette.contrast_ratio(
					lit.get_color(StringName(role)), lit.get_color(StringName(surface))
				)
				(
					assert_float(ratio)
					. override_failure_message(
						"%s lit: %s on %s is %.2f:1" % [theme, role, surface, ratio]
					)
					. is_greater_equal(float(guard[1]) - 0.001)
				)


func test_with_luminance_hits_its_target_and_keeps_the_hue() -> void:
	var blue := Color("#1a1b26")
	for target: float in [0.002, 0.045, 0.3, 0.9]:
		var out := ThemePalette.with_luminance(blue, target)
		assert_float(ThemePalette.relative_luminance(out)).is_equal_approx(target, 0.002)
	# Exposure, not tinting: the hue survives a six-fold lift.
	var lifted := ThemePalette.with_luminance(blue, 0.075)
	assert_float(lifted.h).is_equal_approx(blue.h, 0.02)
	assert_float(lifted.s).is_greater(blue.s * 0.8)
	# White cannot be lifted further, so the fallback path takes over without overshooting.
	(
		assert_float(ThemePalette.relative_luminance(ThemePalette.with_luminance(Color.WHITE, 1.0)))
		. is_equal_approx(1.0, 0.002)
	)
	(
		assert_float(ThemePalette.relative_luminance(ThemePalette.with_luminance(Color.BLACK, 0.2)))
		. is_equal_approx(0.2, 0.002)
	)


func test_separate_only_moves_colours_that_collide() -> void:
	var far := ThemePalette.separate(Color("#ffffff"), Color("#101010"), 1.25)
	assert_that(far).is_equal(Color("#ffffff"))
	# Two near-blacks that `push_apart` is happy with, because it measures a gamma-encoded gap.
	var floor_c := Color("#1a1b26")
	var void_c := Color("#0e0e14")
	assert_that(ThemePalette.push_apart(void_c, floor_c)).is_equal(void_c)
	var moved := ThemePalette.separate(void_c, floor_c, 1.25)
	assert_float(ThemePalette.contrast_ratio(moved, floor_c)).is_greater_equal(1.249)
	# Nothing to gain by going darker than black: the guard turns round instead of giving up.
	var lifted := ThemePalette.separate(Color("#010101"), Color("#000000"), 2.0)
	assert_float(ThemePalette.contrast_ratio(lifted, Color("#000000"))).is_greater_equal(1.99)
