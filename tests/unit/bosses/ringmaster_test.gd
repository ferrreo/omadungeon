## Boss 1 — The Ringmaster: phase gating, invulnerable transitions, capped/cleaned summons,
## every attack landing on a dummy player, and death emitting `enemy_died`.
class_name RingmasterTest
extends GdUnitTestSuite

const BOSS_ID := &"ringmaster"
## Physics frames a 1.5 s transition needs, plus slack.
const TRANSITION_FRAMES := 120


func _arena() -> Node2D:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	root.global_position = Vector2.ZERO
	return root


func _boss(root: Node2D, pos: Vector2 = Vector2(160, 160)) -> Ringmaster:
	var boss := EnemyTestHelpers.spawn(BOSS_ID, root, pos, 2) as Ringmaster
	assert_object(boss).is_not_null()
	boss.set_arena(pos, 110.0)
	return boss


## Dummy player target. `targetable` false keeps the boss AI idle so a single attack can be
## driven by hand and the damage source stays unambiguous.
func _player(root: Node2D, pos: Vector2, targetable: bool = true) -> EnemyTestPlayer:
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = pos
	player.stats.set_base(&"max_hp", 5000.0)
	player.health.setup(5000.0)
	if not targetable:
		player.remove_from_group(&"player")
	return player


## Damages the boss down to `fraction` of its max HP (armor-aware, stops at a transition).
func _grind_to(boss: Ringmaster, fraction: float) -> void:
	for _i in range(24):
		if boss.in_transition or boss.health.fraction() <= fraction:
			return
		var wanted := boss.health.max_hp * fraction
		var soak := Stats.armor_multiplier(boss.health.armor)
		EnemyTestHelpers.hit(boss, maxf(1.0, (boss.health.hp - wanted) / maxf(0.05, soak)))


## Waits until `check` returns true or `frames` physics frames elapsed. Returns the result.
func _until(check: Callable, frames: int) -> bool:
	for _i in range(frames):
		if check.call():
			return true
		await get_tree().physics_frame
	return check.call()


func test_def_numbers_match_the_boss_contract() -> void:
	var def := EnemyTestHelpers.def(BOSS_ID)
	assert_bool(def.is_boss).is_true()
	assert_int(def.min_floor).is_equal(2)
	# A boss is a climax, not a loading screen: a small pool that hits very hard. The
	# shipped 880 HP / 22 damage made a 47 s fight that cost thirteen health.
	assert_float(def.scaled_hp(2)).is_between(350.0, 750.0)
	assert_float(def.damage).is_between(30.0, 50.0)
	assert_int(def.gold_min).is_greater_equal(150)
	assert_int(def.gold_max).is_less_equal(400)
	assert_int(def.sprite_size).is_equal(32)


func test_instantiates_from_its_def() -> void:
	var root := _arena()
	var boss := _boss(root)
	await get_tree().physics_frame
	assert_int(boss.phase).is_equal(1)
	assert_int(boss.phase_count()).is_equal(3)
	assert_str(boss.phase_title()).is_equal("Opening Act")
	assert_float(boss.health.max_hp).is_equal_approx(boss.def.scaled_hp(2), 0.01)
	assert_bool(boss.hp_bar.visible).is_true()


func test_phases_gate_on_health_and_transitions_are_invulnerable() -> void:
	var root := _arena()
	var boss := _boss(root)
	await get_tree().physics_frame
	var seen: Array[int] = []
	boss.phase_changed.connect(func(p: int) -> void: seen.append(p))

	_grind_to(boss, 0.5)
	assert_bool(boss.in_transition).is_true()
	assert_bool(boss.health.invulnerable).is_true()
	var before := boss.health.hp
	EnemyTestHelpers.hit(boss, 100.0)
	assert_float(boss.health.hp).is_equal_approx(before, 0.01)
	assert_bool(await _until(func() -> bool: return boss.phase == 2, TRANSITION_FRAMES)).is_true()
	assert_bool(boss.health.invulnerable).is_false()

	_grind_to(boss, 0.2)
	assert_bool(boss.in_transition).is_true()
	assert_bool(await _until(func() -> bool: return boss.phase == 3, TRANSITION_FRAMES)).is_true()
	assert_array(seen).is_equal([2, 3])
	assert_str(boss.phase_title()).is_equal("Final Bow")


func test_summons_are_capped_and_cleaned_up_on_death() -> void:
	var root := _arena()
	var boss := _boss(root)
	await get_tree().physics_frame
	for _i in range(6):
		boss.summon_wave()
	var alive := boss.live_summons()
	assert_int(alive.size()).is_equal(boss.summon_cap)
	for add: EnemyBase in alive:
		assert_that(add.def.faction).is_equal(EnemyDef.Faction.CLOWNS)
		assert_bool(add.def.is_boss).is_false()
	EnemyTestHelpers.hit(boss, 99999.0)
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(boss.live_summons().size()).is_equal(0)


func test_phase_two_adds_honkers_and_lights_the_fire_ring() -> void:
	var root := _arena()
	var boss := _boss(root)
	await get_tree().physics_frame
	_grind_to(boss, 0.5)
	assert_bool(await _until(func() -> bool: return boss.phase == 2, TRANSITION_FRAMES)).is_true()
	assert_bool(boss.fire_ring.active).is_true()
	assert_int(boss.fire_ring.segment_count()).is_equal(
		boss.fire_ring.segments - boss.fire_ring.gap_slots
	)
	assert_int(boss.whip.hits).is_equal(2)
	var ids: Dictionary = {}
	for _i in range(40):
		for add: EnemyBase in boss.summon_wave():
			ids[add.def.id] = true
		if ids.has(&"honker"):
			break
		for add: EnemyBase in boss.live_summons():
			add.queue_free()
		await get_tree().process_frame
		boss.live_summons()
	assert_bool(ids.has(&"honker")).is_true()


func test_phase_three_sweeps_the_whip_and_brings_a_clown_car() -> void:
	var root := _arena()
	var boss := _boss(root)
	await get_tree().physics_frame
	_grind_to(boss, 0.2)
	assert_bool(await _until(func() -> bool: return boss.phase == 3, TRANSITION_FRAMES)).is_true()
	assert_bool(boss.whip.sweep).is_true()
	var cars := 0
	for add: EnemyBase in boss.live_summons():
		if add.def.id == &"clown_car":
			cars += 1
	assert_int(cars).is_equal(1)


func test_whip_pull_damages_and_yanks_the_player_inward() -> void:
	var root := _arena()
	var boss := _boss(root, Vector2(160, 160))
	var player := _player(root, Vector2(220, 160))
	await get_tree().physics_frame
	var hp := player.health.hp
	var hurt := await _until(func() -> bool: return player.health.hp < hp, 240)
	assert_bool(hurt).override_failure_message("whip never hit the player").is_true()
	assert_float(player.knockback_velocity.x).is_less(0.0)


func test_fire_ring_burns_a_player_standing_in_it() -> void:
	var root := _arena()
	var boss := _boss(root, Vector2(160, 160))
	var player := _player(root, Vector2(160, 160), false)
	await get_tree().physics_frame
	boss.fire_ring.start(Vector2(160, 160), 60.0)
	player.global_position = Vector2(160, 160) + Vector2.RIGHT * 60.0
	var hp := player.health.hp
	var burned := await _until(func() -> bool: return player.health.hp < hp, 300)
	assert_bool(burned).override_failure_message("ring of fire never burned the player").is_true()
	assert_bool(player.status.has(StatusEffect.Kind.BURN)).is_true()
	boss.fire_ring.stop()


func test_confetti_barrage_fires_waves_with_safe_lanes() -> void:
	var root := _arena()
	var boss := _boss(root, Vector2(160, 160))
	var player := _player(root, Vector2(180, 160), false)
	await get_tree().physics_frame
	boss.target = player
	# The boss drives `tick()` from its ATTACK state; here the suite drives it directly so the
	# barrage can be exercised without waiting for phase 3 to come around.
	boss.run_attack(boss.confetti, player.global_position)
	var step := 1.0 / 60.0
	var hurt := false
	for _i in range(240):
		if boss.confetti.running:
			boss.confetti.tick(step)
		await get_tree().physics_frame
		if player.health.hp < player.health.max_hp:
			hurt = true
			break
	assert_int(boss.confetti.waves_fired).is_greater(0)
	assert_int(boss.confetti.last_fired.size()).is_equal(
		boss.confetti.lanes - boss.confetti.safe_lanes
	)
	var safe := 0
	for i in range(boss.confetti.lanes):
		if boss.confetti.is_safe_lane(i):
			safe += 1
	assert_int(safe).is_equal(boss.confetti.safe_lanes)
	assert_bool(hurt).override_failure_message("confetti never hit the player").is_true()


func test_dies_and_emits_enemy_died() -> void:
	var root := _arena()
	var boss := _boss(root)
	await get_tree().physics_frame
	var dead: Array[Node2D] = []
	var handler := func(enemy: Node2D, _killer: Node2D) -> void: dead.append(enemy)
	EventBus.enemy_died.connect(handler)
	EnemyTestHelpers.hit(boss, 99999.0)
	await get_tree().physics_frame
	EventBus.enemy_died.disconnect(handler)
	assert_int(dead.size()).is_equal(1)
	assert_object(dead[0]).is_same(boss)
	assert_bool(boss.def.is_boss).is_true()
	assert_int(boss.state).is_equal(EnemyBase.State.DEAD)
