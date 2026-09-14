class_name RunStateTest
extends GdUnitTestSuite


func _sample() -> RunState:
	var state := RunState.new()
	state.run_seed = 9007199254740993  # > 2^53: must survive JSON as a string
	state.class_id = &"wizard"
	state.floor_index = 4
	state.current_room_id = 7
	state.cleared_room_ids = [0, 1, 3, 7]
	state.hp_fraction = 0.42
	state.gold = 133
	state.potion = 1
	var stats := Stats.new()
	stats.add_primary(&"might", 3)
	stats.add_flat(&"armor", &"item:12", 6.0)
	stats.add_percent(&"damage_fire", &"passive:glass_cannon", 0.4)
	state.stats = stats.to_dict()
	state.equipment = {"weapon": {"uid": 12, "base": "sword", "rarity": 1, "affixes": []}}
	state.abilities = {"actives": [{"id": "fireball", "tier": 2}], "passives": []}
	state.flags = {"altar_used": true, "shop_visited": false}
	state.shield = 12.5
	state.kills = 58
	state.damage_taken = 240
	state.gold_earned = 410
	state.time_played = 812.25
	state.tracks_played = ["Neon Alley", "Beard Dirge"]
	state.starting_passive_pending = true
	state.theme_name = "gruvbox"
	state.rng_states = {&"loot": 123456789012345678}
	return state


func _json_round_trip(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data, "\t"))
	assert_object(parsed).is_not_null()
	return parsed


func test_round_trip_through_json() -> void:
	var original := _sample()
	var restored := RunState.from_dict(_json_round_trip(original.to_dict()))
	assert_object(restored).is_not_null()
	assert_int(restored.version).is_equal(RunState.VERSION)
	assert_int(restored.run_seed).is_equal(original.run_seed)
	assert_str(String(restored.class_id)).is_equal("wizard")
	assert_int(restored.floor_index).is_equal(4)
	assert_int(restored.current_room_id).is_equal(7)
	assert_array(restored.cleared_room_ids).contains_exactly([0, 1, 3, 7])
	assert_float(restored.hp_fraction).is_equal_approx(0.42, 0.0001)
	assert_int(restored.gold).is_equal(133)
	assert_int(restored.potion).is_equal(1)
	assert_float(restored.shield).is_equal_approx(12.5, 0.0001)
	assert_int(restored.kills).is_equal(58)
	assert_int(restored.damage_taken).is_equal(240)
	assert_int(restored.gold_earned).is_equal(410)
	assert_float(restored.time_played).is_equal_approx(812.25, 0.0001)
	assert_array(restored.tracks_played).contains_exactly(["Neon Alley", "Beard Dirge"])
	assert_bool(restored.starting_passive_pending).is_true()
	assert_str(restored.theme_name).is_equal("gruvbox")
	assert_bool(bool(restored.flags["altar_used"])).is_true()
	assert_int(int(restored.equipment["weapon"]["uid"])).is_equal(12)
	assert_str(str(restored.abilities["actives"][0]["id"])).is_equal("fireball")
	assert_int(int(restored.rng_states[&"loot"])).is_equal(123456789012345678)


func test_stats_survive_round_trip() -> void:
	var original := _sample()
	var restored := RunState.from_dict(_json_round_trip(original.to_dict()))
	var stats := Stats.new()
	stats.from_dict(restored.stats)
	assert_int(stats.primary(&"might")).is_equal(3)
	assert_float(stats.get_value(&"armor")).is_equal_approx(6.0, 0.0001)
	assert_float(stats.get_value(&"damage_fire")).is_equal_approx(0.0, 0.0001)
	stats.add_flat(&"damage_fire", &"x", 1.0)
	assert_float(stats.get_value(&"damage_fire")).is_equal_approx(1.4, 0.0001)
	stats.remove_owner(&"item:12")
	assert_float(stats.get_value(&"armor")).is_equal_approx(0.0, 0.0001)


func test_ids_come_back_as_ints_not_floats() -> void:
	var restored := RunState.from_dict(_json_round_trip(_sample().to_dict()))
	for id: Variant in restored.cleared_room_ids:
		assert_bool(id is int).is_true()
	assert_bool(restored.gold is int).is_true()


func test_migrates_from_version_0() -> void:
	var legacy := {
		"seed": 4242,
		"class": "ranger",
		"floor": 2,
		"room": 5,
		"cleared": [0, 2, 5],
		"hp": 0.8,
		"gold": 50,
		"potion": 2,
		"kills": 9,
		"theme": "nord",
	}
	var migrated := RunState.migrate(legacy)
	assert_int(int(migrated["version"])).is_equal(RunState.VERSION)
	assert_bool(RunState.is_valid(migrated)).is_true()
	var state := RunState.from_dict(_json_round_trip(legacy))
	assert_object(state).is_not_null()
	assert_int(state.run_seed).is_equal(4242)
	assert_str(String(state.class_id)).is_equal("ranger")
	assert_int(state.floor_index).is_equal(2)
	assert_int(state.current_room_id).is_equal(5)
	assert_array(state.cleared_room_ids).contains_exactly([0, 2, 5])
	assert_float(state.hp_fraction).is_equal_approx(0.8, 0.0001)
	assert_int(state.gold).is_equal(50)
	assert_int(state.potion).is_equal(2)
	assert_int(state.kills).is_equal(9)
	assert_str(state.theme_name).is_equal("nord")


func test_current_version_is_not_migrated() -> void:
	var data := _sample().to_dict()
	var migrated := RunState.migrate(data)
	assert_dict(migrated).is_equal(data)


func test_rejects_garbage() -> void:
	assert_object(RunState.from_dict({})).is_null()
	assert_object(RunState.from_dict({"version": 1})).is_null()
	assert_object(RunState.from_dict({"version": 1, "seed": "not-a-seed"})).is_null()
	assert_object(RunState.from_dict({"version": 99, "seed": "1"})).is_null()
	assert_object(RunState.from_dict({"version": 1, "seed": "1", "player": "nope"})).is_null()
	assert_object(RunState.from_dict({"version": 1, "seed": "1", "floor_index": -2})).is_null()


func test_minimal_valid_dict_uses_defaults() -> void:
	var state := RunState.from_dict({"version": 1, "seed": "77"})
	assert_object(state).is_not_null()
	assert_int(state.run_seed).is_equal(77)
	assert_str(String(state.class_id)).is_equal("fighter")
	assert_float(state.hp_fraction).is_equal_approx(1.0, 0.0001)
	assert_array(state.cleared_room_ids).is_empty()


func test_seed_and_player_aliases() -> void:
	var state := RunState.new()
	state.seed = 12345
	assert_int(state.run_seed).is_equal(12345)
	state.player = {
		"hp_fraction": 0.5, "gold": 9.0, "potion": "2", "flags": {"x": true}, "shield": 3
	}
	assert_float(state.hp_fraction).is_equal_approx(0.5, 0.0001)
	assert_int(state.gold).is_equal(9)
	assert_int(state.potion).is_equal(2)
	assert_bool(bool(state.flags["x"])).is_true()
	assert_float(state.shield).is_equal_approx(3.0, 0.0001)
	var block: Dictionary = state.player
	assert_dict(block).contains_keys(
		["hp_fraction", "gold", "potion", "stats", "equipment", "abilities", "flags", "shield"]
	)
	assert_dict(block).is_equal(state.to_dict()["player"])
	block["gold"] = 1  # the getter hands out a copy
	assert_int(state.gold).is_equal(9)
	var restored := RunState.from_dict(_json_round_trip(state.to_dict()))
	assert_int(restored.seed).is_equal(12345)
	assert_dict(restored.player).is_equal(state.player)


func test_wrong_typed_blocks_are_tolerated() -> void:
	var state := RunState.from_dict({"version": 1, "seed": "3", "run_stats": "x", "rng_states": 4})
	assert_object(state).is_not_null()
	assert_int(state.kills).is_equal(0)
	assert_dict(state.rng_states).is_empty()
	var legacy := RunState.from_dict({"seed": 3, "player": "x", "cleared": "nope", "stats": 1})
	assert_object(legacy).is_not_null()
	assert_array(legacy.cleared_room_ids).is_empty()
	assert_dict(legacy.stats).is_empty()


func test_to_dict_is_a_deep_copy() -> void:
	var state := _sample()
	var data := state.to_dict()
	data["player"]["flags"]["altar_used"] = false
	data["cleared_room_ids"].append(99)
	assert_bool(bool(state.flags["altar_used"])).is_true()
	assert_array(state.cleared_room_ids).has_size(4)


func test_gen_params_round_trip() -> void:
	# Floor layout depends on the theme profile and music energy, not only on the seed, so
	# the generation inputs travel with the save (see the field's doc comment).
	var state := RunState.new()
	state.run_seed = 11
	state.gen_params = {
		"corridor_wiggle": 0.75,
		"room_size_bias": 0.2,
		"trap_density": 0.4,
		"prop_density": 0.6,
		"biome": "forge",
		"extra_loops": 2,
		"enemy_count_scale": 1.1,
		"music_energy": 0.8,
		"theme_hash": 12345,
	}
	var data := state.to_dict()
	data["gen_params"]["biome"] = "void"  # to_dict() hands out a copy
	assert_str(str(state.gen_params["biome"])).is_equal("forge")
	var restored := RunState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_str(str(restored.gen_params["biome"])).is_equal("forge")
	assert_float(float(restored.gen_params["corridor_wiggle"])).is_equal_approx(0.75, 0.0001)
	assert_int(int(restored.gen_params["theme_hash"])).is_equal(12345)
	# Older saves simply have none: resume falls back to the live theme profile.
	assert_dict(RunState.from_dict({"seed": 3}).gen_params).is_empty()
