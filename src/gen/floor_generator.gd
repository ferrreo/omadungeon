## Entry point of floor generation: archetype -> graph -> layout -> loops -> corridors -> fill
## -> lantern anchors -> validate.
## Pure function of (GenParams, RandomNumberGenerator); the same inputs always produce the
## same FloorData.layout_hash(). On validation failure the pipeline reruns with an rng-derived
## reseed (up to MAX_ATTEMPTS); if every attempt fails the least-broken one is returned with an
## error, and if not even one attempt produced a layout a minimal but playable fallback floor
## (start -> corridor -> stairs) is built so a run can never dead-end on an empty grid.
class_name FloorGenerator
extends RefCounted

const MAX_ATTEMPTS := 20


## Seed the layout rolls are actually made against. The desktop theme is one of generation's
## *inputs*, not a coat of paint applied afterwards, so it belongs in the seed material: docs
## §5.1 promises that the same seed under a different Omarchy theme is a different dungeon,
## and the biases alone cannot promise that - two themes whose derived scalars happen to land
## in the same buckets would otherwise roll the identical floor plan. The biases give a theme
## its character; this gives it its identity. A GenParams with no theme (`theme_hash` 0, i.e.
## a hand-built one in a test) rolls exactly as it did before the salt existed.
static func layout_seed(base_seed: int, params: GenParams) -> int:
	if params.theme_hash == 0:
		return base_seed
	return RunRng.hash_combine(base_seed, params.theme_hash)


## Generates one floor. `rng` is normally `RunRng.floor_stream(&"gen", floor_index)`.
static func generate(params: GenParams, rng: RandomNumberGenerator) -> FloorData:
	var base_seed := rng.seed
	var salted := layout_seed(base_seed, params)
	var best: FloorData = null
	var best_violations: Array[String] = []
	var attempt_rng := rng
	if salted != base_seed:
		attempt_rng = RandomNumberGenerator.new()
		attempt_rng.seed = salted
	for attempt in range(MAX_ATTEMPTS):
		var data := generate_once(params, attempt_rng)
		if data != null:
			data.seed_value = base_seed
			var violations := FloorValidator.validate(data)
			if violations.is_empty():
				return data
			if best == null or violations.size() < best_violations.size():
				best = data
				best_violations = violations
		var next_rng := RandomNumberGenerator.new()
		next_rng.seed = RunRng.hash_combine(
			RunRng.hash_combine(salted, attempt_rng.randi()), attempt + 1
		)
		attempt_rng = next_rng
	push_error(
		(
			"FloorGenerator: no valid floor after %d attempts (floor %d, seed %d): %s"
			% [MAX_ATTEMPTS, params.floor_index, base_seed, ", ".join(best_violations)]
		)
	)
	if best == null:
		best = fallback_floor(params)
	best.seed_value = base_seed
	return best


## Minimal hand-built floor used when every pipeline attempt failed: a START room and a
## STAIRS room (or BOSS arena on boss floors) joined by one straight corridor. Always valid,
## always walkable; `is_fallback` is set so RunManager can tell it apart.
static func fallback_floor(params: GenParams) -> FloorData:
	var data := FloorData.new()
	data.is_fallback = true
	data.floor_index = params.floor_index
	data.biome = params.biome
	var size := FloorLayout.SIZE_SMALL
	var goal_size := FloorLayout.SIZE_ARENA if params.is_boss_floor else FloorLayout.SIZE_SMALL
	var gap := FloorLayout.MIN_GAP
	var margin := FloorLayout.MARGIN
	var start_rect := Rect2i(Vector2i(margin + 1, margin + 1), size)
	var goal_pos := Vector2i(start_rect.end.x + gap, start_rect.position.y)
	var goal_rect := Rect2i(goal_pos, goal_size)
	data.width = goal_rect.end.x + margin + 1
	data.height = maxi(start_rect.end.y, goal_rect.end.y) + margin + 1
	data.tiles.resize(data.width * data.height)
	data.tiles.fill(FloorData.Tile.VOID)
	var start_room := _fallback_room(data, 0, FloorData.RoomType.START, start_rect)
	var goal_type := FloorData.RoomType.BOSS if params.is_boss_floor else FloorData.RoomType.STAIRS
	var goal_room := _fallback_room(data, 1, goal_type, goal_rect)
	var lane := start_rect.position.y + start_rect.size.y / 2
	var door_a := Vector2i(start_rect.end.x, lane)
	var door_b := Vector2i(goal_rect.position.x - 1, lane)
	data.set_tile(door_a.x, door_a.y, FloorData.Tile.DOOR)
	data.set_tile(door_b.x, door_b.y, FloorData.Tile.DOOR)
	start_room.doors[1] = door_a
	goal_room.doors[0] = door_b
	start_room.neighbors = [1]
	goal_room.neighbors = [0]
	start_room.graph_distance = 0
	goal_room.graph_distance = 1
	var corridor := FloorData.Corridor.new()
	corridor.from_room = 0
	corridor.to_room = 1
	for x in range(door_a.x + 1, door_b.x):
		corridor.path.append(Vector2i(x, lane))
		data.set_tile(x, lane, FloorData.Tile.CORRIDOR)
		data.set_tile(x, lane - 1, FloorData.Tile.WALL)
		data.set_tile(x, lane + 1, FloorData.Tile.WALL)
	data.corridors.append(corridor)
	data.start_room = 0
	data.stairs_room = 1
	data.boss_room = 1 if params.is_boss_floor else -1
	if params.is_boss_floor:
		goal_room.enemy_spawns = [goal_room.center()]
	return data


static func _fallback_room(
	data: FloorData, id: int, type: FloorData.RoomType, rect: Rect2i
) -> FloorData.Room:
	var room := FloorData.Room.new()
	room.id = id
	room.type = type
	room.rect = rect
	data.rooms.append(room)
	for p: Vector2i in GenUtil.rect_tiles(rect.grow(1)):
		data.set_tile(p.x, p.y, FloorData.Tile.WALL)
	for p: Vector2i in GenUtil.rect_tiles(rect):
		data.set_tile(p.x, p.y, FloorData.Tile.FLOOR)
	return room


## One pass of the pipeline without validation. Returns null when placement or carving fails.
static func generate_once(params: GenParams, rng: RandomNumberGenerator) -> FloorData:
	var arch := FloorArchetype.resolve(params, rng)
	var graph := FloorGraph.build(params, rng, arch)
	var data := FloorLayout.place(graph, params, rng)
	if data == null:
		return null
	data.seed_value = rng.seed
	data.floor_index = params.floor_index
	data.biome = params.biome
	data.archetype = arch.id
	var candidates := FloorLayout.loop_candidates(data, graph, arch.loop_max_gap)
	graph.add_loops(candidates, graph.loop_target(params), rng)
	if not CorridorCarver.carve_all(data, graph.tree_edges, graph.loop_edges, params, rng, arch):
		return null
	# Loop corridors that could not be routed without touching another corridor are dropped
	# so Room.neighbors always describes exactly what the player can walk.
	graph.prune_uncarved(data)
	graph.apply_to(data)
	var biome := Biome.load_by_id(params.biome)
	RoomFiller.fill_all(data, biome, params, rng)
	data.lantern_anchors = LanternAnchors.place(data, biome.lantern_spacing, rng)
	return data
