class_name PlayerInputTest
extends GdUnitTestSuite

var _input: PlayerInput


func before_test() -> void:
	# The device is shared state (`InputGlyphs`), and a suite before this one may have left the
	# pad live; every case here starts from the keyboard with the pad never heard from.
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)
	UiRuntime.get_shared().last_pad_msec = -1
	_input = auto_free(PlayerInput.new())
	add_child(_input)
	await get_tree().process_frame


func after_test() -> void:
	for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key(key, false)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame


func _key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _axis(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func _settle() -> void:
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame


func test_move_vector_is_normalised_on_diagonal() -> void:
	_key(KEY_W, true)
	_key(KEY_D, true)
	await _settle()
	var v := _input.move_vector()
	assert_float(v.length()).is_equal_approx(1.0, 0.01)
	assert_vector(v).is_equal_approx(Vector2(1, -1).normalized(), Vector2(0.01, 0.01))


func test_move_vector_single_axis() -> void:
	_key(KEY_A, true)
	await _settle()
	assert_vector(_input.move_vector()).is_equal_approx(Vector2.LEFT, Vector2(0.01, 0.01))
	_key(KEY_A, false)
	await _settle()
	assert_vector(_input.move_vector()).is_equal(Vector2.ZERO)


func test_disabled_input_is_idle() -> void:
	_key(KEY_S, true)
	await _settle()
	_input.enabled = false
	assert_vector(_input.move_vector()).is_equal(Vector2.ZERO)
	assert_bool(_input.attack_held()).is_false()


func test_gamepad_switches_device_and_emits_event() -> void:
	var seen: Array[int] = []
	var handler := func(device: int) -> void: seen.append(device)
	EventBus.input_device_changed.connect(handler)
	assert_int(_input.last_device).is_equal(PlayerInput.Device.KBM)
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _settle()
	assert_int(_input.last_device).is_equal(PlayerInput.Device.GAMEPAD)
	assert_bool(_input.is_gamepad()).is_true()
	assert_array(seen).contains([PlayerInput.Device.GAMEPAD])
	assert_vector(_input.move_vector()).is_equal_approx(Vector2.RIGHT, Vector2(0.01, 0.01))
	# A nudged mouse inside the grace window is not the player reaching for the keyboard
	# (`InputGlyphs.observe`): the pad keeps the device, and no change is broadcast.
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(3, 0)
	Input.parse_input_event(motion)
	await _settle()
	assert_int(_input.last_device).is_equal(PlayerInput.Device.GAMEPAD)
	assert_array(seen).not_contains([PlayerInput.Device.KBM])
	# Once the pad has been quiet for the grace window, motion does mean the mouse.
	UiRuntime.get_shared().last_pad_msec = -1
	Input.parse_input_event(motion)
	await _settle()
	assert_int(_input.last_device).is_equal(PlayerInput.Device.KBM)
	assert_array(seen).contains([PlayerInput.Device.KBM])
	EventBus.input_device_changed.disconnect(handler)


func test_gamepad_aim_uses_right_stick_then_auto_aim_then_fallback() -> void:
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _settle()
	assert_vector(_input.aim_direction(Vector2.ZERO, Vector2.RIGHT)).is_equal_approx(
		Vector2.UP, Vector2(0.01, 0.01)
	)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await _settle()
	var target := auto_free(Node2D.new()) as Node2D
	target.position = Vector2(0, 50)
	add_child(target)
	_input.auto_aim_target = target
	assert_vector(_input.aim_direction(Vector2.ZERO, Vector2.RIGHT)).is_equal_approx(
		Vector2.DOWN, Vector2(0.01, 0.01)
	)
	_input.auto_aim_target = null
	assert_vector(_input.aim_direction(Vector2.ZERO, Vector2.LEFT)).is_equal_approx(
		Vector2.LEFT, Vector2(0.01, 0.01)
	)


func test_deadzone_reads_settings() -> void:
	var old: Variant = GameState.settings.get("move_deadzone", null)
	GameState.settings["move_deadzone"] = 0.5
	assert_float(_input.move_deadzone()).is_equal_approx(0.5, 0.001)
	if old == null:
		GameState.settings.erase("move_deadzone")
	else:
		GameState.settings["move_deadzone"] = old


func test_cursor_is_restored_when_the_node_leaves_the_tree() -> void:
	var node := PlayerInput.new()
	add_child(node)
	await get_tree().process_frame
	node._show_cursor(false)
	assert_bool(node._cursor_hidden).is_true()
	node.free()
	# Headless has no real cursor, so assert on the mode the node asked the OS for.
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
