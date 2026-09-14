## "The four dark fixtures and two light ones must each look like *that theme* at a glance, not
## a tint of one look" - the owner's report, measured on the colours a floor is actually drawn
## in. `ThemeIdentityTest` guards the exposure (four themes, four light levels);
## `ThemeColorTest` guards that a theme with colour paints its room in it. This suite is about
## the *amount*: the chroma the room carries, the distance between any two fixtures' rooms,
## the light the torches throw and what the wallpaper adds, all at thresholds a person can see.
class_name ThemeLookTest
extends GdUnitTestSuite

const THEMES: Array[String] = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
## Fixtures whose desktop has colour somewhere - every one but `white`.
const COLOURED: Array[String] = ["tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord"]
const DARK: Array[String] = ["tokyo-night", "gruvbox", "catppuccin", "nord"]
## HSV saturation of the surround on a dark theme with colour. The room surfaces stay at the
## chroma the prop ladder was built on (`ThemePalette.ROOM_CAST_SATURATION`); the surround is
## a third of the frame and reads nothing, so it is where the theme's colour is loud.
const MIN_DARK_SURROUND_SATURATION := 0.42
## ...and the room surfaces themselves still carry a colour rather than a grey.
const MIN_DARK_ROOM_SATURATION := 0.24
## RGB distance (0..sqrt(3)) between two fixtures' structural surfaces, summed over the four of
## them (`ThemePalette.ENV_STRUCTURE`). Two rooms closer than this are one room.
const MIN_PAIR_DISTANCE := 0.12
## RGB distance two coloured dark fixtures' torch lights keep from each other. Two of the
## pairs share a family - tokyo-night and catppuccin both turn toward a blue accent, gruvbox
## and nord both toward a teal one - so this is a distance, not a hue gap: pink and rose are
## two torches, and the measured pairs sit at 0.07 and 0.11.
const MIN_TORCH_GAP := 0.05
## What the two synthetic wallpapers below must move on one theme. Light, and only light: the
## owner took the colours off the wallpaper entirely (docs/GAME_DESIGN.md, decisions log), so
## the hue gap these two used to be required to open is now a thing they are forbidden to do.
const MIN_WALLPAPER_AMBIENT_GAP := 0.2


func _lit(theme: String, wallpaper: WallpaperAnalyzer.Result = null) -> ThemePalette:
	var keys := Biome.load_by_id(&"crypt").palette_keys
	var ambient := wallpaper.ambient_level() if wallpaper != null else 1.0
	return ReactivityFixtures.palette_for(theme).derive_environment(keys).light_environment(ambient)


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func test_a_dark_theme_with_colour_paints_a_coloured_room_not_a_tinted_one() -> void:
	for theme: String in DARK:
		var lit := _lit(theme)
		(
			assert_float(lit.environment_saturation())
			. override_failure_message(
				(
					"%s renders its room at %.3f mean saturation"
					% [theme, lit.environment_saturation()]
				)
			)
			. is_greater_equal(MIN_DARK_ROOM_SATURATION)
		)
		var surround := lit.get_color(&"void")
		(
			assert_float(surround.s)
			. override_failure_message(
				(
					"%s paints its surround %s, at %.3f saturation"
					% [theme, surround.to_html(false), surround.s]
				)
			)
			. is_greater_equal(MIN_DARK_SURROUND_SATURATION)
		)
	# ...and the greyscale desktop is still exactly grey: no hue is ever invented.
	assert_float(_lit("white").environment_saturation()).is_less(0.001)


func test_no_two_fixtures_paint_the_same_room() -> void:
	var lit: Dictionary = {}
	for theme: String in THEMES:
		lit[theme] = _lit(theme)
	for i in range(THEMES.size()):
		for j in range(i + 1, THEMES.size()):
			var a: ThemePalette = lit[THEMES[i]]
			var b: ThemePalette = lit[THEMES[j]]
			var total := 0.0
			for role: String in ThemePalette.ENV_STRUCTURE:
				total += _distance(a.get_color(StringName(role)), b.get_color(StringName(role)))
			(
				assert_float(total)
				. override_failure_message(
					(
						"%s and %s paint rooms only %.3f apart (floor %s vs %s)"
						% [
							THEMES[i],
							THEMES[j],
							total,
							a.get_color(&"floor").to_html(false),
							b.get_color(&"floor").to_html(false)
						]
					)
				)
				. is_greater_equal(MIN_PAIR_DISTANCE)
			)


func test_the_torch_light_is_the_desktops_colour_and_differs_between_desktops() -> void:
	var profile := DungeonLight.resolve()
	var torches: Dictionary = {}
	for theme: String in THEMES:
		var lit := _lit(theme)
		var heat := lit.get_color(&"heat")
		var accent := lit.get_color(&"accent")
		var torch := profile.torch_role_color(lit)
		torches[theme] = torch
		if accent.s < profile.torch_accent_min_saturation:
			assert_float(TileRamp.hue_distance(torch.h, heat.h)).is_less(0.001)
			continue
		var arc := TileRamp.hue_distance(heat.h, accent.h)
		assert_float(TileRamp.hue_distance(heat.h, torch.h)).is_equal_approx(
			arc * profile.torch_accent_mix, 0.005
		)
	for i in range(DARK.size()):
		for j in range(i + 1, DARK.size()):
			var a: Color = torches[DARK[i]]
			var b: Color = torches[DARK[j]]
			(
				assert_float(_distance(a, b))
				. override_failure_message(
					(
						"%s and %s are lit by the same torch (%s vs %s)"
						% [DARK[i], DARK[j], a.to_html(false), b.to_html(false)]
					)
				)
				. is_greater_equal(MIN_TORCH_GAP)
			)


func test_prop_accents_reach_for_the_themes_brightest_chroma() -> void:
	var pool: Array[Color] = [
		Color.from_hsv(0.0, 0.1, 0.6), Color.from_hsv(0.3, 0.5, 0.6), Color.from_hsv(0.6, 1.0, 0.6)
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := [0, 0, 0]
	for _i in range(3000):
		counts[TileRamp.pick_accent(pool, rng)] += 1
	# Weighted 1.3 : 2.5 : 4.0 - the vivid entry leads, the grey still turns up.
	assert_int(counts[2]).is_greater(counts[1])
	assert_int(counts[1]).is_greater(counts[0])
	assert_int(counts[0]).is_greater(3000 / 12)
	assert_float(TileRamp.ACCENT_SATURATION).is_greater(ThemePalette.ROOM_CAST_SATURATION + 0.3)


func test_two_wallpapers_on_one_theme_light_two_different_rooms() -> void:
	var warm := ReactivityFixtures.striped(
		Color("#ffb347"), Color("#fff1a8"), "res://warm-busy.png"
	)
	var cold := ReactivityFixtures.flat(Color("#0b3d4a"), "res://cold-flat.png")
	var theme := "tokyo-night"
	var bare := _lit(theme)
	var lit_warm := _lit(theme, warm)
	var lit_cold := _lit(theme, cold)
	# Luminance: the bright wallpaper lights the floor higher than the dark one.
	assert_float(warm.ambient_level() - cold.ambient_level()).is_greater_equal(
		MIN_WALLPAPER_AMBIENT_GAP
	)
	var floor_warm := ThemePalette.relative_luminance(lit_warm.get_color(&"floor"))
	var floor_cold := ThemePalette.relative_luminance(lit_cold.get_color(&"floor"))
	assert_float(floor_warm).is_greater(floor_cold)
	# Hue: neither of them may move one. An orange picture and a teal one over one navy theme
	# leave every surface on the hue the theme chose - the wallpaper lights the room, the theme
	# colours it.
	for role: StringName in ThemePalette.ENV_ROLES:
		for lit: ThemePalette in [lit_warm, lit_cold]:
			(
				assert_float(TileRamp.hue_distance(lit.get_color(role).h, bare.get_color(role).h))
				. override_failure_message(
					(
						"a wallpaper moved `%s` from hue %.0f to hue %.0f on %s"
						% [
							role,
							bare.get_color(role).h * 360.0,
							lit.get_color(role).h * 360.0,
							theme
						]
					)
				)
				. is_less(0.001)
			)
	# And a flat cold wallpaper lays fewer props than a busy warm one (docs §3.4).
	var profile := ReactivityFixtures.profile_for(theme)
	var busy := GenParams.build(profile, 0, null, warm)
	var quiet := GenParams.build(profile, 0, null, cold)
	assert_float(busy.prop_density - quiet.prop_density).is_greater(0.1)
	# Nothing the guards own moved: the room still reads as a room under either wallpaper.
	for lit: ThemePalette in [lit_warm, lit_cold]:
		var floor_c := lit.get_color(&"floor")
		assert_float(ThemePalette.contrast_ratio(lit.get_color(&"void"), floor_c)).is_greater_equal(
			ThemePalette.ENV_LIT_FLOOR_VOID_RATIO - 0.001
		)
		assert_float(ThemePalette.contrast_ratio(lit.get_color(&"wall"), floor_c)).is_greater_equal(
			ThemePalette.ENV_LIT_FLOOR_WALL_RATIO - 0.001
		)


func test_the_floor_start_line_names_who_lit_the_floor_and_who_coloured_it() -> void:
	assert_str(Hud.desktop_line("Tokyo Night", true)).is_equal(
		"Lit and shaped by your wallpaper - coloured by Tokyo Night"
	)
	assert_str(Hud.desktop_line("Nord", false)).is_equal("Shaped by Nord")
	assert_str(Hud.desktop_line("", false)).is_equal("Shaped by your theme")


func test_the_surround_is_a_dark_of_the_themes_colour_not_black() -> void:
	for theme: String in DARK:
		var void_c := _lit(theme).get_color(&"void")
		assert_float(ThemePalette.relative_luminance(void_c)).is_greater_equal(
			ThemePalette.LIT_SURROUND_LUMINANCE_MIN - 0.0005
		)
		assert_float(TileRamp.chroma(void_c)).is_greater(0.04)
