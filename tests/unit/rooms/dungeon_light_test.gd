## The dungeon's own light sources (docs §14: "simple 2D light on player + point lights on
## torches/lava"). Until this suite existed the player was the only light in the game: a
## `grep` for `PointLight2D` over the whole project returned one hit, on `player.tscn`, and
## every wall torch was a flat sprite that cast nothing on the brick beside it.
##
## Two halves, and they pull against each other, so both are asserted here:
##   * torches light and warm the room, in the theme's own fire colour;
##   * they do it *on top of* the palette lighting model, never instead of it - the materials
##     still carry the full readable ladder and no environment node is dimmed to make room.
class_name DungeonLightTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]

var _floors: Array[FloorRoot] = []


func after_test() -> void:
	for root: FloorRoot in _floors:
		if is_instance_valid(root):
			root.clear_floor()
			root.free()
	_floors.clear()
	GameState.settings.erase(Accessibility.SETTING_REDUCED_FLASH)
	GameState.settings.erase(Accessibility.SETTING_REDUCE_MOTION)
	await get_tree().process_frame
	await get_tree().process_frame


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _floor(theme: String = "tokyo-night") -> FloorRoot:
	var root := FloorRoot.new()
	_floors.append(root)
	add_child(root)
	root.build_with_biome(
		RoomsTestFixtures.three_rooms(), Biome.load_by_id(&"crypt"), null, _palette(theme)
	)
	return root


## Every torch the floor places carries a light. This is the finding, restated as an assertion:
## the decor sprite alone is not a light source.
func test_every_torch_carries_a_point_light() -> void:
	var root := _floor()
	var decor := root.get_node_or_null(^"Decor") as Node2D
	assert_object(decor).is_not_null()
	var torches := 0
	for child: Node in decor.get_children():
		if not String(child.name).begins_with("Torch"):
			continue
		torches += 1
		var light := child.get_node_or_null(^"Light") as PointLight2D
		(
			assert_object(light)
			. override_failure_message("%s casts no light" % child.name)
			. is_not_null()
		)
		assert_object(light.texture).is_not_null()
		assert_float(light.energy).is_greater(0.0)
	assert_int(torches).is_greater(0)
	assert_int(root.torch_lights().size()).is_equal(torches)


## A torch's light is the theme's own fire colour turned part of the way toward the theme's
## accent (`DungeonLight.torch_accent_mix`), so the pool it throws is the desktop's colour and
## not the same orange on every theme - while the flame sprite itself stays on `heat` (see
## `FloorLightingTest`). A greyscale accent turns nothing, and plain fire is what it gets.
func test_torch_light_is_the_theme_fire_colour_turned_toward_its_accent() -> void:
	var profile := DungeonLight.resolve()
	assert_float(profile.torch_accent_mix).is_between(0.2, 0.5)
	for theme: String in THEMES:
		var root := _floor(theme)
		var pal := root.lit_palette()
		var heat := pal.get_color(&"heat")
		var accent := pal.get_color(&"accent")
		var want := profile.torch_role_color(pal)
		assert_that(root.torch_light_color()).is_equal(want)
		var lights := root.torch_lights()
		assert_array(lights).is_not_empty()
		var lit: Color = lights[0].color
		(
			assert_float(TileRamp.hue_distance(lit.h, want.h))
			. override_failure_message(
				(
					"%s: torch light %s is not the turned fire colour %s"
					% [theme, lit.to_html(false), want.to_html(false)]
				)
			)
			. is_less(0.02)
		)
		if accent.s < profile.torch_accent_min_saturation:
			assert_float(TileRamp.hue_distance(want.h, heat.h)).is_less(0.001)
		else:
			# Turned toward the accent by the tuned fraction of the arc between them, and no
			# further: the light is coloured by the desktop, not replaced by its accent.
			var arc := TileRamp.hue_distance(heat.h, accent.h)
			var turned := TileRamp.hue_distance(heat.h, want.h)
			assert_float(turned).is_equal_approx(arc * profile.torch_accent_mix, 0.005)
			assert_float(TileRamp.hue_distance(want.h, accent.h)).is_less(arc)
		# A light is not a surface: it is taken to full value so it can actually light brick.
		assert_float(lit.v).is_greater_equal(0.9)
		root.clear_floor()


## Every theme's torch burns at the same energy, and that energy is the dark exactly undone.
##
## A light theme used to get a gentler one (`torch_light_scale`, 0.4) because an additive pool
## had nowhere to land on a floor that was already near white. The owner's ruling took the
## ambient wash out from under every theme, so a paper dungeon is as dark between its lights as a
## navy one and its lights restore it to paper - there is no headroom problem left to protect,
## and a paper room lit at 0.4 would simply be a dark room that never comes back.
func test_every_theme_burns_its_torches_at_the_dark_undone() -> void:
	var dark := _floor("tokyo-night")
	var pale := _floor("white")
	assert_bool(pale.lit_palette().is_light).is_true()
	assert_float(pale.torch_light_energy()).is_equal_approx(dark.torch_light_energy(), 0.0001)
	var unlit := LightingProfile.resolve().unlit_level()
	(
		assert_float(unlit + pale.torch_light_energy())
		. override_failure_message(
			(
				(
					"a torch restores a surface to x%.3f of the level the theme authored it at; "
					+ "under 1 the lit floor never reaches the theme, over it the pool blows past "
					+ "the exposure the readability ladders were measured at"
				)
				% (unlit + pale.torch_light_energy())
			)
		)
		. is_between(0.95, 1.005)
	)


## The flicker is amplitude, so it goes through the accessibility policy like every other
## pulse in the game: damped under reduced flash, gone under reduce motion, and a floor with no
## flicker left and no music lights to follow stops processing rather than spinning on a
## no-op. (With the music lights on the torches keep processing at zero flicker, because the
## track's mood still moves their colour and level - docs 10.2.)
func test_the_flicker_obeys_the_accessibility_settings() -> void:
	var root := _floor()
	var lights_before: Variant = GameState.settings.get("music_lights", true)
	var full := root.torch_flicker_amount()
	assert_float(full).is_greater(0.0)
	assert_bool(root.is_processing()).is_true()
	GameState.settings[Accessibility.SETTING_REDUCED_FLASH] = true
	var damped := root.torch_flicker_amount()
	assert_float(damped).is_less(full)
	GameState.settings[Accessibility.SETTING_REDUCE_MOTION] = true
	assert_float(root.torch_flicker_amount()).is_equal(0.0)
	root._relight_torches()
	assert_bool(root.is_processing()).is_true()
	GameState.settings["music_lights"] = false
	root._relight_torches()
	assert_bool(root.is_processing()).is_false()
	GameState.settings["music_lights"] = lights_before
	# ...and with the flicker off the lights are still lights.
	for light: PointLight2D in root.torch_lights():
		assert_float(light.energy).is_greater(0.0)


## The other half of the contract. Lights are additive on top of the palette model: no
## environment node is dimmed to make room for them, and the materials still carry the same
## readable ladder they would without a single light in the room.
func test_lights_are_added_to_the_palette_model_not_substituted_for_it() -> void:
	var root := _floor()
	for node: CanvasItem in root.environment_nodes():
		(
			assert_that(node.modulate)
			. override_failure_message("%s is dimmed to make room for the lights" % node.name)
			. is_equal(Color.WHITE)
		)
	var lit := root.lit_palette()
	var unlit := root.environment_palette().light_environment(root.ambient_level())
	for role: String in ThemePalette.ENV_ROLES:
		var key := StringName(role)
		(
			assert_bool(lit.get_color(key).is_equal_approx(unlit.get_color(key)))
			. override_failure_message("the lights moved the %s role" % role)
			. is_true()
		)
	# The room's outline survives, lights or no lights.
	var floor_c := lit.get_color(&"floor")
	assert_float(ThemePalette.contrast_ratio(floor_c, lit.get_color(&"void"))).is_greater_equal(
		ThemePalette.ENV_LIT_FLOOR_VOID_RATIO - 0.001
	)
	assert_float(ThemePalette.contrast_ratio(floor_c, lit.get_color(&"wall"))).is_greater_equal(
		ThemePalette.ENV_LIT_FLOOR_WALL_RATIO - 0.001
	)


## A floor budgets its lights. A forty-room floor would otherwise stack a hundred and fifty
## point lights into one 480x270 viewport for no visible gain.
func test_the_light_budget_is_respected() -> void:
	var root := _floor()
	var profile := DungeonLight.resolve()
	assert_int(profile.torch_max_lights).is_greater(0)
	assert_int(root.torch_lights().size()).is_less_equal(profile.torch_max_lights)


## The shipped tuning resource is the one the floor uses, and a project without it still
## lights its torches (docs §1: content is data, but a missing file is not a crash).
func test_the_light_profile_is_data() -> void:
	var shipped := DungeonLight.load_default()
	assert_object(shipped).is_not_null()
	assert_float(shipped.torch_energy).is_greater(0.0)
	assert_float(shipped.torch_texture_scale).is_greater(0.0)
	var fallback := DungeonLight.new()
	assert_object(DungeonLight.resolve(fallback)).is_same(fallback)
	assert_float(fallback.torch_energy).is_greater(0.0)
	var texture := DungeonLight.make_texture(shipped.light_texture_size)
	assert_int(texture.get_width()).is_equal(shipped.light_texture_size)
