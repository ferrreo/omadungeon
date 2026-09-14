## One whole session on a controller and nothing else: title -> Settings -> the bottom of the
## Settings list -> a rebind in each column -> back out -> a run -> pause -> abandon -> the
## summary -> the title -> quit.
##
## Why it is one test and not twelve. Every round so far fixed the defect a verifier named and
## shipped a pad that was still stuck, because the suites proved *screens* and a player plays a
## *session*: a screen that navigates perfectly in isolation is worthless if the screen before
## it cannot hand focus to it. This walks the whole path with real device events -
## `InputEventJoypadButton` through `Input.parse_input_event`, the same entry point a physical
## pad uses - and never calls `grab_focus()`, `press()`, or a signal by hand to get past a step.
## If any link in the chain breaks, this goes red at the link.
##
## Two deliberate exceptions, both of them the scene management the harness opts out of rather
## than input:
##   * `RunManager.manage_scenes = false` (as every run-level test does), so the run does not
##     replace the test's scene tree; `Main` is hidden by hand where the shipping game would
##     have swapped it out, and `show_screen(SUMMARY)` is called where `_show_main()` would
##     have.
##   * The keyboard column of a rebind row is opened and written with real `InputEventKey`s. A
##     pad cannot type a key and must not pretend to: what the pad proves here is that it can
##     *reach* that column and is told plainly that it cannot fill it in, and that the keyboard
##     beside it then opens and finishes the row - the state a player at a desk with both
##     devices is actually in.
class_name PadSessionTest
extends GdUnitTestSuite

## Seed for the run leg. Any seed builds a floor; this one just keeps the test reproducible.
const SEED := 424242
## How many presses a walk is given before the screen counts as unreachable. The Settings list
## is 36 stops, so this is generous and still finite.
const WALK_LIMIT := 90
## Frames to let a screen swap and its deferred `focus_first` settle.
const SETTLE_FRAMES := 3
## A gamepad button nothing ships bound to, so binding it proves a rebind without destroying
## another action on the way.
const FREE_PAD_BUTTON := JOY_BUTTON_RIGHT_STICK
## The action the session rebinds, in both columns.
const REBOUND := &"potion"

var _device: int = 0
var _settings_backup: Dictionary = {}
var _map_backup: Dictionary = {}


func before_test() -> void:
	_device = int(InputGlyphs.current_device())
	_settings_backup = GameState.settings.duplicate(true)
	_map_backup = _snapshot_input_map()
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true
	_restore_input_map(_map_backup)
	GameState.settings = _settings_backup
	await _centre_stick()
	InputGlyphs.set_device(_device as InputGlyphs.Device)
	EventBus.input_device_changed.emit(_device)


# ------------------------------------------------------------------ device plumbing


static func _button(index: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	return event


## Presses and releases a pad button, exactly as the device sends it.
func _tap(index: JoyButton) -> void:
	Input.parse_input_event(_button(index, true))
	Input.flush_buffered_events()
	Input.parse_input_event(_button(index, false))
	Input.flush_buffered_events()
	await await_idle_frame()


## Presses and releases one keyboard key, for the one step a controller cannot do.
func _type(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await await_idle_frame()


func _centre_stick() -> void:
	for axis: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var event := InputEventJoypadMotion.new()
		event.device = 0
		event.axis = axis
		event.axis_value = 0.0
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await await_idle_frame()


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _focused() -> Control:
	return get_viewport().gui_get_focus_owner()


## Taps `index` until `reached` answers true. Returns the presses it took, or -1 when the
## walk never got there - which is the number a stuck pad produces.
func _walk_until(index: JoyButton, reached: Callable) -> int:
	var presses := 0
	while presses < WALK_LIMIT:
		if bool(reached.call()):
			return presses
		await _tap(index)
		presses += 1
	return presses if bool(reached.call()) else -1


func _snapshot_input_map() -> Dictionary:
	var out: Dictionary = {}
	for action: StringName in InputBindings.ACTIONS:
		var events: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event)
		out[action] = events
	return out


static func _restore_input_map(snapshot: Dictionary) -> void:
	for action: StringName in snapshot.keys():
		InputMap.action_erase_events(action)
		var events: Variant = snapshot[action]
		for event: InputEvent in events as Array:
			InputMap.action_add_event(action, event)


# ------------------------------------------------------------------ the session


func test_a_whole_session_on_the_pad_alone() -> void:
	var main: Main = auto_free((load("res://src/main.tscn") as PackedScene).instantiate())
	add_child(main)
	# The 480x270 internal resolution, so the Settings viewport is the one a player sees: a
	# list that fits needs no scrolling and would prove nothing.
	main.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(480, 270)
	await _frames(SETTLE_FRAMES)

	# --- the title opens with something focused, or the first A does nothing at all.
	(
		assert_object(_focused())
		. override_failure_message("the title opened with nothing focused")
		. is_not_null()
	)
	var title := main.current as Title
	var settings_button: Button = title.get_node("%Settings")
	var walked := await _walk_until(
		JOY_BUTTON_DPAD_DOWN, func() -> bool: return _focused() == settings_button
	)
	(
		assert_int(walked)
		. override_failure_message("the d-pad never reached Settings on the title menu")
		. is_greater_equal(0)
	)
	await _tap(JOY_BUTTON_A)
	await _frames(SETTLE_FRAMES)
	assert_int(int(main.screen)).is_equal(int(Main.Screen.SETTINGS))

	# --- the Settings list scrolls all the way down on the pad.
	var panel := main.current as SettingsPanel
	var scroll: ScrollContainer = panel.get_node("%Scroll")
	await _frames(SETTLE_FRAMES)
	var last := panel.focus_last()
	assert_object(last).is_not_null()
	var to_bottom := await _walk_until(
		JOY_BUTTON_DPAD_DOWN, func() -> bool: return _focused() == last
	)
	(
		assert_int(to_bottom)
		. override_failure_message(
			(
				"the pad could not walk the Settings list to its last row (%d px of list, %d px of viewport, stuck on %s)"
				% [
					int((panel.get_node("%List") as Control).size.y),
					int(scroll.size.y),
					_focused().name if _focused() != null else "nothing"
				]
			)
		)
		. is_greater(0)
	)
	(
		assert_int(scroll.scroll_vertical)
		. override_failure_message("focus reached the last row without the list ever scrolling")
		. is_greater(0)
	)

	# --- a rebind in the gamepad column, opened and completed from the pad.
	var pad_button: Button = panel._pad_buttons[REBOUND]
	var kb_button: Button = panel._rebind_buttons[REBOUND]
	var to_row := await _walk_until(
		JOY_BUTTON_DPAD_UP, func() -> bool: return _focused() == kb_button
	)
	(
		assert_int(to_row)
		. override_failure_message("the pad could not reach the %s rebind row" % REBOUND)
		. is_greater_equal(0)
	)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_object(_focused()).is_same(pad_button)
	await _tap(JOY_BUTTON_A)
	assert_bool(panel.is_capturing()).is_true()
	await _tap(FREE_PAD_BUTTON)
	assert_bool(panel.is_capturing()).is_false()
	(
		assert_str(InputGlyphs.binding_name(REBOUND, InputGlyphs.Device.GAMEPAD))
		. override_failure_message("the gamepad column did not take the new button")
		. is_equal("RS")
	)

	# --- Start may not be taken away from Pause, however it is pressed.
	await _tap(JOY_BUTTON_A)
	assert_bool(panel.is_capturing()).is_true()
	await _tap(JOY_BUTTON_START)
	assert_bool(panel.is_capturing()).is_false()
	(
		assert_str(InputGlyphs.binding_name(&"pause", InputGlyphs.Device.GAMEPAD))
		. override_failure_message("Start was bound away from Pause: the pad lost the menu")
		. is_equal("Start")
	)
	assert_str(InputGlyphs.binding_name(REBOUND, InputGlyphs.Device.GAMEPAD)).is_equal("RS")
	assert_str((panel.get_node("%Hint") as UiPrompt).text).contains("Pause")

	# --- and the keyboard column of the same row: the pad reaches it and is told, in words,
	# that it cannot fill it in; the keyboard next to it opens and finishes the row.
	await _tap(JOY_BUTTON_DPAD_LEFT)
	assert_object(_focused()).is_same(kb_button)
	var hint: UiPrompt = panel.get_node("%Hint")
	(
		assert_str(hint.text)
		. override_failure_message("landing on the Keyboard column with a pad said nothing")
		. contains("keyboard")
	)
	await _tap(JOY_BUTTON_A)
	(
		assert_bool(panel.is_capturing())
		. override_failure_message("A on the Keyboard column opened a capture a pad cannot finish")
		. is_false()
	)
	assert_str(hint.text).contains("Gamepad column")
	await _type(KEY_ENTER)
	(
		assert_bool(panel.is_capturing())
		. override_failure_message("Enter on a keyboard did not open the Keyboard column")
		. is_true()
	)
	await _type(KEY_H)
	assert_bool(panel.is_capturing()).is_false()
	(
		assert_str(InputGlyphs.binding_name(REBOUND, InputGlyphs.Device.KEYBOARD))
		. override_failure_message("the keyboard column did not take the new key")
		. is_equal("H")
	)

	# --- back out of Settings with B.
	await _tap(JOY_BUTTON_B)
	await _frames(SETTLE_FRAMES)
	(
		assert_int(int(main.screen))
		. override_failure_message("B did not leave the Settings page")
		. is_equal(int(Main.Screen.TITLE))
	)

	# --- start a run: New Run, then a class.
	title = main.current as Title
	var new_run: Button = title.get_node("%NewRun")
	var to_new_run := await _walk_until(
		JOY_BUTTON_DPAD_DOWN, func() -> bool: return _focused() == new_run
	)
	assert_int(to_new_run).is_greater_equal(0)
	await _tap(JOY_BUTTON_A)
	await _frames(SETTLE_FRAMES)
	assert_int(int(main.screen)).is_equal(int(Main.Screen.CLASS_SELECT))
	main.pending_seed = SEED
	await _tap(JOY_BUTTON_A)
	await _frames(6)
	(
		assert_bool(RunManager.is_run_active())
		. override_failure_message("A on the class select did not start a run")
		. is_true()
	)
	# The shipping game swaps the menu scene out here; the harness keeps it, so hide it.
	main.visible = false

	# --- pause, abandon, confirm - all on the pad.
	var pause := (RunManager.game as Game).pause_menu
	await _tap(JOY_BUTTON_START)
	await _frames(2)
	(
		assert_bool(pause.is_open())
		. override_failure_message("Start did not open the pause menu in the run")
		. is_true()
	)
	var abandon: Button = pause.get_node("%Abandon")
	var to_abandon := await _walk_until(
		JOY_BUTTON_DPAD_DOWN, func() -> bool: return _focused() == abandon
	)
	if to_abandon < 0:
		to_abandon = await _walk_until(
			JOY_BUTTON_DPAD_RIGHT, func() -> bool: return _focused() == abandon
		)
	assert_int(to_abandon).is_greater_equal(0)
	await _tap(JOY_BUTTON_A)
	assert_bool(pause.confirm_visible()).is_true()
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_object(_focused()).is_same(pause.get_node("%ConfirmYes"))
	await _tap(JOY_BUTTON_A)
	await _frames(4)
	(
		assert_bool(RunManager.is_run_active())
		. override_failure_message("Abandon confirmed on the pad did not end the run")
		. is_false()
	)

	# --- the summary, and back to the title from it.
	main.visible = true
	var summary := main.show_screen(Main.Screen.SUMMARY) as RunSummary
	await _frames(SETTLE_FRAMES)
	assert_object(_focused()).is_not_null()
	var to_title: Button = summary.get_node("%ToTitle")
	var to_exit := await _walk_until(
		JOY_BUTTON_DPAD_RIGHT, func() -> bool: return _focused() == to_title
	)
	assert_int(to_exit).is_greater_equal(0)
	await _tap(JOY_BUTTON_A)
	await _frames(SETTLE_FRAMES)
	assert_int(int(main.screen)).is_equal(int(Main.Screen.TITLE))

	# --- and quit. The real handler calls `SceneTree.quit()`, so the session watches the
	# intent instead of taking the process down with it.
	title = main.current as Title
	for connection: Dictionary in title.quit_pressed.get_connections():
		title.quit_pressed.disconnect(connection["callable"] as Callable)
	var quits: Array[int] = []
	title.quit_pressed.connect(func() -> void: quits.append(1))
	var quit_button: Button = title.get_node("%Quit")
	var to_quit := await _walk_until(
		JOY_BUTTON_DPAD_DOWN, func() -> bool: return _focused() == quit_button
	)
	assert_int(to_quit).is_greater_equal(0)
	await _tap(JOY_BUTTON_A)
	(
		assert_array(quits)
		. override_failure_message("A on Quit did nothing: the pad cannot leave the game")
		. is_not_empty()
	)
