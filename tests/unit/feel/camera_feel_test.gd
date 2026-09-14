class_name CameraFeelTest
extends GdUnitTestSuite

## Half a pixel on each axis: the most the integer snap can lengthen a 2-D vector (sqrt(2)/2).
const SNAP_SLACK := 0.7071067811865476

var _camera: PlayerCamera
var _target: FeelTestHelpers.AimTarget
var _feel: GameFeel


func before_test() -> void:
	_feel = FeelTestHelpers.fresh(get_tree())
	_target = auto_free(FeelTestHelpers.AimTarget.new()) as FeelTestHelpers.AimTarget
	add_child(_target)
	_camera = auto_free(PlayerCamera.new()) as PlayerCamera
	_camera.enabled = false
	add_child(_camera)
	_camera.follow(_target)


func after_test() -> void:
	_feel.reset()
	GameState.settings["screen_shake"] = true


## Runs the camera long enough for the exponential look-ahead to settle.
func _settle(frames: int = 90) -> void:
	await FeelTestHelpers.physics_frames(get_tree(), frames)


func test_look_ahead_leads_the_aim_and_is_clamped_to_the_profile() -> void:
	_target.aim = Vector2.RIGHT
	await _settle()
	var lead := _camera.look_ahead()
	assert_float(lead.x).is_greater(0.0)
	assert_float(lead.length()).is_less_equal(_feel.profile.look_ahead_px + 0.01)
	assert_float(lead.length()).is_equal_approx(_feel.profile.look_ahead_px, 0.5)
	assert_float(_camera.global_position.x).is_greater(_target.global_position.x)


func test_look_ahead_turns_with_the_aim_and_never_overshoots() -> void:
	_target.aim = Vector2.RIGHT
	await _settle()
	_target.aim = Vector2.UP
	await _settle()
	var lead := _camera.look_ahead()
	assert_float(lead.y).is_less(0.0)
	assert_float(absf(lead.x)).is_less(1.0)
	assert_float(lead.length()).is_less_equal(_feel.profile.look_ahead_px + 0.01)


func test_a_target_that_does_not_aim_gets_no_look_ahead() -> void:
	var plain := auto_free(Node2D.new()) as Node2D
	add_child(plain)
	_camera.follow(plain)
	await _settle(30)
	assert_vector(_camera.look_ahead()).is_equal(Vector2.ZERO)
	assert_vector(_camera.global_position).is_equal(Vector2.ZERO)


func test_the_camera_stays_pixel_snapped_through_shake_and_punch() -> void:
	_target.global_position = Vector2(100.4, 50.6)
	_target.aim = Vector2(0.6, -0.8)
	_feel.add_trauma(1.0)
	_feel.punch(Vector2(0.7, 0.7), _feel.profile.punch_px)
	var moved := 0
	for _i in range(20):
		await get_tree().physics_frame
		if _camera.offset != Vector2.ZERO:
			moved += 1
		assert_vector(_camera.global_position).is_equal(_camera.global_position.round())
		assert_vector(_camera.offset).is_equal(_camera.offset.round())
		# The camera caps the shake at `max_shake` and *then* snaps it to whole pixels, and
		# those two cannot both hold exactly: rounding a 2-D vector to the integer lattice
		# moves it by up to half a pixel on each axis, so the magnitude can grow by up to
		# sqrt(2)/2. (6.8, 4.2) is 7.99 long and snaps to (7, 4), which is 8.06 - a reachable
		# lattice point, not a timing artefact, so asserting <= max_shake made the gate red at
		# random. What the cap is actually worth is asserted on both bounds below: the
		# magnitude may only overshoot by that one rounding step, and no single axis may run
		# past the cap's own pixel at all.
		assert_float(_camera.offset.length()).is_less_equal(_camera.max_shake + SNAP_SLACK + 0.01)
		var widest := maxf(absf(_camera.offset.x), absf(_camera.offset.y))
		assert_float(widest).is_less_equal(ceilf(_camera.max_shake))
	assert_int(moved).is_greater(0)


func test_punch_pushes_the_view_along_the_hit_then_settles() -> void:
	_feel.punch(Vector2.RIGHT, _feel.profile.punch_px)
	await FeelTestHelpers.physics_frames(get_tree(), 2)
	assert_float(_camera.offset.x).is_greater(0.0)
	assert_bool(_camera.is_shaking()).is_false()
	await FeelTestHelpers.physics_frames(get_tree(), 40)
	assert_vector(_camera.offset).is_equal(Vector2.ZERO)


func test_screen_shake_setting_keeps_the_view_still() -> void:
	GameState.settings["screen_shake"] = false
	EventBus.screen_shake.emit(6.0, 0.3)
	assert_bool(_camera.is_shaking()).is_false()
	await FeelTestHelpers.physics_frames(get_tree(), 4)
	assert_vector(_camera.offset).is_equal(Vector2.ZERO)
