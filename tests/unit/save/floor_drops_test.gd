## The homing drops on a floor - gold, hearts and the stat orb every elite is guaranteed to
## leave - across a save and a resume (docs §12: "quitting is always resumable").
##
## These are `PickupBase` nodes under the `PickupSpawner`, not `ItemPickup` nodes under a
## RoomNode, and that difference is the whole bug: the spawner empties its container on
## `EventBus.floor_started`, nothing else knows the drops exist, and a resume rebuilds the floor
## from the seed. Until `FloorDrops` carried them, Save & Quit deleted every one of them without
## a word. This suite works at the node level - spawner, pickups, a stand-in player - so a
## regression here points at the serialization rather than at the run lifecycle;
## `ResumeProgressIntegrationTest` proves the same thing through a real RunManager run.
class_name FloorDropsTest
extends GdUnitTestSuite

## Far enough that nothing homes to the player while the test is measuring positions.
const PARKED := Vector2(4000, 4000)
const DROP_SPOT := Vector2(120, -48)
const GOLD := 300
const HEAL := 15

var _root: Node2D
var _spawner: PickupSpawner
var _player: EnemyTestPlayer


func before_test() -> void:
	_root = auto_free(Node2D.new()) as Node2D
	add_child(_root)
	_spawner = PickupSpawner.new()
	_root.add_child(_spawner)
	_player = EnemyTestPlayer.new()
	_root.add_child(_player)
	_player.global_position = PARKED


## One of every kind the spawner can make, dropped in a tight cluster the way an elite's death
## leaves them. Awaits the deferred insertion, so the caller gets live nodes.
func _drop_one_of_each() -> void:
	_spawner.spawn(&"gold", DROP_SPOT, GOLD)
	_spawner.spawn(&"heart", DROP_SPOT + Vector2(8, 0), HEAL)
	_spawner.spawn(&"stat_orb", DROP_SPOT + Vector2(-8, 0), Stats.PRIMARY.find(&"swiftness"))
	await get_tree().process_frame


## Save & Quit and Continue, as the spawner sees them: capture, the floor is torn down and
## rebuilt (`floor_started` empties the container), then the saved drops are replayed.
func _save_and_resume(state: RunState) -> void:
	state.floor_drops = FloorDrops.capture(_spawner)
	EventBus.floor_started.emit(0)
	await get_tree().process_frame
	(
		assert_array(_spawner.live_pickups())
		. override_failure_message("the new floor started with the old floor's drops still on it")
		. is_empty()
	)
	FloorDrops.apply(_spawner, state)
	await get_tree().process_frame


## Kind -> total amount over every live drop, which is the only comparison that survives the
## coin split: `spawn(&"gold", pos, 300)` makes several coins and the save carries each of them.
func _totals() -> Dictionary:
	var out: Dictionary = {}
	for pickup: PickupBase in _spawner.live_pickups():
		out[pickup.kind] = int(out.get(pickup.kind, 0)) + pickup.amount
	return out


func _counts() -> Dictionary:
	var out: Dictionary = {}
	for pickup: PickupBase in _spawner.live_pickups():
		out[pickup.kind] = int(out.get(pickup.kind, 0)) + 1
	return out


func test_every_kind_of_drop_is_recorded_by_a_capture() -> void:
	await _drop_one_of_each()
	var entries := FloorDrops.capture(_spawner)
	var kinds: Array[String] = []
	for entry: Dictionary in entries:
		kinds.append(str(entry["kind"]))
	(
		assert_array(kinds)
		. override_failure_message("a kind of drop the save does not carry is a kind it destroys")
		. contains(["gold", "heart", "stat_orb"])
	)
	assert_int(entries.size()).is_equal(_spawner.live_pickups().size())


func test_one_of_each_kind_comes_back_after_a_save_and_a_resume() -> void:
	await _drop_one_of_each()
	var before_counts := _counts()
	var before_totals := _totals()
	var before_places: Array[Vector2] = []
	for pickup: PickupBase in _spawner.live_pickups():
		before_places.append(pickup.global_position)

	var state := RunState.new()
	await _save_and_resume(state)

	(
		assert_dict(_counts())
		. override_failure_message(
			"Save & Quit destroyed loose drops: %s -> %s" % [before_counts, _counts()]
		)
		. is_equal(before_counts)
	)
	assert_dict(_totals()).is_equal(before_totals)
	for pickup: PickupBase in _spawner.live_pickups():
		var nearest := INF
		for place: Vector2 in before_places:
			nearest = minf(nearest, pickup.global_position.distance_to(place))
		(
			assert_float(nearest)
			. override_failure_message("a drop came back somewhere it never lay")
			. is_less(1.5)
		)


## The orb is the drop with a payload beyond its amount: an elite's orb grants the primary it
## rolled, so restoring it as the `might` default would quietly change what the player earned.
func test_a_restored_stat_orb_still_grants_the_stat_it_rolled() -> void:
	_spawner.spawn(&"stat_orb", DROP_SPOT, Stats.PRIMARY.find(&"fortune"))
	await get_tree().process_frame
	await _save_and_resume(RunState.new())
	var orbs := _spawner.live_pickups()
	assert_int(orbs.size()).is_equal(1)
	assert_str(String((orbs[0] as StatOrbPickup).stat)).is_equal("fortune")


## Surviving the save is only half of it: a drop that comes back as scenery the player cannot
## pick up is still progress taken away. Every kind is walked into and has to pay out.
func test_every_restored_drop_is_still_collectable() -> void:
	_player.health.take_damage(
		DamageInfo.create(50.0, [DamageInfo.TAG_TRUE], null, Layers.Team.NEUTRAL)
	)
	var wounded := _player.health.hp
	await _drop_one_of_each()
	await _save_and_resume(RunState.new())

	_player.global_position = DROP_SPOT
	for _i in range(90):
		await get_tree().physics_frame
	assert_int(_player.gold).override_failure_message("restored gold paid nothing").is_equal(GOLD)
	(
		assert_float(_player.health.hp)
		. override_failure_message("the restored heart healed nothing")
		. is_equal_approx(wounded + float(HEAL), 0.01)
	)
	(
		assert_int(int(_player.stats_added.get(&"swiftness", 0)))
		. override_failure_message("the restored stat orb granted nothing")
		. is_equal(1)
	)
	assert_array(_spawner.live_pickups()).is_empty()


## The other direction, and the one a naive replay gets wrong. `spawn(&"gold", pos, 300)` splits
## a request into up to five coins; replaying five *saved* coins through that would make
## twenty-five, and a player who liked money would learn to quit and continue in a loop. Two
## rounds, because a multiplier only shows up when it is applied twice.
func test_resuming_twice_multiplies_neither_the_coins_nor_the_purse() -> void:
	await _drop_one_of_each()
	var counts := _counts()
	var totals := _totals()
	var state := RunState.new()
	await _save_and_resume(state)
	await _save_and_resume(state)
	(
		assert_dict(_counts())
		. override_failure_message(
			"every resume re-split the drops: %s -> %s" % [counts, _counts()]
		)
		. is_equal(counts)
	)
	(
		assert_dict(_totals())
		. override_failure_message(
			"every resume paid the player again: %s -> %s" % [totals, _totals()]
		)
		. is_equal(totals)
	)


## A drop the player already took is gone, and stays gone: resurrecting collected loot is the
## same bug with the sign flipped.
func test_a_drop_the_player_already_collected_does_not_come_back() -> void:
	await _drop_one_of_each()
	_player.global_position = DROP_SPOT + Vector2(-8, 0)
	for _i in range(90):
		await get_tree().physics_frame
	assert_int(int(_player.stats_added.get(&"swiftness", 0))).is_equal(1)
	var left := _counts()
	assert_bool(left.has(&"stat_orb")).is_false()
	_player.global_position = PARKED

	await _save_and_resume(RunState.new())

	(
		assert_dict(_counts())
		. override_failure_message("a collected orb was resurrected by Save & Quit")
		. is_equal(left)
	)


## A save is data from disk, and may name a kind this build cannot make (a downgrade, a hand-
## edited file). That one entry is skipped; the rest of the floor still comes back.
func test_an_unreadable_entry_is_skipped_without_losing_the_others() -> void:
	var state := RunState.new()
	state.floor_drops = [
		{"kind": "confetti", "amount": 2, "x": 0.0, "y": 0.0},
		{"kind": "gold", "amount": 41, "x": DROP_SPOT.x, "y": DROP_SPOT.y},
	]
	assert_int(FloorDrops.apply(_spawner, state)).is_equal(1)
	await get_tree().process_frame
	var live := _spawner.live_pickups()
	assert_int(live.size()).is_equal(1)
	assert_int(live[0].amount).is_equal(41)


## `capture` and `apply` are called with whatever the run has, and outside a run that is
## nothing. Neither may push an error for it.
func test_no_spawner_and_no_state_are_answered_with_nothing() -> void:
	assert_array(FloorDrops.capture(null)).is_empty()
	assert_int(FloorDrops.apply(null, RunState.new())).is_equal(0)
	assert_int(FloorDrops.apply(_spawner, null)).is_equal(0)
	assert_object(FloorDrops.spawner_of(null)).is_null()
	assert_object(FloorDrops.spawner_of(_root)).is_null()


## A save is a file on disk, and `run.json` is plain JSON in the user's own data directory. An
## entry that says a stat orb is worth 999 has to come back worth one, because that is what the
## class means: `set_stat_index()` picks the *stat*, never the magnitude, so every orb the game
## can drop is a single point. Before `PickupLimits` the only bound on `amount` was `>= 1`, and
## `StatOrbPickup._collect` hands it straight to `player.add_stat()` - a hand-edited file minted
## as many primary stat points as it liked, and the orb it minted them with was a real,
## collectable node that resumed again on the next save.
func test_a_restored_stat_orb_is_worth_one_point_whatever_the_file_claims() -> void:
	var state := RunState.new()
	state.floor_drops = [
		{
			"kind": "stat_orb",
			"amount": 999,
			"x": DROP_SPOT.x,
			"y": DROP_SPOT.y,
			"stat": "might",
		},
	]
	assert_int(FloorDrops.apply(_spawner, state)).is_equal(1)
	await get_tree().process_frame
	var live := _spawner.live_pickups()
	assert_int(live.size()).is_equal(1)
	(
		assert_int(live[0].amount)
		. override_failure_message("a hand-edited save minted %d stat points" % live[0].amount)
		. is_equal(1)
	)

	_player.global_position = DROP_SPOT
	for _i in range(90):
		await get_tree().physics_frame
	(
		assert_int(int(_player.stats_added.get(&"might", 0)))
		. override_failure_message("the orb paid out more than one point")
		. is_equal(1)
	)


## Gold and hearts are bounded too, well above anything the content can roll, so an honest save
## is never quietly shaved while a corrupt one cannot mint a fortune.
func test_gold_and_hearts_are_bounded_by_the_shipped_limits() -> void:
	var limits := PickupLimits.resolve()
	var state := RunState.new()
	state.floor_drops = [
		{"kind": "gold", "amount": 999999999, "x": DROP_SPOT.x, "y": DROP_SPOT.y},
		{"kind": "heart", "amount": 999999999, "x": DROP_SPOT.x + 8.0, "y": DROP_SPOT.y},
	]
	FloorDrops.apply(_spawner, state)
	await get_tree().process_frame
	var by_kind := _totals()
	assert_int(int(by_kind[&"gold"])).is_equal(int(limits.max_amount["gold"]))
	assert_int(int(by_kind[&"heart"])).is_equal(int(limits.max_amount["heart"]))


## ...and the bounds are ceilings, not rewrites: every amount a live floor can actually produce
## restores as the number that was saved. This is the half the clamp could destroy, so it is
## asserted next to it.
func test_the_limits_never_change_an_amount_an_honest_drop_carried() -> void:
	await _drop_one_of_each()
	var totals := _totals()
	var counts := _counts()
	await _save_and_resume(RunState.new())
	(
		assert_dict(_totals())
		. override_failure_message("the corruption guard shaved an honest drop")
		. is_equal(totals)
	)
	assert_dict(_counts()).is_equal(counts)


## A coordinate of `1e30` is finite, so it passed every check there was: the drop was planted
## nowhere at all, lived in the tree, and was written back out on every autosave from then on.
## A non-finite one is worse. Neither is a place a drop could have been lying, and the rest of
## the floor still has to come back.
func test_a_drop_at_an_impossible_position_is_not_restored() -> void:
	var state := RunState.new()
	state.floor_drops = [
		{"kind": "gold", "amount": 9, "x": 1e30, "y": -1e30},
		{"kind": "gold", "amount": 9, "x": NAN, "y": 0.0},
		{"kind": "heart", "amount": 15, "x": 0.0, "y": INF},
		{"kind": "gold", "amount": 41, "x": DROP_SPOT.x, "y": DROP_SPOT.y},
	]
	(
		assert_int(FloorDrops.apply(_spawner, state))
		. override_failure_message("an impossible position was planted as a real drop")
		. is_equal(1)
	)
	await get_tree().process_frame
	var live := _spawner.live_pickups()
	assert_int(live.size()).is_equal(1)
	assert_int(live[0].amount).is_equal(41)
	assert_vector(live[0].global_position).is_equal_approx(DROP_SPOT, Vector2.ONE)


## The tighter bound, the one a live resume uses: the floor's own camera limits. A drop inside
## them is restored, one nowhere near them is not - and the margin is generous enough that a
## coin that popped past the grid edge still comes home.
func test_a_drop_outside_the_floor_rect_is_skipped_and_one_inside_it_is_not() -> void:
	var floor_rect := Rect2(Vector2.ZERO, Vector2(640, 480))
	var state := RunState.new()
	state.floor_drops = [
		{"kind": "gold", "amount": 7, "x": 5000.0, "y": 5000.0},
		{"kind": "gold", "amount": 11, "x": 320.0, "y": 240.0},
		{"kind": "gold", "amount": 13, "x": -8.0, "y": 240.0},
	]
	assert_int(FloorDrops.apply(_spawner, state, floor_rect)).is_equal(2)
	await get_tree().process_frame
	var amounts: Array[int] = []
	for pickup: PickupBase in _spawner.live_pickups():
		amounts.append(pickup.amount)
	amounts.sort()
	(
		assert_array(amounts)
		. override_failure_message("the floor rect rejected a drop that lay on the floor")
		. is_equal([11, 13])
	)


## `apply()` returns a fact, not a promise. It used to count every entry `restore()` handed a
## node back for while the insertion was still in the message queue, so a drop the spawner's
## generation guard went on to throw away counted as restored.
func test_the_restored_count_is_what_is_actually_on_the_floor() -> void:
	var state := RunState.new()
	state.floor_drops = [
		{"kind": "gold", "amount": 5, "x": DROP_SPOT.x, "y": DROP_SPOT.y},
		{"kind": "heart", "amount": 15, "x": DROP_SPOT.x + 8.0, "y": DROP_SPOT.y},
		{"kind": "confetti", "amount": 2, "x": DROP_SPOT.x, "y": DROP_SPOT.y},
	]
	var restored := FloorDrops.apply(_spawner, state)
	(
		assert_int(_spawner.live_pickups().size())
		. override_failure_message("apply() counted %d drops that were not there yet" % restored)
		. is_equal(restored)
	)
	assert_int(restored).is_equal(2)


## The window the deferred insertion left open, measured the way `SaveManager` can hit it: it
## flushes immediately on `NOTIFICATION_WM_CLOSE_REQUEST`, with no debounce to hide behind, so
## a resume followed by a window close in the same frame captured an empty container and wrote
## an empty `floor_drops` over the drops it had just restored.
func test_a_save_taken_in_the_same_frame_as_the_resume_still_carries_the_drops() -> void:
	await _drop_one_of_each()
	var state := RunState.new()
	state.floor_drops = FloorDrops.capture(_spawner)
	var saved := state.floor_drops.size()
	assert_int(saved).is_greater(0)
	EventBus.floor_started.emit(0)
	await get_tree().process_frame
	# From here to the end of the case there is no `await`: this is one frame, the frame a
	# resume and a window close can share.
	var restored := FloorDrops.apply(_spawner, state)
	var carried := FloorDrops.capture(_spawner)
	(
		assert_int(carried.size())
		. override_failure_message(
			"a save in the resume's own frame carried %d of %d drops" % [carried.size(), saved]
		)
		. is_equal(saved)
	)
	assert_int(restored).is_equal(saved)


## The bounds are per kind, and a kind with no row falls back to the amount its own class was
## built with - safe, but it would silently restore every drop of a newly added kind as one.
## `PickupSpawner.make()` is the one table of kinds; this keeps the shipped bounds level with
## it, so adding a pickup type without bounding it fails here instead of in someone's save.
func test_every_kind_the_spawner_can_make_is_bounded_by_the_shipped_limits() -> void:
	var limits := PickupLimits.load_default()
	(
		assert_object(limits)
		. override_failure_message("%s is not shipped" % PickupLimits.PATH)
		. is_not_null()
	)
	var unbounded := PackedStringArray()
	for kind: StringName in [&"gold", &"heart", &"stat_orb"]:
		# Freed by hand rather than auto_free()'d: a bare `make()` never enters the tree, and a
		# node left unparented at the end of the case is an orphan the gate counts.
		var made := PickupSpawner.make(kind)
		(
			assert_object(made)
			. override_failure_message("the spawner cannot make a %s any more" % String(kind))
			. is_not_null()
		)
		if made != null:
			made.free()
		if not limits.max_amount.has(String(kind)):
			unbounded.append(String(kind))
	(
		assert_array(unbounded)
		. override_failure_message(
			"%s has no restore bound for %s" % [PickupLimits.PATH, ", ".join(unbounded)]
		)
		. is_empty()
	)


## `PickupSpawner.live_pickups()` filters on two facts — `is_collected()` and
## `is_queued_for_deletion()` — and only the second of them was pinned. The case above waits 90
## physics frames, by which time `PickupBase._finish_collect` has already queue_freed the node,
## so dropping the `is_collected()` term from the filter left this suite green. The exposure is
## real and small: a save taken inside the 0.12 s fade would record gold the player has already
## banked, and pay it to them again on the next resume.
##
## Sampled from the `collected` signal, which `_finish_collect` emits *before* it starts the
## fade tween. At that instant the drop is collected and provably not yet queued for deletion,
## so `is_collected()` is the only guard that can keep it out of the save.
func test_a_drop_leaves_the_save_the_instant_it_is_collected() -> void:
	# One coin, not a 300-gold split: the player would sweep several of them up in the same
	# physics frame, and "how many are left" would then depend on which one homed first.
	_spawner.spawn(&"gold", DROP_SPOT, 1)
	await get_tree().process_frame
	var coins := _spawner.live_pickups()
	assert_int(coins.size()).is_equal(1)
	var coin := coins[0]
	var sampled: Dictionary = {}
	coin.collected.connect(
		func(_by: Node2D) -> void:
			sampled["collected"] = coin.is_collected()
			sampled["queued"] = coin.is_queued_for_deletion()
			sampled["live"] = _spawner.live_pickups().size()
			sampled["saved"] = FloorDrops.capture(_spawner).size()
	)

	_player.global_position = DROP_SPOT
	await _until(func() -> bool: return sampled.has("live"))

	assert_bool(bool(sampled["collected"])).is_true()
	(
		assert_bool(bool(sampled["queued"]))
		. override_failure_message("the drop was already freed, so this pins the wrong guard")
		. is_false()
	)
	(
		assert_int(int(sampled["live"]))
		. override_failure_message("a coin the player had just banked was still on the floor")
		. is_equal(0)
	)
	assert_int(int(sampled["saved"])).is_equal(0)


## Polls `done` once per physics frame until it answers true, or fails after `deadline` seconds.
## A frame count would report a different result depending on machine load (docs TESTING.md).
func _until(done: Callable, deadline: float = 5.0) -> void:
	var until := Time.get_ticks_msec() + int(deadline * 1000.0)
	while not bool(done.call()):
		if Time.get_ticks_msec() > until:
			fail("timed out after %.1fs waiting for the drop to be collected" % deadline)
			return
		await get_tree().physics_frame
