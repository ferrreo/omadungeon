## TrapRegistry / TrapDef data tests.
class_name TrapRegistryTest
extends GdUnitTestSuite

const ALL_KINDS: Array[StringName] = [
	&"spike_floor",
	&"arrow_wall",
	&"fire_vent",
	&"pit",
	&"pressure_plate",
	&"ice_slide",
	&"laser_grid",
	&"mimic_chest",
	&"ricer_trap",
	&"kernel_spike",
]


func test_registry_loads_and_has_all_kinds() -> void:
	var registry := TrapRegistry.load_default()
	assert_object(registry).is_not_null()
	for kind: StringName in ALL_KINDS:
		assert_bool(registry.has_kind(kind)).override_failure_message("missing " + kind).is_true()
		var def := registry.get_def(kind)
		assert_object(def.scene).is_not_null()
		assert_object(def.script_class).is_not_null()
	assert_int(registry.kinds().size()).is_equal(ALL_KINDS.size())


func test_instantiate_every_kind_produces_matching_trap() -> void:
	for kind: StringName in ALL_KINDS:
		var trap := TrapRegistry.instantiate(kind, Vector2(32, 48))
		assert_object(trap).override_failure_message("cannot instantiate " + kind).is_not_null()
		auto_free(trap)
		assert_str(String(trap.kind)).is_equal(String(kind))
		assert_vector(trap.position).is_equal(Vector2(32, 48))
		assert_object(trap.def).is_not_null()


func test_def_numbers_reach_the_node() -> void:
	var trap := auto_free(TrapRegistry.instantiate(&"spike_floor", Vector2.ZERO)) as TrapBase
	assert_float(trap.damage).is_equal(15.0)
	assert_float(trap.telegraph_time).is_equal(0.5)
	assert_float(trap.active_time).is_equal(0.4)
	assert_float(trap.cooldown_time).is_equal(2.0)
	var laser := auto_free(TrapRegistry.instantiate(&"laser_grid", Vector2.ZERO)) as TrapBase
	assert_float(laser.active_time).is_equal(1.0)
	assert_float(laser.telegraph_time + laser.cooldown_time).is_equal_approx(1.5, 0.001)


func test_extra_overrides_survive_ready() -> void:
	var trap := TrapRegistry.instantiate(
		&"spike_floor", Vector2.ZERO, {"damage": 99.0, "enemies_immune": true}
	)
	add_child(auto_free(trap))
	assert_float(trap.damage).is_equal(99.0)
	assert_bool(trap.enemies_immune).is_true()


func test_biome_filtering_and_hazards() -> void:
	var registry := TrapRegistry.load_default()
	var void_kinds: Array[StringName] = []
	for def: TrapDef in registry.defs_for_biome(&"void"):
		void_kinds.append(def.id)
	assert_array(void_kinds).contains([&"laser_grid", &"pit", &"spike_floor"])
	assert_array(void_kinds).not_contains([&"ricer_trap", &"kernel_spike", &"ice_slide"])
	var crypt_kinds: Array[StringName] = []
	for def: TrapDef in registry.defs_for_biome(&"crypt"):
		crypt_kinds.append(def.id)
	assert_array(crypt_kinds).contains([&"spike_floor"])
	assert_array(crypt_kinds).not_contains([&"laser_grid"])
	assert_bool(registry.get_def(&"kernel_spike").is_hazard).is_true()
	assert_bool(registry.get_def(&"ricer_trap").enemies_immune).is_true()


func test_pick_is_deterministic() -> void:
	var registry := TrapRegistry.load_default()
	var a := RandomNumberGenerator.new()
	a.seed = 777
	var b := RandomNumberGenerator.new()
	b.seed = 777
	for _i in range(20):
		assert_str(String(registry.pick(&"void", a).id)).is_equal(
			String(registry.pick(&"void", b).id)
		)
	assert_object(registry.pick(&"nowhere", a)).is_null()  # unknown biome allows nothing


func test_biome_resources_and_defs_agree() -> void:
	var registry := TrapRegistry.load_default()
	for biome_id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(biome_id)
		var eligible: Array[StringName] = []
		for def: TrapDef in registry.defs_for_biome(biome_id):
			eligible.append(def.id)
		for kind: StringName in biome.trap_kinds:
			(
				assert_bool(registry.has_kind(kind))
				. override_failure_message("biome %s lists unknown trap '%s'" % [biome_id, kind])
				. is_true()
			)
			(
				assert_array(eligible)
				. override_failure_message(
					"biome %s lists '%s' but the registry filters it out" % [biome_id, kind]
				)
				. contains([kind])
			)
		for kind: StringName in eligible:
			(
				assert_bool(biome.allows_trap(kind))
				. override_failure_message(
					"registry offers '%s' in %s, which the biome does not list" % [kind, biome_id]
				)
				. is_true()
			)


func test_hazards_are_never_offered_to_the_generator() -> void:
	var registry := TrapRegistry.load_default()
	for biome_id: StringName in Biome.ALL_IDS:
		for def: TrapDef in registry.defs_for_biome(biome_id):
			(
				assert_bool(def.is_hazard)
				. override_failure_message("hazard '%s' offered in %s" % [def.id, biome_id])
				. is_false()
			)
	var with_hazards: Array[StringName] = []
	for def: TrapDef in registry.defs_for_biome(&"void", true):
		with_hazards.append(def.id)
	assert_array(with_hazards).contains([&"laser_grid", &"kernel_spike", &"ricer_trap"])
