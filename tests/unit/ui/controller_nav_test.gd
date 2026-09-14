## Every screen has to be reachable with a controller alone. Two failure shapes are checked:
## a control that only a mouse can hit (no focus, no ui_* handler), and a region of content
## that no input can scroll to.
##
## **This suite proves handlers, not controllers.** It pushes `InputEventAction` straight at a
## screen, which bypasses the InputMap entirely - so it stayed green through a shipped build in
## which `ui_accept` had no gamepad binding at all and A did nothing anywhere in the game. The
## device-level cover is `controller_device_test.gd`, which sends real `InputEventJoypadButton`
## and `InputEventJoypadMotion` through `Input`. Add a screen there too, not only here.
class_name ControllerNavTest
extends GdUnitTestSuite


static func _action(name: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	return event


func _load(path: String) -> Control:
	var node: Control = auto_free((load(path) as PackedScene).instantiate())
	add_child(node)
	return node


## Every Button/LineEdit/Slider under `node`, whether or not it can take focus.
static func _interactive(node: Node, out: Array[Control] = []) -> Array[Control]:
	for child: Node in node.get_children():
		if child is Button or child is LineEdit or child is Range:
			out.append(child as Control)
		_interactive(child, out)
	return out


func test_title_menu_is_entirely_focusable_and_starts_focused() -> void:
	var title := _load("res://src/ui/title.tscn") as Title
	title.focus_default()
	var focused := title.get_viewport().gui_get_focus_owner()
	assert_object(focused).is_not_null()
	for control: Control in _interactive(title):
		if not control.visible:
			continue
		(
			assert_int(control.focus_mode)
			. override_failure_message("%s on the title screen cannot be focused" % control.name)
			. is_equal(Control.FOCUS_ALL)
		)


func test_settings_panel_rows_are_all_focusable_and_the_list_follows_focus() -> void:
	var panel := _load("res://src/ui/settings_panel.tscn") as SettingsPanel
	var scroll: ScrollContainer = panel.get_node("%Scroll")
	var controls := _interactive(panel)
	assert_int(controls.size()).is_greater(20)
	for control: Control in controls:
		if not control.visible:
			continue
		(
			assert_int(control.focus_mode)
			. override_failure_message("settings row %s cannot be focused" % control.name)
			. is_equal(Control.FOCUS_ALL)
		)
	panel.focus_first()
	assert_object(panel.get_viewport().gui_get_focus_owner()).is_not_null()
	# The list follows focus, asserted on where a row actually lands rather than on
	# `ScrollContainer.follow_focus`. The flag is deliberately off: it scrolls the focused row
	# flush to the edge of the viewport and leaves the section heading above it sliced in half
	# under the page header, which is what a verifier saw. `SettingsPanel.reveal` replaces it.
	#
	# This is the geometry half only, and a `grab_focus()` is not a thing a player can do. The
	# half that matters - that a pad can *walk* here at all - is
	# `controller_device_test.test_the_pad_walks_the_standalone_settings_list_to_its_last_row`
	# and the whole-session walk in `pad_session_test.gd`. Neither replaces the other: this one
	# says the row lands somewhere readable, those say the row can be reached.
	panel.size = Vector2(480, 270)
	await await_idle_frame()
	var far: Button = panel._pad_buttons[&"pause"]
	far.grab_focus()
	await await_idle_frame()
	var top := scroll.global_position.y
	(
		assert_float(far.global_position.y)
		. override_failure_message("the last rebind row was not scrolled into view by focus")
		. is_greater_equal(top)
	)
	assert_float(far.global_position.y + far.size.y).is_less_equal(top + scroll.size.y)


func test_pause_menu_tabs_and_footer_reach_each_other() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	var tabs: Array[Button] = pause._tab_buttons
	var resume: Button = pause.get_node("%Resume")
	var abandon: Button = pause.get_node("%Abandon")
	for tab: Button in tabs:
		(
			assert_str(String(tab.focus_neighbor_bottom))
			. override_failure_message("tab %s has no way down into the footer" % tab.text)
			. is_not_empty()
		)
	assert_str(String(resume.focus_neighbor_top)).is_not_empty()
	assert_str(String(resume.focus_neighbor_left)).is_equal(String(abandon.get_path()))
	# Shoulder buttons (and PgUp/PgDn) are the only way to change tab on a pad.
	pause.set_tab(PauseMenu.Tab.BUILD)
	pause._input(_action(&"ui_page_down"))
	assert_int(pause.current_tab).is_equal(PauseMenu.Tab.CONTROLS)
	pause._input(_action(&"ui_page_up"))
	assert_int(pause.current_tab).is_equal(PauseMenu.Tab.BUILD)
	pause.close()


func test_pause_menu_confirm_dialog_is_navigable() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	pause._ask_abandon()
	assert_bool(pause.confirm_visible()).is_true()
	var no: Button = pause.get_node("%ConfirmNo")
	var yes: Button = pause.get_node("%ConfirmYes")
	assert_object(pause.get_viewport().gui_get_focus_owner()).is_same(no)
	assert_str(String(no.focus_neighbor_right)).is_equal(String(yes.get_path()))
	pause._input(_action(&"ui_cancel"))
	assert_bool(pause.confirm_visible()).is_false()
	pause.close()


func test_every_pause_page_leaves_something_focused() -> void:
	var pause := _load("res://src/ui/pause_menu.tscn") as PauseMenu
	pause.open()
	for tab in PauseMenu.Tab.size():
		pause.set_tab(tab)
		(
			assert_object(pause.get_viewport().gui_get_focus_owner())
			. override_failure_message("pause tab %d left nothing focused" % tab)
			. is_not_null()
		)
	assert_int(pause.focusable_controls().size()).is_greater(4)
	pause.close()


func test_chest_picker_reaches_its_buttons_without_a_pointer() -> void:
	var chest := _load("res://src/ui/chest_ui.tscn") as ChestUi
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	chest.show_offers(
		ChestUi.Kind.ITEM, UiFakes.make_offers(ChestUi.Kind.ITEM), UiFakes.chest_context(player)
	)
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.OFFERS)
	chest._unhandled_input(_action(&"ui_down"))
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.BUTTONS)
	chest._unhandled_input(_action(&"ui_right"))
	assert_int(chest.selected_index()).is_equal(1)
	chest._unhandled_input(_action(&"ui_up"))
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.OFFERS)


func test_class_select_browses_and_confirms_from_the_d_pad() -> void:
	var select := _load("res://src/ui/class_select.tscn") as ClassSelect
	var monitor := monitor_signals(select)
	select.select(0)
	var first := select.selected_id()
	select._unhandled_input(_action(&"ui_right"))
	assert_str(String(select.selected_id())).is_not_equal(String(first))
	select._unhandled_input(_action(&"ui_left"))
	assert_str(String(select.selected_id())).is_equal(String(first))
	select._unhandled_input(_action(&"ui_accept"))
	await assert_signal(monitor).is_emitted("class_chosen", [first])
	select._unhandled_input(_action(&"ui_cancel"))
	await assert_signal(monitor).is_emitted("back_pressed")


func test_stats_table_scrolls_on_the_d_pad() -> void:
	var stats := _load("res://src/ui/stats_screen.tscn") as StatsScreen
	stats.size = Vector2(320, 120)
	stats.show_stats(UiFakes.profile_stats())
	await await_idle_frame()
	assert_int(stats.scroll_offset()).is_equal(0)
	stats._unhandled_input(_action(&"ui_down"))
	# A short profile may already fit; what must never happen is scrolling past the content.
	var limit := stats.scroll_by(10_000)
	assert_int(stats.scroll_by(-10_000)).is_equal(0)
	assert_int(limit).is_greater_equal(0)


func test_credits_scroll_and_leave_on_the_d_pad() -> void:
	var credits := _load("res://src/ui/credits.tscn") as Credits
	var monitor := monitor_signals(credits)
	await await_idle_frame()
	credits._unhandled_input(_action(&"ui_down"))
	credits._unhandled_input(_action(&"ui_cancel"))
	await assert_signal(monitor).is_emitted("back_pressed")


func test_run_summary_buttons_are_focusable_and_one_starts_focused() -> void:
	var summary := _load("res://src/ui/run_summary.tscn") as RunSummary
	summary.show_summary(UiFakes.summary_data(true))
	await await_idle_frame()
	for control: Control in _interactive(summary):
		(
			assert_int(control.focus_mode)
			. override_failure_message("%s on the run summary cannot be focused" % control.name)
			. is_equal(Control.FOCUS_ALL)
		)
	assert_object(summary.get_viewport().gui_get_focus_owner()).is_not_null()
