## Where the boss (and the elite pack that stands in for a boss that is not implemented yet)
## waits in an arena (docs 5.1 #7, 7.4). The boss never stands in the doorway: its spot is
## the reachable tile farthest from every door of the arena, on the far side's midline and
## at least `WALL_INSET` tiles off the wall, and it must clear `DOOR_CLEARANCE` from every
## door or the floor fails validation. The pack's extra spots cluster around that tile under
## the same clearance, so a fallback pack cannot ambush the player at the door either.
class_name ArenaSpawns
extends RefCounted

## Chebyshev tiles every arena spawn keeps from every door.
const DOOR_CLEARANCE := 8
## Tiles a spawn keeps off the arena wall, so the boss has room to move on every side.
const WALL_INSET := 2
## Spawn tiles an arena records: the boss's, then the fallback pack's.
const PACK_SPOTS := 3
## Spacing between pack spots.
const PACK_SPACING := 2


## The spawn list for `room`: index 0 the boss's tile, then up to `PACK_SPOTS` pack tiles.
## `candidates` are the interior tiles that are free and reachable from the doors (the filler
## computes them); an empty result means the arena has no tile clear of its doors, which the
## validator reports. The boss's tile is the deepest into the arena along the door's inward
## normal (not the farthest by Chebyshev distance, which is a corner whenever the door sits
## near one), nearest the centre line.
static func place(room: FloorData.Room, candidates: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var doors: Array[Vector2i] = room.door_tiles()
	var inner := room.rect.grow(-WALL_INSET)
	var best := Vector2i(-1, -1)
	var best_score := -INF
	for p: Vector2i in candidates:
		if not inner.has_point(p):
			continue
		var clearance := door_distance(doors, p)
		if clearance < DOOR_CLEARANCE:
			continue
		var score := _depth(room, doors, p) * 10.0 - _midline_offset(room, doors, p)
		if score > best_score:
			best_score = score
			best = p
	if best.x < 0:
		return out
	out.append(best)
	var ranked: Array[Vector2i] = []
	for p: Vector2i in candidates:
		if p == best or not inner.has_point(p) or door_distance(doors, p) < DOOR_CLEARANCE:
			continue
		ranked.append(p)
	ranked.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return GenUtil.chebyshev(a, best) < GenUtil.chebyshev(b, best)
	)
	for p: Vector2i in ranked:
		if out.size() > PACK_SPOTS:
			break
		var spaced := true
		for s: Vector2i in out:
			if GenUtil.chebyshev(s, p) < PACK_SPACING:
				spaced = false
				break
		if spaced:
			out.append(p)
	return out


## Smallest Chebyshev distance from `p` to any of `doors` (INF with no doors).
static func door_distance(doors: Array[Vector2i], p: Vector2i) -> float:
	var best := INF
	for door: Vector2i in doors:
		best = minf(best, float(GenUtil.chebyshev(door, p)))
	return best


## How far `p` sits from the line through the arena centre opposite the nearest door: the
## boss stands across from the entrance, not in a corner.
static func _midline_offset(room: FloorData.Room, doors: Array[Vector2i], p: Vector2i) -> float:
	if doors.is_empty():
		return float(GenUtil.chebyshev(p, room.center()))
	var c := room.center()
	var horizontal_door := _is_horizontal(room, _nearest(doors, p))
	return float(absi(p.x - c.x) if horizontal_door else absi(p.y - c.y))


## How far into the arena `p` lies from the nearest door, along that door's inward normal.
static func _depth(room: FloorData.Room, doors: Array[Vector2i], p: Vector2i) -> float:
	if doors.is_empty():
		return 0.0
	var door := _nearest(doors, p)
	var inward := room.trap_facing(door)
	var delta := p - door
	return float(delta.x * inward.x + delta.y * inward.y)


static func _nearest(doors: Array[Vector2i], p: Vector2i) -> Vector2i:
	var nearest := doors[0]
	for door: Vector2i in doors:
		if GenUtil.chebyshev(door, p) < GenUtil.chebyshev(nearest, p):
			nearest = door
	return nearest


static func _is_horizontal(room: FloorData.Room, door: Vector2i) -> bool:
	return door.y < room.rect.position.y or door.y >= room.rect.end.y
