class_name PlayerCameraTest
extends GdUnitTestSuite

var _camera: PlayerCamera
var _target: Node2D


func before_test() -> void:
	_target = auto_free(Node2D.new())
	add_child(_target)
	_camera = auto_free(PlayerCamera.new())
	_camera.enabled = false
	add_child(_camera)
	_camera.follow(_target)


func after_test() -> void:
	GameState.settings["screen_shake"] = true


func test_set_limits_from_rect() -> void:
	_camera.set_limits(Rect2(16, 32, 320, 180))
	assert_int(_camera.limit_left).is_equal(16)
	assert_int(_camera.limit_top).is_equal(32)
	assert_int(_camera.limit_right).is_equal(336)
	assert_int(_camera.limit_bottom).is_equal(212)


func test_follow_moves_toward_target_and_snaps_to_pixels() -> void:
	_target.position = Vector2(100.4, 50.6)
	await PlayerTestHelpers.physics_frames(get_tree(), 5)
	var pos := _camera.global_position
	assert_float(pos.x).is_greater(0.0)
	assert_float(pos.x).is_less(100.0)
	assert_float(pos.x).is_equal_approx(roundf(pos.x), 0.0001)
	await PlayerTestHelpers.physics_frames(get_tree(), 120)
	assert_vector(_camera.global_position).is_equal_approx(Vector2(100, 51), Vector2(1, 1))
	_camera.snap_to(Vector2(7.3, 9.9))
	assert_vector(_camera.global_position).is_equal(Vector2(7, 10))


func test_shake_respects_setting_and_decays() -> void:
	GameState.settings["screen_shake"] = false
	EventBus.screen_shake.emit(6.0, 0.3)
	assert_bool(_camera.is_shaking()).is_false()
	GameState.settings["screen_shake"] = true
	EventBus.screen_shake.emit(6.0, 0.3)
	assert_bool(_camera.is_shaking()).is_true()
	await PlayerTestHelpers.physics_frames(get_tree(), 2)
	var offsets := 0
	for _i in range(6):
		await get_tree().physics_frame
		if _camera.offset != Vector2.ZERO:
			offsets += 1
	assert_int(offsets).is_greater(0)
	await PlayerTestHelpers.physics_frames(get_tree(), 30)
	assert_bool(_camera.is_shaking()).is_false()
	assert_vector(_camera.offset).is_equal(Vector2.ZERO)
