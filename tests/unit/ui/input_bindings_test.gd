## Rebinding: two device columns per action, conflict detection, reset to defaults, the
## hold/toggle rows, and the reduce-motion policy the settings panel enforces on other
## modules' settings.
##
## The InputMap and `GameState.settings` are process-global, so every test restores both.
class_name InputBindingsTest
extends GdUnitTestSuite

var _saved: Dictionary
var _saved_events: Dictionary = {}


func before_test() -> void:
	_saved = GameState.settings.duplicate(true)
	_saved_events.clear()
	for action: StringName in InputBindings.ACTIONS:
		var events: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event)
		_saved_events[action] = events


func after_test() -> void:
	for action: StringName in InputBindings.ACTIONS:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved_events[action] as Array[InputEvent]:
			InputMap.action_add_event(action, event)
	GameState.settings = _saved


func _panel() -> SettingsPanel:
	var panel: SettingsPanel = auto_free(
		(load("res://src/ui/settings_panel.tscn") as PackedScene).instantiate()
	)
	add_child(panel)
	return panel


static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


static func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


static func _has_key(action: StringName, code: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
			return true
	return false


static func _has_pad(action: StringName, button: JoyButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			if (event as InputEventJoypadButton).button_index == button:
				return true
	return false


# ------------------------------------------------------------------ two columns


func test_every_action_offers_a_keyboard_and_a_pad_button() -> void:
	var panel := _panel()
	for action: StringName in InputBindings.ACTIONS:
		(
			assert_bool(panel._rebind_buttons.has(action))
			. override_failure_message("%s has no keyboard column" % action)
			. is_true()
		)
		(
			assert_bool(panel._pad_buttons.has(action))
			. override_failure_message("%s has no gamepad column" % action)
			. is_true()
		)
	# The two columns of one row reach each other without a mouse.
	var kb: Button = panel._rebind_buttons[&"interact"]
	var pad: Button = panel._pad_buttons[&"interact"]
	assert_str(String(kb.focus_neighbor_right)).is_equal(String(pad.get_path()))
	assert_str(String(pad.focus_neighbor_left)).is_equal(String(kb.get_path()))


func test_pad_binding_leaves_the_keyboard_binding_alone() -> void:
	var panel := _panel()
	panel.rebind(&"potion", _pad(JOY_BUTTON_Y), true)
	assert_bool(_has_pad(&"potion", JOY_BUTTON_Y)).is_true()
	# R (physical 82) is the shipped keyboard binding for potion.
	assert_bool(_has_key(&"potion", KEY_R)).is_true()
	var bindings: Dictionary = GameState.settings["bindings"]
	assert_bool((bindings["potion"] as Dictionary).has("pad")).is_true()


func test_pad_and_mouse_bindings_get_short_readable_names() -> void:
	# `InputEvent.as_text()` writes a sentence; a 62 px settings column needs a label.
	assert_str(InputGlyphs.pad_name(_pad(JOY_BUTTON_A))).is_equal("A")
	assert_str(InputGlyphs.pad_name(_pad(JOY_BUTTON_LEFT_SHOULDER))).is_equal("LB")
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = -1.0
	assert_str(InputGlyphs.pad_name(motion)).is_equal("LS Left")
	motion.axis_value = 1.0
	assert_str(InputGlyphs.pad_name(motion)).is_equal("LS Right")
	motion.axis = JOY_AXIS_TRIGGER_RIGHT
	assert_str(InputGlyphs.pad_name(motion)).is_equal("RT")
	assert_str(InputGlyphs.mouse_name(MOUSE_BUTTON_RIGHT)).is_equal("Mouse R")
	# And the row labels use them: attack ships on the right trigger and the left mouse.
	assert_str(InputGlyphs.binding_name(&"attack", InputGlyphs.Device.GAMEPAD)).is_equal("RT")
	assert_str(InputGlyphs.binding_name(&"attack", InputGlyphs.Device.KEYBOARD)).is_equal("Mouse L")


# ------------------------------------------------------------------ conflicts


func test_conflicts_are_reported_before_a_rebind_happens() -> void:
	var clash := InputBindings.conflicts_for(&"potion", _key(KEY_F))
	assert_array(clash).contains([&"interact"])
	# Its own binding is never a conflict with itself.
	assert_array(InputBindings.conflicts_for(&"interact", _key(KEY_F))).is_empty()


func test_rebinding_over_another_action_unbinds_that_action() -> void:
	var panel := _panel()
	var cleared := panel.rebind(&"potion", _key(KEY_F), false)
	assert_array(cleared).contains([&"interact"])
	assert_bool(_has_key(&"potion", KEY_F)).is_true()
	assert_bool(_has_key(&"interact", KEY_F)).is_false()
	# The loser is persisted as unbound, or the clash would return on the next launch.
	var bindings: Dictionary = GameState.settings["bindings"]
	assert_array((bindings["interact"] as Dictionary)["kb"] as Array).is_empty()
	assert_str((panel._rebind_buttons[&"interact"] as Button).text).is_equal("-")
	assert_str((panel.get_node("%Hint") as UiPrompt).text).contains("Interact")


func test_an_unbound_column_survives_a_reload_of_the_settings() -> void:
	var panel := _panel()
	panel.rebind(&"potion", _key(KEY_F), false)
	# Put the old binding back by hand, then re-apply what was saved.
	InputMap.action_add_event(&"interact", _key(KEY_F))
	InputBindings.apply_bindings(GameState.settings["bindings"] as Dictionary)
	assert_bool(_has_key(&"interact", KEY_F)).is_false()
	assert_bool(_has_key(&"potion", KEY_F)).is_true()


func test_pad_conflicts_are_found_across_device_classes() -> void:
	var panel := _panel()
	# JOY_BUTTON_X (2) ships on interact; taking it for potion must free it.
	var cleared := panel.rebind(&"potion", _pad(JOY_BUTTON_X), true)
	assert_array(cleared).contains([&"interact"])
	assert_bool(_has_pad(&"interact", JOY_BUTTON_X)).is_false()
	assert_bool(_has_key(&"interact", KEY_F)).is_true()


# ------------------------------------------------------------------ defaults


func test_default_events_come_from_the_project_not_the_live_map() -> void:
	InputMap.action_erase_events(&"dodge")
	InputMap.action_add_event(&"dodge", _key(KEY_Z))
	var defaults := InputBindings.default_events(&"dodge")
	assert_int(defaults.size()).is_greater(1)
	var codes: Array[int] = []
	for event: InputEvent in defaults:
		if event is InputEventKey:
			codes.append(int((event as InputEventKey).physical_keycode))
	assert_array(codes).contains([int(KEY_SPACE)])


func test_snapshot_backs_up_reset_when_project_settings_are_unreadable() -> void:
	# The snapshot is taken before any saved binding is applied and never retaken, so a
	# rebound map cannot poison it.
	InputBindings.capture_default_bindings()
	InputMap.action_erase_events(&"potion")
	InputMap.action_add_event(&"potion", _key(KEY_Z))
	InputBindings.capture_default_bindings()
	var stored: Variant = UiRuntime.get_shared().default_bindings.get(&"potion")
	assert_bool(stored is Array).is_true()
	var codes: Array[int] = []
	for event: InputEvent in stored as Array:
		if event is InputEventKey:
			codes.append(int((event as InputEventKey).physical_keycode))
	assert_array(codes).contains([int(KEY_R)])
	assert_array(codes).not_contains([int(KEY_Z)])


func test_reset_bindings_restores_every_action_and_clears_the_overrides() -> void:
	var panel := _panel()
	panel.rebind(&"potion", _key(KEY_F), false)
	panel.rebind(&"dodge", _pad(JOY_BUTTON_Y), true)
	assert_bool(_has_key(&"interact", KEY_F)).is_false()
	panel.reset_bindings()
	assert_bool(_has_key(&"interact", KEY_F)).is_true()
	assert_bool(_has_key(&"potion", KEY_R)).is_true()
	assert_bool(_has_key(&"potion", KEY_F)).is_false()
	assert_bool(_has_pad(&"dodge", JOY_BUTTON_A)).is_true()
	assert_dict(GameState.settings["bindings"] as Dictionary).is_empty()
	assert_str((panel.get_node("%Hint") as UiPrompt).text).contains("reset")


# ------------------------------------------------------------------ hold / toggle


func test_hold_rows_cycle_and_persist_per_action() -> void:
	var panel := _panel()
	GameState.settings["hold_mode"] = {}
	GameState.settings["hold_to_toggle"] = false
	var button: Button = panel._controls["hold_mode:attack"]
	assert_str(button.text).is_equal("Hold")
	panel.cycle_hold_mode(&"attack")
	assert_str(PlayerInput.hold_mode(&"attack")).is_equal(PlayerInput.MODE_TOGGLE)
	assert_str(button.text).is_equal("Toggle")
	# Only the action that was cycled changes.
	assert_str(PlayerInput.hold_mode(&"secondary")).is_equal(PlayerInput.MODE_HOLD)
	panel.cycle_hold_mode(&"attack")
	assert_str(PlayerInput.hold_mode(&"attack")).is_equal(PlayerInput.MODE_HOLD)


func test_legacy_master_switch_still_drives_unset_actions() -> void:
	GameState.settings["hold_mode"] = {}
	GameState.settings["hold_to_toggle"] = true
	assert_str(PlayerInput.hold_mode(&"attack")).is_equal(PlayerInput.MODE_TOGGLE)
	# An explicit per-action choice wins over the legacy switch.
	GameState.settings["hold_mode"] = {"attack": PlayerInput.MODE_HOLD}
	assert_str(PlayerInput.hold_mode(&"attack")).is_equal(PlayerInput.MODE_HOLD)
	assert_str(PlayerInput.hold_mode(&"map")).is_equal(PlayerInput.MODE_TOGGLE)


# ------------------------------------------------------------------ reduce motion


func test_reduce_motion_overrides_screen_shake_without_eating_the_preference() -> void:
	var panel := _panel()
	panel.set_setting("screen_shake", true)
	panel.set_setting("reduce_motion", true)
	# The player's own choice is untouched; only the effective value flips.
	assert_bool(bool(GameState.settings["screen_shake"])).is_true()
	assert_bool(SettingsPanel.screen_shake_active(GameState.settings)).is_false()
	var check: CheckBox = panel._controls["screen_shake"]
	assert_bool(check.disabled).is_true()
	assert_bool(check.button_pressed).is_false()
	panel.set_setting("reduce_motion", false)
	assert_bool(SettingsPanel.screen_shake_active(GameState.settings)).is_true()
	assert_bool(check.disabled).is_false()
	assert_bool(check.button_pressed).is_true()


func test_reduce_motion_disables_hit_stop_and_screen_shake() -> void:
	var panel := _panel()
	panel.set_setting("reduce_motion", true)
	var feel := GameFeel.instance(get_tree())
	assert_bool(feel.hit_stop_enabled).is_false()
	HitStop.apply(get_tree(), 0.2, 0.1)
	assert_bool(HitStop.is_active(get_tree())).is_false()
	assert_bool(feel.shake_allowed()).is_false()
	panel.set_setting("reduce_motion", false)
	assert_bool(GameFeel.instance(get_tree()).hit_stop_enabled).is_true()
	assert_bool(feel.shake_allowed()).is_true()


func test_apply_all_enforces_the_policy_at_boot() -> void:
	GameState.settings["screen_shake"] = true
	GameState.settings["reduce_motion"] = true
	SettingsPanel.apply_all(GameState.settings)
	assert_bool(GameFeel.instance(get_tree()).hit_stop_enabled).is_false()
	assert_bool(GameFeel.instance(get_tree()).shake_allowed()).is_false()
	GameState.settings["reduce_motion"] = false
	SettingsPanel.apply_all(GameState.settings)
	assert_bool(GameFeel.instance(get_tree()).hit_stop_enabled).is_true()
