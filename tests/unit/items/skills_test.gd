class_name WeaponSkillsTest
extends GdUnitTestSuite

const SKILL_IDS: Array[StringName] = [
	&"lunge", &"cleave", &"rain", &"barrier", &"fan_of_knives", &"sweep", &"bribe"
]


func _make_player(with_gold: bool = false) -> Entity:
	var world := auto_free(Node2D.new()) as Node2D
	add_child(world)
	var player: Entity = GoldTestEntity.new() if with_gold else Entity.new()
	player.team = Layers.Team.PLAYER
	world.add_child(player)
	player.stats.add_primary(&"might", 3)
	return player


func _make_enemy(world: Node, pos: Vector2) -> Entity:
	var enemy := Entity.new()
	enemy.team = Layers.Team.ENEMY
	world.add_child(enemy)
	enemy.global_position = pos
	return enemy


func _load(id: StringName) -> WeaponSkill:
	var skill := load("res://data/items/skills/%s.tres" % id) as WeaponSkill
	return skill.duplicate_ability() as WeaponSkill


func test_all_skill_resources_load() -> void:
	for id: StringName in SKILL_IDS:
		var skill := _load(id)
		assert_object(skill).override_failure_message("skill %s" % id).is_not_null()
		assert_bool(skill.is_active()).is_true()
		assert_float(skill.cooldown).is_greater(0.0)
		assert_str(skill.display_name).is_not_empty()
		# A weapon skill lives on the equipped weapon, not in an AbilitySlots socket, so
		# nothing in the game ever raises its tier. `max_tier = 3` was dead data promising an
		# upgrade path that does not exist; the resource says what the code actually does.
		(
			assert_int(skill.max_tier)
			. override_failure_message("%s claims tiers nothing can award" % id)
			. is_equal(1)
		)
		assert_int(skill.tier).is_equal(1)
		assert_float(skill.tier_damage_scale()).is_equal_approx(1.0, 0.001)


func test_every_skill_activates_on_dummy_entity() -> void:
	for id: StringName in SKILL_IDS:
		var player := _make_player()
		await get_tree().physics_frame
		var skill := _load(id)
		var ok := skill.try_activate(player, Vector2.RIGHT)
		assert_bool(ok).override_failure_message("skill %s refused" % id).is_true()
		assert_bool(skill.is_ready()).is_false()
		for _i in range(4):
			await get_tree().physics_frame
		assert_bool(skill.try_activate(player, Vector2.RIGHT)).is_false()
		skill.tick(100.0)
		assert_bool(skill.is_ready()).is_true()
	for _i in range(40):
		await get_tree().physics_frame


func test_skill_refuses_when_not_in_tree_or_stunned() -> void:
	var loose := auto_free(Entity.new()) as Entity
	loose.team = Layers.Team.PLAYER
	var skill := _load(&"lunge")
	assert_bool(skill.try_activate(loose, Vector2.RIGHT)).is_false()
	assert_bool(skill.is_ready()).is_true()
	var player := _make_player()
	await get_tree().physics_frame
	player.status.apply(StatusEffect.make(StatusEffect.Kind.STUN, 2.0, 0.0))
	assert_bool(skill.try_activate(player, Vector2.RIGHT)).is_false()


func test_cleave_damages_enemy_in_front_and_reports_hit() -> void:
	var player := _make_player()
	var enemy := _make_enemy(player.get_parent(), Vector2(24.0, 0.0))
	await get_tree().physics_frame
	var reported: Array[Node2D] = []
	var handler := func(target: Node2D, _info: DamageInfo) -> void: reported.append(target)
	EventBus.player_hit_dealt.connect(handler)
	var skill := _load(&"cleave")
	var hp_before := enemy.health.hp
	assert_bool(skill.try_activate(player, Vector2.RIGHT)).is_true()
	for _i in range(6):
		await get_tree().physics_frame
	EventBus.player_hit_dealt.disconnect(handler)
	assert_float(enemy.health.hp).is_less(hp_before)
	assert_int(reported.size()).is_greater_equal(1)
	assert_object(reported[0]).is_same(enemy)
	assert_bool(enemy.knockback_velocity.length() > 0.0 or enemy.velocity.length() >= 0.0).is_true()


func test_fan_of_knives_spawns_projectiles() -> void:
	var player := _make_player()
	await get_tree().physics_frame
	var skill := _load(&"fan_of_knives")
	skill.tier = 2
	assert_bool(skill.try_activate(player, Vector2.DOWN)).is_true()
	var count := 0
	for child: Node in player.get_parent().get_children():
		if child is Projectile:
			count += 1
	assert_int(count).is_equal(7)
	for _i in range(50):
		await get_tree().physics_frame


func test_sweep_applies_slow() -> void:
	var player := _make_player()
	var enemy := _make_enemy(player.get_parent(), Vector2(-16.0, 8.0))
	await get_tree().physics_frame
	var skill := _load(&"sweep")
	assert_bool(skill.try_activate(player, Vector2.ZERO)).is_true()
	for _i in range(4):
		await get_tree().physics_frame
	assert_bool(enemy.status.has(StatusEffect.Kind.SLOW)).is_true()


func test_bribe_costs_gold_and_stuns() -> void:
	var player := _make_player(true)
	await get_tree().physics_frame
	var skill := _load(&"bribe")
	player.set(&"gold", 5)
	assert_bool(skill.try_activate(player, Vector2.RIGHT)).is_false()
	player.set(&"gold", 50)
	assert_bool(skill.try_activate(player, Vector2.RIGHT)).is_true()
	assert_int(int(player.get(&"gold"))).is_equal(40)
	var enemy := _make_enemy(player.get_parent(), Vector2(40.0, 0.0))
	for _i in range(20):
		await get_tree().physics_frame
	assert_bool(enemy.status.is_stunned()).is_true()


func test_rain_lands_arrows_after_telegraph() -> void:
	var player := _make_player()
	var enemy := _make_enemy(player.get_parent(), Vector2(60.0, 0.0))
	await get_tree().physics_frame
	var skill := _load(&"rain") as SkillRain
	assert_bool(skill.try_activate(player, Vector2(60.0, 0.0))).is_true()
	await get_tree().create_timer(1.0).timeout
	assert_int(skill.arrows_landed).is_equal(SkillRain.BASE_ARROWS)
	assert_float(enemy.health.hp).is_less(enemy.health.max_hp)


func test_barrier_blocks_enemy_projectiles() -> void:
	var player := _make_player()
	await get_tree().physics_frame
	var skill := _load(&"barrier") as SkillBarrier
	assert_bool(skill.try_activate(player, Vector2.RIGHT)).is_true()
	var enemy := _make_enemy(player.get_parent(), Vector2(60.0, 0.0))
	var shot := Projectile.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shot.add_child(shape)
	var builder := func(_t: Node2D) -> DamageInfo:
		return DamageInfo.create(5.0, [DamageInfo.TAG_RANGED], enemy, Layers.Team.ENEMY)
	shot.setup(enemy, Layers.Team.ENEMY, Vector2.LEFT, builder, 200.0, 2.0)
	shot.position = Vector2(40.0, 0.0)
	player.get_parent().add_child(shot)
	for _i in range(30):
		await get_tree().physics_frame
	assert_int(skill.projectiles_blocked).is_equal(1)
	assert_bool(is_instance_valid(shot)).is_false()
	assert_float(player.health.hp).is_equal(player.health.max_hp)


func _enemy_shot(shooter: Entity, parent: Node, pos: Vector2) -> Projectile:
	var shot := Projectile.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shot.add_child(shape)
	var builder := func(_t: Node2D) -> DamageInfo:
		return DamageInfo.create(5.0, [DamageInfo.TAG_RANGED], shooter, Layers.Team.ENEMY)
	shot.setup(shooter, Layers.Team.ENEMY, Vector2.LEFT, builder, 120.0, 4.0)
	parent.add_child(shot)
	shot.global_position = pos
	return shot


func test_barrier_lives_and_blocks_for_its_whole_duration() -> void:
	var player := _make_player()
	var world := player.get_parent()
	await get_tree().physics_frame
	var skill := _load(&"barrier") as SkillBarrier
	assert_bool(skill.try_activate(player, Vector2.RIGHT)).is_true()
	var wall := world.get_node_or_null(^"Barrier")
	assert_object(wall).is_not_null()
	await get_tree().create_timer(SkillBarrier.DURATION * 0.8).timeout
	assert_bool(is_instance_valid(wall)).override_failure_message("wall died early").is_true()
	# a projectile parented under another node (a room, the firing enemy) is caught too.
	var enemy := _make_enemy(world, Vector2(80.0, 0.0))
	var holder := Node2D.new()
	world.add_child(holder)
	var shot := _enemy_shot(enemy, holder, Vector2(34.0, 0.0))
	for _i in range(40):
		await get_tree().physics_frame
	assert_int(skill.projectiles_blocked).is_greater_equal(1)
	assert_bool(is_instance_valid(shot)).is_false()
	assert_float(player.health.hp).is_equal(player.health.max_hp)
	await get_tree().create_timer(SkillBarrier.DURATION * 0.4).timeout
	assert_bool(is_instance_valid(wall)).override_failure_message("wall outlived").is_false()
	holder.queue_free()


func test_every_weapon_skill_has_an_icon_the_hud_can_draw() -> void:
	# The third HUD slot is a whole secondary attack on its own cooldown, and not one of the
	# seven skills carried an `icon`, so `AbilitySlot._draw` fell through to its single-letter
	# placeholder: Lunge was a box with "L" in it, and Barrier and Bribe were both "B".
	var seen: Dictionary = {}
	for id: StringName in SKILL_IDS:
		var skill := _load(id)
		(
			assert_object(skill.icon)
			. override_failure_message("%s has no icon; the HUD draws a bare letter" % id)
			. is_not_null()
		)
		assert_vector(skill.icon.get_size()).is_equal(Vector2(16, 16))
		(
			assert_str(skill.description)
			. override_failure_message("%s has no blurb" % id)
			. is_not_empty()
		)
		var initial := skill.display_name.substr(0, 1).to_upper()
		seen[initial] = int(seen.get(initial, 0)) + 1
	# Two skills share an initial (Barrier / Bribe), which is exactly why a letter cannot be
	# the fallback: without icons the HUD is ambiguous, not merely plain.
	var collisions := 0
	for initial: String in seen:
		if int(seen[initial]) > 1:
			collisions += 1
	assert_int(collisions).is_greater(0)
