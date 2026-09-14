## Pure data output of the floor generator. Rooms scenes are built from this.
## Coordinates are in tiles (16px). Tile ids are the Tile enum, stored in a flat grid.
##
## Tile semantics are a contract other modules build on (the rooms module draws them, the
## lighting system hangs lanterns on them, `LanternAnchors`): VOID is outside the dungeon,
## never walked and never a surface; WALL is solid wherever it stands - a room's ring, a
## `RoomShape` cut-out, a template pillar, the ring around a corridor; FLOOR is a room's
## walkable interior; CORRIDOR is walkable ground outside rooms; DOOR is the one walkable
## tile of a wall ring; PIT is a hole inside a room. `is_walkable()` is the only test of
## "can stand here" and answers FLOOR, DOOR and CORRIDOR.
class_name FloorData
extends RefCounted

enum Tile { VOID, FLOOR, WALL, DOOR, PIT, CORRIDOR }

enum RoomType { START, COMBAT, ELITE, TRAP, TREASURE, ALTAR, SHOP, SHRINE, STAIRS, BOSS }


## One room.
class Room:
	extends RefCounted
	var id: int = 0
	var type: RoomType = RoomType.COMBAT
	var rect: Rect2i  # interior floor rect in tiles (walls are outside)
	var neighbors: Array[int] = []
	## Door tile positions (on the wall ring) keyed by neighbor room id.
	var doors: Dictionary = {}  # int -> Vector2i
	## Enemy spawn tiles; never within 3 tiles of a door. In ELITE rooms index 0 is the
	## elite's spot; in BOSS rooms the single entry is the boss's spot.
	var enemy_spawns: Array[Vector2i] = []
	var prop_positions: Array[Vector2i] = []
	## Prop kind per entry of prop_positions (same index), chosen from Biome.prop_kinds.
	var prop_kinds: Array[StringName] = []
	## {pos: Vector2i, kind: StringName, dir: Vector2i}. Floor traps sit on interior tiles and
	## carry dir = ZERO; wall-mounted kinds (arrow_wall) sit on the wall ring and carry the
	## inward normal to face/fire along. A `pit` kind also sets the tile to PIT.
	var trap_positions: Array[Dictionary] = []
	var fill_template: StringName = &"empty"
	## Footprint inside `rect` (`RoomShape` ids): a cut shape's corners are WALL tiles.
	var shape: StringName = &"rect"
	var palette_variant: int = 0
	var graph_distance: int = 0  # edges from start
	var cleared: bool = false

	func center() -> Vector2i:
		return rect.position + rect.size / 2

	func center_world() -> Vector2:
		return (Vector2(center()) + Vector2(0.5, 0.5)) * Layers.TILE

	## Door tiles of this room in neighbour-id order.
	func door_tiles() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		var keys := doors.keys()
		keys.sort()
		for key: int in keys:
			out.append(doors[key])
		return out

	## Wall ring rect (interior grown by one tile).
	func ring() -> Rect2i:
		return rect.grow(1)

	## Direction from a wall-ring tile towards the interior (used to aim wall-mounted traps).
	## Returns ZERO for interior tiles and tiles that do not touch the interior.
	func trap_facing(pos: Vector2i) -> Vector2i:
		if rect.has_point(pos):
			return Vector2i.ZERO
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if rect.has_point(pos + d):
				return d
		return Vector2i.ZERO


## One corridor: ordered tile path between two door tiles (door tiles excluded; path[0]
## touches from_room's door, path[-1] touches to_room's door). Paths may share tiles.
class Corridor:
	extends RefCounted
	var from_room: int = 0
	var to_room: int = 0
	var path: Array[Vector2i] = []
	## Tiles `CorridorDressing` opened beside the path (widening, chambers, alcoves).
	var extra: Array[Vector2i] = []


var seed_value: int = 0
var floor_index: int = 0
var biome: StringName = &"crypt"
## The plan this floor was laid to (`FloorArchetype` ids; empty for a fallback floor).
var archetype: StringName = &""
var width: int = 0
var height: int = 0
var tiles: PackedInt32Array = []
var rooms: Array[FloorData.Room] = []
var corridors: Array[FloorData.Corridor] = []
var start_room: int = 0
var stairs_room: int = 0
var boss_room: int = -1
## WALL tiles the lighting system may hang a lantern on (`LanternAnchors`): along wall runs,
## one every `Biome.lantern_spacing` tiles, never in or beside a doorway. Rolled last, from
## the floor's own rng, so a regenerated floor carries the same list.
var lantern_anchors: Array[Vector2i] = []
## True when the generator could not produce a real floor and returned the minimal
## start -> corridor -> stairs fallback. RunManager should treat this as a bad-luck floor
## (log it, still playable) rather than a normal one.
var is_fallback: bool = false


func get_tile(x: int, y: int) -> Tile:
	if x < 0 or y < 0 or x >= width or y >= height:
		return Tile.VOID
	return tiles[y * width + x] as Tile


func set_tile(x: int, y: int, tile: Tile) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	tiles[y * width + x] = tile


func is_walkable(x: int, y: int) -> bool:
	var t := get_tile(x, y)
	return t == Tile.FLOOR or t == Tile.DOOR or t == Tile.CORRIDOR


func room_at(pos: Vector2i) -> FloorData.Room:
	for room: FloorData.Room in rooms:
		if room.rect.has_point(pos):
			return room
	return null


func room_by_id(id: int) -> FloorData.Room:
	return rooms[id] if id >= 0 and id < rooms.size() else null


## Stable content hash for determinism tests.
func layout_hash() -> int:
	var h := hash(tiles)
	h = RunRng.hash_combine(h, hash(lantern_anchors))
	for room: FloorData.Room in rooms:
		h = RunRng.hash_combine(
			h, hash([room.id, room.type, room.rect, room.enemy_spawns, room.trap_positions])
		)
	return h


func to_ascii() -> String:
	var chars := {
		Tile.VOID: " ",
		Tile.FLOOR: ".",
		Tile.WALL: "#",
		Tile.DOOR: "+",
		Tile.PIT: "~",
		Tile.CORRIDOR: ","
	}
	var out := ""
	for y in range(height):
		for x in range(width):
			out += str(chars[get_tile(x, y)])
		out += "\n"
	return out


## Like to_ascii() but overlays rooms' content: P start, S stairs/boss centre, e enemy spawn,
## o prop, x trap, and a room type letter at each room's top-left interior tile.
func to_ascii_annotated() -> String:
	var chars := {
		Tile.VOID: " ",
		Tile.FLOOR: ".",
		Tile.WALL: "#",
		Tile.DOOR: "+",
		Tile.PIT: "~",
		Tile.CORRIDOR: ","
	}
	var type_chars := {
		RoomType.START: "P",
		RoomType.COMBAT: "C",
		RoomType.ELITE: "E",
		RoomType.TRAP: "T",
		RoomType.TREASURE: "$",
		RoomType.ALTAR: "A",
		RoomType.SHOP: "M",
		RoomType.SHRINE: "H",
		RoomType.STAIRS: "S",
		RoomType.BOSS: "B",
	}
	var overlay: Dictionary = {}
	for room: FloorData.Room in rooms:
		for p: Vector2i in room.prop_positions:
			overlay[p] = "o"
		for trap: Dictionary in room.trap_positions:
			overlay[trap["pos"]] = "x"
		for p: Vector2i in room.enemy_spawns:
			overlay[p] = "e"
		overlay[room.rect.position] = type_chars[room.type]
		if room.id == start_room:
			overlay[room.center()] = "P"
		elif room.id == stairs_room:
			overlay[room.center()] = "S"
	var out := ""
	for y in range(height):
		for x in range(width):
			var p := Vector2i(x, y)
			out += str(overlay[p]) if overlay.has(p) else str(chars[get_tile(x, y)])
		out += "\n"
	return out
