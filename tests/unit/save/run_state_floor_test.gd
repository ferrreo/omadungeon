## RunState's floor block (docs §12): what the player spent or opened on the floor they are
## standing on. Without it a resume rebuilds the floor from the seed and hands every altar,
## shrine, shop and chest back fresh while the cleared rooms stay cleared.
class_name RunStateFloorTest
extends GdUnitTestSuite


func _sample() -> RunState:
	var state := RunState.new()
	state.run_seed = 4242
	state.floor_index = 2
	state.cleared_room_ids = [1, 4]
	state.visited_room_ids = [0, 1, 4, 6]
	state.chest_room_ids = [1, 4, 5]
	state.looted_room_ids = [1, 5]
	state.used_altar_room_ids = [6]
	state.used_shrine_room_ids = [8]
	state.shops = [
		{
			"room_id": 7,
			"offers": [{"uid": 3, "base": "sword", "rarity": 1, "affixes": []}],
			"prices": [56],
			"rerolls": 2,
		}
	]
	state.floor_pickups = [
		{
			"room_id": 4,
			"x": 112.5,
			"y": -48.0,
			"item": {"uid": 9, "base": "sword", "rarity": 2, "affixes": []},
		}
	]
	state.stairs_unlocked = true
	state.rerolls_this_floor = 3
	state.free_reroll_used = true
	return state


func _json_round_trip(state: RunState) -> RunState:
	var parsed: Variant = JSON.parse_string(JSON.stringify(state.to_dict(), "\t"))
	assert_object(parsed).is_not_null()
	var restored := RunState.from_dict(parsed as Dictionary)
	assert_object(restored).is_not_null()
	return restored


## The boards the floor still owes the player travel with the floor block. Without them the
## save said *that* a pick was owed and never *on what*, so the resume rolled a new hand out of
## a loot stream already past the cards the player had been looking at - Save & Quit, Continue,
## a new board, for free and for ever, while the picker's Reroll button charges 25g for it.
func test_the_unanswered_offer_boards_survive_the_json_round_trip() -> void:
	var state := _sample()
	state.offer_boards = [
		{
			"source": 1,
			"room_id": 4,
			"kind": 3,
			"offers": [{"card": "stat", "stat": "might", "points": 2}],
			"curse": "",
			"rerolled": true,
		},
		{
			"source": 5,
			"room_id": -1,
			"kind": 2,
			"offers": [{"card": "ability", "id": "adrenaline", "tier": 1}],
			"curse": "curse_brittle",
			"rerolled": false,
		},
	]

	var restored := _json_round_trip(state)

	var chest := restored.offer_board_for(1, 4)
	assert_dict(chest).is_not_empty()
	assert_bool(bool(chest["rerolled"])).is_true()
	var cards := chest["offers"] as Array
	assert_int(cards.size()).is_equal(1)
	assert_str(str((cards[0] as Dictionary)["stat"])).is_equal("might")
	# The opening pick belongs to the run rather than to a room, and says so with room_id -1.
	var opening := restored.offer_board_for(5, -1)
	assert_str(str(opening["curse"])).is_equal("curse_brittle")
	# A board nobody recorded is not invented for the caller: an empty answer means "roll one".
	assert_dict(restored.offer_board_for(1, 9)).is_empty()
	assert_dict(restored.offer_board_for(2, 4)).is_empty()


## A save written before boards were persisted resumes as "no board was owed", which is the
## honest answer for one: its chest, if any, rolls a fresh board exactly as it used to.
func test_a_save_without_offer_boards_resumes_owing_none() -> void:
	var restored := RunState.from_dict(RunState.new().to_dict())
	assert_array(restored.offer_boards).is_empty()
	assert_dict(restored.offer_board_for(1, 0)).is_empty()


func test_the_floor_block_survives_the_json_round_trip() -> void:
	var restored := _json_round_trip(_sample())
	assert_array(restored.visited_room_ids).contains_exactly([0, 1, 4, 6])
	assert_array(restored.chest_room_ids).contains_exactly([1, 4, 5])
	assert_array(restored.looted_room_ids).contains_exactly([1, 5])
	assert_array(restored.used_altar_room_ids).contains_exactly([6])
	assert_array(restored.used_shrine_room_ids).contains_exactly([8])
	assert_bool(restored.stairs_unlocked).is_true()
	assert_int(restored.rerolls_this_floor).is_equal(3)
	assert_bool(restored.free_reroll_used).is_true()
	var shop := restored.shop_for_room(7)
	assert_dict(shop).is_not_empty()
	assert_int(int(shop["rerolls"])).is_equal(2)
	assert_int(int((shop["prices"] as Array)[0])).is_equal(56)
	assert_str(str(((shop["offers"] as Array)[0] as Dictionary)["base"])).is_equal("sword")
	assert_dict(restored.shop_for_room(99)).is_empty()
	# The `floor_state` property is the same block, and like `player` it hands out a copy.
	var block: Dictionary = restored.floor_state
	assert_dict(block).is_equal(restored.to_dict()["floor_state"])
	block["stairs_unlocked"] = false
	assert_bool(restored.stairs_unlocked).is_true()


func test_room_ids_come_back_as_ints_not_json_floats() -> void:
	var restored := _json_round_trip(_sample())
	for list: Array in [
		restored.visited_room_ids,
		restored.chest_room_ids,
		restored.looted_room_ids,
		restored.used_altar_room_ids,
		restored.used_shrine_room_ids
	]:
		for id: Variant in list:
			assert_bool(id is int).is_true()


func test_potion_capacity_is_part_of_the_player_block() -> void:
	# A key RunState does not know about is dropped by `set_player_dict`, and the player then
	# falls back to the class default: this is the one that used to clamp the purse to one.
	var state := RunState.new()
	state.player = {"potion": 4, "max_potions": 4, "gold": 12}
	assert_int(state.max_potions).is_equal(4)
	assert_int(state.potion).is_equal(4)
	var restored := _json_round_trip(state)
	assert_int(restored.max_potions).is_equal(4)
	assert_int(int(restored.player["max_potions"])).is_equal(4)


func test_an_unknown_potion_capacity_is_left_out_rather_than_written_as_zero() -> void:
	# A pre-v2 save has no capacity. Writing 0 would be worse than writing nothing: the
	# player clamps `potions` to `max_potions`, so the resume would take the potions away.
	var state := RunState.new()
	state.player = {"potion": 1, "gold": 3}
	assert_int(state.max_potions).is_equal(0)
	assert_bool((state.player as Dictionary).has("max_potions")).is_false()


func test_a_version_1_save_resumes_with_an_untouched_floor() -> void:
	# Old runs must still load: every floor field defaults to "nothing spent here yet".
	var legacy := {
		"version": 1,
		"seed": "99",
		"floor_index": 1,
		"cleared_room_ids": [2],
		"player": {"gold": 40, "potion": 1},
	}
	var migrated := RunState.migrate(legacy)
	assert_int(int(migrated["version"])).is_equal(RunState.VERSION)
	assert_bool(RunState.is_valid(migrated)).is_true()
	var state := RunState.from_dict(legacy)
	assert_object(state).is_not_null()
	assert_int(state.gold).is_equal(40)
	assert_array(state.cleared_room_ids).contains_exactly([2])
	assert_array(state.chest_room_ids).is_empty()
	assert_array(state.used_altar_room_ids).is_empty()
	assert_bool(state.stairs_unlocked).is_false()
	assert_int(state.max_potions).is_equal(0)


func test_wrong_typed_floor_blocks_are_tolerated() -> void:
	var state := RunState.from_dict({"version": 1, "seed": "3", "floor_state": "nope"})
	assert_object(state).is_not_null()
	assert_array(state.looted_room_ids).is_empty()
	assert_array(state.shops).is_empty()
	var odd := (
		RunState
		. from_dict(
			{
				"version": 2,
				"seed": "3",
				"floor_state":
				{"chest_room_ids": ["2", 3.0], "shops": [7, {"room_id": 1}], "stairs_unlocked": 1},
			}
		)
	)
	assert_array(odd.chest_room_ids).contains_exactly([2, 3])
	assert_int(odd.shops.size()).is_equal(1)
	assert_bool(odd.stairs_unlocked).is_true()


func test_the_floor_block_is_a_deep_copy() -> void:
	var state := _sample()
	var data := state.to_dict()
	(data["floor_state"]["shops"] as Array)[0]["rerolls"] = 99
	(data["floor_state"]["looted_room_ids"] as Array).append(42)
	assert_int(int(state.shops[0]["rerolls"])).is_equal(2)
	assert_array(state.looted_room_ids).has_size(2)


## Items lying on the floor are part of the floor block, because they exist nowhere else: a
## resume rebuilds the floor from the seed, the room stays cleared, and a drop the save does
## not carry is gone for good - an elite's guaranteed Rare-or-better included.
func test_uncollected_floor_drops_survive_the_json_round_trip() -> void:
	var restored := _json_round_trip(_sample())
	assert_int(restored.floor_pickups.size()).is_equal(1)
	var drop := restored.floor_pickups[0]
	assert_int(int(drop["room_id"])).is_equal(4)
	assert_float(float(drop["x"])).is_equal_approx(112.5, 0.01)
	assert_float(float(drop["y"])).is_equal_approx(-48.0, 0.01)
	assert_str(str((drop["item"] as Dictionary)["base"])).is_equal("sword")
	assert_int(int((drop["item"] as Dictionary)["rarity"])).is_equal(2)


## A save written before the field existed says nothing about drops, and "nothing" is the
## honest answer for it: it must load rather than be rejected as unreadable.
func test_a_save_without_the_drop_list_loads_as_an_empty_floor() -> void:
	var raw := _sample().to_dict()
	(raw["floor_state"] as Dictionary).erase("floor_pickups")
	var restored := RunState.from_dict(raw)
	assert_object(restored).is_not_null()
	assert_array(restored.floor_pickups).is_empty()
	# ... and the rest of the floor block is untouched by the omission.
	assert_array(restored.looted_room_ids).contains_exactly([1, 5])
	assert_bool(restored.stairs_unlocked).is_true()


## Like `player` and the rest of `floor_state`, the drop list is handed out as a copy.
func test_the_drop_list_cannot_be_edited_through_the_floor_state_snapshot() -> void:
	var state := _sample()
	var block: Dictionary = state.floor_state
	(block["floor_pickups"] as Array).clear()
	assert_int(state.floor_pickups.size()).is_equal(1)


## The anti-farm half of the floor block, added this round. A resume rebuilds every prop whole
## and re-arms every mimic chest, and respawns every room that is not fully cleared — while
## the gold those things already paid stays banked. These three lists are what stops the same
## barrel, the same decoy and the same pack being sold to the player twice.
func test_the_anti_farm_lists_survive_the_json_round_trip() -> void:
	var state := _sample()
	state.broken_prop_tiles = [Vector2i(12, 2), Vector2i(-3, 40)]
	state.revealed_mimic_tiles = [Vector2i(9, 9)]
	state.defeated_spawns = [{"room_id": 4, "enemy_ids": ["mime", "mime", "gremlin"]}]
	state.chest_offer_room_id = 5

	var back := _json_round_trip(state)
	assert_array(back.broken_prop_tiles).is_equal([Vector2i(12, 2), Vector2i(-3, 40)])
	assert_array(back.revealed_mimic_tiles).is_equal([Vector2i(9, 9)])
	assert_int(back.defeated_spawns.size()).is_equal(1)
	assert_int(int(back.defeated_spawns[0]["room_id"])).is_equal(4)
	assert_array(back.defeated_spawns[0]["enemy_ids"]).is_equal(["mime", "mime", "gremlin"])
	assert_int(back.chest_offer_room_id).is_equal(5)


## A save written before these fields existed has to resume as "nothing broken, nothing sprung,
## nothing half-fought, no offer owed" rather than fail to load — the same additive rule every
## other field of this block follows. -1 is the honest "no chest offer", not room 0.
func test_a_save_without_the_anti_farm_lists_resumes_as_an_untouched_floor() -> void:
	var state := RunState.new()
	state.set_floor_state_dict({"visited_room_ids": [2]})
	assert_array(state.broken_prop_tiles).is_empty()
	assert_array(state.revealed_mimic_tiles).is_empty()
	assert_array(state.defeated_spawns).is_empty()
	assert_int(state.chest_offer_room_id).is_equal(-1)
	# A half-pair in the flat tile list is dropped, not guessed at.
	state.set_floor_state_dict({"broken_prop_tiles": [4, 5, 6]})
	assert_array(state.broken_prop_tiles).is_equal([Vector2i(4, 5)])


## `PackLedger` is what reads `defeated_spawns` back: it has to survive the same trip and come
## out as the same multiset, or a pack of three the player killed two of comes back whole.
func test_the_pack_ledger_round_trips_through_the_floor_block() -> void:
	var ledger := PackLedger.new()
	ledger.record(4, &"mime")
	ledger.record(4, &"mime")
	ledger.record(2, &"gremlin")
	var state := _sample()
	state.defeated_spawns = ledger.to_entries()

	var back := PackLedger.from_entries(_json_round_trip(state).defeated_spawns)
	assert_array(back.killed_in(4)).is_equal(["mime", "mime"])
	assert_array(back.killed_in(2)).is_equal(["gremlin"])
	assert_array(back.killed_in(9)).is_empty()
	back.forget(4)
	assert_array(back.killed_in(4)).is_empty()
	back.clear()
	assert_bool(back.is_empty()).is_true()
