## The loot boards, driven the way the owner drives them: a physical pad, inside a real run.
##
## Why this is a *run* and not a `ChestUi` on its own. Every existing chest suite either pushes
## an `InputEventAction` straight at `_unhandled_input` or stands one board up in an otherwise
## empty tree, and both were green through the whole of the owner's report ("the controller is
## not working to move selection in the loot menus"). The defect was never in the board: it was
## another screen in the same overlay claiming the directional actions before the board was
## served (see `LoadoutScreen.takes_input`). Nothing that leaves the rest of the game out of the
## tree can see that, so the run is started, a chest is opened in it, and the pad is pushed.
##
## Both devices are sent as real devices through `Input.parse_input_event`: an
## `InputEventJoypadButton` for the d-pad and an `InputEventJoypadMotion` for the left stick,
## which reaches the board as d-pad buttons by way of `UiStickNav`.
class_name LootPadNavTest
extends GdUnitTestSuite

const SEED := 20250913
## Price the test shop puts on its one ring; the player is given far more than this.
const SHOP_PRICE := 40

var _device: int = 0


func before_test() -> void:
	_device = int(InputGlyphs.current_device())
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	# The docs 2 starting-passive board would sit over every chest opened here.
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _centre_stick()
	await _frames(2)
	get_tree().paused = false
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true
	InputGlyphs.set_device(_device as InputGlyphs.Device)
	EventBus.input_device_changed.emit(_device)


# ------------------------------------------------------------------ device plumbing


## One press-and-release of a pad button, through the real InputMap and the real viewport.
func _pad_press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


## One flick of the left stick: past the press threshold, ticked so `UiStickNav` sees it, then
## back to centre and ticked again so the next flick counts as a fresh one.
func _stick_flick(axis: JoyAxis, value: float) -> void:
	for reading: float in [value, 0.0]:
		await _feed_axis(axis, reading)


func _centre_stick() -> void:
	await _feed_axis(JOY_AXIS_LEFT_X, 0.0)
	await _feed_axis(JOY_AXIS_LEFT_Y, 0.0)


func _feed_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(2)


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


# ------------------------------------------------------------------ run plumbing


func _ui() -> ChestUi:
	return (RunManager.game as Game).chest_ui


func _start() -> Player:
	assert_bool(RunManager.new_run(SEED, &"fighter")).is_true()
	await _frames(4)
	var live := RunManager.player()
	assert_object(live).is_not_null()
	live.health.invulnerable = true
	return live


## A run with an item chest open on it: the board the owner meets first.
func _item_board() -> ChestUi:
	var live := await _start()
	var chest := Chest.new()
	chest.kind = Chest.Kind.ITEM
	RunManager.floor_root().add_child(chest)
	chest.global_position = live.global_position
	await _frames(2)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	assert_bool(ui.is_open()).is_true()
	assert_int(ui.card_count()).is_greater(1)
	assert_int(ui.selected_index()).is_equal(0)
	return ui


## A run sitting on the "which ring goes?" trade view, reached the way a player reaches it:
## both ring slots worn, a ring bought off a counter, the offer taken.
func _swap_board() -> ChestUi:
	var live := await _start()
	var gear := live.equipment as Equipment
	for i: int in 2:
		gear.equip(_make_ring(i), live.stats)
	live.add_gold(500)
	var shop := Shop.new()
	RunManager.floor_root().add_child(shop)
	shop.global_position = live.global_position
	shop.stock([_make_ring(2)], SHOP_PRICE)
	await _frames(2)
	assert_bool(shop.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	ui.select(0)
	ui.activate()
	await _frames(2)
	assert_int(ui.selected_row()).is_equal(ChestUi.Row.REPLACE)
	assert_str(ui.compare_view().footer()).is_equal("Slot 1 of 2")
	return ui


## A ring rolled from the real registry, with a salt so the three in a case are distinct.
func _make_ring(salt: int) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + salt
	var slots: Array[int] = [int(ItemBase.Slot.RING)]
	var ring := ItemGenerator.generate(RunManager.item_registry, 1, rng, 0.0, slots)
	assert_object(ring).is_not_null()
	return ring


# ------------------------------------------------------------------ the boards


func test_the_dpad_moves_the_selection_on_the_item_board() -> void:
	var ui := await _item_board()
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	(
		assert_int(ui.selected_index())
		. override_failure_message("the d-pad did not move the item board's selection")
		. is_equal(1)
	)


func test_the_left_stick_moves_the_selection_on_the_item_board() -> void:
	var ui := await _item_board()
	await _stick_flick(JOY_AXIS_LEFT_X, 1.0)
	(
		assert_int(ui.selected_index())
		. override_failure_message("the left stick did not move the item board's selection")
		. is_equal(1)
	)


func test_the_dpad_moves_the_selection_on_the_swap_board() -> void:
	var ui := await _swap_board()
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	(
		assert_str(ui.compare_view().footer())
		. override_failure_message("the d-pad did not move the swap board's selection")
		. is_equal("Slot 2 of 2")
	)


func test_the_left_stick_moves_the_selection_on_the_swap_board() -> void:
	var ui := await _swap_board()
	await _stick_flick(JOY_AXIS_LEFT_X, 1.0)
	(
		assert_str(ui.compare_view().footer())
		. override_failure_message("the left stick did not move the swap board's selection")
		. is_equal("Slot 2 of 2")
	)


## The root cause, named directly: the pause menu's Build tab is a second `LoadoutScreen`, it
## is `PROCESS_MODE_ALWAYS` like every screen, and it used to answer - and consume - the
## directional actions while the pause menu was shut, because its only guard was
## `standalone and not _is_open` and it is not standalone.
func test_a_hidden_build_tab_does_not_claim_the_directional_actions() -> void:
	var live := await _start()
	var menu := (RunManager.game as Game).pause_menu
	var embedded := menu.loadout_screen()
	assert_object(embedded).is_not_null()
	assert_bool(embedded.standalone).is_false()
	embedded.bind(live)
	assert_bool(menu.is_open()).is_false()
	(
		assert_bool(embedded.takes_input())
		. override_failure_message("the shut pause menu's Build tab still takes directional input")
		. is_false()
	)
	# ... and the in-run overlay copy is just as quiet while it is closed.
	var overlay := (RunManager.game as Game).loadout
	assert_bool(overlay.standalone).is_true()
	assert_bool(overlay.is_open()).is_false()
	assert_bool(overlay.takes_input()).is_false()
