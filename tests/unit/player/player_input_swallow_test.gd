## The press that closed a menu must not reach the run. `ui_accept` shares gamepad A and Space
## with `dodge`, and the Player polls `Input` state rather than handling events, so a UI
## consuming the event changes nothing: the tick after input comes back, the same press is
## still `just_pressed`. Every case drives a real device event through `Input`, and reads the
## result the way the Player does - from `_physics_process`, one tick behind `PlayerInput`.
class_name PlayerInputSwallowTest
extends GdUnitTestSuite


## Stands in for the Player: polls once per physics tick, after `PlayerInput` (default
## priority 0 runs after `LATCH_PRIORITY`), and counts what it would have acted on.
class Probe:
	extends Node
	var input: PlayerInput
	var dodges: int = 0
	var attacks: int = 0
	var attack_releases: int = 0
	var held_ticks: int = 0

	func _physics_process(_delta: float) -> void:
		if input.dodge_just_pressed():
			dodges += 1
		if input.attack_just_pressed():
			attacks += 1
		if input.attack_just_released():
			attack_releases += 1
		if input.attack_held():
			held_ticks += 1


var _holder: Node
var _input: PlayerInput
var _probe: Probe
var _saved: Dictionary


func before_test() -> void:
	_saved = GameState.settings.duplicate(true)
	GameState.settings["hold_mode"] = {}
	GameState.settings["hold_to_toggle"] = false
	# A pausable parent, the way the Player is: a paused tree blocks it, not the input node.
	_holder = auto_free(Node.new())
	add_child(_holder)
	_input = PlayerInput.new()
	_holder.add_child(_input)
	_probe = Probe.new()
	_probe.input = _input
	_holder.add_child(_probe)
	await _ticks(2)


func after_test() -> void:
	_pad(JOY_BUTTON_A, false)
	_key(KEY_SPACE, false)
	_trigger(0.0)
	get_tree().paused = false
	await _ticks(2)
	GameState.settings = _saved


func _pad(button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## `attack` is the right trigger on a pad: an axis, so a press is the trigger pulled in.
func _trigger(value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = JOY_AXIS_TRIGGER_RIGHT
	ev.axis_value = value
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _ticks(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


# ---------------------------------------------------------------- input handed back


func test_the_a_press_that_re_enabled_input_does_not_dodge() -> void:
	_input.enabled = false
	_pad(JOY_BUTTON_A, true)
	await _ticks(1)
	# The board picked its card and gave input back, all on this press.
	_input.enabled = true
	await _ticks(4)
	assert_bool(_input.is_swallowed(&"dodge")).is_true()
	assert_int(_probe.dodges).is_equal(0)

	# A fresh press after the release is a real dodge.
	_pad(JOY_BUTTON_A, false)
	await _ticks(3)
	assert_bool(_input.is_swallowed(&"dodge")).is_false()
	_pad(JOY_BUTTON_A, true)
	await _ticks(3)
	assert_int(_probe.dodges).is_equal(1)


func test_the_space_press_that_re_enabled_input_does_not_dodge() -> void:
	_input.enabled = false
	_key(KEY_SPACE, true)
	await _ticks(1)
	_input.enabled = true
	await _ticks(4)
	assert_int(_probe.dodges).is_equal(0)
	_key(KEY_SPACE, false)
	await _ticks(3)
	_key(KEY_SPACE, true)
	await _ticks(3)
	assert_int(_probe.dodges).is_equal(1)


func test_a_press_made_after_input_came_back_is_honoured() -> void:
	_input.enabled = false
	await _ticks(2)
	_input.enabled = true
	await _ticks(2)
	_pad(JOY_BUTTON_A, true)
	await _ticks(3)
	assert_int(_probe.dodges).is_equal(1)


func test_a_tap_released_before_the_first_live_tick_is_still_swallowed() -> void:
	_input.enabled = false
	await _ticks(1)
	# Press and release between two ticks: `just_pressed` still reads true on the next one.
	_pad(JOY_BUTTON_A, true)
	_input.enabled = true
	_pad(JOY_BUTTON_A, false)
	await _ticks(4)
	assert_int(_probe.dodges).is_equal(0)


func test_a_held_action_is_neither_held_nor_edged_until_released() -> void:
	_input.enabled = false
	_trigger(1.0)
	await _ticks(1)
	_input.enabled = true
	await _ticks(4)
	assert_int(_probe.attacks).is_equal(0)
	assert_int(_probe.held_ticks).is_equal(0)
	_trigger(0.0)
	await _ticks(3)
	# The release edge of a swallowed press is eaten with it.
	assert_int(_probe.attack_releases).is_equal(0)
	_trigger(1.0)
	await _ticks(3)
	assert_int(_probe.attacks).is_equal(1)
	assert_int(_probe.held_ticks).is_greater(0)
	_trigger(0.0)
	await _ticks(3)
	assert_int(_probe.attack_releases).is_equal(1)


func test_a_swallowed_press_does_not_flip_a_toggle_latch() -> void:
	GameState.settings["hold_mode"] = {"attack": PlayerInput.MODE_TOGGLE}
	_input.enabled = false
	_trigger(1.0)
	await _ticks(1)
	_input.enabled = true
	await _ticks(4)
	assert_bool(_input.is_latched(&"attack")).is_false()
	assert_int(_probe.attacks).is_equal(0)
	_trigger(0.0)
	await _ticks(3)
	_trigger(1.0)
	await _ticks(3)
	assert_bool(_input.is_latched(&"attack")).is_true()


# ---------------------------------------------------------------- tree unpaused


func test_the_press_that_unpaused_the_tree_does_not_dodge() -> void:
	# The pause menu never touches `enabled`: it pauses the tree over the Player and unpauses
	# on Resume, which A confirms.
	get_tree().paused = true
	await _ticks(2)
	_pad(JOY_BUTTON_A, true)
	get_tree().paused = false
	await _ticks(4)
	assert_int(_probe.dodges).is_equal(0)
	_pad(JOY_BUTTON_A, false)
	await _ticks(3)
	_pad(JOY_BUTTON_A, true)
	await _ticks(3)
	assert_int(_probe.dodges).is_equal(1)


func test_every_gameplay_action_is_covered() -> void:
	for action: StringName in [
		&"attack", &"secondary", &"dodge", &"interact", &"potion", &"active_1", &"active_2"
	]:
		assert_bool(PlayerInput.GAMEPLAY_ACTIONS.has(action)).is_true()
		assert_bool(InputMap.has_action(action)).is_true()
