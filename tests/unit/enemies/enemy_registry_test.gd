class_name EnemyRegistryTest
extends GdUnitTestSuite

const EXPECTED_IDS: Array[StringName] = [
	&"juggler",
	&"honker",
	&"balloon_clown",
	&"mime",
	&"clown_car",
	&"manpage_hurler",
	&"beard_warden",
	&"rant_priest",
	&"vim_zealot",
	&"kernel_panic",
	&"ricer",
	&"distro_hopper",
	&"config_gremlin",
	&"dotfile_golem",
]

const EXPECTED_BOSS_IDS: Array[StringName] = [&"ringmaster", &"elder_greybeard", &"the_suit"]


func test_registry_has_14_complete_defs() -> void:
	var registry := EnemyTestHelpers.registry()
	assert_object(registry).is_not_null()
	assert_int(registry.regular_defs().size()).is_equal(14)
	var seen: Dictionary = {}
	for def: EnemyDef in registry.regular_defs():
		assert_object(def).is_not_null()
		(
			assert_bool(seen.has(def.id))
			. override_failure_message("duplicate id %s" % def.id)
			. is_false()
		)
		seen[def.id] = true
		assert_object(def.scene).override_failure_message("%s has no scene" % def.id).is_not_null()
		(
			assert_object(def.texture)
			. override_failure_message("%s has no texture" % def.id)
			. is_not_null()
		)
		assert_float(def.max_hp).is_between(20.0, 70.0)
		assert_float(def.damage).is_between(5.0, 14.0)
		assert_float(def.move_speed).is_between(30.0, 90.0)
		assert_float(def.cost).is_greater(0.0)
	for id: StringName in EXPECTED_IDS:
		assert_object(registry.find(id)).override_failure_message("missing %s" % id).is_not_null()
	assert_object(registry.find(&"nope")).is_null()


func test_elites_flagged_and_scaled() -> void:
	var registry := EnemyTestHelpers.registry()
	var elites := registry.candidates(0, true)
	assert_int(elites.size()).is_equal(3)
	var car := registry.find(&"clown_car")
	var curve := DifficultyCurve.shared()
	assert_float(car.scaled_hp(0)).is_equal(car.max_hp * curve.elite_hp_multiplier)
	assert_float(car.scaled_hp(2)).is_equal_approx(
		car.max_hp * curve.elite_hp_multiplier * curve.hp_multiplier(2), 0.01
	)
	assert_int(car.sprite_size).is_equal(32)
	assert_int(car.summon_defs.size()).is_equal(4)
	assert_int(registry.find(&"dotfile_golem").summon_defs.size()).is_equal(1)
	assert_float(registry.find(&"honker").param(&"charge_speed", 1.0)).is_equal(230.0)
	assert_float(registry.find(&"honker").param(&"missing", 9.0)).is_equal(9.0)


func test_registry_carries_the_three_bosses() -> void:
	var registry := EnemyTestHelpers.registry()
	var boss_ids: Array[StringName] = []
	for def: EnemyDef in registry.boss_defs():
		boss_ids.append(def.id)
		(
			assert_bool(def.is_boss)
			. override_failure_message("%s is not flagged as a boss" % def.id)
			. is_true()
		)
		assert_object(def.scene).override_failure_message("%s has no scene" % def.id).is_not_null()
		assert_float(def.max_hp).override_failure_message("%s hp" % def.id).is_greater(200.0)
	for id: StringName in EXPECTED_BOSS_IDS:
		assert_bool(boss_ids.has(id)).override_failure_message("missing boss %s" % id).is_true()
	assert_int(registry.boss_defs().size()).is_equal(EXPECTED_BOSS_IDS.size())
