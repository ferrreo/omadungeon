## The abilities added to close the gap between the shipped pool (18 offerable options, every
## one of them seen in 82-94% of runs) and the pool docs §4.4 describes.
##
## Every case here asserts the thing a player would notice — an enemy dies, a status lands, a
## stat moves — rather than that a method returned. The pool-level properties (offer rates,
## take-up, rarity spread) are asserted in `tests/unit/balance/balance_targets_test.gd`.
class_name ExpandedPoolTest
extends GdUnitTestSuite

## Ids added in the build-variety pass, by kind.
const NEW_ACTIVES: Array[StringName] = [
	&"kill_9", &"fork_bomb", &"smoke_bomb", &"stack_smash", &"siphon", &"sudo"
]
const NEW_PASSIVES: Array[StringName] = [
	&"close_quarters",
	&"pipeline",
	&"rootkit",
	&"cron_job",
	&"firewall",
	&"bit_shift",
	&"man_page",
	&"overclock",
	&"verbose_logging",
	&"kernel_headers",
	&"hardlink",
	&"undervolt",
]

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


func _melee_info(amount: float) -> DamageInfo:
	var tags: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
	var info := DamageInfo.create(amount, tags, _player, _player.team)
	info.applied = amount
	return info


# --- the pool ------------------------------------------------------------------------------


func test_every_new_ability_is_in_the_registry_and_offerable() -> void:
	var registry := AbilityTestHelpers.registry()
	for id: StringName in NEW_ACTIVES + NEW_PASSIVES:
		var ability := registry.find(id)
		assert_object(ability).override_failure_message("%s is missing" % String(id)).is_not_null()
		assert_str(ability.display_name).is_not_empty()
		assert_str(ability.description).is_not_empty()
		assert_object(ability.icon).override_failure_message("no icon for %s" % id).is_not_null()
		(
			assert_bool(registry.is_offerable(ability, &"fighter", {}))
			. override_failure_message("%s can never reach a card" % String(id))
			. is_true()
		)
	for id: StringName in NEW_ACTIVES:
		assert_bool(registry.find(id).is_active()).is_true()
	for id: StringName in NEW_PASSIVES:
		assert_bool(registry.find(id).is_active()).is_false()


# --- actives -------------------------------------------------------------------------------


func test_kill_nine_hurts_a_healthy_target_and_finishes_a_wounded_one() -> void:
	var healthy := _enemy(Vector2(40, 0))
	var pool := healthy.health.max_hp
	_cast(&"kill_9")
	await _frames(2)
	var plain_loss := pool - healthy.health.hp
	assert_float(plain_loss).is_greater(0.0)
	(
		assert_bool(healthy.is_dying)
		. override_failure_message("a full-health target should survive one signal")
		. is_false()
	)
	# The same ability against a target already on its knees takes the rest of it.
	healthy.health.hp = pool * 0.25
	var execute := AbilityTestHelpers.active(&"kill_9") as KillNineAbility
	_slots.replace(0, execute)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	await _frames(2)
	(
		assert_bool(not is_instance_valid(healthy) or healthy.is_dying)
		. override_failure_message("a target under the execute threshold survived kill -9")
		. is_true()
	)


func test_kill_nine_refuses_when_nothing_is_in_reach() -> void:
	var ability := AbilityTestHelpers.active(&"kill_9")
	_slots.add(ability)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_false()
	assert_bool(ability.is_ready()).is_true()


func test_fork_bomb_covers_every_side_of_the_player() -> void:
	var right := _enemy(Vector2(40, 0))
	var left := _enemy(Vector2(-40, 0))
	var below := _enemy(Vector2(0, 40))
	_cast(&"fork_bomb")
	await _frames(40)
	for enemy: DummyEnemy in [right, left, below]:
		(
			assert_float(enemy.health.hp)
			. override_failure_message("the ring missed the enemy at %v" % enemy.position)
			. is_less(enemy.health.max_hp)
		)


func test_smoke_bomb_slows_and_weakens_the_pack_and_speeds_the_player() -> void:
	var caught := _enemy(Vector2(30, 0))
	var outside := _enemy(Vector2(200, 0))
	_cast(&"smoke_bomb")
	await _frames(2)
	assert_bool(caught.status.has(StatusEffect.Kind.SLOW)).is_true()
	assert_bool(caught.status.has(StatusEffect.Kind.WEAKEN)).is_true()
	assert_float(caught.status.damage_multiplier()).is_less(1.0)
	assert_bool(outside.status.has(StatusEffect.Kind.SLOW)).is_false()
	assert_bool(_player.status.has(StatusEffect.Kind.HASTE)).is_true()
	assert_float(_player.status.speed_multiplier()).is_greater(1.0)
	# It is crowd control, not damage: nothing in the cloud loses health.
	assert_float(caught.health.hp).is_equal(caught.health.max_hp)


func test_stack_smash_stuns_everything_around_the_player() -> void:
	var near := _enemy(Vector2(24, 0))
	var far := _enemy(Vector2(200, 0))
	_cast(&"stack_smash")
	await _frames(4)
	assert_float(near.health.hp).is_less(near.health.max_hp)
	assert_bool(near.status.is_stunned()).is_true()
	assert_float(far.health.hp).is_equal(far.health.max_hp)
	assert_bool(far.status.is_stunned()).is_false()


func test_siphon_drains_the_target_into_the_player() -> void:
	var target := _enemy(Vector2(40, 0))
	_player.health.hp = _player.health.max_hp * 0.5
	var before := _player.health.hp
	_cast(&"siphon")
	await _frames(80)
	assert_float(target.health.hp).is_less(target.health.max_hp)
	assert_float(_player.health.hp).override_failure_message("the drain healed nothing").is_greater(
		before
	)


func test_siphon_refuses_with_no_target() -> void:
	var ability := AbilityTestHelpers.active(&"siphon")
	_slots.add(ability)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_false()


func test_sudo_empowers_and_hastens_for_its_window() -> void:
	var sudo := AbilityTestHelpers.active(&"sudo") as SudoAbility
	sudo.duration = 0.3
	sudo.duration_per_tier = 0.0
	_slots.add(sudo)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	assert_bool(_player.status.has(StatusEffect.Kind.EMPOWER)).is_true()
	assert_float(_player.status.damage_multiplier()).is_greater_equal(1.8)
	assert_float(_player.status.speed_multiplier()).is_greater(1.0)
	await await_millis(500)
	assert_float(_player.status.damage_multiplier()).is_equal_approx(1.0, 0.001)


# --- passives ------------------------------------------------------------------------------


func test_close_quarters_pays_melee_and_ignores_everything_else() -> void:
	var armor_before := _player.stats.get_value(&"armor")
	_slots.add(AbilityTestHelpers.passive(&"close_quarters"))
	assert_float(_player.stats.get_value(&"armor")).is_greater(armor_before)
	assert_float(_slots.outgoing_damage_multiplier(null, _melee_info(10.0))).is_greater(1.1)
	var ranged: Array[StringName] = [DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]
	var shot := DamageInfo.create(10.0, ranged, _player, _player.team)
	assert_float(_slots.outgoing_damage_multiplier(null, shot)).is_equal(1.0)


func test_pipeline_stacks_on_kills_and_lapses() -> void:
	var pipeline := AbilityTestHelpers.passive(&"pipeline") as PipelinePassive
	pipeline.duration = 0.3
	_slots.add(pipeline)
	assert_float(_slots.outgoing_damage_multiplier(null, _melee_info(10.0))).is_equal(1.0)
	var victim := _enemy(Vector2(20, 0))
	pipeline.on_kill(_player, victim)
	pipeline.on_kill(_player, victim)
	assert_int(pipeline.stacks()).is_equal(2)
	assert_float(_slots.outgoing_damage_multiplier(null, _melee_info(10.0))).is_greater(1.1)
	await await_millis(500)
	assert_int(pipeline.stacks()).is_equal(0)
	assert_float(_slots.outgoing_damage_multiplier(null, _melee_info(10.0))).is_equal(1.0)


func test_pipeline_never_exceeds_its_cap() -> void:
	var pipeline := AbilityTestHelpers.passive(&"pipeline") as PipelinePassive
	_slots.add(pipeline)
	var victim := _enemy(Vector2(20, 0))
	for _i in range(12):
		pipeline.on_kill(_player, victim)
	assert_int(pipeline.stacks()).is_equal(pipeline.max_stacks)


func test_rootkit_pays_once_per_enemy() -> void:
	var rootkit := AbilityTestHelpers.passive(&"rootkit") as RootkitPassive
	_slots.add(rootkit)
	var first := _enemy(Vector2(20, 0))
	var second := _enemy(Vector2(40, 0))
	assert_bool(rootkit.is_fresh(first)).is_true()
	var ambush := _slots.outgoing_damage_multiplier(first, _melee_info(10.0))
	assert_float(ambush).is_greater(1.5)
	assert_bool(rootkit.is_fresh(first)).is_false()
	assert_float(_slots.outgoing_damage_multiplier(first, _melee_info(10.0))).is_equal(1.0)
	# A different body is still a fresh one.
	assert_float(_slots.outgoing_damage_multiplier(second, _melee_info(10.0))).is_equal_approx(
		ambush, 0.001
	)


func test_cron_job_heals_when_the_room_falls_quiet() -> void:
	_player.health.hp = _player.health.max_hp * 0.4
	var before := _player.health.hp
	var cron := AbilityTestHelpers.passive(&"cron_job") as CronJobPassive
	_slots.add(cron)
	cron.on_room_cleared(_player)
	assert_float(_player.health.hp).is_greater(before)
	assert_float(_player.health.hp - before).is_equal_approx(
		_player.health.max_hp * cron.fraction(), 1.0
	)


func test_every_stat_passive_moves_the_stat_it_claims_and_gives_it_back() -> void:
	# The eight data-only passives share one script, so the thing worth testing is that each
	# resource actually reaches `Stats` and unwinds cleanly when it is replaced.
	var claims := {
		&"firewall": &"armor",
		&"bit_shift": &"crit_mult",
		&"man_page": &"damage_ability",
		&"overclock": &"attack_speed",
		&"verbose_logging": &"gold_find",
		&"kernel_headers": &"might",
		&"hardlink": &"projectile_count",
		&"undervolt": &"move_speed",
	}
	for id: StringName in claims.keys():
		var stat: StringName = claims[id]
		var before := _player.stats.get_value(stat)
		var passive := AbilityTestHelpers.passive(id)
		(
			assert_object(passive as StatPassive)
			. override_failure_message("%s is not a StatPassive" % String(id))
			. is_not_null()
		)
		_slots.add(passive)
		(
			assert_float(_player.stats.get_value(stat))
			. override_failure_message("%s did not move %s" % [String(id), String(stat)])
			. is_greater(before)
		)
		_slots.remove(_slots.index_of(id))
		(
			assert_float(_player.stats.get_value(stat))
			. override_failure_message("%s left %s behind" % [String(id), String(stat)])
			. is_equal_approx(before, 0.001)
		)


func test_a_stat_passive_scales_with_its_tier() -> void:
	var firewall := AbilityTestHelpers.passive(&"firewall")
	_slots.add(firewall)
	var tier_one := _player.stats.get_value(&"armor")
	_slots.add(AbilityTestHelpers.passive(&"firewall"))
	assert_int(_slots.tier_of(&"firewall")).is_equal(2)
	assert_float(_player.stats.get_value(&"armor")).is_greater(tier_one)


func test_overclock_is_a_trade_not_a_gift() -> void:
	var hp_before := _player.stats.get_value(&"max_hp")
	_slots.add(AbilityTestHelpers.passive(&"overclock"))
	assert_float(_player.stats.get_value(&"attack_speed")).is_greater(1.0)
	(
		assert_float(_player.stats.get_value(&"max_hp"))
		. override_failure_message("Overclock costs nothing")
		. is_less(hp_before)
	)
