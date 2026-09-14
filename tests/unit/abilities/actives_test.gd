class_name ActivesTest
extends GdUnitTestSuite

var _world: Node2D
var _player: DummyPlayer
var _slots: AbilitySlots


func before_test() -> void:
	_world = auto_free(Node2D.new())
	_world.name = "World"
	add_child(_world)
	_player = AbilityTestHelpers.make_player()
	_world.add_child(_player)
	_slots = AbilityTestHelpers.attach_slots(_player)


func _enemy(pos: Vector2, elite: bool = false) -> DummyEnemy:
	var e := AbilityTestHelpers.make_enemy(pos, elite)
	_world.add_child(e)
	return e


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func _cast(id: StringName, aim: Vector2 = Vector2.RIGHT) -> ActiveAbility:
	var ability := AbilityTestHelpers.active(id)
	_slots.add(ability)
	assert_bool(_slots.try_use(0, aim)).override_failure_message("%s refused" % id).is_true()
	return ability


func test_fireball_bursts_and_burns() -> void:
	var near := _enemy(Vector2(30, 0))
	var far := _enemy(Vector2(200, 0))
	_cast(&"fireball")
	await _frames(40)
	assert_float(near.health.hp).is_less(near.health.max_hp)
	assert_bool(near.status.has(StatusEffect.Kind.BURN)).is_true()
	assert_float(far.health.hp).is_equal(far.health.max_hp)


func test_fireball_bursts_at_max_range_without_target() -> void:
	var at_range := _enemy(Vector2(96, 0))
	_cast(&"fireball")
	await _frames(50)
	assert_float(at_range.health.hp).is_less(at_range.health.max_hp)


func test_frost_nova_chills_in_radius_only() -> void:
	var near := _enemy(Vector2(24, 0))
	var far := _enemy(Vector2(100, 0))
	_cast(&"frost_nova")
	await _frames(4)
	assert_float(near.health.hp).is_less(near.health.max_hp)
	assert_bool(near.status.has(StatusEffect.Kind.FROST)).is_true()
	assert_float(far.health.hp).is_equal(far.health.max_hp)
	assert_bool(far.status.has(StatusEffect.Kind.FROST)).is_false()


func test_frost_nova_tier_three_applies_extra_stack() -> void:
	var near := _enemy(Vector2(24, 0))
	var nova := AbilityTestHelpers.active(&"frost_nova")
	nova.tier = 3
	_slots.add(nova)
	_slots.try_use(0, Vector2.RIGHT)
	await _frames(4)
	assert_int((near.status.effects[StatusEffect.Kind.FROST] as StatusEffect).stacks).is_equal(2)


func test_shadowstep_moves_and_arms_crit() -> void:
	_cast(&"shadowstep", Vector2.RIGHT)
	assert_float(_player.global_position.x).is_equal_approx(64.0, 0.5)
	assert_bool(_slots.has_next_hit(AbilitySlots.BUFF_CRIT)).is_true()
	var info := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], _player, _player.team)
	assert_float(_slots.outgoing_damage_multiplier(null, info)).is_equal_approx(1.5, 0.001)
	assert_bool(info.is_crit).is_true()


func test_shadowstep_stops_at_walls() -> void:
	var wall: StaticBody2D = auto_free(StaticBody2D.new())
	wall.collision_layer = Layers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 64)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(40, 0)
	_world.add_child(wall)
	await _frames(2)
	_cast(&"shadowstep", Vector2.RIGHT)
	assert_float(_player.global_position.x).is_between(20.0, 34.0)


func test_whirlwind_hits_repeatedly() -> void:
	var near := _enemy(Vector2(16, 0))
	var ability := _cast(&"whirlwind")
	await _frames(36)
	var per_hit := ability.damage
	assert_float(near.health.hp).is_less_equal(near.health.max_hp - 2.0 * per_hit)
	assert_object(_player.get_node_or_null("AbilityHitbox")).is_not_null()
	assert_object(_player.get_node_or_null("WhirlwindBlades")).is_not_null()


func test_turret_shoots_nearest_enemy() -> void:
	var target := _enemy(Vector2(70, 0))
	_cast(&"turret")
	var turrets := get_tree().get_nodes_in_group(&"turret")
	assert_int(turrets.size()).is_equal(1)
	assert_float((turrets[0] as Node2D).global_position.x).is_equal_approx(16.0, 0.5)
	await _frames(70)
	assert_float(target.health.hp).is_less(target.health.max_hp)


func test_warcry_empowers_and_taunts_nearby() -> void:
	var near := _enemy(Vector2(50, 0))
	var far := _enemy(Vector2(200, 0))
	_cast(&"warcry")
	assert_bool(_player.status.has(StatusEffect.Kind.EMPOWER)).is_true()
	assert_float(_player.status.damage_multiplier()).is_equal_approx(1.5, 0.001)
	assert_bool(near.status.is_taunted()).is_true()
	assert_object(near.status.taunt_source()).is_same(_player)
	assert_bool(far.status.is_taunted()).is_false()


func test_rm_rf_frees_enemy_projectiles_and_hazards() -> void:
	var bullet: Node2D = Node2D.new()
	bullet.add_to_group(&"enemy_projectile")
	_world.add_child(bullet)
	var spikes: Node2D = Node2D.new()
	spikes.add_to_group(&"hazard")
	_world.add_child(spikes)
	var bystander: Node2D = auto_free(Node2D.new())
	_world.add_child(bystander)
	_cast(&"rm_rf")
	assert_bool(bullet.is_queued_for_deletion()).is_true()
	assert_bool(spikes.is_queued_for_deletion()).is_true()
	assert_bool(bystander.is_queued_for_deletion()).is_false()
	await _frames(2)
	assert_int(get_tree().get_nodes_in_group(&"enemy_projectile").size()).is_equal(0)
	assert_int(get_tree().get_nodes_in_group(&"hazard").size()).is_equal(0)


func test_reboot_heals_over_time_and_slows() -> void:
	_player.health.hp = 50.0
	var reboot := AbilityTestHelpers.active(&"reboot") as RebootAbility
	reboot.duration = 0.3
	_slots.add(reboot)
	assert_bool(_slots.try_use(0, Vector2.ZERO)).is_true()
	assert_bool(_player.status.has(StatusEffect.Kind.SLOW)).is_true()
	assert_float(_player.status.speed_multiplier()).is_equal_approx(0.75, 0.001)
	await await_millis(600)
	assert_float(_player.health.hp).is_equal_approx(95.0, 1.0)
	assert_object(_player.get_node_or_null("RebootHeal")).is_null()


func test_bulwark_absorbs_and_reflects() -> void:
	var attacker := _enemy(Vector2(12, 0))
	var bulwark := AbilityTestHelpers.active(&"bulwark") as BulwarkAbility
	bulwark.duration = 0.4
	_slots.add(bulwark)
	assert_bool(_slots.try_use(0, Vector2.ZERO)).is_true()
	var shield := _player.get_node_or_null("BulwarkShield") as BulwarkShield
	assert_object(shield).is_not_null()
	assert_float(shield.remaining()).is_equal_approx(40.0, 0.001)
	assert_object(_player.hurtbox.health_override).is_same(shield.pool)
	_player.hurtbox.receive(AbilityTestHelpers.melee_hit(attacker, 10.0))
	assert_float(_player.health.hp).is_equal(100.0)
	assert_float(shield.remaining()).is_equal_approx(30.0, 0.001)
	await _frames(4)
	assert_float(attacker.health.hp).is_less(attacker.health.max_hp)
	await await_millis(600)
	assert_object(_player.get_node_or_null("BulwarkShield")).is_null()
	assert_object(_player.hurtbox.health_override).is_null()


func test_bulwark_breaks_when_depleted_and_carries_overkill() -> void:
	var attacker := _enemy(Vector2(60, 0))
	_cast(&"bulwark")
	var shield := _player.get_node_or_null("BulwarkShield") as BulwarkShield
	# 50 against a 40 shield: 40 soaked, the remaining 10 must still reach HP.
	_player.hurtbox.receive(AbilityTestHelpers.melee_hit(attacker, 50.0))
	assert_float(_player.health.hp).is_equal_approx(90.0, 0.001)
	await _frames(2)
	assert_bool(is_instance_valid(shield) and not shield.is_queued_for_deletion()).is_false()
	assert_object(_player.hurtbox.health_override).is_null()
	_player.hurtbox.receive(AbilityTestHelpers.melee_hit(attacker, 10.0))
	assert_float(_player.health.hp).is_equal_approx(80.0, 0.001)


func test_bulwark_uses_the_player_shield_api_and_reflects_on_absorption() -> void:
	var world: Node2D = auto_free(Node2D.new())
	add_child(world)
	var player: ShieldedDummyPlayer = auto_free(ShieldedDummyPlayer.new())
	player.name = "Player"
	world.add_child(player)
	var slots := AbilityTestHelpers.attach_slots(player)
	var attacker := AbilityTestHelpers.make_enemy(Vector2(12, 0))
	world.add_child(attacker)
	var bulwark := AbilityTestHelpers.active(&"bulwark") as BulwarkAbility
	bulwark.duration = 0.6
	slots.add(bulwark)
	assert_bool(slots.try_use(0, Vector2.ZERO)).is_true()
	# The shipped path is `set_shield`; BulwarkShield must not be used at all.
	assert_float(player.shield_amount).is_greater(0.0)
	assert_object(player.get_node_or_null("BulwarkShield")).is_null()
	# A fully absorbed hit deals no HP damage, so only `shield_absorbed` can drive the pulse.
	player.hurtbox.receive(AbilityTestHelpers.melee_hit(attacker, 10.0))
	assert_float(player.health.hp).is_equal(100.0)
	await _frames(4)
	assert_float(attacker.health.hp).is_less(attacker.health.max_hp)


func test_bulwark_recast_does_not_stack_reflect_handlers() -> void:
	var world: Node2D = auto_free(Node2D.new())
	add_child(world)
	var player: ShieldedDummyPlayer = auto_free(ShieldedDummyPlayer.new())
	player.name = "Player"
	world.add_child(player)
	var slots := AbilityTestHelpers.attach_slots(player)
	var bulwark := AbilityTestHelpers.active(&"bulwark") as BulwarkAbility
	bulwark.duration = 0.6
	slots.add(bulwark)
	assert_bool(slots.try_use(0, Vector2.ZERO)).is_true()
	bulwark.cooldown_left = 0.0
	assert_bool(slots.try_use(0, Vector2.ZERO)).is_true()
	(
		assert_int((player.health as ShieldedDummyHealth).shield_absorbed.get_connections().size())
		. is_equal(1)
	)


func test_volley_fires_a_fan_that_hits() -> void:
	var target := _enemy(Vector2(40, 0))
	_cast(&"volley")
	var arrows := 0
	for child: Node in _world.get_children():
		if child is Projectile:
			arrows += 1
	assert_int(arrows).is_equal(5)
	await _frames(20)
	assert_float(target.health.hp).is_less(target.health.max_hp)


func test_chain_lightning_arcs_through_four_and_refuses_without_targets() -> void:
	var lightning := AbilityTestHelpers.active(&"chain_lightning")
	_slots.add(lightning)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_false()
	assert_float(lightning.cooldown_left).is_equal(0.0)
	var chain: Array[DummyEnemy] = []
	for x: int in [30, 60, 90, 120]:
		chain.append(_enemy(Vector2(x, 0)))
	var fifth := _enemy(Vector2(150, 0))
	var isolated := _enemy(Vector2(0, 300))
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	for e: DummyEnemy in chain:
		assert_float(e.health.hp).is_less(e.health.max_hp)
		assert_bool(e.status.has(StatusEffect.Kind.SHOCK)).is_true()
	assert_float(fifth.health.hp).is_equal(fifth.health.max_hp)
	assert_float(isolated.health.hp).is_equal(isolated.health.max_hp)
	assert_float(chain[0].health.hp).is_less(chain[3].health.hp)


func test_hostile_takeover_converts_nearest_non_elite() -> void:
	var elite := _enemy(Vector2(20, 0), true)
	var minion := AbilityTestHelpers.make_convertible_enemy(Vector2(50, 0))
	_world.add_child(minion)
	_cast(&"hostile_takeover")
	assert_int(minion.converted_team).is_equal(Layers.Team.PLAYER)
	assert_float(minion.converted_seconds).is_equal_approx(10.0, 0.001)
	assert_bool(elite.status.is_stunned()).is_false()


func test_hostile_takeover_falls_back_to_stun_and_refuses_when_empty() -> void:
	var takeover := AbilityTestHelpers.active(&"hostile_takeover")
	_slots.add(takeover)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_false()
	var plain := _enemy(Vector2(40, 0))
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	assert_bool(plain.status.is_stunned()).is_true()
	assert_float(plain.status.effects[StatusEffect.Kind.STUN].remaining).is_equal_approx(10.0, 0.05)


func test_contract_summons_bodyguard_that_fights_then_expires() -> void:
	var target := _enemy(Vector2(28, 0))
	var contract := AbilityTestHelpers.active(&"contract") as ContractAbility
	contract.duration = 1.2
	_slots.add(contract)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	var hirelings := get_tree().get_nodes_in_group(&"hireling")
	assert_int(hirelings.size()).is_equal(1)
	var guard := hirelings[0] as Hireling
	assert_int(guard.team).is_equal(Layers.Team.PLAYER)
	assert_object(guard.leader).is_same(_player)
	await _frames(60)
	assert_float(target.health.hp).is_less(target.health.max_hp)
	await await_millis(600)
	assert_int(get_tree().get_nodes_in_group(&"hireling").size()).is_equal(0)


func test_ability_hits_report_to_event_bus() -> void:
	var seen: Array = []
	var listener := func(target: Node2D, info: DamageInfo) -> void: seen.append([target, info])
	EventBus.player_hit_dealt.connect(listener)
	var near := _enemy(Vector2(24, 0))
	_cast(&"frost_nova")
	await _frames(4)
	EventBus.player_hit_dealt.disconnect(listener)
	assert_int(seen.size()).is_equal(1)
	assert_object(seen[0][0]).is_same(near)
	assert_object((seen[0][1] as DamageInfo).source).is_same(_player)


func test_hireling_hits_credit_the_leader_on_the_bus() -> void:
	var seen: Array = []
	var listener := func(_target: Node2D, info: DamageInfo) -> void: seen.append(info)
	EventBus.player_hit_dealt.connect(listener)
	var target := _enemy(Vector2(24, 0))
	var contract := AbilityTestHelpers.active(&"contract") as ContractAbility
	contract.duration = 2.0
	_slots.add(contract)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	await _frames(60)
	EventBus.player_hit_dealt.disconnect(listener)
	assert_float(target.health.hp).is_less(target.health.max_hp)
	assert_bool(seen.size() > 0).is_true()
	var guard := _world.get_node_or_null("Bodyguard") as Hireling
	assert_object((seen[0] as DamageInfo).source).is_same(guard)
	# The slots hook accepts a hireling that follows the owner, so Vampiric/Hotkey and
	# on_kill see its damage even though the node is not parented under the player.
	assert_bool(_slots._is_owner_or_child((seen[0] as DamageInfo).source)).is_true()


func test_enemy_lookup_never_returns_a_freed_enemy_in_the_same_frame() -> void:
	var doomed := _enemy(Vector2(20, 0))
	var survivor := _enemy(Vector2(40, 0))
	assert_int(AbilityUtil.enemies(get_tree()).size()).is_equal(2)
	# Same frame, same group size: the cache must notice the entity is gone.
	doomed.free()
	var replacement := _enemy(Vector2(60, 0))
	var found := AbilityUtil.enemies(get_tree())
	assert_int(found.size()).is_equal(2)
	assert_bool(found.has(survivor)).is_true()
	assert_bool(found.has(replacement)).is_true()
	assert_object(AbilityUtil.nearest_enemy(get_tree(), Vector2.ZERO, 200.0)).is_same(survivor)


func test_contract_hireling_uses_the_slots_rng() -> void:
	var contract := AbilityTestHelpers.active(&"contract")
	_slots.add(contract)
	_enemy(Vector2(24, 0))
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	var guard := get_tree().get_nodes_in_group(&"hireling")[0] as Hireling
	assert_object(guard.rng).is_same(_slots.rng)
