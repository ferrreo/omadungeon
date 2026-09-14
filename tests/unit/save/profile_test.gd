class_name ProfileTest
extends GdUnitTestSuite


func _json_round_trip(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data, "\t"))
	assert_object(parsed).is_not_null()
	return parsed


## A new player starts with the Fighter alone (docs §12). The other three classes are the
## first thing there is to win; before this they were handed over on the first launch and a
## first run earned nothing.
func test_a_new_profile_starts_with_one_class() -> void:
	var profile := Profile.new()
	for id: StringName in [&"fighter", &"fireball", &"thorns"]:
		assert_bool(profile.is_unlocked(id)).override_failure_message(String(id)).is_true()
	for id: StringName in [
		&"ranger",
		&"wizard",
		&"oligarch",
		&"whirlwind",
		&"rm_rf",
		&"reboot",
		&"tiling_wm",
		&"lucky_coin"
	]:
		assert_bool(profile.is_unlocked(id)).override_failure_message(String(id)).is_false()
	var playable := 0
	for id: StringName in [&"fighter", &"ranger", &"wizard", &"oligarch"]:
		if profile.is_unlocked(id):
			playable += 1
	assert_int(playable).is_equal(1)
	assert_int(profile.runs).is_equal(0)
	assert_int(profile.version).is_equal(Profile.VERSION)


func test_unlock_is_idempotent() -> void:
	var profile := Profile.new()
	assert_bool(profile.unlock(&"oligarch")).is_true()
	assert_bool(profile.unlock(&"oligarch")).is_false()
	assert_bool(profile.unlock(&"")).is_false()
	assert_bool(profile.is_unlocked(&"oligarch")).is_true()
	assert_int(profile.unlocks.count(&"oligarch")).is_equal(1)


func test_counters() -> void:
	var profile := Profile.new()
	assert_int(profile.get_counter(&"clowns_killed")).is_equal(0)
	assert_int(profile.add_counter(&"clowns_killed", 3)).is_equal(3)
	assert_int(profile.add_counter(&"clowns_killed")).is_equal(4)
	assert_int(profile.raise_counter(&"best_floor", 3)).is_equal(3)
	assert_int(profile.raise_counter(&"best_floor", 1)).is_equal(3)
	assert_int(profile.get_counter(&"best_floor")).is_equal(3)


func test_round_trip_through_json() -> void:
	var original := Profile.new()
	original.unlock(&"oligarch")
	original.add_counter(&"clowns_killed", 51)
	original.runs = 12
	original.wins = 2
	original.best_floor_per_class["fighter"] = 6
	original.best_floor_per_class["wizard"] = 3
	original.per_theme_wins["gruvbox"] = 2
	original.deaths_by_enemy["honker"] = 4
	var restored := Profile.from_dict(_json_round_trip(original.to_dict()))
	assert_int(restored.version).is_equal(Profile.VERSION)
	assert_bool(restored.is_unlocked(&"oligarch")).is_true()
	assert_bool(restored.is_unlocked(&"whirlwind")).is_false()
	assert_int(restored.unlocks.size()).is_equal(original.unlocks.size())
	assert_int(restored.get_counter(&"clowns_killed")).is_equal(51)
	assert_int(restored.runs).is_equal(12)
	assert_int(restored.wins).is_equal(2)
	assert_int(restored.best_floor(&"fighter")).is_equal(6)
	assert_int(restored.best_floor(&"wizard")).is_equal(3)
	assert_int(restored.best_floor(&"ranger")).is_equal(0)
	assert_int(restored.theme_wins("gruvbox")).is_equal(2)
	assert_int(int(restored.deaths_by_enemy["honker"])).is_equal(4)
	assert_bool(restored.deaths_by_enemy["honker"] is int).is_true()


func test_migrates_from_version_0() -> void:
	var legacy := {
		"unlocks": ["fighter", "oligarch"],
		"counters": {"clowns_killed": 7},
		"runs": 3,
		"wins": 1,
		"best_floors": {"fighter": 4},
		"theme_wins": {"nord": 1},
		"deaths": {"juggler": 2},
	}
	var restored := Profile.from_dict(_json_round_trip(legacy))
	assert_bool(restored.is_unlocked(&"oligarch")).is_true()
	assert_bool(restored.is_unlocked(&"ranger")).is_true()  # defaults are always present
	assert_int(restored.get_counter(&"clowns_killed")).is_equal(7)
	assert_int(restored.runs).is_equal(3)
	assert_int(restored.wins).is_equal(1)
	assert_int(restored.best_floor(&"fighter")).is_equal(4)
	assert_int(restored.theme_wins("nord")).is_equal(1)
	assert_int(int(restored.deaths_by_enemy["juggler"])).is_equal(2)


func test_garbage_yields_fresh_profile() -> void:
	var restored := Profile.from_dict({"version": 42, "unlocks": "nope"})
	assert_object(restored).is_not_null()
	assert_bool(restored.is_unlocked(&"fighter")).is_true()
	assert_int(restored.runs).is_equal(0)
	assert_object(Profile.from_dict({})).is_not_null()
	assert_object(Profile.from_dict({"version": 1, "stats": "x", "counters": 3})).is_not_null()
	assert_object(Profile.from_dict({"stats": "x", "runs": "many"})).is_not_null()
	var odd := Profile.from_dict({"version": 1, "counters": {"a": "7", "b": 2.0}})
	assert_int(odd.get_counter(&"a")).is_equal(7)
	assert_int(odd.get_counter(&"b")).is_equal(2)


func test_only_gated_ids_are_locked_by_default() -> void:
	var profile := Profile.new()
	for id: StringName in AbilityRegistry.ICON_ORDER:
		var expected := not Profile.GATED_UNLOCKS.has(id)
		assert_bool(profile.is_unlocked(id)).override_failure_message(String(id)).is_equal(expected)
	for id: StringName in AbilityRegistry.INNATE_IDS:
		assert_bool(profile.is_unlocked(id)).override_failure_message(String(id)).is_true()
	for id: StringName in [&"fighter", &"some_future_ability"]:
		assert_bool(profile.is_unlocked(id)).override_failure_message(String(id)).is_true()
	for id: StringName in [&"ranger", &"wizard", &"oligarch"]:
		assert_bool(profile.is_unlocked(id)).override_failure_message(String(id)).is_false()
		assert_bool(Profile.is_gated(id)).override_failure_message(String(id)).is_true()
	assert_bool(Profile.is_gated(&"fireball")).is_false()
	assert_array(profile.locked_ids()).contains_exactly_in_any_order(Profile.GATED_UNLOCKS)
	profile.unlock(&"whirlwind")
	assert_int(profile.locked_ids().size()).is_equal(Profile.GATED_UNLOCKS.size() - 1)
	assert_bool(profile.unlock(&"bulwark")).is_false()  # ungated: nothing to unlock


func test_migrate_rejects_a_dictionary_that_is_not_a_profile() -> void:
	# A truncated `{}` or a foreign JSON object must not migrate into a "valid" default
	# profile: SaveManager relies on is_valid() failing so it backs the file up instead.
	for raw: Dictionary in [{}, {"hello": "world"}, {"tracks": [1, 2]}]:
		var migrated := Profile.migrate(raw)
		assert_bool(Profile.is_valid(migrated)).override_failure_message(str(raw)).is_false()
	# A real v0 profile still migrates.
	var v0 := {"unlocks": ["oligarch"], "runs": 3, "best_floors": {"fighter": 4}}
	var upgraded := Profile.migrate(v0)
	assert_bool(Profile.is_valid(upgraded)).is_true()
	var profile := Profile.from_dict(v0)
	assert_int(profile.runs).is_equal(3)
	assert_bool(profile.is_unlocked(&"oligarch")).is_true()
	assert_int(profile.best_floor(&"fighter")).is_equal(4)
