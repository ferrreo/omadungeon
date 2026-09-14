class_name PlayerHitStopTest
extends GdUnitTestSuite


func after_test() -> void:
	HitStop.set_enabled(get_tree(), true)
	Engine.time_scale = 1.0


func test_hit_stop_slows_then_restores_time_scale() -> void:
	HitStop.set_enabled(get_tree(), true)
	HitStop.apply(get_tree(), 0.05)
	assert_float(Engine.time_scale).is_equal_approx(HitStop.DEFAULT_SCALE, 0.001)
	assert_bool(HitStop.is_active(get_tree())).is_true()
	await get_tree().create_timer(0.2, true, false, true).timeout
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)
	assert_bool(HitStop.is_active(get_tree())).is_false()


func test_disabled_hit_stop_is_noop() -> void:
	HitStop.set_enabled(get_tree(), false)
	HitStop.apply(get_tree(), 0.05)
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.001)
