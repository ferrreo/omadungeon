## Boss 2 — The Elder Greybeard (floor 6): def numbers, the three health-gated phases with
## invulnerable transitions, capped/cleaned-up summons, every attack hitbox landing on a dummy
## player, and the death signal the Stairs listen for.
class_name ElderGreybeardTest
extends GdUnitTestSuite

const BOSS_ID := &"elder_greybeard"
const FLOOR := 6
const PLAYER_HP := 8000.0

var _root: Node2D
var _player: EnemyTestPlayer
var _boss: ElderGreybeard
var _hits: Array[DamageInfo] = []


func before_test() -> void:
	_hits = []
	_root = auto_free(Node2D.new()) as Node2D
	add_child(_root)
	_player = EnemyTestPlayer.new()
	_root.add_child(_player)
	_player.global_position = Vector2(160, 100)
	_player.health.setup(PLAYER_HP)
	_player.health.dodge_chance = 0.0
	_player.hurtbox.hit_received.connect(_on_player_hit)
	_boss = EnemyTestHelpers.spawn(BOSS_ID, _root, Vector2(100, 100), FLOOR) as ElderGreybeard
	_boss.set_arena(Vector2(100, 100), 160.0)
	# Three steps: the boss only runs its first _physics_process (and picks a target) after the
	# frame it was added in.
	await _frames(3)
	assert_object(_boss.target).is_same(_player)


func _on_player_hit(info: DamageInfo) -> void:
	_hits.append(info)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await _frames(int(ceilf(seconds * 60.0)) + 4)


## Applies true damage straight to the boss hurtbox (ignores armor, respects invulnerability).
func _true_hit(amount: float) -> float:
	var tags: Array[StringName] = [DamageInfo.TAG_TRUE]
	return _boss.hurtbox.receive(DamageInfo.create(amount, tags, _player, Layers.Team.PLAYER))


func _damage_to(fraction: float) -> void:
	_true_hit(maxf(1.0, _boss.health.hp - _boss.health.max_hp * fraction))


func _hits_tagged(tag: StringName) -> int:
	var count := 0
	for info: DamageInfo in _hits:
		if info.has_tag(tag):
			count += 1
	return count


func test_def_is_a_floor_six_greybeard_boss() -> void:
	var boss_def := EnemyTestHelpers.def(BOSS_ID)
	assert_bool(boss_def.is_boss).is_true()
	assert_int(boss_def.faction).is_equal(EnemyDef.Faction.GREYBEARDS)
	assert_int(boss_def.min_floor).is_equal(FLOOR)
	# A boss is a climax, not a loading screen: a small pool that hits very hard. The
	# shipped 880 HP / 22 damage made a 47 s fight that cost thirteen health.
	assert_float(boss_def.max_hp).is_between(300.0, 600.0)
	assert_float(boss_def.damage).is_between(30.0, 50.0)
	assert_int(boss_def.gold_min).is_greater_equal(150)
	assert_int(boss_def.gold_max).is_less_equal(400)
	assert_int(boss_def.sprite_size).is_equal(32)
	assert_object(boss_def.scene).is_not_null()
	assert_object(boss_def.texture).is_not_null()
	assert_bool(_boss is BossBase).is_true()
	assert_int(_boss.phase).is_equal(1)
	assert_str(_boss.phase_name(1)).is_equal("Read The Manual")
	assert_str(_boss.phase_name(2)).is_equal("RTFM Beam")
	assert_str(_boss.phase_name(3)).is_equal("Beard Tentacles")
	assert_float(_boss.health.max_hp).is_equal_approx(boss_def.scaled_hp(FLOOR), 0.5)
	assert_bool(_boss.hp_bar.visible).is_true()


func test_phases_advance_through_invulnerable_transitions() -> void:
	var phases: Array[int] = []
	_boss.phase_changed.connect(func(value: int) -> void: phases.append(value))
	var feed: Array[Array] = []
	var listener := func(boss: String, fraction: float, phase: int) -> void:
		feed.append([boss, fraction, phase])
	EventBus.boss_health_changed.connect(listener)

	_damage_to(0.6)
	assert_bool(_boss.in_transition).is_true()
	assert_bool(_boss.health.invulnerable).is_true()
	assert_int(_boss.phase).is_equal(1)
	var hp_mid_transition := _boss.health.hp
	assert_float(_true_hit(120.0)).is_equal(0.0)
	assert_float(_boss.health.hp).is_equal(hp_mid_transition)

	await _seconds(_boss.transition_time + 0.2)
	assert_int(_boss.phase).is_equal(2)
	assert_bool(_boss.in_transition).is_false()
	assert_bool(_boss.health.invulnerable).is_false()

	_damage_to(0.2)
	assert_bool(_boss.in_transition).is_true()
	assert_bool(_boss.health.invulnerable).is_true()
	await _seconds(_boss.transition_time + 0.2)
	assert_int(_boss.phase).is_equal(3)
	assert_bool(_boss.health.invulnerable).is_false()

	EventBus.boss_health_changed.disconnect(listener)
	assert_array(phases).is_equal([2, 3])
	assert_int(feed.size()).is_greater(0)
	assert_str(str(feed[feed.size() - 1][0])).is_equal("The Elder Greybeard")
	assert_int(int(feed[feed.size() - 1][2])).is_equal(3)


func test_phase_one_tome_volley_damages_the_player() -> void:
	var spots := _boss.tome_volley()
	assert_int(spots.size()).is_equal(3)
	assert_int(_boss.volleys).is_greater_equal(1)
	assert_float(spots[0].distance_to(_player.global_position)).is_less(2.0)
	await _seconds(1.2)
	assert_int(_hits_tagged(DamageInfo.TAG_RANGED)).is_greater(0)


func test_phase_two_beam_warms_up_sweeps_and_burns() -> void:
	_player.global_position = _boss.global_position + Vector2(60.0, 0.0)
	await get_tree().physics_frame
	_boss.start_beam()
	assert_bool(_boss.beam_active).is_false()
	await _seconds(0.9)
	assert_bool(_boss.beam_active).is_true()
	var angle_before := _boss.beam_angle
	await _seconds(0.6)
	assert_int(_hits_tagged(DamageInfo.TAG_ARCANE)).is_greater(0)
	assert_float(absf(angle_difference(_boss.beam_angle, angle_before))).is_greater(0.05)
	_boss.stop_beam()
	assert_bool(_boss.beam_active).is_false()


func test_phase_two_spike_rows_rotate_across_the_arena() -> void:
	var spawned: Array[Vector2] = []
	var listener := func(kind: StringName, pos: Vector2, duration: float) -> void:
		if kind == &"kernel_spike":
			assert_float(duration).is_greater(0.0)
			spawned.append(pos)
	EventBus.spawn_hazard.connect(listener)
	var first := _boss.spike_row()
	var second := _boss.spike_row()
	EventBus.spawn_hazard.disconnect(listener)
	assert_int(first.size()).is_equal(7)
	assert_int(second.size()).is_equal(7)
	assert_int(spawned.size()).is_equal(14)
	assert_int(_boss.spike_rows).is_equal(2)
	var dir_first := (first[6] - first[0]).normalized()
	var dir_second := (second[6] - second[0]).normalized()
	(
		assert_float(absf(dir_first.dot(dir_second)))
		. override_failure_message("spike rows did not rotate: %s vs %s" % [dir_first, dir_second])
		. is_less(0.99)
	)


func test_phase_three_tentacles_lash_and_damage_the_player() -> void:
	var angles := _boss.tentacle_strike()
	assert_int(angles.size()).is_equal(4)
	assert_int(_boss.tentacle_strikes).is_equal(1)
	assert_int(_boss.tentacles.size()).is_equal(4)
	_player.global_position = _boss.global_position + Vector2.from_angle(angles[0]) * 28.0
	await _seconds(1.0)
	assert_int(_hits_tagged(DamageInfo.TAG_MELEE)).is_greater(0)


func test_summons_are_capped_and_cleared_when_the_boss_dies() -> void:
	var made: Array[EnemyBase] = []
	for _i in range(6):
		made.append_array(_boss.summon_wave())
	await get_tree().physics_frame
	assert_int(made.size()).is_greater(0)
	assert_int(made.size()).is_less_equal(_boss.summon_cap)
	assert_int(_boss.live_summons().size()).is_less_equal(_boss.summon_cap)
	for add: EnemyBase in made:
		assert_str(String(add.def.id)).is_equal("manpage_hurler")

	var died: Array[Node2D] = []
	var listener := func(enemy: Node2D, _killer: Node2D) -> void: died.append(enemy)
	EventBus.enemy_died.connect(listener)
	_true_hit(_boss.health.max_hp * 2.0)
	await _frames(2)
	await get_tree().process_frame
	await get_tree().process_frame
	EventBus.enemy_died.disconnect(listener)
	assert_bool(_boss.health.is_dead()).is_true()
	assert_bool(died.has(_boss)).is_true()
	assert_int(_boss.live_summons().size()).is_equal(0)
	assert_bool(_boss.beam_active).is_false()
