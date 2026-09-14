## The last four things a controller could not do, each tested as the device does it.
##
## Everything here goes in through `Input.parse_input_event`, so a press travels the whole path
## a physical pad's press travels - the InputMap, `Input`, the viewport, focus, `_gui_input`,
## `_unhandled_input` - and the assertions are on what the player would see happen.
class_name ControllerGapsTest
extends GdUnitTestSuite

## Slack on a `Color` component: they are stored as 32-bit floats, so a modulate written as
## 0.45 does not read back equal to the 64-bit 0.45 the constant is.
const ALPHA_EPSILON := 0.005
## Frames a screen is given to settle before it is driven.
const SETTLE_FRAMES := 3
## Milliseconds a shake needs to run its five legs out (0.03 s each), plus slack. Waited as
## time rather than as frames: headless idle frames are far shorter than a rendered one, so a
## frame count is not a wait for a tween at all.
const SHAKE_MS := 400
## The four movement directions and the d-pad button each of them should answer to.
const MOVE_DPAD: Dictionary = {
	&"move_left": JOY_BUTTON_DPAD_LEFT,
	&"move_right": JOY_BUTTON_DPAD_RIGHT,
	&"move_up": JOY_BUTTON_DPAD_UP,
	&"move_down": JOY_BUTTON_DPAD_DOWN,
}
## Direction on screen each d-pad button should push the player in.
const MOVE_VECTORS: Dictionary = {
	&"move_left": Vector2.LEFT,
	&"move_right": Vector2.RIGHT,
	&"move_up": Vector2.UP,
	&"move_down": Vector2.DOWN,
}

var _device: int = 0


func before_test() -> void:
	_device = int(InputGlyphs.current_device())


func after_test() -> void:
	for button: JoyButton in MOVE_DPAD.values():
		Input.parse_input_event(_button(button, false))
	Input.flush_buffered_events()
	await await_idle_frame()
	InputGlyphs.set_device(_device as InputGlyphs.Device)
	EventBus.input_device_changed.emit(_device)


# ------------------------------------------------------------------ device plumbing


static func _button(index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	return event


func _hold(index: JoyButton, pressed: bool) -> void:
	Input.parse_input_event(_button(index, pressed))
	Input.flush_buffered_events()
	await await_idle_frame()


func _tap(index: JoyButton) -> void:
	await _hold(index, true)
	await _hold(index, false)


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await await_idle_frame()


func _load(path: String) -> Control:
	var node: Control = auto_free((load(path) as PackedScene).instantiate())
	add_child(node)
	return node


# ------------------------------------------------------------- movement has a d-pad


## The complaint, in one assertion. Movement shipped with WASD and the left stick and nothing
## else, so a pad whose stick is worn - or a player who simply prefers the cross - had no way
## to walk. A previous round's report claimed this was already bound; it was not.
func test_every_movement_direction_has_a_dpad_button() -> void:
	for action: StringName in MOVE_DPAD.keys():
		var wanted: JoyButton = MOVE_DPAD[action]
		var found := false
		for event: InputEvent in InputMap.action_get_events(action):
			var pad := event as InputEventJoypadButton
			if pad != null and pad.button_index == wanted:
				found = true
		(
			assert_bool(found)
			. override_failure_message("%s has no d-pad binding: movement is stick-only" % action)
			. is_true()
		)


## And the binding actually moves the player: held, the d-pad produces the same wish direction
## a full stick push does. `move_vector` is what `Player._physics_process` walks on.
func test_holding_the_dpad_pushes_the_player_in_that_direction() -> void:
	var input: PlayerInput = auto_free(PlayerInput.new())
	add_child(input)
	await await_idle_frame()
	for action: StringName in MOVE_DPAD.keys():
		var button: JoyButton = MOVE_DPAD[action]
		await _hold(button, true)
		var moved := input.move_vector()
		await _hold(button, false)
		(
			assert_vector(moved)
			. override_failure_message(
				(
					"holding the %s d-pad button moved the player %s, not %s"
					% [action, moved, MOVE_VECTORS[action]]
				)
			)
			. is_equal(MOVE_VECTORS[action] as Vector2)
		)


## The stick keeps the Move glyph. Both are bound now, and the Controls page draws the first
## pad event it finds, so the order in `project.godot` is what decides which one is taught.
func test_the_move_row_still_draws_the_left_stick_and_not_the_dpad() -> void:
	InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
	(
		assert_int(InputGlyphs.cell_for(&"move_up"))
		. override_failure_message("the Move row now teaches the d-pad instead of the stick")
		. is_equal(int(InputGlyphs.Cell.LSTICK))
	)


# --------------------------------------------- the keyboard column says what it needs


## The row used to open a "Press a key for Interact" capture for a device that has no keys,
## swallow the whole input stream, and then answer every button with "that lives in the other
## column". Opening it is the pad's job no longer: the row says what it needs instead.
func test_a_pad_cannot_open_the_keyboard_column_and_is_told_why() -> void:
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	await await_idle_frame()
	var kb_button: Button = panel._rebind_buttons[&"interact"]
	kb_button.grab_focus()
	await _tap(JOY_BUTTON_A)
	(
		assert_bool(panel.is_capturing())
		. override_failure_message("the pad opened a capture only a keyboard can complete")
		. is_false()
	)
	var hint: UiPrompt = panel.get_node("%Hint")
	(
		assert_str(hint.text)
		. override_failure_message("the Keyboard column refused without saying anything")
		. contains("keyboard")
	)
	(
		assert_str(hint.text)
		. override_failure_message("the refusal does not point at the column a pad can set")
		. contains("Gamepad column")
	)


## And it says so on arrival, not only after a press that did nothing.
func test_landing_on_the_keyboard_column_with_a_pad_says_what_it_needs() -> void:
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	await await_idle_frame()
	(panel._pad_buttons[&"interact"] as Button).grab_focus()
	await _tap(JOY_BUTTON_DPAD_LEFT)
	var hint: UiPrompt = panel.get_node("%Hint")
	assert_object(panel.get_viewport().gui_get_focus_owner()).is_same(
		panel._rebind_buttons[&"interact"]
	)
	(
		assert_str(hint.text)
		. override_failure_message("stepping onto the Keyboard column on a pad said nothing")
		. contains("keyboard")
	)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	(
		assert_str(hint.text)
		. override_failure_message("the notice stayed up after the column was left")
		. is_equal(SettingsPanel.HINT_DEFAULT)
	)


## The column is drawn inert while a pad is live, so a player reads the row before pressing it.
## It goes back to normal the moment a keyboard is the live device - it is not disabled, it is
## a column this device cannot fill in.
func test_the_keyboard_column_is_drawn_inert_on_a_pad_and_normal_on_a_keyboard() -> void:
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	await await_idle_frame()
	var kb_button: Button = panel._rebind_buttons[&"interact"]
	var pad_button: Button = panel._pad_buttons[&"interact"]
	await _tap(JOY_BUTTON_DPAD_DOWN)
	(
		assert_float(kb_button.modulate.a)
		. override_failure_message("the Keyboard column looks pressable to a controller")
		. is_equal_approx(SettingsPanel.INERT_COLUMN_ALPHA, ALPHA_EPSILON)
	)
	assert_float(pad_button.modulate.a).is_equal_approx(1.0, ALPHA_EPSILON)
	await _key(KEY_DOWN)
	(
		assert_float(kb_button.modulate.a)
		. override_failure_message("the Keyboard column stayed greyed out for a keyboard")
		. is_equal_approx(1.0, ALPHA_EPSILON)
	)


## The regression guard on the refusal: the column next to it still opens from the pad, which
## is the whole point of refusing this one.
func test_the_gamepad_column_still_opens_from_the_pad() -> void:
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	await await_idle_frame()
	(panel._pad_buttons[&"interact"] as Button).grab_focus()
	await _tap(JOY_BUTTON_A)
	(
		assert_bool(panel.is_capturing())
		. override_failure_message("the Gamepad column stopped opening from a pad")
		. is_true()
	)
	await _tap(JOY_BUTTON_B)
	assert_bool(panel.is_capturing()).is_false()


# ------------------------------------------------- Start answers on an offer board


func _board(kind: int, context: Dictionary) -> ChestUi:
	var chest := _load("res://src/ui/chest_ui.tscn") as ChestUi
	chest.show_offers(kind, [{"stat": &"might", "points": 2}], context)
	return chest


## Start reached nothing on a board: `PauseMenu` refuses to stack over one on purpose, so the
## press was answered by nothing at all, which is what a hung game looks like.
func test_start_on_an_offer_board_points_at_the_way_out() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var chest := _board(ChestUi.Kind.STAT, UiFakes.chest_context(player))
	var taken: Array[int] = []
	chest.skipped.connect(func() -> void: taken.append(1))
	chest.chosen.connect(func(_o: Variant, _i: int, _p: int) -> void: taken.append(2))
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	var hint: UiPrompt = chest.get_node("%Hint")
	var before := hint.text

	await _tap(JOY_BUTTON_START)

	(
		assert_str(hint.text)
		. override_failure_message("Start on an offer board still says nothing at all")
		. is_not_equal(before)
	)
	(
		assert_str(hint.plain())
		. override_failure_message("the answer does not name the button that does leave")
		. contains("B ")
	)
	(
		assert_array(taken)
		. override_failure_message("Start took the offer board's way out instead of naming it")
		. is_empty()
	)


## The shake that goes with the answer must not move the button it is drawing attention to.
##
## `UiHintLine.shake` puts a control back "where it was" at the end, and a control that has not
## been laid out yet is at (0, 0) - so shaking a container child in the frame it was created
## pinned it to the left edge of its row for good. A board that answered Start in the same
## frame it was filled left its Skip button there, in front of the player, permanently.
func test_shaking_a_control_before_it_is_laid_out_does_not_move_it() -> void:
	var saved := GameState.settings.duplicate(true)
	GameState.settings["reduce_motion"] = false
	var box: HBoxContainer = auto_free(HBoxContainer.new())
	add_child(box)
	var first := Button.new()
	first.text = "Reroll (25g)"
	var second := Button.new()
	second.text = "Skip (+10g)"
	box.add_child(first)
	box.add_child(second)

	UiHintLine.shake(second)

	# The row is only given its width afterwards, so the shake ran against unplaced buttons.
	box.size = Vector2(300.0, 24.0)
	await await_millis(SHAKE_MS)
	GameState.settings = saved
	(
		assert_float(second.position.x)
		. override_failure_message("the shake left the button pinned at the edge of its row")
		. is_greater(first.position.x)
	)


## A board with no way out has nothing to point at, so it says why it is not going anywhere
## rather than nothing. Silence here is the same bug wearing a different board.
func test_start_on_a_mandatory_board_says_why_it_will_not_move() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var context := UiFakes.chest_context(player)
	context["no_skip"] = true
	var chest := _board(ChestUi.Kind.STAT, context)
	await await_idle_frame()
	var hint: UiPrompt = chest.get_node("%Hint")

	await _tap(JOY_BUTTON_START)

	(
		assert_str(hint.text)
		. override_failure_message("Start on a mandatory board still says nothing")
		. is_equal(UiHintLine.MANDATORY_NOTICE)
	)


## The answer is a notice, not the board's new hint: the next thing the player does takes it
## down and the controls line comes back.
func test_the_answer_goes_away_when_the_player_moves_on() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var chest := _load("res://src/ui/chest_ui.tscn") as ChestUi
	chest.show_offers(
		ChestUi.Kind.STAT,
		[{"stat": &"might", "points": 2}, {"stat": &"vitality", "points": 2}],
		UiFakes.chest_context(player)
	)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	var hint: UiPrompt = chest.get_node("%Hint")
	var controls := hint.text
	await _tap(JOY_BUTTON_START)
	assert_str(hint.text).is_not_equal(controls)

	await _tap(JOY_BUTTON_DPAD_RIGHT)

	(
		assert_str(hint.text)
		. override_failure_message("the board kept answering Start after the player moved on")
		. is_equal(controls)
	)
