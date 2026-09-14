class_name EnemyCombatTest
extends GdUnitTestSuite

## Space between the per-enemy test clusters so nothing targets a neighbour's player.
const CLUSTER_SPACING := 2000.0
## Physics frames every enemy gets to land its first hit (~10 s).
const COMBAT_FRAMES := 600


func _tough_player(root: Node2D, pos: Vector2) -> EnemyTestPlayer:
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.stats.add_flat(&"max_hp", &"test", 100000.0)
	player.global_position = pos
	return player


func test_honk_stuns_the_player_through_the_hitbox() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := _tough_player(root, Vector2(106, 100))
	var honker := EnemyTestHelpers.spawn(&"honker", root, Vector2(100, 100)) as Honker
	await get_tree().physics_frame
	honker.set_physics_process(false)
	honker.honk()
	for _i in range(10):
		await get_tree().physics_frame
		if player.status.is_stunned():
			break
	assert_bool(player.status.is_stunned()).is_true()
	assert_float(player.health.hp).is_less(player.health.max_hp)


func test_every_enemy_damages_a_stationary_player() -> void:
	var registry := EnemyTestHelpers.registry()
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var players: Array[EnemyTestPlayer] = []
	for i in range(registry.defs.size()):
		var def: EnemyDef = registry.defs[i]
		var origin := Vector2(i * CLUSTER_SPACING, 0.0)
		players.append(_tough_player(root, origin + Vector2(40.0, 0.0)))
		EnemyTestHelpers.spawn(def.id, root, origin)
	var hurt := 0
	for _frame in range(COMBAT_FRAMES):
		await get_tree().physics_frame
		hurt = 0
		for player: EnemyTestPlayer in players:
			if player.health.hp < player.health.max_hp:
				hurt += 1
		if hurt == players.size():
			break
	for i in range(players.size()):
		var def: EnemyDef = registry.defs[i]
		(
			assert_float(players[i].health.hp)
			. override_failure_message("%s never damaged the player" % def.id)
			. is_less(players[i].health.max_hp)
		)


func test_telegraph_radius_matches_the_attack_not_the_aggro_range() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var juggler := EnemyTestHelpers.spawn(&"juggler", root, Vector2(0, 0))
	var warden := EnemyTestHelpers.spawn(&"beard_warden", root, Vector2(60, 0))
	var priest := EnemyTestHelpers.spawn(&"rant_priest", root, Vector2(120, 0)) as RantPriest
	await get_tree().physics_frame
	assert_float(juggler.telegraph_radius()).is_less(juggler.def.attack_range * 0.5)
	assert_float(warden.telegraph_radius()).is_equal_approx(warden.def.attack_range, 0.01)
	assert_float(priest.telegraph_radius()).is_equal_approx(
		priest.def.param(&"scream_radius", 40.0), 0.01
	)


func test_loot_rolls_are_reproducible_from_the_spawn_stream() -> void:
	var amounts: Array[int] = []
	for run in range(2):
		var root := auto_free(Node2D.new()) as Node2D
		add_child(root)
		var stream := EnemyTestHelpers.seeded(1234)
		var gold: Array[int] = []
		var handler := func(kind: StringName, _p: Vector2, amount: int) -> void:
			if kind == &"gold":
				gold.append(amount)
		EventBus.spawn_pickup.connect(handler)
		for id: StringName in [&"juggler", &"ricer", &"vim_zealot"]:
			var enemy := EnemySpawner.instantiate(
				EnemyTestHelpers.def(id), 3, Vector2(50, 50), stream
			)
			root.add_child(enemy)
			await get_tree().physics_frame
			EnemyTestHelpers.hit(enemy, 99999.0)
		EventBus.spawn_pickup.disconnect(handler)
		assert_int(gold.size()).is_equal(3)
		if run == 0:
			amounts = gold
		else:
			assert_array(gold).is_equal(amounts)


func test_floating_enemies_only_ignore_pits_not_every_trap() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var balloon := EnemyTestHelpers.spawn(&"balloon_clown", root, Vector2(0, 0))
	var ricer := EnemyTestHelpers.spawn(&"ricer", root, Vector2(60, 0))
	await get_tree().physics_frame
	assert_bool(balloon.floats).is_true()
	assert_bool(balloon.has_method(&"is_trap_immune")).is_false()
	assert_bool(ricer.floats).is_false()
	var tags: Array[StringName] = [DamageInfo.TAG_TRAP, DamageInfo.TAG_PHYSICAL]
	var on_balloon := balloon.hurtbox.receive(
		DamageInfo.create(10.0, tags, null, Layers.Team.NEUTRAL)
	)
	var on_ricer := ricer.hurtbox.receive(DamageInfo.create(10.0, tags, null, Layers.Team.NEUTRAL))
	assert_float(on_balloon).is_greater(0.0)
	assert_float(on_ricer).is_equal(0.0)
