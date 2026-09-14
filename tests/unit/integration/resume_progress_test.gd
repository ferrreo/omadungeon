## End-to-end integration for the docs §12 promise that "quitting is always resumable": a run
## is played forward through a shop, an altar, a shrine, a boss arena and a chest the player
## left closed, then saved and resumed. A resume can fail in two directions and both are bugs:
## progress the player *spent* coming back fresh (farmable altars, restocked shops) and
## progress the player *earned* being thrown away (a closed chest, an opened boss door).
class_name ResumeProgressIntegrationTest
extends GdUnitTestSuite

## Under the per-floor room budget (docs 5.1 #4, `RoomBudget`) the first floor always holds
## an Altar and never a Shop, the second floor always holds a Shop, and a floor holds an Altar
## *or* a Shrine, never both. Floor 3 of this seed is the first boss floor and holds the arena
## and a Shrine; the treasure room is met on whichever floor first rolls one
## (`_descend_to_room_type`), since that is a per-floor chance rather than a guarantee.
const SEED := 987654
const CLASS_ID := &"fighter"
## 0-based index of the first boss floor (`RunManager.BOSS_FLOORS[0]`).
const BOSS_FLOOR := 2
## Loose drops the homing-drop tests leave on the floor: enough gold that `PickupSpawner`
## splits it into several coins (that split is what a naive resume multiplies), one heart, and
## one stat orb on a primary the fighter does not start at zero-and-unreadable.
const LOOSE_GOLD := 300
const HEART_HEAL := 15
const ORB_STAT := &"swiftness"


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	# The docs §2 passive pick has its own suite; it would open on top of every resume here.
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


# ---------------------------------------------------------------- the whole trip


func test_a_run_played_forward_resumes_exactly_where_the_player_left_it() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	live.add_gold(5000)

	# --- floor 1: pray at the altar, loot one chest and leave one closed.
	var root := RunManager.floor_root()
	var altar := _first_altar(root)
	assert_object(altar).is_not_null()
	await _use(altar, live, 0)
	assert_bool(altar.used).is_true()

	var fought := _combat_rooms(root, 2)
	assert_int(fought.size()).is_equal(2)
	await _clear(fought[0], live)
	await _clear(fought[1], live)
	await _use(fought[0].chest, live, 0)  # looted
	assert_bool(fought[0].chest.is_opened).is_true()
	assert_object(fought[1].chest).is_not_null()
	assert_bool(fought[1].chest.is_opened).is_false()
	var looted_id := fought[0].id
	var closed_id := fought[1].id
	var closed_kind := fought[1].chest.kind
	var gold := live.gold
	# Read last: the altar pick and the chest reward both land in the ability slots.
	var abilities := _ability_count(live)

	await _save_and_resume()

	root = RunManager.floor_root()
	live = RunManager.player()
	assert_int(RunManager.floor_index).is_equal(0)
	assert_int(live.gold).is_equal(gold)
	assert_int(_ability_count(live)).is_equal(abilities)
	# Spent: the altar stays spent.
	var resumed_altar := _first_altar(root)
	assert_bool(resumed_altar.used).is_true()
	assert_bool(resumed_altar.can_interact()).is_false()
	# Earned: the chest the player never opened is still there, still closed, same kind.
	var closed := root.get_room(closed_id)
	assert_int(closed.state).is_equal(RoomNode.State.CLEARED)
	assert_object(closed.chest).is_not_null()
	assert_bool(closed.chest.is_opened).is_false()
	assert_int(int(closed.chest.kind)).is_equal(int(closed_kind))
	# ... and the one they did open is still open, not a second reward.
	var opened := root.get_room(looted_id)
	assert_int(opened.state).is_equal(RoomNode.State.CLEARED)
	assert_bool(opened.chest == null or opened.chest.is_opened).is_true()

	# --- floor 2: buy from the shop the budget guarantees there.
	live.health.invulnerable = true
	await _descend_to(1)
	root = RunManager.floor_root()
	live = RunManager.player()
	live.health.invulnerable = true
	var shop := _first_shop(root)
	assert_object(shop).is_not_null()
	assert_int(shop.offers.size()).is_equal(Shop.MAX_OFFERS)
	await _use(shop, live, 0)
	var stock_left := _offer_ids(shop)
	assert_int(stock_left.size()).is_equal(Shop.MAX_OFFERS - 1)

	await _save_and_resume()

	root = RunManager.floor_root()
	live = RunManager.player()
	assert_int(RunManager.floor_index).is_equal(1)
	# Spent: the shop keeps only what it had left.
	assert_array(_offer_ids(_first_shop(root))).contains_exactly(stock_left)

	# --- floor 3: kill the boss and kneel at the shrine.
	live.health.invulnerable = true
	await _descend_to(BOSS_FLOOR)
	root = RunManager.floor_root()
	live = RunManager.player()
	live.health.invulnerable = true
	var boss_room := _room_of_type(root, FloorData.RoomType.BOSS)
	var shrine := _first_shrine(root)
	assert_object(boss_room).is_not_null()
	assert_object(shrine).is_not_null()
	# Ids, not nodes: a resume frees this floor and builds a new one.
	var boss_id := boss_room.id
	assert_bool(root.stairs.locked).is_true()
	await _clear(boss_room, live)
	assert_bool(root.stairs.locked).is_false()
	await _use(shrine, live, 0)
	assert_bool(shrine.used).is_true()
	assert_object(boss_room.chest).is_not_null()
	assert_bool(boss_room.chest.is_opened).is_false()
	var might := live.stats.primary(&"might")

	await _save_and_resume()

	root = RunManager.floor_root()
	live = RunManager.player()
	assert_int(RunManager.floor_index).is_equal(BOSS_FLOOR)
	assert_int(live.stats.primary(&"might")).is_equal(might)
	# The blocker: the arena comes back cleared, so the exit must come back open.
	assert_bool(root.stairs.locked).is_false()
	assert_bool(root.stairs.can_interact()).is_true()
	assert_str(root.stairs.prompt_text).starts_with("Descend")
	var resumed_boss := root.get_room(boss_id)
	assert_int(resumed_boss.state).is_equal(RoomNode.State.CLEARED)
	assert_int(resumed_boss.pending_enemy_count()).is_equal(0)
	assert_object(resumed_boss.chest).is_not_null()
	assert_bool(resumed_boss.chest.is_opened).is_false()
	assert_bool(_first_shrine(root).used).is_true()
	assert_bool(_first_shrine(root).can_interact()).is_false()
	# And the player can actually leave the floor they saved on.
	await _descend_to(BOSS_FLOOR + 1)


# ---------------------------------------------------------------- one bug per test


func test_a_boss_floor_saved_after_the_boss_died_is_not_a_locked_room() -> void:
	# Blocker: the arena restores as cleared (no boss left to kill) while the stairs restore
	# sealed, and the only way out is Abandon Run, which records a loss.
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	await _descend_to(BOSS_FLOOR)
	var root := RunManager.floor_root()
	live = RunManager.player()
	live.health.invulnerable = true
	var boss_room := _room_of_type(root, FloorData.RoomType.BOSS)
	assert_object(boss_room).is_not_null()
	var boss_id := boss_room.id
	assert_bool(root.stairs.locked).is_true()
	await _clear(boss_room, live)
	assert_bool(root.stairs.locked).is_false()

	await _save_and_resume()

	root = RunManager.floor_root()
	assert_int(root.get_room(boss_id).state).is_equal(RoomNode.State.CLEARED)
	assert_int(root.get_room(boss_id).pending_enemy_count()).is_equal(0)
	assert_bool(root.stairs.locked).is_false()
	await _descend_to(BOSS_FLOOR + 1)


func test_the_saved_stairs_flag_alone_reopens_a_boss_floor() -> void:
	# Belt and braces for the derived answer above: a save whose boss room is not in the
	# cleared list (the elite-pack fallback in `_spawn_boss` opens the stairs without a
	# clear) still resumes with an open exit.
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	await _descend_to(BOSS_FLOOR)
	var root := RunManager.floor_root()
	assert_bool(root.stairs.locked).is_true()
	root.stairs.unlock()
	var state := RunManager.build_run_state()
	assert_bool(state.stairs_unlocked).is_true()
	assert_bool(state.cleared_room_ids.has(RunManager.floor_data.boss_room)).is_false()

	await _save_and_resume()

	assert_bool(RunManager.floor_root().stairs.locked).is_false()


func test_an_altar_cannot_be_prayed_at_twice_by_quitting_and_continuing() -> void:
	# Major: consumed interactables were not recorded, so Save & Quit -> Continue handed the
	# altar back and a player could farm unlimited abilities in a few seconds per loop.
	await _start()
	var live := RunManager.player()
	var altar := _first_altar(RunManager.floor_root())
	assert_object(altar).is_not_null()
	await _use(altar, live, 0)
	var abilities := _ability_count(live)

	await _save_and_resume()

	var resumed_altar := _first_altar(RunManager.floor_root())
	assert_bool(resumed_altar.used).is_true()
	assert_bool(resumed_altar.enabled).is_false()
	assert_bool(resumed_altar.can_interact()).is_false()
	assert_bool(resumed_altar.interact(RunManager.player())).is_false()
	await _frames(4)
	assert_bool((RunManager.game as Game).chest_ui.is_open()).is_false()
	assert_int(_ability_count(RunManager.player())).is_equal(abilities)


func test_a_shrine_cannot_be_knelt_at_twice_by_quitting_and_continuing() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	await _descend_to(BOSS_FLOOR)
	live = RunManager.player()
	var shrine := _first_shrine(RunManager.floor_root())
	assert_object(shrine).is_not_null()
	await _use(shrine, live, 0)
	assert_bool(shrine.used).is_true()
	var might := RunManager.player().stats.primary(&"might")

	await _save_and_resume()

	var resumed := _first_shrine(RunManager.floor_root())
	assert_bool(resumed.used).is_true()
	assert_bool(resumed.interact(RunManager.player())).is_false()
	await _frames(4)
	assert_bool((RunManager.game as Game).chest_ui.is_open()).is_false()
	assert_int(RunManager.player().stats.primary(&"might")).is_equal(might)


func test_a_shop_is_not_restocked_and_its_reroll_is_not_refunded_by_a_resume() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	# The first floor never holds a shop; the second always does (`RoomBudget`).
	await _descend_to(1)
	live = RunManager.player()
	live.add_gold(5000)
	var view := RunManager.game as Game
	var shop := _first_shop(RunManager.floor_root())
	assert_object(shop).is_not_null()
	# Pay for one reroll, then buy one of the new offers.
	assert_bool(shop.interact(live)).is_true()
	await _frames(4)
	assert_bool(view.chest_ui.is_open()).is_true()
	view.chest_ui.rerolled.emit()
	await _frames(4)
	view.chest_ui.select(0)
	await _confirm_offer(view.chest_ui)
	assert_int(shop.reroll_count).is_equal(1)
	var next_reroll := shop.reroll_price()
	var stock := _offer_ids(shop)
	var prices := shop.prices.duplicate()
	assert_int(stock.size()).is_equal(Shop.MAX_OFFERS - 1)
	assert_int(next_reroll).is_greater(Shop.reroll_base_price())

	await _save_and_resume()

	var resumed := _first_shop(RunManager.floor_root())
	assert_array(_offer_ids(resumed)).contains_exactly(stock)
	assert_array(resumed.prices).contains_exactly(prices)
	assert_int(resumed.reroll_count).is_equal(1)
	assert_int(resumed.reroll_price()).is_equal(next_reroll)


func test_a_chest_left_closed_is_still_there_after_a_resume() -> void:
	# Major: `mark_cleared` replayed every cleared room through `force_clear(false)`, which
	# skips the chest, so exploring on after a fight and quitting destroyed the reward.
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var room_id := room.id
	await _clear(room, live)
	assert_object(room.chest).is_not_null()
	var kind := room.chest.kind

	await _save_and_resume()

	var resumed := RunManager.floor_root().get_room(room_id)
	assert_int(resumed.state).is_equal(RoomNode.State.CLEARED)
	(
		assert_object(resumed.chest)
		. override_failure_message("the reward chest was destroyed by the resume")
		. is_not_null()
	)
	assert_bool(resumed.chest.is_opened).is_false()
	assert_bool(resumed.chest.can_interact()).is_true()
	assert_int(int(resumed.chest.kind)).is_equal(int(kind))


func test_an_opened_chest_stays_opened_across_repeated_resumes() -> void:
	# The other direction of the same bug: a chest that comes back closed is a free reward
	# per Save & Quit. Two round trips, because a resume also has to re-record what it read.
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var room_id := room.id
	await _clear(room, live)
	await _use(room.chest, live, 0)
	assert_bool(room.chest.is_opened).is_true()

	for _pass in range(2):
		await _save_and_resume()
		var resumed := RunManager.floor_root().get_room(room_id)
		assert_int(resumed.state).is_equal(RoomNode.State.CLEARED)
		assert_object(resumed.chest).is_not_null()
		assert_bool(resumed.chest.is_opened).is_true()
		assert_bool(resumed.chest.can_interact()).is_false()
		assert_bool(RunManager.build_run_state().looted_room_ids.has(room_id)).is_true()


func test_a_looted_treasure_room_does_not_refill_on_resume() -> void:
	# A Treasure chest is built with the floor rather than spawned by a clear, and its room
	# never enters the cleared set, so it was rebuilt closed on every resume.
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	await _descend_to_room_type(FloorData.RoomType.TREASURE)
	live = RunManager.player()
	var treasure := _room_of_type(RunManager.floor_root(), FloorData.RoomType.TREASURE)
	assert_object(treasure).is_not_null()
	assert_object(treasure.chest).is_not_null()
	var treasure_id := treasure.id
	await _use(treasure.chest, live, 0)
	assert_bool(treasure.chest.is_opened).is_true()

	await _save_and_resume()

	var resumed := RunManager.floor_root().get_room(treasure_id)
	assert_object(resumed.chest).is_not_null()
	assert_bool(resumed.chest.is_opened).is_true()
	assert_bool(resumed.chest.can_interact()).is_false()


func test_potion_capacity_and_stock_survive_the_round_trip() -> void:
	# Major: RunState's player block had no `max_potions`, so `restore_from_dict` fell back to
	# the class default and clamped the count down to it on every Continue.
	await _start()
	var live := RunManager.player()
	live.max_potions = 4
	live.add_potion(3)
	assert_int(live.potions).is_equal(4)

	await _save_and_resume()

	var resumed := RunManager.player()
	assert_int(resumed.max_potions).is_equal(4)
	assert_int(resumed.potions).is_equal(4)


## The run summary lists the tracks the run played. `build_run_state` wrote them, but nothing
## handed them back: `resume_run` reseeds the shuffle, which clears the list, so a summary
## after a relaunch started counting from the resume and forgot the first eight floors.
func test_the_tracks_already_heard_survive_a_resume() -> void:
	await _start()
	var heard: Array[String] = ["Neon Corridors", "Dotfiles"]
	Music.restore_tracks(heard)
	assert_array(RunManager.build_run_state().tracks_played).contains(heard)

	await _save_and_resume()

	(
		assert_array(Music.tracks_played())
		. override_failure_message("the resumed run forgot what it had already played")
		. contains(heard)
	)
	assert_array(RunManager.build_run_state().tracks_played).contains(heard)


func test_the_saved_player_block_carries_every_key_the_player_writes() -> void:
	# `set_player_dict` silently drops any key RunState does not know about, which is how
	# potion capacity went missing. Compare the key sets instead of listing them by hand.
	await _start()
	var live := RunManager.player()
	var written: Array = live.to_dict().keys()
	written.sort()
	var state := RunManager.build_run_state()
	var kept: Array = (state.player as Dictionary).keys()
	kept.sort()
	(
		assert_array(kept)
		. override_failure_message("RunState.player_dict() drops keys Player.to_dict() writes")
		. contains_exactly(written)
	)


func test_the_minimap_still_knows_which_rooms_were_explored() -> void:
	await _start()
	var root := RunManager.floor_root()
	var explored: Array[int] = []
	for room: RoomNode in root.rooms:
		if room.id == root.current_room_id:
			continue
		# The state walking into a room leaves behind; the entry trigger itself is the rooms
		# module's business and is covered by its own suite.
		room.visited = true
		EventBus.room_entered.emit(room.id)
		await _frames(2)
		explored.append(room.id)
		if explored.size() >= 3:
			break
	assert_array(explored).is_not_empty()

	await _save_and_resume()

	var resumed := RunManager.floor_root()
	for id: int in explored:
		(
			assert_bool(resumed.get_room(id).visited)
			. override_failure_message("room %d was explored but resumed unvisited" % id)
			. is_true()
		)
	assert_array(resumed.visited_ids()).contains(explored)


func test_a_resume_does_not_replay_the_room_clear_feedback() -> void:
	# Restoring cleared rooms through `force_clear` re-emitted `room_cleared` once per room,
	# which re-fires the clear jingle and the screen flash and runs every `on_room_cleared`
	# passive hook again, for free, on every Continue.
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	for room: RoomNode in _combat_rooms(RunManager.floor_root(), 2):
		await _clear(room, live)
	var cleared := RunManager.build_run_state().cleared_room_ids.size()
	assert_int(cleared).is_greater(1)
	RunManager.save_and_quit()
	await _frames(4)

	var replays: Array[int] = []
	var handler := func(room_id: int) -> void: replays.append(room_id)
	EventBus.room_cleared.connect(handler)
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(6)
	EventBus.room_cleared.disconnect(handler)
	(
		assert_array(replays)
		. override_failure_message("resume re-announced %d room clears" % replays.size())
		. is_empty()
	)
	assert_int(RunManager.build_run_state().cleared_room_ids.size()).is_equal(cleared)


# ---------------------------------------------------------------- drops on the floor


## An item lying on the floor is loot the player has already earned and has not bent down for
## yet - an elite's guaranteed Rare-or-better, or the gear an equip swap put back down. It
## lives only as a node under the RoomNode, so a resume that rebuilds the floor from the seed
## (with the room still cleared, so nothing respawns) used to delete it without a word. The
## descend path got a whole `DescendNotice` for abandoning less than this.
func test_an_item_left_on_the_floor_survives_save_and_quit() -> void:
	await _start()
	RunManager.player().health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var item := _drop_item(room, room.center_world())
	await _frames(4)
	var live_drops := FloorPickups.find_all(RunManager.floor_root())
	assert_int(live_drops.size()).is_equal(1)
	var where := live_drops[0].global_position
	# Read before the resume: it frees this floor, RoomNodes and all.
	var room_id := room.id
	var saved := RunManager.build_run_state()
	assert_int(saved.floor_pickups.size()).is_equal(1)

	await _save_and_resume()

	var back := FloorPickups.find_all(RunManager.floor_root())
	(
		assert_int(back.size())
		. override_failure_message("the drop was destroyed by Save & Quit")
		. is_equal(1)
	)
	assert_int(back[0].item.uid).is_equal(item.uid)
	assert_str(back[0].item.display_name).is_equal(item.display_name)
	assert_int(back[0].item.rarity).is_equal(item.rarity)
	assert_int(FloorRestore.room_id_of(back[0])).is_equal(room_id)
	assert_vector(back[0].global_position).is_equal_approx(where, Vector2(1.5, 1.5))


## The other direction, and the one a naive replay gets wrong: quitting must not *multiply*
## the loot either. Two Save & Quits in a row over the same floor leave two items, not four.
func test_resuming_twice_does_not_duplicate_the_drops() -> void:
	await _start()
	RunManager.player().health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	_drop_item(room, room.center_world() + Vector2(6, 0))
	_drop_item(room, room.center_world() + Vector2(-6, 0))
	await _frames(4)
	assert_int(FloorPickups.find_all(RunManager.floor_root()).size()).is_equal(2)
	await _save_and_resume()
	assert_int(FloorPickups.find_all(RunManager.floor_root()).size()).is_equal(2)
	await _save_and_resume()
	(
		assert_int(FloorPickups.find_all(RunManager.floor_root()).size())
		. override_failure_message("every resume re-dropped the loot")
		. is_equal(2)
	)


## A drop the player already took is gone, and stays gone. Resurrecting collected loot would
## be the same bug with the sign flipped: infinite items for the price of a Save & Quit.
func test_a_drop_the_player_already_collected_does_not_come_back() -> void:
	await _start()
	RunManager.player().health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var kept := _drop_item(room, room.center_world() + Vector2(6, 0))
	var taken := _drop_item(room, room.center_world() + Vector2(-6, 0))
	await _frames(4)
	for pickup: ItemPickup in FloorPickups.find_all(RunManager.floor_root()):
		if pickup.item.uid == taken.uid:
			pickup.queue_free()
	await _frames(3)
	assert_int(RunManager.build_run_state().floor_pickups.size()).is_equal(1)

	await _save_and_resume()

	var back := FloorPickups.find_all(RunManager.floor_root())
	assert_int(back.size()).is_equal(1)
	assert_int(back[0].item.uid).is_equal(kept.uid)


## The second half of the finding, through the real equip path: `ItemPickup` promises that
## "whatever it displaces is dropped back on the floor as another ItemPickup, so a swap is
## always reversible and nothing is ever destroyed". That was true inside a session and false
## across one - the displaced weapon went in the bin on Save & Quit, and the swap stopped being
## reversible the moment the player took a break.
func test_the_weapon_an_equip_swap_displaced_is_still_there_after_a_resume() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var worn := (live.equipment as Equipment).get_item(&"weapon")
	assert_object(worn).is_not_null()
	var offered := _drop_weapon(room, live.global_position + Vector2(4, 0))
	assert_object(offered).is_not_null()
	# The drop refuses an interact for its own SETTLE_TIME, so the key press that dropped it
	# cannot immediately equip it. That is wall-clock, not frames.
	await get_tree().create_timer(ItemPickup.SETTLE_TIME + 0.2).timeout
	var drops := FloorPickups.find_all(RunManager.floor_root())
	assert_int(drops.size()).is_equal(1)
	assert_bool(drops[0].interact(live)).is_true()
	await _frames(4)
	assert_int((live.equipment as Equipment).get_item(&"weapon").uid).is_equal(offered.uid)
	var displaced := FloorPickups.find_all(RunManager.floor_root())
	(
		assert_int(displaced.size())
		. override_failure_message("the swap put nothing back on the floor")
		. is_equal(1)
	)
	assert_int(displaced[0].item.uid).is_equal(worn.uid)

	await _save_and_resume()

	var back := FloorPickups.find_all(RunManager.floor_root())
	(
		assert_int(back.size())
		. override_failure_message("the displaced weapon was destroyed by Save & Quit")
		. is_equal(1)
	)
	assert_int(back[0].item.uid).is_equal(worn.uid)
	assert_int((RunManager.player().equipment as Equipment).get_item(&"weapon").uid).is_equal(
		offered.uid
	)


## Drops a generated *weapon* in `room`, so equipping it is guaranteed to displace the one the
## class started with. Seeded, never `randf()`.
func _drop_weapon(room: RoomNode, pos: Vector2) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var weapon_only: Array[int] = [ItemBase.Slot.WEAPON]
	var item := ItemGenerator.generate(
		RunManager.item_registry, RunManager.floor_index, rng, 0.0, weapon_only
	)
	if item == null:
		return null
	ItemPickup.drop(room, item, pos, rng)
	return item


## Drops belong to the floor they fell on: taking the stairs leaves them behind, and a resume
## on the next floor must not carry them down (`ItemPickup` frees itself on `floor_started`).
func test_drops_do_not_follow_the_player_down_the_stairs() -> void:
	await _start()
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	_drop_item(room, room.center_world())
	await _frames(4)
	assert_int(RunManager.build_run_state().floor_pickups.size()).is_equal(1)
	await _descend_to(1)
	assert_int(RunManager.floor_index).is_equal(1)
	assert_array(RunManager.build_run_state().floor_pickups).is_empty()
	await _save_and_resume()
	assert_array(FloorPickups.find_all(RunManager.floor_root())).is_empty()


## Generates one item off a fixed stream and drops it in `room` at `pos`. Loot never uses the
## global `randf()`, in a test least of all.
func _drop_item(room: RoomNode, pos: Vector2) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos)
	var item := ItemGenerator.generate(RunManager.item_registry, RunManager.floor_index, rng, 0.0)
	assert_object(item).is_not_null()
	ItemPickup.drop(room, item, pos, rng)
	return item


# ---------------------------------------------------------------- homing drops on the floor


## The other half of the same promise, and the half that was still open. Gold, hearts and the
## stat orb every elite is guaranteed to drop are `PickupBase` nodes under the `PickupSpawner`,
## not `ItemPickup` nodes under a RoomNode, so the sweep that saved the items found none of
## them: Save & Quit destroyed the orb, the loose gold and the hearts without a word, which is
## progress the player had already earned being taken away for taking a break.
##
## One of every kind that can be lying on a floor goes down together - an elite's item, its
## orb, its gold, a heart - because the two halves drifting apart is what caused this, and a
## test that drops only one kind cannot notice the next one going missing.
func test_one_of_every_kind_of_drop_on_the_floor_survives_save_and_quit() -> void:
	await _start()
	RunManager.player().health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var spot := room.center_world()
	var item := _drop_item(room, spot)
	_drop_homing(spot)
	await _settle(spot)

	var before_counts := _drop_counts()
	var before_totals := _drop_totals()
	var before_places := _drop_places()
	assert_int(FloorPickups.find_all(RunManager.floor_root()).size()).is_equal(1)
	var saved := RunManager.build_run_state()
	assert_int(saved.floor_pickups.size()).is_equal(1)
	var live_drops := _live_drops().size()
	(
		assert_int(saved.floor_drops.size())
		. override_failure_message(
			(
				"the save carries %d of the %d homing drops on the floor"
				% [saved.floor_drops.size(), live_drops]
			)
		)
		. is_equal(live_drops)
	)

	await _save_and_resume()

	var items := FloorPickups.find_all(RunManager.floor_root())
	(
		assert_int(items.size())
		. override_failure_message("the item drop was destroyed by Save & Quit")
		. is_equal(1)
	)
	assert_int(items[0].item.uid).is_equal(item.uid)
	(
		assert_dict(_drop_counts())
		. override_failure_message(
			"Save & Quit destroyed loose drops: %s -> %s" % [before_counts, _drop_counts()]
		)
		. is_equal(before_counts)
	)
	(
		assert_dict(_drop_totals())
		. override_failure_message("a restored drop came back worth a different amount")
		. is_equal(before_totals)
	)
	assert_str(String(_restored_orb().stat)).is_equal(String(ORB_STAT))
	for place: Vector2 in _drop_places():
		var nearest := INF
		for was: Vector2 in before_places:
			nearest = minf(nearest, place.distance_to(was))
		(
			assert_float(nearest)
			. override_failure_message("a drop came back somewhere it never lay")
			. is_less(1.5)
		)


## Coming back is not enough: a drop that is scenery the player cannot pick up is still
## progress taken away. Every restored kind is walked into and has to pay out - the coins into
## the purse, the heart into the health bar, the orb into the primary it rolled, the item onto
## the character - through the same collection paths the live drops use.
func test_every_restored_drop_is_still_collectable() -> void:
	await _start()
	RunManager.player().health.invulnerable = true
	var room := _combat_rooms(RunManager.floor_root(), 1)[0]
	var spot := room.center_world()
	var item := _drop_item(room, spot)
	_drop_homing(spot)
	await _settle(spot)

	await _save_and_resume()

	var live := RunManager.player()
	live.health.invulnerable = true
	var gold_before := live.gold
	var orb_before := live.stats.primary(ORB_STAT)
	live.health.hp = maxf(1.0, live.health.max_hp - 2.0 * HEART_HEAL)
	var hp_before := live.health.hp
	live.global_position = spot
	await _physics_frames(90)

	(
		assert_int(live.gold - gold_before)
		. override_failure_message("the restored gold paid nothing")
		. is_equal(LOOSE_GOLD)
	)
	(
		assert_float(live.health.hp)
		. override_failure_message("the restored heart healed nothing")
		. is_equal_approx(hp_before + float(HEART_HEAL), 0.01)
	)
	(
		assert_int(live.stats.primary(ORB_STAT) - orb_before)
		. override_failure_message("the restored stat orb granted nothing")
		. is_equal(1)
	)
	assert_array(_live_drops()).is_empty()
	# The item is the one drop that waits to be asked; it settles on wall-clock, not frames.
	await get_tree().create_timer(ItemPickup.SETTLE_TIME + 0.2).timeout
	var drops := FloorPickups.find_all(RunManager.floor_root())
	assert_int(drops.size()).is_equal(1)
	(
		assert_bool(drops[0].interact(live))
		. override_failure_message("the restored item refused to be equipped")
		. is_true()
	)
	await _frames(4)
	# By uid over every worn slot: a ring lands in `ring1` or `ring2`, never in a slot called
	# "ring", and which item this seed drops is a function of where the room's centre lies.
	var worn_uids: Array[int] = []
	for worn: ItemInstance in (live.equipment as Equipment).items():
		worn_uids.append(worn.uid)
	(
		assert_array(worn_uids)
		. override_failure_message("the restored item was taken but is not worn")
		. contains([item.uid])
	)


## The sign flipped, and the one a naive replay gets wrong: quitting must not *multiply* the
## loot. `PickupSpawner.spawn(&"gold", pos, 300)` splits a request into several coins, so
## replaying saved coins through it would make several coins out of each of them and a player
## who liked money would learn to quit and continue in a loop. Two rounds, because a multiplier
## only shows itself when it is applied twice.
func test_repeated_save_and_quit_multiplies_neither_the_coins_nor_the_purse() -> void:
	await _start()
	RunManager.player().health.invulnerable = true
	var spot := _combat_rooms(RunManager.floor_root(), 1)[0].center_world()
	_drop_homing(spot)
	await _settle(spot)
	var counts := _drop_counts()
	var totals := _drop_totals()

	await _save_and_resume()
	await _save_and_resume()

	(
		assert_dict(_drop_counts())
		. override_failure_message(
			"every resume re-split the drops: %s -> %s" % [counts, _drop_counts()]
		)
		. is_equal(counts)
	)
	(
		assert_dict(_drop_totals())
		. override_failure_message(
			"every resume made the floor richer: %s -> %s" % [totals, _drop_totals()]
		)
		. is_equal(totals)
	)


## Drops belong to the floor they fell on, whichever kind they are. Taking the stairs leaves
## them behind and a resume on the next floor must not carry them down - the guarantee
## `PickupSpawner.clear_pickups()` gives inside a session, held across one.
func test_homing_drops_do_not_follow_the_player_down_the_stairs() -> void:
	await _start()
	RunManager.player().health.invulnerable = true
	var spot := _combat_rooms(RunManager.floor_root(), 1)[0].center_world()
	_drop_homing(spot)
	await _settle(spot)
	assert_array(RunManager.build_run_state().floor_drops).is_not_empty()

	await _descend_to(1)

	assert_int(RunManager.floor_index).is_equal(1)
	(
		assert_array(_live_drops())
		. override_failure_message("the drops followed the player down the stairs")
		. is_empty()
	)
	assert_array(RunManager.build_run_state().floor_drops).is_empty()
	await _save_and_resume()
	assert_array(_live_drops()).is_empty()


## One of every homing kind at `pos`, through the real path: `EventBus.spawn_pickup` is what an
## enemy death emits and the live `PickupSpawner` is what listens, so this is the drop the game
## makes rather than a node the test built.
func _drop_homing(pos: Vector2) -> void:
	EventBus.spawn_pickup.emit(&"gold", pos, LOOSE_GOLD)
	EventBus.spawn_pickup.emit(&"heart", pos + Vector2(10, 0), HEART_HEAL)
	EventBus.spawn_pickup.emit(&"stat_orb", pos + Vector2(-10, 0), Stats.PRIMARY.find(ORB_STAT))


## Waits for the drops to come to rest so a saved position can be compared with a restored one
## without the spawn scatter still moving underneath the measurement, and checks the premise
## every one of these tests rests on: the player is nowhere near, so nothing is collected by
## accident and the floor the save describes is the floor the test dropped.
func _settle(spot: Vector2) -> void:
	await _physics_frames(40)
	var live := RunManager.player()
	(
		assert_float(live.global_position.distance_to(spot))
		. override_failure_message("the player is standing on the drops; they would be collected")
		. is_greater(PickupBase.pickup_radius_of(live) * 3.0)
	)
	assert_array(_live_drops()).is_not_empty()


## The homing drops lying on the live floor. They are children of the `PickupSpawner`, which is
## a sibling of the floor root, so `FloorPickups.find_all` cannot see them and neither can any
## other sweep of the floor.
static func _live_drops() -> Array[PickupBase]:
	var out: Array[PickupBase] = []
	var spawner := FloorDrops.spawner_of(RunManager.game)
	return spawner.live_pickups() if spawner != null else out


## Kind -> how many drops of it are on the floor.
static func _drop_counts() -> Dictionary:
	var out: Dictionary = {}
	for pickup: PickupBase in _live_drops():
		out[pickup.kind] = int(out.get(pickup.kind, 0)) + 1
	return out


## Kind -> the total it is worth, which is the comparison that survives the coin split: a gold
## request becomes several coins and only their sum is the drop the player earned.
static func _drop_totals() -> Dictionary:
	var out: Dictionary = {}
	for pickup: PickupBase in _live_drops():
		out[pickup.kind] = int(out.get(pickup.kind, 0)) + pickup.amount
	return out


static func _drop_places() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pickup: PickupBase in _live_drops():
		out.append(pickup.global_position)
	return out


## The one stat orb on the floor. Fails the assertion rather than returning null, so a missing
## orb reads as "the elite's orb is gone" instead of a crash three lines later.
static func _restored_orb() -> StatOrbPickup:
	for pickup: PickupBase in _live_drops():
		var orb := pickup as StatOrbPickup
		if orb != null:
			return orb
	return StatOrbPickup.new()


# ---------------------------------------------------------------- helpers


func _start() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)


## Save & Quit from the pause menu, then Continue from the title screen.
func _save_and_resume() -> void:
	RunManager.save_and_quit()
	await _frames(4)
	assert_bool(SaveManager.has_run()).is_true()
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(6)


## Walks down to `target` the way a player does: through the floor's stairs, answering the
## "you are leaving rewards behind" prompt with a second press. Bounded, so a floor that
## refuses to let the player leave fails the test instead of hanging the suite.
func _descend_to(target: int) -> void:
	for _step in range(target + 2):
		if RunManager.floor_index >= target:
			break
		var before := RunManager.floor_index
		var root := RunManager.floor_root()
		assert_bool(root.stairs.locked).is_false()
		assert_bool(root.stairs.interact(RunManager.player())).is_true()
		await _frames(4)
		if RunManager.floor_index == before:
			assert_bool(root.stairs.interact(RunManager.player())).is_true()
			await _frames(6)
		assert_int(RunManager.floor_index).is_equal(before + 1)
	assert_int(RunManager.floor_index).is_equal(target)


## Walks down until the current floor holds a room of `type` (a per-floor chance under the
## room budget, not a guarantee on any one floor), clearing a boss arena on the way when the
## stairs are sealed behind it. Bounded: a run with no such room in its first six floors fails.
func _descend_to_room_type(type: FloorData.RoomType) -> void:
	for _step in range(6):
		var root := RunManager.floor_root()
		if _room_of_type(root, type) != null:
			return
		var live := RunManager.player()
		live.health.invulnerable = true
		if root.stairs.locked:
			var boss_room := _room_of_type(root, FloorData.RoomType.BOSS)
			assert_object(boss_room).is_not_null()
			await _clear(boss_room, live)
		await _descend_to(RunManager.floor_index + 1)
	assert_object(_room_of_type(RunManager.floor_root(), type)).is_not_null()


## Uses an interactable and takes card `index` from the picker it opens.
func _use(node: Interactable, live: Player, index: int) -> void:
	assert_object(node).is_not_null()
	assert_bool(node.interact(live)).is_true()
	await _frames(4)
	var view := RunManager.game as Game
	assert_bool(view.chest_ui.is_open()).is_true()
	assert_int(view.chest_ui.card_count()).is_greater(index)
	view.chest_ui.select(index)
	await _confirm_offer(view.chest_ui)
	assert_bool(view.chest_ui.is_open()).is_false()


## Confirms the card the selection is on, and answers the trade view if one opens. An offer
## that displaces something the player already has - a weapon, a piece of armour, an ability
## against full slots - holds the two up side by side first, so one confirm is no longer the
## whole interaction.
func _confirm_offer(ui: ChestUi) -> void:
	ui.activate()
	await _frames(4)
	if ui.is_open() and ui.selected_row() == ChestUi.Row.REPLACE:
		ui.activate()
		await _frames(4)


## Walks the player in and kills everything with them credited, then waits for the clear.
## The walk in matters: a room only locks and clears once the player is inside it.
func _clear(room: RoomNode, killer: Player) -> void:
	assert_int(room.enemies.size()).is_greater(0)
	killer.global_position = room.center_world()
	await _physics_frames(6)
	for enemy: Node2D in room.enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		var entity := enemy as Entity
		if entity != null and entity.health != null:
			entity.health.take_damage(
				DamageInfo.create(99999.0, [DamageInfo.TAG_TRUE], killer, Layers.Team.PLAYER)
			)
	await _frames(8)
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)


static func _first_altar(root: FloorRoot) -> Altar:
	return root.get_altars()[0] as Altar if not root.get_altars().is_empty() else null


static func _first_shop(root: FloorRoot) -> Shop:
	return root.get_shops()[0] as Shop if not root.get_shops().is_empty() else null


static func _first_shrine(root: FloorRoot) -> Shrine:
	return root.get_shrines()[0] as Shrine if not root.get_shrines().is_empty() else null


static func _room_of_type(root: FloorRoot, type: FloorData.RoomType) -> RoomNode:
	for room: RoomNode in root.rooms:
		if room.type == type:
			return room
	return null


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


## Base ids of a shop's remaining offers, in order.
static func _offer_ids(shop: Shop) -> Array[String]:
	var out: Array[String] = []
	for offer: RefCounted in shop.offers:
		var item := offer as ItemInstance
		out.append(String(item.base.id) if item != null else "?")
	return out


static func _ability_count(live: Player) -> int:
	var slots := live.ability_slots as AbilitySlots
	return slots.all().size() if slots != null else 0


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame
