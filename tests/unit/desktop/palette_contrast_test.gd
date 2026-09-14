## Contrast floor for the whole palette, on every shipped theme fixture including the two
## light ones. `ThemePalette.ROLE_GUARDS` is the contract: each role names the surface it is
## really drawn on and the ratio it has to keep there. This suite fails the moment a role is
## added without a guard, so nothing can slip back to "guarded against the floor and nothing
## else" (which is how `heal` ended up invisible inside the HP bar on light themes).
class_name PaletteContrastTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const LIGHT_THEMES: PackedStringArray = ["catppuccin-latte", "white"]


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func test_every_guarded_role_clears_its_target_on_every_fixture() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		for role: String in ThemePalette.ROLE_GUARDS:
			var guard: Array = ThemePalette.ROLE_GUARDS[role]
			for surface: String in guard[0] as PackedStringArray:
				var background := p.get_color(StringName(surface))
				var ratio := ThemePalette.contrast_ratio(p.get_color(StringName(role)), background)
				(
					assert_float(ratio)
					. override_failure_message(
						(
							"%s: %s on %s is %.2f:1, needs %.1f:1"
							% [theme, role, surface, ratio, guard[1]]
						)
					)
					. is_greater_equal(float(guard[1]) - 0.001)
				)


## Every role is either a guarded foreground or an environment surface. A new role that is
## neither would silently ship unguarded, so the two lists have to cover `ROLES` exactly.
func test_every_role_is_either_guarded_or_a_surface() -> void:
	for role: String in ThemePalette.ROLES:
		var covered := ThemePalette.ROLE_GUARDS.has(role) or ThemePalette.ENV_ROLES.has(role)
		(
			assert_bool(covered)
			. override_failure_message("role %s has neither a contrast guard nor a surface" % role)
			. is_true()
		)


## The guard this file used to stop at. It measures a *gamma-encoded* luminance gap on the raw
## palette, which is a weak contract twice over: near black a gap it accepts belongs to colours
## whose real contrast is 1.05:1, and the raw palette is not what gets drawn - the floor light
## level is applied after it. It is kept because it still catches a theme whose surfaces are
## literally identical, but `test_environment_surfaces_stay_apart_once_lit` below is the one
## that speaks for the player, and `EnvironmentLightingTest` is where the model is proven.
func test_environment_surfaces_stay_apart_on_every_fixture() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		for i in range(ThemePalette.ENV_ROLES.size()):
			for j in range(i + 1, ThemePalette.ENV_ROLES.size()):
				var a := p.get_color(StringName(ThemePalette.ENV_ROLES[i]))
				var b := p.get_color(StringName(ThemePalette.ENV_ROLES[j]))
				var gap := absf(a.get_luminance() - b.get_luminance())
				(
					assert_float(gap)
					. override_failure_message(
						(
							"%s: %s and %s differ by only %.3f"
							% [theme, ThemePalette.ENV_ROLES[i], ThemePalette.ENV_ROLES[j], gap]
						)
					)
					. is_greater_equal(ThemePalette.ENV_MIN_SEPARATION - 0.0005)
				)


## The post-ambient half of the same question, and the one the blocker was filed against: run
## the guard on the colours the dungeon is actually painted in, at both ends of the light
## level, rather than on the palette they are derived from.
func test_environment_surfaces_stay_apart_once_lit() -> void:
	for theme: String in THEMES:
		var raw := _palette(theme)
		for level: float in [WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX]:
			var lit := raw.light_environment(level)
			for i in range(ThemePalette.ENV_ROLES.size()):
				for j in range(i + 1, ThemePalette.ENV_ROLES.size()):
					var a := StringName(ThemePalette.ENV_ROLES[i])
					var b := StringName(ThemePalette.ENV_ROLES[j])
					var got := ThemePalette.contrast_ratio(lit.get_color(a), lit.get_color(b))
					(
						assert_float(got)
						. override_failure_message(
							(
								"%s @ ambient %.2f: %s and %s render at %.3f:1"
								% [theme, level, a, b, got]
							)
						)
						. is_greater_equal(ThemePalette.ENV_LIT_DETAIL_RATIO - 0.001)
					)


## The regression the blocker was filed for: the HP bar fills with `heal` over a `void` track.
func test_heal_reads_against_the_hp_bar_track() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		var ratio := ThemePalette.contrast_ratio(p.get_color(&"heal"), p.get_color(&"void"))
		(
			assert_float(ratio)
			. override_failure_message("%s heal on void %.2f" % [theme, ratio])
			. is_greater_equal(3.0)
		)


## The other half: secondary HUD text was 1.4:1 on the white fixture.
func test_dim_text_reads_on_every_fixture() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		var ratio := ThemePalette.contrast_ratio(p.get_color(&"text_dim"), p.get_color(&"floor"))
		(
			assert_float(ratio)
			. override_failure_message("%s text_dim on floor %.2f" % [theme, ratio])
			. is_greater_equal(3.0)
		)


func test_light_fixtures_are_detected_as_light() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		assert_bool(p.is_light).is_equal(LIGHT_THEMES.has(theme))


## A light theme's floor stays the brightest surface and its walls take a real step down, so
## the dungeon has depth instead of reading as one sheet of grey.
func test_light_themes_get_a_depth_ladder() -> void:
	for theme: String in LIGHT_THEMES:
		var p := _palette(theme)
		var floor_lum := p.get_color(&"floor").get_luminance()
		for role: StringName in [&"floor_alt", &"wall_top", &"wall", &"void"]:
			(
				assert_float(p.get_color(role).get_luminance())
				. override_failure_message("%s: %s is not below floor" % [theme, role])
				. is_less(floor_lum)
			)
		assert_float(p.get_color(&"wall_top").get_luminance()).is_greater(
			p.get_color(&"wall").get_luminance()
		)
		var wall_ratio := ThemePalette.contrast_ratio(p.get_color(&"wall"), p.get_color(&"floor"))
		(
			assert_float(wall_ratio)
			. override_failure_message("%s wall/floor only %.2f" % [theme, wall_ratio])
			. is_greater_equal(3.0)
		)


## `void` doubles as the unlit surround and the HUD plate, so the palette's own foreground has
## to be readable on it - on a light theme that means `void` stays light rather than flipping
## polarity halfway up the screen.
func test_hud_plate_carries_the_palette_foreground() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		var void_c := p.get_color(&"void")
		for role: StringName in [&"text", &"text_dim", &"heal", &"loot", &"danger"]:
			var ratio := ThemePalette.contrast_ratio(p.get_color(role), void_c)
			(
				assert_float(ratio)
				. override_failure_message("%s: %s on the HUD plate is %.2f" % [theme, role, ratio])
				. is_greater_equal(3.0)
			)
		var polarity := p.get_color(&"floor").get_luminance() > 0.5
		(
			assert_bool(void_c.get_luminance() > 0.5)
			. override_failure_message("%s: the plate flips polarity against the floor" % theme)
			. is_equal(polarity)
		)


## Tile outlines must stay ink. On a dark theme that is `void`; on a light one `void` is a mid
## tone, so the outline is derived separately and has to be darker than every surface.
func test_outline_is_ink_on_every_fixture() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		var ink := p.outline_color()
		if not p.is_light:
			assert_that(ink).is_equal(p.get_color(&"void"))
			continue
		for role: String in ThemePalette.ENV_ROLES:
			(
				assert_float(ink.get_luminance())
				. override_failure_message("%s: outline not darker than %s" % [theme, role])
				. is_less(p.get_color(StringName(role)).get_luminance())
			)


func test_guard_is_idempotent() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		var again := p.derive_environment()
		for role: String in ThemePalette.ROLES:
			(
				assert_bool(again.get_color(role).is_equal_approx(p.get_color(role)))
				. override_failure_message("%s: %s drifted on re-derive" % [theme, role])
				. is_true()
			)


func test_push_apart_only_moves_colliding_surfaces() -> void:
	var far := ThemePalette.push_apart(Color("#ffffff"), Color("#101010"))
	assert_that(far).is_equal(Color("#ffffff"))
	var near := ThemePalette.push_apart(Color("#808080"), Color("#828282"))
	var gap := absf(near.get_luminance() - Color("#828282").get_luminance())
	assert_float(gap).is_greater_equal(ThemePalette.ENV_MIN_SEPARATION - 0.0005)


func test_ensure_contrast_toward_falls_back_when_the_direction_cannot_reach() -> void:
	# White cannot contrast white, so the guard has to turn round and go dark instead.
	var out := ThemePalette.ensure_contrast_toward(
		Color("#eeeeee"), Color("#ffffff"), 4.5, Color.WHITE
	)
	assert_float(ThemePalette.contrast_ratio(out, Color("#ffffff"))).is_greater_equal(4.5)


## `ensure_contrast_all` is what "guard against what is actually behind the element" means:
## a colour that clears the floor but not the plate is not readable, and where no colour can
## clear every surface at once the guard has to land on the most readable one rather than on
## the first one that happens to pass the single background it was handed.
func test_ensure_contrast_all_guards_every_surface_it_is_given() -> void:
	var surfaces: Array[Color] = [Color("#ffffff"), Color("#c2c2c2")]
	var grey := Color("#8d8d8d")
	assert_float(ThemePalette.worst_contrast(grey, surfaces)).is_less(4.5)
	var out := ThemePalette.ensure_contrast_all(grey, surfaces, 4.5, Color.BLACK)
	assert_float(ThemePalette.worst_contrast(out, surfaces)).is_greater_equal(4.5)
	# Already readable on all of them: returned untouched.
	var ink := ThemePalette.ensure_contrast_all(Color("#000000"), surfaces, 4.5, Color.BLACK)
	assert_that(ink).is_equal(Color("#000000"))
	# The impossible pair the HUD used to float over: a near-white floor beside a mid-dark
	# wall. Nothing clears 4.5:1 on both, so the guard maximises the worst case instead.
	var impossible: Array[Color] = [Color("#ffffff"), Color("#5c5c5c")]
	var best := ThemePalette.ensure_contrast_all(grey, impossible, 4.5, Color.BLACK)
	(
		assert_float(ThemePalette.worst_contrast(best, impossible))
		. override_failure_message("the guard gave up instead of improving the worst surface")
		. is_greater(ThemePalette.worst_contrast(grey, impossible))
	)
	assert_float(ThemePalette.worst_contrast(Color("#000000"), [] as Array[Color])).is_equal(INF)
