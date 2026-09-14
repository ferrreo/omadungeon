class_name PickupsTest
extends GdUnitTestSuite

## Scene parts of the hitbox-kill tests, held as fields so the awaited half can be a plain
## method: `assert_error()` takes a Callable, and a multi-line lambda cannot carry the loop.
var _root: Node2D
var _spawner: PickupSpawner
var _victim: EnemyBase
var _hitbox: Hitbox


func _setup_scene() -> Array:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var spawner := PickupSpawner.new()
	root.add_child(spawner)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(100, 100)
	return [root, spawner, player]


func test_gold_homes_to_player_and_grants_gold() -> void:
	var parts := _setup_scene()
	var spawner: PickupSpawner = parts[1]
	var player: EnemyTestPlayer = parts[2]
	var pickups := spawner.spawn(&"gold", Vector2(150, 100), 7)
	assert_int(pickups.size()).is_between(1, 5)
	var sum := 0
	for p: PickupBase in pickups:
		sum += p.amount
	assert_int(sum).is_equal(7)
	for _i in range(45):
		await get_tree().physics_frame
	assert_int(player.gold).override_failure_message("far coins should not be collected").is_equal(
		0
	)
	player.global_position = Vector2(150, 100)
	for _i in range(60):
		await get_tree().physics_frame
	assert_int(player.gold).is_equal(7)
	for p: PickupBase in pickups:
		assert_bool(not is_instance_valid(p) or p.is_queued_for_deletion()).is_true()


func test_event_bus_spawns_heart_and_stat_orb() -> void:
	var parts := _setup_scene()
	var spawner: PickupSpawner = parts[1]
	var player: EnemyTestPlayer = parts[2]
	player.health.take_damage(
		DamageInfo.create(50.0, [DamageInfo.TAG_TRUE], null, Layers.Team.NEUTRAL)
	)
	var before := player.health.hp
	EventBus.spawn_pickup.emit(&"heart", Vector2(104, 100), 15)
	EventBus.spawn_pickup.emit(&"stat_orb", Vector2(96, 100), Stats.PRIMARY.find(&"swiftness"))
	# Pickups enter the tree on the next deferred flush (see PickupSpawner._place).
	await get_tree().process_frame
	assert_int(spawner.get_child_count()).is_equal(2)
	for _i in range(60):
		await get_tree().physics_frame
	assert_float(player.health.hp).is_equal_approx(before + 15.0, 0.01)
	assert_int(int(player.stats_added.get(&"swiftness", 0))).is_equal(1)
	assert_int(spawner.get_child_count()).is_equal(0)


func test_pickup_radius_uses_player_stat() -> void:
	var parts := _setup_scene()
	var player: EnemyTestPlayer = parts[2]
	assert_float(PickupBase.pickup_radius_of(player)).is_equal_approx(24.0, 0.01)
	player.stats.add_flat(&"pickup_radius", &"test", 40.0)
	assert_float(PickupBase.pickup_radius_of(player)).is_equal_approx(64.0, 0.01)
	var plain := auto_free(Node2D.new()) as Node2D
	assert_float(PickupBase.pickup_radius_of(plain)).is_equal_approx(24.0, 0.01)


func test_pickups_are_cleared_when_a_new_floor_starts() -> void:
	var parts := _setup_scene()
	var spawner: PickupSpawner = parts[1]
	spawner.spawn(&"gold", Vector2(400, 400), 9)
	spawner.spawn(&"heart", Vector2(420, 400), 15)
	await get_tree().process_frame
	assert_int(spawner.get_child_count()).is_greater(1)
	EventBus.floor_started.emit(3)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(spawner.get_child_count()).is_equal(0)


## The bug this guards: a gremlin killed inside a `Hitbox` overlap callback dropped its coins
## while the physics server was flushing queries, which refuses the pickup's monitoring state
## and its collision shape - three engine errors per death and a pickup the server never got
## a shape for. The kill has to land on a *signal* (the enemy is moved into a live hitbox),
## not on `activate()`'s own sweep, because only the signal runs inside the flush.
func _kill_in_overlap_callback() -> void:
	_hitbox.activate(2.0)
	await get_tree().physics_frame
	_victim.global_position = _hitbox.global_position
	for _i in range(6):
		await get_tree().physics_frame


func _setup_hitbox_kill() -> void:
	var parts := _setup_scene()
	_root = parts[0]
	_spawner = parts[1]
	_victim = EnemyTestHelpers.spawn(&"config_gremlin", _root, Vector2(400, 400))
	_victim.set_physics_process(false)
	_hitbox = Hitbox.new()
	_hitbox.team = Layers.Team.PLAYER
	_hitbox.damage = 9999.0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	_hitbox.add_child(shape)
	_root.add_child(_hitbox)
	_hitbox.global_position = Vector2(150, 100)


func test_a_kill_inside_a_hit_callback_logs_no_engine_error() -> void:
	_setup_hitbox_kill()
	await assert_error(_kill_in_overlap_callback).is_success()


func test_coins_dropped_inside_a_hit_callback_keep_a_live_collider() -> void:
	_setup_hitbox_kill()
	await _kill_in_overlap_callback()
	var coins: Array[PickupBase] = []
	for child: Node in _spawner.get_children():
		if child is PickupBase:
			coins.append(child as PickupBase)
	assert_int(coins.size()).override_failure_message("the gremlin dropped nothing").is_greater(0)
	for coin: PickupBase in coins:
		# The node-side shape owner survives the refused call; only the server knows.
		(
			assert_int(PhysicsServer2D.area_get_shape_count(coin.get_rid()))
			. override_failure_message("the dropped coin has no shape in the physics server")
			. is_greater(0)
		)
		assert_bool(coin.monitorable).is_true()
		# Deferred placement still lands the coin on the corpse (it scatters a little as it
		# pops), rather than leaving it at the origin because the position was never applied.
		(
			assert_float(coin.global_position.distance_to(_hitbox.global_position))
			. override_failure_message("the deferred drop did not land where the enemy died")
			. is_less(40.0)
		)


## A drop is the same shape every time a run and floor are replayed.
##
## `PickupBase._bob_phase` used to be `randf() * TAU` - the last unseeded *global* RNG draw in
## `src/`, on a project whose whole save model is "rebuild the floor from the seed". Three things
## came of it. A resumed floor drew its coins at a different phase from the session that dropped
## them; no capture of loose loot could be compared pixel for pixel; and `pickup_frame` was flaky
## in a way nobody had noticed, reading one kind at 4.31:1 on one run and 2.42:1 on the next
## because a coin frozen a pixel higher put a different share of its rim on the wall speckle.
##
## The phase now comes from the spawner's own stream, seeded from the run and the floor, so this
## is the assertion that keeps it there: same seed and floor, same phases, in order.
func test_a_drops_shape_is_the_same_on_every_replay_of_a_run() -> void:
	var saved := GameState.run_seed
	GameState.run_seed = 8817
	var phases: Array[PackedFloat32Array] = []
	for pass_index in range(2):
		var parts := _setup_scene()
		var spawner: PickupSpawner = parts[1]
		spawner._on_floor_started(3)
		var run: PackedFloat32Array = []
		for kind: StringName in [&"gold", &"heart", &"stat_orb"]:
			for drop: PickupBase in spawner.spawn(kind, Vector2(150, 100), 3):
				run.append(drop._bob_phase)
		phases.append(run)
	GameState.run_seed = saved
	(
		assert_int(phases[0].size())
		. override_failure_message("no drops were made, so nothing was compared")
		. is_greater(2)
	)
	(
		assert_array(phases[1])
		. override_failure_message(
			"the same run and floor drew different bob phases: %s then %s" % [phases[0], phases[1]]
		)
		. is_equal(phases[0])
	)


## And two different floors of the same run are not the same drop, so the stream is really being
## advanced rather than reset to one fixed value.
func test_two_floors_of_a_run_do_not_draw_the_same_drop() -> void:
	var saved := GameState.run_seed
	GameState.run_seed = 8817
	var phases: Array[PackedFloat32Array] = []
	for floor_index: int in [1, 2]:
		var parts := _setup_scene()
		var spawner: PickupSpawner = parts[1]
		spawner._on_floor_started(floor_index)
		var run: PackedFloat32Array = []
		for drop: PickupBase in spawner.spawn(&"gold", Vector2(150, 100), 5):
			run.append(drop._bob_phase)
		phases.append(run)
	GameState.run_seed = saved
	assert_array(phases[1]).is_not_equal(phases[0])
