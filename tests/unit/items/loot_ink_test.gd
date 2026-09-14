## The other half of the pickup contrast guarantee: a drop is measured against the surfaces the
## *lighting layer draws*, not the ones the palette authored.
##
## `PickupWorldContrastTest` holds `ThemePalette.world_color()` against the authored surfaces and
## every fixture passes it. The frame did not. On `white` the ink solves to 3.04:1 against the
## authored wall, which is 0.04 over its own 3.0 line, and the darkness over the environment takes
## that to 2.52:1 - a coin the player cannot see on a wall tile (`pickup_frame`). Deepening the ink
## cannot fix it either: on that fixture the floor is paper and the wall is mid-grey, so an ink
## dark enough for one is too close to the other, whichever way it is pushed.
##
## So the line is met per surface rather than globally, by a second colour: `LootInk.halo_for`
## hands back the ring a drop wears behind its ink, and between the two of them every drawn
## surface is cleared. This suite holds three things about that - the ring appears exactly where
## one ink cannot do the job, the pair clears every drawn surface on every fixture, and with the
## lighting layer off a drop is the single-colour shape it always was.
class_name LootInkTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const LIGHT_THEMES: PackedStringArray = ["catppuccin-latte", "white"]
## Slack for the last lerp of the guard's search, which lands on the target rather than exactly
## on it (same value and reason as `PickupWorldContrastTest`).
const EPSILON := 0.01

var _saved: Variant


func before_test() -> void:
	_saved = GameState.settings.get(LightingProfile.SETTING_QUALITY)


func after_test() -> void:
	if _saved == null:
		GameState.settings.erase(LightingProfile.SETTING_QUALITY)
	else:
		GameState.settings[LightingProfile.SETTING_QUALITY] = _saved


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


## The guarantee, on every fixture and every surface as the layer draws it: for each surface the
## ink or the ring clears the line. Neither has to clear all of them alone - that is the whole
## point of there being two.
## The contrast test below measures against `LootInk.MIN_CONTRAST`, which is the same number
## the ink picker itself targets, so the two move together and that test cannot see the
## guarantee being lowered. This is the literal it has to clear. 3.0:1 is `WORLD_MIN_CONTRAST`,
## the WCAG AA line for graphical objects rather than the 4.5:1 for body text - a drop is a
## shape on a floor, not a paragraph - and a drop nobody can pick out of the tiles is a lost item.
func test_the_contrast_guarantee_is_a_number_not_a_tautology() -> void:
	(
		assert_float(LootInk.MIN_CONTRAST)
		. override_failure_message(
			(
				(
					"LootInk.MIN_CONTRAST is %.2f; the ink tests measure against this same "
					+ "constant, so lowering it lowers the guarantee with them"
				)
				% LootInk.MIN_CONTRAST
			)
		)
		. is_greater_equal(3.0)
	)


func test_the_ink_and_its_ring_clear_every_surface_as_the_layer_draws_it() -> void:
	GameState.settings[LightingProfile.SETTING_QUALITY] = LightingProfile.Quality.HIGH
	for theme: String in THEMES:
		var p := _palette(theme)
		var surfaces := LootInk.surfaces_as_drawn(p)
		assert_int(surfaces.size()).is_equal(ThemePalette.WORLD_SURFACES.size())
		for role: String in ThemePalette.WORLD_ROLES:
			var ink := p.world_color(StringName(role))
			var halo := LootInk.halo_for(ink, p)
			for i in range(surfaces.size()):
				var best := ThemePalette.contrast_ratio(ink, surfaces[i])
				if LootInk.has_halo(halo):
					best = maxf(best, ThemePalette.contrast_ratio(halo, surfaces[i]))
				(
					assert_float(best)
					. override_failure_message(
						(
							"%s: %s on a drawn %s reads %.2f:1 (ink %s, ring %s)"
							% [
								theme,
								role,
								ThemePalette.WORLD_SURFACES[i],
								best,
								ink.to_html(false),
								halo.to_html(true),
							]
						)
					)
					. is_greater_equal(LootInk.MIN_CONTRAST - EPSILON)
				)


## The ring is not decoration: it is there when it is needed and absent when it is not, so a dark
## theme's drop is the shape it has always been.
func test_a_ring_appears_only_where_one_ink_cannot_carry_every_surface() -> void:
	GameState.settings[LightingProfile.SETTING_QUALITY] = LightingProfile.Quality.HIGH
	for theme: String in THEMES:
		var p := _palette(theme)
		var surfaces := LootInk.surfaces_as_drawn(p)
		for role: String in ThemePalette.WORLD_ROLES:
			var ink := p.world_color(StringName(role))
			var worst := ThemePalette.worst_contrast(ink, surfaces)
			var wants := worst < LootInk.MIN_CONTRAST
			(
				assert_bool(LootInk.has_halo(LootInk.halo_for(ink, p)))
				. override_failure_message(
					(
						"%s: %s reads %.2f:1 at worst on the drawn surfaces, ring %s"
						% [theme, role, worst, "expected" if wants else "not wanted"]
					)
				)
				. is_equal(wants)
			)


## Every light fixture needs one somewhere and no dark fixture does. This is the statement the
## frame check measures, written where it can be read without a compositor.
func test_light_fixtures_need_a_ring_and_dark_ones_do_not() -> void:
	GameState.settings[LightingProfile.SETTING_QUALITY] = LightingProfile.Quality.HIGH
	for theme: String in THEMES:
		var p := _palette(theme)
		var any := false
		for role: String in ThemePalette.WORLD_ROLES:
			if LootInk.has_halo(LootInk.halo_for(p.world_color(StringName(role)), p)):
				any = true
		assert_bool(any).override_failure_message("%s: ring drawn = %s" % [theme, any]).is_equal(
			LIGHT_THEMES.has(theme)
		)


## With the layer off there is no darkness to solve against, so the surfaces are the authored
## ones and a drop is a single colour again - the look this subsystem promises Off is.
func test_the_layer_off_leaves_the_surfaces_and_the_drop_as_authored() -> void:
	GameState.settings[LightingProfile.SETTING_QUALITY] = LightingProfile.Quality.OFF
	for theme: String in THEMES:
		var p := _palette(theme)
		assert_float(LootInk.darkness_for(p)).is_equal_approx(1.0, 0.0001)
		var surfaces := LootInk.surfaces_as_drawn(p)
		for i in range(surfaces.size()):
			var authored := p.get_color(StringName(ThemePalette.WORLD_SURFACES[i]))
			var same := surfaces[i].is_equal_approx(Color(authored.r, authored.g, authored.b))
			(
				assert_bool(same)
				. override_failure_message(
					(
						"%s: %s drawn %s, authored %s"
						% [
							theme,
							ThemePalette.WORLD_SURFACES[i],
							surfaces[i].to_html(false),
							authored.to_html(false),
						]
					)
				)
				. is_true()
			)


## The layer darkens a surface, it never brightens one, so the model can only ever ask a drop for
## more contrast than the authored guard did - never less.
func test_the_drawn_surfaces_are_never_brighter_than_the_authored_ones() -> void:
	GameState.settings[LightingProfile.SETTING_QUALITY] = LightingProfile.Quality.HIGH
	for theme: String in THEMES:
		var p := _palette(theme)
		assert_float(LootInk.darkness_for(p)).is_between(0.0, 1.0)
		var surfaces := LootInk.surfaces_as_drawn(p)
		for i in range(surfaces.size()):
			var authored := p.get_color(StringName(ThemePalette.WORLD_SURFACES[i]))
			assert_float(ThemePalette.relative_luminance(surfaces[i])).is_less_equal(
				ThemePalette.relative_luminance(authored) + EPSILON
			)
