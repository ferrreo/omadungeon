class_name ThemePaletteTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func test_all_roles_present_for_every_fixture() -> void:
	for theme: String in [
		"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
	]:
		var p := _palette(theme)
		for role: String in ThemePalette.ROLES:
			(
				assert_bool(p.colors.has(role))
				. override_failure_message("%s missing %s" % [theme, role])
				. is_true()
			)


func test_contrast_guard_holds_for_every_fixture() -> void:
	for theme: String in [
		"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
	]:
		var p := _palette(theme)
		var ratio := ThemePalette.contrast_ratio(p.get_color(&"text"), p.get_color(&"floor"))
		(
			assert_float(ratio)
			. override_failure_message("%s text contrast %.2f" % [theme, ratio])
			. is_greater_equal(4.5)
		)
		var danger := ThemePalette.contrast_ratio(p.get_color(&"danger"), p.get_color(&"floor"))
		(
			assert_float(danger)
			. override_failure_message("%s danger contrast %.2f" % [theme, danger])
			. is_greater_equal(3.0)
		)


func test_light_mode_wall_darker_than_floor() -> void:
	var p := _palette("white")
	assert_bool(p.is_light).is_true()
	assert_float(p.get_color(&"wall").get_luminance()).is_less(
		p.get_color(&"floor").get_luminance()
	)


func test_dark_mode_keeps_theme_wall() -> void:
	var p := _palette("tokyo-night")
	assert_bool(p.is_light).is_false()
	assert_object(p.get_color(&"wall")).is_equal(Color("#13141c"))
	assert_object(p.get_color(&"floor")).is_equal(Color("#1a1b26"))


func test_ensure_contrast_pushes_towards_white_on_dark() -> void:
	var out := ThemePalette.ensure_contrast(Color("#222222"), Color("#111111"), 4.5)
	assert_float(ThemePalette.contrast_ratio(out, Color("#111111"))).is_greater_equal(4.5)


func test_fallback_palette_loads() -> void:
	var p := ThemePalette.fallback()
	assert_str(p.name).is_equal("Tokyo Night")
	assert_object(p.get_color(&"floor")).is_equal(Color("#1a1b26"))


func test_otter_colors_mapping() -> void:
	var p := (
		ThemePalette
		. from_otter_colors(
			{
				"background": Color("#101010"),
				"foreground": Color("#eeeeee"),
				"accent": Color("#3399ff"),
				"danger": Color("#ff3333"),
				"success": Color("#33ff33"),
				"warning": Color("#ffcc00"),
				"surface": Color("#202020"),
				"surface_alt": Color("#181818"),
				"muted": Color("#777777"),
			},
			"otter"
		)
	)
	assert_object(p.get_color(&"floor")).is_equal(Color("#101010"))
	assert_object(p.get_color(&"wall")).is_equal(Color("#202020"))
	assert_object(p.get_color(&"loot")).is_equal(Color("#ffcc00"))
	assert_bool(p.is_light).is_false()
