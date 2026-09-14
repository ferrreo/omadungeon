class_name TinkerersTest
extends GdUnitTestSuite

## Every EventBus handler this suite connects goes through the probe, which hands them all back
## in after_test: an autoload signal outlives the suite, so a leaked lambda silently changes
## the result of whatever runs next (see tests/unit/tools/test_isolation_test.gd).
var _probe := EventBusProbe.new()


func after_test() -> void:
	_probe.release()


func test_ricer_drops_trap_hazard() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var ricer := EnemyTestHelpers.spawn(&"ricer", root, Vector2(100, 100)) as Ricer
	var hazards: Array[StringName] = []
	_probe.watch(
		EventBus.spawn_hazard,
		func(kind: StringName, _pos: Vector2, duration: float) -> void:
			hazards.append(kind)
			assert_float(duration).is_equal(8.0)
	)
	await get_tree().physics_frame
	ricer.drop_trap()
	_probe.release()
	assert_array(hazards).contains([&"ricer_trap"])
	assert_int(ricer.traps_dropped).is_equal(1)


func test_distro_hopper_hops_within_range() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var hopper := EnemyTestHelpers.spawn(&"distro_hopper", root, Vector2(100, 100)) as DistroHopper
	await get_tree().physics_frame
	var start := hopper.global_position
	hopper.hop()
	assert_int(hopper.hops).is_equal(1)
	var moved := hopper.global_position.distance_to(start)
	assert_float(moved).is_between(16.0, 96.5)


func test_config_gremlin_drops_stolen_stat_on_death() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var gremlin := (
		EnemyTestHelpers.spawn(&"config_gremlin", root, Vector2(100, 100)) as ConfigGremlin
	)
	var orbs: Array[int] = []
	_probe.watch(
		EventBus.spawn_pickup,
		func(kind: StringName, _pos: Vector2, amount: int) -> void:
			if kind == &"stat_orb":
				orbs.append(amount)
	)
	await get_tree().physics_frame
	gremlin.stolen_stat = &"arcana"
	EnemyTestHelpers.hit(gremlin, 9999.0)
	_probe.release()
	assert_int(orbs.size()).is_equal(1)
	assert_int(orbs[0]).is_equal(Stats.PRIMARY.find(&"arcana"))


func test_dotfile_golem_splits_into_three_gremlins() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var golem := EnemyTestHelpers.spawn(&"dotfile_golem", root, Vector2(100, 100))
	await get_tree().physics_frame
	EnemyTestHelpers.hit(golem, 99999.0)
	var gremlins := 0
	for child: Node in root.get_children():
		var enemy := child as EnemyBase
		if enemy != null and enemy != golem:
			gremlins += 1
			assert_that(enemy.def.id).is_equal(&"config_gremlin")
	assert_int(gremlins).is_equal(3)
