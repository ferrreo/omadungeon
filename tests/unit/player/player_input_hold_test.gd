## Held actions in HOLD and TOGGLE mode. The latch is what lets a player who cannot keep a
## trigger down still attack continuously, so it has to survive the button being released
## and it has to report a clean pressed/released edge exactly once.
class_name PlayerInputHoldTest
extends GdUnitTestSuite

var _input: PlayerInput
var _saved: Dictionary


func before_test() -> void:
	_saved = GameState.settings.duplicate(true)
	GameState.settings["hold_mode"] = {}
	GameState.settings["hold_to_toggle"] = false
	_input = auto_free(PlayerInput.new())
	add_child(_input)
	await get_tree().process_frame


func after_test() -> void:
	_release_all()
	await get_tree().physics_frame
	await get_tree().physics_frame
	GameState.settings = _saved


func _release_all() -> void:
	for action: StringName in PlayerInput.HOLD_ACTIONS:
		Input.action_release(action)


## `SceneTree.physics_frame` fires at the *start* of a tick, before `_physics_process` runs.
## So a button state has to be set right after one of those signals (aligning the change with
## a frame that has not processed yet) and read right after the next one — that window is
## exactly what a caller inside `_physics_process` sees, edges included.
func _tick() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _set_action(action: StringName, pressed: bool) -> void:
	await get_tree().physics_frame
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
	await get_tree().physics_frame


func _press(action: StringName) -> void:
	await _set_action(action, true)


func _release(action: StringName) -> void:
	await _set_action(action, false)


## A press and release, the way a tap reaches the game.
func _tap(action: StringName) -> void:
	await _press(action)
	await _release(action)


func _mode(action: StringName, mode: String) -> void:
	var modes: Dictionary = GameState.settings["hold_mode"]
	modes[String(action)] = mode
	GameState.settings["hold_mode"] = modes


func test_hold_mode_reports_the_raw_button_state() -> void:
	_mode(&"attack", PlayerInput.MODE_HOLD)
	assert_bool(_input.attack_held()).is_false()
	await _press(&"attack")
	assert_bool(_input.attack_held()).is_true()
	await _release(&"attack")
	assert_bool(_input.attack_held()).is_false()


func test_toggle_mode_latches_across_the_release() -> void:
	_mode(&"attack", PlayerInput.MODE_TOGGLE)
	await _tap(&"attack")
	# The button is already back up; a hold-mode reading would be false here.
	assert_bool(Input.is_action_pressed(&"attack")).is_false()
	assert_bool(_input.attack_held()).is_true()
	assert_bool(_input.is_latched(&"attack")).is_true()
	await _tap(&"attack")
	assert_bool(_input.attack_held()).is_false()


func test_toggle_mode_reports_one_pressed_edge_and_one_released_edge() -> void:
	_mode(&"attack", PlayerInput.MODE_TOGGLE)
	await _press(&"attack")
	assert_bool(_input.attack_just_pressed()).is_true()
	# Asking twice in the same tick must not invent a second edge for the weapon controller.
	assert_bool(_input.attack_just_pressed()).is_true()
	assert_bool(_input.attack_just_released()).is_false()
	await _release(&"attack")
	assert_bool(_input.attack_just_pressed()).is_false()
	assert_bool(_input.attack_held()).is_true()
	await _press(&"attack")
	assert_bool(_input.attack_just_released()).is_true()
	assert_bool(_input.attack_held()).is_false()


func test_switching_back_to_hold_drops_a_stuck_latch() -> void:
	_mode(&"attack", PlayerInput.MODE_TOGGLE)
	await _tap(&"attack")
	assert_bool(_input.attack_held()).is_true()
	_mode(&"attack", PlayerInput.MODE_HOLD)
	await _tick()
	assert_bool(_input.attack_held()).is_false()
	assert_bool(_input.is_latched(&"attack")).is_false()


func test_each_held_action_latches_on_its_own() -> void:
	_mode(&"attack", PlayerInput.MODE_TOGGLE)
	_mode(&"secondary", PlayerInput.MODE_HOLD)
	_mode(&"map", PlayerInput.MODE_TOGGLE)
	await _tap(&"attack")
	await _tap(&"map")
	await _tap(&"secondary")
	assert_bool(_input.attack_held()).is_true()
	assert_bool(_input.map_held()).is_true()
	assert_bool(_input.secondary_held()).is_false()


func test_disabled_input_never_reports_a_latched_action() -> void:
	_mode(&"attack", PlayerInput.MODE_TOGGLE)
	await _tap(&"attack")
	assert_bool(_input.attack_held()).is_true()
	_input.enabled = false
	assert_bool(_input.attack_held()).is_false()
	assert_bool(_input.attack_just_pressed()).is_false()
	_input.enabled = true
	assert_bool(_input.attack_held()).is_true()
	_input.clear_latches()
	assert_bool(_input.attack_held()).is_false()
