class_name RoomTest
extends GdUnitTestSuite

var _root: FloorRoot
var _player: CharacterBody2D
var _locked: Array[int] = []
var _cleared: Array[int] = []
var _entered: Array[int] = []
var _on_locked: Callable
var _on_cleared: Callable
var _on_entered: Callable


func before_test() -> void:
	_locked.clear()
	_cleared.clear()
	_entered.clear()
	_on_locked = func(id: int) -> void: _locked.append(id)
	_on_cleared = func(id: int) -> void: _cleared.append(id)
	_on_entered = func(id: int) -> void: _entered.append(id)
	EventBus.room_locked.connect(_on_locked)
	EventBus.room_cleared.connect(_on_cleared)
	EventBus.room_entered.connect(_on_entered)
	_root = auto_free(FloorRoot.new())
	add_child(_root)
	_root.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	_player = auto_free(RoomsTestFixtures.make_player())
	_player.position = Vector2(-200, -200)
	add_child(_player)


func after_test() -> void:
	EventBus.room_locked.disconnect(_on_locked)
	EventBus.room_cleared.disconnect(_on_cleared)
	EventBus.room_entered.disconnect(_on_entered)


func _settle(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().physics_frame


func _make_enemy() -> Entity:
	var e: Entity = auto_free(Entity.new())
	e.team = Layers.Team.ENEMY
	add_child(e)
	return e


func test_floor_root_layout() -> void:
	assert_int(_root.rooms.size()).is_equal(3)
	assert_object(_root.stairs).is_not_null()
	assert_that(_root.player_spawn).is_equal(_root.data.rooms[0].center_world())
	assert_that(_root.camera_limits()).is_equal(Rect2(0, 0, 20 * 16, 16 * 16))
	assert_int(_root.get_room(1).doors.size()).is_equal(2)
	assert_int(_root.get_room(0).doors.size()).is_equal(1)
	assert_int(_root.props.size()).is_equal(1)
	assert_bool(_root.get_room(0).is_lockable()).is_false()
	assert_bool(_root.get_room(1).is_lockable()).is_true()
	assert_bool(_root.get_room(2).is_lockable()).is_false()
	for door: Door in _root.get_room(1).doors:
		assert_bool(door.is_open).is_true()
	assert_object(_root.room_at_world(_root.data.rooms[1].center_world())).is_same(
		_root.get_room(1)
	)


func test_combat_room_locks_and_clears() -> void:
	var room := _root.get_room(1)
	var enemies: Array[Node2D] = [_make_enemy(), _make_enemy()]
	room.populate(enemies)
	assert_int(room.pending_enemy_count()).is_equal(2)
	assert_int(room.state).is_equal(RoomNode.State.UNVISITED)
	_player.global_position = room.center_world()
	await _settle()
	assert_int(room.state).is_equal(RoomNode.State.ACTIVE)
	assert_bool(room.is_locked()).is_true()
	assert_array(_locked).contains_exactly([1])
	assert_array(_entered).contains_exactly([1])
	assert_int(_root.current_room_id).is_equal(1)
	for door: Door in room.doors:
		assert_bool(door.is_open).is_false()
		assert_int(door.collision_layer).is_equal(Layers.WORLD)
	EventBus.enemy_died.emit(enemies[0], null)
	assert_int(room.state).is_equal(RoomNode.State.ACTIVE)
	assert_int(room.pending_enemy_count()).is_equal(1)
	EventBus.enemy_died.emit(enemies[1], null)
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)
	assert_array(_cleared).contains_exactly([1])
	for door: Door in room.doors:
		assert_bool(door.is_open).is_true()
		assert_int(door.collision_layer).is_equal(0)
	await _settle(2)
	assert_object(room.chest).is_not_null()
	assert_bool(room.chest.is_inside_tree()).is_true()
	assert_that(room.chest.position).is_equal(room.tile_to_local(room.data.center()))
	assert_array(_root.cleared_ids()).contains_exactly([1])
	# Re-entering a cleared room reports entry but never re-locks.
	_player.global_position = Vector2(-200, -200)
	await _settle()
	_player.global_position = room.center_world()
	await _settle()
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)
	assert_array(_locked).contains_exactly([1])
	assert_int(_entered.size()).is_equal(2)


func test_entity_death_signal_also_counts() -> void:
	var room := _root.get_room(1)
	var enemy := _make_enemy()
	room.populate([enemy])
	_player.global_position = room.center_world()
	await _settle()
	assert_int(room.state).is_equal(RoomNode.State.ACTIVE)
	enemy.health.take_damage(
		DamageInfo.create(9999.0, [DamageInfo.TAG_TRUE], null, Layers.Team.PLAYER)
	)
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)


func test_populate_after_entry_locks() -> void:
	var room := _root.get_room(1)
	_player.global_position = room.center_world()
	await _settle()
	assert_int(room.state).is_equal(RoomNode.State.UNVISITED)
	assert_bool(room.player_inside).is_true()
	room.populate([_make_enemy()])
	assert_int(room.state).is_equal(RoomNode.State.ACTIVE)
	assert_array(_locked).contains_exactly([1])


func test_never_lock_rooms() -> void:
	var start := _root.get_room(0)
	start.populate([_make_enemy()])
	_player.global_position = start.center_world()
	await _settle()
	assert_int(start.state).is_equal(RoomNode.State.CLEARED)
	assert_array(_locked).is_empty()
	assert_array(_cleared).is_empty()
	assert_array(_entered).contains_exactly([0])
	assert_array(_root.visited_ids()).contains_exactly([0])


func test_empty_lockable_room_clears_on_entry() -> void:
	var room := _root.get_room(1)
	var empty: Array[Node2D] = []
	room.populate(empty)
	assert_int(room.state).is_equal(RoomNode.State.UNVISITED)
	_player.global_position = room.center_world()
	await _settle()
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)
	assert_array(_cleared).contains_exactly([1])
	assert_array(_locked).is_empty()
	await _settle(2)
	# Nothing was ever fought here, so no reward chest is handed out.
	assert_object(room.chest).is_null()


func test_enemies_killed_before_entry_clear_the_room() -> void:
	var room := _root.get_room(1)
	var enemies: Array[Node2D] = [_make_enemy(), _make_enemy()]
	room.populate(enemies)
	EventBus.enemy_died.emit(enemies[0], null)
	EventBus.enemy_died.emit(enemies[1], null)
	assert_int(room.state).is_equal(RoomNode.State.UNVISITED)
	assert_array(_cleared).is_empty()
	_player.global_position = room.center_world()
	await _settle()
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)
	assert_array(_cleared).contains_exactly([1])
	await _settle(2)
	assert_object(room.chest).is_not_null()


func test_chest_kind_is_stable_per_room() -> void:
	var room := _root.get_room(1)
	var kind := room.chest_kind
	var other: FloorRoot = auto_free(FloorRoot.new())
	add_child(other)
	other.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	assert_int(other.get_room(1).chest_kind).is_equal(kind)
	# Breaking props first must not shift the chest kind.
	for prop: Prop in other.props:
		for _hit in range(2):
			prop.take_hit(DamageInfo.create(9.0, [DamageInfo.TAG_TRUE], null, Layers.Team.PLAYER))
	var third: FloorRoot = auto_free(FloorRoot.new())
	add_child(third)
	third.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	assert_int(third.get_room(1).chest_kind).is_equal(kind)


func test_room_entry_position_is_inside_the_room() -> void:
	var room := _root.get_room(1)
	var pos := _root.room_entry_position(1)
	var tile := Vector2i((pos / Layers.TILE).floor())
	assert_bool(room.data.rect.has_point(tile)).is_true()
	assert_that(_root.room_entry_position(99)).is_equal(_root.player_spawn_position())


func test_mark_cleared_skips_the_chest() -> void:
	_root.mark_cleared(1)
	await _settle(2)
	var room := _root.get_room(1)
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)
	assert_object(room.chest).is_null()
	assert_array(_cleared).contains_exactly([1])
	for door: Door in room.doors:
		assert_bool(door.is_open).is_true()


func test_chest_avoids_blocked_center() -> void:
	var room := _root.get_room(1)
	room.blocked_tiles[room.data.center()] = true
	var tile := room.free_tile_near_center()
	assert_that(tile).is_not_equal(room.data.center())
	assert_bool(room.data.rect.has_point(tile)).is_true()
	var delta := tile - room.data.center()
	assert_int(absi(delta.x) + absi(delta.y)).is_equal(1)


func test_minimap_model_from_root() -> void:
	var rooms := _root.minimap_rooms()
	assert_int(rooms.size()).is_equal(3)
	assert_bool(bool(rooms[0]["current"])).is_true()
	assert_bool(bool(rooms[1]["cleared"])).is_false()
	assert_int(_root.minimap_edges().size()).is_equal(2)


func test_navigation_path_between_rooms() -> void:
	# The NavigationServer map sync is asynchronous and load-dependent, so a fixed frame count
	# is not a wait: under load it returns an empty path, the size assert fails and the
	# following index raises a second, bogus runtime error on top of it.
	var baked := await _root.await_nav_ready(10.0)
	assert_bool(baked).override_failure_message("nav map never baked within 10 s").is_true()
	assert_int(_root.nav_region.navigation_polygon.get_polygon_count()).is_greater(0)
	if not baked:
		return
	var map := _root.get_world_2d().navigation_map
	var from := _root.data.rooms[0].center_world()
	var to := _root.data.rooms[2].center_world()
	var path := NavigationServer2D.map_get_path(map, from, to, true)
	assert_int(path.size()).is_greater(2)
	if path.size() < 2:
		return
	assert_float(path[path.size() - 1].distance_to(to)).is_less(8.0)
	assert_float(path[0].distance_to(from)).is_less(8.0)


## The property the poll above must not quietly destroy. A wait is only worth having if it can
## still say no: an unbuilt floor must report `nav_ready() == false` and `await_nav_ready()`
## must return false at its deadline rather than hanging or claiming success.
func test_nav_ready_says_no_for_an_unbuilt_floor() -> void:
	var fresh := auto_free(FloorRoot.new()) as FloorRoot
	assert_bool(fresh.nav_ready()).is_false()
	add_child(fresh)
	assert_bool(fresh.nav_ready()).is_false()
	var start := Time.get_ticks_msec()
	var baked := await fresh.await_nav_ready(0.15)
	assert_bool(baked).is_false()
	assert_int(Time.get_ticks_msec() - start).is_less(5000)
	# ... and it must still say yes for a floor that really did bake.
	assert_bool(await _root.await_nav_ready(10.0)).is_true()
