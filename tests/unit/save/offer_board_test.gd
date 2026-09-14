## The identity of an offer board: which interactable owes it, and what it costs to write one
## down (`FloorRestore.board_for` / `record_board` / `drop_board` / `offer_boards_to_dicts`).
##
## A board that has been rolled belongs to the thing that rolled it until it is answered. Before
## this, only the *fact* that a pick was owed reached `run.json`; the cards were rolled again on
## resume, against a loot stream the save had already advanced past them, so leaving an altar or
## closing the window on a picker dealt a new hand for free, without limit, while the picker's
## own Reroll button charges 25g and grows with every use (docs §8, §12).
class_name OfferBoardTest
extends GdUnitTestSuite

## `RunManager.OfferSource` values, written out so this suite does not need a live run.
const CHEST := 1
const ALTAR := 2
const STARTING_PASSIVE := 5

var _items: ItemRegistry
var _abilities: AbilityRegistry


func before_test() -> void:
	_items = ItemRegistry.load_default()
	_abilities = AbilityRegistry.load_default()


# ---------------------------------------------------------------- the cards


func test_every_card_a_board_can_hold_round_trips_through_json() -> void:
	var ability := _abilities.instance(_first_ability_id())
	ability.tier = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var item := ItemGenerator.generate(_items, 2, rng, 0.0)
	assert_object(item).is_not_null()
	var board: Array = [{"stat": &"might", "points": 2}, 47, ability, item]

	var written := FloorRestore.offers_to_dicts(board)
	assert_int(written.size()).is_equal(4)
	var parsed: Variant = JSON.parse_string(JSON.stringify(written))
	var back := FloorRestore.offers_from_dicts(parsed as Array, _items, _abilities)

	assert_int(back.size()).is_equal(4)
	var stat := back[0] as Dictionary
	assert_str(String(stat["stat"])).is_equal("might")
	assert_int(int(stat["points"])).is_equal(2)
	assert_int(int(back[1])).is_equal(47)
	# An ability card carries the tier it was offered at: an owned ability is offered as the
	# upgrade, and restoring it at tier 1 would quietly change what the card gives.
	assert_str(String((back[2] as Ability).id)).is_equal(String(ability.id))
	assert_int((back[2] as Ability).tier).is_equal(2)
	assert_str(String((back[3] as ItemInstance).base.id)).is_equal(String(item.base.id))
	assert_int((back[3] as ItemInstance).uid).is_equal(item.uid)


## All or nothing: a board is the choice the player was given, and three cards restored as two
## is a different choice. A shrine's menu card is the shape that is deliberately not written
## down - a shrine's options are carved into the shrine and rebuilt from it, never rolled.
func test_a_board_holding_a_card_that_cannot_be_written_down_is_not_written_at_all() -> void:
	var shrine_card := {"stat": &"might", "points": 2, "cost_kind": &"hp", "cost": 25}
	(
		assert_array(FloorRestore.offers_to_dicts([{"stat": &"might", "points": 1}, shrine_card]))
		. is_empty()
	)
	assert_array(FloorRestore.offers_to_dicts([{"stat": &"might", "points": 1}])).is_not_empty()


func test_a_board_this_build_can_no_longer_rebuild_is_dropped_rather_than_restored_short() -> void:
	var raw: Array = [
		{"card": "stat", "stat": "might", "points": 1},
		{"card": "ability", "id": "an_ability_that_was_deleted", "tier": 1},
	]
	assert_array(FloorRestore.offers_from_dicts(raw, _items, _abilities)).is_empty()
	assert_array(FloorRestore.offers_from_dicts([raw[0]], _items, _abilities)).is_not_empty()


# ---------------------------------------------------------------- whose board it is


func test_two_altars_in_different_rooms_do_not_share_a_board() -> void:
	var first := _altar_in_room(4)
	var second := _altar_in_room(7)
	var boards: Array[Dictionary] = []
	FloorRestore.record_board(boards, ALTAR, first, 2, [11], null, false)
	FloorRestore.record_board(boards, ALTAR, second, 2, [22], null, false)

	assert_int(boards.size()).is_equal(2)
	assert_array(FloorRestore.board_for(boards, ALTAR, first)["offers"] as Array).is_equal([11])
	assert_array(FloorRestore.board_for(boards, ALTAR, second)["offers"] as Array).is_equal([22])
	# ... and a chest standing in the first altar's room is not handed the altar's cards.
	assert_dict(FloorRestore.board_for(boards, CHEST, first)).is_empty()


## A reroll is a new board for the same interactable, not a second board beside it, and an
## answered board is not owed a second time.
func test_a_reroll_replaces_the_board_and_answering_it_drops_it() -> void:
	var altar := _altar_in_room(4)
	var boards: Array[Dictionary] = []
	FloorRestore.record_board(boards, ALTAR, altar, 2, [11], null, false)
	FloorRestore.record_board(boards, ALTAR, altar, 2, [22], null, true)
	assert_int(boards.size()).is_equal(1)
	assert_bool(bool(FloorRestore.board_for(boards, ALTAR, altar)["rerolled"])).is_true()

	FloorRestore.drop_board(boards, ALTAR, altar)
	assert_array(boards).is_empty()
	assert_dict(FloorRestore.board_for(boards, ALTAR, altar)).is_empty()


## An empty roll is not a board: there is nothing to come back to, and recording one would make
## the picker re-open on a row of no cards.
func test_an_empty_roll_records_no_board() -> void:
	var boards: Array[Dictionary] = []
	FloorRestore.record_board(boards, ALTAR, _altar_in_room(4), 2, [], null, false)
	assert_array(boards).is_empty()


## Only a board that can be addressed again after a rebuilt floor is saved. The room is the
## address; a node outside a room (a bare Altar in a test) could never be found again, and the
## opening pick belongs to the run rather than to any room, which is what `room_id` -1 means.
func test_only_boards_a_resume_could_find_again_reach_the_save() -> void:
	var boards: Array[Dictionary] = []
	FloorRestore.record_board(boards, ALTAR, _altar_in_room(4), 2, [11], null, false)
	FloorRestore.record_board(boards, ALTAR, auto_free(Altar.new()), 2, [22], null, false)
	FloorRestore.record_board(boards, STARTING_PASSIVE, null, 2, [33], null, false)

	var saved := FloorRestore.offer_boards_to_dicts(boards, STARTING_PASSIVE)
	assert_int(saved.size()).is_equal(2)
	var rooms: Array[int] = []
	for entry: Dictionary in saved:
		rooms.append(int(entry["room_id"]))
	assert_array(rooms).contains_exactly_in_any_order([4, -1])


## The gold card is an int, which JSON hands back as a float; a board that came back as
## `[47.0]` would be granted as gold 47 but compared as a different board.
func test_a_saved_board_comes_back_as_the_same_board_through_run_state() -> void:
	var boards: Array[Dictionary] = []
	FloorRestore.record_board(boards, CHEST, _altar_in_room(4), 3, [47], null, true)
	var state := RunState.new()
	state.run_seed = 99
	state.offer_boards = FloorRestore.offer_boards_to_dicts(boards, STARTING_PASSIVE)
	var parsed: Variant = JSON.parse_string(JSON.stringify(state.to_dict()))
	var restored := RunState.from_dict(parsed as Dictionary)

	var back := FloorRestore.offer_boards_from(restored, _items, _abilities)
	assert_int(back.size()).is_equal(1)
	assert_int(int(back[0]["room_id"])).is_equal(4)
	assert_bool(bool(back[0]["rerolled"])).is_true()
	assert_array(back[0]["offers"] as Array).is_equal([47])


# ---------------------------------------------------------------- helpers


## An Altar parented to a RoomNode with `id`, which is how a floor builds one and therefore how
## `FloorRestore.room_id_of()` reads its address.
func _altar_in_room(id: int) -> Altar:
	var room := auto_free(RoomNode.new()) as RoomNode
	room.id = id
	var altar := Altar.new()
	room.add_child(altar)
	return altar


func _first_ability_id() -> StringName:
	for ability: Ability in _abilities.abilities:
		if ability != null and not (ability is CursePassive):
			return ability.id
	return &""
