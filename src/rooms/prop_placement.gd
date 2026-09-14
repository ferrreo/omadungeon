## Where clutter goes in a room (docs §10 "clutter"): the placement rules `RoomFiller` calls
## once it knows which interior tiles are free, and nothing about layout itself.
##
## Three rules, and every one answers a playtest finding:
##
## * **Solid props stand in clusters against the walls and in corners**, never as confetti in
##   the middle of the room. A cluster is `CLUSTER_MIN`..`CLUSTER_MAX` solid kinds on adjacent
##   wall-side tiles, seeded in a corner `CORNER_WEIGHT` times as readily as beside a plain wall,
##   and two clusters never touch (a one-tile gap is kept between them), so a wall is never lined
##   end to end and the floor between the clusters stays open to fight in.
## * **Flat props are sparse, in the open.** `OPEN_FLAT_SHARE` of the budget goes to walk-over
##   kinds (bones, pages, a puddle) on interior tiles, no two within `FLAT_SPACING` of each other
##   and never beside a solid; they are texture, not obstacles, and nothing the player has to
##   route around.
## * **Nothing sits in a doorway or on the straight line between doors.** The caller hands in the
##   door aprons it already protects plus `door_paths()` - one shortest interior route per pair
##   of doors - and no prop of either kind lands on those tiles. A cluster beside a door is still
##   a cluster the player walks past, not through.
##
## Kinds are assigned by slot: a wall slot takes a solid kind and an open slot a flat one, and
## the track's signature kind (`accent_kind`, docs §10.2) is written onto `accent_share` of the
## room's slots before the rest are rolled, so the music lever still reaches the floor. A solid
## signature takes its share off the wall slots; a flat one fills the open slots first and lies
## beside the wall clusters for the rest, because a flat against a wall is still a flat.
##
## Every number here can be overridden from `data/rooms/rooms_content.tres` (`prop_*`), which is
## how a new room shape tunes its clutter without touching this file. Deterministic per `rng`.
##
## Cost: `place` resolves the content resource **once** and hands it to every lookup below.
## The first cut resolved it per lookup - `RoomsContent.resolve(null)` is a `ResourceLoader`
## round trip, and thirty of them a room put a 3-prop closet at 4.7 ms and a floor fill at
## nearly four times its layout time (measured by the generator's owner as ~30x on the fill
## alone). The open pass keeps a *blocked* set expanded once from what is taken instead of
## measuring every candidate against every placed prop, so a 40x30 hall costs what a closet
## does per tile.
class_name PropPlacement
extends RefCounted

## Expected props per free interior tile at density 1.0. Playtest: 0.05 read as empty, and
## the previous round's 0.08 as confetti - because it was spread evenly. Clustered against the
## walls, 0.07 reads as furnished with the middle open.
const PER_FREE_TILE := 0.07
const CLUSTER_MIN := 2
const CLUSTER_MAX := 3
const OPEN_FLAT_SHARE := 0.25
const CORNER_WEIGHT := 3.0
## Chebyshev distance two flat props keep from each other and from any solid.
const FLAT_SPACING := 2
## Chebyshev distance kept between two clusters, so a wall is never a continuous shelf.
const CLUSTER_GAP := 1

## One placed prop: the tile and the kind that goes on it.
const KEY_POS := &"pos"
const KEY_KIND := &"kind"
const KEY_SOLID := &"solid"


static func per_free_tile(content: RoomsContent = null) -> float:
	var res := RoomsContent.resolve(content)
	if res != null and res.prop_per_free_tile >= 0.0:
		return res.prop_per_free_tile
	return PER_FREE_TILE


static func cluster_min(content: RoomsContent = null) -> int:
	var res := RoomsContent.resolve(content)
	if res != null and res.prop_cluster_min > 0:
		return res.prop_cluster_min
	return CLUSTER_MIN


static func cluster_max(content: RoomsContent = null) -> int:
	var res := RoomsContent.resolve(content)
	if res != null and res.prop_cluster_max > 0:
		return maxi(res.prop_cluster_max, cluster_min(content))
	return maxi(CLUSTER_MAX, cluster_min(content))


static func open_flat_share(content: RoomsContent = null) -> float:
	var res := RoomsContent.resolve(content)
	if res != null and res.prop_open_flat_share >= 0.0:
		return clampf(res.prop_open_flat_share, 0.0, 1.0)
	return OPEN_FLAT_SHARE


static func corner_weight(content: RoomsContent = null) -> float:
	var res := RoomsContent.resolve(content)
	if res != null and res.prop_corner_weight > 0.0:
		return maxf(res.prop_corner_weight, 1.0)
	return CORNER_WEIGHT


## Expected prop count for a room with `free_tiles` free interior tiles at `density`
## (`GenParams.prop_density`) and the room type's `multiplier`.
static func expected_count(
	free_tiles: int, density: float, multiplier: float, content: RoomsContent = null
) -> float:
	return free_tiles * per_free_tile(content) * density * multiplier


## The tiles on one shortest walkable route between every pair of `doors`, as a set.
## `passable` is every tile a route may use, including the door tiles themselves. A pair with no
## route contributes nothing. This is the "direct door-to-door path" no prop may sit on.
static func door_paths(passable: Dictionary, doors: Array[Vector2i]) -> Dictionary:
	var out: Dictionary = {}
	for i in range(doors.size()):
		for j in range(i + 1, doors.size()):
			for p: Vector2i in _shortest_path(passable, doors[i], doors[j]):
				out[p] = true
	for door: Vector2i in doors:
		out.erase(door)
	return out


## Places `budget` props. `free` is every interior tile that may take one (scan order, for
## determinism); `wall_side` maps a free tile to how many of its four neighbours are wall (1 for
## a tile along a wall, 2 for a corner; tiles absent from it are in the open); `avoid` is the
## set of tiles no prop may use. Returns `[{pos, kind, solid}]`, solids first.
static func place(
	free: Array[Vector2i],
	wall_side: Dictionary,
	avoid: Dictionary,
	budget: int,
	kinds: Array[StringName],
	accent_kind: StringName,
	accent_share: float,
	rng: RandomNumberGenerator,
	content: RoomsContent = null
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if budget <= 0 or free.is_empty() or kinds.is_empty():
		return out
	# Resolved once: every helper takes `res` and `RoomsContent.resolve(res)` is then a return.
	var res := RoomsContent.resolve(content)
	var solid_of: Dictionary = {}
	var solids: Array[StringName] = []
	var flats: Array[StringName] = []
	for kind: StringName in kinds:
		var solid := Prop.is_solid(kind, res)
		solid_of[kind] = solid
		if solid:
			solids.append(kind)
		else:
			flats.append(kind)
	var flat_budget := roundi(budget * open_flat_share(res)) if not flats.is_empty() else 0
	var taken: Dictionary = {}
	var slots := wall_slots(free, wall_side, avoid, budget - flat_budget, rng, res, taken)
	var open := open_slots(free, wall_side, avoid, flat_budget, rng, taken)
	# A room with no wall side to speak of (every wall tile is a doorway) still gets its props:
	# the unspent solid budget falls through to the open floor as flats.
	if slots.size() < budget - flat_budget and not flats.is_empty():
		var extra := open_slots(
			free, wall_side, avoid, budget - flat_budget - slots.size(), rng, taken
		)
		open.append_array(extra)
	var solid_kinds := solids if not solids.is_empty() else flats
	var flat_kinds := flats if not flats.is_empty() else solids
	# The signature kind's share is of the *whole* room. A solid signature fills its share of the
	# wall slots; a flat one fills the open slots first and then lies beside the wall clusters
	# for the rest - a flat against a wall is fine (bones by a coffin), a solid in the open is
	# the thing the split exists to prevent.
	# Rounded, and never zero once there is a share at all: a closet with one prop in it shows
	# the track's kind, which is the point of a signature.
	var share := clampf(accent_share, 0.0, 1.0)
	var accents := roundi((slots.size() + open.size()) * share)
	if share > 0.0 and slots.size() + open.size() > 0:
		accents = maxi(accents, 1)
	var solid_accents := 0
	var flat_accents := 0
	if solid_kinds.has(accent_kind):
		solid_accents = accents
	elif flat_kinds.has(accent_kind):
		flat_accents = mini(accents, open.size())
		solid_accents = accents - flat_accents
	var solid_names := assign_kinds(slots.size(), solid_kinds, accent_kind, 0, rng)
	var flat_names := assign_kinds(open.size(), flat_kinds, accent_kind, flat_accents, rng)
	solid_names = with_accents(solid_names, accent_kind, solid_accents, rng)
	for i in range(slots.size()):
		var kind: StringName = solid_names[i]
		out.append({KEY_POS: slots[i], KEY_KIND: kind, KEY_SOLID: solid_of[kind]})
	for i in range(open.size()):
		var kind: StringName = flat_names[i]
		out.append({KEY_POS: open[i], KEY_KIND: kind, KEY_SOLID: solid_of[kind]})
	return out


## Up to `want` wall-side tiles in clusters (see the class comment). `taken` is filled with
## every tile used so the open pass keeps clear of them.
static func wall_slots(
	free: Array[Vector2i],
	wall_side: Dictionary,
	avoid: Dictionary,
	want: int,
	rng: RandomNumberGenerator,
	content: RoomsContent,
	taken: Dictionary
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pool: Array[Vector2i] = []
	var in_pool: Dictionary = {}
	for p: Vector2i in free:
		if wall_side.has(p) and not avoid.has(p):
			pool.append(p)
			in_pool[p] = true
	var corner := corner_weight(content)
	var lo := cluster_min(content)
	var hi := cluster_max(content)
	# The budget is spent in whole clusters: a last solid with no room for a second beside it
	# would be the lone object in the middle of a wall that this exists to end, so a remainder
	# is left to the open floor instead. The one exception is a room whose whole budget is
	# under a cluster: it gets a single object, and only in a corner, where one thing standing
	# alone reads as placed rather than dropped.
	while out.size() < want and not pool.is_empty():
		var size := mini(rng.randi_range(lo, hi), want - out.size())
		var single := size < lo
		if single and not out.is_empty():
			break
		var weights := PackedFloat32Array()
		for p: Vector2i in pool:
			var in_corner := int(wall_side[p]) >= 2
			var alone := size > 1 and not _has_neighbour(p, in_pool)
			if alone or (single and not in_corner):
				weights.append(0.0)
			else:
				weights.append(corner if in_corner else 1.0)
		var seed_index := GenUtil.weighted_index(weights, rng)
		if seed_index < 0:
			break
		var cluster: Array[Vector2i] = [pool[seed_index]]
		in_pool.erase(pool[seed_index])
		while cluster.size() < size:
			var next := _grow(cluster, in_pool, rng)
			if next == Vector2i.MAX:
				break
			cluster.append(next)
			in_pool.erase(next)
		for p: Vector2i in cluster:
			out.append(p)
			taken[p] = true
		# Keep the gap: nothing in the pool may touch this cluster any more.
		var kept: Array[Vector2i] = []
		for p: Vector2i in pool:
			if in_pool.has(p) and _distance_to(p, cluster) > CLUSTER_GAP:
				kept.append(p)
			else:
				in_pool.erase(p)
		pool = kept
	return out


## Up to `want` open-floor tiles for flat props, each `FLAT_SPACING` clear of everything placed.
static func open_slots(
	free: Array[Vector2i],
	wall_side: Dictionary,
	avoid: Dictionary,
	want: int,
	rng: RandomNumberGenerator,
	taken: Dictionary
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if want <= 0:
		return out
	# Every tile within `FLAT_SPACING` of something placed, built once and grown per placement:
	# a candidate is then one dictionary probe rather than a pass over everything taken.
	var blocked: Dictionary = {}
	for t: Vector2i in taken:
		_block_around(t, blocked)
	var pool: Array[Vector2i] = []
	for p: Vector2i in free:
		if wall_side.has(p) or avoid.has(p) or blocked.has(p):
			continue
		pool.append(p)
	GenUtil.shuffle_vec2i(pool, rng)
	while out.size() < want and not pool.is_empty():
		var p: Vector2i = pool.pop_back()
		if blocked.has(p):
			continue
		out.append(p)
		taken[p] = true
		_block_around(p, blocked)
	return out


## `count` kind names drawn from `pool`, with `accent_kind` (when the pool holds it) written
## onto `accents` of them (see `with_accents`).
static func assign_kinds(
	count: int,
	pool: Array[StringName],
	accent_kind: StringName,
	accents: int,
	rng: RandomNumberGenerator
) -> Array[StringName]:
	var out: Array[StringName] = []
	if count <= 0 or pool.is_empty():
		return out
	for _i in range(count):
		out.append(pool[rng.randi_range(0, pool.size() - 1)])
	if not pool.has(accent_kind):
		return out
	return with_accents(out, accent_kind, accents, rng)


## `names` with `accent_kind` written onto `accents` of them, chosen at random - as many as
## fit. The number is rounded by the caller from the room's share, not rolled per slot, so a
## track's signature kind is on the floor whenever there is room for it.
static func with_accents(
	names: Array[StringName], accent_kind: StringName, accents: int, rng: RandomNumberGenerator
) -> Array[StringName]:
	if accents <= 0 or accent_kind.is_empty() or names.is_empty():
		return names
	var order: Array[int] = []
	for i in range(names.size()):
		order.append(i)
	GenUtil.shuffle_ints(order, rng)
	var out := names.duplicate()
	for i in range(mini(accents, names.size())):
		out[order[i]] = accent_kind
	return out


## A pool tile 4-adjacent to the cluster, chosen at random; `Vector2i.MAX` when there is none.
static func _grow(
	cluster: Array[Vector2i], in_pool: Dictionary, rng: RandomNumberGenerator
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for c: Vector2i in cluster:
		for d: Vector2i in GenUtil.DIRS4:
			var q := c + d
			if in_pool.has(q) and not candidates.has(q):
				candidates.append(q)
	if candidates.is_empty():
		return Vector2i.MAX
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _has_neighbour(p: Vector2i, in_pool: Dictionary) -> bool:
	for d: Vector2i in GenUtil.DIRS4:
		if in_pool.has(p + d):
			return true
	return false


static func _distance_to(p: Vector2i, tiles: Array[Vector2i]) -> int:
	var best := 1 << 30
	for t: Vector2i in tiles:
		best = mini(best, GenUtil.chebyshev(p, t))
	return best


## Marks every tile within `FLAT_SPACING` (Chebyshev) of `p` in `blocked`.
static func _block_around(p: Vector2i, blocked: Dictionary) -> void:
	for dy in range(-FLAT_SPACING, FLAT_SPACING + 1):
		for dx in range(-FLAT_SPACING, FLAT_SPACING + 1):
			blocked[p + Vector2i(dx, dy)] = true


## One shortest 4-connected route from `from` to `to` over `passable`, both ends included;
## empty when there is none.
static func _shortest_path(passable: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var came: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size() and not came.has(to):
		var cur := queue[head]
		head += 1
		for d: Vector2i in GenUtil.DIRS4:
			var n := cur + d
			if came.has(n) or not passable.has(n):
				continue
			came[n] = cur
			queue.append(n)
	var path: Array[Vector2i] = []
	if not came.has(to):
		return path
	var step := to
	while step != from:
		path.append(step)
		step = came[step]
	path.append(from)
	path.reverse()
	return path
