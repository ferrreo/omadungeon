class_name TitleTest
extends GdUnitTestSuite

const SCENE := "res://src/ui/title.tscn"


## Every title test starts from "no saved run" so the ones about the plain path are not at the
## mercy of whatever an earlier suite left in the save sandbox.
func before_test() -> void:
	SaveManager.delete_run()
	GameState.settings[Title.SEED_SETTING] = ""


func after_test() -> void:
	SaveManager.delete_run()
	GameState.settings[Title.SEED_SETTING] = ""


func _title() -> Title:
	var title: Title = auto_free((load(SCENE) as PackedScene).instantiate())
	add_child(title)
	return title


func test_subtitle_shows_theme_name() -> void:
	var title := _title()
	assert_str(title.subtitle_text()).is_equal("Dungeon of %s" % Desktop.palette.name)
	assert_str(title.subtitle_text()).contains("Tokyo Night")


## A seed parked in Settings is what the next run uses - and then it is gone, so a player who
## tried one seed once is not silently pinned to it for the rest of the evening.
func test_a_parked_seed_drives_the_next_run_and_is_then_spent() -> void:
	GameState.settings[Title.SEED_SETTING] = "1234"
	var title := _title()
	assert_int(title.current_seed()).is_equal(1234)
	var monitor := monitor_signals(title)
	(title.get_node("%NewRun") as Button).pressed.emit()
	await assert_signal(monitor).is_emitted("new_run_pressed", [1234])
	assert_str(str(GameState.settings[Title.SEED_SETTING])).is_empty()
	# With nothing parked the run is random, which is the case a player never has to think
	# about - two calls in a row do not agree.
	var seeds: Array[int] = []
	for _i in 8:
		seeds.append(title.current_seed())
	assert_bool(seeds.count(seeds[0]) < seeds.size()).is_true()


## The owner's report: the seed sat in the middle of the main menu with a paragraph under it.
## Nothing on this screen may mention it.
func test_the_title_screen_never_mentions_the_seed() -> void:
	var title := _title()
	assert_object(title.get_node_or_null("%SeedEdit")).is_null()
	assert_object(title.get_node_or_null("%SeedHint")).is_null()
	var labels: Array[Node] = []
	_collect_labels(title, labels)
	for node: Node in labels:
		var text := ""
		if node is Label:
			text = (node as Label).text
		elif node is Button:
			text = (node as Button).text
		(
			assert_str(text.to_lower())
			. override_failure_message("the title screen still says '%s'" % text)
			. not_contains("seed")
		)


static func _collect_labels(node: Node, out: Array[Node]) -> void:
	for child: Node in node.get_children():
		if child is Label or child is Button:
			out.append(child)
		_collect_labels(child, out)


## The caption names the live theme *and* the other two generation inputs, and promises
## nothing the generator cannot deliver: the music levers are sampled live (docs 5.1), so
## "same seed, same dungeon" - which is what this line used to say - is not true even on one
## desktop with one playlist.
## The caption (now under the Settings field) names the live theme *and* the other two
## generation inputs, and promises nothing the generator cannot deliver: the music levers are
## sampled live (docs 5.1), so "same seed, same dungeon" is not true even on one desktop.
func test_seed_caption_names_the_live_theme_and_the_other_inputs() -> void:
	var text := Title.seed_hint_text(Desktop.palette.name)
	assert_str(text).contains(Desktop.palette.name)
	assert_str(text.to_lower()).contains("wallpaper")
	assert_str(text.to_lower()).contains("music")
	(
		assert_bool(text.to_lower().contains("same dungeon"))
		. override_failure_message("the caption promises a dungeon the seed cannot pin")
		. is_false()
	)
	assert_str(Title.seed_hint_text("Gruvbox")).contains("Gruvbox")


func test_the_seed_tooltip_explains_what_a_seed_does_not_reproduce() -> void:
	assert_str(Title.SEED_TOOLTIP).contains("theme")
	assert_str(Title.SEED_TOOLTIP).contains("wallpaper")
	assert_str(Title.SEED_TOOLTIP).contains("blank")


func _save_run_on_floor(floor_number: int) -> void:
	var state := RunState.new()
	state.run_seed = 4242
	state.class_id = &"fighter"
	state.floor_index = maxi(0, floor_number - 1)
	assert_bool(SaveManager.save_run(state)).is_true()
	assert_bool(SaveManager.has_run()).is_true()


func _watch_new_run(title: Title) -> Array[int]:
	var seen: Array[int] = []
	title.new_run_pressed.connect(func(run_seed: int) -> void: seen.append(run_seed))
	return seen


## The gate must not get in the way of the common case: with nothing to lose, New Run is still
## one press and no panel appears. This is the property the confirm is most likely to break.
func test_new_run_without_a_saved_run_is_still_one_press() -> void:
	var title := _title()
	var seen := _watch_new_run(title)
	(title.get_node("%NewRun") as Button).pressed.emit()
	assert_bool(title.confirm_visible()).is_false()
	assert_int(seen.size()).is_equal(1)


## The finding: New Run used to delete a 20-35 minute run with no warning at all.
func test_new_run_asks_before_it_destroys_a_saved_run() -> void:
	_save_run_on_floor(3)
	var title := _title()
	var seen := _watch_new_run(title)
	(title.get_node("%NewRun") as Button).pressed.emit()
	(
		assert_bool(title.confirm_visible())
		. override_failure_message("New Run started without asking about the saved run")
		. is_true()
	)
	assert_array(seen).is_empty()
	assert_bool(SaveManager.has_run()).is_true()


## "Keep saved run" is the focused answer and it emits nothing, so nothing is deleted.
func test_keeping_the_saved_run_starts_no_run() -> void:
	_save_run_on_floor(2)
	var title := _title()
	var seen := _watch_new_run(title)
	(title.get_node("%NewRun") as Button).pressed.emit()
	var buttons := title.confirm_buttons()
	assert_bool(buttons[0].has_focus()).is_true()
	buttons[0].pressed.emit()
	assert_bool(title.confirm_visible()).is_false()
	assert_array(seen).is_empty()
	assert_bool(SaveManager.has_run()).is_true()


## ... and the danger-styled answer does start the run, with the seed that was typed.
func test_confirming_starts_the_run_with_the_typed_seed() -> void:
	_save_run_on_floor(5)
	GameState.settings[Title.SEED_SETTING] = "1234"
	var title := _title()
	var seen := _watch_new_run(title)
	(title.get_node("%NewRun") as Button).pressed.emit()
	var buttons := title.confirm_buttons()
	assert_str(buttons[1].theme_type_variation).is_equal("DangerButton")
	buttons[1].pressed.emit()
	assert_bool(title.confirm_visible()).is_false()
	assert_array(seen).is_equal([1234] as Array[int])


## A parked seed may not become a second, quieter way to destroy a saved run: New Run is the
## only path to a new run and it still asks first. (The old one-keystroke path was Enter in
## the seed field, which reached `new_run()` with no button press at all.)
func test_a_parked_seed_still_goes_through_the_overwrite_gate() -> void:
	_save_run_on_floor(4)
	GameState.settings[Title.SEED_SETTING] = "9"
	var title := _title()
	var seen := _watch_new_run(title)
	(title.get_node("%NewRun") as Button).pressed.emit()
	assert_bool(title.confirm_visible()).is_true()
	assert_array(seen).is_empty()
	assert_bool(SaveManager.has_run()).is_true()
	# ... and a refused run does not spend the seed.
	title.cancel_new_run()
	assert_str(str(GameState.settings[Title.SEED_SETTING])).is_equal("9")


## The warning names the floor, because "floor 7" is what says how much is at stake. The
## floor is read without going through `SaveManager.load_run()`, which would prime the resume
## counters and make the next run mis-count its floors.
func test_the_warning_names_the_floor_of_the_saved_run() -> void:
	_save_run_on_floor(7)
	assert_int(Title.saved_run_floor()).is_equal(7)
	assert_str(Title.overwrite_warning(7)).contains("floor 7")
	assert_str(Title.overwrite_warning(7).to_lower()).contains("deletes")
	# Unreadable floor, but still a save: the wording drops the number, never the warning.
	assert_str(Title.overwrite_warning(0).to_lower()).contains("deletes your saved run")
	SaveManager.delete_run()
	assert_int(Title.saved_run_floor()).is_equal(0)
