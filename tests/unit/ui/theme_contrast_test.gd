## The GDD §3.2 contrast guard, applied to the roles the HUD *signals* with rather than only
## to body text. The `white` fixture exists to catch this: it ships green/red/yellow as three
## neutral greys, which every per-surface guard passes and no player can tell apart.
class_name ThemeContrastTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "nord", "catppuccin-latte", "white"
]


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func after_test() -> void:
	UiTheme.rebuild(Desktop.palette)


func test_signal_roles_stay_apart_and_readable_on_the_hud_plate() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		UiTheme.rebuild(p)
		var void_c := p.get_color(&"void")
		for role: StringName in UiTheme.SIGNAL_ROLES:
			(
				assert_float(ThemePalette.contrast_ratio(UiTheme.signal_color(role), void_c))
				. override_failure_message("%s: %s unreadable on the HUD plate" % [theme, role])
				. is_greater_equal(UiTheme.SIGNAL_MIN_CONTRAST)
			)
		(
			assert_float(UiTheme.signal_separation())
			. override_failure_message(
				(
					"%s: heal/danger/loot are indistinguishable (%.3f)"
					% [theme, UiTheme.signal_separation()]
				)
			)
			. is_greater_equal(UiTheme.SIGNAL_MIN_DISTANCE)
		)


## Proves the guard is doing work rather than passing by luck: the raw `white` palette really
## does collapse its three signal colours, and a full HP bar really did read as an empty one.
func test_the_white_fixture_needs_the_guard() -> void:
	var p := _palette("white")
	var raw := UiTheme.color_distance(p.get_color(&"heal"), p.get_color(&"danger"))
	assert_float(raw).is_less(UiTheme.SIGNAL_MIN_DISTANCE)
	UiTheme.rebuild(p)
	var full := UiTheme.signal_color(&"heal")
	var critical := UiTheme.signal_color(&"danger")
	assert_float(UiTheme.color_distance(full, critical)).is_greater_equal(
		UiTheme.SIGNAL_MIN_DISTANCE
	)


func test_key_cap_labels_stay_readable_on_the_cap_sprite() -> void:
	var cap := InputGlyphs.cell_color(InputGlyphs.Cell.KEYCAP)
	for theme: String in THEMES:
		var p := _palette(theme)
		UiTheme.rebuild(p)
		var ink := InputGlyphs.keycap_ink(UiTheme.color(&"void"))
		(
			assert_float(ThemePalette.contrast_ratio(ink, cap))
			. override_failure_message(
				"%s: key-cap glyph %s on cap %s" % [theme, ink.to_html(false), cap.to_html(false)]
			)
			. is_greater_equal(4.5)
		)


## The menu backdrop was a 16 px two-tone checkerboard, which on a light theme is not texture,
## it is the transparency grid an image editor draws behind an empty layer: catppuccin-latte
## measured (239,241,245) against (213,216,222) and the first screen a player saw looked like a
## failed asset load. The step is now a fixed contrast ratio, so paper and navy get the same
## faint weave instead of one loud grid and one invisible one.
func test_the_menu_backdrop_weave_is_the_same_faint_step_in_every_polarity() -> void:
	for theme: String in THEMES:
		var palette := _palette(theme)
		UiTheme.rebuild(palette)
		var ground := UiTheme.color(&"floor")
		var weave := ScrollingBackdrop.weave_color(ground, UiTheme.color(&"floor_alt"))
		var ratio := ThemePalette.contrast_ratio(weave, ground)
		(
			assert_float(ratio)
			. override_failure_message("%s: the backdrop weave is a %.2f:1 grid" % [theme, ratio])
			. is_between(
				ScrollingBackdrop.WEAVE_CONTRAST - 0.02, ScrollingBackdrop.WEAVE_CONTRAST + 0.02
			)
		)
	UiTheme.rebuild(Desktop.palette)
