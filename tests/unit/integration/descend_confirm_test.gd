## The floor exit must always be usable. Descending used to ask a player standing at the stairs
## for a confirmation press when reward rooms were still unexplored, and a staircase spends
## itself when it is used — put together, the first press once disabled the only exit. The
## confirmation is gone now (the map says what is left instead), so this suite holds the
## simpler promise: a descent with rooms unexplored goes down on the first press, the HUD's map
## is told what was left, and a staircase still cannot be used twice.
class_name DescendConfirmIntegrationTest
extends GdUnitTestSuite

const SEED := 987654
const CLASS_ID := &"fighter"


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


func test_a_descent_with_rooms_unexplored_goes_down_on_the_first_press() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	var live := RunManager.player()
	await _stand_on_the_stairs(root, live)
	assert_array(_unexplored(root)).is_not_empty()
	# The map, not the stairs, carries what is left: the HUD's minimap counts the rooms the
	# player has not entered, and the stairs prompt is one word.
	var map := (RunManager.game as Game).hud.get_node("%Minimap") as Minimap
	assert_int(map.unvisited_count()).is_greater(0)
	assert_str(map.caption_text()).contains("left")
	assert_str(root.stairs.prompt_text).is_equal(DescendNotice.DESCEND)

	# One press: down.
	assert_bool(root.stairs.interact(live)).is_true()
	await _frames(6)
	assert_int(RunManager.floor_index).is_equal(1)


func test_a_floor_with_nothing_left_descends_on_the_first_press() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	var live := RunManager.player()
	await _stand_on_the_stairs(root, live)
	_explore_everything(root)
	assert_array(_unexplored(root)).is_empty()
	assert_bool(root.stairs.interact(live)).is_true()
	await _frames(6)
	assert_int(RunManager.floor_index).is_equal(1)


func test_a_staircase_still_cannot_be_used_twice() -> void:
	# Handing the staircase back must not weaken the one-descent-per-staircase rule: that
	# guard is what stops a queued second press from skipping a whole floor and its rewards.
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	var live := RunManager.player()
	var stairs := root.stairs
	await _stand_on_the_stairs(root, live)
	_explore_everything(root)
	assert_bool(stairs.interact(live)).is_true()
	assert_int(RunManager.floor_index).is_equal(1)
	assert_bool(stairs.used).is_true()
	assert_bool(stairs.interact(live)).is_false()
	await _frames(6)
	assert_int(RunManager.floor_index).is_equal(1)


## Reward rooms of the live floor the player has not walked into yet.
static func _unexplored(root: FloorRoot) -> Array[String]:
	return DescendNotice.unexplored(RunManager.floor_data, root.visited_ids())


## Marks every room as walked into, the state the player's own entry trigger produces, so the
## descent has nothing left to warn about.
static func _explore_everything(root: FloorRoot) -> void:
	for room: RoomNode in root.rooms:
		room.visited = true


## Puts the player on the staircase and waits for its detection box to notice. Only a player
## standing there is asked to confirm, so the proximity is part of the test.
func _stand_on_the_stairs(root: FloorRoot, live: Player) -> void:
	live.global_position = root.stairs.global_position
	await _physics_frames(6)
	assert_bool(root.stairs.player_nearby()).is_true()


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame
