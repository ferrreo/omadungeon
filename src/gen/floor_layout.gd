## Places the rooms of a FloorGraph on a tile grid (docs 5.1 #2). Grid-tree placement:
## children are placed next to their parent (facing sides overlapping so a corridor can
## connect them), candidates are rejection-sampled against overlaps and scored for a
## compact bounding box. The `FloorArchetype` steers where a child goes (a winding floor
## snakes on, a ring curls, a hub fans its spokes out) and how far apart rooms sit. Up to
## MAX_ATTEMPTS full layouts are tried before giving up (the generator then reseeds).
## Output: a FloorData with room interiors (FLOOR), their 1-tile wall rings (WALL) and each
## room's `RoomShape` cut-outs stamped as WALL; everything else VOID.
class_name FloorLayout
extends RefCounted

const MAX_WIDTH := 160
const MAX_HEIGHT := 120
## Minimum wall tiles between two room interiors (ring, gap, ring).
const MIN_GAP := 3
## Void margin around the outermost wall rings so corridors have room to wander.
const MARGIN := 4
const MAX_ATTEMPTS := 50
## Facing sides must share at least this many tiles so a door can face a door.
const MIN_SIDE_OVERLAP := 3
const CANDIDATES_PER_ROOM := 10

const SIZE_CLOSET := Vector2i(7, 5)
const SIZE_SMALL := Vector2i(9, 7)
const SIZE_MEDIUM := Vector2i(13, 9)
const SIZE_LARGE := Vector2i(17, 13)
## A wide hall and a long, narrow gallery (the layout may turn either on its side).
const SIZE_HALL := Vector2i(21, 9)
const SIZE_GALLERY := Vector2i(17, 7)
const SIZE_ARENA := Vector2i(21, 15)
## The crossroads room of a hub floor.
const SIZE_HUB := Vector2i(23, 17)
## Size classes a fight room rolls over, in `FloorArchetype.size_weights` key order.
const SIZE_CLASSES: Array[StringName] = [
	&"closet", &"small", &"medium", &"large", &"hall", &"gallery"
]
const SIZES: Array[Vector2i] = [
	SIZE_CLOSET, SIZE_SMALL, SIZE_MEDIUM, SIZE_LARGE, SIZE_HALL, SIZE_GALLERY
]
## Base odds of each size class for a fight room at bias 0.
const FIGHT_SIZE_WEIGHTS: Array[float] = [0.10, 0.30, 0.35, 0.15, 0.05, 0.05]
## Steering odds: how often a snake keeps its heading and a curl turns.
const SNAKE_KEEP := 0.6
const CURL_TURN := 0.65


## Returns a FloorData with rooms placed, or null when no valid layout was found.
static func place(graph: FloorGraph, params: GenParams, rng: RandomNumberGenerator) -> FloorData:
	for _attempt in range(MAX_ATTEMPTS):
		var rects := _try_place(graph, params, rng)
		if rects.is_empty():
			continue
		var data := _build_data(graph, rects, rng)
		if data != null:
			return data
	return null


## Interior size for a room type, biased by `bias`: larger above 0, tighter below it
## (`ThemeProfile.ROOM_SIZE_BIAS_MIN..MAX`); `arch` multiplies the size-class odds of fight
## rooms and may turn a room on its side. Boss arenas never move.
static func size_for(
	type: FloorData.RoomType, bias: float, rng: RandomNumberGenerator, arch: FloorArchetype = null
) -> Vector2i:
	var b := clampf(bias, ThemeProfile.ROOM_SIZE_BIAS_MIN, ThemeProfile.ROOM_SIZE_BIAS_MAX)
	var size := SIZE_MEDIUM
	var may_turn := true
	match type:
		FloorData.RoomType.BOSS:
			return SIZE_ARENA
		FloorData.RoomType.START, FloorData.RoomType.STAIRS, FloorData.RoomType.SHOP:
			size = SIZE_MEDIUM if rng.randf() < 0.35 + b else SIZE_SMALL
			may_turn = type != FloorData.RoomType.START
		FloorData.RoomType.ALTAR, FloorData.RoomType.SHRINE:
			size = SIZE_MEDIUM if rng.randf() < 0.15 + b else SIZE_SMALL
		FloorData.RoomType.TREASURE:
			var r := rng.randf()
			size = SIZE_CLOSET if r < 0.45 - b * 0.5 else (SIZE_SMALL if r < 0.85 else SIZE_MEDIUM)
		FloorData.RoomType.ELITE:
			var r := rng.randf()
			size = SIZE_HALL if r < 0.15 else (SIZE_LARGE if r < 0.7 + b else SIZE_MEDIUM)
		FloorData.RoomType.TRAP:
			var r := rng.randf()
			size = SIZE_GALLERY if r < 0.3 else (SIZE_LARGE if r < 0.75 + b else SIZE_MEDIUM)
		_:
			size = SIZES[maxi(GenUtil.weighted_index(fight_size_weights(b, arch), rng), 0)]
	var turn_chance := arch.transpose_chance if arch != null else 0.3
	if may_turn and rng.randf() < turn_chance:
		size = Vector2i(size.y, size.x)
	return size


## Size-class odds of a fight room at `bias`, times the archetype's multipliers. Below 0 the
## closets and small rooms gain and the halls vanish; above it the reverse, so the light and
## open themes keep the documented bigger rooms (docs 3.3).
static func fight_size_weights(bias: float, arch: FloorArchetype) -> PackedFloat32Array:
	var b := bias
	var scale: Array[float] = [
		maxf(1.0 - 2.0 * b, 0.0),
		maxf(1.0 - 1.6 * b, 0.05),
		1.0 - absf(b) * 0.3,
		maxf(1.0 + 2.4 * b, 0.05),
		maxf(1.0 + 2.4 * b, 0.0),
		1.0,
	]
	var out := PackedFloat32Array()
	for i in range(SIZE_CLASSES.size()):
		var w := FIGHT_SIZE_WEIGHTS[i] * scale[i]
		if arch != null:
			w *= arch.size_weight(SIZE_CLASSES[i])
		out.append(w)
	return out


## Pairs of rooms (x < y) that are not already connected and lie close enough for a short
## loop corridor, nearest first. Used by FloorGraph.add_loops.
static func loop_candidates(
	data: FloorData, graph: FloorGraph, max_gap: int = 14
) -> Array[Vector2i]:
	var scored: Array[Vector3i] = []
	for a: FloorData.Room in data.rooms:
		for b: FloorData.Room in data.rooms:
			if b.id <= a.id:
				continue
			if graph.has_edge(a.id, b.id):
				continue
			if a.type == FloorData.RoomType.BOSS or b.type == FloorData.RoomType.BOSS:
				continue
			var gap := GenUtil.rect_gap(a.rect, b.rect)
			if gap > max_gap:
				continue
			scored.append(Vector3i(gap, a.id, b.id))
	scored.sort()
	var out: Array[Vector2i] = []
	for s: Vector3i in scored:
		out.append(Vector2i(s.y, s.z))
	return out


## One placement attempt. Returns interior rects indexed by room id (empty on failure).
static func _try_place(
	graph: FloorGraph, params: GenParams, rng: RandomNumberGenerator
) -> Array[Rect2i]:
	var n := graph.nodes.size()
	var arch := graph.archetype
	var rects: Array[Rect2i] = []
	rects.resize(n)
	var placed: Array[bool] = []
	placed.resize(n)
	placed.fill(false)
	var headings: Array[Vector2i] = []
	headings.resize(n)
	headings.fill(Vector2i.RIGHT)
	var spoke_count: Dictionary = {}
	var order := graph.bfs_order()
	var bbox := Rect2i()
	var gap_extra := params.room_gap_extra() + (arch.gap_delta if arch != null else 0)
	var max_gap := maxi(MIN_GAP + 1 + gap_extra, MIN_GAP)
	for id: int in order:
		var node := graph.nodes[id]
		var size := (
			SIZE_HUB
			if id == graph.hub_id
			else size_for(node.type, params.room_size_bias, rng, arch)
		)
		if node.parent < 0:
			rects[id] = Rect2i(Vector2i.ZERO, size)
			placed[id] = true
			bbox = rects[id]
			continue
		var parent := rects[node.parent]
		var spoke := int(spoke_count.get(node.parent, 0))
		spoke_count[node.parent] = spoke + 1
		var best := Rect2i()
		var best_dir := Vector2i.RIGHT
		var best_score := 1.0e18
		var found := false
		for _c in range(CANDIDATES_PER_ROOM):
			var dir := _steer(arch, graph, node, headings[node.parent], spoke, rng)
			var gap := rng.randi_range(MIN_GAP, max_gap)
			var cand := _candidate_rect(parent, size, dir, gap, rng)
			if _overlaps_any(cand, rects, placed):
				continue
			var merged := bbox.merge(cand)
			# Compact and roughly square layouts read best on the minimap and stay in bounds.
			var longest := maxi(merged.size.x, merged.size.y)
			var score := (
				float(merged.size.x * merged.size.y + longest * longest) + rng.randf() * 60.0
			)
			if score < best_score:
				best_score = score
				best = cand
				best_dir = dir
				found = true
		if not found:
			return []
		rects[id] = best
		headings[id] = best_dir
		placed[id] = true
		bbox = bbox.merge(best)
		# Bail as soon as the layout cannot possibly fit any more; no point placing the rest.
		var probe := bbox.grow(1)
		if probe.size.x + 2 * MARGIN > MAX_WIDTH or probe.size.y + 2 * MARGIN > MAX_HEIGHT:
			return []
	var ring_bbox := bbox.grow(1)
	if ring_bbox.size.x + 2 * MARGIN > MAX_WIDTH or ring_bbox.size.y + 2 * MARGIN > MAX_HEIGHT:
		return []
	var offset := Vector2i(MARGIN, MARGIN) - ring_bbox.position
	for i in range(n):
		rects[i] = Rect2i(rects[i].position + offset, rects[i].size)
	return rects


## The side of its parent a room is tried on, by the archetype's steering: a snake keeps the
## parent's heading, a curl turns the same way every time, spokes fan out from the hub one
## side each, and anything else (or any branch room) picks a side at random.
static func _steer(
	arch: FloorArchetype,
	graph: FloorGraph,
	node: FloorGraph.RoomVertex,
	heading: Vector2i,
	spoke: int,
	rng: RandomNumberGenerator
) -> Vector2i:
	var random := GenUtil.DIRS4[rng.randi_range(0, 3)]
	if arch == null:
		return random
	var roll := rng.randf()
	match arch.dir_style:
		FloorArchetype.DIR_SNAKE:
			if node.on_spine and roll < SNAKE_KEEP:
				return heading
			return random
		FloorArchetype.DIR_CURL:
			if node.on_spine and roll < CURL_TURN:
				# Turn right of the heading; the spine curls back toward the start.
				return Vector2i(-heading.y, heading.x)
			return random
		FloorArchetype.DIR_SPOKE:
			if node.parent == graph.hub_id and roll < 0.8:
				return GenUtil.DIRS4[(spoke + graph.hub_id) % 4]
			if not node.on_spine and roll < 0.5:
				return heading
			return random
		_:
			return random


static func _candidate_rect(
	parent: Rect2i, size: Vector2i, dir: Vector2i, gap: int, rng: RandomNumberGenerator
) -> Rect2i:
	var pos := Vector2i.ZERO
	if dir.x != 0:
		pos.x = parent.end.x + gap if dir.x > 0 else parent.position.x - gap - size.x
		var lo := parent.position.y - size.y + MIN_SIDE_OVERLAP
		var hi := parent.end.y - MIN_SIDE_OVERLAP
		pos.y = rng.randi_range(lo, hi)
	else:
		pos.y = parent.end.y + gap if dir.y > 0 else parent.position.y - gap - size.y
		var lo := parent.position.x - size.x + MIN_SIDE_OVERLAP
		var hi := parent.end.x - MIN_SIDE_OVERLAP
		pos.x = rng.randi_range(lo, hi)
	return Rect2i(pos, size)


static func _overlaps_any(cand: Rect2i, rects: Array[Rect2i], placed: Array[bool]) -> bool:
	var grown := cand.grow(MIN_GAP)
	for i in range(rects.size()):
		if placed[i] and grown.intersects(rects[i]):
			return true
	return false


static func _build_data(
	graph: FloorGraph, rects: Array[Rect2i], rng: RandomNumberGenerator
) -> FloorData:
	var data := FloorData.new()
	var bbox := rects[0]
	for r: Rect2i in rects:
		bbox = bbox.merge(r)
	var ring_bbox := bbox.grow(1)
	data.width = ring_bbox.end.x + MARGIN
	data.height = ring_bbox.end.y + MARGIN
	if data.width > MAX_WIDTH or data.height > MAX_HEIGHT:
		return null
	data.tiles.resize(data.width * data.height)
	data.tiles.fill(FloorData.Tile.VOID)
	for node: FloorGraph.RoomVertex in graph.nodes:
		var room := FloorData.Room.new()
		room.id = node.id
		room.type = node.type
		room.rect = rects[node.id]
		room.graph_distance = node.distance
		room.neighbors = node.neighbors.duplicate()
		data.rooms.append(room)
		var ring := room.rect.grow(1)
		for y in range(ring.position.y, ring.end.y):
			for x in range(ring.position.x, ring.end.x):
				data.set_tile(x, y, FloorData.Tile.WALL)
		for y in range(room.rect.position.y, room.rect.end.y):
			for x in range(room.rect.position.x, room.rect.end.x):
				data.set_tile(x, y, FloorData.Tile.FLOOR)
		room.shape = RoomShape.pick(room.type, room.rect.size, graph.archetype, rng)
		RoomShape.stamp(data, room, rng.randi_range(0, 3))
	data.start_room = graph.start_id
	data.stairs_room = graph.stairs_id
	data.boss_room = graph.boss_id
	if graph.archetype != null:
		data.archetype = graph.archetype.id
	return data
