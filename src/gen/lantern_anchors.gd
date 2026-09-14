## Where the lighting system may hang a lantern (docs 5.1 #8): WALL tiles along the wall runs
## of every room and corridor, one every `spacing` tiles, never a doorway and never beside one
## (the door already carries its own pair of torches, `FloorRoot._place_torches`). The list is
## the last thing the generator writes onto a `FloorData`, rolled from the same rng stream as
## the rest of the floor, so it is deterministic per seed and comes back identical when a
## floor is regenerated from its saved `GenParams` (`FloorRestore`).
##
## Tile semantics the anchors rely on, and which `FloorData.Tile` keeps stable: VOID is
## outside the dungeon and never walked or drawn as a surface; WALL is solid - a room's ring,
## a shape cut-out, a template pillar, the ring around a corridor; FLOOR, CORRIDOR and DOOR
## are walkable; PIT is a hole inside a room. An anchor is always a WALL tile with at least
## one walkable 4-neighbour, so a lantern hung on it faces open ground.
class_name LanternAnchors
extends RefCounted

## Chebyshev distance an anchor keeps from every DOOR tile (2 = never in or beside a door).
const DOOR_CLEARANCE := 2
## Chebyshev distance two anchors keep from each other, whatever runs they lie on.
const MIN_APART := 2
## Spacing a biome that says nothing gets. Wide on purpose: a lantern every five or six tiles
## lights a whole room evenly, which is the look the owner called "BARELY makes a difference",
## and `lighting_frame` agreed - the floor under a pool read 8% over the floor between the
## pools, because there was no floor between the pools. Light has to be a local event before a
## pocket of it can exist, so the biomes space theirs 10 to 16 tiles apart and most rooms take
## one or two (`data/biomes/*.tres`).
const DEFAULT_SPACING := 10
## How much wider a corridor's lanterns stand than a room's, as a multiple of the biome's
## spacing. A corridor is the dark between the pockets; see `place()`.
const CORRIDOR_SPACING := 2.2
const MIN_SPACING := 3


## Anchors for `data`, rooms first (ring sides in reading order, one every `spacing` tiles,
## and at least one per *room* that has room for it) then corridors (along the path, one side
## per stop). `spacing` is the biome's; `rng` gives each run a phase so a wall of six tiles
## does not always light its first tile, rolled once per side.
##
## The fallback used to be per side, which quietly made four the floor for a room of any size:
## a room whose walls were all shorter than the spacing still hung a lantern on each of them,
## and the room came out ringed with light. Per room is the honest reading of "one every
## `spacing` tiles" - a small room gets one lantern in one corner and the other three corners
## are dark, which is the asymmetry the pockets are made of. `lantern_anchors_test` still
## guarantees that a room with a free wall is lit at all.
static func place(data: FloorData, spacing: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var step := maxi(spacing, MIN_SPACING)
	var out: Array[Vector2i] = []
	var forbidden := door_zone(data)
	var rings: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		var sides := ring_sides(room)
		var placed := 0
		for side: Array[Vector2i] in sides:
			# A phase per side, not per room. One phase shared by all four walls is all-or-
			# nothing once the spacing is wider than the walls are long: either every side's
			# first stop lands inside it and the room comes out ringed with light, or none does.
			# Rolled per side, a room of ordinary size lights one or two of its walls and leaves
			# the others dark, which is the asymmetry the pockets are made of.
			var i := rng.randi_range(0, step - 1)
			while i < side.size():
				var p := side[i]
				if _ok(data, p, forbidden, out):
					out.append(p)
					placed += 1
				i += step
			for p: Vector2i in side:
				rings[p] = true
		# A room every stepped stop of which fell in a doorway, or whose walls are all shorter
		# than the spacing, still gets its one lantern - on whichever side has a tile for it.
		if placed == 0:
			for side: Array[Vector2i] in sides:
				var found := false
				for p: Vector2i in side:
					if _ok(data, p, forbidden, out):
						out.append(p)
						found = true
						break
				if found:
					break
	# Corridor walls only: a corridor running along a room's ring leaves that ring to the room's
	# own pass, so the spacing along a room wall is the room's.
	#
	# And a corridor is lit at `CORRIDOR_SPACING` times the room's spacing, not at the room's.
	# A corridor is the part of a floor nobody has to fight in and the part a player crosses
	# with their own light; lighting it as densely as a room is how a floor ends up lit end to
	# end, which is what `lighting_frame` measured on gruvbox - three floor tiles in the whole
	# viewport stood four tiles clear of a light. The dark between the rooms is where the
	# pockets come from, and it is the cheapest dark there is.
	var corridor_step := maxi(int(round(float(step) * CORRIDOR_SPACING)), MIN_SPACING)
	for corridor: FloorData.Corridor in data.corridors:
		var path := corridor.path
		if path.is_empty():
			continue
		var phase := rng.randi_range(0, corridor_step - 1)
		var i := phase
		while i < path.size():
			var dir := _local_direction(path, i)
			var side := Vector2i(-dir.y, dir.x)
			for cand: Vector2i in [path[i] + side, path[i] - side]:
				if not rings.has(cand) and _ok(data, cand, forbidden, out):
					out.append(cand)
					break
			i += corridor_step
	return out


## Every tile within `DOOR_CLEARANCE` (exclusive) of a DOOR tile, as a set.
static func door_zone(data: FloorData) -> Dictionary:
	var zone: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		for door: Vector2i in room.door_tiles():
			for dy in range(-DOOR_CLEARANCE + 1, DOOR_CLEARANCE):
				for dx in range(-DOOR_CLEARANCE + 1, DOOR_CLEARANCE):
					zone[door + Vector2i(dx, dy)] = true
	return zone


## The four sides of a room's wall ring without the corners: top and bottom left to right,
## left and right top to bottom.
static func ring_sides(room: FloorData.Room) -> Array[Array]:
	var ring := room.ring()
	var top: Array[Vector2i] = []
	var bottom: Array[Vector2i] = []
	var left: Array[Vector2i] = []
	var right: Array[Vector2i] = []
	for x in range(ring.position.x + 1, ring.end.x - 1):
		top.append(Vector2i(x, ring.position.y))
		bottom.append(Vector2i(x, ring.end.y - 1))
	for y in range(ring.position.y + 1, ring.end.y - 1):
		left.append(Vector2i(ring.position.x, y))
		right.append(Vector2i(ring.end.x - 1, y))
	return [top, right, bottom, left]


## True when `p` is a WALL tile facing walkable ground, clear of every door and every anchor
## already placed.
static func is_anchor_tile(data: FloorData, p: Vector2i, forbidden: Dictionary) -> bool:
	if data.get_tile(p.x, p.y) != FloorData.Tile.WALL or forbidden.has(p):
		return false
	for d: Vector2i in GenUtil.DIRS4:
		if data.is_walkable(p.x + d.x, p.y + d.y):
			return true
	return false


static func _ok(
	data: FloorData, p: Vector2i, forbidden: Dictionary, placed: Array[Vector2i]
) -> bool:
	if not is_anchor_tile(data, p, forbidden):
		return false
	for q: Vector2i in placed:
		if GenUtil.chebyshev(p, q) < MIN_APART:
			return false
	return true


static func _local_direction(path: Array[Vector2i], i: int) -> Vector2i:
	if path.size() < 2:
		return Vector2i.RIGHT
	if i < path.size() - 1:
		return path[i + 1] - path[i]
	return path[i] - path[i - 1]
