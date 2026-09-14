class_name UiThemeTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func after_test() -> void:
	UiTheme.rebuild(Desktop.palette)


func test_theme_builds_with_fonts_and_styles() -> void:
	var theme := UiTheme.theme()
	assert_object(theme).is_not_null()
	assert_object(theme.get_font(&"font", &"Label")).is_not_null()
	assert_int(theme.get_font_size(&"font_size", &"Label")).is_equal(UiTheme.SIZE_S)
	assert_bool(theme.has_stylebox(&"normal", &"Button")).is_true()
	assert_bool(theme.has_stylebox(&"panel", &"Card")).is_true()
	assert_bool(theme.is_type_variation(&"Heading", &"Label")).is_true()
	assert_object(UiTheme.icon(UiTheme.Icon.GOLD)).is_not_null()


func test_rebuild_applies_palette_immediately() -> void:
	var p := _palette("white")
	UiTheme.rebuild(p)
	assert_that(UiTheme.color(&"text")).is_equal(p.get_color(&"text"))
	assert_that(UiTheme.theme().get_color(&"font_color", &"Label")).is_equal(p.get_color(&"text"))
	var style := UiTheme.theme().get_stylebox(&"panel", &"Panel") as StyleBoxFlat
	assert_that(style.bg_color).is_equal(p.get_color(&"floor"))


func test_recolours_on_palette_changed_with_crossfade() -> void:
	var start := _palette("tokyo-night")
	UiTheme.rebuild(start)
	var target := _palette("gruvbox")
	EventBus.palette_changed.emit(target)
	await await_millis(150)
	var mid := UiTheme.color(&"text")
	assert_that(mid).is_not_equal(start.get_color(&"text"))
	assert_that(mid).is_not_equal(target.get_color(&"text"))
	await await_millis(700)
	assert_that(UiTheme.color(&"text")).is_equal(target.get_color(&"text"))
	assert_that(UiTheme.theme().get_color(&"font_color", &"Label")).is_equal(
		target.get_color(&"text")
	)


func test_apply_sets_shared_theme_on_control() -> void:
	var control: Control = auto_free(Control.new())
	UiTheme.apply(control)
	assert_object(control.theme).is_same(UiTheme.theme())


## The white fixture ships `dark_foreground = #c0c0c0` on a #ffffff background (1.8:1). The
## palette now guards that role itself, and the theme guard on top of it is a no-op - both
## ends have to clear 3:1 or secondary HUD text disappears again.
func test_dim_text_keeps_contrast_on_light_themes() -> void:
	for theme: String in ["white", "catppuccin-latte"]:
		var p := _palette(theme)
		UiTheme.rebuild(p)
		var dim := UiTheme.theme().get_color(&"font_color", &"Dim")
		var raw := p.get_color(&"text_dim")
		assert_float(ThemePalette.contrast_ratio(raw, p.get_color(&"floor"))).is_greater_equal(3.0)
		assert_float(ThemePalette.contrast_ratio(dim, p.get_color(&"floor"))).is_greater_equal(3.0)


## `on()` is what custom-drawn widgets use to judge a role against the plate they actually
## draw it on, rather than against the dungeon floor.
func test_on_guards_a_role_against_another_surface() -> void:
	for theme: String in ["white", "catppuccin-latte", "tokyo-night"]:
		var p := _palette(theme)
		UiTheme.rebuild(p)
		var accent := UiTheme.on(&"accent", &"void", 4.5)
		(
			assert_float(ThemePalette.contrast_ratio(accent, p.get_color(&"void")))
			. override_failure_message("%s: accent not readable on void" % theme)
			. is_greater_equal(4.5)
		)
		var same := UiTheme.readable_on(Color("#ffffff"), Color("#000000"), 4.5)
		assert_that(same).is_equal(Color("#ffffff"))


func test_plate_colour_is_the_void_surface() -> void:
	var p := _palette("catppuccin-latte")
	UiTheme.rebuild(p)
	var plate := UiTheme.plate_color(0.94)
	assert_float(plate.a).is_equal_approx(0.94, 0.001)
	assert_bool(Color(plate.r, plate.g, plate.b).is_equal_approx(p.get_color(&"void"))).is_true()


func test_icon_for_falls_back_to_the_shared_sheet() -> void:
	var ability := UiFakes.make_active("fireball", "Fireball", 6.0)
	ability.icon = null
	assert_object(UiTheme.icon_for(ability)).is_not_null()
	assert_object(UiTheme.icon_for(null)).is_null()
