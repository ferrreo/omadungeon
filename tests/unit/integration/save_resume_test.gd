## End-to-end integration: Save & Quit from a live run, then Continue. The resumed run must
## rebuild the same floor layout and restore the floor index, the cleared rooms and the
## player's gold, stats and equipment.
class_name SaveResumeIntegrationTest
extends GdUnitTestSuite

const SEED := 987654
const CLASS_ID := &"ranger"
## A path no process can create, standing in for the reasons a save really fails on a player's
## machine: a full disk, a quota, a read-only home, a vanished XDG data dir.
const UNWRITABLE_RUN_PATH := "/proc/omadungeon-not-a-directory/run.json"


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	# The docs §2 passive pick has its own suite; it would open over every resume here.
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


func test_save_and_quit_then_resume_restores_the_run() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	# Move to floor 2 so the resume has a non-trivial floor index to restore.
	await _descend_one_floor()
	assert_int(RunManager.floor_index).is_equal(1)
	var root := RunManager.floor_root()
	var live := RunManager.player()
	live.add_gold(137)
	live.add_stat(&"might", 3)
	live.add_potion(2)
	var cleared_ids: Array[int] = []
	for room: RoomNode in root.rooms:
		if room.is_lockable() and not room.enemies.is_empty():
			room.force_clear(false)
			cleared_ids.append(room.id)
			if cleared_ids.size() >= 2:
				break
	await _frames(4)
	assert_array(cleared_ids).is_not_empty()
	var layout_hash := RunManager.floor_data.layout_hash()
	var gold := live.gold
	var might := live.stats.primary(&"might")
	var potions := live.potions
	var weapon := (live.equipment as Equipment).get_item(&"weapon")
	assert_object(weapon).is_not_null()
	var weapon_id := weapon.base.id

	RunManager.save_and_quit()
	await _frames(4)
	assert_bool(RunManager.is_run_active()).is_false()
	assert_bool(SaveManager.has_run()).is_true()

	assert_bool(RunManager.resume_run()).is_true()
	await _frames(6)
	assert_int(RunManager.floor_index).is_equal(1)
	assert_int(RunManager.run_seed).is_equal(SEED)
	assert_int(RunManager.floor_data.layout_hash()).is_equal(layout_hash)
	var resumed := RunManager.player()
	assert_int(resumed.gold).is_equal(gold)
	assert_int(resumed.stats.primary(&"might")).is_equal(might)
	assert_int(resumed.potions).is_equal(potions)
	var resumed_weapon := (resumed.equipment as Equipment).get_item(&"weapon")
	assert_object(resumed_weapon).is_not_null()
	assert_str(String(resumed_weapon.base.id)).is_equal(String(weapon_id))
	var resumed_root := RunManager.floor_root()
	for id: int in cleared_ids:
		var room := resumed_root.get_room(id)
		assert_object(room).is_not_null()
		assert_int(room.state).is_equal(RoomNode.State.CLEARED)
		assert_int(room.pending_enemy_count()).is_equal(0)
	var state := RunManager.build_run_state()
	for id: int in cleared_ids:
		assert_bool(state.cleared_room_ids.has(id)).is_true()


func test_resume_without_a_save_fails_cleanly() -> void:
	SaveManager.delete_run()
	assert_bool(RunManager.resume_run()).is_false()
	assert_bool(RunManager.is_run_active()).is_false()


func test_autosave_snapshot_carries_the_generation_inputs() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var state := RunManager.build_run_state()
	assert_object(state).is_not_null()
	assert_dict(state.gen_params).is_not_empty()
	assert_str(str(state.gen_params.get("biome", ""))).is_equal(String(RunManager.floor_data.biome))
	assert_int(state.run_seed).is_equal(SEED)
	assert_str(String(state.class_id)).is_equal(String(CLASS_ID))
	# The snapshot round-trips through JSON without losing the 64-bit seed.
	var restored := RunState.from_dict(state.to_dict())
	assert_object(restored).is_not_null()
	assert_int(restored.run_seed).is_equal(SEED)


func test_autosave_snapshot_carries_the_rng_stream_positions() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var state := RunManager.build_run_state()
	assert_dict(state.rng_states).is_not_empty()
	for name: StringName in RunManager.PERSISTENT_RNG_STREAMS:
		assert_bool(state.rng_states.has(name)).is_true()
	# 64-bit stream positions survive the JSON round trip (they go out as strings).
	var restored := RunState.from_dict(state.to_dict())
	assert_object(restored).is_not_null()
	for name: StringName in RunManager.PERSISTENT_RNG_STREAMS:
		assert_int(int(restored.rng_states[name])).is_equal(int(state.rng_states[name]))


func test_resume_does_not_rewind_the_loot_stream_into_a_free_reroll() -> void:
	# docs §12: resume continues the run's RNG. Without the saved stream positions, quitting
	# before opening a chest and resuming rerolls the offer from the seed, for free, forever.
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var live := RunManager.player()
	var loot := RunManager.rng.stream(&"loot")
	# Burn the stream the way a floor of chests and shop rerolls would.
	for _i in range(25):
		loot.randf()
	var position := loot.state
	var expected := _next_offer_ids(live)

	RunManager.save_and_quit()
	await _frames(4)
	assert_bool(SaveManager.has_run()).is_true()
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(6)
	var resumed := RunManager.player()
	assert_int(RunManager.rng.stream(&"loot").state).is_equal(position)
	assert_array(_next_offer_ids(resumed)).is_equal(expected)


func test_a_resumed_run_does_not_re_earn_the_gold_it_already_had() -> void:
	# The Oligarch's 150g purse is emitted again by restore_from_dict on every resume.
	assert_bool(RunManager.new_run(SEED, &"oligarch")).is_true()
	await _frames(4)
	var live := RunManager.player()
	assert_int(live.gold).is_greater(0)
	live.add_gold(60)
	await _frames(2)
	var earned := RunManager.build_run_state().gold_earned
	assert_int(earned).is_equal(60)
	# Read before Save & Quit: it frees the Game node and with it this Player.
	var purse := live.gold
	RunManager.save_and_quit()
	await _frames(4)
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(6)
	assert_int(RunManager.player().gold).is_equal(purse)
	assert_int(RunManager.build_run_state().gold_earned).is_equal(earned)


## Ability ids the next chest-style ability offer would roll, without consuming the stream
## for real: a snapshot of the stream position is taken and put back.
func _next_offer_ids(live: Player) -> Array[String]:
	var loot := RunManager.rng.stream(&"loot")
	var position := loot.state
	var slots := live.ability_slots as AbilitySlots
	var owned: Dictionary = slots.owned_tiers() if slots != null else {}
	var out: Array[String] = []
	for ability: Ability in RunManager.ability_registry.offer(loot, 3, CLASS_ID, owned):
		out.append(String(ability.id))
	loot.state = position
	return out


func test_no_snapshot_is_offered_outside_a_run() -> void:
	assert_bool(RunManager.is_run_active()).is_false()
	assert_object(RunManager.build_run_state()).is_null()


## Descends one floor. Docs §8: leaving reward rooms unexplored costs a confirmation press
## first (RunManager.DESCEND_CONFIRM_WINDOW), so a floor still holding an altar or a shop
## answers the first request with a warning toast and only the second one goes down.
func _descend_one_floor() -> void:
	var before := RunManager.floor_index
	EventBus.floor_exit_requested.emit()
	await _frames(3)
	if RunManager.floor_index == before and RunManager.is_run_active():
		EventBus.floor_exit_requested.emit()
		await _frames(6)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


# ---------------------------------------------------------------- a write that fails


## The run must outlive a failed Save & Quit. This used to be the one destructive path nobody
## confirmed: `save_run()`'s answer was discarded and the run was torn down regardless, so a
## failed write returned the player to the title with Continue greyed out and nothing on
## screen to say why. Half an hour of play, gone, silently.
func test_save_and_quit_keeps_the_run_when_the_write_fails() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var live := RunManager.player()
	live.add_gold(210)
	var gold := live.gold
	var real_path := SaveManager.run_path
	SaveManager.run_path = UNWRITABLE_RUN_PATH
	var said: Array[String] = []
	var listen := func(text: String, _duration: float) -> void: said.append(text)
	EventBus.toast.connect(listen)
	var ok := RunManager.save_and_quit()
	EventBus.toast.disconnect(listen)
	SaveManager.run_path = real_path
	await _frames(4)

	assert_bool(ok).override_failure_message("a failed save reported success").is_false()
	(
		assert_bool(RunManager.is_run_active())
		. override_failure_message("a failed save threw the run away")
		. is_true()
	)
	assert_object(RunManager.player()).is_not_null()
	assert_int(RunManager.player().gold).is_equal(gold)
	assert_object(RunManager.floor_root()).is_not_null()
	(
		assert_array(said)
		. override_failure_message("the player was told nothing about the failed save")
		. contains([RunManager.SAVE_FAILED_TEXT])
	)


## ... and the run is still savable afterwards. A failure that leaves the run in a state the
## next Save & Quit cannot write either is only a slower version of the same loss.
func test_a_run_that_survived_a_failed_save_can_still_be_saved_and_resumed() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	RunManager.player().add_gold(77)
	var gold := RunManager.player().gold
	var real_path := SaveManager.run_path
	SaveManager.run_path = UNWRITABLE_RUN_PATH
	assert_bool(RunManager.save_and_quit()).is_false()
	SaveManager.run_path = real_path
	await _frames(2)

	assert_bool(RunManager.save_and_quit()).is_true()
	await _frames(4)
	assert_bool(RunManager.is_run_active()).is_false()
	assert_bool(SaveManager.has_run()).is_true()
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(6)
	assert_int(RunManager.player().gold).is_equal(gold)


## The half the check could have broken: a save that *works* still ends the session. A
## `save_and_quit` that refused to tear down would be just as broken as one that always did.
func test_a_successful_save_and_quit_still_leaves_the_run() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	assert_bool(RunManager.save_and_quit()).is_true()
	await _frames(4)
	assert_bool(RunManager.is_run_active()).is_false()
	assert_object(RunManager.player()).is_null()
	assert_bool(SaveManager.has_run()).is_true()


## Save & Quit outside a run is a no-op that still leaves the title screen, not a failure.
func test_save_and_quit_with_no_run_reports_success() -> void:
	assert_bool(RunManager.is_run_active()).is_false()
	assert_bool(RunManager.save_and_quit()).is_true()
