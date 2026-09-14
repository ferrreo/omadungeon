## The *visual* half of pillar 3: "your desktop colours the dungeon" measured on the colours a
## room is actually painted in, not on the palette it is derived from.
##
## What this suite exists for: the lighting model (docs §3.2) places the five environment
## surfaces by luminance, and a theme whose three background keys are grey by authorship came
## out of it as a grey dungeon however well it was lit. Three of the six shipped fixtures are
## that theme - gruvbox authors a pure `#282828`, catppuccin-latte a paper white, `white` is
## greyscale from end to end - and captures of floor 1 measured 1-6% mean screen saturation
## against 25-29% on the vivid ones, i.e. a white-tiled bathroom rather than a place worth
## being in. `ThemePalette.apply_room_cast` hands those themes their own colour; this is the
## measurement that says it happened, and the counter-measurements that say it cost nothing.
class_name ThemeColorTest
extends GdUnitTestSuite

const THEMES: Array[String] = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
## Fixtures whose own background keys are grey: the ones the cast exists for.
const LOW_CHROMA: Array[String] = ["gruvbox", "catppuccin-latte"]
## Fixtures that already colour their own dungeon and must come through untouched.
const VIVID: Array[String] = ["tokyo-night", "catppuccin", "nord"]
## The one shipped fixture with no chroma anywhere. A greyscale desktop is a legitimate
## Omarchy theme and the dungeon it gets is grey: inventing a hue for it would be inventing a
## desktop the player does not have.
const GREYSCALE := "white"
## Mean saturation the five dungeon surfaces must carry on a theme that has any colour at all.
## Measured on the shipped fixtures after the cast: gruvbox 0.256, catppuccin-latte 0.192 at
## its brightest (a near-white paper floor cannot physically hold much chroma, so the cast
## lands on its walls, caps and surround instead), nord 0.263, tokyo-night 0.286.
const MIN_ROOM_SATURATION := 0.18
## How far a lit surface's luminance may drift from the value the exposure model gave it. The
## cast is a hue change at constant luminance; this is the tolerance on "constant".
const LUMINANCE_EPSILON := 0.002
const LEVELS: Array[float] = [WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX]


func _palette(theme: String) -> ThemePalette:
	return ReactivityFixtures.palette_for(theme)


## Mean chroma (brightest minus dimmest channel) of the four rungs a room's tiles are drawn in.
static func _mean_rung_chroma(colors: Array[Color]) -> float:
	var total := 0.0
	for i: int in TileRamp.ENVIRONMENT_RUNGS:
		total += TileRamp.chroma(colors[i])
	return total / float(TileRamp.ENVIRONMENT_RUNGS.size())


func test_every_theme_with_a_colour_paints_its_dungeon_in_it() -> void:
	for theme: String in THEMES:
		if theme == GREYSCALE:
			continue
		for level: float in LEVELS:
			var lit := _palette(theme).light_environment(level)
			var saturation := lit.environment_saturation()
			(
				assert_float(saturation)
				. override_failure_message(
					(
						"%s @ ambient %.2f renders its dungeon at %.3f mean saturation - a grey"
						% [theme, level, saturation]
					)
				)
				. is_greater_equal(MIN_ROOM_SATURATION)
			)


func test_the_low_chroma_fixtures_are_the_ones_that_gained_it() -> void:
	# Stated as the *change*, so the guard cannot be satisfied by a fixture that never had the
	# problem: the themes testers measured as greyscale carry several times the environment
	# saturation they were authored with.
	for theme: String in LOW_CHROMA:
		var raw := _palette(theme)
		var before := raw.environment_saturation()
		var after := raw.light_environment(WallpaperAnalyzer.AMBIENT_MIN).environment_saturation()
		(
			assert_float(before)
			. override_failure_message(
				"%s stopped being the low-chroma case (%.3f)" % [theme, before]
			)
			. is_less(ThemePalette.ROOM_CAST_ENV_FULL)
		)
		(
			assert_float(after)
			. override_failure_message(
				"%s: the dungeon renders at %.3f where the theme is %.3f" % [theme, after, before]
			)
			. is_greater(before * 2.0)
		)


func test_a_greyscale_desktop_is_never_handed_a_colour_it_does_not_own() -> void:
	var raw := _palette(GREYSCALE)
	assert_float(raw.room_cast().a).is_equal(0.0)
	for level: float in LEVELS:
		var lit := raw.light_environment(level)
		for role: String in ThemePalette.ENV_ROLES:
			var c := lit.get_color(StringName(role))
			(
				assert_float(TileRamp.chroma(c))
				. override_failure_message(
					"%s renders %s on a theme with no colour in it" % [role, c.to_html(false)]
				)
				. is_less(0.01)
			)


func test_a_theme_that_already_colours_its_room_keeps_its_own_hue() -> void:
	# The cast may not overwrite a theme that never needed it: nord's slate and tokyo-night's
	# navy are the thing being protected, and a wash that repainted every theme to one target
	# would be the flattening bug wearing a new hat.
	for theme: String in VIVID:
		var raw := _palette(theme)
		for level: float in LEVELS:
			var lit := raw.light_environment(level)
			for role: String in ThemePalette.ENV_ROLES:
				var key := StringName(role)
				var want := raw.get_color(key)
				if want.s < 0.05:
					continue
				var got := lit.get_color(key)
				(
					assert_float(TileRamp.hue_distance(got.h, want.h))
					. override_failure_message(
						(
							"%s @ %.2f: %s renders %s, not the theme's own %s"
							% [theme, level, role, got.to_html(false), want.to_html(false)]
						)
					)
					. is_less(0.04)
				)


func test_the_cast_moves_no_surface_off_the_lighting_ladder() -> void:
	# The counter-property, and the reason the cast is allowed to run inside the lighting
	# model at all: it changes hue at *constant luminance*, so every rung lands on exactly the
	# value the exposure model computed for it and every contrast guard in
	# `EnvironmentLightingTest` is measuring the same numbers it measured before.
	for theme: String in THEMES:
		var raw := _palette(theme)
		var scales := raw.lit_scales()
		for level: float in LEVELS:
			var lit := raw.light_environment(level)
			var floor_lum := ThemePalette.relative_luminance(lit.get_color(&"floor"))
			for role: String in ThemePalette.ENV_ROLES:
				var want := (floor_lum + 0.05) * float(scales[role]) - 0.05
				var got := ThemePalette.relative_luminance(lit.get_color(StringName(role)))
				(
					assert_float(got)
					. override_failure_message(
						(
							"%s @ %.2f: %s sits at L=%.5f where the ladder puts it at %.5f"
							% [theme, level, role, got, want]
						)
					)
					. is_equal_approx(clampf(want, 0.0, 1.0), LUMINANCE_EPSILON)
				)


func test_the_room_still_reads_as_a_room_under_the_cast() -> void:
	# ...and the same property from the player's side rather than the model's: the outline of
	# every room, on every fixture, at both ends of the light level.
	for theme: String in THEMES:
		for level: float in LEVELS:
			var lit := _palette(theme).light_environment(level)
			var floor_c := lit.get_color(&"floor")
			var pairs := {
				"void": ThemePalette.ENV_LIT_FLOOR_VOID_RATIO,
				"wall": ThemePalette.ENV_LIT_FLOOR_WALL_RATIO,
				"wall_top": ThemePalette.ENV_LIT_MIN_RATIO,
				"floor_alt": ThemePalette.ENV_LIT_DETAIL_RATIO,
			}
			for role: String in pairs:
				var got := ThemePalette.contrast_ratio(lit.get_color(StringName(role)), floor_c)
				(
					assert_float(got)
					. override_failure_message(
						"%s @ %.2f: floor/%s reads %.3f:1" % [theme, level, role, got]
					)
					. is_greater_equal(float(pairs[role]) - 0.001)
				)


func test_props_still_stand_off_the_room_they_are_drawn_in() -> void:
	# The other property this work must not break. Giving the room the theme's hue could have
	# handed the props the same one back - "a lavender grid with lavender pots in it" is the
	# regression three testers reported in an earlier round - so every accent a room can roll
	# is measured against the floor it will be drawn on, per biome and per palette variant.
	for theme: String in THEMES:
		var raw := _palette(theme)
		if raw.room_cast().a <= 0.0:
			continue
		for biome_id: StringName in Biome.ALL_IDS:
			var keys := Biome.load_by_id(biome_id).palette_keys
			var lit := raw.derive_environment(keys).light_environment(WallpaperAnalyzer.AMBIENT_MIN)
			for variant: int in range(4):
				var room := TileRamp.target_colors(lit, variant, 4242)
				for rung: int in [TileRamp.FLAME_A, TileRamp.FLAME_B]:
					(
						assert_bool(TileRamp.differs_in_hue(room[rung], room[3]))
						. override_failure_message(
							(
								"%s/%s variant %d: accent rung %d renders %s, the floor's own hue (%s)"
								% [
									theme,
									biome_id,
									variant,
									rung,
									room[rung].to_html(false),
									room[3].to_html(false)
								]
							)
						)
						. is_true()
					)
					(
						assert_float(TileRamp.chroma(room[rung]))
						. override_failure_message(
							(
								"%s/%s variant %d: accent rung %d renders %s, a grey"
								% [theme, biome_id, variant, rung, room[rung].to_html(false)]
							)
						)
						. is_greater_equal(TileRamp.ACCENT_MIN_CHROMA)
					)


func test_the_room_the_tiles_are_drawn_in_carries_the_colour_too() -> void:
	# The palette is not what the player sees; the ramp is. Measured on the four rungs the
	# floor, the wall, the floor detail and the wall cap are actually painted in.
	for theme: String in THEMES:
		if theme == GREYSCALE:
			continue
		var lit := _palette(theme).light_environment(WallpaperAnalyzer.AMBIENT_MIN)
		for variant: int in range(4):
			var room := TileRamp.target_colors(lit, variant, 7)
			var chroma := _mean_rung_chroma(room)
			(
				assert_float(chroma)
				. override_failure_message(
					(
						"%s variant %d: the room's own rungs average %.3f chroma"
						% [theme, variant, chroma]
					)
				)
				. is_greater(0.02)
			)
