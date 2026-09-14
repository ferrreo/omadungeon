## Room footprints that are not plain rectangles (docs 5.1 #2). A room keeps `rect` as its
## bounding interior; a shape is a set of corner cut-outs stamped as WALL tiles inside that
## rect before any corridor is carved, so every door the carver picks still opens onto floor
## (`CorridorCarver._door_ok` checks the tile behind the door). The centre 3x3 is always kept:
## the player spawns, the stairs stand and the altar sits on `Room.center()`.
##
## Shapes: `rect`, `l_shape` (one corner quadrant gone), `t_shape` (two corners on one long
## side gone), `cross` (all four corners gone, a plus), `octagon` (corners stepped off).
class_name RoomShape
extends RefCounted

const RECT := &"rect"
const L_SHAPE := &"l_shape"
const T_SHAPE := &"t_shape"
const CROSS := &"cross"
const OCTAGON := &"octagon"
const ALL: Array[StringName] = [RECT, L_SHAPE, T_SHAPE, CROSS, OCTAGON]

## Smallest interior each cut shape reads on; below it the room stays a rectangle.
const MIN_CUT_SIZE := Vector2i(11, 9)
const MIN_OCTAGON_SIDE := 7
## Fraction of each axis an L cut removes.
const L_CUT := 0.45
## Base odds per room family, before the archetype multiplies them.
const FIGHT_WEIGHTS := {RECT: 0.28, L_SHAPE: 0.22, T_SHAPE: 0.12, CROSS: 0.18, OCTAGON: 0.20}
const SERVICE_WEIGHTS := {RECT: 0.40, CROSS: 0.25, OCTAGON: 0.35}
const START_WEIGHTS := {RECT: 0.45, OCTAGON: 0.55}
const BOSS_WEIGHTS := {RECT: 0.45, OCTAGON: 0.55}

const SERVICE_TYPES: Array[int] = [
	FloorData.RoomType.ALTAR,
	FloorData.RoomType.SHOP,
	FloorData.RoomType.SHRINE,
	FloorData.RoomType.TREASURE,
	FloorData.RoomType.STAIRS,
]


## Rolls a shape for a room of `type` and interior `size`. `orientation` (from the layout)
## decides which corner an L or T loses; `arch` may be null for the base odds.
static func pick(
	type: FloorData.RoomType, size: Vector2i, arch: FloorArchetype, rng: RandomNumberGenerator
) -> StringName:
	var base: Dictionary = FIGHT_WEIGHTS
	match type:
		FloorData.RoomType.START:
			base = START_WEIGHTS
		FloorData.RoomType.BOSS:
			base = BOSS_WEIGHTS
		_:
			if type in SERVICE_TYPES:
				base = SERVICE_WEIGHTS
	var ids: Array[StringName] = []
	var weights := PackedFloat32Array()
	for shape: StringName in ALL:
		if not base.has(shape) or not fits(shape, size):
			continue
		var w := float(base[shape])
		if arch != null:
			w *= arch.shape_weight(shape)
		ids.append(shape)
		weights.append(w)
	var idx := GenUtil.weighted_index(weights, rng)
	return ids[idx] if idx >= 0 else RECT


## True when `shape` reads on an interior of `size`.
static func fits(shape: StringName, size: Vector2i) -> bool:
	match shape:
		RECT:
			return true
		OCTAGON:
			return mini(size.x, size.y) >= MIN_OCTAGON_SIDE
		L_SHAPE, T_SHAPE, CROSS:
			return size.x >= MIN_CUT_SIZE.x and size.y >= MIN_CUT_SIZE.y
		_:
			return false


## Interior tiles of `rect` that `shape` turns into wall. `variant` picks the corner(s) an
## L or T loses (0..3) and the side a T keeps (its low two bits).
static func cut_tiles(shape: StringName, rect: Rect2i, variant: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not fits(shape, rect.size):
		return out
	match shape:
		L_SHAPE:
			var cut := _cut_size(rect.size, L_CUT)
			_append_corner(out, rect, variant % 4, cut)
		T_SHAPE:
			var cut := Vector2i(rect.size.x / 4, rect.size.y / 4)
			if rect.size.x >= rect.size.y:
				var top := variant % 2 == 0
				_append_corner(out, rect, 0 if top else 3, cut)
				_append_corner(out, rect, 1 if top else 2, cut)
			else:
				var left := variant % 2 == 0
				_append_corner(out, rect, 0 if left else 1, cut)
				_append_corner(out, rect, 3 if left else 2, cut)
		CROSS:
			var cut := Vector2i(rect.size.x / 4, rect.size.y / 4)
			for corner in range(4):
				_append_corner(out, rect, corner, cut)
		OCTAGON:
			var k := _octagon_step(rect.size)
			for corner in range(4):
				for i in range(k):
					for j in range(k - i):
						out.append(_corner_tile(rect, corner, Vector2i(i, j)))
		_:
			pass
	return out


## Stamps `room.shape` into `data` as WALL tiles. Returns the cut tiles.
static func stamp(data: FloorData, room: FloorData.Room, variant: int) -> Array[Vector2i]:
	var cut := cut_tiles(room.shape, room.rect, variant)
	for p: Vector2i in cut:
		data.set_tile(p.x, p.y, FloorData.Tile.WALL)
	return cut


## Interior tiles of `rect` a `shape` leaves as floor.
static func floor_count(shape: StringName, rect: Rect2i) -> int:
	return rect.size.x * rect.size.y - cut_tiles(shape, rect, 0).size()


## The corner tile `offset` steps in from corner `corner` (0 top-left, 1 top-right,
## 2 bottom-right, 3 bottom-left).
static func _corner_tile(rect: Rect2i, corner: int, offset: Vector2i) -> Vector2i:
	var x := rect.position.x + offset.x if corner == 0 or corner == 3 else rect.end.x - 1 - offset.x
	var y := rect.position.y + offset.y if corner == 0 or corner == 1 else rect.end.y - 1 - offset.y
	return Vector2i(x, y)


static func _append_corner(out: Array[Vector2i], rect: Rect2i, corner: int, cut: Vector2i) -> void:
	for j in range(cut.y):
		for i in range(cut.x):
			out.append(_corner_tile(rect, corner, Vector2i(i, j)))


## Size of an L cut: `share` of each axis, never eating into the centre 3x3.
static func _cut_size(size: Vector2i, share: float) -> Vector2i:
	return Vector2i(
		clampi(int(floor(size.x * share)), 2, size.x / 2 - 2),
		clampi(int(floor(size.y * share)), 2, size.y / 2 - 2)
	)


static func _octagon_step(size: Vector2i) -> int:
	return clampi(mini(size.x, size.y) / 3 - 1, 2, 5)
