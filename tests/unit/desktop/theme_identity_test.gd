## "Your desktop is the dungeon" measured: a dark theme has to be recognisable from its level,
## not only from its HUD.
##
## The bug this suite exists for: the lighting model that made the dungeon readable did it by
## exposing every dark theme's floor to one target luminance and placing every other surface at
## fixed ratios off it. That guaranteed the contrast and threw the theme away - four fixtures
## rendered floors inside 2% of each other and surrounds inside a pixel value of black, and a
## `magick compare` of the nord and catppuccin captures came back at 3% RMSE, i.e. the same
## picture. Every assertion here is about the *spread* between themes; the readability
## assertions live next door in `EnvironmentLightingTest`, and the last test in this file makes
## sure the two are not in a race - identity may never be bought by breaking the ladder.
class_name ThemeIdentityTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const DARK_THEMES: PackedStringArray = ["tokyo-night", "gruvbox", "catppuccin", "nord"]
const LEVELS: PackedFloat32Array = [0.55, 0.7, 0.85, 1.0]
## Contrast the brightest dark fixture's floor must keep against the darkest one's. Two themes
## a player can tell apart have to differ by more than the rounding of a colour channel; this
## is roughly one rung of the room's own depth ladder, which is the amount a person reads as
## "a different place" rather than "the same place at a different moment".
const THEME_FLOOR_SPREAD := 1.15
## Smallest channel spread the surround keeps on a theme whose own surround has a hue. Pure
## black has a spread of 0, and the model used to land on 2/255.
const SURROUND_CHROMA := 0.02


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


## Largest difference between any two channels of a colour: 0 for a grey, and how much hue a
## near-black surround has left in it once it has been exposed.
static func _chroma(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


## The headline: at every light level the four dark fixtures light their floors to four
## different values, far enough apart to read as four different dungeons.
func test_the_dark_fixtures_do_not_all_light_their_floors_alike() -> void:
	for level: float in LEVELS:
		var lowest := INF
		var highest := 0.0
		var dim := ""
		var bright := ""
		for theme: String in DARK_THEMES:
			var lit := _palette(theme).light_environment(level)
			var lum := ThemePalette.relative_luminance(lit.get_color(&"floor"))
			if lum < lowest:
				lowest = lum
				dim = theme
			if lum > highest:
				highest = lum
				bright = theme
		var spread := (highest + 0.05) / (lowest + 0.05)
		(
			assert_float(spread)
			. override_failure_message(
				(
					"@ ambient %.2f the dark fixtures span only %.3f:1 (%s %.4f .. %s %.4f)"
					% [level, spread, dim, lowest, bright, highest]
				)
			)
			. is_greater_equal(THEME_FLOOR_SPREAD)
		)


## ...and the order is the theme's own. A theme authored lighter than another gets the lighter
## dungeon: the exposure follows the theme's value structure instead of replacing it.
func test_a_lighter_theme_gets_a_lighter_dungeon() -> void:
	var by_theme: Dictionary = {}
	for theme: String in DARK_THEMES:
		var raw := _palette(theme)
		by_theme[theme] = [
			ThemePalette.relative_luminance(raw.get_color(&"floor")),
			ThemePalette.relative_luminance(
				raw.light_environment(WallpaperAnalyzer.AMBIENT_MAX).get_color(&"floor")
			),
		]
	for a: String in DARK_THEMES:
		for b: String in DARK_THEMES:
			if a == b:
				continue
			var left: Array = by_theme[a]
			var right: Array = by_theme[b]
			if float(left[0]) <= float(right[0]):
				continue
			(
				assert_float(float(left[1]))
				. override_failure_message(
					(
						"%s is authored lighter than %s but renders darker (%.4f vs %.4f)"
						% [a, b, float(left[1]), float(right[1])]
					)
				)
				. is_greater(float(right[1]))
			)


## The surround is the largest single region on screen - a third of it on some floors - so it
## is also the largest thing the theme gets to say. It may be dark; it may not be black.
func test_the_surround_never_goes_black() -> void:
	for theme: String in DARK_THEMES:
		for level: float in LEVELS:
			var lit := _palette(theme).light_environment(level)
			var lum := ThemePalette.relative_luminance(lit.get_color(&"void"))
			(
				assert_float(lum)
				. override_failure_message(
					(
						"%s @ %.2f: the surround renders %s (L=%.5f), which is black"
						% [theme, level, lit.get_color(&"void").to_html(false), lum]
					)
				)
				. is_greater_equal(ThemePalette.LIT_SURROUND_LUMINANCE_MIN - 0.0005)
			)


## ...and it is still the theme's own colour down there. A theme whose `darker_background` has
## a hue keeps it; the exposure scales the channels, so the only way to lose it is to land so
## close to black that the channels round together.
func test_the_surround_keeps_the_theme_hue() -> void:
	for theme: String in DARK_THEMES:
		var raw := _palette(theme)
		if _chroma(raw.get_color(&"void")) < 0.01:
			continue  # a genuinely neutral theme has no hue to keep (gruvbox)
		var lit := raw.light_environment(WallpaperAnalyzer.AMBIENT_MIN)
		var got := _chroma(lit.get_color(&"void"))
		(
			assert_float(got)
			. override_failure_message(
				(
					"%s: the surround renders %s, a grey - the theme's is %s"
					% [
						theme,
						lit.get_color(&"void").to_html(false),
						raw.get_color(&"void").to_html(false)
					]
				)
			)
			. is_greater_equal(SURROUND_CHROMA)
		)


## No two dark fixtures may resolve to the same dungeon, taken as the whole set of surfaces
## rather than one of them: same floor and same walls and same surround is the regression.
func test_no_two_dark_fixtures_render_the_same_dungeon() -> void:
	var lit_by_theme: Dictionary = {}
	for theme: String in DARK_THEMES:
		lit_by_theme[theme] = _palette(theme).light_environment(WallpaperAnalyzer.AMBIENT_MIN)
	for i in range(DARK_THEMES.size()):
		for j in range(i + 1, DARK_THEMES.size()):
			var a: ThemePalette = lit_by_theme[DARK_THEMES[i]]
			var b: ThemePalette = lit_by_theme[DARK_THEMES[j]]
			var worst := INF
			for role: String in ThemePalette.ENV_STRUCTURE:
				var key := StringName(role)
				var ca := a.get_color(key)
				var cb := b.get_color(key)
				worst = minf(
					worst, Vector3(ca.r, ca.g, ca.b).distance_to(Vector3(cb.r, cb.g, cb.b))
				)
			(
				assert_float(worst)
				. override_failure_message(
					(
						"%s and %s paint every structural surface within %.4f of each other"
						% [DARK_THEMES[i], DARK_THEMES[j], worst]
					)
				)
				. is_greater(0.01)
			)


## Identity is not allowed to cost readability. The exposure moved; the ladder did not - every
## structural pair still clears the same minimum it did before, on every fixture and level.
## (`EnvironmentLightingTest` owns that contract; this is the cross-check that a change made
## for the sake of theme character cannot pass without it.)
func test_identity_never_costs_the_room_its_outline() -> void:
	for theme: String in DARK_THEMES:
		for level: float in LEVELS:
			var lit := _palette(theme).light_environment(level)
			var floor_c := lit.get_color(&"floor")
			var pairs := {
				"void": ThemePalette.ENV_LIT_FLOOR_VOID_RATIO,
				"wall": ThemePalette.ENV_LIT_FLOOR_WALL_RATIO,
				"wall_top": ThemePalette.ENV_LIT_MIN_RATIO,
			}
			for role: String in pairs:
				var got := ThemePalette.contrast_ratio(lit.get_color(StringName(role)), floor_c)
				(
					assert_float(got)
					. override_failure_message(
						"%s @ %.2f: floor/%s fell to %.3f:1" % [theme, level, role, got]
					)
					. is_greater_equal(float(pairs[role]) - 0.001)
				)
