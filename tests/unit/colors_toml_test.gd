class_name ColorsTomlTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"


func _fixture(theme: String) -> String:
	return "%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme]


func test_parses_every_fixture_completely() -> void:
	for theme: String in [
		"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
	]:
		var toml := ColorsToml.load_file(_fixture(theme))
		assert_object(toml).override_failure_message("missing fixture %s" % theme).is_not_null()
		assert_bool(toml.is_complete()).override_failure_message("incomplete %s" % theme).is_true()


func test_tokyo_night_values_and_mode() -> void:
	var toml := ColorsToml.load_file(_fixture("tokyo-night"))
	assert_str(toml.mode).is_equal("dark")
	assert_object(toml.get_color("background")).is_equal(Color("#1a1b26"))
	assert_object(toml.get_color("accent")).is_equal(Color("#7aa2f7"))
	assert_object(toml.get_color("bright_magenta")).is_equal(Color("#bb9af7"))


func test_light_themes_report_light_mode() -> void:
	assert_str(ColorsToml.load_file(_fixture("catppuccin-latte")).mode).is_equal("light")
	assert_str(ColorsToml.load_file(_fixture("white")).mode).is_equal("light")


func test_legacy_color_aliases_and_defaults() -> void:
	var text := """
background = "#000000"
foreground = "#ffffff"
color1 = "#ff0000"
color2 = "#00ff00"
color3 = "#ffff00"
color4 = "#0000ff"
purple = "#ff00ff"
color6 = "#00ffff"
color8 = "#444444"
"""
	var toml := ColorsToml.parse(text)
	assert_bool(toml.is_complete()).is_true()
	assert_object(toml.get_color("red")).is_equal(Color("#ff0000"))
	assert_object(toml.get_color("magenta")).is_equal(Color("#ff00ff"))
	assert_object(toml.get_color("orange")).is_equal(Color("#ffff00"))
	assert_object(toml.get_color("muted")).is_equal(Color("#444444"))
	assert_object(toml.get_color("bright_red")).is_equal(Color("#ff0000"))
	assert_object(toml.get_color("accent")).is_equal(Color("#0000ff"))
	assert_object(toml.get_color("brown")).is_equal(Color("#ffff00").lerp(Color.BLACK, 0.5))
	assert_str(toml.mode).is_equal("dark")


func test_mode_precedence() -> void:
	assert_str(ColorsToml.parse('mode = "light"\nbackground = "#000000"').mode).is_equal("light")
	assert_str(ColorsToml.parse('theme_type = "dark"\nbackground = "#ffffff"').mode).is_equal(
		"dark"
	)
	assert_str(ColorsToml.parse('background = "#000000"', true).mode).is_equal("light")
	assert_str(ColorsToml.parse('background = "#f0f0f0"').mode).is_equal("light")
	assert_str(ColorsToml.parse('background = "#101010"').mode).is_equal("dark")


func test_comments_and_quotes() -> void:
	var toml := ColorsToml.parse(
		"# comment\nbackground = '#123456' # trailing\n[section]\nfoo = bar\n"
	)
	assert_object(toml.get_color("background")).is_equal(Color("#123456"))
	assert_str(str(toml.raw.get("foo"))).is_equal("bar")
