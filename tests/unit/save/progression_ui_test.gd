## Meta-progression, driven the way the owner drove it: with a controller.
##
## Every case here sends real `InputEventJoypadButton`s through `Input.parse_input_event`, so
## they travel the whole path a pad's press takes - the project's input map, the viewport, the
## focus system, `_unhandled_input`. A test that posts an `InputEventAction` proves the handler
## is wired to the action and nothing at all about whether a player with a pad can do the
## thing, which is how eight rounds of review missed "pressing A does nothing".
class_name ProgressionUiTest
extends GdUnitTestSuite

const CLASS_SELECT := "res://src/ui/class_select.tscn"
const RUN_SUMMARY := "res://src/ui/run_summary.tscn"
## Pad buttons, as `project.godot` binds them: A -> ui_accept, B -> ui_cancel, d-pad -> ui_*.
const PAD_A := JOY_BUTTON_A
const PAD_B := JOY_BUTTON_B
const PAD_LEFT := JOY_BUTTON_DPAD_LEFT
const PAD_RIGHT := JOY_BUTTON_DPAD_RIGHT
const PAD_DOWN := JOY_BUTTON_DPAD_DOWN

var _chosen: Array[StringName] = []


func after_test() -> void:
	_chosen = []


## One real press and release of a physical pad button.
func _press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		event.pressure = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		await get_tree().process_frame
	await get_tree().process_frame


func _class_select(rows: Array[Dictionary] = []) -> ClassSelect:
	var node: ClassSelect = auto_free((load(CLASS_SELECT) as PackedScene).instantiate())
	node.unlock_rows = rows if not rows.is_empty() else _fresh_rows()
	add_child(node)
	node.locked_ids = _locked_from(node.unlock_rows)
	node.class_chosen.connect(func(id: StringName) -> void: _chosen.append(id))
	return node


## The progress a brand-new profile would produce, without touching the real save files.
func _fresh_rows() -> Array[Dictionary]:
	var profile := Profile.new()
	var table := UnlockTable.load_default()
	var out: Array[Dictionary] = []
	for def: UnlockDef in table.ordered():
		(
			out
			. append(
				{
					"id": def.id,
					"title": def.title,
					"description": def.description,
					"kind": "class" if def.grants_class() else "ability",
					"counter": def.counter,
					"value": 0,
					"threshold": def.threshold,
					"fraction": 0.0,
					"progress": def.progress_text(0),
					"unlocked": profile.is_unlocked(def.id),
					"earned_this_run": false,
				}
			)
		)
	return out


static func _locked_from(rows: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Dictionary in rows:
		if not bool(row["unlocked"]):
			out.append(StringName(str(row["id"])))
	return out


## The headline of the whole change: a new player has one class, and the pad says so. Pressing
## A on a locked card starts nothing; pressing A on the Fighter starts the run.
func test_a_new_player_can_only_start_a_run_as_the_fighter() -> void:
	var select := _class_select()
	assert_that(select.selected_id()).is_equal(&"fighter")
	var playable := 0
	for entry: Dictionary in select.classes:
		if not select.is_locked(entry["id"]):
			playable += 1
	assert_int(playable).is_equal(1)
	await _press(PAD_RIGHT)
	assert_that(select.selected_id()).is_equal(&"ranger")
	await _press(PAD_A)
	(
		assert_array(_chosen)
		. override_failure_message("A on a locked class started a run anyway")
		. is_empty()
	)
	await _press(PAD_LEFT)
	assert_that(select.selected_id()).is_equal(&"fighter")
	await _press(PAD_A)
	(
		assert_array(_chosen)
		. override_failure_message("A on the one unlocked class did nothing")
		. contains_exactly([&"fighter"])
	)


## A padlock that explains nothing is a dead end. Selecting a locked class names the
## achievement and the count on the hint line under the cards.
func test_selecting_a_locked_class_states_what_unlocks_it_and_how_close_it_is() -> void:
	var select := _class_select()
	await get_tree().process_frame
	for id: StringName in [&"ranger", &"wizard", &"oligarch"]:
		var text := select.requirement_text(id)
		(
			assert_str(text)
			. override_failure_message("%s is locked and says nothing about why" % String(id))
			. is_not_empty()
		)
		assert_str(text).contains("/")
	assert_str(select.requirement_text(&"ranger")).contains("Clear a floor")
	var index := 0
	for i in select.classes.size():
		if select.classes[i]["id"] == &"wizard":
			index = i
	select.select(index)
	var hint: UiPrompt = select.get_node("%Hint")
	assert_str(hint.text.to_lower()).contains("locked")
	assert_str(hint.text).contains(select.requirement_text(&"wizard"))
	# The old screen said this for whichever class happened to be locked.
	assert_str(hint.text.to_lower()).not_contains("beat floor 3 to unlock")


## Down on the pad opens the unlock board; B closes it again.
func test_the_pad_opens_and_closes_the_unlock_board() -> void:
	var select := _class_select()
	assert_bool(select.board_visible()).is_false()
	await _press(PAD_DOWN)
	(
		assert_bool(select.board_visible())
		. override_failure_message("d-pad down did not open the unlock board")
		. is_true()
	)
	await _press(PAD_B)
	(
		assert_bool(select.board_visible())
		. override_failure_message("B left the unlock board open")
		. is_false()
	)
	# ... and B on the board must not have fallen through and left the screen as well.
	assert_bool(select.visible).is_true()


## The board is the "what have I got and what is close" page: every gated unlock, the locked
## ones the player is nearest to first.
func test_the_board_lists_every_gated_unlock_closest_first() -> void:
	var rows := _fresh_rows()
	rows[0]["fraction"] = 0.9
	rows[0]["value"] = 9
	rows[0]["progress"] = "9 / 10"
	var select := _class_select(rows)
	await _press(PAD_DOWN)
	assert_int(select.board_row_count()).is_equal(Profile.GATED_UNLOCKS.size())
	var grid: GridContainer = select._board_grid
	assert_str((grid.get_child(0) as Label).text).is_equal(str(rows[0]["title"]))
	assert_str((grid.get_child(2) as Label).text).is_equal("9 / 10")
	# Scrolling is the only way a pad reaches the bottom of the list.
	var before := select._board_scroll.scroll_vertical
	await _press(PAD_DOWN)
	assert_int(select._board_scroll.scroll_vertical).is_greater_equal(before)


## A run has to end by saying what it was for.
func test_the_summary_names_what_the_run_unlocked_and_what_is_next() -> void:
	var summary: RunSummary = auto_free((load(RUN_SUMMARY) as PackedScene).instantiate())
	add_child(summary)
	var rows := _fresh_rows()
	rows[0]["unlocked"] = true
	rows[0]["earned_this_run"] = true
	rows[0]["progress"] = "1 / 1"
	(
		summary
		. show_summary(
			{
				"victory": false,
				"floor": 2,
				"progress_rows": rows,
				"counter_gains": {"kills": 42, "gold_earned": 130},
			}
		)
	)
	await get_tree().process_frame
	var text := _text_of(summary.get_node("%Tracks"))
	assert_str(text).contains("Unlocked The Ranger")
	assert_str(text).contains("+42 kills")
	assert_str(text).contains("+130 gold")
	assert_str(text).contains("Next: The Wizard")
	assert_str(text).contains("Defeat 120 enemies.")
	assert_str(text).contains("0 / 120")


## The music section says what the radio did to each floor, not just which songs played.
func test_the_summary_says_what_the_music_did_to_each_floor() -> void:
	var summary: RunSummary = auto_free((load(RUN_SUMMARY) as PackedScene).instantiate())
	add_child(summary)
	(
		summary
		. show_summary(
			{
				"victory": false,
				"floor": 2,
				"tracks": ["Omarchy - Cam"],
				"music_floors":
				[
					{
						"floor": 1,
						"title": "Omarchy",
						"energy": 0.15,
						"tempo": 90.0,
						"playing": true
					},
					{
						"floor": 2,
						"title": "Still Licensed",
						"energy": 0.9,
						"tempo": 140.0,
						"playing": true
					},
				],
			}
		)
	)
	await get_tree().process_frame
	var text := _text_of(summary.get_node("%Tracks"))
	assert_str(text).contains("Music:")
	assert_str(text).contains("Omarchy - Cam")
	# ... in a sentence rather than a debug readout. "F1 calm +12% foes" is how the code says
	# it; a results screen has to say it the way the player would.
	assert_str(text).contains("Calm on floor 1")
	assert_str(text).contains("frantic on floor 2")
	assert_str(text.to_lower()).not_contains("f1 calm")
	assert_str(text.to_lower()).not_contains("foes")
	# The quiet floor got fewer enemies than the loud one, and the screen says so.
	var levers := MusicLevers.shared()
	assert_str(text).contains("%d%% fewer enemies" % -levers.foes_percent(0.15))
	assert_str(text).contains("%d%% more" % levers.foes_percent(0.9))


## Without a floor log there is still the old flat list, so nothing regresses for a resumed run.
func test_the_summary_falls_back_to_the_track_list() -> void:
	var summary: RunSummary = auto_free((load(RUN_SUMMARY) as PackedScene).instantiate())
	add_child(summary)
	summary.show_summary({"victory": true, "tracks": ["A - X", "B - Y"], "music_floors": []})
	await get_tree().process_frame
	assert_str(_text_of(summary.get_node("%Tracks"))).contains("A - X")


static func _text_of(node: Node) -> String:
	var parts: PackedStringArray = []
	for child: Node in node.get_children():
		if child is Label:
			parts.append((child as Label).text)
		parts.append(_text_of(child))
	return "\n".join(parts)
