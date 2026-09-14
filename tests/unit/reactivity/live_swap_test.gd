## A theme change mid-run has to reach *everything* that shows theme colour, not just the tile
## layers that already crossfade (docs §3.5). Measured on a built floor: the torch lights, the
## chest glow and the toast that names the theme all follow one `palette_changed`, alongside
## the tiles. (`FloorLightingTest` covers the props and the flame sprites; `UiThemeTest` the
## HUD; `MinimapTest` the minimap.)
class_name LiveSwapTest
extends GdUnitTestSuite

const FROM := "tokyo-night"
const TO := "white"
## Longer than `TileRamp.RETINT_SECONDS`, so every crossfade has landed.
const SETTLE_MS := 800

var _root: FloorRoot
var _toast: Toast


func before_test() -> void:
	# The torch colour the floor draws each frame includes the music's mood
	# (`DungeonLight.torch_color`), so the music lights are pinned to neutral first: a suite
	# that ran before this one may have left a run's crossfade in flight, and a colour taken
	# mid-fade is not the colour the assertion below computes a frame later.
	Music.stop(0.0)
	EventBus.run_ended.emit(false)
	await get_tree().process_frame
	assert_bool(Music.mood_state().is_neutral()).is_true()
	_root = FloorRoot.new()
	add_child(_root)
	_root.build_with_biome(
		RoomsTestFixtures.three_rooms(),
		Biome.load_by_id(&"crypt"),
		null,
		ReactivityFixtures.palette_for(FROM)
	)
	_toast = Toast.new()
	add_child(_toast)


func after_test() -> void:
	_root.clear_floor()
	_root.free()
	_toast.free()
	await get_tree().process_frame


func test_lights_glow_tiles_and_toast_all_follow_one_palette_change() -> void:
	var chest := _root.rooms[0].spawn_chest()
	await get_tree().process_frame
	var lights := _root.torch_lights()
	assert_array(lights).is_not_empty()
	var light_before: Color = lights[0].color
	var energy_before: float = lights[0].energy
	var glow_before := Color(chest.glow.modulate.r, chest.glow.modulate.g, chest.glow.modulate.b)
	var tiles_before := TileRamp.current_colors(_root.material_for_room(0))
	var to := ReactivityFixtures.palette_for(TO)
	EventBus.palette_changed.emit(to)
	await await_millis(SETTLE_MS)
	# The lights swapped to the new theme's turned fire colour and re-scaled to its exposure -
	# through the same contract the floor lights them by, so the expectation cannot drift
	# from the runtime.
	var profile := DungeonLight.resolve()
	var want_light := profile.torch_color(_root.lit_palette())
	assert_str(_root.lit_palette().name).is_equal(TO)
	assert_bool(lights[0].color.is_equal_approx(light_before)).is_false()
	assert_bool(lights[0].color.is_equal_approx(want_light)).is_true()
	assert_float(lights[0].energy).is_not_equal(energy_before)
	# The chest glow crossfaded to the new `loot`.
	var glow_after := Color(chest.glow.modulate.r, chest.glow.modulate.g, chest.glow.modulate.b)
	var want_glow := to.get_color(&"loot")
	assert_bool(glow_after.is_equal_approx(glow_before)).is_false()
	assert_float(_distance(glow_after, Color(want_glow.r, want_glow.g, want_glow.b))).is_less(0.02)
	# The tiles finished their crossfade onto the new lit palette.
	var tiles_after := TileRamp.current_colors(_root.material_for_room(0))
	assert_bool(tiles_after[3].is_equal_approx(tiles_before[3])).is_false()
	assert_bool(tiles_after[3].is_equal_approx(_root.lit_palette().get_color(&"floor"))).is_true()
	# And the toast said which theme it now is.
	assert_str(_toast.current_text()).is_equal(Toast.THEME_PREFIX + TO)


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


## The lighting layer follows the same swap: every wall lantern and every emitter alight
## retints to the new theme's role colour, from the same `palette_changed` as the tiles.
func test_lanterns_and_emitters_follow_the_same_palette_change() -> void:
	var rig := LightRig.of(_root)
	assert_object(rig).is_not_null()
	assert_array(rig.lanterns).is_not_empty()
	var host := Node2D.new()
	_root.add_child(host)
	var emitter := LightEmitter.attach(host, &"frost")
	assert_object(emitter).is_not_null()
	var lantern_before: Color = rig.lanterns[0].light.color
	var emitter_before: Color = emitter.color
	EventBus.palette_changed.emit(ReactivityFixtures.palette_for(TO))
	await await_millis(SETTLE_MS)
	assert_str(_root.lit_palette().name).is_equal(TO)
	var role := rig.profile.lantern_role_for(rig.lanterns[0].kind)
	assert_bool(rig.lanterns[0].light.color.is_equal_approx(lantern_before)).is_false()
	assert_bool(rig.lanterns[0].light.color.is_equal_approx(rig.light_color_for(role))).is_true()
	assert_bool(emitter.color.is_equal_approx(emitter_before)).is_false()
	assert_bool(emitter.color.is_equal_approx(rig.light_color_for(&"cold"))).is_true()
	# The darkness re-read the theme too: a light theme dims less than a dark one.
	assert_float(rig.unlit_level()).is_equal_approx(rig.profile.unlit_level(), 0.0001)
	host.free()
