class_name SettingsPanelTest
extends GdUnitTestSuite

const REBIND_ACTION := &"interact"
const PANEL_SCENE := preload("res://src/ui/settings_panel.tscn")

var _saved: Dictionary
var _saved_file: String = ""
var _had_file: bool = false
var _saved_events: Array[InputEvent] = []


func before_test() -> void:
	_saved = GameState.settings.duplicate(true)
	_had_file = FileAccess.file_exists(GameState.settings_path)
	_saved_file = ""
	if _had_file:
		var file := FileAccess.open(GameState.settings_path, FileAccess.READ)
		if file != null:
			_saved_file = file.get_as_text()
	_saved_events = []
	for event: InputEvent in InputMap.action_get_events(REBIND_ACTION):
		_saved_events.append(event)


## Restores the settings file and the InputMap: settings are global process state, so nothing
## here may survive the suite. `GameState.settings_path` is the sandbox copy under a test run
## (SaveManager redirects it), never the developer's real settings.json.
func after_test() -> void:
	GameState.settings = _saved
	SettingsPanel.apply_all(GameState.settings)
	InputMap.action_erase_events(REBIND_ACTION)
	for event: InputEvent in _saved_events:
		InputMap.action_add_event(REBIND_ACTION, event)
	if _had_file:
		var file := FileAccess.open(GameState.settings_path, FileAccess.WRITE)
		if file != null:
			file.store_string(_saved_file)
	elif FileAccess.file_exists(GameState.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.settings_path))


func _panel() -> SettingsPanel:
	var panel: SettingsPanel = auto_free(PANEL_SCENE.instantiate())
	add_child(panel)
	return panel


func test_toggle_round_trips_into_game_state() -> void:
	var panel := _panel()
	var check: CheckBox = panel._controls["screen_shake"]
	var monitor := monitor_signals(panel)
	check.button_pressed = false
	assert_bool(GameState.settings["screen_shake"]).is_false()
	await assert_signal(monitor).is_emitted("changed", ["screen_shake", false])
	check.button_pressed = true
	assert_bool(GameState.settings["screen_shake"]).is_true()
	assert_str(check.text).is_equal("On")


func test_change_announces_on_the_event_bus() -> void:
	var panel := _panel()
	var monitor := monitor_signals(EventBus, false)
	panel.set_setting("music_lights", false)
	await assert_signal(monitor).is_emitted("settings_changed", ["music_lights"])


func test_slider_writes_value_after_flush() -> void:
	var panel := _panel()
	var slider: HSlider = panel._controls["music_volume"]
	slider.value = 0.5
	assert_float(float(GameState.settings["music_volume"])).is_equal_approx(0.5, 0.01)
	panel.flush_pending_save()
	# `settings_path`, not the constant: under a test run it points into the throwaway sandbox,
	# and reading the constant would assert against the developer's real settings.json.
	assert_bool(FileAccess.file_exists(GameState.settings_path)).is_true()
	var file := FileAccess.open(GameState.settings_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_float(float((parsed as Dictionary)["music_volume"])).is_equal_approx(0.5, 0.01)


func test_rebind_updates_input_map_and_settings() -> void:
	var panel := _panel()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	panel.rebind(REBIND_ACTION, key, false)
	var found := false
	for event: InputEvent in InputMap.action_get_events(REBIND_ACTION):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_J:
			found = true
	assert_bool(found).is_true()
	var bindings: Dictionary = GameState.settings["bindings"]
	assert_that(bindings["interact"]["kb"][0]["code"]).is_equal(int(KEY_J))


func test_apply_all_sets_deadzone() -> void:
	GameState.settings["deadzone"] = 0.45
	SettingsPanel.apply_all(GameState.settings)
	assert_float(InputMap.action_get_deadzone(&"move_left")).is_equal_approx(0.45, 0.001)


func test_apply_key_only_touches_that_setting() -> void:
	GameState.settings["deadzone"] = 0.2
	SettingsPanel.apply_key(GameState.settings, "deadzone")
	assert_float(InputMap.action_get_deadzone(&"move_up")).is_equal_approx(0.2, 0.001)


# --------------------------------------------------- the seed's new home (owner report 7)


## The seed used to be the second row of the title menu. It is one row at the bottom of
## Settings now: findable on purpose, unmissable no longer.
func test_the_seed_lives_in_the_advanced_section_at_the_bottom() -> void:
	var panel := _panel()
	var headings: PackedStringArray = []
	for child: Node in (panel.get_node("%List") as VBoxContainer).get_children():
		if child is Label and (child as Label).theme_type_variation == &"Heading":
			headings.append((child as Label).text)
	assert_array(headings).contains([SettingsPanel.ADVANCED_TITLE])
	assert_str(headings[headings.size() - 1]).is_equal(SettingsPanel.ADVANCED_TITLE)
	var field := panel.get_seed_field()
	assert_object(field).is_not_null()
	assert_str(field.placeholder_text).is_equal(SettingsPanel.SEED_PLACEHOLDER)
	# It says what it does, including that a seed does not pin a whole dungeon.
	assert_str(field.tooltip_text).is_equal(Title.SEED_TOOLTIP)
	assert_str(SettingsPanel.seed_help_text().to_lower()).contains("next new run")
	assert_str(SettingsPanel.seed_help_text().to_lower()).contains("wallpaper")


## Typing one is still easy, and what is typed is what the title screen will spend.
func test_a_typed_seed_reaches_the_setting_the_title_screen_reads() -> void:
	var panel := _panel()
	var field := panel.get_seed_field()
	field.text = "12345"
	field.text_changed.emit("12345")
	assert_str(str(GameState.settings[Title.SEED_SETTING])).is_equal("12345")
	panel.roll_seed()
	assert_str(field.text).is_not_equal("12345")
	assert_str(field.text).is_not_empty()
	assert_str(str(GameState.settings[Title.SEED_SETTING])).is_equal(field.text)
	panel.set_seed_text("")
	assert_str(str(GameState.settings[Title.SEED_SETTING])).is_empty()


# ------------------------------------------- the window is the truth (owner report 12)


## Hosts a panel inside its own embedded `Window`, so a test can move the window the way a
## compositor does. An embedded sub-window keeps `mode` in the engine instead of handing it to
## the display server, which is what makes `window.mode = ...` mean something headless; the
## panel reads whatever window it happens to be in, with no test-only path through it.
func _windowed_panel() -> SettingsPanel:
	var window: Window = auto_free(Window.new())
	window.size = Vector2i(480, 270)
	add_child(window)
	var panel := PANEL_SCENE.instantiate() as SettingsPanel
	window.add_child(panel)
	await await_idle_frame()
	return panel


## Polls until `key` reads `want`, or gives up. A poll with a deadline, not a frame count:
## the panel reconciles on its own `_process`, and how many frames that takes is not a fact
## about the code.
func _settles_to(key: String, want: bool) -> bool:
	for i in 12:
		if bool(GameState.settings.get(key, false)) == want:
			return true
		await await_idle_frame()
	return bool(GameState.settings.get(key, false)) == want


## Owner report 12: "got an issue with the fullscreen toggle too - it can be out of sync, say
## it is not fullscreen when in reality it is."
##
## The compositor's move, made the way the compositor makes it: the window mode changes and
## nothing tells the game. Nothing below touches the panel, calls a setter or presses a row -
## a test that flipped the setting and read the setting back is exactly the test that missed
## this, because the bug was that the setting was never the thing being asked.
func test_a_window_the_compositor_fullscreened_reaches_the_row_and_the_setting() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	var check: CheckBox = panel._controls["fullscreen"]
	assert_bool(check.button_pressed).is_false()

	panel.get_window().mode = Window.MODE_FULLSCREEN

	(
		assert_bool(await _settles_to("fullscreen", true))
		. override_failure_message(
			"the stored setting still says windowed over a fullscreen window"
		)
		. is_true()
	)
	(
		assert_bool(check.button_pressed)
		. override_failure_message("the Fullscreen row still reads Off over a fullscreen window")
		. is_true()
	)
	assert_str(check.text).is_equal("On")


## The other fullscreen mode. A compositor or a driver can leave the window in
## `MODE_EXCLUSIVE_FULLSCREEN`, and the old comparison was against `MODE_FULLSCREEN` alone,
## so a window filling the screen read as windowed.
func test_exclusive_fullscreen_counts_as_fullscreen() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	panel.get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	assert_bool(await _settles_to("fullscreen", true)).is_true()
	assert_bool((panel._controls["fullscreen"] as CheckBox).button_pressed).is_true()
	assert_bool(SettingsPanel.window_is_fullscreen(panel.get_window())).is_true()


## And back: the compositor un-fullscreens the window, and the row follows it down again
## rather than the panel pushing its stale "on" back onto the window.
func test_leaving_fullscreen_underneath_the_game_turns_the_row_back_off() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	var window := panel.get_window()
	window.mode = Window.MODE_FULLSCREEN
	assert_bool(await _settles_to("fullscreen", true)).is_true()

	window.mode = Window.MODE_WINDOWED

	assert_bool(await _settles_to("fullscreen", false)).is_true()
	assert_bool((panel._controls["fullscreen"] as CheckBox).button_pressed).is_false()
	assert_int(int(window.mode)).is_equal(int(Window.MODE_WINDOWED))


## A maximised window is not a fullscreen window, and applying the video settings must not
## restore it. The old `_apply_window` compared the mode against one value and assigned the
## other, so every touch of any video setting un-maximised a window the player had maximised.
func test_applying_video_settings_leaves_a_maximised_window_maximised() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	var window := panel.get_window()
	window.mode = Window.MODE_MAXIMIZED
	GameState.settings["fullscreen"] = false

	SettingsPanel.apply_key(GameState.settings, "fullscreen", window)

	assert_int(int(window.mode)).is_equal(int(Window.MODE_MAXIMIZED))
	assert_bool(SettingsPanel.window_is_fullscreen(window)).is_false()
	assert_bool(await _settles_to("fullscreen", false)).is_true()


## Owner report 12, the half the engine cannot reach. On Wayland a window the compositor
## fullscreened still reads `MODE_MAXIMIZED` to every call the engine offers - which is also
## what an ordinary *tiled* Hyprland window reads - so `window.mode` is the same byte in both
## states and no amount of reading it can tell them apart. `CompositorWindow` asks the window
## manager instead, and its answer outranks the engine's wherever it has one.
func test_the_compositor_outranks_a_window_mode_that_cannot_see_the_change() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	var check: CheckBox = panel._controls["fullscreen"]
	panel.get_window().mode = Window.MODE_MAXIMIZED
	assert_bool(await _settles_to("fullscreen", false)).is_true()

	panel._compositor.state = CompositorWindow.State.FULLSCREEN

	(
		assert_bool(await _settles_to("fullscreen", true))
		. override_failure_message(
			"the window manager says fullscreen and the setting still says windowed"
		)
		. is_true()
	)
	assert_bool(check.button_pressed).is_true()
	assert_str(check.text).is_equal("On")


## And down again when the compositor drops it, with the engine's reading never moving.
func test_the_row_follows_the_compositor_back_out_of_fullscreen() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	panel.get_window().mode = Window.MODE_MAXIMIZED
	panel._compositor.state = CompositorWindow.State.FULLSCREEN
	assert_bool(await _settles_to("fullscreen", true)).is_true()

	panel._compositor.state = CompositorWindow.State.WINDOWED

	assert_bool(await _settles_to("fullscreen", false)).is_true()
	assert_bool((panel._controls["fullscreen"] as CheckBox).button_pressed).is_false()
	assert_int(int(panel.get_window().mode)).is_equal(int(Window.MODE_MAXIMIZED))


## No compositor, or a query that failed: the engine's reading is all there is, and it is
## still read. Nothing here may depend on a window manager being present.
func test_no_compositor_answer_leaves_the_engine_in_charge() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	assert_int(panel._compositor.state).is_equal(CompositorWindow.State.UNKNOWN)

	panel.get_window().mode = Window.MODE_FULLSCREEN

	assert_bool(await _settles_to("fullscreen", true)).is_true()
	assert_bool((panel._controls["fullscreen"] as CheckBox).button_pressed).is_true()


## Unticking the row over a compositor-made fullscreen has to *leave* fullscreen. Godot's
## Wayland backend sends only the difference between the mode it believes it is in and the one
## asked for, so with the engine still believing `MODE_MAXIMIZED` there is no fullscreen on its
## books to unset and the window would stay where the compositor put it. The panel writes
## reality in first, which is why the window ends up windowed rather than merely un-maximised.
func test_unticking_the_row_under_a_compositor_fullscreen_leaves_fullscreen() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	var window := panel.get_window()
	window.mode = Window.MODE_MAXIMIZED
	panel._compositor.state = CompositorWindow.State.FULLSCREEN
	assert_bool(await _settles_to("fullscreen", true)).is_true()

	panel.set_setting("fullscreen", false)

	(
		assert_int(int(window.mode))
		. override_failure_message("the window was un-maximised instead of un-fullscreened")
		. is_equal(int(Window.MODE_WINDOWED))
	)
	assert_bool(bool(GameState.settings["fullscreen"])).is_false()


## The game moving its own window must not be undone a frame later by an answer that predates
## the move. The stale reading is dropped when the panel writes, so the row stays where the
## player put it until a fresh query comes back.
func test_the_row_does_not_flap_when_the_game_makes_the_change() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	panel._compositor.state = CompositorWindow.State.WINDOWED
	assert_bool(await _settles_to("fullscreen", false)).is_true()

	(panel._controls["fullscreen"] as CheckBox).button_pressed = true
	for i in 8:
		await await_idle_frame()

	assert_int(panel._compositor.state).is_equal(CompositorWindow.State.UNKNOWN)
	(
		assert_bool(bool(GameState.settings["fullscreen"]))
		. override_failure_message("a stale compositor answer turned the player's choice back off")
		. is_true()
	)
	assert_bool(SettingsPanel.window_is_fullscreen(panel.get_window())).is_true()


## The row is still a control: pressing it fullscreens the window it is in.
func test_the_row_still_drives_the_window_it_lives_in() -> void:
	var panel: SettingsPanel = await _windowed_panel()
	var check: CheckBox = panel._controls["fullscreen"]
	check.button_pressed = true
	await await_idle_frame()
	assert_bool(SettingsPanel.window_is_fullscreen(panel.get_window())).is_true()
	assert_bool(bool(GameState.settings["fullscreen"])).is_true()


# ------------------------------------------- the list is not clipped under the header


## A verifier found the settings list drawn half-clipped under its own header: `follow_focus`
## scrolls the focused row to the very edge of the viewport, so stepping onto the first row of
## a section left that section's heading sliced in half above it - and the heading is the only
## thing on the page that says what the row belongs to.
func test_stepping_into_a_section_keeps_its_heading_fully_on_screen() -> void:
	var panel := _panel()
	panel.size = Vector2(480, 270)
	await await_idle_frame()
	var scroll := panel.get_node("%Scroll") as ScrollContainer
	var heading := _heading_named(panel, "Audio")
	assert_object(heading).is_not_null()

	# The first row of the Audio section, reached the way focus navigation reaches it.
	(panel._controls["master_volume"] as HSlider).grab_focus()
	await await_idle_frame()

	var top := scroll.global_position.y
	var bottom := top + scroll.size.y
	(
		assert_float(heading.global_position.y)
		. override_failure_message("the Audio heading is clipped off the top of the list")
		. is_greater_equal(top)
	)
	assert_float(heading.global_position.y + heading.size.y).is_less_equal(bottom)
	var row := (panel._controls["master_volume"] as HSlider).global_position.y
	assert_float(row).is_greater_equal(top)
	assert_float(row).is_less_equal(bottom)


## A row far below its heading still wins: the heading is brought along only while both fit.
func test_a_row_too_far_from_its_heading_is_still_revealed() -> void:
	var panel := _panel()
	panel.size = Vector2(480, 270)
	await await_idle_frame()
	var scroll := panel.get_node("%Scroll") as ScrollContainer
	var button: Button = panel._pad_buttons[&"pause"]

	button.grab_focus()
	await await_idle_frame()

	var top := scroll.global_position.y
	(
		assert_float(button.global_position.y)
		. override_failure_message("the last rebind row never scrolled into view")
		. is_greater_equal(top)
	)
	assert_float(button.global_position.y + button.size.y).is_less_equal(top + scroll.size.y)


## The other half of the same complaint. A section whose heading cannot fit alongside the
## focused row used to leave its rule hanging alone under the page header with the word gone -
## a list that looks cut off. Now the heading block is shown whole or not at all.
func test_no_section_heading_is_ever_sliced_by_the_top_of_the_list() -> void:
	var panel := _panel()
	panel.size = Vector2(480, 270)
	await await_idle_frame()
	var scroll := panel.get_node("%Scroll") as ScrollContainer
	var list := panel.get_node("%List") as VBoxContainer

	# The row the gallery focuses, deep inside the Input section and far below its heading.
	(panel._rebind_buttons[&"attack"] as Button).grab_focus()
	await await_idle_frame()

	var top := scroll.global_position.y
	for i in list.get_child_count():
		var label := list.get_child(i) as Label
		if label == null or label.theme_type_variation != &"Heading":
			continue
		var rule := list.get_child(i + 1) as Control
		var block_top := label.global_position.y
		var block_bottom := (
			rule.global_position.y + rule.size.y if rule != null else block_top + label.size.y
		)
		var straddles := block_top < top and block_bottom > top
		(
			assert_bool(straddles)
			. override_failure_message("the %s heading is cut by the top of the list" % label.text)
			. is_false()
		)


## The list keeps a gutter at the top of its viewport, so nothing is ever drawn flush against
## the page header.
func test_the_list_keeps_a_gutter_under_the_header() -> void:
	var panel := _panel()
	panel.size = Vector2(480, 270)
	await await_idle_frame()
	var scroll := panel.get_node("%Scroll") as ScrollContainer
	var list := panel.get_node("%List") as VBoxContainer
	assert_float(list.global_position.y).is_greater(scroll.global_position.y)


func _heading_named(panel: SettingsPanel, text: String) -> Label:
	for child: Node in (panel.get_node("%List") as VBoxContainer).get_children():
		var label := child as Label
		if label != null and label.theme_type_variation == &"Heading" and label.text == text:
			return label
	return null
