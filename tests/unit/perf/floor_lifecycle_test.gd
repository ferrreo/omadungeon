## Five floors built and torn down in a row must return the process to the state it started
## in: no node, orphan or group membership left behind, and nothing still ticking.
##
## Method: one warm-up run is started and abandoned *before* the baseline census is taken.
## That is deliberate — the first run of the process creates the things that are supposed to
## outlive a floor (the tree-level FX pool, the audio player pools, registries loaded once),
## and counting those as a leak would make the test assert the opposite of what it wants.
## Everything created after the baseline belongs to a floor and has to be gone again.
class_name FloorLifecycleTest
extends GdUnitTestSuite

const SEED := 4242
## Frames waited after a teardown so queue_free()d nodes are actually deleted (a queued node
## still counts as an orphan) and any one-shot tween or timer has had its turn.
const SETTLE_FRAMES := 12

var _restore_manage_scenes: bool = true
var _restore_offers: bool = true


func before_test() -> void:
	_restore_manage_scenes = RunManager.manage_scenes
	_restore_offers = RunManager.offer_starting_passive
	RunManager.manage_scenes = false
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	await _frames(SETTLE_FRAMES)
	RunManager.manage_scenes = _restore_manage_scenes
	RunManager.offer_starting_passive = _restore_offers
	SaveManager.delete_run()


func test_five_floors_return_to_baseline() -> void:
	var budget := PerfBudget.load_default()
	await _warm_up()
	var before := NodeCensus.take(get_tree())

	assert_bool(RunManager.new_run(SEED, &"fighter")).is_true()
	await _frames(4)
	var floors_built := 1
	for i in range(budget.floor_cycles - 1):
		EventBus.floor_exit_requested.emit()
		await _frames(4)
		floors_built += 1
	assert_int(floors_built).is_equal(budget.floor_cycles)
	assert_int(RunManager.floor_index).is_equal(budget.floor_cycles - 1)

	RunManager.abandon_run()
	await _frames(SETTLE_FRAMES)
	var after := NodeCensus.take(get_tree())
	var delta := NodeCensus.diff(before, after)
	prints(
		(
			"\nfloor cycles: %d\n  before %s\n  after  %s\n  diff   %s"
			% [
				budget.floor_cycles,
				NodeCensus.describe(before),
				NodeCensus.describe(after),
				NodeCensus.describe(delta),
			]
		)
	)
	assert_int(int(delta["nodes"])).is_less_equal(budget.node_leak_tolerance)
	assert_int(int(after["orphans"])).is_less_equal(int(before["orphans"]))
	for group: StringName in NodeCensus.RUN_GROUPS:
		assert_int(int(after[group])).is_equal(0)


func test_teardown_leaves_nothing_processing() -> void:
	await _warm_up()
	assert_bool(RunManager.new_run(SEED + 1, &"ranger")).is_true()
	await _frames(6)
	assert_int(NodeCensus.group_size(get_tree(), &"enemy")).is_greater(0)
	RunManager.abandon_run()
	await _frames(SETTLE_FRAMES)
	# Nothing from the run may still be in the tree: a tween or a SceneTreeTimer that outlived
	# the scene would keep one of these alive (or resurrect it) for the rest of the process.
	assert_object(RunManager.game).is_null()
	for group: StringName in NodeCensus.RUN_GROUPS:
		assert_int(NodeCensus.group_size(get_tree(), group)).is_equal(0)
	# A second settle window catches anything that only reappears once a delayed callback runs.
	await _frames(SETTLE_FRAMES * 2)
	assert_int(NodeCensus.group_size(get_tree(), &"enemy")).is_equal(0)
	assert_int(NodeCensus.group_size(get_tree(), &"player")).is_equal(0)


## Starts and abandons one run so process-lifetime singletons exist before the baseline.
func _warm_up() -> void:
	RunManager.new_run(SEED - 1, &"fighter")
	await _frames(4)
	RunManager.abandon_run()
	await _frames(SETTLE_FRAMES)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
