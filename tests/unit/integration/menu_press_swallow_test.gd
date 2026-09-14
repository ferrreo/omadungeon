## Found with a controller in hand: "when I press A to select something it also dodges". A is
## `ui_accept` and `dodge` at once (Space is the same pair on a keyboard). The board consumed
## the press, handed input back the same frame, and the Player rolled off the press it never
## saw as an event. These drive real device events through `Input`, the way the pad does, at a
## live run - a board over the player, the pause menu's Resume - and watch the character.
class_name MenuPressSwallowIntegrationTest
extends GdUnitTestSuite

const SEED := 20250914


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	_pad(JOY_BUTTON_A, false)
	_key(KEY_SPACE, false)
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	get_tree().paused = false
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


# ---------------------------------------------------------------- offer boards


func test_the_a_press_that_picks_a_card_does_not_dodge() -> void:
	var live := await _start()
	var chest := await _add_chest(Chest.Kind.GOLD)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	assert_bool(_ui().is_open()).is_true()
	var at := live.global_position

	_ui().select(0)
	_pad(JOY_BUTTON_A, true)
	await _ticks(4)
	# The press picked the card and the run is back...
	assert_bool(_ui().is_open()).is_false()
	assert_bool(live.input_enabled).is_true()
	assert_bool(get_tree().paused).is_false()
	# ...and the character did not roll off the same press.
	_assert_still(live, at)

	# A second press, after the release, is the dodge the player meant.
	_pad(JOY_BUTTON_A, false)
	await _ticks(3)
	_pad(JOY_BUTTON_A, true)
	await _ticks(3)
	_assert_dodged(live)


func test_the_space_press_that_picks_a_card_does_not_dodge() -> void:
	var live := await _start()
	var chest := await _add_chest(Chest.Kind.GOLD)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var at := live.global_position

	_ui().select(0)
	_key(KEY_SPACE, true)
	await _ticks(4)
	assert_bool(_ui().is_open()).is_false()
	assert_bool(live.input_enabled).is_true()
	_assert_still(live, at)

	_key(KEY_SPACE, false)
	await _ticks(3)
	_key(KEY_SPACE, true)
	await _ticks(3)
	_assert_dodged(live)


# ---------------------------------------------------------------- pause menu


## Resume is a Button, and a Button fires on the release of A, so the run comes back with
## nothing held; the guard is that whichever of the press and release hands the run back, the
## character stays put, and the next press is a real dodge.
func test_the_a_press_on_resume_does_not_dodge() -> void:
	var live := await _start()
	var menu := _pause_menu()
	menu.open()
	await _frames(2)
	assert_bool(get_tree().paused).is_true()
	(menu.get_node("%Resume") as Button).grab_focus()
	await _frames(1)
	var at := live.global_position

	_pad(JOY_BUTTON_A, true)
	await _ticks(2)
	_pad(JOY_BUTTON_A, false)
	await _ticks(4)
	assert_bool(menu.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_bool(live.is_dodging()).is_false()
	assert_bool(live.dodge_ready()).is_true()
	assert_vector(live.global_position).is_equal_approx(at, Vector2(0.5, 0.5))

	_pad(JOY_BUTTON_A, true)
	await _ticks(3)
	_assert_dodged(live)


# ---------------------------------------------------------------- helpers


func _assert_still(live: Player, at: Vector2) -> void:
	assert_bool(live.is_dodging()).is_false()
	assert_bool(live.dodge_ready()).is_true()
	assert_bool(live.input.is_swallowed(&"dodge")).is_true()
	assert_vector(live.global_position).is_equal_approx(at, Vector2(0.5, 0.5))


func _assert_dodged(live: Player) -> void:
	assert_bool(live.is_dodging()).is_true()
	assert_bool(live.dodge_ready()).is_false()


func _pad(button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _start(class_id: StringName = &"fighter") -> Player:
	assert_bool(RunManager.new_run(SEED, class_id)).is_true()
	await _frames(4)
	var live := RunManager.player()
	assert_object(live).is_not_null()
	live.health.invulnerable = true
	return live


func _ui() -> ChestUi:
	return (RunManager.game as Game).chest_ui


func _pause_menu() -> PauseMenu:
	return (RunManager.game as Game).pause_menu


func _add_chest(kind: Chest.Kind) -> Chest:
	var chest := Chest.new()
	chest.kind = kind
	RunManager.floor_root().add_child(chest)
	chest.global_position = RunManager.player().global_position
	await _frames(2)
	return chest


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _ticks(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame
