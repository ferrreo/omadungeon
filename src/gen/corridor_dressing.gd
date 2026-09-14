## Gives carved corridors some character (docs 5.1 #3): a share of them are widened to two
## tiles, given a small chamber half-way along, or a side alcove. Runs after every corridor of
## the floor is carved and before the corridors are ringed with wall, on the floor's own tile
## grid. Nothing here may change the walkable topology: a tile is only opened when every
## walkable neighbour it would touch already belongs to the same corridor, so no dressing can
## join two corridors, reach a foreign door or brush a room interior (room rings are WALL and
## never opened). The opened tiles are recorded on `FloorData.Corridor.extra`.
class_name CorridorDressing
extends RefCounted

## Chamber footprints (long axis along the corridor).
const CHAMBER_LONG := 5
const CHAMBER_SHORT := 3
## Shortest corridor that earns a chamber or an alcove.
const MIN_PATH_FOR_CHAMBER := 6
const MIN_PATH_FOR_ALCOVE := 4
const ALCOVE_DEPTH := 2


## Dresses every corridor of `data`. `owners` maps each CORRIDOR and DOOR tile to the index of
## its corridor in `data.corridors` (the carver builds it). `arch` may be null (no dressing).
static func apply(
	data: FloorData, owners: Dictionary, arch: FloorArchetype, rng: RandomNumberGenerator
) -> void:
	if arch == null:
		return
	for index in range(data.corridors.size()):
		var corridor := data.corridors[index]
		var roll := rng.randf()
		if corridor.path.size() >= MIN_PATH_FOR_CHAMBER and roll < arch.chamber_share:
			_chamber(data, owners, corridor, index, rng)
		elif roll < arch.chamber_share + arch.wide_share:
			_widen(data, owners, corridor, index, rng)
		if corridor.path.size() >= MIN_PATH_FOR_ALCOVE and rng.randf() < arch.alcove_share:
			_alcove(data, owners, corridor, index, rng)


## True when `p` can be opened for corridor `index` without touching anything else.
static func is_safe(data: FloorData, owners: Dictionary, p: Vector2i, index: int) -> bool:
	if p.x <= 0 or p.y <= 0 or p.x >= data.width - 1 or p.y >= data.height - 1:
		return false
	if data.get_tile(p.x, p.y) != FloorData.Tile.VOID:
		return false
	for d: Vector2i in GenUtil.DIRS8:
		var q := p + d
		var t := data.get_tile(q.x, q.y)
		if t == FloorData.Tile.VOID:
			continue
		if t == FloorData.Tile.WALL:
			# Room rings and shape cuts are solid; a corridor may run beside them.
			continue
		if not owners.has(q) or int(owners[q]) != index:
			return false
	return true


## Opens `p` for corridor `index` if it is safe. Returns true when it did.
static func open(
	data: FloorData, owners: Dictionary, corridor: FloorData.Corridor, index: int, p: Vector2i
) -> bool:
	if not is_safe(data, owners, p, index):
		return false
	data.set_tile(p.x, p.y, FloorData.Tile.CORRIDOR)
	owners[p] = index
	corridor.extra.append(p)
	return true


## Doubles the corridor along one side for its whole length (turns leave a small notch).
static func _widen(
	data: FloorData,
	owners: Dictionary,
	corridor: FloorData.Corridor,
	index: int,
	rng: RandomNumberGenerator
) -> void:
	var flip := rng.randf() < 0.5
	var path := corridor.path
	for i in range(path.size()):
		var dir := _local_direction(path, i)
		var side := Vector2i(-dir.y, dir.x) if flip else Vector2i(dir.y, -dir.x)
		open(data, owners, corridor, index, path[i] + side)


## A CHAMBER_LONG x CHAMBER_SHORT room-let centred on the corridor's middle tile.
static func _chamber(
	data: FloorData,
	owners: Dictionary,
	corridor: FloorData.Corridor,
	index: int,
	rng: RandomNumberGenerator
) -> void:
	var path := corridor.path
	var mid := path.size() / 2 + rng.randi_range(-1, 1)
	mid = clampi(mid, 2, path.size() - 3)
	var dir := _local_direction(path, mid)
	var along := Vector2i(absi(dir.x), absi(dir.y))
	var across := Vector2i(along.y, along.x)
	var half_long := CHAMBER_LONG / 2
	var half_short := CHAMBER_SHORT / 2
	var wanted: Array[Vector2i] = []
	for a in range(-half_long, half_long + 1):
		for b in range(-half_short, half_short + 1):
			var p := path[mid] + along * a + across * b
			if data.get_tile(p.x, p.y) == FloorData.Tile.VOID:
				wanted.append(p)
	# All or nothing: a half chamber reads as a glitch, not a room.
	for p: Vector2i in wanted:
		if not is_safe(data, owners, p, index):
			return
	for p: Vector2i in wanted:
		open(data, owners, corridor, index, p)


## A short dead-end pocket off one side of the corridor.
static func _alcove(
	data: FloorData,
	owners: Dictionary,
	corridor: FloorData.Corridor,
	index: int,
	rng: RandomNumberGenerator
) -> void:
	var path := corridor.path
	var at := rng.randi_range(1, path.size() - 2)
	var dir := _local_direction(path, at)
	var side := Vector2i(-dir.y, dir.x) if rng.randf() < 0.5 else Vector2i(dir.y, -dir.x)
	for depth in range(1, ALCOVE_DEPTH + 1):
		if not open(data, owners, corridor, index, path[at] + side * depth):
			return


## Direction of travel at path index `i` (the step out of it, or into it at the end).
static func _local_direction(path: Array[Vector2i], i: int) -> Vector2i:
	if path.size() < 2:
		return Vector2i.RIGHT
	if i < path.size() - 1:
		return path[i + 1] - path[i]
	return path[i] - path[i - 1]
