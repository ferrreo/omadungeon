## End-to-end integration for the run scene's lifetime: starting a run while one is still up
## must not orphan the old Game. An orphaned Game keeps its player in group "player" and its
## enemies in group "enemy" for the rest of the process, so every later lookup by group (enemy
## targeting, pickup homing, `Interactable.dispatch`) sees a dead run's nodes.
class_name RunLifecycleIntegrationTest
extends GdUnitTestSuite

const SEED := 31337


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
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


func test_starting_a_second_run_frees_the_first_game() -> void:
	assert_bool(RunManager.new_run(SEED, &"fighter")).is_true()
	await _frames(4)
	var first := RunManager.game
	assert_object(first).is_not_null()
	assert_int(_group_size(&"player")).is_equal(1)

	assert_bool(RunManager.new_run(SEED + 1, &"ranger")).is_true()
	await _frames(4)
	assert_object(RunManager.game).is_not_same(first)
	assert_bool(is_instance_valid(first)).is_false()
	# Exactly one live run means exactly one player and only this floor's enemies.
	assert_int(_group_size(&"player")).is_equal(1)
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		assert_bool(RunManager.game.is_ancestor_of(node)).is_true()


func test_ending_a_run_leaves_no_player_or_enemy_behind() -> void:
	assert_bool(RunManager.new_run(SEED, &"fighter")).is_true()
	await _frames(4)
	assert_int(_group_size(&"player")).is_equal(1)
	RunManager.abandon_run()
	await _frames(4)
	assert_int(_group_size(&"player")).is_equal(0)
	assert_int(_group_size(&"enemy")).is_equal(0)


# --------------------- an abandoned run is not a death (owner report 11, round 4)


## Abandon Run went through the same ending path a death does, so the summary it produced said
## YOU DIED - and, because the run tally keeps the last thing that hit the player whatever the
## run ended of, named an enemy as the killer of a player nothing had killed. The two are told
## apart on the summary and in the profile now: lifetime deaths are runs - wins - abandons,
## which is a number the stats page could not work out before because nothing recorded it.
func test_abandoning_a_run_is_recorded_as_abandoned_and_not_as_a_death() -> void:
	var before := SaveManager.profile.get_counter(RunManager.ABANDON_COUNTER)
	var runs := SaveManager.profile.runs
	assert_bool(RunManager.new_run(SEED, &"fighter")).is_true()
	await _frames(4)
	RunManager.abandon_run()
	await _frames(4)

	var summary := RunManager.pending_summary
	assert_bool(bool(summary.get("victory", true))).is_false()
	assert_bool(RunSummary.is_abandoned(summary)).is_true()
	assert_str(RunSummary.headline_for(false, true)).is_equal("RUN ABANDONED")
	# It is still a run, and still worth the floor it reached; it is only not a death.
	assert_int(SaveManager.profile.runs).is_equal(runs + 1)
	assert_int(SaveManager.profile.get_counter(RunManager.ABANDON_COUNTER)).is_equal(before + 1)


## The other half of the same rule: dying still reports a death, and never raises the abandon
## counter, so the two paths cannot drift back into each other.
func test_dying_is_still_a_death_and_raises_no_abandon_counter() -> void:
	var before := SaveManager.profile.get_counter(RunManager.ABANDON_COUNTER)
	assert_bool(RunManager.new_run(SEED, &"fighter")).is_true()
	await _frames(4)
	EventBus.player_died.emit()
	await get_tree().create_timer(RunManager.DEATH_DELAY + 0.4).timeout
	await _frames(4)

	var summary := RunManager.pending_summary
	assert_bool(summary.is_empty()).is_false()
	assert_bool(bool(summary.get("victory", true))).is_false()
	assert_bool(RunSummary.is_abandoned(summary)).is_false()
	assert_int(SaveManager.profile.get_counter(RunManager.ABANDON_COUNTER)).is_equal(before)


func _group_size(group: StringName) -> int:
	var live := 0
	for node: Node in get_tree().get_nodes_in_group(group):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			live += 1
	return live


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
