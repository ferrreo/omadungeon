class_name PauseMenuTest
extends GdUnitTestSuite


func after_test() -> void:
	get_tree().paused = false


func _pause() -> PauseMenu:
	var pause: PauseMenu = auto_free(
		(load("res://src/ui/pause_menu.tscn") as PackedScene).instantiate()
	)
	add_child(pause)
	return pause


func test_open_pauses_tree_and_close_resumes() -> void:
	var pause := _pause()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	pause.bind(player)
	pause.open()
	assert_bool(get_tree().paused).is_true()
	assert_bool(pause.is_open()).is_true()
	pause.set_tab(PauseMenu.Tab.CONTROLS)
	assert_int(pause.current_tab).is_equal(PauseMenu.Tab.CONTROLS)
	pause.close()
	assert_bool(get_tree().paused).is_false()


func test_abandon_requires_confirmation() -> void:
	var pause := _pause()
	pause.open()
	var monitor := monitor_signals(pause)
	(pause.get_node("%Abandon") as Button).pressed.emit()
	assert_bool(pause.confirm_visible()).is_true()
	(pause.get_node("%ConfirmYes") as Button).pressed.emit()
	await assert_signal(monitor).is_emitted("abandon_pressed")
	assert_bool(pause.is_open()).is_false()


func test_settings_tab_embeds_panel() -> void:
	var pause := _pause()
	assert_object(pause.settings_panel()).is_not_null()
	assert_bool(pause.settings_panel().standalone).is_false()


func test_save_and_quit_unpauses_the_tree() -> void:
	var pause := _pause()
	pause.open()
	var monitor := monitor_signals(pause)
	(pause.get_node("%SaveQuit") as Button).pressed.emit()
	await assert_signal(monitor).is_emitted("save_quit_pressed")
	assert_bool(pause.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()


func test_resume_button_emits_resume_pressed() -> void:
	var pause := _pause()
	pause.open()
	var monitor := monitor_signals(pause)
	(pause.get_node("%Resume") as Button).pressed.emit()
	await assert_signal(monitor).is_emitted("resume_pressed")
	assert_bool(get_tree().paused).is_false()


func test_leaving_the_tree_while_open_unpauses() -> void:
	var pause := _pause()
	pause.open()
	assert_bool(get_tree().paused).is_true()
	pause.get_parent().remove_child(pause)
	assert_bool(get_tree().paused).is_false()
	assert_bool(pause.is_open()).is_false()


func test_pause_input_is_ignored_while_a_chest_is_open() -> void:
	var pause := _pause()
	var chest: ChestUi = auto_free(
		(load("res://src/ui/chest_ui.tscn") as PackedScene).instantiate()
	)
	pause.get_parent().add_child(chest)
	chest.show_offers(ChestUi.Kind.GOLD, [10, 20, 30], {})
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	pause._input(event)
	assert_bool(pause.is_open()).is_false()
	chest.close()
	pause._input(event)
	assert_bool(pause.is_open()).is_true()
	pause.close()


## Every Label text under `node`, in tree order.
static func _label_texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child: Node in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_label_texts(child))
	return out


## The stats page is where a player decides which stat orb to take, and it used to list
## everything a primary buys *except* the damage: a Fighter with Might 6 (+24% melee per
## Stats._derived_bonus) saw no damage number anywhere on the page.
func test_stats_page_shows_the_damage_a_primary_buys() -> void:
	var pause := _pause()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	pause.bind(player)
	pause.open()
	pause.set_tab(PauseMenu.Tab.BUILD)
	var texts := _label_texts(pause)
	for label: String in ["Melee damage", "Ranged damage", "Ability damage", "Lifesteal"]:
		(
			assert_bool(texts.has(label))
			. override_failure_message("the stats page never shows '%s'" % label)
			. is_true()
		)
	assert_int(player.stats.primary(&"might")).is_equal(6)
	(
		assert_bool(texts.has("+24%"))
		. override_failure_message(
			"Might 6 is +24%% melee damage, but the page shows none of it: %s" % str(texts)
		)
		. is_true()
	)
	pause.close()


## A verifier found the settings list drawn half-clipped under its own header, and this is the
## screen it was on. `set_tab` focuses the first row the moment the tab opens, before the page
## has been laid out, so the scroll-to-focus ran against a viewport still zero pixels tall,
## decided the row was miles below the bottom, and scrolled the list 8 px down and left it
## there - with "Video" sliced in half by the top edge under the tab row. Asserted on where the
## heading lands, in the tab the player opens.
func test_the_settings_tab_does_not_open_with_its_first_heading_cut_in_half() -> void:
	var pause := _pause()
	pause.open()
	pause.set_tab(PauseMenu.Tab.SETTINGS)
	var panel := pause.settings_panel()
	var scroll := panel.get_node("%Scroll") as ScrollContainer
	var heading := (panel.get_node("%List") as VBoxContainer).get_child(0) as Label
	assert_str(heading.text).is_equal("Video")
	# Past the open animation, which is what made the old numbers wrong.
	for i in 8:
		await await_idle_frame()

	var top := UiListReveal.offset_in(scroll, heading)
	(
		assert_float(top)
		. override_failure_message("the first settings heading is cut by the top of the list")
		. is_greater_equal(0.0)
	)
	assert_float(top + heading.size.y).is_less_equal(scroll.size.y)
	assert_int(scroll.scroll_vertical).is_equal(0)
	pause.close()
