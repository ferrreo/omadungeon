## Checks a generated FloorData against the docs 5.1 #7 guarantees and returns a list of
## human-readable violations (empty = valid). Pure and side-effect free.
class_name FloorValidator
extends RefCounted

const MAX_WIDTH := 160
const MAX_HEIGHT := 120
const MIN_GAP := 3
const MIN_STAIRS_DISTANCE := 3
const DOOR_CLEARANCE := 3


static func validate(data: FloorData) -> Array[String]:
	var out: Array[String] = []
	_check_grid(data, out)
	if data.rooms.is_empty():
		out.append("no rooms")
		return out
	_check_rooms(data, out)
	_check_types(data, out)
	_check_doors(data, out)
	_check_spawns(data, out)
	_check_connectivity(data, out, false)
	_check_connectivity(data, out, true)
	_check_walkable_topology(data, out)
	return out


static func is_valid(data: FloorData) -> bool:
	return validate(data).is_empty()


## Interior tiles of `room` reachable from one of its doors with props, template walls and
## pits treated as solid. Enemy spawns must lie inside this set or the room can never be
## cleared (props are StaticBody2D on Layers.PROP and block entities).
static func room_reachable_tiles(data: FloorData, room: FloorData.Room) -> Dictionary:
	var blocked: Dictionary = {}
	for p: Vector2i in room.prop_positions:
		blocked[p] = true
	var rect := room.rect
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for key: int in room.doors.keys():
		var door: Vector2i = room.doors[key]
		for d: Vector2i in GenUtil.DIRS4:
			var p := door + d
			if not rect.has_point(p) or seen.has(p):
				continue
			if data.is_walkable(p.x, p.y) and not blocked.has(p):
				seen[p] = true
				queue.append(p)
	if queue.is_empty():
		var c := room.center()
		if rect.has_point(c) and data.is_walkable(c.x, c.y) and not blocked.has(c):
			seen[c] = true
			queue.append(c)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for d: Vector2i in GenUtil.DIRS4:
			var n := cur + d
			if seen.has(n) or not rect.has_point(n):
				continue
			if not data.is_walkable(n.x, n.y) or blocked.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


## Floor trap tiles (not wall-mounted ones) as a set for blocked-path checks.
static func trap_tiles(data: FloorData) -> Dictionary:
	var tiles: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		for trap: Dictionary in room.trap_positions:
			var pos: Vector2i = trap["pos"]
			if data.is_walkable(pos.x, pos.y):
				tiles[pos] = true
	return tiles


static func _check_grid(data: FloorData, out: Array[String]) -> void:
	if data.width <= 0 or data.height <= 0:
		out.append("empty grid")
	if data.width > MAX_WIDTH or data.height > MAX_HEIGHT:
		out.append("grid %dx%d exceeds %dx%d" % [data.width, data.height, MAX_WIDTH, MAX_HEIGHT])
	if data.tiles.size() != data.width * data.height:
		out.append("tile array size mismatch")


static func _check_rooms(data: FloorData, out: Array[String]) -> void:
	var grid := Rect2i(1, 1, data.width - 2, data.height - 2)
	for i in range(data.rooms.size()):
		var room := data.rooms[i]
		if room.id != i:
			out.append("room %d stored at index %d" % [room.id, i])
		if not grid.encloses(room.rect.grow(1)):
			out.append("room %d ring leaves the grid" % room.id)
		if room.rect.size.x < 5 or room.rect.size.y < 5:
			out.append("room %d too small" % room.id)
		for j in range(i + 1, data.rooms.size()):
			var other := data.rooms[j]
			if room.rect.grow(MIN_GAP).intersects(other.rect):
				out.append("rooms %d and %d closer than %d tiles" % [room.id, other.id, MIN_GAP])
		for p: Vector2i in GenUtil.rect_tiles(room.rect):
			var t := data.get_tile(p.x, p.y)
			if t != FloorData.Tile.FLOOR and t != FloorData.Tile.WALL and t != FloorData.Tile.PIT:
				out.append("room %d interior tile %s is %d" % [room.id, p, t])
				break
		if room.neighbors.is_empty():
			out.append("room %d has no neighbours" % room.id)
		for nb: int in room.neighbors:
			if data.room_by_id(nb) == null:
				out.append("room %d neighbour %d missing" % [room.id, nb])
			elif not (room.id in data.rooms[nb].neighbors):
				out.append("edge %d-%d not symmetric" % [room.id, nb])


## The per-floor room budget (docs 5.1 #4, `RoomBudget`): one altar or shrine, a shop where
## the table guarantees one and never two, and no optional room the floor's row rules out.
static func _check_types(data: FloorData, out: Array[String]) -> void:
	var counts: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		counts[room.type] = int(counts.get(room.type, 0)) + 1
	if int(counts.get(FloorData.RoomType.START, 0)) != 1:
		out.append("expected exactly one START room")
	var blessings := (
		int(counts.get(FloorData.RoomType.ALTAR, 0)) + int(counts.get(FloorData.RoomType.SHRINE, 0))
	)
	if blessings != 1:
		out.append("expected exactly one ALTAR or SHRINE room, got %d" % blessings)
	var shops := int(counts.get(FloorData.RoomType.SHOP, 0))
	if shops > RoomBudget.max_count(data.floor_index, FloorData.RoomType.SHOP):
		out.append("floor %d allows no shop, got %d" % [data.floor_index, shops])
	elif RoomBudget.shop_guaranteed(data.floor_index) and shops != 1:
		out.append("floor %d guarantees a shop, got %d" % [data.floor_index, shops])
	for optional: int in [
		FloorData.RoomType.ELITE, FloorData.RoomType.TRAP, FloorData.RoomType.TREASURE
	]:
		var cap := RoomBudget.max_count(data.floor_index, optional as FloorData.RoomType)
		if int(counts.get(optional, 0)) > cap:
			out.append(
				(
					"floor %d allows %d rooms of type %d, got %d"
					% [data.floor_index, cap, optional, int(counts.get(optional, 0))]
				)
			)
	var start := data.room_by_id(data.start_room)
	if start == null or start.type != FloorData.RoomType.START:
		out.append("start_room does not point at the START room")
	var stairs := data.room_by_id(data.stairs_room)
	if stairs == null:
		out.append("stairs_room missing")
	elif data.boss_room >= 0:
		var boss := data.room_by_id(data.boss_room)
		if boss == null or boss.type != FloorData.RoomType.BOSS:
			out.append("boss_room does not point at a BOSS room")
		elif boss.graph_distance < MIN_STAIRS_DISTANCE:
			out.append("boss only %d edges from start" % boss.graph_distance)
		if int(counts.get(FloorData.RoomType.BOSS, 0)) != 1:
			out.append("boss floor needs exactly one BOSS room")
	else:
		if stairs.type != FloorData.RoomType.STAIRS:
			out.append("stairs_room is not a STAIRS room")
		if stairs.graph_distance < MIN_STAIRS_DISTANCE:
			out.append("stairs only %d edges from start" % stairs.graph_distance)
		if int(counts.get(FloorData.RoomType.BOSS, 0)) != 0:
			out.append("BOSS room on a non-boss floor")
	# Same rule as FloorGraph._assign_types: the quota is measured over the free pool
	# (ordinary rooms minus the guaranteed altar and shop/shrine) and ELITE / TRAP count
	# as fights, so small floors can still carry a special room.
	var free_pool := 0
	var fights := 0
	for room: FloorData.Room in data.rooms:
		if room.type in FloorGraph.STRUCTURAL_TYPES or room.type in FloorGraph.SERVICE_TYPES:
			continue
		free_pool += 1
		if room.type in FloorGraph.FIGHT_TYPES:
			fights += 1
	if free_pool > 0 and fights < FloorGraph.combat_quota(free_pool):
		out.append("only %d of %d free rooms are fights" % [fights, free_pool])


static func _check_doors(data: FloorData, out: Array[String]) -> void:
	for room: FloorData.Room in data.rooms:
		if room.doors.is_empty():
			out.append("room %d has no doors" % room.id)
		for nb: int in room.neighbors:
			if not room.doors.has(nb):
				out.append("room %d has no door towards %d" % [room.id, nb])
		for key: int in room.doors.keys():
			var door: Vector2i = room.doors[key]
			if data.get_tile(door.x, door.y) != FloorData.Tile.DOOR:
				out.append("room %d door %s is not a DOOR tile" % [room.id, door])
			var ring := room.rect.grow(1)
			if not ring.has_point(door) or room.rect.has_point(door):
				out.append("room %d door %s is not on its wall ring" % [room.id, door])
			var inside := false
			for d: Vector2i in GenUtil.DIRS4:
				if room.rect.has_point(door + d) and data.is_walkable(door.x + d.x, door.y + d.y):
					inside = true
			if not inside:
				out.append("room %d door %s is blocked from inside" % [room.id, door])


static func _check_spawns(data: FloorData, out: Array[String]) -> void:
	for room: FloorData.Room in data.rooms:
		var occupied: Dictionary = {}
		var doors: Array = room.doors.values()
		for p: Vector2i in room.prop_positions:
			if not room.rect.has_point(p) or data.get_tile(p.x, p.y) != FloorData.Tile.FLOOR:
				out.append("room %d prop %s not on floor" % [room.id, p])
			if occupied.has(p):
				out.append("room %d prop overlap at %s" % [room.id, p])
			occupied[p] = true
		for trap: Dictionary in room.trap_positions:
			var p: Vector2i = trap["pos"]
			var t := data.get_tile(p.x, p.y)
			if room.rect.has_point(p):
				if t != FloorData.Tile.FLOOR and t != FloorData.Tile.PIT:
					out.append("room %d trap %s on tile %d" % [room.id, p, t])
			elif not room.rect.grow(1).has_point(p) or t != FloorData.Tile.WALL:
				out.append("room %d trap %s off room" % [room.id, p])
			if occupied.has(p):
				out.append("room %d trap overlap at %s" % [room.id, p])
			occupied[p] = true
		if room.type == FloorData.RoomType.START and not room.enemy_spawns.is_empty():
			out.append("START room has enemy spawns")
		if room.type == FloorData.RoomType.BOSS:
			_check_arena_spawns(data, room, out)
		if not room.enemy_spawns.is_empty():
			var reachable := room_reachable_tiles(data, room)
			for p: Vector2i in room.enemy_spawns:
				if not reachable.has(p):
					out.append("room %d spawn %s is sealed off by props or pits" % [room.id, p])
		for p: Vector2i in room.enemy_spawns:
			if not room.rect.has_point(p) or not data.is_walkable(p.x, p.y):
				out.append("room %d spawn %s not walkable" % [room.id, p])
			if occupied.has(p):
				out.append("room %d spawn overlap at %s" % [room.id, p])
			occupied[p] = true
			for door: Vector2i in doors:
				if GenUtil.chebyshev(door, p) < DOOR_CLEARANCE:
					out.append(
						"room %d spawn %s within %d of door %s" % [room.id, p, DOOR_CLEARANCE, door]
					)
					break


## The boss waits across the arena (docs 7.4): a spawn list, every entry clear of every door
## by `ArenaSpawns.DOOR_CLEARANCE`, and no spawn inside the doorway apron.
static func _check_arena_spawns(_data: FloorData, room: FloorData.Room, out: Array[String]) -> void:
	if room.enemy_spawns.is_empty():
		out.append("boss room %d has no spawn" % room.id)
		return
	var doors := room.door_tiles()
	for p: Vector2i in room.enemy_spawns:
		var clearance := ArenaSpawns.door_distance(doors, p)
		if clearance < ArenaSpawns.DOOR_CLEARANCE:
			out.append(
				(
					"boss room %d spawn %s only %d tiles from a door (needs %d)"
					% [room.id, p, int(clearance), ArenaSpawns.DOOR_CLEARANCE]
				)
			)


## BFS from the start room centre; every door tile of every room and the stairs/boss centre
## must be reachable. With `traps_block` floor traps count as solid.
static func _check_connectivity(data: FloorData, out: Array[String], traps_block: bool) -> void:
	var start := data.room_by_id(data.start_room)
	if start == null:
		return
	var blocked := trap_tiles(data) if traps_block else {}
	var origin := start.center()
	if not data.is_walkable(origin.x, origin.y):
		out.append("start centre not walkable")
		return
	var seen := PackedByteArray()
	seen.resize(data.width * data.height)
	seen.fill(0)
	var queue := PackedInt32Array()
	queue.append(origin.y * data.width + origin.x)
	seen[origin.y * data.width + origin.x] = 1
	var head := 0
	var w := data.width
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var x := idx % w
		var y := idx / w
		for d: Vector2i in GenUtil.DIRS4:
			var nx := x + d.x
			var ny := y + d.y
			if not data.is_walkable(nx, ny):
				continue
			var nidx := ny * w + nx
			if seen[nidx] != 0:
				continue
			if traps_block and blocked.has(Vector2i(nx, ny)):
				continue
			seen[nidx] = 1
			queue.append(nidx)
	var label := " (traps blocked)" if traps_block else ""
	for room: FloorData.Room in data.rooms:
		for key: int in room.doors.keys():
			var door: Vector2i = room.doors[key]
			if seen[door.y * w + door.x] == 0:
				out.append("room %d door %s unreachable%s" % [room.id, door, label])
	var goal := data.room_by_id(data.stairs_room)
	if goal != null:
		var c := goal.center()
		if not data.is_walkable(c.x, c.y) or seen[c.y * w + c.x] == 0:
			out.append("stairs/boss centre unreachable%s" % label)


## The corridor/door components must describe exactly the room graph: two rooms are walkably
## adjacent only when they are graph neighbours, and the walkable room distance from start to
## stairs/boss must still be >= MIN_STAIRS_DISTANCE (docs 5.1 #1). Without this a corridor
## that merges with, or runs beside, a foreign corridor would open a shortcut the minimap and
## the room graph know nothing about.
static func _check_walkable_topology(data: FloorData, out: Array[String]) -> void:
	var door_owner: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		for key: int in room.doors.keys():
			var door: Vector2i = room.doors[key]
			var owners: Array[int] = []
			if door_owner.has(door):
				owners = door_owner[door]
			if not (room.id in owners):
				owners.append(room.id)
			door_owner[door] = owners
	var adjacency: Array[Dictionary] = []
	for _room: FloorData.Room in data.rooms:
		adjacency.append({})
	var w := data.width
	var seen := PackedByteArray()
	seen.resize(w * data.height)
	seen.fill(0)
	for y in range(data.height):
		for x in range(w):
			var origin := Vector2i(x, y)
			if seen[y * w + x] != 0 or not _is_link_tile(data, origin):
				continue
			var component: Array[int] = []
			var queue: Array[Vector2i] = [origin]
			seen[y * w + x] = 1
			var head := 0
			while head < queue.size():
				var cur := queue[head]
				head += 1
				if door_owner.has(cur):
					for owner: int in door_owner[cur] as Array[int]:
						if not (owner in component):
							component.append(owner)
				for d: Vector2i in GenUtil.DIRS4:
					var n := cur + d
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= data.height:
						continue
					if seen[n.y * w + n.x] != 0 or not _is_link_tile(data, n):
						continue
					seen[n.y * w + n.x] = 1
					queue.append(n)
			for i in range(component.size()):
				for j in range(i + 1, component.size()):
					var a: int = component[i]
					var b: int = component[j]
					adjacency[a][b] = true
					adjacency[b][a] = true
					if not (b in data.rooms[a].neighbors):
						out.append("rooms %d and %d are walkable but not graph neighbours" % [a, b])
	_check_walkable_distance(data, adjacency, out)


static func _is_link_tile(data: FloorData, p: Vector2i) -> bool:
	var t := data.get_tile(p.x, p.y)
	return t == FloorData.Tile.DOOR or t == FloorData.Tile.CORRIDOR


## BFS over the adjacency derived from the carved corridors.
static func _check_walkable_distance(
	data: FloorData, adjacency: Array[Dictionary], out: Array[String]
) -> void:
	var dist: Array[int] = []
	dist.resize(data.rooms.size())
	dist.fill(-1)
	if data.start_room < 0 or data.start_room >= dist.size():
		return
	dist[data.start_room] = 0
	var queue: Array[int] = [data.start_room]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for nb: int in adjacency[cur].keys():
			if dist[nb] < 0:
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	for i in range(dist.size()):
		if dist[i] < 0:
			out.append("room %d is not walkably reachable from the start" % i)
	var goal := data.stairs_room
	if goal >= 0 and goal < dist.size() and dist[goal] >= 0 and dist[goal] < MIN_STAIRS_DISTANCE:
		out.append("stairs/boss only %d rooms of walking from start" % dist[goal])
