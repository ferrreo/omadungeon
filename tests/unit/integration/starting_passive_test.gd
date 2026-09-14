## End-to-end integration for the docs §2 step "Pick 1 starting passive": the run opens on a
## passive choice, the pick lands in a passive slot, the choice cannot be skipped away, and it
## is part of the seed rather than of the wall clock. `manage_scenes` is off so the SceneTree's
## `current_scene` (the gdUnit runner) is never swapped out.
class_name StartingPassiveIntegrationTest
extends GdUnitTestSuite

const SEED := 31337
const CLASS_ID := &"fighter"


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	RunManager.offer_starting_passive = true
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


func test_a_run_opens_on_a_choice_of_starting_passives() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var view := RunManager.game as Game
	assert_bool(view.chest_ui.is_open()).is_true()
	assert_int(view.chest_ui.card_count()).is_greater(1)
	assert_int(view.chest_ui.card_count()).is_less_equal(StartingPassive.COUNT)
	# Only passives: the innate and the class active are granted, not chosen.
	for offer: Variant in _offers():
		assert_object(offer).is_instanceof(PassiveAbility)


func test_taking_the_starting_passive_fills_a_passive_slot() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var live := RunManager.player()
	var slots := live.ability_slots as AbilitySlots
	var before := _passive_ids(slots)
	var picked := String((_offers()[0] as Ability).id)
	var view := RunManager.game as Game
	view.chest_ui.select(0)
	view.chest_ui.activate()
	await _frames(4)
	assert_bool(view.chest_ui.is_open()).is_false()
	var after := _passive_ids(slots)
	assert_int(after.size()).is_equal(before.size() + 1)
	assert_bool(after.has(picked)).is_true()
	# The pick is over: the floor is playable and nothing is still pending.
	assert_bool(RunManager.is_run_active()).is_true()
	assert_object(RunManager.floor_root()).is_not_null()


func test_the_starting_passive_cannot_be_skipped() -> void:
	# docs §2 makes this a choice, not an option; skipping must not start floor 1 with two
	# empty passive slots (nor pay the chest skip bonus).
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var live := RunManager.player()
	var gold_before := live.gold
	var view := RunManager.game as Game
	var skip := view.chest_ui.find_child("Skip", true, false) as Button
	assert_object(skip).is_not_null()
	skip.pressed.emit()
	await _frames(4)
	assert_bool(view.chest_ui.is_open()).is_true()
	assert_int(view.chest_ui.card_count()).is_greater(1)
	assert_int(live.gold).is_equal(gold_before)


func test_the_offer_is_seeded_and_differs_between_seeds() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var first := _offer_ids()
	RunManager.abandon_run()
	await _frames(4)

	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	assert_array(_offer_ids()).is_equal(first)
	RunManager.abandon_run()
	await _frames(4)

	# A different seed is a different opening decision, so the class does not play out the
	# same way every run (the point of the step).
	var differing := 0
	for offset in range(1, 6):
		assert_bool(RunManager.new_run(SEED + offset * 977, CLASS_ID)).is_true()
		await _frames(6)
		if _offer_ids() != first:
			differing += 1
		RunManager.abandon_run()
		await _frames(4)
	assert_int(differing).is_greater(0)


func test_the_scenario_driver_leaves_the_picker_out_of_rendered_checks() -> void:
	# tools/run-scenario.sh captures the floor, combat, the chest and the pause menu; a modal
	# on the first frame of every run would cover all of them.
	RunManager.offer_starting_passive = false
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var view := RunManager.game as Game
	assert_bool(view.chest_ui.is_open()).is_false()


## Closing the window during the mandatory pick used to lose it for good: `new_run` autosaves
## before the picker opens, `SaveManager` flushes that snapshot on WM_CLOSE even though the
## tree is paused, and `resume_run` never re-offered the choice. The run came back with two
## empty passive slots and no way to fill them.
func test_a_run_saved_during_the_pick_is_still_owed_it_on_resume() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var view := RunManager.game as Game
	assert_bool(view.chest_ui.is_open()).is_true()
	var slots := (RunManager.player().ability_slots) as AbilitySlots
	assert_array(_passive_ids(slots)).is_empty()
	# What a window-close flush writes while the cards are still up.
	SaveManager.save_run(RunManager.build_run_state())
	var on_disk := SaveManager.load_run()
	assert_object(on_disk).is_not_null()
	assert_bool(on_disk.starting_passive_pending).is_true()

	# The process dies here. Resuming has to hand the pick back, not skip it.
	RunManager.save_and_quit()
	await _frames(4)
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(8)
	var resumed := RunManager.game as Game
	assert_bool(resumed.chest_ui.is_open()).is_true()
	assert_int(resumed.chest_ui.card_count()).is_greater(1)
	for offer: Variant in _offers():
		assert_object(offer).is_instanceof(PassiveAbility)

	# Taking it now settles the debt: the next snapshot no longer owes a pick.
	resumed.chest_ui.select(0)
	resumed.chest_ui.activate()
	await _frames(4)
	assert_int(_passive_ids(RunManager.player().ability_slots as AbilitySlots).size()).is_equal(1)
	SaveManager.save_run(RunManager.build_run_state())
	assert_bool(SaveManager.load_run().starting_passive_pending).is_false()


## The opening pick is the third board of the same shape, and it was re-dealt on every resume:
## `resume_run` puts the loot stream back where the save left it — past the roll — and then
## rolled again. Closing the window on the mandatory pick until a build-defining passive turned
## up was an unlimited free reroll of the run's first decision, and the picker's own Reroll
## button charges gold for that (docs §2, §8).
func test_the_opening_pick_resumes_as_the_same_cards() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var board := _offer_ids()
	assert_array(board).is_not_empty()

	for cycle in range(3):
		RunManager.save_and_quit()
		await _frames(4)
		assert_bool(RunManager.resume_run()).is_true()
		await _frames(8)
		assert_bool((RunManager.game as Game).chest_ui.is_open()).is_true()
		(
			assert_array(_offer_ids())
			. override_failure_message("Continue number %d dealt a new opening board" % (cycle + 1))
			. is_equal(board)
		)

	# And it is still the pick it always was: taking one fills a passive slot, and the save
	# stops owing both the pick and a board to make it on.
	var view := RunManager.game as Game
	view.chest_ui.select(0)
	view.chest_ui.activate()
	await _frames(4)
	var slots := RunManager.player().ability_slots as AbilitySlots
	assert_int(_passive_ids(slots).size()).is_equal(1)
	assert_bool(SaveManager.save_run(RunManager.build_run_state())).is_true()
	var on_disk := SaveManager.load_run()
	assert_bool(on_disk.starting_passive_pending).is_false()
	assert_array(on_disk.offer_boards).is_empty()


## Paying for a reroll of the opening board buys that board, not a fresh deal on the way back.
func test_a_rerolled_opening_pick_resumes_as_the_board_that_was_paid_for() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var live := RunManager.player()
	live.add_gold(500)
	var view := RunManager.game as Game
	var gold := live.gold
	var cost := int(view.chest_ui.context.get("reroll_cost", 0))
	assert_int(cost).is_greater(0)
	view.chest_ui.rerolled.emit()
	await _frames(4)
	var paid := _offer_ids()
	assert_array(paid).is_not_empty()
	assert_int(RunManager.player().gold).is_equal(gold - cost)

	RunManager.save_and_quit()
	await _frames(4)
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(8)

	(
		assert_array(_offer_ids())
		. override_failure_message("the resume handed back a board the player had not paid for")
		. is_equal(paid)
	)
	# ... and the price the next reroll costs is not refunded along the way (docs §8).
	var resumed_ui := (RunManager.game as Game).chest_ui
	assert_int(int(resumed_ui.context.get("reroll_cost", 0))).is_greater(cost)


## A run saved after the pick resolved must not re-open the picker on every resume.
func test_a_resume_after_the_pick_does_not_ask_again() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(6)
	var view := RunManager.game as Game
	view.chest_ui.select(0)
	view.chest_ui.activate()
	await _frames(4)
	RunManager.save_and_quit()
	await _frames(4)
	assert_bool(RunManager.resume_run()).is_true()
	await _frames(8)
	assert_bool((RunManager.game as Game).chest_ui.is_open()).is_false()


## The offers the picker is showing right now.
func _offers() -> Array:
	var view := RunManager.game as Game
	return view.chest_ui.offers


func _offer_ids() -> Array[String]:
	var out: Array[String] = []
	for offer: Variant in _offers():
		if offer is Ability:
			out.append(String((offer as Ability).id))
	return out


## Ids in the two real passive slots (innates are granted outside them).
static func _passive_ids(slots: AbilitySlots) -> Array[String]:
	var out: Array[String] = []
	if slots == null:
		return out
	for index in range(AbilitySlots.SLOT_COUNT):
		var ability := slots.get_ability(index)
		if ability != null and ability.kind == Ability.Kind.PASSIVE:
			out.append(String(ability.id))
	return out


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
