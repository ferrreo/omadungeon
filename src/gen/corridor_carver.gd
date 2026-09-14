## Carves 1-tile corridors between rooms (docs 5.1 #3). For every graph edge a door tile is
## chosen on each room's wall ring (facing the other room), then an AStarGrid2D path is found
## through the void with per-tile random weights scaled by `corridor_wiggle` (0 = clean
## L-shapes, 1 = winding). Room tiles are solid so corridors never cut through rooms. Every
## finished corridor is *sealed*: its tiles and its two door tiles mark their void neighbours
## solid, so a later corridor can neither merge with it nor run beside one of its doors. That
## keeps the walkable topology identical to the room graph (no hidden room-to-room shortcuts).
## A door only ever opens onto floor: the tile behind it must be FLOOR, so a room's shape
## cut-outs (`RoomShape`) never get a door. Once every corridor is carved `CorridorDressing`
## widens some and gives others chambers and alcoves, under the same no-shortcut rule.
## Finally every void tile touching a corridor becomes WALL.
class_name CorridorCarver
extends RefCounted

const WEIGHT_BASE := 1.0
const WEIGHT_JITTER := 6.0
const WEIGHT_NEAR_ROOM := 2.5
## Minimum distance between two doors on the same room ring.
const MIN_DOOR_SPACING := 2


## Carves every required edge and as many optional (loop) edges as fit. Returns false when a
## required corridor could not be routed (the generator treats that as a failed attempt).
## Optional edges that could not be routed are simply skipped; the caller detects them by the
## missing door entry and prunes them from the graph.
static func carve_all(
	data: FloorData,
	required_edges: Array[Vector2i],
	optional_edges: Array[Vector2i],
	params: GenParams,
	rng: RandomNumberGenerator,
	arch: FloorArchetype = null
) -> bool:
	var astar := _build_astar(data, params, rng)
	var owners: Dictionary = {}
	for edge: Vector2i in required_edges:
		if not _carve_edge(data, astar, owners, edge.x, edge.y, params, rng):
			return false
	for edge: Vector2i in optional_edges:
		_carve_edge(data, astar, owners, edge.x, edge.y, params, rng)
	CorridorDressing.apply(data, owners, arch, rng)
	_ring_corridors(data)
	return true


## Door tile on `room`'s wall ring facing `other`, or Vector2i(-1, -1) if the ring is full.
## When `astar` is given, tiles already reserved by another corridor are not valid approaches.
static func pick_door(
	data: FloorData,
	room: FloorData.Room,
	other: FloorData.Room,
	wiggle: float,
	rng: RandomNumberGenerator,
	astar: AStarGrid2D = null
) -> Vector2i:
	var delta := other.center() - room.center()
	var sides: Array[Vector2i] = []
	var primary := (
		Vector2i(signi(delta.x), 0)
		if absi(delta.x) >= absi(delta.y)
		else Vector2i(0, signi(delta.y))
	)
	if primary == Vector2i.ZERO:
		primary = Vector2i(1, 0)
	var secondary := (
		Vector2i(0, signi(delta.y) if delta.y != 0 else 1)
		if primary.x != 0
		else Vector2i(signi(delta.x) if delta.x != 0 else 1, 0)
	)
	sides.append(primary)
	sides.append(secondary)
	sides.append(-secondary)
	sides.append(-primary)
	var jitter := int(round(wiggle * 3.0))
	for side: Vector2i in sides:
		var door := _door_on_side(data, room, other, side, jitter, rng, astar)
		if door.x >= 0:
			return door
	return Vector2i(-1, -1)


static func _door_on_side(
	data: FloorData,
	room: FloorData.Room,
	other: FloorData.Room,
	side: Vector2i,
	jitter: int,
	rng: RandomNumberGenerator,
	astar: AStarGrid2D
) -> Vector2i:
	var rect := room.rect
	var along_min: int
	var along_max: int
	var target: int
	if side.x != 0:
		along_min = rect.position.y
		along_max = rect.end.y - 1
		target = other.center().y
	else:
		along_min = rect.position.x
		along_max = rect.end.x - 1
		target = other.center().x
	# Keep doors off the ring corners so door frames and corridor mouths read cleanly.
	if along_max - along_min >= 4:
		along_min += 1
		along_max -= 1
	var start := clampi(target + rng.randi_range(-jitter, jitter), along_min, along_max)
	var span := along_max - along_min + 1
	for step in range(span):
		for sign_dir: int in [1, -1]:
			var along := start + step * sign_dir
			if along < along_min or along > along_max:
				continue
			var door := _door_pos(rect, side, along)
			if _door_ok(data, room, door, side, astar):
				return door
			if step == 0:
				break
	return Vector2i(-1, -1)


static func _door_pos(rect: Rect2i, side: Vector2i, along: int) -> Vector2i:
	if side.x > 0:
		return Vector2i(rect.end.x, along)
	if side.x < 0:
		return Vector2i(rect.position.x - 1, along)
	if side.y > 0:
		return Vector2i(along, rect.end.y)
	return Vector2i(along, rect.position.y - 1)


static func _door_ok(
	data: FloorData, room: FloorData.Room, door: Vector2i, side: Vector2i, astar: AStarGrid2D
) -> bool:
	if data.get_tile(door.x, door.y) != FloorData.Tile.WALL:
		return false
	var behind := door - side
	if data.get_tile(behind.x, behind.y) != FloorData.Tile.FLOOR:
		return false
	var approach := door + side
	if (
		approach.x <= 0
		or approach.y <= 0
		or approach.x >= data.width - 1
		or approach.y >= data.height - 1
	):
		return false
	if data.get_tile(approach.x, approach.y) != FloorData.Tile.VOID:
		return false
	if astar != null and astar.is_point_solid(approach):
		return false
	for existing: Vector2i in room.doors.values():
		if GenUtil.chebyshev(existing, door) < MIN_DOOR_SPACING:
			return false
	return true


static func _build_astar(
	data: FloorData, params: GenParams, rng: RandomNumberGenerator
) -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, data.width, data.height)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.jumping_enabled = false
	astar.update()
	var wiggle := clampf(params.corridor_wiggle, 0.0, 1.0)
	for y in range(data.height):
		for x in range(data.width):
			var p := Vector2i(x, y)
			var t := data.get_tile(x, y)
			var border := x == 0 or y == 0 or x == data.width - 1 or y == data.height - 1
			if border or t != FloorData.Tile.VOID:
				astar.set_point_solid(p, true)
				continue
			var r := rng.randf()
			var w := WEIGHT_BASE + r * r * wiggle * WEIGHT_JITTER
			if _touches_wall(data, p):
				w *= WEIGHT_NEAR_ROOM
			astar.set_point_weight_scale(p, w)
	return astar


static func _touches_wall(data: FloorData, p: Vector2i) -> bool:
	for d: Vector2i in GenUtil.DIRS4:
		if data.get_tile(p.x + d.x, p.y + d.y) == FloorData.Tile.WALL:
			return true
	return false


static func _carve_edge(
	data: FloorData,
	astar: AStarGrid2D,
	owners: Dictionary,
	a_id: int,
	b_id: int,
	params: GenParams,
	rng: RandomNumberGenerator
) -> bool:
	var a := data.room_by_id(a_id)
	var b := data.room_by_id(b_id)
	if a == null or b == null:
		return false
	var door_a := pick_door(data, a, b, params.corridor_wiggle, rng, astar)
	if door_a.x < 0:
		return false
	var door_b := pick_door(data, b, a, params.corridor_wiggle, rng, astar)
	if door_b.x < 0:
		return false
	astar.set_point_solid(door_a, false)
	astar.set_point_solid(door_b, false)
	astar.set_point_weight_scale(door_a, 1.0)
	astar.set_point_weight_scale(door_b, 1.0)
	var ids := astar.get_id_path(door_a, door_b)
	astar.set_point_solid(door_a, true)
	astar.set_point_solid(door_b, true)
	if ids.size() < 2 or ids[0] != door_a or ids[ids.size() - 1] != door_b:
		return false
	var corridor := FloorData.Corridor.new()
	corridor.from_room = a_id
	corridor.to_room = b_id
	var index := data.corridors.size()
	for i in range(1, ids.size() - 1):
		var p := ids[i]
		corridor.path.append(p)
		data.set_tile(p.x, p.y, FloorData.Tile.CORRIDOR)
		astar.set_point_solid(p, true)
		owners[p] = index
	data.set_tile(door_a.x, door_a.y, FloorData.Tile.DOOR)
	data.set_tile(door_b.x, door_b.y, FloorData.Tile.DOOR)
	owners[door_a] = index
	owners[door_b] = index
	a.doors[b_id] = door_a
	b.doors[a_id] = door_b
	data.corridors.append(corridor)
	_seal(data, astar, corridor.path)
	_seal(data, astar, [door_a, door_b] as Array[Vector2i])
	return true


## Marks every void tile orthogonally touching `tiles` solid so no later corridor can run
## next to (and therefore merge with) this one.
static func _seal(data: FloorData, astar: AStarGrid2D, tiles: Array[Vector2i]) -> void:
	for p: Vector2i in tiles:
		for d: Vector2i in GenUtil.DIRS4:
			var q := p + d
			if data.get_tile(q.x, q.y) == FloorData.Tile.VOID:
				astar.set_point_solid(q, true)


## Every VOID tile 8-adjacent to a corridor becomes WALL.
static func _ring_corridors(data: FloorData) -> void:
	var to_wall: Array[Vector2i] = []
	for y in range(data.height):
		for x in range(data.width):
			if data.get_tile(x, y) != FloorData.Tile.CORRIDOR:
				continue
			for d: Vector2i in GenUtil.DIRS8:
				if data.get_tile(x + d.x, y + d.y) == FloorData.Tile.VOID:
					to_wall.append(Vector2i(x + d.x, y + d.y))
	for p: Vector2i in to_wall:
		data.set_tile(p.x, p.y, FloorData.Tile.WALL)
