class_name GameFeelTest
extends GdUnitTestSuite

var _feel: GameFeel


func before_test() -> void:
	_feel = FeelTestHelpers.fresh(get_tree())


func after_test() -> void:
	_feel.enabled = true
	_feel.hit_stop_enabled = true
	_feel.reset()
	GameState.settings["screen_shake"] = true
	GameState.settings["reduced_flash"] = false
	Engine.time_scale = 1.0


func test_the_shipped_profile_resource_is_what_the_service_uses() -> void:
	# A typo in data/feel/feel.tres would silently fall back to the script defaults, so the
	# numbers the game ships with would stop being the ones in the .tres.
	assert_bool(ResourceLoader.exists(FeelProfile.DEFAULT_PATH)).is_true()
	var shipped := load(FeelProfile.DEFAULT_PATH) as FeelProfile
	assert_object(shipped).is_not_null()
	assert_object(_feel.profile).is_same(shipped)
	assert_object(DangerTell.default_profile()).is_same(shipped)
	assert_object(FxPool.instance(get_tree()).profile).is_same(shipped)


func test_hit_stop_is_frame_based_and_never_compounds() -> void:
	assert_bool(_feel.request_hit_stop(2)).is_true()
	assert_int(_feel.hit_stop_frames_left()).is_equal(2)
	assert_float(Engine.time_scale).is_equal_approx(_feel.profile.hit_stop_scale, 0.0001)
	# A second hit landing inside the first stop extends it to the longest, never to the sum.
	assert_bool(_feel.request_hit_stop(3)).is_true()
	assert_int(_feel.hit_stop_frames_left()).is_equal(3)
	assert_bool(_feel.request_hit_stop(1)).is_true()
	assert_int(_feel.hit_stop_frames_left()).is_equal(3)


func test_hit_stop_is_capped_at_the_profile_maximum() -> void:
	_feel.request_hit_stop(999)
	assert_int(_feel.hit_stop_frames_left()).is_equal(_feel.profile.hit_stop_max_frames)


func test_hit_stop_restores_time_and_then_refuses_a_flurry() -> void:
	_feel.request_hit_stop(2)
	await FeelTestHelpers.wait_for_thaw(get_tree(), _feel)
	assert_bool(_feel.is_frozen()).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)
	# The refractory window is what stops six enemies dying at once from freezing the game.
	assert_int(_feel.refractory_frames_left()).is_greater(0)
	assert_bool(_feel.request_hit_stop(4)).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)


func test_disabled_hit_stop_is_a_noop_but_flashes_still_run() -> void:
	_feel.hit_stop_enabled = false
	assert_bool(_feel.request_hit_stop(4)).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)
	assert_float(_feel.flash_scale()).is_greater(0.0)


func test_heavy_hits_freeze_longer_and_shake_harder_than_light_ones() -> void:
	var light := _feel.profile.hit_stop_frames(1.0)
	var heavy := _feel.profile.hit_stop_frames(_feel.profile.heavy_damage + 1.0)
	assert_int(heavy).is_greater(light)
	assert_int(light).is_greater_equal(2)
	assert_int(heavy).is_less_equal(4)
	assert_float(_feel.profile.hit_trauma(_feel.profile.heavy_damage)).is_greater(
		_feel.profile.hit_trauma(1.0)
	)


func test_trauma_decays_to_nothing() -> void:
	_feel.add_trauma(1.0, 0.2)
	assert_float(_feel.trauma()).is_equal_approx(1.0, 0.001)
	await FeelTestHelpers.physics_frames(get_tree(), 3)
	assert_float(_feel.trauma()).is_less(1.0)
	await FeelTestHelpers.physics_frames(get_tree(), 20)
	assert_float(_feel.trauma()).is_equal(0.0)
	assert_vector(_feel.shake_offset()).is_equal(Vector2.ZERO)


func test_screen_shake_setting_gates_trauma_and_punch() -> void:
	GameState.settings["screen_shake"] = false
	_feel.add_trauma(1.0)
	_feel.punch(Vector2.RIGHT, 6.0)
	assert_float(_feel.trauma()).is_equal(0.0)
	assert_vector(_feel.punch_offset()).is_equal(Vector2.ZERO)
	GameState.settings["screen_shake"] = true
	_feel.add_trauma(0.5)
	assert_float(_feel.trauma()).is_greater(0.0)


func test_shake_offset_is_whole_pixels_within_the_profile_cap() -> void:
	_feel.add_trauma(1.0)
	var sampled := 0
	for _i in range(12):
		await get_tree().physics_frame
		var off := _feel.shake_offset()
		assert_vector(off).is_equal(off.round())
		assert_float(absf(off.x)).is_less_equal(_feel.profile.shake_max_offset)
		assert_float(absf(off.y)).is_less_equal(_feel.profile.shake_max_offset)
		if off != Vector2.ZERO:
			sampled += 1
	assert_int(sampled).is_greater(0)


func test_punch_takes_the_strongest_kick_and_decays() -> void:
	_feel.punch(Vector2.RIGHT, 5.0)
	_feel.punch(Vector2.RIGHT, 2.0)
	assert_float(_feel.punch_offset().length()).is_equal_approx(5.0, 0.001)
	assert_float(_feel.punch_offset().x).is_greater(0.0)
	var before := _feel.punch_offset().length()
	await FeelTestHelpers.physics_frames(get_tree(), 3)
	assert_float(_feel.punch_offset().length()).is_less(before)
	await FeelTestHelpers.physics_frames(get_tree(), 40)
	assert_vector(_feel.punch_offset()).is_equal(Vector2.ZERO)


func test_reduced_flash_dims_every_flash_from_one_place() -> void:
	var full := _feel.flash_scale()
	GameState.settings["reduced_flash"] = true
	var dimmed := _feel.flash_scale()
	GameState.settings["reduced_flash"] = false
	assert_float(dimmed).is_less(full)
	assert_float(dimmed).is_equal_approx(full * _feel.profile.reduced_flash_scale, 0.001)


func test_room_ending_blow_slows_time_but_an_already_empty_room_does_not() -> void:
	var dummy := auto_free(Node2D.new()) as Node2D
	add_child(dummy)
	# A room that unlocks with no death behind it is just a door opening.
	EventBus.room_cleared.emit(1)
	assert_bool(_feel.is_frozen()).is_false()
	# The blow that empties the room gets the celebratory slow.
	EventBus.enemy_died.emit(dummy, dummy)
	assert_bool(_feel.room_ending_blow_pending()).is_true()
	EventBus.room_cleared.emit(1)
	assert_bool(_feel.is_frozen()).is_true()
	assert_float(Engine.time_scale).is_equal_approx(_feel.profile.room_clear_slow_scale, 0.001)
	assert_float(_feel.trauma()).is_greater(0.0)
	await FeelTestHelpers.wait_for_thaw(get_tree(), _feel)
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)


func test_room_clear_slow_is_not_a_hit_stop_and_ignores_the_refractory() -> void:
	var dummy := auto_free(Node2D.new()) as Node2D
	add_child(dummy)
	_feel.request_hit_stop(2)
	await FeelTestHelpers.wait_for_thaw(get_tree(), _feel)
	assert_bool(_feel.request_hit_stop(2)).is_false()
	EventBus.enemy_died.emit(dummy, dummy)
	EventBus.room_cleared.emit(2)
	assert_bool(_feel.is_frozen()).is_true()
	assert_float(Engine.time_scale).is_greater(_feel.profile.hit_stop_scale)
	await FeelTestHelpers.wait_for_thaw(get_tree(), _feel)


func test_hit_stop_facade_still_speaks_seconds() -> void:
	HitStop.apply(get_tree(), 0.05)
	assert_bool(HitStop.is_active(get_tree())).is_true()
	assert_int(_feel.hit_stop_frames_left()).is_equal(3)
	HitStop.set_enabled(get_tree(), false)
	assert_bool(HitStop.is_active(get_tree())).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.0001)
	HitStop.set_enabled(get_tree(), true)
