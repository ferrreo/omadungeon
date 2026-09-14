## Abstract room graph for one floor (docs 5.1 #1, #4): a spanning tree with a guaranteed
## spine so the stairs sit >= 3 edges from the start, optional loop edges, and room types
## rolled from the per-floor `RoomBudget` (one altar or shrine, a shop where the table says,
## >= 60% fight rooms among the free pool, 0-1 each of elite / trap gauntlet / treasure).
## The `FloorArchetype` decides how long the spine is, where branches hang, whether one spine
## room is a big hub, and how many loops are added on top of the theme's own count. Boss
## floors are linear-ish whatever the archetype: start -> 2-3 rooms -> boss, side rooms
## hanging off the spine.
class_name FloorGraph
extends RefCounted

const MIN_STAIRS_DISTANCE := 3
## Tree degree cap keeps one door per side plausible; loops may add one more.
const MAX_TREE_DEGREE := 3
const MAX_DEGREE := 4
## Loops on top of the tree, after the archetype's delta.
const MAX_LOOPS := 4
## Share of the free pool (ordinary rooms minus the service rooms) that must be fight rooms.
## COMBAT, ELITE and TRAP all count as fights (RunManager treats them the same way), so a
## small floor can still afford one elite or gauntlet room.
const COMBAT_RATIO := 0.6
const OPTIONAL_TYPES: Array[int] = [
	FloorData.RoomType.ELITE, FloorData.RoomType.TRAP, FloorData.RoomType.TREASURE
]
## Room types that never count towards the free pool.
const STRUCTURAL_TYPES: Array[int] = [
	FloorData.RoomType.START, FloorData.RoomType.STAIRS, FloorData.RoomType.BOSS
]
## Service rooms: excluded from the free pool, never a fight.
const SERVICE_TYPES: Array[int] = [
	FloorData.RoomType.ALTAR, FloorData.RoomType.SHOP, FloorData.RoomType.SHRINE
]
## Types that count as a fight for the COMBAT_RATIO quota.
const FIGHT_TYPES: Array[int] = [
	FloorData.RoomType.COMBAT, FloorData.RoomType.ELITE, FloorData.RoomType.TRAP
]
## Chance a branch room of a hub floor hangs off the hub itself while it has a free side.
const HUB_ATTACH_CHANCE := 0.7


## One vertex of the graph.
class RoomVertex:
	extends RefCounted
	var id: int = 0
	var type: FloorData.RoomType = FloorData.RoomType.COMBAT
	var neighbors: Array[int] = []
	var parent: int = -1
	## Edges from start along the tree.
	var depth: int = 0
	## Edges from start over the full graph (tree + loops).
	var distance: int = 0
	## True for spine rooms (the guaranteed start -> stairs/boss path).
	var on_spine: bool = false
	## Depth below the spine for branch rooms (boss floors keep this small).
	var branch_depth: int = 0


var nodes: Array[FloorGraph.RoomVertex] = []
var tree_edges: Array[Vector2i] = []
var loop_edges: Array[Vector2i] = []
var start_id: int = 0
var stairs_id: int = 0
var boss_id: int = -1
## The big central room of a hub floor, -1 elsewhere.
var hub_id: int = -1
var is_boss_floor: bool = false
var archetype: FloorArchetype = null


## Builds tree + types from params. Deterministic for a given rng state. `arch` null rolls
## the archetype here (`FloorArchetype.resolve`), which is what a caller without one wants.
static func build(
	params: GenParams, rng: RandomNumberGenerator, arch: FloorArchetype = null
) -> FloorGraph:
	var g := FloorGraph.new()
	g.is_boss_floor = params.is_boss_floor
	g.archetype = arch if arch != null else FloorArchetype.resolve(params, rng)
	var n := maxi(params.room_count, 5)
	for i in range(n):
		var node := RoomVertex.new()
		node.id = i
		g.nodes.append(node)
	g.nodes[0].on_spine = true

	var spine_len := g._spine_length(n, rng)
	var prev := 0
	var next_id := 1
	for _s in range(spine_len):
		g._connect_tree(prev, next_id)
		g.nodes[next_id].on_spine = true
		prev = next_id
		next_id += 1
	var spine_end := prev
	if g.archetype.has_hub and not g.is_boss_floor:
		g.hub_id = rng.randi_range(1, mini(2, spine_len - 1))
	elif g.archetype.has_hub:
		g.hub_id = 1

	while next_id < n:
		var parent_id := g._pick_parent(next_id, spine_end, rng)
		g._connect_tree(parent_id, next_id)
		var parent_node := g.nodes[parent_id]
		g.nodes[next_id].branch_depth = 1 if parent_node.on_spine else parent_node.branch_depth + 1
		next_id += 1

	if g.is_boss_floor:
		g.boss_id = spine_end
		g.stairs_id = spine_end
		g.nodes[spine_end].type = FloorData.RoomType.BOSS
	else:
		g.stairs_id = g._deepest_leaf(rng)
		g.nodes[g.stairs_id].type = FloorData.RoomType.STAIRS
	g.nodes[g.start_id].type = FloorData.RoomType.START
	g._assign_types(params.floor_index, rng)
	g.compute_distances()
	return g


## Minimum number of fight rooms (COMBAT/ELITE/TRAP) for a free pool of `free_pool` rooms.
static func combat_quota(free_pool: int) -> int:
	return ceili(COMBAT_RATIO * maxi(free_pool, 0))


## Loops the floor asks for: the theme's count plus the archetype's delta, 0..MAX_LOOPS.
func loop_target(params: GenParams) -> int:
	var delta := archetype.loop_delta if archetype != null else 0
	return clampi(params.extra_loops + delta, 0, MAX_LOOPS)


## Degree cap of one node for tree edges (the hub gets more sides).
func tree_degree_cap(id: int) -> int:
	return FloorArchetype.HUB_MAX_DEGREE if id == hub_id else MAX_TREE_DEGREE


## Degree cap of one node once loops are added.
func degree_cap(id: int) -> int:
	return FloorArchetype.HUB_MAX_DEGREE if id == hub_id else MAX_DEGREE


## Adds up to `max_count` loop edges from `candidates` (pairs of room ids, x < y). Edges that
## would drop the stairs/boss below MIN_STAIRS_DISTANCE, touch the boss room or exceed the
## degree cap are skipped. A ring archetype spends its first loop closing the spine back on
## the start's neighbourhood: the candidate pair whose graph distances differ most.
func add_loops(candidates: Array[Vector2i], max_count: int, rng: RandomNumberGenerator) -> void:
	var pool := candidates.duplicate()
	GenUtil.shuffle_vec2i(pool, rng)
	var added := 0
	if archetype != null and archetype.closes_ring and max_count > 0:
		var closing := _ring_closer(pool)
		if closing.x >= 0 and _try_loop(closing):
			pool.erase(closing)
			added += 1
	for pair: Vector2i in pool:
		if added >= max_count:
			break
		if _try_loop(pair):
			added += 1


func _try_loop(pair: Vector2i) -> bool:
	if pair.x == pair.y or pair.x < 0 or pair.y >= nodes.size():
		return false
	if pair.x == boss_id or pair.y == boss_id:
		return false
	if has_edge(pair.x, pair.y):
		return false
	var a := nodes[pair.x]
	var b := nodes[pair.y]
	if a.neighbors.size() >= degree_cap(a.id) or b.neighbors.size() >= degree_cap(b.id):
		return false
	a.neighbors.append(b.id)
	b.neighbors.append(a.id)
	compute_distances()
	if nodes[stairs_id].distance < MIN_STAIRS_DISTANCE:
		a.neighbors.erase(b.id)
		b.neighbors.erase(a.id)
		compute_distances()
		return false
	loop_edges.append(Vector2i(mini(a.id, b.id), maxi(a.id, b.id)))
	return true


## The candidate pair that would close the longest ring: both rooms on the spine, farthest
## apart along it. Vector2i(-1, -1) when no candidate joins two spine rooms.
func _ring_closer(pool: Array[Vector2i]) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_span := 1
	for pair: Vector2i in pool:
		if pair.x < 0 or pair.y >= nodes.size():
			continue
		if not nodes[pair.x].on_spine or not nodes[pair.y].on_spine:
			continue
		var span := absi(nodes[pair.x].depth - nodes[pair.y].depth)
		if span > best_span:
			best_span = span
			best = pair
	return best


## Drops loop edges the carver could not route (no door pair on `data`) so the graph always
## matches what was actually carved. Tree edges are mandatory and never pruned.
func prune_uncarved(data: FloorData) -> void:
	var kept: Array[Vector2i] = []
	for pair: Vector2i in loop_edges:
		var a := data.room_by_id(pair.x)
		var b := data.room_by_id(pair.y)
		if a != null and b != null and a.doors.has(pair.y) and b.doors.has(pair.x):
			kept.append(pair)
			continue
		nodes[pair.x].neighbors.erase(pair.y)
		nodes[pair.y].neighbors.erase(pair.x)
	loop_edges = kept
	compute_distances()


func has_edge(a: int, b: int) -> bool:
	return b in nodes[a].neighbors


func all_edges() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(tree_edges)
	out.append_array(loop_edges)
	return out


## BFS distance from start over tree + loops, stored in `RoomVertex.distance`.
func compute_distances() -> void:
	for node: FloorGraph.RoomVertex in nodes:
		node.distance = -1
	var queue: Array[int] = [start_id]
	nodes[start_id].distance = 0
	var head := 0
	while head < queue.size():
		var cur := nodes[queue[head]]
		head += 1
		for nb: int in cur.neighbors:
			if nodes[nb].distance < 0:
				nodes[nb].distance = cur.distance + 1
				queue.append(nb)


## Tree order from the start (parents before children).
func bfs_order() -> Array[int]:
	var order: Array[int] = [start_id]
	var head := 0
	while head < order.size():
		var cur := order[head]
		head += 1
		for nb: int in nodes[cur].neighbors:
			if nodes[nb].parent == cur:
				order.append(nb)
	return order


func count_type(type: FloorData.RoomType) -> int:
	var c := 0
	for node: FloorGraph.RoomVertex in nodes:
		if node.type == type:
			c += 1
	return c


## Copies types, neighbours, distances and special room ids onto the FloorData rooms.
func apply_to(data: FloorData) -> void:
	for node: FloorGraph.RoomVertex in nodes:
		var room := data.room_by_id(node.id)
		if room == null:
			continue
		room.type = node.type
		room.neighbors = node.neighbors.duplicate()
		room.graph_distance = node.distance
	data.start_room = start_id
	data.stairs_room = stairs_id
	data.boss_room = boss_id
	if archetype != null:
		data.archetype = archetype.id


func _connect_tree(parent_id: int, child_id: int) -> void:
	nodes[parent_id].neighbors.append(child_id)
	nodes[child_id].neighbors.append(parent_id)
	nodes[child_id].parent = parent_id
	nodes[child_id].depth = nodes[parent_id].depth + 1
	tree_edges.append(Vector2i(parent_id, child_id))


## Rooms on the spine past the start: boss floors 3-4, otherwise the archetype's share of
## the floor, jittered by one, and always 3..n-2 so branches and the stairs leaf exist.
func _spine_length(n: int, rng: RandomNumberGenerator) -> int:
	if is_boss_floor:
		return rng.randi_range(3, 4)
	var wanted := int(round(archetype.spine_share * n)) + rng.randi_range(-1, 1)
	return clampi(wanted, 3, n - 2)


## Parent for branch room `child`, by the archetype's branch style. Never the spine end (the
## exit stays a leaf), never past the degree cap or the branch-depth cap. Falls back to the
## previous room when every candidate is exhausted (cannot happen for n <= 13, but stay safe).
func _pick_parent(child: int, spine_end: int, rng: RandomNumberGenerator) -> int:
	var style := archetype.branch_style
	var depth_cap := 2 if is_boss_floor else archetype.max_branch_depth
	if is_boss_floor and style == FloorArchetype.BRANCH_HUB:
		style = FloorArchetype.BRANCH_ANY
	if style == FloorArchetype.BRANCH_HUB and hub_id >= 0:
		var hub := nodes[hub_id]
		if hub.neighbors.size() < tree_degree_cap(hub_id) and rng.randf() < HUB_ATTACH_CHANCE:
			return hub_id
	var candidates: Array[int] = []
	for node: FloorGraph.RoomVertex in nodes:
		if node.id >= child:
			break
		if node.id == spine_end or node.neighbors.size() >= tree_degree_cap(node.id):
			continue
		if node.branch_depth >= depth_cap:
			continue
		if style == FloorArchetype.BRANCH_SPINE and not node.on_spine:
			continue
		candidates.append(node.id)
	if candidates.is_empty():
		for node: FloorGraph.RoomVertex in nodes:
			if node.id < child and node.id != spine_end and node.neighbors.size() < MAX_TREE_DEGREE:
				candidates.append(node.id)
	if candidates.is_empty():
		return child - 1
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _deepest_leaf(rng: RandomNumberGenerator) -> int:
	var best_depth := -1
	var best: Array[int] = []
	for node: FloorGraph.RoomVertex in nodes:
		if node.id == start_id or node.id == hub_id:
			continue
		if node.depth > best_depth:
			best_depth = node.depth
			best = [node.id]
		elif node.depth == best_depth:
			best.append(node.id)
	return best[rng.randi_range(0, best.size() - 1)]


## Assigns the `RoomBudget` roll to the ordinary rooms: dead ends take the services and the
## treasure room, through-rooms take the elite and the gauntlet, the hub is always a fight.
func _assign_types(floor_index: int, rng: RandomNumberGenerator) -> void:
	var leaves: Array[int] = []
	var inner: Array[int] = []
	for node: FloorGraph.RoomVertex in nodes:
		if node.id == start_id or node.id == stairs_id or node.id == boss_id or node.id == hub_id:
			continue
		if node.neighbors.size() == 1:
			leaves.append(node.id)
		else:
			inner.append(node.id)
	GenUtil.shuffle_ints(leaves, rng)
	GenUtil.shuffle_ints(inner, rng)
	# Front of the list prefers dead ends (shops, altars, treasure); back prefers through-rooms.
	var ordered: Array[int] = []
	ordered.append_array(leaves)
	ordered.append_array(inner)
	var ordinary := ordered.size() + (1 if hub_id >= 0 else 0)
	var types := RoomBudget.roll(floor_index, ordinary, rng)
	for node: FloorGraph.RoomVertex in nodes:
		if node.id != start_id and node.id != stairs_id and node.id != boss_id:
			node.type = FloorData.RoomType.COMBAT
	if hub_id >= 0:
		# The hub is the floor's crossroads: an elite holds it when one was rolled, else a fight.
		var elite_at := types.find(FloorData.RoomType.ELITE)
		if elite_at >= 0:
			nodes[hub_id].type = FloorData.RoomType.ELITE
			types.remove_at(elite_at)
		else:
			types.erase(FloorData.RoomType.COMBAT)
	var front := 0
	var back := ordered.size() - 1
	for type: int in types:
		if front > back:
			break
		match type:
			FloorData.RoomType.ELITE, FloorData.RoomType.TRAP:
				nodes[ordered[back]].type = type as FloorData.RoomType
				back -= 1
			FloorData.RoomType.COMBAT:
				pass
			_:
				nodes[ordered[front]].type = type as FloorData.RoomType
				front += 1
