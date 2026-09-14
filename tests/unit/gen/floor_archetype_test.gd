## The floor plan roll (docs 5.1 #1): every archetype turns up, none dominates, a seed is
## still a seed, a forced archetype is honoured, and the choice survives a save.
class_name FloorArchetypeTest
extends GdUnitTestSuite

const SEEDS := 200
const MAX_SHARE := 0.5
const THEMES: Array[String] = ["tokyo-night", "gruvbox", "catppuccin-latte"]


func _params(theme: String, floor_index: int) -> GenParams:
	return GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)


func _generate(theme: String, seed_value: int, floor_index: int) -> FloorData:
	var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
	return FloorGenerator.generate(_params(theme, floor_index), rng)


func test_every_archetype_appears_and_none_dominates() -> void:
	# Pooled over three fixtures and three floors, since the levers deliberately tilt the
	# roll per theme and per biome: the promise is variety within a run, not a flat die.
	var counts: Dictionary = {}
	var total := 0
	for theme: String in THEMES:
		for floor_index: int in [0, 3, 6]:
			for i in range(SEEDS / 3):
				var data := _generate(theme, 1000 + i * 17 + floor_index, floor_index)
				counts[data.archetype] = int(counts.get(data.archetype, 0)) + 1
				total += 1
	for id: StringName in FloorArchetype.ALL:
		var share := float(int(counts.get(id, 0))) / float(total)
		(
			assert_float(share)
			. override_failure_message("archetype %s rolled %.2f of floors" % [id, share])
			. is_between(0.02, MAX_SHARE)
		)


func test_same_seed_same_archetype_and_layout() -> void:
	for seed_value in range(20):
		var a := _generate("tokyo-night", seed_value, seed_value % 9)
		var b := _generate("tokyo-night", seed_value, seed_value % 9)
		assert_str(String(a.archetype)).is_equal(String(b.archetype))
		assert_int(a.layout_hash()).is_equal(b.layout_hash())
		for i in range(a.rooms.size()):
			assert_str(String(a.rooms[i].shape)).is_equal(String(b.rooms[i].shape))


func test_a_forced_archetype_is_honoured_on_every_floor() -> void:
	for id: StringName in FloorArchetype.ALL:
		for floor_index in range(9):
			var params := _params("nord", floor_index)
			params.archetype = id
			var rng := RunRng.new(77 + floor_index).floor_stream(&"gen", floor_index)
			var data := FloorGenerator.generate(params, rng)
			assert_str(String(data.archetype)).is_equal(String(id))
			assert_bool(data.is_fallback).is_false()
			assert_array(FloorValidator.validate(data)).is_empty()


func test_the_levers_tilt_the_roll_without_ruling_anything_out() -> void:
	var tight := _params("gruvbox", 0)
	tight.room_size_bias = ThemeProfile.ROOM_SIZE_BIAS_MIN
	tight.corridor_wiggle = 0.1
	var open := _params("catppuccin-latte", 0)
	open.room_size_bias = ThemeProfile.ROOM_SIZE_BIAS_MAX
	open.corridor_wiggle = 0.9
	var w_tight := FloorArchetype.weights(tight)
	var w_open := FloorArchetype.weights(open)
	assert_float(float(w_tight[FloorArchetype.GRID])).is_greater(float(w_open[FloorArchetype.GRID]))
	assert_float(float(w_open[FloorArchetype.CAVERN])).is_greater(
		float(w_tight[FloorArchetype.CAVERN])
	)
	for id: StringName in FloorArchetype.ALL:
		assert_float(float(w_tight[id])).is_greater(0.0)
		assert_float(float(w_open[id])).is_greater(0.0)


func test_the_biome_has_a_say() -> void:
	var crypt := _params("nord", 0)
	var void_floor := _params("nord", 7)
	assert_str(String(void_floor.biome)).is_equal("void")
	var w_crypt := FloorArchetype.weights(crypt)
	var w_void := FloorArchetype.weights(void_floor)
	assert_float(float(w_void[FloorArchetype.CAVERN])).is_greater(
		float(w_crypt[FloorArchetype.CAVERN])
	)
	assert_float(float(w_crypt[FloorArchetype.WINDING])).is_greater(
		float(w_void[FloorArchetype.WINDING])
	)


func test_resolve_spends_one_draw_whether_forced_or_not() -> void:
	var free := _params("nord", 1)
	var forced := _params("nord", 1)
	forced.archetype = FloorArchetype.RING
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 5
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 5
	FloorArchetype.resolve(free, rng_a)
	var picked := FloorArchetype.resolve(forced, rng_b)
	assert_str(String(picked.id)).is_equal("ring")
	assert_int(rng_a.randi()).is_equal(rng_b.randi())


func test_the_archetype_survives_the_save_block() -> void:
	var params := _params("tokyo-night", 4)
	params.archetype = FloorArchetype.HUB
	var saved := FloorRestore.gen_params_to_dict(params)
	assert_str(str(saved["archetype"])).is_equal("hub")
	var restored := FloorRestore.gen_params_for(4, saved)
	assert_str(String(restored.archetype)).is_equal("hub")
	var a := FloorGenerator.generate(params, RunRng.new(9).floor_stream(&"gen", 4))
	var b := FloorGenerator.generate(restored, RunRng.new(9).floor_stream(&"gen", 4))
	assert_int(a.layout_hash()).is_equal(b.layout_hash())


func test_by_id_rejects_unknown_ids() -> void:
	assert_object(FloorArchetype.by_id(&"")).is_null()
	assert_object(FloorArchetype.by_id(&"castle")).is_null()
	for id: StringName in FloorArchetype.ALL:
		assert_str(String(FloorArchetype.by_id(id).id)).is_equal(String(id))
