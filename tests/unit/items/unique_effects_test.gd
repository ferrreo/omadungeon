class_name UniqueEffectsTest
extends GdUnitTestSuite


func _make_player(with_gold: bool = false) -> Entity:
	var world := auto_free(Node2D.new()) as Node2D
	add_child(world)
	var player: Entity = GoldTestEntity.new() if with_gold else Entity.new()
	player.team = Layers.Team.PLAYER
	world.add_child(player)
	return player


func test_registry_finds_all_and_returns_fresh_instances() -> void:
	assert_int(UniqueEffects.ids().size()).is_greater_equal(4)
	for id: StringName in UniqueEffects.ids():
		var a := UniqueEffects.find(id)
		var b := UniqueEffects.find(id)
		assert_object(a).is_not_null()
		assert_object(a).is_not_same(b)
		assert_str(String(a.id)).is_equal(String(id))
		assert_bool(a.is_active()).is_false()
		assert_str(a.description).is_not_empty()
	assert_object(UniqueEffects.find(&"nope")).is_null()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_bool(UniqueEffects.ids().has(UniqueEffects.pick(rng))).is_true()


func test_sudo_multiplies_against_elites_only() -> void:
	var sudo := UniqueEffects.find(&"sudo")
	var player := _make_player()
	var grunt := auto_free(Entity.new()) as Entity
	var elite := auto_free(GoldTestEntity.new()) as Entity
	elite.set_meta(&"x", 1)
	var boss := auto_free(Node2D.new()) as Node2D
	boss.set_script(load("res://tests/unit/items/elite_dummy.gd"))
	var info := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], player, Layers.Team.PLAYER)
	assert_float(sudo.outgoing_damage_multiplier(player, grunt, info)).is_equal(1.0)
	assert_float(sudo.outgoing_damage_multiplier(player, null, info)).is_equal(1.0)
	assert_float(sudo.outgoing_damage_multiplier(player, boss, info)).is_equal(1.25)


func test_fork_bomb_flags_player_and_spawns_shards() -> void:
	var fork := UniqueEffects.find(&"fork_bomb") as UniqueForkBomb
	var player := _make_player()
	await get_tree().physics_frame
	fork.apply(player)
	assert_bool(player.has_meta(&"fork_bomb")).is_true()
	var target := auto_free(Node2D.new()) as Node2D
	player.get_parent().add_child(target)
	target.global_position = Vector2(40.0, 0.0)
	var ranged := DamageInfo.create(20.0, [DamageInfo.TAG_RANGED], player, Layers.Team.PLAYER)
	ranged.with_knockback(Vector2.RIGHT, 10.0)
	fork.on_hit_dealt(player, target, ranged)
	assert_int(fork.forks_spawned).is_equal(2)
	var melee := DamageInfo.create(20.0, [DamageInfo.TAG_MELEE], player, Layers.Team.PLAYER)
	fork.on_hit_dealt(player, target, melee)
	var forked := DamageInfo.create(
		20.0, [DamageInfo.TAG_RANGED, UniqueForkBomb.FORK_TAG], player, Layers.Team.PLAYER
	)
	fork.on_hit_dealt(player, target, forked)
	assert_int(fork.forks_spawned).is_equal(2)
	fork.remove(player)
	assert_bool(player.has_meta(&"fork_bomb")).is_false()
	for _i in range(45):
		await get_tree().physics_frame


func test_omakase_serves_one_buff_per_room() -> void:
	var omakase := UniqueEffects.find(&"omakase") as UniqueOmakase
	var player := _make_player()
	omakase.apply(player)
	var baseline := _values(player.stats)
	assert_dict(_values(player.stats)).is_equal(baseline)
	omakase.on_room_cleared(player)
	assert_bool(omakase.current.is_empty()).is_false()
	assert_dict(_values(player.stats)).is_not_equal(baseline)
	for _i in range(6):
		omakase.on_room_cleared(player)
		var changed := 0
		var now := _values(player.stats)
		for stat: StringName in now.keys():
			if not is_equal_approx(float(now[stat]), float(baseline[stat])):
				changed += 1
		assert_int(changed).is_between(1, 2)
	omakase.remove(player)
	assert_dict(_values(player.stats)).is_equal(baseline)


func test_yacht_pays_gold_on_hits() -> void:
	var yacht := UniqueEffects.find(&"yacht") as UniqueYacht
	var player := _make_player(true)
	yacht.apply(player)
	var target := auto_free(Node2D.new()) as Node2D
	var info := DamageInfo.create(5.0, [DamageInfo.TAG_MELEE], player, Layers.Team.PLAYER)
	for _i in range(200):
		yacht.on_hit_dealt(player, target, info)
	assert_int(yacht.gold_earned).is_greater(20)
	assert_int(int(player.get(&"gold"))).is_equal(yacht.gold_earned)


## The regression this guards: the effect used to route its payment through
## `EventBus.spawn_pickup` whenever *anything* was connected to it, so a listener left behind
## by an unrelated system (or an earlier suite) silently stopped paying the player. A shipping
## item must never branch on how many objects happen to be listening to a global signal.
func test_yacht_pays_the_player_even_with_a_spawn_pickup_listener() -> void:
	var seen: Array[StringName] = []
	var listener := func(kind: StringName, _pos: Vector2, _amount: int) -> void: seen.append(kind)
	EventBus.spawn_pickup.connect(listener)
	var yacht := UniqueEffects.find(&"yacht") as UniqueYacht
	var player := _make_player(true)
	yacht.apply(player)
	var target := auto_free(Node2D.new()) as Node2D
	var info := DamageInfo.create(5.0, [DamageInfo.TAG_MELEE], player, Layers.Team.PLAYER)
	for _i in range(200):
		yacht.on_hit_dealt(player, target, info)
	EventBus.spawn_pickup.disconnect(listener)
	assert_int(yacht.gold_earned).is_greater(20)
	assert_int(int(player.get(&"gold"))).is_equal(yacht.gold_earned)
	assert_array(seen).is_empty()


func _values(stats: Stats) -> Dictionary:
	var out: Dictionary = {}
	for stat: StringName in Stats.PRIMARY + Stats.SECONDARY:
		out[stat] = stats.get_value(stat)
	return out


func test_fork_bomb_shards_damage_through_a_real_hitbox_hit() -> void:
	# The hook runs inside a physics query flush in real play (Hitbox._on_area_entered), where
	# enabling a hitbox is refused: the shards must be spawned deferred and still hit.
	var fork := UniqueEffects.find(&"fork_bomb") as UniqueForkBomb
	var player := _make_player()
	var world := player.get_parent()
	var host := ItemUniqueHost.attach(player)
	host.add_passive(fork)
	var hit := _spawn_enemy(world, Vector2(40.0, 0.0))
	var left := _spawn_enemy(world, Vector2(52.0, -12.0))
	var right := _spawn_enemy(world, Vector2(52.0, 12.0))
	await get_tree().physics_frame
	var hitbox := Hitbox.new()
	hitbox.name = "TestHitbox"
	hitbox.team = Layers.Team.PLAYER
	hitbox.source = player
	hitbox.tags = [DamageInfo.TAG_RANGED]
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	hitbox.add_child(shape)
	hitbox.damage_builder = func(_t: Node2D) -> DamageInfo:
		var info := DamageInfo.create(20.0, [DamageInfo.TAG_RANGED], player, Layers.Team.PLAYER)
		info.with_knockback(Vector2.RIGHT, 5.0)
		return info
	hitbox.hit_dealt.connect(WeaponSkill.report_hit)
	world.add_child(hitbox)
	hitbox.global_position = hit.global_position
	hitbox.activate(0.1)
	for _i in range(30):
		await get_tree().physics_frame
	assert_int(fork.forks_spawned).is_equal(2)
	var flank_damage := (
		(left.health.max_hp - left.health.hp) + (right.health.max_hp - right.health.hp)
	)
	assert_float(flank_damage).is_greater(0.0)
	host.remove_passive(fork)
	for _i in range(20):
		await get_tree().physics_frame


func _spawn_enemy(world: Node, pos: Vector2) -> Entity:
	var enemy := Entity.new()
	enemy.team = Layers.Team.ENEMY
	world.add_child(enemy)
	enemy.global_position = pos
	return enemy
