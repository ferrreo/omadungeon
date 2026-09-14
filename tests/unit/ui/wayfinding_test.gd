## The game never said what to do. There is no tutorial, the banner said "Floor 1 - Crypt" and
## stopped, and the minimap withheld room type from every room the player had not already
## entered - with the type shapes gated behind the colour-blind setting on top of that, so a
## default install drew thirteen identical rectangles and never marked the stairs until you
## were standing in them. Floor 1 was "wander until something happens" (GDD §2: "Explore -
## find stairs").
##
## The suite asserts the two answers a player needs: the objective is stated in words, and the
## room that satisfies it is marked on the map before they walk into it.
class_name WayfindingTest
extends GdUnitTestSuite

var _saved: Dictionary


func before_test() -> void:
	_saved = GameState.settings.duplicate(true)


func after_test() -> void:
	GameState.settings = _saved


func _map() -> Minimap:
	var map: Minimap = auto_free(Minimap.new())
	add_child(map)
	map.size = Vector2(80, 56)
	return map


func _hud() -> Hud:
	var hud: Hud = auto_free((load("res://src/ui/hud.tscn") as PackedScene).instantiate())
	add_child(hud)
	return hud


func _room(id: int, kind: int, visited: bool) -> Dictionary:
	return {
		"id": id,
		"rect": Rect2i(id * 10, 0, 6, 5),
		"type": kind,
		"cleared": visited,
		"visited": visited,
		"current": false,
	}


## Room centres, so an edge between two rooms is the corridor the map really feeds.
func _edge(a: int, b: int) -> Vector4i:
	return Vector4i(a * 10 + 3, 2, b * 10 + 3, 2)


## Start room entered, stairs one corridor away, a treasure room the same distance off.
func _floor_with_stairs() -> Array[Dictionary]:
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true),
		_room(1, Minimap.RoomKind.STAIRS, false),
		_room(2, Minimap.RoomKind.TREASURE, false),
	]
	return rooms


func _edges() -> Array[Vector4i]:
	var edges: Array[Vector4i] = [_edge(0, 1), _edge(0, 2)]
	return edges


# ------------------------------------------------------------------ the map


func test_the_stairs_are_marked_one_corridor_before_you_reach_them() -> void:
	var map := _map()
	var rooms := _floor_with_stairs()
	map.set_rooms(rooms, _edges())
	(
		assert_bool(map.is_goal_hint(rooms[1]))
		. override_failure_message("the stairs next door are still a blank rectangle")
		. is_true()
	)
	assert_bool(map.goal_room_known(Minimap.RoomKind.STAIRS)).is_true()


## Fog of war still does its job: the objective stops being a secret, the loot does not.
func test_a_treasure_room_next_door_stays_a_secret() -> void:
	var map := _map()
	var rooms := _floor_with_stairs()
	map.set_rooms(rooms, _edges())
	assert_bool(map.is_goal_hint(rooms[2])).is_false()


## Nothing is given away before the player has been anywhere near it: a stairs room two
## corridors out is not adjacent to anywhere they have entered.
func test_stairs_further_off_are_not_revealed() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true),
		_room(1, Minimap.RoomKind.COMBAT, false),
		_room(2, Minimap.RoomKind.STAIRS, false),
	]
	var edges: Array[Vector4i] = [_edge(0, 1), _edge(1, 2)]
	map.set_rooms(rooms, edges)
	assert_bool(map.is_goal_hint(rooms[2])).is_false()
	assert_bool(map.goal_room_known(Minimap.RoomKind.STAIRS)).is_false()


## On a boss floor the objective is the arena, and the staircase behind it does not count as
## "found" - answering a question nobody asked is how the map got useless in the first place.
func test_the_boss_floor_asks_about_the_arena_not_the_stairs() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true),
		_room(1, Minimap.RoomKind.STAIRS, false),
		_room(2, Minimap.RoomKind.BOSS, false),
	]
	var edges: Array[Vector4i] = [_edge(0, 1), _edge(1, 2)]
	map.set_rooms(rooms, edges)
	assert_bool(map.goal_room_known(Minimap.RoomKind.STAIRS)).is_true()
	assert_bool(map.goal_room_known(Minimap.RoomKind.BOSS)).is_false()


## The room-kind stamps are what tell a shop from a boss. They used to be drawn only for a
## player who had found the colour-blind setting, so a default install had no shapes at all.
func test_room_kind_shapes_do_not_depend_on_the_accessibility_setting() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true),
		_room(1, Minimap.RoomKind.SHOP, true),
		_room(2, Minimap.RoomKind.STAIRS, true),
	]
	var edges: Array[Vector4i] = [_edge(0, 1), _edge(1, 2)]
	for glyphs: bool in [false, true]:
		GameState.settings[Accessibility.SETTING_GLYPHS] = glyphs
		map.set_rooms(rooms, edges)
		map.queue_redraw()
		await get_tree().process_frame
	assert_int(Accessibility.room_shape(Minimap.RoomKind.STAIRS)).is_greater_equal(0)
	assert_int(Accessibility.room_shape(Minimap.RoomKind.SHOP)).is_greater_equal(0)
	assert_int(Accessibility.room_shape(Minimap.RoomKind.COMBAT)).is_equal(-1)


# ------------------------------------------------------------------ the words


func test_the_hud_states_the_objective_on_an_ordinary_floor() -> void:
	var hud := _hud()
	hud.set_floor(0, "Crypt")
	assert_str(hud.objective_text()).is_equal(Hud.OBJECTIVE_FIND_STAIRS)
	var rooms: Array[Dictionary] = _floor_with_stairs()
	hud.set_minimap(rooms, _edges())
	assert_str(hud.objective_text()).is_equal(Hud.OBJECTIVE_TAKE_STAIRS)


func test_the_objective_changes_on_a_boss_floor() -> void:
	var hud := _hud()
	hud.set_floor(2, "Crypt")
	assert_str(hud.objective_text()).is_equal(Hud.OBJECTIVE_FIND_BOSS)
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true), _room(1, Minimap.RoomKind.BOSS, false)
	]
	var edges: Array[Vector4i] = [_edge(0, 1)]
	hud.set_minimap(rooms, edges)
	assert_str(hud.objective_text()).is_equal(Hud.OBJECTIVE_FIGHT_BOSS)


## The objective is on screen, not only in a method: the label carries the same sentence.
func test_the_objective_line_is_on_the_hud() -> void:
	var hud := _hud()
	hud.set_floor(0, "Crypt")
	var label := hud.get_node("%ObjectiveLabel") as Label
	assert_str(label.text).is_equal(Hud.OBJECTIVE_FIND_STAIRS)
	assert_bool(label.visible).is_true()


## A first-time player gets told the loop once, on the first floor of the run.
func test_the_first_floor_hints_the_loop() -> void:
	var hud := _hud()
	EventBus.floor_started.emit(0)
	assert_str(hud.toast_widget().current_text()).is_equal(Hud.FIRST_FLOOR_HINT)


## ...and nobody is lectured on floor 4. The hint is for the first floor of a run only.
func test_a_later_floor_does_not_repeat_the_hint() -> void:
	var hud := _hud()
	EventBus.floor_started.emit(3)
	assert_str(hud.toast_widget().current_text()).is_not_equal(Hud.FIRST_FLOOR_HINT)


## The two lanes may not carry the same instruction. They did: the banner said "Clear rooms,
## find the stairs" while the permanent objective line said "Stairs found - descend", and four
## captures caught the HUD contradicting itself. The hint now explains the door rule, which the
## objective line never mentions, and the word the two used to fight over is gone from it.
func test_the_first_floor_hint_does_not_restate_the_objective() -> void:
	var objectives: Array[String] = [
		Hud.OBJECTIVE_FIND_STAIRS,
		Hud.OBJECTIVE_TAKE_STAIRS,
		Hud.OBJECTIVE_FIND_BOSS,
		Hud.OBJECTIVE_FIGHT_BOSS,
	]
	for line: String in objectives:
		assert_str(Hud.FIRST_FLOOR_HINT).is_not_equal(line)
	(
		assert_bool(Hud.FIRST_FLOOR_HINT.to_lower().contains("stairs"))
		. override_failure_message("the hint is back to duplicating the objective's own goal")
		. is_false()
	)


## ...and it is pulled off screen the moment the objective it sits beside changes state, so a
## floor where the stairs are found inside the hint's four seconds shows one instruction.
func test_finding_the_goal_room_stands_the_hint_down() -> void:
	var hud := _hud()
	EventBus.floor_started.emit(0)
	hud.set_floor(0, "Crypt")
	assert_str(hud.toast_widget().current_text()).is_equal(Hud.FIRST_FLOOR_HINT)
	hud.set_minimap(_floor_with_stairs(), _edges())
	assert_str(hud.objective_text()).is_equal(Hud.OBJECTIVE_TAKE_STAIRS)
	assert_str(hud.toast_widget().current_text()).is_not_equal(Hud.FIRST_FLOOR_HINT)


## A banner is a sentence frozen when it was pushed. A capture of floor 6 still carried the
## first-floor hint because nothing stood it down when the floor moved on.
func test_a_new_floor_stands_the_hint_down() -> void:
	var hud := _hud()
	EventBus.floor_started.emit(0)
	assert_str(hud.toast_widget().current_text()).is_equal(Hud.FIRST_FLOOR_HINT)
	EventBus.floor_started.emit(5)
	assert_str(hud.toast_widget().current_text()).is_not_equal(Hud.FIRST_FLOOR_HINT)


## The guard for what the lane is *for*: dismissing one message may not take the queue with it.
func test_dismissing_a_banner_leaves_the_other_messages_alone() -> void:
	var toast: Toast = auto_free(Toast.new())
	add_child(toast)
	toast.push("Equipped Rusty Sword")
	toast.push("-1 Might - stolen!")
	toast.dismiss("Equipped Rusty Sword")
	assert_str(toast.current_text()).is_not_equal("Equipped Rusty Sword")
	assert_int(toast.queued_count()).is_equal(1)
