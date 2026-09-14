## Hand-built FloorData layouts for the rooms tests (the generator is not needed here).
class_name RoomsTestFixtures
extends RefCounted

const ATLAS := "res://assets/tiles/crypt.png"


## Group member that exposes a zero-argument `interact()` (mimic-style interactables).
class ArityZeroInteractable:
	extends Node2D
	var used: int = 0

	func interact() -> bool:
		used += 1
		return true


## 20x16 grid, three rooms: START (0) at the top-left, COMBAT (1) top-right with a 2-tile pit,
## STAIRS (2) below the combat room. Corridors 0-1 (horizontal) and 1-2 (vertical).
static func three_rooms() -> FloorData:
	var d := FloorData.new()
	d.seed_value = 4242
	d.floor_index = 0
	d.biome = &"crypt"
	d.width = 20
	d.height = 16
	d.tiles.resize(d.width * d.height)
	d.tiles.fill(FloorData.Tile.VOID)
	var a := add_room(d, 0, FloorData.RoomType.START, Rect2i(2, 2, 5, 4))
	var b := add_room(d, 1, FloorData.RoomType.COMBAT, Rect2i(12, 2, 5, 4))
	var c := add_room(d, 2, FloorData.RoomType.STAIRS, Rect2i(12, 9, 5, 4))
	b.palette_variant = TileRamp.Variant.ACCENT_SHIFT
	b.enemy_spawns = [Vector2i(13, 3), Vector2i(15, 3)]
	b.prop_positions = [Vector2i(12, 2)]
	b.prop_kinds = [&"coffin"]
	d.set_tile(15, 5, FloorData.Tile.PIT)
	d.set_tile(16, 5, FloorData.Tile.PIT)
	connect_rooms(
		d, a, b, Vector2i(7, 3), Vector2i(11, 3), [Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3)]
	)
	connect_rooms(d, b, c, Vector2i(14, 6), Vector2i(14, 8), [Vector2i(14, 7)])
	d.start_room = 0
	d.stairs_room = 2
	d.boss_room = -1
	return d


static func add_room(
	d: FloorData, id: int, type: FloorData.RoomType, rect: Rect2i
) -> FloorData.Room:
	var room := FloorData.Room.new()
	room.id = id
	room.type = type
	room.rect = rect
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			d.set_tile(x, y, FloorData.Tile.FLOOR)
	var ring := rect.grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if d.get_tile(x, y) == FloorData.Tile.VOID:
				d.set_tile(x, y, FloorData.Tile.WALL)
	d.rooms.append(room)
	return room


static func connect_rooms(
	d: FloorData,
	a: FloorData.Room,
	b: FloorData.Room,
	door_a: Vector2i,
	door_b: Vector2i,
	path: Array[Vector2i]
) -> void:
	a.neighbors.append(b.id)
	b.neighbors.append(a.id)
	a.doors[b.id] = door_a
	b.doors[a.id] = door_b
	d.set_tile(door_a.x, door_a.y, FloorData.Tile.DOOR)
	d.set_tile(door_b.x, door_b.y, FloorData.Tile.DOOR)
	for p: Vector2i in path:
		d.set_tile(p.x, p.y, FloorData.Tile.CORRIDOR)
	for p: Vector2i in path:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if d.get_tile(p.x + dx, p.y + dy) == FloorData.Tile.VOID:
					d.set_tile(p.x + dx, p.y + dy, FloorData.Tile.WALL)
	var corridor := FloorData.Corridor.new()
	corridor.from_room = a.id
	corridor.to_room = b.id
	corridor.path = path.duplicate()
	d.corridors.append(corridor)


static func count_tiles(d: FloorData, kinds: Array[FloorData.Tile]) -> int:
	var n := 0
	for y in range(d.height):
		for x in range(d.width):
			if kinds.has(d.get_tile(x, y)):
				n += 1
	return n


## Bare Interactable with an explicit prompt and detection size (prompt arbitration tests).
static func make_interactable(text: String, size: float = 60.0) -> Interactable:
	var it := Interactable.new()
	it.prompt_text = text
	it.detect_size = Vector2(size, size)
	return it


## Minimal player stand-in: body on Layers.PLAYER in group "player".
static func make_player() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = "FakePlayer"
	body.add_to_group(&"player")
	body.collision_layer = Layers.PLAYER
	body.collision_mask = Layers.WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 10)
	shape.shape = rect
	body.add_child(shape)
	return body
