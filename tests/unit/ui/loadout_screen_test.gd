## The build screen (owner report 8, round 5: "there seems to be no way to compare or see what
## your current passives and abilities are"). One page answers "what do I have right now":
## the class, two actives, two passives, the innate, the weapon skill, every gear slot and the
## stat sheet with its sources - reachable from the pause menu and from the Tab key.
class_name LoadoutScreenTest
extends GdUnitTestSuite

const SCENE := "res://src/ui/loadout_screen.tscn"


func after_test() -> void:
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame


func _screen(standalone: bool = true) -> LoadoutScreen:
	var screen: LoadoutScreen = auto_free((load(SCENE) as PackedScene).instantiate())
	screen.standalone = standalone
	add_child(screen)
	return screen


func _player() -> UiFakes.FakePlayer:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	return player


func _press(screen: LoadoutScreen, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	screen._unhandled_input(event)


func test_the_page_lists_two_actives_two_passives_the_innate_and_the_skill() -> void:
	var screen := _screen()
	var player := _player()
	screen.bind(player)
	screen.open()
	var text := "\n".join(screen.texts())
	assert_str(text).contains("Fireball")
	assert_str(text).contains("Frost Nova")
	assert_str(text).contains("Thorns")
	assert_str(text).contains("Vampiric")
	assert_str(text).contains("Second Wind")
	assert_str(text).contains(LoadoutScreen.SKILL_CAPTION)
	assert_str(text).contains("Lunge")
	for caption: String in LoadoutScreen.ACTIVE_CAPTIONS + LoadoutScreen.PASSIVE_CAPTIONS:
		assert_str(text).contains(caption)
	# Cooldowns and descriptions, in full.
	assert_str(text).contains("6s cooldown")
	assert_str(text).contains(player.ability_slots.actives[0].describe())
	assert_str(text).contains(player.ability_slots.passives[1].describe())
	# And the class.
	assert_str(text).contains(player.class_def.display_name)
	assert_int((screen.model["actives"] as Array).size()).is_equal(AbilitySlots.ACTIVE_COUNT)
	assert_int((screen.model["passives"] as Array).size()).is_equal(AbilitySlots.PASSIVE_COUNT)


func test_every_gear_slot_is_a_row_with_the_items_own_lines() -> void:
	var screen := _screen()
	var player := _player()
	screen.bind(player)
	screen.open()
	var text := "\n".join(screen.texts())
	var rows: Array[Dictionary] = screen.model["equipment"]
	assert_int(rows.size()).is_equal(5)
	var worn := player.equipment.slots["weapon"] as ItemInstance
	assert_str(text).contains(worn.display_name)
	# The same lines the compare screen prints for the same item.
	for line: String in ItemCard.item_lines(worn):
		assert_str(text).contains(line)
	assert_str(text).contains(LoadoutScreen.EMPTY_TEXT)


## The sheet carries every primary and every derived number with where it comes from, and
## its numbers are the player's live `Stats` - the same object the compare screen reads.
func test_the_stat_sheet_names_its_sources() -> void:
	var screen := _screen()
	var player := _player()
	player.stats.add_flat(&"might", &"item:1", 2.0)
	screen.bind(player)
	screen.open()
	var rows: Array[Dictionary] = screen.model["stats"]
	var by_label: Dictionary = {}
	for row: Dictionary in rows:
		by_label[str(row["label"])] = row
	for stat: StringName in Stats.PRIMARY:
		assert_bool(by_label.has(String(stat).capitalize())).is_true()
	for entry: Dictionary in LoadoutModel.DERIVED:
		assert_bool(by_label.has(str(entry["label"]))).is_true()
	var might: Dictionary = by_label["Might"]
	assert_str(str(might["value"])).is_equal(str(player.stats.primary(&"might")))
	assert_str(str(might["sources"])).contains("%s 6" % LoadoutModel.CLASS_SOURCE)
	assert_str(str(might["sources"])).contains("%s +2" % LoadoutModel.OTHER_SOURCE)
	var melee: Dictionary = by_label["Melee damage"]
	assert_str(str(melee["sources"])).contains("Might")
	assert_str(str(melee["value"])).starts_with("+")


## Opened from the run it pauses the tree, and Escape or the same key closes it again.
func test_opening_pauses_and_the_map_key_closes() -> void:
	var screen := _screen()
	screen.bind(_player())
	screen.open()
	assert_bool(screen.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(screen.visible).is_true()
	_press(screen, &"map")
	assert_bool(screen.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	screen.open()
	_press(screen, &"ui_cancel")
	assert_bool(screen.is_open()).is_false()


## Left and right pick a column and up/down scroll it, so the whole sheet is reachable on a
## pad; and the heading of the column the pad is on is the bright one.
func test_a_pad_reaches_both_columns_and_scrolls_them() -> void:
	var screen := _screen()
	screen.bind(_player())
	screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(screen.column).is_equal(0)
	var before := screen.scroll_by(0)
	_press(screen, &"ui_down")
	assert_int(screen.scroll_by(0)).is_greater(before)
	_press(screen, &"ui_right")
	assert_int(screen.column).is_equal(1)
	var sheet_before := screen.scroll_by(0)
	_press(screen, &"ui_down")
	assert_int(screen.scroll_by(0)).is_greater(sheet_before)
	_press(screen, &"ui_right")
	assert_int(screen.column).is_equal(0)


## Embedded in the pause menu it draws no frame, dim, header or footer of its own.
func test_embedded_in_the_pause_menu_it_is_a_page_not_a_dialog() -> void:
	var screen := _screen(false)
	screen.bind(_player())
	assert_bool((screen.get_node("%Dim") as Control).visible).is_false()
	assert_bool((screen.get_node("%Footer") as Control).visible).is_false()
	assert_bool((screen.get_node("%Header") as Control).visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_str("\n".join(screen.texts())).contains("Fireball")


## The seed is a power-user handle, and this is the one screen that prints it.
func test_the_seed_is_tucked_into_the_footer() -> void:
	var screen := _screen()
	screen.bind(_player())
	screen.set_context("Floor 3 - Crypt", 20240911)
	screen.open()
	var text := "\n".join(screen.texts())
	assert_str(text).contains(LoadoutScreen.SEED_LINE % 20240911)
	assert_str(text).contains("Floor 3 - Crypt")
