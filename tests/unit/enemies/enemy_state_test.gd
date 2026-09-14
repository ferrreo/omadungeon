class_name EnemyStateTest
extends GdUnitTestSuite

## Every EventBus handler this suite connects goes through the probe, which hands them all back
## in after_test: an autoload signal outlives the suite, so a leaked lambda silently changes
## the result of whatever runs next (see tests/unit/tools/test_isolation_test.gd).
var _probe := EventBusProbe.new()


func after_test() -> void:
	_probe.release()


func _await_state(enemy: EnemyBase, wanted: EnemyBase.State, max_frames: int) -> bool:
	var seen := {}
	enemy.state_changed.connect(
		func(_p: EnemyBase.State, c: EnemyBase.State) -> void: seen[c] = true
	)
	for _i in range(max_frames):
		await get_tree().physics_frame
		if seen.has(wanted):
			return true
	return false


func test_melee_enemy_reaches_attack_and_hits_player() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(200, 100)
	var gremlin := EnemyTestHelpers.spawn(&"config_gremlin", root, Vector2(150, 100))
	var reached := await _await_state(gremlin, EnemyBase.State.ATTACK, 180)
	assert_bool(reached).override_failure_message("state %s" % gremlin.state).is_true()
	for _i in range(30):
		await get_tree().physics_frame
	assert_float(player.health.hp).is_less(player.health.max_hp)
	assert_int(player.stats_stolen.size()).is_equal(1)
	assert_that(gremlin.stolen_stat).is_equal(player.stats_stolen[0])


func test_stun_interrupts_and_recovers() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(300, 100)
	var enemy := EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(100, 100))
	# The player is 200 px off, past a zealot's sight: this case is about the stun interrupting
	# a chase, so the chase is started explicitly rather than waited on. Noticing is measured
	# in awareness_test.gd.
	enemy.alert()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_that(enemy.state).is_equal(EnemyBase.State.APPROACH)
	enemy.status.apply(StatusEffect.make(StatusEffect.Kind.STUN, 0.2, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_that(enemy.state).is_equal(EnemyBase.State.STUNNED)
	var released := await _await_state(enemy, EnemyBase.State.APPROACH, 40)
	assert_bool(released).is_true()


func test_death_emits_died_drops_loot_and_frees() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var enemy := EnemyTestHelpers.spawn(&"juggler", root, Vector2(50, 50))
	var died: Array[Node2D] = []
	var pickups: Array[StringName] = []
	_probe.watch(EventBus.enemy_died, func(e: Node2D, _k: Node2D) -> void: died.append(e))
	_probe.watch(
		EventBus.spawn_pickup,
		func(kind: StringName, _p: Vector2, _a: int) -> void: pickups.append(kind)
	)
	await get_tree().physics_frame
	var killer := auto_free(Node2D.new()) as Node2D
	EnemyTestHelpers.hit(enemy, 9999.0, killer)
	_probe.release()
	assert_int(died.size()).is_equal(1)
	assert_that(enemy.state).is_equal(EnemyBase.State.DEAD)
	assert_bool(pickups.has(&"gold")).is_true()
	assert_bool(enemy.is_in_group(&"enemy")).is_false()
	await get_tree().physics_frame
	assert_int(enemy.hurtbox.collision_layer).is_equal(0)
	await get_tree().create_timer(2.0).timeout
	assert_bool(is_instance_valid(enemy)).is_false()


func test_convert_switches_sides_and_targets_enemies() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(400, 300)
	var ally := EnemyTestHelpers.spawn(&"honker", root, Vector2(100, 100))
	var foe := EnemyTestHelpers.spawn(&"juggler", root, Vector2(140, 100))
	await get_tree().physics_frame
	ally.convert(Layers.Team.PLAYER, 0.3)
	assert_that(ally.team).is_equal(Layers.Team.PLAYER)
	assert_bool(ally.is_in_group(&"enemy")).is_false()
	assert_bool(ally.is_in_group(&"ally")).is_true()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(ally.hurtbox.collision_layer).is_equal(Layers.PLAYER_HURTBOX)
	assert_object(ally.target).is_same(foe)
	await get_tree().create_timer(0.5).timeout
	assert_that(ally.team).is_equal(Layers.Team.ENEMY)
	assert_bool(ally.is_in_group(&"enemy")).is_true()


func test_tinkerers_ignore_trap_damage() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var ricer := EnemyTestHelpers.spawn(&"ricer", root, Vector2(50, 50))
	var clown := EnemyTestHelpers.spawn(&"juggler", root, Vector2(90, 50))
	var tags: Array[StringName] = [DamageInfo.TAG_TRAP, DamageInfo.TAG_PHYSICAL]
	var dealt_ricer := ricer.hurtbox.receive(
		DamageInfo.create(10.0, tags, null, Layers.Team.NEUTRAL)
	)
	var dealt_clown := clown.hurtbox.receive(
		DamageInfo.create(10.0, tags, null, Layers.Team.NEUTRAL)
	)
	assert_float(dealt_ricer).is_equal(0.0)
	assert_float(dealt_clown).is_greater(0.0)
