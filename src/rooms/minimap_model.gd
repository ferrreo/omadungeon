## Pure helper turning FloorData + run state into what the minimap draws. No nodes, no
## rendering: the UI module reads `rooms()` and `edges()` and paints rectangles/lines.
class_name MinimapModel
extends RefCounted


## One entry per room: {id, rect: Rect2i, shape: StringName, type: int, cleared: bool,
## visited: bool, current: bool}. `shape` is the `RoomShape` id (the UI may draw the cut).
## `cleared` / `visited` are room-id lists; unvisited rooms are still listed (UI may hide them).
static func rooms(
	data: FloorData, cleared: Array[int], current_id: int, visited: Array[int] = []
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if data == null:
		return out
	for room: FloorData.Room in data.rooms:
		var is_cleared := cleared.has(room.id)
		var entry := {
			"id": room.id,
			"rect": room.rect,
			"shape": room.shape,
			"type": int(room.type),
			"cleared": is_cleared,
			"visited": is_cleared or visited.has(room.id) or room.id == current_id,
			"current": room.id == current_id,
		}
		out.append(entry)
	return out


## One Vector4i per corridor: (from_center.x, from_center.y, to_center.x, to_center.y) in tiles.
## Falls back to the room graph when no corridors were generated. The minimap reads the
## endpoints back as room lookups, which is why they are centres and not door tiles.
static func edges(data: FloorData) -> Array[Vector4i]:
	var out: Array[Vector4i] = []
	for pair: Vector2i in pairs(data):
		out.append(_edge(data, pair.x, pair.y))
	return out


## One polyline per entry of `edges()`, in the same order: the route the corridor actually
## takes, in tile-centre coordinates, from one room's door tile to the other's.
##
## The minimap used to draw each link as a straight room-centre to room-centre chord, which
## cuts across the rectangles it connects and across unrelated rooms (measured: 1.8% of links
## on a generated floor crossed a room that was not one of their two endpoints). The carver
## only ever routes through VOID, so the recorded path cannot cross any room - drawing it is
## what makes the panel a graph instead of a scribble. Ends at the door tiles rather than the
## centres so the line stops at the room box instead of running over it.
static func links(data: FloorData) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for pair: Vector2i in pairs(data):
		out.append(_link(data, pair.x, pair.y))
	return out


## Room-id pairs one link is drawn for, deduplicated and ordered. `edges()` and `links()` are
## both built from this, so entry *i* of one describes the same connection as entry *i* of the
## other. Falls back to the room graph when no corridors were generated.
static func pairs(data: FloorData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if data == null:
		return out
	var seen: Dictionary = {}
	for c: FloorData.Corridor in data.corridors:
		var key := Vector2i(mini(c.from_room, c.to_room), maxi(c.from_room, c.to_room))
		if seen.has(key):
			continue
		seen[key] = true
		out.append(Vector2i(c.from_room, c.to_room))
	if not out.is_empty():
		return out
	for room: FloorData.Room in data.rooms:
		for n: int in room.neighbors:
			var key := Vector2i(mini(room.id, n), maxi(room.id, n))
			if seen.has(key):
				continue
			seen[key] = true
			out.append(Vector2i(room.id, n))
	return out


## Tile bounds enclosing every room (for fitting the map into its panel).
static func bounds(data: FloorData) -> Rect2i:
	if data == null:
		return Rect2i()
	if data.rooms.is_empty():
		return Rect2i(0, 0, data.width, data.height)
	var r := data.rooms[0].rect
	for room: FloorData.Room in data.rooms:
		r = r.merge(room.rect)
	return r


static func _edge(data: FloorData, a: int, b: int) -> Vector4i:
	if data == null:
		return Vector4i()
	var ra := data.room_by_id(a)
	var rb := data.room_by_id(b)
	var ca := ra.center() if ra != null else Vector2i.ZERO
	var cb := rb.center() if rb != null else Vector2i.ZERO
	return Vector4i(ca.x, ca.y, cb.x, cb.y)


## The drawn route between two connected rooms: door, corridor path, door. Falls back to the
## two room centres when the floor records no doors for the pair (the graph fallback above,
## and hand-built fixtures) - the minimap routes those itself.
static func _link(data: FloorData, a: int, b: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if data == null:
		return out
	var ra := data.room_by_id(a)
	var rb := data.room_by_id(b)
	if ra == null or rb == null:
		return out
	if not ra.doors.has(b) or not rb.doors.has(a):
		out.append(_tile_center(ra.center()))
		out.append(_tile_center(rb.center()))
		return out
	out.append(_tile_center(ra.doors[b]))
	var corridor := _corridor_between(data, a, b)
	if corridor != null:
		var path := corridor.path
		var forward := corridor.from_room == a
		for i in range(path.size()):
			out.append(_tile_center(path[i if forward else path.size() - 1 - i]))
	out.append(_tile_center(rb.doors[a]))
	return _straighten(out)


static func _corridor_between(data: FloorData, a: int, b: int) -> FloorData.Corridor:
	for c: FloorData.Corridor in data.corridors:
		if (c.from_room == a and c.to_room == b) or (c.from_room == b and c.to_room == a):
			return c
	return null


## Drops points that lie on the segment between their neighbours. A corridor is stored tile by
## tile; at minimap scale a straight run is one line, and keeping every tile would hand the
## renderer dozens of sub-pixel segments per link.
static func _straighten(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array()
	out.append(points[0])
	for i in range(1, points.size() - 1):
		var prev := points[i - 1]
		var next := points[i + 1]
		var cross := (points[i] - prev).cross(next - points[i])
		if absf(cross) > 0.0001:
			out.append(points[i])
	out.append(points[points.size() - 1])
	return out


static func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) + Vector2(0.5, 0.5)
