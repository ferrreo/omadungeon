## The test that would have caught "controller cannot select menu items or items in shop etc
## (pressing A does nothing)".
##
## `controller_nav_test.gd` drives `InputEventAction` straight at a screen's handler, which
## proves the *handler* works and says nothing about whether a pad can reach it. Eight review
## rounds read that as coverage; meanwhile `ui_accept` and `ui_cancel` had no gamepad event at
## all (Godot's built-in defaults give them none), so A and B did nothing anywhere in the game.
##
## Everything here goes in as a real device event - `InputEventJoypadButton`,
## `InputEventJoypadMotion` - through `Input.parse_input_event`, so it travels the whole path a
## physical pad travels: the InputMap, `Input`, the viewport, focus, `_gui_input`,
## `_unhandled_input`. The assertions are on what the player would see happen: the highlight
## moved, the button fired, the screen closed.
class_name ControllerDeviceTest
extends GdUnitTestSuite

## Frames to let a synthesised flick settle. `UiStickNav` converts the stick on its own
## `_process`, so a stick assertion needs a frame; two is slack for the emit-then-handle hop.
const SETTLE_FRAMES := 3
## Deflection a "full push" of the stick reports.
const FULL := 1.0
## Milliseconds between samples while a held stick is being watched for auto-repeat.
const SAMPLE_MS := 40
## Presses a walk is given before the thing it is walking to counts as unreachable. The
## Settings list is 36 stops long, so this is generous and still finite.
const WALK_LIMIT := 90

var _device: int = 0


func before_test() -> void:
	_device = int(InputGlyphs.current_device())


func after_test() -> void:
	# The stick state and the active-device flag both live on the SceneTree, so a suite that
	# leaves either dirty changes what the next suite's screens draw.
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


static func _motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event


## Presses and releases a pad button, as the device sends it.
func _tap(index: JoyButton) -> void:
	Input.parse_input_event(_button(index, true))
	Input.flush_buffered_events()
	Input.parse_input_event(_button(index, false))
	Input.flush_buffered_events()
	await await_idle_frame()


## Presses and releases a key, as the keyboard sends it. Opening a keyboard-column rebind is
## the keyboard's job (`SettingsPanel.keyboard_column_live`), so the suite has to be able to.
func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await await_idle_frame()


## One physical flick of the left stick and back to centre. The ramp is the point: a real
## stick sends a stream of motion events on the way out (0.6, 0.8, 1.0), and a naive binding
## counts every one of them as a fresh press.
func _flick(axis: JoyAxis, sign_value: float) -> void:
	for step: float in [0.6, 0.8, FULL]:
		Input.parse_input_event(_motion(axis, sign_value * step))
		Input.flush_buffered_events()
	for i in SETTLE_FRAMES:
		await await_idle_frame()
	await _centre_stick()


## Holds the stick for `millis`, sampling `probe` as it goes, and returns how many times the
## answer changed. Counting transitions rather than comparing the ends is the point: four
## repeats on a four-card row land back where they started.
func _hold_and_count(axis: JoyAxis, sign_value: float, millis: int, probe: Callable) -> int:
	Input.parse_input_event(_motion(axis, sign_value * FULL))
	Input.flush_buffered_events()
	var changes := 0
	var last: Variant = probe.call()
	var elapsed := 0
	while elapsed < millis:
		await await_millis(SAMPLE_MS)
		elapsed += SAMPLE_MS
		var now: Variant = probe.call()
		if now != last:
			changes += 1
			last = now
	await _centre_stick()
	return changes


func _centre_stick() -> void:
	for axis: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		Input.parse_input_event(_motion(axis, 0.0))
	Input.flush_buffered_events()
	for i in SETTLE_FRAMES:
		await await_idle_frame()


func _load(path: String) -> Control:
	var node: Control = auto_free((load(path) as PackedScene).instantiate())
	add_child(node)
	return node


## Records every Button under `root` that fires, by node name.
static func _watch_buttons(root: Node, out: Array[StringName]) -> void:
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		button.pressed.connect(func() -> void: out.append(button.name))


# ------------------------------------------------------------------ the input map itself


func test_the_confirm_and_back_buttons_exist_on_the_pad_at_all() -> void:
	# The whole bug in one assertion: the shipped map gave `ui_accept` three keyboard events
	# and nothing a controller could send.
	var expected: Dictionary = {
		&"ui_accept": JOY_BUTTON_A,
		&"ui_cancel": JOY_BUTTON_B,
		&"ui_left": JOY_BUTTON_DPAD_LEFT,
		&"ui_right": JOY_BUTTON_DPAD_RIGHT,
		&"ui_up": JOY_BUTTON_DPAD_UP,
		&"ui_down": JOY_BUTTON_DPAD_DOWN,
		&"ui_page_up": JOY_BUTTON_LEFT_SHOULDER,
		&"ui_page_down": JOY_BUTTON_RIGHT_SHOULDER,
	}
	for action: StringName in expected.keys():
		var wanted: JoyButton = expected[action]
		var found := false
		for event: InputEvent in InputMap.action_get_events(action):
			var pad := event as InputEventJoypadButton
			if pad != null and pad.button_index == wanted:
				found = true
		(
			assert_bool(found)
			. override_failure_message(
				"%s has no gamepad binding: a controller cannot do it at all" % action
			)
			. is_true()
		)


func test_the_stick_is_not_wired_straight_to_the_directional_ui_actions() -> void:
	# `InputEventJoypadMotion` has no edge detection, so a raw stick binding turns one flick
	# into three presses. `UiStickNav` owns the stick instead; this pins that decision.
	for action: StringName in [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		for event: InputEvent in InputMap.action_get_events(action):
			(
				assert_bool(event is InputEventJoypadMotion)
				. override_failure_message("%s is bound to a raw stick axis again" % action)
				. is_false()
			)


# --------------------------------------------------- prompts name the button that works


func test_the_on_screen_prompts_name_the_button_that_actually_works() -> void:
	# Every gamepad hint in the game promised A and B long before either did anything. The
	# glyph layer and the screens' own hint lines have to agree with the map that now works.
	assert_str(InputGlyphs.binding_name(&"ui_accept", InputGlyphs.Device.GAMEPAD)).is_equal("A")
	assert_str(InputGlyphs.binding_name(&"ui_cancel", InputGlyphs.Device.GAMEPAD)).is_equal("B")
	var select := _load("res://src/ui/class_select.tscn") as ClassSelect
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var chest := _board(ChestUi.Kind.ITEM, UiFakes.chest_context(player))
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_int(int(InputGlyphs.current_device())).is_equal(int(InputGlyphs.Device.GAMEPAD))
	assert_str((select.get_node("%Hint") as UiPrompt).plain()).contains("A confirm")
	assert_str((select.get_node("%Hint") as UiPrompt).plain()).contains("B back")
	assert_str((chest.get_node("%Hint") as UiPrompt).plain()).contains("A ")
	assert_str((pause.get_node("%Hint") as UiPrompt).plain()).contains("B resume")
	# And they name the stick as well as the cross. The stick reaches every board and every
	# focus list because it is sent as the matching d-pad button (`UiStickNav.emit_direction`),
	# which is asserted by walking screens below, not by this line; a prompt saying only
	# "D-pad" would be a prompt that teaches a player their stick does nothing here.
	(
		assert_str((chest.get_node("%Hint") as UiPrompt).plain())
		. override_failure_message("the board prompt still names only the d-pad")
		. contains("Stick")
	)
	assert_str(UiPrompt.render_plain(CompareView.hint_text(true, 2))).contains("Stick")
	pause.close()


# ------------------------------------------------------------------ title


func test_the_title_menu_is_driven_entirely_from_the_pad() -> void:
	var title := _load("res://src/ui/title.tscn") as Title
	var fired: Array[StringName] = []
	_watch_buttons(title, fired)
	await await_idle_frame()
	var first := title.get_viewport().gui_get_focus_owner()
	(
		assert_object(first)
		. override_failure_message(
			"the title opened with nothing focused: the first A does nothing"
		)
		. is_not_null()
	)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	var second := title.get_viewport().gui_get_focus_owner()
	assert_object(second).is_not_same(first)
	await _tap(JOY_BUTTON_A)
	(
		assert_array(fired)
		. override_failure_message("A on the title screen pressed nothing")
		. is_not_empty()
	)
	assert_str(String(fired[0])).is_equal(String((second as Button).name))


func test_the_title_menu_wraps_so_the_bottom_is_not_a_cul_de_sac() -> void:
	var title := _load("res://src/ui/title.tscn") as Title
	await await_idle_frame()
	var ring := title.focus_ring()
	assert_int(ring.size()).is_greater(2)
	ring[0].grab_focus()
	await _tap(JOY_BUTTON_DPAD_UP)
	(
		assert_object(title.get_viewport().gui_get_focus_owner())
		. override_failure_message("up from the first menu row went nowhere")
		. is_same(ring[ring.size() - 1])
	)


func test_the_left_stick_moves_the_title_focus_one_row_per_flick() -> void:
	var title := _load("res://src/ui/title.tscn") as Title
	await await_idle_frame()
	var ring := title.focus_ring()
	ring[0].grab_focus()
	await _flick(JOY_AXIS_LEFT_Y, 1.0)
	(
		assert_object(title.get_viewport().gui_get_focus_owner())
		. override_failure_message("one flick of the stick moved focus by more or less than a row")
		. is_same(ring[1])
	)
	await _flick(JOY_AXIS_LEFT_Y, 1.0)
	assert_object(title.get_viewport().gui_get_focus_owner()).is_same(ring[2])


func test_a_text_field_is_not_a_dead_end_for_a_controller() -> void:
	# Any LineEdit left on the title drops out of the pad's focus ring: A on one does nothing,
	# which is exactly what the owner hit.
	var title := _load("res://src/ui/title.tscn") as Title
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_int(int(InputGlyphs.current_device())).is_equal(int(InputGlyphs.Device.GAMEPAD))
	for control: Control in title.focus_ring():
		(
			assert_bool(control is LineEdit)
			. override_failure_message("%s is a text field a pad can focus" % control.name)
			. is_false()
		)


# ------------------------------------------------------------------ class select


func test_the_class_select_is_browsed_and_confirmed_from_the_pad() -> void:
	var select := _load("res://src/ui/class_select.tscn") as ClassSelect
	var chosen: Array[StringName] = []
	var backs: Array[int] = []
	select.class_chosen.connect(func(id: StringName) -> void: chosen.append(id))
	select.back_pressed.connect(func() -> void: backs.append(1))
	select.select(0)
	var first := select.selected_id()
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_str(String(select.selected_id())).is_not_equal(String(first))
	await _tap(JOY_BUTTON_DPAD_LEFT)
	assert_str(String(select.selected_id())).is_equal(String(first))
	await _tap(JOY_BUTTON_A)
	assert_array(chosen).override_failure_message("A on the class select chose nothing").contains(
		[first]
	)
	await _tap(JOY_BUTTON_B)
	(
		assert_array(backs)
		. override_failure_message("B on the class select did not go back")
		. is_not_empty()
	)


func test_one_flick_of_the_stick_moves_the_class_select_by_one_card() -> void:
	# The owner's second sentence: "using the joystick of the controller doesn't allow easy
	# selection of characters". A stick bound straight to `ui_right` sent Fighter to Oligarch
	# on one push, because every motion event past the deadzone read as a fresh press.
	var select := _load("res://src/ui/class_select.tscn") as ClassSelect
	select.select(0)
	var ids: Array[StringName] = []
	for entry: Dictionary in select.classes:
		ids.append(entry["id"])
	assert_int(ids.size()).is_greater(2)
	await _flick(JOY_AXIS_LEFT_X, 1.0)
	(
		assert_str(String(select.selected_id()))
		. override_failure_message("one flick of the stick skipped past the next class")
		. is_equal(String(ids[1]))
	)
	await _flick(JOY_AXIS_LEFT_X, 1.0)
	assert_str(String(select.selected_id())).is_equal(String(ids[2]))
	await _flick(JOY_AXIS_LEFT_X, -1.0)
	assert_str(String(select.selected_id())).is_equal(String(ids[1]))


func test_a_held_stick_repeats_instead_of_stopping_after_one_step() -> void:
	var select := _load("res://src/ui/class_select.tscn") as ClassSelect
	select.select(0)
	var probe := func() -> Variant: return select.selected_id()
	var changes: int = await _hold_and_count(JOY_AXIS_LEFT_X, 1.0, 900, probe)
	(
		assert_int(changes)
		. override_failure_message("holding the stick moved the selection once and then stopped")
		. is_greater_equal(2)
	)


# ------------------------------------------------------------------ chest / shop boards


func _board(kind: int, context: Dictionary) -> ChestUi:
	var chest := _load("res://src/ui/chest_ui.tscn") as ChestUi
	chest.show_offers(kind, UiFakes.make_offers(kind), context)
	return chest


## Taking gear off the board is a trade, and a pad has to be able to see it and take it.
## An item used to swap in silence on one button press: the card named what it would replace
## and the next thing on screen was the dungeon, with the old armour already gone.
func test_an_item_is_picked_off_the_chest_board_with_the_pad() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var chest := _board(ChestUi.Kind.ITEM, UiFakes.chest_context(player))
	var taken: Array = []
	chest.chosen.connect(
		func(offer: Variant, _replace: int, _price: int) -> void: taken.append(offer)
	)
	await await_idle_frame()
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.OFFERS)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	(
		assert_int(chest.selected_index())
		. override_failure_message("the d-pad did not move the board selection")
		. is_equal(1)
	)
	await _tap(JOY_BUTTON_A)
	# A holds the trade up first: the worn armour on the left, the offer on the right.
	(
		assert_int(chest.selected_row())
		. override_failure_message("A took the item without showing what it displaced")
		. is_equal(ChestUi.Row.REPLACE)
	)
	assert_array(taken).is_empty()
	var worn := UiFakes.equipped_for(player, chest.offers[1] as ItemInstance)
	assert_object(worn).is_not_null()
	var swap := chest.compare_view()
	assert_object(swap.out_head).is_not_null()
	assert_str(_title_of(swap.out_head)).is_equal(worn.display_name)
	assert_str(_title_of(swap.in_head)).is_equal((chest.offers[1] as ItemInstance).display_name)
	await _tap(JOY_BUTTON_A)
	assert_array(taken).override_failure_message("A on the swap view took nothing").is_not_empty()
	assert_object(taken[0]).is_same(chest.offers[1])


## The heading label of a card, wherever it sits in the card's own box.
static func _title_of(card: Control) -> String:
	for child: Node in card.get_children():
		if child is Label and (child as Label).theme_type_variation == &"Heading":
			return (child as Label).text
		if child is Control:
			var found := _title_of(child as Control)
			if not found.is_empty():
				return found
	return ""


func test_the_shop_counter_is_bought_from_with_the_pad() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var chest := _board(ChestUi.Kind.ITEM, UiFakes.shop_context(player))
	var taken: Array = []
	chest.chosen.connect(
		func(offer: Variant, _replace: int, _price: int) -> void: taken.append(offer)
	)
	await await_idle_frame()
	assert_bool(chest.is_shop()).is_true()
	# The first item on the counter costs more than the fake player has; the second does not.
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	await _tap(JOY_BUTTON_A)
	(
		assert_array(taken)
		. override_failure_message("A on the shop counter bought nothing")
		. is_not_empty()
	)


func test_the_board_rows_and_the_skip_button_are_reachable_from_the_pad() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var chest := _board(ChestUi.Kind.ITEM, UiFakes.chest_context(player))
	await await_idle_frame()
	await _tap(JOY_BUTTON_DPAD_DOWN)
	(
		assert_int(chest.selected_row())
		. override_failure_message("down off the cards never reached the buttons")
		. is_equal(ChestUi.Row.BUTTONS)
	)
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.OFFERS)


func test_one_flick_of_the_stick_moves_the_board_by_one_card() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var chest := _board(ChestUi.Kind.ITEM, UiFakes.chest_context(player))
	await await_idle_frame()
	assert_int(chest.selected_index()).is_equal(0)
	await _flick(JOY_AXIS_LEFT_X, 1.0)
	(
		assert_int(chest.selected_index())
		. override_failure_message("one flick of the stick skipped past the next card")
		. is_equal(1)
	)


# ------------------------------------------------------------------ pause menu


func test_the_pause_menu_opens_navigates_and_resumes_on_the_pad() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	await _tap(JOY_BUTTON_START)
	(
		assert_bool(pause.is_open())
		. override_failure_message("Start did not open the pause menu")
		. is_true()
	)
	(
		assert_object(pause.get_viewport().gui_get_focus_owner())
		. override_failure_message("the pause menu opened with nothing focused")
		. is_not_null()
	)
	await _tap(JOY_BUTTON_B)
	assert_bool(pause.is_open()).is_false()
	pause.close()


func test_every_pause_tab_is_reached_with_the_shoulder_buttons() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	pause.set_tab(PauseMenu.Tab.BUILD)
	var seen: Array[int] = [pause.current_tab]
	for i in PauseMenu.Tab.size() - 1:
		await _tap(JOY_BUTTON_RIGHT_SHOULDER)
		seen.append(pause.current_tab)
	assert_int(seen.size()).is_equal(PauseMenu.Tab.size())
	for tab in PauseMenu.Tab.size():
		(
			assert_array(seen)
			. override_failure_message("tab %d cannot be reached with RB" % tab)
			. contains([tab])
		)
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	assert_int(pause.current_tab).is_equal(seen[seen.size() - 2])
	pause.close()


func test_the_abandon_dialog_is_answered_from_the_pad() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	pause._ask_abandon()
	await await_idle_frame()
	var no: Button = pause.get_node("%ConfirmNo")
	var yes: Button = pause.get_node("%ConfirmYes")
	assert_object(pause.get_viewport().gui_get_focus_owner()).is_same(no)
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	(
		assert_object(pause.get_viewport().gui_get_focus_owner())
		. override_failure_message("the d-pad could not reach the other answer")
		. is_same(yes)
	)
	await _tap(JOY_BUTTON_B)
	assert_bool(pause.confirm_visible()).is_false()
	pause.close()


func test_the_pause_footer_buttons_fire_on_a() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	var fired: Array[StringName] = []
	var resume: Button = pause.get_node("%Resume")
	resume.pressed.connect(func() -> void: fired.append(resume.name))
	resume.grab_focus()
	await _tap(JOY_BUTTON_A)
	(
		assert_array(fired)
		. override_failure_message("A did not press the focused pause-menu button")
		. contains([resume.name])
	)
	pause.close()


# ------------------------------------------------------------------ settings


func test_the_standalone_settings_screen_focuses_itself() -> void:
	# Opened from the title, nothing else grabs a row: the page used to come up with no focus
	# at all, so the first A did nothing. Embedded in the pause menu the tab owns the focus.
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	assert_bool(panel.standalone).is_true()
	await await_idle_frame()
	await await_idle_frame()
	(
		assert_object(panel.get_viewport().gui_get_focus_owner())
		. override_failure_message("the settings screen opened with nothing focused")
		. is_not_null()
	)


func test_the_settings_rows_are_toggled_with_a() -> void:
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	panel.focus_first()
	await await_idle_frame()
	(
		assert_object(panel.get_viewport().gui_get_focus_owner())
		. override_failure_message("the settings panel opened with nothing focused")
		. is_not_null()
	)
	var checks := panel.find_children("*", "CheckBox", true, false)
	assert_array(checks).is_not_empty()
	var check := checks[0] as CheckBox
	check.grab_focus()
	var before := check.button_pressed
	await _tap(JOY_BUTTON_A)
	(
		assert_bool(check.button_pressed)
		. override_failure_message("A did not toggle the focused settings row")
		. is_not_equal(before)
	)


func test_a_binding_is_rebound_by_pressing_the_pad_button_itself() -> void:
	var saved: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(&"potion"):
		saved.append(event)
	var settings := GameState.settings.duplicate(true)
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	var pad_button: Button = panel._pad_buttons[&"potion"]
	pad_button.grab_focus()
	await _tap(JOY_BUTTON_A)
	(
		assert_bool(panel.is_capturing())
		. override_failure_message("A on a rebind row did not start a capture")
		. is_true()
	)
	await _tap(JOY_BUTTON_RIGHT_STICK)
	assert_bool(panel.is_capturing()).is_false()
	var found := false
	for event: InputEvent in InputMap.action_get_events(&"potion"):
		var pad := event as InputEventJoypadButton
		if pad != null and pad.button_index == JOY_BUTTON_RIGHT_STICK:
			found = true
	(
		assert_bool(found)
		. override_failure_message("the pad button pressed during a capture was not bound")
		. is_true()
	)
	InputMap.action_erase_events(&"potion")
	for event: InputEvent in saved:
		InputMap.action_add_event(&"potion", event)
	GameState.settings = settings


func test_the_seed_field_is_not_a_trap_for_a_pad() -> void:
	# Settings -> Advanced holds a text field. A pad cannot type into it, so the one thing that
	# must be true is that the pad can get back out of it and that the die beside it still
	# rolls a seed on A.
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	var field := panel.get_seed_field()
	assert_object(field).is_not_null()
	field.grab_focus()
	await _tap(JOY_BUTTON_DPAD_DOWN)
	(
		assert_object(panel.get_viewport().gui_get_focus_owner())
		. override_failure_message("the pad could not move off the seed field")
		. is_not_same(field)
	)
	var row := field.get_parent()
	var die: Button = null
	for node: Node in row.get_children():
		if node is Button:
			die = node as Button
	assert_object(die).is_not_null()
	field.text = ""
	die.grab_focus()
	await _tap(JOY_BUTTON_A)
	(
		assert_str(panel.get_seed_field().text)
		. override_failure_message("A on the die beside the seed field rolled nothing")
		. is_not_empty()
	)


func test_the_settings_list_scrolls_with_the_stick() -> void:
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	panel.focus_first()
	await await_idle_frame()
	var first := panel.get_viewport().gui_get_focus_owner()
	await _flick(JOY_AXIS_LEFT_Y, 1.0)
	(
		assert_object(panel.get_viewport().gui_get_focus_owner())
		. override_failure_message("the stick did not move down the settings list")
		. is_not_same(first)
	)


# ------------------------------------------------------------------ run summary, stats, credits


func test_the_run_summary_is_answered_from_the_pad() -> void:
	var summary := _load("res://src/ui/run_summary.tscn") as RunSummary
	summary.show_summary(UiFakes.summary_data(true))
	await await_idle_frame()
	var fired: Array[StringName] = []
	_watch_buttons(summary, fired)
	(
		assert_object(summary.get_viewport().gui_get_focus_owner())
		. override_failure_message("the run summary opened with nothing focused")
		. is_not_null()
	)
	await _tap(JOY_BUTTON_A)
	(
		assert_array(fired)
		. override_failure_message("A on the run summary pressed nothing")
		. is_not_empty()
	)


func test_the_stats_table_scrolls_and_closes_on_the_pad() -> void:
	var stats := _load("res://src/ui/stats_screen.tscn") as StatsScreen
	stats.size = Vector2(320, 120)
	stats.show_stats(UiFakes.profile_stats())
	await await_idle_frame()
	var backs: Array[int] = []
	stats.back_pressed.connect(func() -> void: backs.append(1))
	var limit := stats.scroll_by(10_000)
	assert_int(stats.scroll_by(-10_000)).is_equal(0)
	if limit > 0:
		await _tap(JOY_BUTTON_DPAD_DOWN)
		(
			assert_int(stats.scroll_offset())
			. override_failure_message("the d-pad did not scroll the stats table")
			. is_greater(0)
		)
	await _tap(JOY_BUTTON_B)
	assert_array(backs).override_failure_message("B did not leave the stats table").is_not_empty()


func test_the_credits_leave_on_b() -> void:
	var credits := _load("res://src/ui/credits.tscn") as Credits
	var backs: Array[int] = []
	credits.back_pressed.connect(func() -> void: backs.append(1))
	await await_idle_frame()
	await _tap(JOY_BUTTON_B)
	assert_array(backs).override_failure_message("B did not leave the credits").is_not_empty()


# ------------------------------------------------------------------ the stick stays out of play


func test_closing_the_pause_menu_gives_a_back_to_the_player() -> void:
	# A is `ui_accept` *and* `dodge`, the same overlap Space has had on the keyboard since
	# release. That is only safe while nothing holds focus once a menu is gone: a stale focus
	# owner would turn every dodge into a button press on an invisible menu.
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	await await_idle_frame()
	assert_object(pause.get_viewport().gui_get_focus_owner()).is_not_null()
	pause.close()
	await await_idle_frame()
	await await_idle_frame()
	(
		assert_object(pause.get_viewport().gui_get_focus_owner())
		. override_failure_message("the closed pause menu kept focus: A would press it, not dodge")
		. is_null()
	)


func test_the_stick_does_not_fire_ui_actions_during_play() -> void:
	# Nothing focused and no board on screen: the left stick is the player's movement and must
	# not also be pushing menu navigation into the game.
	var nav := UiStickNav.instance(get_tree())
	assert_object(nav).is_not_null()
	get_viewport().gui_release_focus()
	await await_idle_frame()
	(
		assert_bool(nav.is_live())
		. override_failure_message("the stick is driving UI navigation with no UI on screen")
		. is_false()
	)


# ------------------------------------------------- a rebind capture a pad can always leave

## What this section is about. A capture takes the whole input stream while it is open, and the
## build the owner played had one that nothing on a pad could close: press A on any *keyboard*
## column button and every pad button and every stick deflection was swallowed with a hint
## saying "use the other column", forever. The pause menu withholds Start while a capture is
## open, so on the standalone Settings screen - no pause menu behind it - a pad-only player's
## only way out was killing the process. Everything below goes in as a real device event.


## Restores one action's bindings and the stored settings, so a capture test cannot change
## what the next suite's InputMap or settings look like.
func _with_bindings_restored(action: StringName, body: Callable) -> void:
	var saved: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		saved.append(event)
	var settings := GameState.settings.duplicate(true)
	await body.call()
	InputMap.action_erase_events(action)
	for event: InputEvent in saved:
		InputMap.action_add_event(action, event)
	GameState.settings = settings


func test_a_pad_press_ends_a_keyboard_capture_instead_of_being_swallowed() -> void:
	await _with_bindings_restored(
		&"interact",
		func() -> void:
			var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
			var kb_button: Button = panel._rebind_buttons[&"interact"]
			kb_button.grab_focus()
			# Opened from the keyboard, because that is the only device that can open it now
			# (a pad gets the "keys need a keyboard" notice instead - see below).
			await _key(KEY_ENTER)
			assert_bool(panel.is_capturing()).is_true()

			# The trap: A again, on a keyboard-column capture. It used to vanish into the hint.
			await _tap(JOY_BUTTON_A)

			(
				assert_bool(panel.is_capturing())
				. override_failure_message("the pad could not end a keyboard-column capture")
				. is_false()
			)
			# And it bound nothing: the keyboard column still holds the key it shipped with.
			var still_a_key := false
			for event: InputEvent in InputMap.action_get_events(&"interact"):
				if event is InputEventKey:
					still_a_key = true
			assert_bool(still_a_key).is_true()
	)


func test_b_backs_out_of_a_pad_capture_without_binding_it() -> void:
	await _with_bindings_restored(
		&"potion",
		func() -> void:
			var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
			var pad_button: Button = panel._pad_buttons[&"potion"]
			pad_button.grab_focus()
			await _tap(JOY_BUTTON_A)
			assert_bool(panel.is_capturing()).is_true()

			await _tap(JOY_BUTTON_B)

			(
				assert_bool(panel.is_capturing())
				. override_failure_message("B did not cancel the gamepad capture")
				. is_false()
			)
			var bound_b := false
			for event: InputEvent in InputMap.action_get_events(&"potion"):
				var pad := event as InputEventJoypadButton
				if pad != null and pad.button_index == JOY_BUTTON_B:
					bound_b = true
			(
				assert_bool(bound_b)
				. override_failure_message("B was bound instead of backing out")
				. is_false()
			)
	)


func test_a_stick_flick_does_not_wedge_a_keyboard_capture() -> void:
	await _with_bindings_restored(
		&"map",
		func() -> void:
			var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
			(panel._rebind_buttons[&"map"] as Button).grab_focus()
			await _key(KEY_ENTER)
			assert_bool(panel.is_capturing()).is_true()

			await _flick(JOY_AXIS_LEFT_X, 1.0)

			(
				assert_bool(panel.is_capturing())
				. override_failure_message("a stick deflection left the capture open")
				. is_false()
			)
	)


## Once the capture is closed the screen answers again: B leaves the standalone page. That is
## the whole complaint - "the only documented way out is the Escape key" - answered on a pad.
func test_the_pad_can_leave_the_settings_page_after_a_capture() -> void:
	await _with_bindings_restored(
		&"interact",
		func() -> void:
			var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
			var backs: Array[int] = []
			panel.back_pressed.connect(func() -> void: backs.append(1))
			(panel._rebind_buttons[&"interact"] as Button).grab_focus()
			await _key(KEY_ENTER)
			await _tap(JOY_BUTTON_A)
			assert_bool(panel.is_capturing()).is_false()

			await _tap(JOY_BUTTON_B)

			(
				assert_array(backs)
				. override_failure_message("B did not leave Settings once the capture was closed")
				. is_not_empty()
			)
	)


## And the way out is on screen, naming a button a controller actually has. "Esc cancels" is
## not an instruction a pad can follow.
func test_the_capture_prompt_names_a_button_a_pad_can_press() -> void:
	var pad_device := InputGlyphs.Device.GAMEPAD
	var kb_device := InputGlyphs.Device.KEYBOARD
	for pad: bool in [true, false]:
		var prompt := SettingsPanel.capture_prompt(&"interact", pad)
		(
			assert_str(UiPrompt.render_plain(prompt, pad_device if pad else kb_device))
			. override_failure_message("the capture prompt does not name the pad's way out")
			. contains("B")
		)
	var kb_prompt := SettingsPanel.capture_prompt(&"interact", false)
	assert_str(UiPrompt.render_plain(kb_prompt, kb_device)).contains("Esc")


# ---------------------------------------------- the stick is the d-pad, on every kind of screen


## The class of bug this pins. `UiStickNav` used to synthesise an `InputEventAction`, which
## reaches a screen's own `_unhandled_input` but is not the event a pad sends; the boards - which
## read the action themselves - navigated fine while the title, the pause menu, the Settings
## list and the summary buttons, which rely on the engine's focus stepping, did not move at
## all. What goes in now is the d-pad button itself, so "works on the d-pad" and "works on the
## stick" cannot come apart.
func test_the_stick_is_sent_as_the_matching_d_pad_button() -> void:
	var expected: Dictionary = {
		Vector2i(0, 1): JOY_BUTTON_DPAD_DOWN,
		Vector2i(0, -1): JOY_BUTTON_DPAD_UP,
		Vector2i(-1, 0): JOY_BUTTON_DPAD_LEFT,
		Vector2i(1, 0): JOY_BUTTON_DPAD_RIGHT,
	}
	for dir: Vector2i in expected.keys():
		(
			assert_int(UiStickNav.button_for(dir))
			. override_failure_message("the stick does not send %s as a d-pad press" % dir)
			. is_equal(int(expected[dir]))
		)
	assert_int(UiStickNav.button_for(Vector2i.ZERO)).is_equal(-1)


## A focus-driven menu, driven by the stick alone. The pause menu is the one a player reaches
## mid-run with a controller in their hands and nothing else.
func test_the_left_stick_moves_focus_on_the_pause_menu() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	await await_idle_frame()
	var before := pause.get_viewport().gui_get_focus_owner()
	assert_object(before).is_not_null()
	await _flick(JOY_AXIS_LEFT_Y, 1.0)
	(
		assert_object(pause.get_viewport().gui_get_focus_owner())
		. override_failure_message("the left stick moved nothing on the pause menu")
		. is_not_same(before)
	)
	pause.close()


## And on the run summary's button row, the other focus-driven screen the stick was dead on.
func test_the_left_stick_moves_focus_on_the_run_summary() -> void:
	var summary := _load("res://src/ui/run_summary.tscn") as RunSummary
	summary.show_summary(UiFakes.summary_data(true))
	await await_idle_frame()
	var retry: Button = summary.get_node("%Retry")
	retry.grab_focus()
	await await_idle_frame()
	await _flick(JOY_AXIS_LEFT_X, 1.0)
	(
		assert_object(summary.get_viewport().gui_get_focus_owner())
		. override_failure_message("the left stick moved nothing on the run summary buttons")
		. is_not_same(retry)
	)


# ------------------------------------------- the Settings list, walked rather than grabbed


## Presses `button` until `reached` is true, and reports how many presses it took (-1 for
## never). No `grab_focus()` anywhere: a grab proves a control exists, not that a player can
## get to it, and the round that swapped this suite's walk for a grab shipped thirteen rebind
## rows nothing on a pad could reach.
func _walk_until(index: JoyButton, reached: Callable, limit: int = WALK_LIMIT) -> int:
	var presses := 0
	while presses < limit:
		if bool(reached.call()):
			return presses
		await _tap(index)
		presses += 1
	return presses if bool(reached.call()) else -1


## The standalone Settings page: every row, to the last one, on the d-pad.
func test_the_pad_walks_the_standalone_settings_list_to_its_last_row() -> void:
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(480, 270)
	await await_idle_frame()
	await await_idle_frame()
	var scroll: ScrollContainer = panel.get_node("%Scroll")
	panel.focus_first()
	await await_idle_frame()
	var last := panel.focus_last()
	var walked := await _walk_until(
		JOY_BUTTON_DPAD_DOWN,
		func() -> bool: return panel.get_viewport().gui_get_focus_owner() == last
	)
	(
		assert_int(walked)
		. override_failure_message("the d-pad dead-ended before the last Settings row")
		. is_greater(0)
	)
	(
		assert_int(scroll.scroll_vertical)
		. override_failure_message("the list never scrolled, so the walk saw nothing move")
		. is_greater(0)
	)


## The same list embedded in the pause menu, where it has a footer under it rather than a Back
## button. Down off the last row used to land on Abandon - the destructive button - with no way
## further down; it lands on Resume now, and Resume climbs back into the list.
func test_the_pause_settings_list_closes_its_ring_on_resume() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause.size = Vector2(480, 270)
	pause.open()
	pause.set_tab(PauseMenu.Tab.SETTINGS)
	await await_idle_frame()
	var panel := pause.settings_panel()
	var resume: Button = pause.get_node("%Resume")
	var last := panel.focus_last()
	var walked := await _walk_until(
		JOY_BUTTON_DPAD_DOWN,
		func() -> bool: return pause.get_viewport().gui_get_focus_owner() == last
	)
	(
		assert_int(walked)
		. override_failure_message("the pad dead-ended inside the pause menu's Settings list")
		. is_greater(0)
	)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	(
		assert_object(pause.get_viewport().gui_get_focus_owner())
		. override_failure_message("the bottom of the settings list is still a one-way trip")
		. is_same(resume)
	)
	await _tap(JOY_BUTTON_DPAD_UP)
	assert_object(pause.get_viewport().gui_get_focus_owner()).is_same(last)
	pause.close()


# --------------------------------------------- a binding may not cost the player the menu


## Start during a gamepad capture used to bind Start to whatever was being captured and
## silently unbind it from `pause`. The pause menu withholds `pause` while a capture is open,
## so the mis-press was easy; the result was a run with no reachable menu at all and the two
## rows that could undo it below a fold no pad could scroll past.
func test_start_cannot_be_taken_away_from_pause() -> void:
	await _with_bindings_restored(
		&"interact",
		func() -> void:
			var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
			(panel._pad_buttons[&"interact"] as Button).grab_focus()
			await _tap(JOY_BUTTON_A)
			assert_bool(panel.is_capturing()).is_true()

			await _tap(JOY_BUTTON_START)

			assert_bool(panel.is_capturing()).is_false()
			(
				assert_str(InputGlyphs.binding_name(&"pause", InputGlyphs.Device.GAMEPAD))
				. override_failure_message("Pause lost Start to another action")
				. is_equal("Start")
			)
			assert_str(InputGlyphs.binding_name(&"interact", InputGlyphs.Device.GAMEPAD)).is_equal(
				"X"
			)
			# And it said why, naming the button and what already owns it.
			var hint := (panel.get_node("%Hint") as UiPrompt).plain()
			assert_str(hint).contains("Start")
			assert_str(hint).contains("Pause")
	)


## The other half of reserving B for "cancel": B is still a button the player can bind, by
## holding it. Without this the capture's way out cost the pad one of its four face buttons.
func test_holding_b_binds_b_instead_of_cancelling() -> void:
	await _with_bindings_restored(
		&"potion",
		func() -> void:
			var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
			(panel._pad_buttons[&"potion"] as Button).grab_focus()
			await _tap(JOY_BUTTON_A)
			assert_bool(panel.is_capturing()).is_true()

			Input.parse_input_event(_button(JOY_BUTTON_B, true))
			Input.flush_buffered_events()
			var profile := UiNavProfile.load_default()
			await await_millis(int(profile.capture_hold_seconds * 1000.0) + 250)
			Input.parse_input_event(_button(JOY_BUTTON_B, false))
			Input.flush_buffered_events()
			await await_idle_frame()

			assert_bool(panel.is_capturing()).is_false()
			(
				assert_str(InputGlyphs.binding_name(&"potion", InputGlyphs.Device.GAMEPAD))
				. override_failure_message("a held B did not bind B: the cancel button is lost")
				. is_equal("B")
			)
	)


# ------------------------------------------------------- the boards say how to leave them


## B and Start both did nothing at all on an offers row, and the hint never mentioned the
## Reroll/Skip row under the cards. B now takes the selection there and a second press leaves.
func test_b_leaves_an_offer_board_and_the_hint_says_so() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var chest := _board(ChestUi.Kind.ITEM, UiFakes.chest_context(player))
	var left: Array[int] = []
	chest.skipped.connect(func() -> void: left.append(1))
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.OFFERS)

	await _tap(JOY_BUTTON_B)

	(
		assert_int(chest.selected_row())
		. override_failure_message("B did nothing at all on the offers row")
		. is_equal(ChestUi.Row.BUTTONS)
	)
	(
		assert_str((chest.get_node("%Hint") as UiPrompt).plain())
		. override_failure_message("the board hint still does not say how to leave")
		. contains("B ")
	)
	await _tap(JOY_BUTTON_B)
	(
		assert_array(left)
		. override_failure_message("a second B did not take the way out it had just offered")
		. is_not_empty()
	)


# ------------------------------------------------------ the Controls page can be read on a pad


## The page is the only place the game teaches its controls, and on a pad it drew Move as four
## identical grey discs and Start/Back as two unlabelled pills of the same shape.
func test_the_controls_page_is_legible_on_a_pad() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	pause.set_tab(PauseMenu.Tab.CONTROLS)
	await await_idle_frame()
	# Counted on the page itself, not on the rule behind it: what a player sees is how many
	# glyphs are actually drawn in the Move row.
	var drawn := 0
	for node: Node in pause.find_children("*", "GlyphIcon", true, false):
		var glyph := node as GlyphIcon
		if (
			glyph.visible
			and [&"move_up", &"move_down", &"move_left", &"move_right"].has(glyph.action)
		):
			drawn += 1
	(
		assert_int(drawn)
		. override_failure_message(
			"the Move row draws %d identical glyphs on a pad instead of one" % drawn
		)
		. is_equal(1)
	)
	for action: StringName in [&"pause", &"map"]:
		(
			assert_str(InputGlyphs.label_for(action))
			. override_failure_message("%s draws an unlabelled pad glyph" % action)
			. is_not_empty()
		)
	assert_str(InputGlyphs.label_for(&"pause")).is_equal("Start")
	assert_str(InputGlyphs.label_for(&"map")).is_equal("Back")
	pause.close()
