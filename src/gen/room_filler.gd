## Fills room interiors (docs 5.1 #5): picks a RoomTemplate (pillars, ring, pits...), scatters
## props by `prop_density`, traps by `trap_density` (kinds filtered by biome), enemy spawn
## points (never within DOOR_CLEARANCE tiles of a door; a boss across the arena from its door,
## see `ArenaSpawns`) and rolls the per-room palette
## variant (60/20/15/5, docs 10). Template weights are biased by `GenParams.template_bias`,
## the theme/wallpaper/track tie-break of docs 3.3, 3.4, 10.2.
## Every placement keeps every door of the room reachable from every
## other door, with props and traps treated as blocked, and every enemy spawn sits on a
## tile that is still reachable from a door once props, pits and template walls are solid.
class_name RoomFiller
extends RefCounted

const TEMPLATES_DIR := "res://data/rooms/"
const TEMPLATE_IDS: Array[StringName] = [
	&"empty", &"pillars", &"cross", &"ring", &"rubble", &"pits", &"vault"
]
## Spawn points keep this Chebyshev distance from every door tile of their room.
const DOOR_CLEARANCE := 3
## Props one room may hold. The cap used to be flat, so the biggest hall on a floor was held
## to the same eight objects a closet was and a vivid theme's density lever stopped meaning
## anything above it. It now grows with the room's own free area, up to `MAX_PROPS_LARGE`;
## a room under 160 free tiles keeps the old cap, and `doors_connected` still prunes anything
## that would actually block a door.
const MAX_PROPS := 8
const MAX_PROPS_LARGE := 16
const FREE_TILES_PER_PROP_CAP := 20
## Expected props per free tile is `PropPlacement.per_free_tile()` (`rooms_content.tres`), and so
## are the cluster rules; this file only decides how many a room may hold.
const MAX_TRAPS := 12
## Room types whose centre (3x3) stays free for a placed object (stairs, altar, boss...).
const CENTER_RESERVED: Array[int] = [
	FloorData.RoomType.START,
	FloorData.RoomType.STAIRS,
	FloorData.RoomType.BOSS,
	FloorData.RoomType.ALTAR,
	FloorData.RoomType.SHOP,
	FloorData.RoomType.SHRINE,
	FloorData.RoomType.TREASURE,
]
## Room types that always use the empty template.
const ALWAYS_EMPTY: Array[int] = [
	FloorData.RoomType.START,
	FloorData.RoomType.ALTAR,
	FloorData.RoomType.SHOP,
	FloorData.RoomType.SHRINE,
]
## Trap kinds that sit on the wall ring instead of the floor.
const WALL_TRAPS: Array[StringName] = [&"arrow_wall"]


## Scratch state for one room while it is being filled.
class RoomCtx:
	extends RefCounted
	var room: FloorData.Room
	## Interior tiles that are not walkable any more (template walls/pits, props).
	var blocked: Dictionary = {}
	## Interior tiles that must stay free (door aprons, reserved centre).
	var protected: Dictionary = {}
	## Interior tiles occupied by floor traps (walkable, but avoided by spawns/props).
	var trapped: Dictionary = {}
	var template_changes: Array[Vector2i] = []
	## Props added by a mask template, so a reverted template takes them with it.
	var template_props: int = 0


static func fill_all(
	data: FloorData, biome: Biome, params: GenParams, rng: RandomNumberGenerator
) -> void:
	var templates := load_templates()
	for room: FloorData.Room in data.rooms:
		fill_room(data, room, biome, params, rng, templates)


static func fill_room(
	data: FloorData,
	room: FloorData.Room,
	biome: Biome,
	params: GenParams,
	rng: RandomNumberGenerator,
	templates: Array[RoomTemplate]
) -> void:
	var ctx := RoomCtx.new()
	ctx.room = room
	_mark_protected(data, ctx)
	_apply_template(data, ctx, biome, params, rng, templates)
	_place_props(data, ctx, biome, params, rng)
	_place_traps(data, ctx, biome, params, rng)
	_place_spawns(data, ctx, params, rng)
	room.palette_variant = roll_palette_variant(rng)


## Loads data/rooms/<id>.tres for every known template id (missing ones are skipped).
static func load_templates() -> Array[RoomTemplate]:
	var out: Array[RoomTemplate] = []
	for id: StringName in TEMPLATE_IDS:
		var path := TEMPLATES_DIR + String(id) + ".tres"
		if ResourceLoader.exists(path):
			var t := load(path) as RoomTemplate
			if t != null:
				out.append(t)
	if out.is_empty():
		var empty := RoomTemplate.new()
		empty.id = &"empty"
		empty.pattern = &"empty"
		out.append(empty)
	return out


## 60% base, 20% accent shift, 15% warm/cool push, 5% inverted lighting.
static func roll_palette_variant(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.6:
		return 0
	if r < 0.8:
		return 1
	if r < 0.95:
		return 2
	return 3


## True when every door of `room` can reach every other door through walkable interior
## tiles, treating `blocked` (and `trapped` if `traps_block`) as solid.
static func doors_connected(data: FloorData, ctx: RoomCtx, traps_block: bool) -> bool:
	var doors := ctx.room.doors.values()
	if doors.size() <= 1 and ctx.protected.is_empty():
		return true
	var origin: Vector2i = doors[0] if not doors.is_empty() else ctx.room.center()
	var seen: Dictionary = {origin: true}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	var rect := ctx.room.rect
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for d: Vector2i in GenUtil.DIRS4:
			var n := cur + d
			if seen.has(n):
				continue
			if rect.has_point(n):
				if not data.is_walkable(n.x, n.y) or ctx.blocked.has(n):
					continue
				if traps_block and ctx.trapped.has(n):
					continue
			elif data.get_tile(n.x, n.y) != FloorData.Tile.DOOR or not _is_room_door(ctx.room, n):
				continue
			seen[n] = true
			queue.append(n)
	for door: Vector2i in doors:
		if not seen.has(door):
			return false
	for p: Vector2i in ctx.protected.keys():
		if not seen.has(p):
			return false
	return true


static func _is_room_door(room: FloorData.Room, p: Vector2i) -> bool:
	for door: Vector2i in room.doors.values():
		if door == p:
			return true
	return false


static func _mark_protected(data: FloorData, ctx: RoomCtx) -> void:
	var rect := ctx.room.rect
	for door: Vector2i in ctx.room.doors.values():
		var inward := Vector2i.ZERO
		for d: Vector2i in GenUtil.DIRS4:
			if rect.has_point(door + d):
				inward = d
				break
		var apron := door + inward
		for d: Vector2i in GenUtil.DIRS8:
			var p := apron + d
			if rect.has_point(p):
				ctx.protected[p] = true
		ctx.protected[apron] = true
		ctx.protected[apron + inward] = true
	if ctx.room.type in CENTER_RESERVED:
		var c := ctx.room.center()
		for y in range(-1, 2):
			for x in range(-1, 2):
				var p := c + Vector2i(x, y)
				if rect.has_point(p):
					ctx.protected[p] = true
	# Only floor can be kept free: a shape cut-out (`RoomShape`) next to a door apron is wall
	# already, and asking `doors_connected` to reach it would fail every fill of the room.
	for p: Vector2i in ctx.protected.keys():
		if data.get_tile(p.x, p.y) != FloorData.Tile.FLOOR:
			ctx.protected.erase(p)


static func _apply_template(
	data: FloorData,
	ctx: RoomCtx,
	biome: Biome,
	params: GenParams,
	rng: RandomNumberGenerator,
	templates: Array[RoomTemplate]
) -> void:
	var room := ctx.room
	var chosen: RoomTemplate = null
	if room.type in ALWAYS_EMPTY:
		chosen = _find_template(templates, &"empty")
	else:
		var fitting: Array[RoomTemplate] = []
		var weights := PackedFloat32Array()
		for t: RoomTemplate in templates:
			if not t.fits(room.rect.size, room.type, biome.id) or not biome.allows_template(t.id):
				continue
			fitting.append(t)
			weights.append(t.weight_in(biome.id) * params.template_bias(t.id))
		var idx := GenUtil.weighted_index(weights, rng)
		if idx >= 0:
			chosen = fitting[idx]
	if chosen == null:
		room.fill_template = &"empty"
		return
	room.fill_template = chosen.id
	if not chosen.mask.is_empty():
		_stamp_mask(data, ctx, chosen)
	else:
		match chosen.pattern:
			&"pillars":
				_pattern_pillars(data, ctx, chosen)
			&"cross":
				_pattern_cross(data, ctx, chosen)
			&"ring":
				_pattern_ring(data, ctx, chosen)
			&"rubble":
				_pattern_rubble(data, ctx, chosen, rng)
			&"pits":
				_pattern_pits(data, ctx, chosen, rng)
			_:
				pass
	if not doors_connected(data, ctx, false):
		_revert_template(data, ctx)
		room.fill_template = &"empty"


static func _find_template(templates: Array[RoomTemplate], id: StringName) -> RoomTemplate:
	for t: RoomTemplate in templates:
		if t.id == id:
			return t
	return null


static func _revert_template(data: FloorData, ctx: RoomCtx) -> void:
	for p: Vector2i in ctx.template_changes:
		data.set_tile(p.x, p.y, FloorData.Tile.FLOOR)
		ctx.blocked.erase(p)
	ctx.template_changes.clear()
	while ctx.template_props > 0 and not ctx.room.prop_positions.is_empty():
		var p: Vector2i = ctx.room.prop_positions.pop_back()
		ctx.room.prop_kinds.pop_back()
		ctx.blocked.erase(p)
		ctx.template_props -= 1


## Sets an interior tile to WALL or PIT if it is free; returns true on success.
static func _carve(data: FloorData, ctx: RoomCtx, p: Vector2i, tile: FloorData.Tile) -> bool:
	if not ctx.room.rect.has_point(p) or ctx.protected.has(p) or ctx.blocked.has(p):
		return false
	if data.get_tile(p.x, p.y) != FloorData.Tile.FLOOR:
		return false
	data.set_tile(p.x, p.y, tile)
	ctx.blocked[p] = true
	ctx.template_changes.append(p)
	return true


## Evenly spread coordinates along one axis with at least 2 tiles from each wall.
static func _grid_coords(origin: int, size: int, spacing: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var usable := size - 4
	if usable < 1:
		return out
	var count := usable / maxi(spacing, 1) + 1
	var span := (count - 1) * spacing
	if span > usable:
		count -= 1
		span = (count - 1) * spacing
	var start := origin + 2 + (usable - span) / 2
	for i in range(count):
		out.append(start + i * spacing)
	return out


static func _pattern_pillars(data: FloorData, ctx: RoomCtx, t: RoomTemplate) -> void:
	var r := ctx.room.rect
	for y: int in _grid_coords(r.position.y, r.size.y, t.spacing):
		for x: int in _grid_coords(r.position.x, r.size.x, t.spacing):
			_carve(data, ctx, Vector2i(x, y), FloorData.Tile.WALL)


static func _pattern_cross(data: FloorData, ctx: RoomCtx, t: RoomTemplate) -> void:
	var r := ctx.room.rect
	var c := ctx.room.center()
	var spacing := maxi(t.spacing, 2)
	var k := 1
	while true:
		var placed := false
		for p: Vector2i in [
			Vector2i(c.x - k * spacing, c.y),
			Vector2i(c.x + k * spacing, c.y),
			Vector2i(c.x, c.y - k * spacing),
			Vector2i(c.x, c.y + k * spacing),
		]:
			if (
				p.x >= r.position.x + 2
				and p.x < r.end.x - 2
				and p.y >= r.position.y + 2
				and p.y < r.end.y - 2
			):
				_carve(data, ctx, p, FloorData.Tile.WALL)
				placed = true
		if not placed:
			break
		k += 1


static func _pattern_ring(data: FloorData, ctx: RoomCtx, _t: RoomTemplate) -> void:
	var inner := ctx.room.rect.grow(-2)
	if inner.size.x < 3 or inner.size.y < 3:
		return
	var mid_x := inner.position.x + inner.size.x / 2
	var mid_y := inner.position.y + inner.size.y / 2
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var on_edge := (
				x == inner.position.x
				or x == inner.end.x - 1
				or y == inner.position.y
				or y == inner.end.y - 1
			)
			if not on_edge:
				continue
			var gap_x := absi(x - mid_x) <= 1 and (y == inner.position.y or y == inner.end.y - 1)
			var gap_y := absi(y - mid_y) <= 1 and (x == inner.position.x or x == inner.end.x - 1)
			if gap_x or gap_y:
				continue
			_carve(data, ctx, Vector2i(x, y), FloorData.Tile.WALL)


static func _pattern_rubble(
	data: FloorData, ctx: RoomCtx, t: RoomTemplate, rng: RandomNumberGenerator
) -> void:
	var r := ctx.room.rect
	var area := r.size.x * r.size.y
	var count := clampi(int(round(area * 0.04 * t.density)), 2, 7)
	var tries := 0
	var placed := 0
	while placed < count and tries < count * 8:
		tries += 1
		var p := Vector2i(
			rng.randi_range(r.position.x + 1, r.end.x - 2),
			rng.randi_range(r.position.y + 1, r.end.y - 2)
		)
		var crowded := false
		for d: Vector2i in GenUtil.DIRS4:
			if ctx.blocked.has(p + d):
				crowded = true
				break
		if crowded:
			continue
		if _carve(data, ctx, p, FloorData.Tile.WALL):
			placed += 1


static func _pattern_pits(
	data: FloorData, ctx: RoomCtx, t: RoomTemplate, rng: RandomNumberGenerator
) -> void:
	var r := ctx.room.rect
	var area := r.size.x * r.size.y
	var pools := 1
	if area > 100:
		pools += 1
	if area > 200:
		pools += 1
	pools = maxi(1, int(round(pools * clampf(t.density * 2.0, 0.5, 1.5))))
	for _i in range(pools):
		var size := Vector2i(rng.randi_range(2, 3), rng.randi_range(2, 3))
		if r.size.x - 4 < size.x or r.size.y - 4 < size.y:
			continue
		var pos := Vector2i(
			rng.randi_range(r.position.x + 2, r.end.x - 2 - size.x),
			rng.randi_range(r.position.y + 2, r.end.y - 2 - size.y)
		)
		var pool := Rect2i(pos, size)
		var free := true
		for p: Vector2i in GenUtil.rect_tiles(pool.grow(1)):
			if ctx.protected.has(p) or ctx.blocked.has(p):
				free = false
				break
		if not free:
			continue
		for p: Vector2i in GenUtil.rect_tiles(pool):
			_carve(data, ctx, p, FloorData.Tile.PIT)


static func _stamp_mask(data: FloorData, ctx: RoomCtx, t: RoomTemplate) -> void:
	var lines := t.mask_lines()
	var r := ctx.room.rect
	var mask_w := 0
	for line: String in lines:
		mask_w = maxi(mask_w, line.length())
	var origin := r.position + Vector2i((r.size.x - mask_w) / 2, (r.size.y - lines.size()) / 2)
	for y in range(lines.size()):
		var line := lines[y]
		for x in range(line.length()):
			var p := origin + Vector2i(x, y)
			match line[x]:
				RoomTemplate.MASK_WALL:
					_carve(data, ctx, p, FloorData.Tile.WALL)
				RoomTemplate.MASK_PIT:
					_carve(data, ctx, p, FloorData.Tile.PIT)
				RoomTemplate.MASK_PROP:
					if _free_floor(data, ctx, p):
						ctx.room.prop_positions.append(p)
						ctx.room.prop_kinds.append(&"rubble")
						ctx.blocked[p] = true
						ctx.template_props += 1
				_:
					pass


static func _free_floor(data: FloorData, ctx: RoomCtx, p: Vector2i) -> bool:
	return (
		ctx.room.rect.has_point(p)
		and data.get_tile(p.x, p.y) == FloorData.Tile.FLOOR
		and not ctx.blocked.has(p)
		and not ctx.protected.has(p)
		and not ctx.trapped.has(p)
	)


static func _free_tiles(data: FloorData, ctx: RoomCtx) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in GenUtil.rect_tiles(ctx.room.rect):
		if _free_floor(data, ctx, p):
			out.append(p)
	return out


static func _prop_multiplier(type: FloorData.RoomType) -> float:
	match type:
		FloorData.RoomType.START:
			return 0.5
		FloorData.RoomType.ELITE:
			return 0.7
		FloorData.RoomType.TRAP:
			return 0.4
		FloorData.RoomType.TREASURE:
			return 1.2
		FloorData.RoomType.ALTAR, FloorData.RoomType.SHRINE:
			return 0.6
		FloorData.RoomType.SHOP:
			return 0.5
		FloorData.RoomType.BOSS:
			return 0.3
		_:
			return 1.0


## Props a room with `free_tiles` walkable tiles may hold (see `MAX_PROPS`).
static func prop_cap(free_tiles: int) -> int:
	return clampi(free_tiles / FREE_TILES_PER_PROP_CAP, MAX_PROPS, MAX_PROPS_LARGE)


static func _place_props(
	data: FloorData, ctx: RoomCtx, biome: Biome, params: GenParams, rng: RandomNumberGenerator
) -> void:
	var room := ctx.room
	if biome.prop_kinds.is_empty():
		return
	var free := _free_tiles(data, ctx)
	var expected := PropPlacement.expected_count(
		free.size(), params.prop_density, _prop_multiplier(room.type)
	)
	var count := mini(_roll_count(expected, rng), prop_cap(free.size()))
	if count <= 0:
		return
	# The placement rules live in `PropPlacement` (rooms module); this only hands them what the
	# fill already knows: which free tiles hug a wall, and which tiles a door route needs.
	var wall_side: Dictionary = {}
	var passable: Dictionary = {}
	for p: Vector2i in free:
		passable[p] = true
		var walls := 0
		for d: Vector2i in GenUtil.DIRS4:
			var q := p + d
			if not room.rect.has_point(q) and data.get_tile(q.x, q.y) == FloorData.Tile.WALL:
				walls += 1
		if walls > 0:
			wall_side[p] = walls
	for p: Vector2i in ctx.protected.keys():
		if data.is_walkable(p.x, p.y) and not ctx.blocked.has(p):
			passable[p] = true
	var doors: Array[Vector2i] = []
	for door: Vector2i in room.doors.values():
		doors.append(door)
		passable[door] = true
	var avoid := PropPlacement.door_paths(passable, doors)
	var accent_kind := &""
	if params.accent_prop >= 0:
		accent_kind = biome.prop_kinds[params.accent_prop % biome.prop_kinds.size()]
	var placed := PropPlacement.place(
		free,
		wall_side,
		avoid,
		count,
		biome.prop_kinds,
		accent_kind,
		MusicLevers.shared().accent_share,
		rng
	)
	for entry: Dictionary in placed:
		var p: Vector2i = entry[PropPlacement.KEY_POS]
		room.prop_positions.append(p)
		room.prop_kinds.append(entry[PropPlacement.KEY_KIND] as StringName)
		ctx.blocked[p] = true
	while not doors_connected(data, ctx, false) and not room.prop_positions.is_empty():
		var last: Vector2i = room.prop_positions.pop_back()
		room.prop_kinds.pop_back()
		ctx.blocked.erase(last)


static func _trap_expectation(type: FloorData.RoomType, density: float) -> float:
	match type:
		FloorData.RoomType.TRAP:
			return 5.0 + density * 6.0
		FloorData.RoomType.COMBAT:
			return density * 2.2
		FloorData.RoomType.ELITE:
			return density * 1.2
		FloorData.RoomType.TREASURE:
			return 1.0 + density * 2.0
		FloorData.RoomType.STAIRS:
			return density * 0.8
		_:
			return 0.0


static func _roll_count(expected: float, rng: RandomNumberGenerator) -> int:
	var base := int(floor(expected))
	var frac := expected - base
	return base + (1 if rng.randf() < frac else 0)


static func _place_traps(
	data: FloorData, ctx: RoomCtx, biome: Biome, params: GenParams, rng: RandomNumberGenerator
) -> void:
	var room := ctx.room
	if biome.trap_kinds.is_empty():
		return
	var count := mini(
		_roll_count(_trap_expectation(room.type, params.trap_density), rng), MAX_TRAPS
	)
	if count <= 0:
		return
	var floor_kinds: Array[StringName] = []
	var wall_kinds: Array[StringName] = []
	for kind: StringName in biome.trap_kinds:
		if (
			kind == &"mimic_chest"
			and room.type != FloorData.RoomType.TREASURE
			and room.type != FloorData.RoomType.COMBAT
		):
			continue
		if kind in WALL_TRAPS:
			wall_kinds.append(kind)
		else:
			floor_kinds.append(kind)
	var free := _free_tiles(data, ctx)
	if room.type == FloorData.RoomType.TRAP:
		# Gauntlet: prefer a checkerboard so the room reads as a pattern to weave through.
		var board: Array[Vector2i] = []
		var rest: Array[Vector2i] = []
		for p: Vector2i in free:
			if (p.x + p.y) % 2 == 0:
				board.append(p)
			else:
				rest.append(p)
		GenUtil.shuffle_vec2i(board, rng)
		GenUtil.shuffle_vec2i(rest, rng)
		free = board
		free.append_array(rest)
	else:
		GenUtil.shuffle_vec2i(free, rng)
	var wall_slots := _wall_trap_slots(data, ctx)
	GenUtil.shuffle_vec2i(wall_slots, rng)
	var mimic_used := false
	var free_idx := 0
	for _i in range(count):
		var use_wall := (
			not wall_kinds.is_empty() and rng.randf() < 0.25 and not wall_slots.is_empty()
		)
		if use_wall or floor_kinds.is_empty():
			if wall_slots.is_empty() or wall_kinds.is_empty():
				continue
			# Re-check the slot rather than trusting the list: `_wall_trap_slots` runs once,
			# before any of this loop's pit traps have turned floor tiles into PIT, so a slot
			# that was aimed at open floor when it was collected can be aiming into a hole by
			# the time it is used - and a wall trap that fires into a pit fires into nothing.
			var wp := Vector2i(-1, -1)
			while not wall_slots.is_empty():
				var cand: Vector2i = wall_slots.pop_back()
				var front := cand + _inward_normal(room, cand)
				if (
					data.get_tile(front.x, front.y) == FloorData.Tile.FLOOR
					and not ctx.blocked.has(front)
				):
					wp = cand
					break
			if wp.x < 0:
				continue
			var wkind := wall_kinds[_pick_kind(wall_kinds, params, rng)]
			room.trap_positions.append({"pos": wp, "kind": wkind, "dir": _inward_normal(room, wp)})
			continue
		var kind := floor_kinds[_pick_kind(floor_kinds, params, rng)]
		if kind == &"mimic_chest":
			if mimic_used:
				continue
			mimic_used = true
		var p := Vector2i(-1, -1)
		while free_idx < free.size():
			var cand := free[free_idx]
			free_idx += 1
			if _free_floor(data, ctx, cand):
				p = cand
				break
		if p.x < 0:
			break
		if kind == &"pit":
			data.set_tile(p.x, p.y, FloorData.Tile.PIT)
			ctx.blocked[p] = true
		else:
			ctx.trapped[p] = true
		room.trap_positions.append({"pos": p, "kind": kind, "dir": Vector2i.ZERO})
	while not doors_connected(data, ctx, true):
		# Only floor traps and pits can block a path; wall-mounted traps never do, so they
		# are kept instead of being thrown away by a blind pop_back().
		var idx := -1
		for i in range(room.trap_positions.size() - 1, -1, -1):
			var pos: Vector2i = room.trap_positions[i]["pos"]
			if ctx.trapped.has(pos) or ctx.blocked.has(pos):
				idx = i
				break
		if idx < 0:
			break
		var last: Dictionary = room.trap_positions[idx]
		room.trap_positions.remove_at(idx)
		var lp: Vector2i = last["pos"]
		var lkind: StringName = last["kind"]
		if lkind == &"pit":
			data.set_tile(lp.x, lp.y, FloorData.Tile.FLOOR)
			ctx.blocked.erase(lp)
		ctx.trapped.erase(lp)
	_drop_wall_traps_aimed_at_nothing(data, ctx)


## Index of one trap kind rolled from `kinds`, weighted by the theme's hazard tilt
## (`GenParams.trap_kind_weight`). One rng draw, like the uniform pick it replaced.
static func _pick_kind(
	kinds: Array[StringName], params: GenParams, rng: RandomNumberGenerator
) -> int:
	var weights := PackedFloat32Array()
	for kind: StringName in kinds:
		weights.append(params.trap_kind_weight(kind))
	return maxi(GenUtil.weighted_index(weights, rng), 0)


## Removes wall traps whose muzzle no longer faces open floor. `_wall_trap_slots` checks that
## once, up front, but a pit rolled later in the same pass can open in the tile a wall trap was
## already aimed at - and an arrow fired into a hole is not a trap, it is a facing pointing at
## nothing. Cheap to re-check at the end and impossible to get wrong by ordering.
static func _drop_wall_traps_aimed_at_nothing(data: FloorData, ctx: RoomCtx) -> void:
	var traps: Array[Dictionary] = ctx.room.trap_positions
	for i in range(traps.size() - 1, -1, -1):
		var facing: Vector2i = traps[i]["dir"]
		if facing == Vector2i.ZERO:
			continue
		var front: Vector2i = (traps[i]["pos"] as Vector2i) + facing
		if data.get_tile(front.x, front.y) != FloorData.Tile.FLOOR or ctx.blocked.has(front):
			traps.remove_at(i)


## Wall ring tiles that can host an arrow wall: not a corner, not a door, not next to a door,
## and facing a free interior floor tile (so the arrow does not fire straight into a pillar,
## pit or prop).
static func _wall_trap_slots(data: FloorData, ctx: RoomCtx) -> Array[Vector2i]:
	var room := ctx.room
	var out: Array[Vector2i] = []
	var ring := room.rect.grow(1)
	var doors: Array = room.doors.values()
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var p := Vector2i(x, y)
			if room.rect.has_point(p):
				continue
			var corner := (
				(x == ring.position.x or x == ring.end.x - 1)
				and (y == ring.position.y or y == ring.end.y - 1)
			)
			if corner or data.get_tile(x, y) != FloorData.Tile.WALL:
				continue
			var near_door := false
			for door: Vector2i in doors:
				if GenUtil.chebyshev(door, p) <= 1:
					near_door = true
					break
			if near_door:
				continue
			var inward := _inward_normal(room, p)
			if inward == Vector2i.ZERO:
				continue
			var front := p + inward
			if data.get_tile(front.x, front.y) != FloorData.Tile.FLOOR or ctx.blocked.has(front):
				continue
			out.append(p)
	return out


## Direction from a wall-ring tile towards the room interior, or ZERO for interior tiles.
static func _inward_normal(room: FloorData.Room, p: Vector2i) -> Vector2i:
	if room.rect.has_point(p):
		return Vector2i.ZERO
	for d: Vector2i in GenUtil.DIRS4:
		if room.rect.has_point(p + d):
			return d
	return Vector2i.ZERO


## Interior tiles reachable from the room's doors with template walls, pits and props solid.
## Enemies must stand on one of these or they are sealed into a pocket and the room can
## never be cleared (docs 6 room lock).
static func reachable_interior(data: FloorData, ctx: RoomCtx) -> Dictionary:
	var rect := ctx.room.rect
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for door: Vector2i in ctx.room.doors.values():
		for d: Vector2i in GenUtil.DIRS4:
			var p := door + d
			if not rect.has_point(p) or seen.has(p):
				continue
			if data.is_walkable(p.x, p.y) and not ctx.blocked.has(p):
				seen[p] = true
				queue.append(p)
	if queue.is_empty():
		var c := ctx.room.center()
		if rect.has_point(c) and data.is_walkable(c.x, c.y) and not ctx.blocked.has(c):
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
			if not data.is_walkable(n.x, n.y) or ctx.blocked.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


static func _spawn_count(
	type: FloorData.RoomType, params: GenParams, rng: RandomNumberGenerator
) -> int:
	var base := 0.0
	match type:
		FloorData.RoomType.COMBAT:
			base = 3.0 + params.floor_index * 0.5 + rng.randi_range(-1, 1)
		FloorData.RoomType.ELITE:
			base = 3.0 + params.floor_index / 3.0
		FloorData.RoomType.STAIRS:
			base = 2.0 + params.floor_index / 3.0
		FloorData.RoomType.TRAP:
			# The ambush: a calm track fills the trap rooms while it empties the rest.
			base = 1.0 + rng.randi_range(0, 1)
			return clampi(int(round(base * params.ambush_scale)), 1, 9)
		FloorData.RoomType.BOSS:
			return 1
		_:
			return 0
	return clampi(int(round(base * params.enemy_count_scale)), 1, 9)


static func _place_spawns(
	data: FloorData, ctx: RoomCtx, params: GenParams, rng: RandomNumberGenerator
) -> void:
	var room := ctx.room
	var count := _spawn_count(room.type, params, rng)
	if count <= 0:
		return
	var center := room.center()
	var doors: Array = room.doors.values()
	var reachable := reachable_interior(data, ctx)
	if room.type == FloorData.RoomType.BOSS:
		# The boss waits across the arena from the door, never in it (`ArenaSpawns`).
		var arena: Array[Vector2i] = []
		for p: Vector2i in _free_tiles(data, ctx):
			if reachable.has(p):
				arena.append(p)
		room.enemy_spawns = ArenaSpawns.place(room, arena)
		return
	var candidates: Array[Vector2i] = []
	for p: Vector2i in _free_tiles(data, ctx):
		if not reachable.has(p):
			continue
		var ok := true
		for door: Vector2i in doors:
			if GenUtil.chebyshev(door, p) < DOOR_CLEARANCE:
				ok = false
				break
		if ok:
			candidates.append(p)
	GenUtil.shuffle_vec2i(candidates, rng)
	if room.type == FloorData.RoomType.ELITE and not candidates.is_empty():
		# The elite (spawn 0) stands closest to the centre of its arena.
		var best := 0
		for i in range(candidates.size()):
			if (
				GenUtil.chebyshev(candidates[i], center)
				< GenUtil.chebyshev(candidates[best], center)
			):
				best = i
		var elite := candidates[best]
		candidates.remove_at(best)
		candidates.push_front(elite)
	for min_spacing: int in [2, 1]:
		for p: Vector2i in candidates:
			if room.enemy_spawns.size() >= count:
				break
			var spaced := true
			for s: Vector2i in room.enemy_spawns:
				if GenUtil.chebyshev(s, p) < min_spacing:
					spaced = false
					break
			if spaced:
				room.enemy_spawns.append(p)
		if room.enemy_spawns.size() >= count:
			break
