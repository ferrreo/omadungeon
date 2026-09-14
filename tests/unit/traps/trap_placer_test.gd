## TrapPlacer: FloorData trap_positions + PIT tiles -> live trap nodes under the floor root.
class_name TrapPlacerTest
extends GdUnitTestSuite

const ROOM_RECT := Rect2i(2, 2, 7, 5)


## Stand-in for FloorRoot: HazardSpawner only needs a Node2D carrying `data`.
class FakeFloorRoot:
	extends Node2D
	var data: FloorData


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## 16x12 grid with one room, four generator traps and a 2-tile pit run.
func _floor() -> FloorData:
	var data := FloorData.new()
	data.biome = &"void"
	data.width = 16
	data.height = 12
	data.tiles.resize(data.width * data.height)
	data.tiles.fill(FloorData.Tile.VOID)
	var room := FloorData.Room.new()
	room.id = 0
	room.type = FloorData.RoomType.TRAP
	room.rect = ROOM_RECT
	for y in range(ROOM_RECT.position.y, ROOM_RECT.end.y):
		for x in range(ROOM_RECT.position.x, ROOM_RECT.end.x):
			data.set_tile(x, y, FloorData.Tile.FLOOR)
	var ring := ROOM_RECT.grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if data.get_tile(x, y) == FloorData.Tile.VOID:
				data.set_tile(x, y, FloorData.Tile.WALL)
	room.trap_positions = [
		{"pos": Vector2i(4, 3), "kind": &"spike_floor", "dir": Vector2i.ZERO},
		{"pos": Vector2i(1, 3), "kind": &"arrow_wall", "dir": Vector2i(1, 0)},
		{"pos": Vector2i(6, 4), "kind": &"pressure_plate", "dir": Vector2i.ZERO},
		{"pos": Vector2i(3, 5), "kind": &"laser_grid", "dir": Vector2i.ZERO},
	]
	data.rooms.append(room)
	data.set_tile(7, 2, FloorData.Tile.PIT)
	data.set_tile(8, 2, FloorData.Tile.PIT)
	return data


func _populate(parent: Node2D) -> Array[TrapBase]:
	return TrapPlacer.populate(_floor(), parent, TrapRegistry.load_default())


func _first(traps: Array[TrapBase], kind: StringName) -> TrapBase:
	for trap: TrapBase in traps:
		if trap.kind == kind:
			return trap
	return null


func test_every_entry_becomes_a_trap_node() -> void:
	var parent := auto_free(Node2D.new()) as Node2D
	add_child(parent)
	var traps := _populate(parent)
	await _frames(2)
	assert_int(traps.size()).is_equal(5)  # 4 entries + 1 pit run
	for trap: TrapBase in traps:
		assert_object(trap.get_parent()).is_same(parent)
		assert_bool(trap.is_in_group(&"trap")).is_true()
		assert_int(trap.room_id).is_equal(0)
		assert_bool(trap.is_in_group(TrapBase.room_group(0))).is_true()
	assert_vector(_first(traps, &"spike_floor").global_position).is_equal(
		TrapPlacer.tile_center(Vector2i(4, 3))
	)


func test_arrow_wall_faces_into_the_room() -> void:
	var parent := auto_free(Node2D.new()) as Node2D
	add_child(parent)
	var wall := _first(_populate(parent), &"arrow_wall") as ArrowWall
	await _frames(2)
	assert_object(wall).is_not_null()
	assert_vector(wall.direction).is_equal(Vector2.RIGHT)


func test_pit_run_becomes_one_sized_pit() -> void:
	var parent := auto_free(Node2D.new()) as Node2D
	add_child(parent)
	var pit := _first(_populate(parent), &"pit") as Pit
	await _frames(2)
	assert_object(pit).is_not_null()
	assert_vector(pit.size).is_equal(Vector2(32.0, 16.0))
	assert_vector(pit.global_position).is_equal(Vector2(128.0, 40.0))


func test_plate_controls_the_room_trap_group() -> void:
	var parent := auto_free(Node2D.new()) as Node2D
	add_child(parent)
	var traps := _populate(parent)
	await _frames(2)
	var plate := _first(traps, &"pressure_plate") as PressurePlate
	var spike := _first(traps, &"spike_floor")
	assert_str(String(plate.plate_id)).is_equal("room0_plate0")
	assert_str(String(plate.controlled_group())).is_equal(String(TrapBase.room_group(0)))
	plate.press()
	assert_int(spike.state).is_equal(TrapBase.State.TELEGRAPH)


func test_laser_gets_a_beam_across_the_room() -> void:
	var parent := auto_free(Node2D.new()) as Node2D
	add_child(parent)
	var laser := _first(_populate(parent), &"laser_grid") as LaserGrid
	await _frames(2)
	assert_object(laser).is_not_null()
	assert_bool(laser.end_offset.length() >= float(Layers.TILE)).is_true()


func test_hazard_spawner_places_floor_traps_for_a_floor_root() -> void:
	var root := auto_free(FakeFloorRoot.new()) as FakeFloorRoot
	root.name = "FloorRoot"
	root.data = _floor()
	add_child(root)
	var spawner := auto_free(HazardSpawner.new()) as HazardSpawner
	add_child(spawner)
	spawner.parent_node = root
	await _frames(2)
	assert_int(spawner.floor_traps().size()).is_equal(5)
	spawner.parent_node = root  # idempotent per floor root
	assert_int(spawner.floor_traps().size()).is_equal(5)
	# Hazards still land under the same parent.
	var hazard := spawner.spawn(&"kernel_spike", Vector2(64.0, 64.0), 0.4)
	assert_object(hazard.get_parent()).is_same(root)


func test_hazard_spawner_parent_node_beats_parent_path() -> void:
	var path_parent := auto_free(Node2D.new()) as Node2D
	path_parent.name = "PathParent"
	add_child(path_parent)
	var live := auto_free(Node2D.new()) as Node2D
	live.name = "LiveParent"
	add_child(live)
	var spawner := auto_free(HazardSpawner.new()) as HazardSpawner
	add_child(spawner)
	spawner.parent_path = spawner.get_path_to(path_parent)
	assert_object(spawner.spawn_parent()).is_same(path_parent)
	spawner.parent_node = live
	assert_object(spawner.spawn_parent()).is_same(live)
	var hazard := spawner.spawn(&"ricer_trap", Vector2(10.0, 10.0), 0.3)
	assert_object(hazard.get_parent()).is_same(live)
