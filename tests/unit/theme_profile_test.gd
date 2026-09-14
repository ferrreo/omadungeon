class_name ThemeProfileTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"


func _profile(theme: String) -> ThemeProfile:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemeProfile.from_palette(ThemePalette.from_colors_toml(toml, theme))


func test_values_within_clamps() -> void:
	for theme: String in [
		"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
	]:
		var t := _profile(theme)
		# The wiggle band is the profile's own constant (docs §3.3: 0.10 straight halls to 0.90
		# winding), widened from 0.15..0.85 when the owner measured the old spread as below
		# perception; the difficulty levers below keep their documented bounds.
		assert_float(t.corridor_wiggle).is_between(ThemeProfile.WIGGLE_MIN, ThemeProfile.WIGGLE_MAX)
		assert_float(t.room_size_bias).is_between(
			ThemeProfile.ROOM_SIZE_BIAS_MIN, ThemeProfile.ROOM_SIZE_BIAS_MAX
		)
		assert_float(t.trap_density).is_between(0.4, 0.8)
		assert_float(t.prop_density).is_between(0.3, 0.8)
		assert_float(t.hue_dominant).is_between(0.0, 360.0)


## The clamp test above measures the profile's values against the profile's own constants, so
## it passes by construction: set `WIGGLE_MIN` and `WIGGLE_MAX` both to 0.5 and every theme is
## still "within clamps" while corridor wiggle has stopped being a lever at all. Two things are
## needed to make that claim mean something, and neither is a restatement of the code.
##
## First, the bands themselves have to stay wide. The numbers here are the documented ones
## (docs §3.3: 0.10 straight halls to 0.90 winding, widened from 0.15..0.85 when the spread was
## measured as below perception), stated as literals so narrowing a band fails here.
func test_the_lever_bands_are_literals_not_whatever_the_code_says() -> void:
	assert_float(ThemeProfile.WIGGLE_MIN).is_less_equal(0.15)
	assert_float(ThemeProfile.WIGGLE_MAX).is_greater_equal(0.85)
	(
		assert_float(ThemeProfile.WIGGLE_MAX - ThemeProfile.WIGGLE_MIN)
		. override_failure_message("the corridor-wiggle band has been narrowed below 0.60")
		. is_greater_equal(0.60)
	)
	(
		assert_float(ThemeProfile.ROOM_SIZE_BIAS_MAX - ThemeProfile.ROOM_SIZE_BIAS_MIN)
		. override_failure_message("the room-size-bias band has been narrowed below 0.50")
		. is_greater_equal(0.50)
	)
	assert_float(ThemeProfile.FACTION_FAVOURED).is_greater_equal(2.0)


## Second, and this is the half a constant cannot fake: the shipped themes have to actually
## *spread* across those bands. A band can stay 0.10..0.90 while every theme lands on 0.5, and
## then two themes lay out the same dungeon - which is the thing docs §3.3 promises they do not.
## Measured over the six fixtures on 2026-09-14: wiggle spans 0.100 to 0.900, bias spans -0.153
## to 0.229. The floors below sit well under those, so ordinary retuning is free and a flattened
## lever is not.
func test_the_shipped_themes_actually_spread_across_the_bands() -> void:
	var wiggles: Array[float] = []
	var biases: Array[float] = []
	for theme: String in [
		"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
	]:
		var t := _profile(theme)
		wiggles.append(t.corridor_wiggle)
		biases.append(t.room_size_bias)
	wiggles.sort()
	biases.sort()
	(
		assert_float(wiggles[-1] - wiggles[0])
		. override_failure_message(
			(
				(
					"the six fixture themes span only %.3f of corridor wiggle; the lever is flat "
					+ "and two themes lay out the same dungeon"
				)
				% (wiggles[-1] - wiggles[0])
			)
		)
		. is_greater_equal(0.50)
	)
	(
		assert_float(biases[-1] - biases[0])
		. override_failure_message(
			"the six fixture themes span only %.3f of room-size bias" % (biases[-1] - biases[0])
		)
		. is_greater_equal(0.20)
	)


func test_deterministic() -> void:
	var a := _profile("gruvbox")
	var b := _profile("gruvbox")
	assert_int(a.theme_hash).is_equal(b.theme_hash)
	assert_float(a.corridor_wiggle).is_equal(b.corridor_wiggle)
	assert_int(a.biome_order).is_equal(b.biome_order)


func test_light_theme_biases_bigger_rooms() -> void:
	assert_float(_profile("white").room_size_bias).is_greater(
		_profile("tokyo-night").room_size_bias
	)


func test_faction_weights_sum_sane() -> void:
	# The favoured faction is `FACTION_FAVOURED` (2.0, half of every pack - docs §3.3, §7); no
	# faction is ever weighted below 1, so every floor still mixes all three.
	var t := _profile("nord")
	for key: String in ["clowns", "greybeards", "tinkerers"]:
		assert_float(t.faction_weights[key]).is_between(1.0, ThemeProfile.FACTION_FAVOURED)
