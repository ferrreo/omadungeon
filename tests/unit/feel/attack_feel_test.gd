class_name AttackFeelTest
extends GdUnitTestSuite

var _player: Player
var _wc: WeaponController
var _feel: GameFeel


func before_test() -> void:
	_feel = FeelTestHelpers.fresh(get_tree())
	_feel.hit_stop_enabled = false
	_player = auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(_player)
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.input.enabled = false
	_player.health.dodge_chance = 0.0
	_wc = _player.weapon_controller
	await get_tree().physics_frame


func after_test() -> void:
	_feel.enabled = true
	_feel.hit_stop_enabled = true
	_feel.reset()
	Engine.time_scale = 1.0


func test_a_swing_runs_anticipation_then_impact_then_recovery() -> void:
	assert_int(_wc.phase()).is_equal(WeaponController.Phase.READY)
	assert_bool(_wc.try_attack(Vector2.RIGHT)).is_true()
	assert_int(_wc.phase()).is_equal(WeaponController.Phase.ANTICIPATION)
	await FeelTestHelpers.physics_frames(get_tree(), 5)
	assert_int(_wc.phase()).is_equal(WeaponController.Phase.IMPACT)
	await FeelTestHelpers.physics_frames(get_tree(), 8)
	assert_int(_wc.phase()).is_equal(WeaponController.Phase.RECOVERY)
	assert_bool(_wc.is_in_recovery()).is_true()
	await FeelTestHelpers.physics_frames(get_tree(), 40)
	assert_int(_wc.phase()).is_equal(WeaponController.Phase.READY)
	assert_bool(_wc.is_ready()).is_true()


func test_the_hitbox_is_live_from_the_first_anticipation_frame() -> void:
	# Anticipation is weight, not input lag: a committed swing must never be eaten.
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(14, 0))) as Entity
	add_child(dummy)
	await FeelTestHelpers.physics_frames(get_tree(), 2)
	_wc.try_attack(Vector2.RIGHT)
	assert_int(_wc.phase()).is_equal(WeaponController.Phase.ANTICIPATION)
	# `monitoring` is applied deferred (Hitbox must survive being toggled inside an overlap
	# callback), so the box says it is live now and the physics flag follows within the frame.
	assert_bool(_wc.hitbox.is_live()).is_true()
	await FeelTestHelpers.physics_frames(get_tree(), 1)
	assert_bool(_wc.hitbox.monitoring).is_true()
	await FeelTestHelpers.physics_frames(get_tree(), 4)
	assert_float(dummy.health.hp).is_less(dummy.health.max_hp)


func test_the_hitbox_closes_when_the_impact_window_ends() -> void:
	_wc.try_attack(Vector2.RIGHT)
	var window := WeaponController.MELEE_ANTICIPATION + WeaponController.MELEE_ACTIVE_TIME
	await FeelTestHelpers.physics_frames(get_tree(), int(window * 60.0) + 3)
	assert_bool(_wc.hitbox.monitoring).is_false()
	assert_bool(_wc.is_in_recovery()).is_true()


func test_a_dodge_cancels_the_recovery_so_the_tail_never_traps_the_player() -> void:
	_wc.try_attack(Vector2.RIGHT)
	await FeelTestHelpers.physics_frames(get_tree(), 12)
	assert_bool(_wc.is_in_recovery()).is_true()
	assert_bool(_wc.is_ready()).is_false()
	assert_bool(_player.try_dodge(Vector2.RIGHT)).is_true()
	assert_int(_wc.phase()).is_equal(WeaponController.Phase.READY)
	assert_bool(_wc.is_ready()).is_true()


func test_the_impact_window_itself_cannot_be_cancelled() -> void:
	_wc.try_attack(Vector2.RIGHT)
	await FeelTestHelpers.physics_frames(get_tree(), 5)
	assert_int(_wc.phase()).is_equal(WeaponController.Phase.IMPACT)
	assert_bool(_wc.cancel_recovery()).is_false()
	assert_bool(_wc.is_ready()).is_false()


func test_a_finisher_is_still_rate_limited_while_it_winds_up() -> void:
	assert_bool(_wc.try_attack(Vector2.RIGHT)).is_true()
	assert_bool(_wc.try_attack(Vector2.RIGHT)).is_false()
	assert_int(_wc.combo_index).is_equal(1)


func test_a_crit_queues_one_hit_stop_for_a_whole_flurry() -> void:
	_feel.hit_stop_enabled = true
	_feel.reset()
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(14, 0))) as Entity
	add_child(dummy)
	var info := DamageInfo.create(50.0, [DamageInfo.TAG_MELEE], _player, Layers.Team.PLAYER)
	info.is_crit = true
	_player.on_weapon_hit(dummy, info)
	var frames := _feel.hit_stop_frames_left()
	assert_int(frames).is_equal(_feel.profile.hit_stop_heavy_frames)
	# Three more hits in the same breath must not add up to a longer freeze.
	_player.on_weapon_hit(dummy, info)
	_player.on_weapon_hit(dummy, info)
	assert_int(_feel.hit_stop_frames_left()).is_equal(frames)


func test_a_light_hit_does_not_freeze_the_game_at_all() -> void:
	_feel.hit_stop_enabled = true
	_feel.reset()
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(14, 0))) as Entity
	add_child(dummy)
	var info := DamageInfo.create(4.0, [DamageInfo.TAG_MELEE], _player, Layers.Team.PLAYER)
	_player.on_weapon_hit(dummy, info)
	assert_bool(_feel.is_frozen()).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)
	# ...but it still registers as a nudge of shake.
	assert_float(_feel.trauma()).is_greater(0.0)
