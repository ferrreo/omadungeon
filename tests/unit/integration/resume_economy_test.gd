## The economics of a resume, end to end through the real API (docs §12).
##
## A resume can get a reward wrong in two directions, and this round both were open at once:
##
##  * it can **destroy** what the player earned — a chest marks its lid open the instant the
##    player interacts, and the autosave the room clear queued half a second earlier lands
##    while the offer is still on screen (the tree is paused, `SaveManager` is
##    `PROCESS_MODE_ALWAYS`), so a session that ended there resumed to an opened, empty chest;
##  * it can **pay twice** for what the player already banked — a rebuilt floor hands back
##    every breakable prop whole and respawns every room that is not fully cleared, while the
##    gold and drops from the first pass stay banked. Clear most of a pack, quit, continue,
##    repeat: an unbounded loot loop, and the deterministic prop gold made it exact to the coin.
##
## Every case here holds *both* edges down: the farm is closed, and an honest player who simply
## quits and comes back loses nothing they had not already spent.
class_name ResumeEconomyIntegrationTest
extends GdUnitTestSuite

## Same floor-1 seed the rest of the resume suite walks: a Shop, an Altar, several combat
## rooms and a floor full of breakable props.
const SEED := 987654
const CLASS_ID := &"fighter"
## `RunManager.OfferSource` values, as `RunState.offer_board_for()` takes them.
const _CHEST := int(RunManager.OfferSource.CHEST)
const _ALTAR := int(RunManager.OfferSource.ALTAR)

var _probe := EventBusProbe.new()
var _gold_seen: int = 0


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	# The docs §2 passive pick has its own suite; it would open on top of every resume here.
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()
	_gold_seen = 0
	_probe.watch(
		EventBus.spawn_pickup,
		func(kind: StringName, _pos: Vector2, amount: int) -> void:
			if kind == &"gold":
				_gold_seen += amount
	)


func after_test() -> void:
	_probe.release()
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


# ---------------------------------------------------------------- the unanswered offer


## The reward-destroying half. The save written while the picker is up must say "this chest
## still owes a pick", and the resume must hand that pick back.
##
## The write under test is the *autosave*, asserted straight off the disk: that is the one an
## abnormal exit leaves behind, and the pause menu is modal-blocked so Save & Quit cannot
## normally reach this state at all. `save_and_quit()` is used afterwards only to end the
## session — it writes the same snapshot `build_run_state()` just put on disk.
func test_a_chest_saved_with_its_offer_unanswered_still_owes_the_player_a_pick() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var room_id := room.id
	await _clear(room, live)
	assert_object(room.chest).is_not_null()
	assert_bool(room.chest.interact(live)).is_true()
	await _frames(4)
	var view := RunManager.game as Game
	assert_bool(view.chest_ui.is_open()).is_true()
	assert_bool(room.chest.is_opened).is_true()
	(
		assert_bool(room.chest.reward_taken)
		. override_failure_message("the chest was spent before the player answered the offer")
		. is_false()
	)

	SaveManager.flush_autosave()
	var on_disk := SaveManager.load_run()
	assert_object(on_disk).is_not_null()
	(
		assert_bool(on_disk.looted_room_ids.has(room_id))
		. override_failure_message("run.json recorded an opened, empty chest")
		. is_false()
	)
	assert_int(on_disk.chest_offer_room_id).is_equal(room_id)

	var before := _signature(live)
	await _save_and_resume()

	var resumed := RunManager.floor_root().get_room(room_id)
	assert_object(resumed.chest).is_not_null()
	var resumed_view := RunManager.game as Game
	(
		assert_bool(resumed_view.chest_ui.is_open())
		. override_failure_message("the resume did not hand the pick back")
		. is_true()
	)
	assert_int(resumed_view.chest_ui.card_count()).is_greater(0)
	await _answer(resumed_view)
	assert_bool(resumed.chest.reward_taken).is_true()
	(
		assert_str(_signature(RunManager.player()))
		. override_failure_message("the resumed pick granted nothing")
		. is_not_equal(before)
	)


## The direction the fix must not break, and the one a careless "never mark it spent" would:
## a chest the player *did* answer stays answered. It comes back opened, the picker does not
## re-open on top of the run, and the loadout does not grow a second time.
func test_a_chest_the_player_answered_is_not_offered_again() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var room_id := room.id
	await _clear(room, live)
	assert_bool(room.chest.interact(live)).is_true()
	await _frames(4)
	await _answer(RunManager.game as Game)
	assert_bool(room.chest.reward_taken).is_true()
	var after_pick := _signature(live)

	await _save_and_resume()

	var view := RunManager.game as Game
	assert_bool(view.chest_ui.is_open()).is_false()
	var resumed := RunManager.floor_root().get_room(room_id)
	assert_bool(resumed.chest == null or resumed.chest.reward_taken).is_true()
	assert_bool(resumed.chest == null or not resumed.chest.can_interact()).is_true()
	(
		assert_str(_signature(RunManager.player()))
		. override_failure_message("the chest paid a second time across the resume")
		. is_equal(after_pick)
	)


# ------------------------------------------------- the board an unanswered offer was left on


## The half this round opened. Last round made the *pick* survive an interrupted offer; the
## board it was made on was still rolled fresh on the way back, against a loot stream the save
## had already advanced past the cards the player saw. So the supported pause-menu route —
## Save & Quit, Continue — dealt three new cards, free and without limit, on a board whose own
## Reroll button charges 25g and multiplies that price by 1.5 per use (docs §8). A board that
## has been rolled belongs to its interactable until it is answered.
##
## Both edges again: the same three cards come back however often the session ends, and they
## are still worth taking when the player finally answers them.
func test_a_chest_offer_resumes_as_the_same_cards_however_often_the_session_ends() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var room_id := room.id
	await _clear(room, live)
	assert_bool(room.chest.interact(live)).is_true()
	await _frames(4)
	var board := _board()
	assert_array(board).is_not_empty()

	# What a window closed on the picker leaves on disk, read back as cards.
	SaveManager.flush_autosave()
	(
		assert_array(_saved_board(SaveManager.load_run(), _CHEST, room_id))
		. override_failure_message("run.json recorded that a pick was owed but not on what")
		. is_equal(board)
	)

	for cycle in range(3):
		await _save_and_resume()
		(
			assert_array(_board())
			. override_failure_message(
				"Continue number %d dealt a new board for free" % (cycle + 1)
			)
			. is_equal(board)
		)

	# Still the reward the round before this one saved: answering it grants something, and the
	# save stops owing a board once it has been answered.
	var before := _signature(RunManager.player())
	await _answer(RunManager.game as Game)
	assert_str(_signature(RunManager.player())).is_not_equal(before)
	assert_bool(RunManager.floor_root().get_room(room_id).chest.reward_taken).is_true()
	assert_bool(SaveManager.save_run(RunManager.build_run_state())).is_true()
	assert_array(_saved_board(SaveManager.load_run(), _CHEST, room_id)).is_empty()


## The altar route, which is the one a player can walk into three button presses deep: leaving
## an altar keeps the altar (docs §5.1), so praying at it again must show the cards it was left
## on. That held within a session and died on the first save — `run.json` carried no altar board
## at all — which turned Leave -> Esc -> Save and Quit -> Continue -> Pray into the free reroll.
func test_an_altar_left_and_resumed_shows_the_board_it_was_left_on() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var altar := _first_altar()
	var room_id := FloorRestore.room_id_of(altar)
	assert_int(room_id).is_greater_equal(0)
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	var board := _board()
	assert_array(board).is_not_empty()
	_leave()
	await _frames(4)
	assert_bool(altar.used).is_false()

	for cycle in range(3):
		await _save_and_resume()
		(
			assert_array(_saved_board(SaveManager.load_run(), _ALTAR, room_id))
			. override_failure_message("the save stopped carrying the altar's board")
			. is_equal(board)
		)
		var back := _first_altar()
		assert_bool(back.used).is_false()
		assert_bool(back.interact(RunManager.player())).is_true()
		await _frames(4)
		(
			assert_array(_board())
			. override_failure_message("pray number %d dealt a new board for free" % (cycle + 2))
			. is_equal(board)
		)
		_leave()
		await _frames(4)

	# The altar is still an altar: praying for real still pays, and spends it.
	var last := _first_altar()
	assert_bool(last.interact(RunManager.player())).is_true()
	await _frames(4)
	var before := _signature(RunManager.player())
	await _answer(RunManager.game as Game)
	assert_bool(last.used).is_true()
	assert_str(_signature(RunManager.player())).is_not_equal(before)


## The other route into the same hole: the window closed while the altar's picker was up, so
## nothing was ever left or answered. The altar comes back unspent — it was never consumed —
## and praying at it shows the board that was on screen when the process died.
func test_an_altar_picker_killed_by_the_window_keeps_its_board_and_its_altar() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var altar := _first_altar()
	var room_id := FloorRestore.room_id_of(altar)
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	assert_bool((RunManager.game as Game).chest_ui.is_open()).is_true()
	var board := _board()
	SaveManager.flush_autosave()
	assert_array(_saved_board(SaveManager.load_run(), _ALTAR, room_id)).is_equal(board)

	await _save_and_resume()

	var back := _first_altar()
	assert_bool(back.used).is_false()
	assert_bool(back.interact(RunManager.player())).is_true()
	await _frames(4)
	assert_array(_board()).is_equal(board)
	await _answer(RunManager.game as Game)
	assert_bool(back.used).is_true()


## What the player paid for is what they come back to. A reroll buys a *new* board, and it is
## the new one the altar is left on; the price the next reroll costs went up and stays up, so
## quitting on a rerolled board cannot refund the ratchet either (docs §8).
func test_the_board_a_reroll_paid_for_is_the_board_that_comes_back() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	live.add_gold(500)
	var altar := _first_altar()
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	var ui := (RunManager.game as Game).chest_ui
	var first := _board()
	var gold := live.gold
	var cost := int(ui.context.get("reroll_cost", 0))
	assert_int(cost).is_greater(0)
	ui.rerolled.emit()
	await _frames(4)
	var paid := _board()
	assert_array(paid).is_not_equal(first)
	assert_int(live.gold).is_equal(gold - cost)
	_leave()
	await _frames(4)

	await _save_and_resume()

	assert_bool(_first_altar().interact(RunManager.player())).is_true()
	await _frames(4)
	(
		assert_array(_board())
		. override_failure_message("quitting on a rerolled board handed back the free one")
		. is_equal(paid)
	)
	var resumed_ui := (RunManager.game as Game).chest_ui
	(
		assert_int(int(resumed_ui.context.get("reroll_cost", 0)))
		. override_failure_message("the reroll price was refunded by the resume")
		. is_greater(cost)
	)


## A theme switch is allowed mid-run (docs §12) and repaints the picker; it may not re-deal it.
## The floor is rebuilt from the recorded `gen_params` and the board from the recorded cards, so
## neither the layout nor the three cards move when the desktop does.
func test_switching_theme_with_a_board_open_does_not_re_deal_it() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var altar := _first_altar()
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	var board := _board()
	var layout := RunManager.floor_data.layout_hash()

	EventBus.palette_changed.emit(Desktop.palette)
	await _frames(4)
	assert_array(_board()).is_equal(board)

	await _save_and_resume()

	assert_int(RunManager.floor_data.layout_hash()).is_equal(layout)
	assert_bool(_first_altar().interact(RunManager.player())).is_true()
	await _frames(4)
	assert_array(_board()).is_equal(board)


## A run that ends with a board still on screen takes the board with it: the save is gone, the
## tree is handed back, and the next run owes nothing. (A death ends a run the same way, minus
## the death animation this suite would have to wait through.)
func test_a_run_that_ends_with_a_board_open_carries_nothing_into_the_next_one() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var altar := _first_altar()
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	assert_bool((RunManager.game as Game).chest_ui.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()

	RunManager.abandon_run()
	await _frames(4)
	assert_bool(SaveManager.has_run()).is_false()
	assert_bool(get_tree().paused).is_false()

	await _start()
	assert_array(RunManager.build_run_state().offer_boards).is_empty()
	assert_bool((RunManager.game as Game).chest_ui.is_open()).is_false()


# ---------------------------------------------------------------- props


## Smashed props stay smashed. Their gold is rolled from a stream derived from (run seed, tile,
## floor index), so a rebuilt barrel pays the *same* coins every cycle — Save & Quit ->
## Continue -> re-smash was an exactly repeatable gold source.
##
## Both edges: the props the player did smash are gone and pay nothing, and the ones they never
## touched are still standing and still pay.
func test_smashed_props_stay_smashed_and_untouched_ones_still_pay() -> void:
	await _start()
	RunManager.player().health.invulnerable = true
	var root := RunManager.floor_root()
	# Only a solid prop can be smashed; a flat one (a rug, a crack) takes no hits and is not
	# part of what this test is about. Which kinds a floor carries follows the track's
	# signature prop (docs 10.2), so the flat ones are filtered rather than assumed absent.
	var breakable := _solid_props(root)
	var total := breakable.size()
	assert_int(total).is_greater(3)
	var half := total / 2
	_smash(breakable.slice(0, half))
	var first_sweep := _gold_seen
	(
		assert_int(first_sweep)
		. override_failure_message("this floor's props paid nothing, so the test proves nothing")
		. is_greater(0)
	)

	await _save_and_resume()

	var resumed := RunManager.floor_root()
	(
		assert_int(_solid_props(resumed).size())
		. override_failure_message("a resume rebuilt props the player had already smashed")
		. is_equal(total - half)
	)
	_gold_seen = 0
	_smash(_solid_props(resumed))
	(
		assert_int(_gold_seen)
		. override_failure_message("the props the player never touched were destroyed silently")
		. is_greater(0)
	)
	assert_int(_solid_props(resumed).size()).is_equal(0)

	# And a third pass over the same floor finds nothing left to sell.
	await _save_and_resume()
	assert_int(_solid_props(RunManager.floor_root()).size()).is_equal(0)
	_gold_seen = 0
	_smash(_solid_props(RunManager.floor_root()))
	assert_int(_gold_seen).is_equal(0)


# ---------------------------------------------------------------- enemies


## Kill most of a pack, bank the drops, quit, continue: the pack used to come back whole while
## the gold stayed banked, forever. Docs §12 still resets mid-fight state — the survivors come
## back at full HP, at their spawn tiles — but one enemy is dropped per enemy already killed
## there, so nothing is ever sold twice and the player keeps the progress they made.
func test_a_partly_fought_pack_comes_back_thinned_not_whole() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var room_id := room.id
	var pack := room.pending_enemy_count()
	assert_int(pack).is_greater(1)
	live.global_position = room.center_world()
	await _physics_frames(6)
	var killed := _kill_all_but_one(room, live)
	await _frames(8)
	assert_int(killed).is_equal(pack - 1)
	assert_int(room.pending_enemy_count()).is_equal(1)
	assert_int(room.state).is_not_equal(RoomNode.State.CLEARED)

	await _save_and_resume()

	var resumed := RunManager.floor_root().get_room(room_id)
	(
		assert_int(resumed.pending_enemy_count())
		. override_failure_message(
			"Save & Quit -> Continue resurrected a pack the player had killed"
		)
		. is_equal(pack - killed)
	)
	assert_int(resumed.state).is_not_equal(RoomNode.State.CLEARED)

	# Finish the room, and it stays finished: no pack, no second chest.
	var live_again := RunManager.player()
	live_again.health.invulnerable = true
	live_again.global_position = resumed.center_world()
	await _physics_frames(6)
	await _kill_room(resumed, live_again)
	await _save_and_resume()
	var cleared := RunManager.floor_root().get_room(room_id)
	assert_int(cleared.pending_enemy_count()).is_equal(0)
	assert_int(cleared.state).is_equal(RoomNode.State.CLEARED)


## The honest player. Walking into a room, locking it and quitting without landing a kill must
## cost nothing: the pack comes back exactly as it was. A "punish anyone who resumes a room
## they entered" fix would pass the farm test above and fail this one.
func test_a_room_entered_but_never_fought_comes_back_whole() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var room_id := room.id
	var pack := room.pending_enemy_count()
	assert_int(pack).is_greater(0)
	live.global_position = room.center_world()
	await _physics_frames(8)
	assert_int(room.pending_enemy_count()).is_equal(pack)

	await _save_and_resume()

	var resumed := RunManager.floor_root().get_room(room_id)
	(
		assert_int(resumed.pending_enemy_count())
		. override_failure_message("quitting a fight nobody had started cost the player the room")
		. is_equal(pack)
	)


## The pack a room comes back with has to be the pack it had. Each room draws from its own
## stream now (seed + floor + room id), so a resume — which skips every cleared room and would
## otherwise shift a shared stream — cannot re-roll the composition of the rooms still
## standing. Without this the ledger would be matching ids against a different pack, and
## quitting until the room ahead of you looked cheap would be a lever of its own.
func test_a_resume_does_not_re_roll_the_rooms_still_standing() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var root := RunManager.floor_root()
	var rooms := _combat_rooms(root, 99)
	assert_int(rooms.size()).is_greater(1)
	var before: Dictionary = {}
	for room: RoomNode in rooms.slice(1):
		before[room.id] = _pack_ids(room)
	# Clear the busiest room, which is exactly what used to shift the shared spawn stream.
	await _clear(rooms[0], live)

	await _save_and_resume()

	var after := RunManager.floor_root()
	for room_id: int in before:
		(
			assert_array(_pack_ids(after.get_room(room_id)))
			. override_failure_message(
				"the resume re-rolled room %d, which nobody had touched" % room_id
			)
			. is_equal(before[room_id])
		)


# ---------------------------------------------------------------- helpers


func _start() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)


## Save & Quit from the pause menu, then Continue from the title screen.
func _save_and_resume() -> void:
	assert_bool(RunManager.save_and_quit()).is_true()
	await _frames(4)
	assert_bool(SaveManager.has_run()).is_true()
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(8)


## Answers the board on screen: the first card, and once more when the pick routes through the
## replace row (a full ability slot, a swap the player has to confirm).
func _answer(view: Game) -> void:
	assert_bool(view.chest_ui.is_open()).is_true()
	assert_int(view.chest_ui.card_count()).is_greater(0)
	view.chest_ui.select(0)
	view.chest_ui.activate()
	await _frames(4)
	if view.chest_ui.is_open():
		view.chest_ui.select(0)
		view.chest_ui.activate()
		await _frames(4)
	assert_bool(view.chest_ui.is_open()).is_false()


## The board on screen, one comparable string per card. The cards are rebuilt objects after a
## resume, so "the same board" has to be read off what each card *is*, not off its identity.
static func _board() -> Array[String]:
	return _card_texts((RunManager.game as Game).chest_ui.offers)


## The cards `run.json` says `source` still owes in `room_id`, in the same form as `_board()`.
static func _saved_board(state: RunState, source: int, room_id: int) -> Array[String]:
	if state == null:
		return []
	var entry := state.offer_board_for(source, room_id)
	if entry.is_empty():
		return []
	return _card_texts(
		FloorRestore.offers_from_dicts(
			entry.get("offers", []) as Array, RunManager.item_registry, RunManager.ability_registry
		)
	)


static func _card_texts(offers: Array) -> Array[String]:
	var out: Array[String] = []
	for offer: Variant in offers:
		if offer is Ability:
			out.append("ability:%s@%d" % [(offer as Ability).id, (offer as Ability).tier])
		elif offer is ItemInstance:
			out.append(
				"item:%s#%d" % [(offer as ItemInstance).base.id, (offer as ItemInstance).uid]
			)
		elif offer is Dictionary:
			var entry := offer as Dictionary
			out.append("stat:%s+%d" % [str(entry.get("stat", "")), int(entry.get("points", 0))])
		else:
			out.append("gold:%d" % int(offer))
	return out


## The floor's one Altar (`src/gen/floor_validator.gd` requires exactly one per floor).
static func _first_altar() -> Altar:
	var altars := RunManager.floor_root().get_altars()
	return altars[0] as Altar if not altars.is_empty() else null


## Presses the picker's Leave button the way a player does, so the picker closes itself.
static func _leave() -> void:
	var ui := (RunManager.game as Game).chest_ui
	(ui.get_node("%Skip") as Button).pressed.emit()


## The floor's standing props: the ones a weapon can break.
static func _solid_props(root: FloorRoot) -> Array[Prop]:
	var out: Array[Prop] = []
	for prop: Prop in root.props:
		if is_instance_valid(prop) and prop.solid:
			out.append(prop)
	return out


## Breaks every prop in `targets` the way a weapon does.
func _smash(targets: Array[Prop]) -> void:
	var info := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], null, Layers.Team.PLAYER)
	for prop: Prop in targets:
		if not is_instance_valid(prop):
			continue
		var guard := 0
		while not prop.is_broken and guard < 4:
			prop.take_hit(info)
			guard += 1
		assert_bool(prop.is_broken).is_true()


## Kills every enemy in `room` but one, credited to the player. Returns how many died.
func _kill_all_but_one(room: RoomNode, killer: Player) -> int:
	var alive := room.enemies.duplicate()
	var killed := 0
	for i in range(alive.size() - 1):
		if _kill(alive[i], killer):
			killed += 1
	return killed


func _kill_room(room: RoomNode, killer: Player) -> void:
	for enemy: Node2D in room.enemies.duplicate():
		_kill(enemy, killer)
	await _frames(8)
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)


static func _kill(enemy: Node2D, killer: Player) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var entity := enemy as Entity
	if entity == null or entity.health == null:
		return false
	entity.health.take_damage(
		DamageInfo.create(99999.0, [DamageInfo.TAG_TRUE], killer, Layers.Team.PLAYER)
	)
	return true


## Walks the player in and kills everything with them credited, then waits for the clear.
func _clear(room: RoomNode, killer: Player) -> void:
	assert_int(room.enemies.size()).is_greater(0)
	killer.global_position = room.center_world()
	await _physics_frames(6)
	await _kill_room(room, killer)


## Up to `count` rooms with live enemies, busiest first.
static func _combat_rooms(root: FloorRoot, count: int) -> Array[RoomNode]:
	var out: Array[RoomNode] = []
	for room: RoomNode in root.rooms:
		if room.pending_enemy_count() > 0:
			out.append(room)
	out.sort_custom(
		func(a: RoomNode, b: RoomNode) -> bool:
			return a.pending_enemy_count() > b.pending_enemy_count()
	)
	return out.slice(0, count)


## `EnemyDef.id`s of a room's live pack, sorted so spawn order does not enter the comparison.
static func _pack_ids(room: RoomNode) -> Array[String]:
	var out: Array[String] = []
	if room == null:
		return out
	for enemy: Node2D in room.enemies:
		if not is_instance_valid(enemy):
			continue
		var def := enemy.get(&"def") as EnemyDef
		out.append(String(def.id) if def != null else "?")
	out.sort()
	return out


## Everything a chest can hand out, in one comparable string: gold, primaries, ability count
## and the uid in every equipment slot. Any prize moves it; nothing else in these tests does.
static func _signature(live: Player) -> String:
	var parts := PackedStringArray([str(live.gold)])
	for stat: StringName in Stats.PRIMARY:
		parts.append("%s=%d" % [stat, live.stats.primary(stat)])
	var slots := live.ability_slots as AbilitySlots
	parts.append("abilities=%d" % (slots.all().size() if slots != null else 0))
	var gear: Dictionary = live.to_dict().get("equipment", {}) as Dictionary
	var keys: Array = gear.keys()
	keys.sort()
	for key: Variant in keys:
		parts.append("%s:%s" % [str(key), str((gear[key] as Dictionary).get("uid", 0))])
	return "|".join(parts)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame
