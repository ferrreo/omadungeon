## HazardSpawner: EventBus.spawn_hazard -> TrapBase under the configured parent, group "hazard".
class_name HazardSpawnerTest
extends GdUnitTestSuite


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func test_spawns_on_signal_under_parent() -> void:
	var world := auto_free(Node2D.new()) as Node2D
	world.name = "World"
	world.position = Vector2(10, 10)
	add_child(world)
	var spawner := auto_free(HazardSpawner.new()) as HazardSpawner
	add_child(spawner)
	spawner.parent_path = spawner.get_path_to(world)
	var spawned: Array[TrapBase] = []
	spawner.hazard_spawned.connect(func(trap: TrapBase) -> void: spawned.append(trap))
	EventBus.spawn_hazard.emit(&"kernel_spike", Vector2(100, 100), 0.4)
	assert_int(spawned.size()).is_equal(1)
	var trap := spawned[0]
	assert_object(trap.get_parent()).is_same(world)
	assert_bool(trap.is_in_group(&"hazard")).is_true()
	assert_vector(trap.global_position).is_equal(Vector2(100, 100))
	assert_float(trap.active_time).is_equal(0.4)
	assert_int(spawner.active_hazards().size()).is_equal(1)
	await _frames(80)
	assert_bool(is_instance_valid(trap)).is_false()
	assert_int(spawner.active_hazards().size()).is_equal(0)


func test_unknown_kind_is_ignored() -> void:
	var spawner := auto_free(HazardSpawner.new()) as HazardSpawner
	add_child(spawner)
	EventBus.spawn_hazard.emit(&"not_a_trap", Vector2.ZERO, 1.0)
	assert_int(spawner.active_hazards().size()).is_equal(0)


func test_floor_start_clears_hazards() -> void:
	var spawner := auto_free(HazardSpawner.new()) as HazardSpawner
	add_child(spawner)
	spawner.spawn(&"ricer_trap", Vector2(50, 50), 5.0)
	spawner.spawn(&"fire_vent", Vector2(80, 50), 5.0)
	assert_int(spawner.active_hazards().size()).is_equal(2)
	EventBus.floor_started.emit(1)
	await _frames(2)
	assert_int(spawner.active_hazards().size()).is_equal(0)
	assert_int(get_tree().get_nodes_in_group(&"hazard").size()).is_equal(0)
