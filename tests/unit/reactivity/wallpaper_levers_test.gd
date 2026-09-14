## The wallpaper levers of docs §3.4, each proven end to end from a synthetic image. The
## wallpaper shapes the run and never colours it (docs/GAME_DESIGN.md, decisions log): the
## top-third luminance becomes the floor's light level inside the documented 0.55-1.0 clamp,
## Sobel edge density moves prop density by at most ±0.15, hue spread opens or tightens the
## rooms, chroma moves the hazard density, and the image-path hash breaks ties in the room fill
## choice. The first test in the file is the other side of that rule: not one colour of the
## picture reaches the palette.
class_name WallpaperLeversTest
extends GdUnitTestSuite

const THEME := "tokyo-night"
const SEED := 20250912
## Of 12 seeds, how many must build a different floor under two different wallpapers. Not all
## 12: the archetype roll and the fill-template picks are discrete, so two sets of levers that
## differ can still land on the same draw for a given seed. Two thirds is the bar at which the
## lever is something a player meets rather than a number in a struct - measured at 8.
const MIN_DIFFERING_FLOORS := 7


func _params(wallpaper: WallpaperAnalyzer.Result, floor_index: int = 1) -> GenParams:
	return GenParams.build(
		ReactivityFixtures.profile_for(THEME),
		floor_index,
		ReactivityFixtures.music(0.5, 0.0, "silence"),
		wallpaper
	)


func test_edge_density_moves_prop_density_by_at_most_the_documented_swing() -> void:
	var flat := ReactivityFixtures.flat(Color(0.25, 0.3, 0.4))
	var busy := ReactivityFixtures.striped(Color.BLACK, Color.WHITE)
	assert_float(flat.edge_density).is_equal(0.0)
	assert_float(busy.edge_density).is_greater(0.5)
	var swing := WallpaperAnalyzer.EDGE_SWING
	assert_float(flat.prop_density_delta()).is_equal_approx(-swing, 0.0001)
	assert_float(busy.prop_density_delta()).is_equal_approx(swing, 0.0001)
	var none := _params(null)
	var quiet := _params(flat)
	var cluttered := _params(busy)
	assert_float(cluttered.prop_density).is_greater(quiet.prop_density)
	assert_float(quiet.prop_density).is_less(none.prop_density)
	assert_float(cluttered.prop_density).is_greater(none.prop_density)
	assert_float(absf(cluttered.prop_density - none.prop_density)).is_less_equal(swing + 0.0001)
	assert_float(absf(quiet.prop_density - none.prop_density)).is_less_equal(swing + 0.0001)


func test_edge_density_changes_how_many_props_a_floor_actually_gets() -> void:
	var quiet := _params(ReactivityFixtures.flat(Color(0.25, 0.3, 0.4)))
	var busy := _params(ReactivityFixtures.striped(Color.BLACK, Color.WHITE))
	var quiet_props := 0
	var busy_props := 0
	for offset in range(12):
		for room: FloorData.Room in ReactivityFixtures.generate(quiet, SEED + offset).rooms:
			quiet_props += room.prop_positions.size()
		for room: FloorData.Room in ReactivityFixtures.generate(busy, SEED + offset).rooms:
			busy_props += room.prop_positions.size()
	assert_int(busy_props).is_greater(quiet_props)


func test_top_third_luminance_becomes_the_floor_light_level_inside_the_clamp() -> void:
	var bright := ReactivityFixtures.top_band(Color.WHITE, Color.BLACK, "res://bright.png")
	var dark := ReactivityFixtures.top_band(Color.BLACK, Color.WHITE, "res://dark.png")
	assert_float(bright.ambient_level()).is_equal_approx(WallpaperAnalyzer.AMBIENT_MAX, 0.001)
	assert_float(dark.ambient_level()).is_equal_approx(WallpaperAnalyzer.AMBIENT_MIN, 0.001)
	for wallpaper: WallpaperAnalyzer.Result in [bright, dark]:
		assert_float(wallpaper.ambient_level()).is_between(
			WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX
		)
	# A light theme is pinned to full ambient (docs §3.2).
	assert_float(dark.ambient_level(true)).is_equal_approx(WallpaperAnalyzer.AMBIENT_MAX, 0.001)
	assert_float(_params(dark).ambient).is_equal_approx(WallpaperAnalyzer.AMBIENT_MIN, 0.001)
	assert_float(_params(bright).ambient).is_equal_approx(WallpaperAnalyzer.AMBIENT_MAX, 0.001)


func test_ambient_dims_the_floor_environment_and_leaves_enemies_alone() -> void:
	var root := auto_free(FloorRoot.new()) as FloorRoot
	add_child(root)
	root.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	assert_float(root.ambient_level()).is_between(
		WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX
	)
	var enemy := auto_free(Node2D.new()) as Node2D
	root.get_room(1).add_child(enemy)
	root.set_wallpaper(ReactivityFixtures.top_band(Color.WHITE, Color.BLACK, "res://bright.png"))
	assert_float(root.ambient_level()).is_equal_approx(WallpaperAnalyzer.AMBIENT_MAX, 0.001)
	root.set_wallpaper(ReactivityFixtures.top_band(Color.BLACK, Color.WHITE, "res://dark.png"))
	var level := root.ambient_level()
	assert_float(level).is_equal_approx(WallpaperAnalyzer.AMBIENT_MIN, 0.001)
	# The light lives in the palette the environment materials carry, never in a `modulate`:
	# scaling the drawn pixels divides the ladder out along with the light, which is how the
	# floor came to render at the void's own value. What has to be true is that the floor is
	# actually darker, and that the room is still readable at that level (FloorLightingTest).
	var dark_floor := root.lit_palette().get_color(&"floor")
	var lit := 0
	for node: CanvasItem in root.environment_nodes():
		assert_that(node.modulate).is_equal(Color.WHITE)
		lit += 1
	assert_int(lit).is_greater(3)
	root.set_wallpaper(ReactivityFixtures.top_band(Color.WHITE, Color.BLACK, "res://bright.png"))
	var bright_floor := root.lit_palette().get_color(&"floor")
	(
		assert_float(ThemePalette.relative_luminance(dark_floor))
		. override_failure_message("a dark wallpaper did not darken the floor")
		. is_less(ThemePalette.relative_luminance(bright_floor))
	)
	assert_float(enemy.modulate.r).is_equal_approx(1.0, 0.001)
	root.set_wallpaper(ReactivityFixtures.top_band(Color.BLACK, Color.WHITE, "res://dark.png"))
	# Deriving twice must not compound: the palette always comes off the theme, not off the
	# previously derived one.
	var alt_once: Color = root.environment_palette().get_color(&"floor_alt")
	root.set_wallpaper(ReactivityFixtures.top_band(Color.BLACK, Color.WHITE, "res://dark.png"))
	(
		assert_bool(root.environment_palette().get_color(&"floor_alt").is_equal_approx(alt_once))
		. is_true()
	)


func test_a_live_wallpaper_change_retints_the_floor_without_a_rebuild() -> void:
	var root := auto_free(FloorRoot.new()) as FloorRoot
	add_child(root)
	root.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	var layers := root.built_layers
	root.set_wallpaper(ReactivityFixtures.top_band(Color.WHITE, Color.BLACK, "res://bright.png"))
	assert_float(root.ambient_level()).is_equal_approx(WallpaperAnalyzer.AMBIENT_MAX, 0.001)
	EventBus.desktop_changed.emit(EventBus.DesktopChangeKind.WALLPAPER)
	await get_tree().process_frame
	# Same built layers: a wallpaper change retints, it never regenerates the floor.
	assert_object(root.built_layers).is_same(layers)
	# ...and the floor is back on whatever the live desktop is showing.
	var live := FloorRoot.live_wallpaper()
	var expected := WallpaperAnalyzer.AMBIENT_MAX if live == null else live.ambient_level()
	assert_float(root.ambient_level()).is_equal_approx(expected, 0.001)


func test_the_wallpaper_supplies_no_colour_to_the_dungeon_at_all() -> void:
	var palette := ReactivityFixtures.palette_for(THEME)
	var orange := ReactivityFixtures.flat(Color(0.9, 0.35, 0.1), "res://orange.png")
	assert_array(orange.accents()).is_not_empty()
	var derived := palette.derive_environment()
	# Not one of the wallpaper's colours may reach the prop pool...
	for c: Color in derived.prop_pool:
		for a: Color in orange.accents():
			(
				assert_float(Vector3(c.r, c.g, c.b).distance_to(Vector3(a.r, a.g, a.b)))
				. override_failure_message(
					"a wallpaper colour (#%s) reached the prop pool" % a.to_html(false)
				)
				. is_greater(0.05)
			)
	# ...and no palette role may differ from the theme's own by so much as a rounding step.
	for role: StringName in derived.colors:
		(
			assert_bool(derived.get_color(role).is_equal_approx(palette.get_color(role)))
			. override_failure_message(
				(
					"`%s` is #%s on the theme and #%s after deriving an environment"
					% [
						role,
						palette.get_color(role).to_html(false),
						derived.get_color(role).to_html(false)
					]
				)
			)
			. is_true()
		)


func test_two_wallpapers_build_two_different_floors_from_one_seed() -> void:
	# The other half of the owner's rule: the wallpaper lost the colours, so it has to be
	# visibly alive as a generation lever. Same theme, same track, same seed, two pictures.
	var quiet := ReactivityFixtures.flat(Color(0.25, 0.3, 0.4), "res://one.png")
	var loud := ReactivityFixtures.striped(Color("#d94f2b"), Color("#2b6bd9"), "res://two.png")
	var a := _params(quiet)
	var b := _params(loud)
	assert_float(a.wallpaper_variety).is_not_equal(b.wallpaper_variety)
	var differing := 0
	for offset in range(12):
		var left := ReactivityFixtures.floor_signature(
			ReactivityFixtures.generate(a, SEED + offset)
		)
		var right := ReactivityFixtures.floor_signature(
			ReactivityFixtures.generate(b, SEED + offset)
		)
		if left != right:
			differing += 1
	(
		assert_int(differing)
		. override_failure_message(
			(
				(
					"two wallpapers built the same floor on %d of 12 seeds - the wallpaper gave up "
					+ "the colours and has to earn its keep in the generator"
				)
				% (12 - differing)
			)
		)
		. is_greater_equal(MIN_DIFFERING_FLOORS)
	)
	# ...and deterministically so: the same wallpaper twice is the same floor.
	(
		assert_str(
			ReactivityFixtures.floor_signature(ReactivityFixtures.generate(_params(loud), SEED))
		)
		. is_equal(ReactivityFixtures.floor_signature(ReactivityFixtures.generate(b, SEED)))
	)


func test_hue_spread_and_chroma_move_the_room_shape_and_the_hazards() -> void:
	var monochrome := ReactivityFixtures.flat(Color("#6b6f52"), "res://mono.png")
	var many := ReactivityFixtures.striped(Color("#d94f2b"), Color("#2b6bd9"), "res://many.png")
	assert_float(monochrome.hue_spread()).is_less(0.1)
	assert_float(many.hue_spread()).is_greater(0.3)
	var tight := _params(monochrome)
	var open := _params(many)
	assert_float(open.room_size_bias).is_greater(tight.room_size_bias)
	# The hazard lever is chroma, and it moves the trap density the same bounded way.
	var grey := ReactivityFixtures.flat(Color("#6e6e6e"), "res://grey.png")
	var vivid := ReactivityFixtures.flat(Color("#e02020"), "res://vivid.png")
	assert_float(grey.colour_energy()).is_less(0.1)
	assert_float(vivid.colour_energy()).is_greater(0.9)
	var push := GenParams.WALLPAPER_HAZARD_PUSH
	assert_float(_params(vivid).trap_density).is_greater(_params(grey).trap_density)
	assert_float(_params(vivid).trap_density - _params(grey).trap_density).is_less_equal(
		2.0 * push + 0.0001
	)


func test_the_wallpaper_seed_breaks_ties_in_room_fill_choice() -> void:
	var base := ReactivityFixtures.flat(Color(0.3, 0.3, 0.35), "res://one.png")
	var other := ReactivityFixtures.reseeded(base, "res://two.png")
	assert_int(other.seed_hash).is_not_equal(base.seed_hash)
	var a := _params(base)
	var b := _params(other)
	# Every generation input except the tie-break hash is identical.
	assert_float(b.prop_density).is_equal_approx(a.prop_density, 0.0001)
	assert_float(b.trap_density).is_equal_approx(a.trap_density, 0.0001)
	assert_float(b.corridor_wiggle).is_equal_approx(a.corridor_wiggle, 0.0001)
	assert_int(b.fill_bias_hash).is_not_equal(a.fill_bias_hash)
	var differing := 0
	for offset in range(12):
		var left := ReactivityFixtures.fill_templates(ReactivityFixtures.generate(a, SEED + offset))
		var right := ReactivityFixtures.fill_templates(
			ReactivityFixtures.generate(b, SEED + offset)
		)
		if left != right:
			differing += 1
	(
		assert_int(differing)
		. override_failure_message(
			(
				(
					"the wallpaper seed moved a fill template on only %d of 12 floors - a ±30%% "
					+ "weight nudge that never wins a roll is not a lever"
				)
				% differing
			)
		)
		. is_greater(2)
	)


func test_turning_wallpaper_influence_off_leaves_generation_exactly_as_it_was() -> void:
	var profile := ReactivityFixtures.profile_for(THEME)
	var with_none := GenParams.build(profile, 3, MusicProfile.silent(), null)
	var legacy := GenParams.from_profile(profile, 3)
	assert_int(with_none.wallpaper_seed).is_equal(0)
	assert_int(with_none.fill_bias_hash).is_equal(profile.theme_hash)
	assert_float(with_none.prop_density).is_equal_approx(legacy.prop_density, 0.0001)
	assert_float(with_none.corridor_wiggle).is_equal_approx(legacy.corridor_wiggle, 0.0001)
	(
		assert_str(ReactivityFixtures.floor_signature(ReactivityFixtures.generate(with_none, SEED)))
		. is_equal(ReactivityFixtures.floor_signature(ReactivityFixtures.generate(legacy, SEED)))
	)
