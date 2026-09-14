## Floor 9 final boss. Covers the def, the three phases, the invulnerable transitions, the
## capped/cleaned-up hires, every damage source landing on a dummy player, the briefcase
## buy-back gate, the bought ability slots and the death signal RunManager wins the run on.
class_name TheSuitTest
extends GdUnitTestSuite

const FLOOR := 8
const BOSS_ID := &"the_suit"


func _root() -> Node2D:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	return root


func _spawn(root: Node2D, pos: Vector2 = Vector2.ZERO) -> TheSuit:
	var boss := EnemyTestHelpers.spawn(BOSS_ID, root, pos, FLOOR) as TheSuit
	boss.transition_time = 0.2
	return boss


func _true_hit(target_health: Health, amount: float) -> float:
	var tags: Array[StringName] = [DamageInfo.TAG_TRUE]
	return target_health.take_damage(DamageInfo.create(amount, tags, null, Layers.Team.PLAYER))


## Chips the boss down to `fraction` of its max HP, waiting out invulnerable transitions.
func _drive_to(boss: BossBase, fraction: float) -> void:
	for _i in range(240):
		if boss.health.is_dead() or boss.health.fraction() <= fraction:
			return
		if not boss.health.invulnerable:
			_true_hit(boss.health, boss.health.hp - boss.health.max_hp * fraction)
		await get_tree().physics_frame


func _await_phase(boss: BossBase, phase: int) -> void:
	await _drive_to(boss, boss.phase_thresholds[phase - 2] - 0.02)
	for _i in range(120):
		if boss.phase >= phase and not boss.in_transition:
			return
		await get_tree().physics_frame


# --- def + spawn ----------------------------------------------------------------------------


func test_def_matches_the_boss_contract() -> void:
	var def := EnemyTestHelpers.def(BOSS_ID)
	assert_bool(def.is_boss).is_true()
	assert_int(def.min_floor).is_equal(FLOOR)
	assert_that(def.faction).is_equal(EnemyDef.Faction.BOSS)
	# A boss is a climax, not a loading screen: a small pool that hits very hard. The
	# shipped 880 HP / 22 damage made a 47 s fight that cost thirteen health.
	assert_float(def.max_hp).is_between(300.0, 600.0)
	assert_float(def.damage).is_between(30.0, 50.0)
	assert_int(def.gold_min).is_between(150, 400)
	assert_int(def.gold_max).is_between(150, 400)
	assert_int(def.sprite_size).is_equal(32)
	assert_object(def.scene).is_not_null()
	assert_object(def.texture).is_not_null()
	assert_int(def.summon_defs.size()).is_equal(3)


func test_instantiates_from_its_def() -> void:
	var root := _root()
	var boss := _spawn(root)
	await get_tree().physics_frame
	assert_object(boss).is_not_null()
	assert_int(boss.phase).is_equal(1)
	assert_int(boss.phase_count()).is_equal(3)
	assert_float(boss.health.max_hp).is_equal_approx(boss.def.scaled_hp(FLOOR), 0.01)
	assert_float(boss.health.fraction()).is_equal_approx(1.0, 0.001)
	assert_bool(boss.health.invulnerable).is_false()
	assert_object(boss.sprite.sprite_frames).is_not_null()


# --- phases ---------------------------------------------------------------------------------


func test_reaches_every_phase_and_transitions_are_invulnerable() -> void:
	var root := _root()
	var boss := _spawn(root)
	await get_tree().physics_frame
	var phases: Array[int] = []
	boss.phase_changed.connect(func(value: int) -> void: phases.append(value))

	_true_hit(boss.health, boss.health.hp - boss.health.max_hp * 0.5)
	assert_bool(boss.in_transition).is_true()
	assert_bool(boss.health.invulnerable).is_true()
	var during := boss.health.hp
	_true_hit(boss.health, 500.0)
	assert_float(boss.health.hp).is_equal_approx(during, 0.01)

	await _await_phase(boss, 2)
	assert_int(boss.phase).is_equal(2)
	assert_bool(boss.health.invulnerable).is_false()
	assert_object(boss.zone).is_not_null()

	await _await_phase(boss, 3)
	assert_int(boss.phase).is_equal(3)
	assert_array(phases).contains([2, 3])


func test_phase_two_seizes_the_arena_and_phase_three_shrinks_it() -> void:
	var root := _root()
	var boss := _spawn(root)
	await get_tree().physics_frame
	await _await_phase(boss, 2)
	assert_that(boss.zone.mode).is_equal(TheSuitZone.Mode.SEIZE)
	await _await_phase(boss, 3)
	assert_that(boss.zone.mode).is_equal(TheSuitZone.Mode.SHRINK)
	assert_float(boss.zone.safe_radius()).is_less(boss.arena_radius)


# --- hires ----------------------------------------------------------------------------------


func test_hires_cover_all_three_factions() -> void:
	var root := _root()
	var boss := _spawn(root)
	await get_tree().physics_frame
	var wave := boss.hire_wave()
	assert_int(wave.size()).is_equal(3)
	var factions: Array[int] = []
	for add: EnemyBase in wave:
		factions.append(int(add.def.faction))
	assert_bool(factions.has(int(EnemyDef.Faction.CLOWNS))).is_true()
	assert_bool(factions.has(int(EnemyDef.Faction.GREYBEARDS))).is_true()
	assert_bool(factions.has(int(EnemyDef.Faction.TINKERERS))).is_true()


func test_hires_are_capped_and_cleaned_up_on_death() -> void:
	var root := _root()
	var boss := _spawn(root)
	await get_tree().physics_frame
	for _i in range(6):
		boss.hire_wave()
	var live := boss.live_summons()
	assert_int(live.size()).is_equal(boss.summon_cap)
	_true_hit(boss.health, boss.health.max_hp * 2.0)
	assert_bool(boss.health.is_dead()).is_true()
	await get_tree().physics_frame
	await get_tree().process_frame
	for add: EnemyBase in live:
		assert_bool(not is_instance_valid(add) or add.is_queued_for_deletion()).is_true()


# --- damage sources -------------------------------------------------------------------------


func test_coin_burst_damages_a_player_in_range() -> void:
	var root := _root()
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(140, 0)
	var boss := _spawn(root, Vector2(40, 0))
	var before := player.health.hp
	var hit := false
	for _i in range(240):
		await get_tree().physics_frame
		if player.health.hp < before:
			hit = true
			break
	assert_bool(hit).override_failure_message("state %s" % boss.state).is_true()


func test_seized_sector_damages_a_player_standing_in_it() -> void:
	var root := _root()
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(60, 0)
	var zone := TheSuitZone.new()
	root.add_child(zone)
	zone.sector_angle = 0.0
	zone.setup(Vector2.ZERO, 100.0, 12.0, 0.2)
	zone.arm(TheSuitZone.Mode.SEIZE, 0.05, 1.0)
	assert_bool(zone.is_live()).is_false()
	var before := player.health.hp
	var hit := false
	for _i in range(120):
		await get_tree().physics_frame
		if player.health.hp < before:
			hit = true
			break
	assert_bool(hit).is_true()
	assert_bool(zone.is_live()).is_true()
	assert_bool(zone.contains_point(Vector2(60, 0))).is_true()
	assert_bool(zone.contains_point(Vector2(-60, 0))).is_false()


func test_shrinking_arena_damages_a_player_outside_the_safe_circle() -> void:
	var root := _root()
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(97, 0)
	var zone := TheSuitZone.new()
	root.add_child(zone)
	zone.setup(Vector2.ZERO, 100.0, 12.0, 0.2)
	zone.arm(TheSuitZone.Mode.SHRINK, 0.05, 0.3)
	var before := player.health.hp
	var hit := false
	for _i in range(120):
		await get_tree().physics_frame
		if player.health.hp < before:
			hit = true
			break
	assert_bool(hit).is_true()
	assert_bool(zone.contains_point(Vector2(97, 0))).is_true()
	assert_bool(zone.contains_point(Vector2.ZERO)).is_false()


# --- briefcases -----------------------------------------------------------------------------


func test_briefcase_ignores_damage_amounts_and_pops_one_latch_per_hit() -> void:
	var root := _root()
	var case := TheSuitBriefcase.new()
	case.setup(3)
	root.add_child(case)
	await get_tree().physics_frame
	var tags: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
	case.hurtbox.receive(DamageInfo.create(9999.0, tags, null, Layers.Team.PLAYER))
	assert_int(case.latches).is_equal(2)
	assert_bool(case.is_broken).is_false()
	for _i in range(3):
		await get_tree().create_timer(0.15).timeout
		case.hurtbox.receive(DamageInfo.create(1.0, tags, null, Layers.Team.PLAYER))
	assert_int(case.latches).is_equal(0)
	assert_bool(case.is_broken).is_true()


func test_buyback_heals_until_both_briefcases_break() -> void:
	var root := _root()
	var boss := _spawn(root)
	await get_tree().physics_frame
	await _await_phase(boss, 3)
	var cases := boss.live_briefcases()
	assert_int(cases.size()).is_equal(2)
	assert_bool(boss.is_buying_back()).is_true()
	var before := boss.health.hp
	for _i in range(45):
		await get_tree().physics_frame
	assert_float(boss.health.hp).is_greater(before)
	for case: TheSuitBriefcase in cases:
		for _i in range(60):
			if case.is_broken:
				break
			case.pop_latch()
			await get_tree().physics_frame
	assert_bool(boss.is_buying_back()).is_false()
	var flat := boss.health.hp
	for _i in range(30):
		await get_tree().physics_frame
	assert_float(boss.health.hp).is_equal_approx(flat, 0.01)


# --- hostile takeover of the loadout ---------------------------------------------------------


func test_every_phase_change_buys_an_ability_slot_and_death_returns_them() -> void:
	var root := _root()
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(400, 0)
	var slots := AbilitySlots.attach(player)
	var passive := PassiveAbility.new()
	passive.id = &"test_passive"
	passive.display_name = "Test Passive"
	slots.add(passive)
	var boss := _spawn(root)
	await get_tree().physics_frame
	await _await_phase(boss, 2)
	var bought := 0
	for index in range(AbilitySlots.SLOT_COUNT):
		if slots.is_slot_disabled(index):
			bought += 1
	assert_int(bought).is_equal(1)
	await _await_phase(boss, 3)
	bought = 0
	for index in range(AbilitySlots.SLOT_COUNT):
		if slots.is_slot_disabled(index):
			bought += 1
	assert_int(bought).is_equal(2)
	_true_hit(boss.health, boss.health.max_hp * 2.0)
	for index in range(AbilitySlots.SLOT_COUNT):
		assert_bool(slots.is_slot_disabled(index)).is_false()


func test_disabled_passive_slot_stops_dispatching_hooks() -> void:
	var root := _root()
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	var slots := AbilitySlots.attach(player)
	var passive := PassiveAbility.new()
	passive.id = &"test_passive"
	slots.add(passive)
	var index := slots.index_of(&"test_passive")
	assert_int(index).is_greater_equal(AbilitySlots.ACTIVE_COUNT)
	assert_int(slots.all_passives().size()).is_equal(1)
	slots.set_slot_disabled(index, true)
	assert_int(slots.all_passives().size()).is_equal(0)
	slots.set_slot_disabled(index, false)
	assert_int(slots.all_passives().size()).is_equal(1)


# --- death ----------------------------------------------------------------------------------


func test_death_emits_enemy_died_and_drops_boss_gold() -> void:
	var root := _root()
	var boss := _spawn(root)
	await get_tree().physics_frame
	var dead: Array[Node2D] = []
	var gold: Array[int] = []
	var on_died := func(enemy: Node2D, _killer: Node2D) -> void: dead.append(enemy)
	var on_pickup := func(kind: StringName, _pos: Vector2, amount: int) -> void:
		if kind == &"gold":
			gold.append(amount)
	EventBus.enemy_died.connect(on_died)
	EventBus.spawn_pickup.connect(on_pickup)
	_true_hit(boss.health, boss.health.max_hp * 2.0)
	EventBus.enemy_died.disconnect(on_died)
	EventBus.spawn_pickup.disconnect(on_pickup)
	assert_int(dead.size()).is_equal(1)
	assert_object(dead[0]).is_same(boss)
	assert_int(gold.size()).is_equal(1)
	assert_int(gold[0]).is_greater_equal(300)
