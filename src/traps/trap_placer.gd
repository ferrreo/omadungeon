## Turns generator output into live trap nodes (docs §9). `FloorData.Room.trap_positions` carries
## {pos, kind, dir} entries and PIT tiles mark holes; this places one `TrapBase` per entry (and
## one `Pit` per run of PIT tiles) under the floor root, wiring room ids, arrow directions,
## laser anchors and pressure-plate groups. `HazardSpawner` calls it for the live floor; rooms
## or RunManager may call it directly.
class_name TrapPlacer
extends RefCounted

## Kinds handled by the PIT tiles pass instead of `trap_positions`.
const PIT_KIND := &"pit"
## Fallback beam length when a laser has no room to shoot across.
const DEFAULT_LASER_LENGTH := 48.0


## World-space centre of tile `tile`.
static func tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * float(Layers.TILE)


## Builds every trap of `data` under `parent` and returns them (also in group "trap").
static func populate(
	data: FloorData, parent: Node2D, registry: TrapRegistry = null
) -> Array[TrapBase]:
	var out: Array[TrapBase] = []
	if data == null or parent == null:
		return out
	var reg := registry if registry != null else TrapRegistry.load_default()
	for room: FloorData.Room in data.rooms:
		out.append_array(build_room_traps(data, room, parent, reg))
	out.append_array(build_pits(data, parent, reg))
	return out


## Traps of one room (pits excluded: those follow the PIT tiles).
static func build_room_traps(
	data: FloorData, room: FloorData.Room, parent: Node2D, registry: TrapRegistry
) -> Array[TrapBase]:
	var out: Array[TrapBase] = []
	var plate_index := 0
	for entry: Dictionary in room.trap_positions:
		var kind: StringName = entry.get("kind", &"")
		if kind == &"" or kind == PIT_KIND or not registry.has_kind(kind):
			continue
		var tile: Vector2i = entry.get("pos", Vector2i.ZERO)
		var extra := {"room_id": room.id, "damage": _trap_damage(registry, kind, data.floor_index)}
		var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
		if dir == Vector2i.ZERO:
			dir = room.trap_facing(tile)
		if dir != Vector2i.ZERO:
			extra["direction"] = Vector2(dir)
		if kind == &"laser_grid":
			extra["to"] = _laser_anchor(data, room, tile)
		if kind == &"pressure_plate":
			extra["plate_id"] = StringName("room%d_plate%d" % [room.id, plate_index])
			extra["linked_group"] = TrapBase.room_group(room.id)
			plate_index += 1
		var trap := _spawn(registry, kind, tile_center(tile), parent, extra)
		if trap != null:
			out.append(trap)
	return out


## One `Pit` per horizontal run of PIT tiles (runs tile the region without overlapping, and
## every pit shares the same re-fall grace so a body never falls twice for one hole).
static func build_pits(data: FloorData, parent: Node2D, registry: TrapRegistry) -> Array[TrapBase]:
	var out: Array[TrapBase] = []
	if not registry.has_kind(PIT_KIND):
		return out
	for y in range(data.height):
		var x := 0
		while x < data.width:
			if data.get_tile(x, y) != FloorData.Tile.PIT:
				x += 1
				continue
			var start := x
			while x < data.width and data.get_tile(x, y) == FloorData.Tile.PIT:
				x += 1
			var length := x - start
			var size := Vector2(float(length * Layers.TILE), float(Layers.TILE))
			var centre := tile_center(Vector2i(start, y))
			centre.x += float((length - 1) * Layers.TILE) * 0.5
			var room := data.room_at(Vector2i(start, y))
			var extra := {
				"size": size, "damage": _trap_damage(registry, PIT_KIND, data.floor_index)
			}
			if room != null:
				extra["room_id"] = room.id
			var pit := _spawn(registry, PIT_KIND, centre, parent, extra)
			if pit != null:
				out.append(pit)
	return out


## Far anchor for a laser beam: the longest clear straight line from `tile` inside the room.
static func _laser_anchor(data: FloorData, room: FloorData.Room, tile: Vector2i) -> Vector2:
	var best := Vector2i.ZERO
	var best_len := 0
	for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var back := _scan(data, room, tile, -axis)
		var forward := _scan(data, room, tile, axis)
		var span := (forward - back).length()
		if span > float(best_len):
			best_len = int(span)
			best = forward
	if best_len <= 0:
		return tile_center(tile) + Vector2(DEFAULT_LASER_LENGTH, 0.0)
	return tile_center(best)


## Last walkable tile from `tile` towards `step` without leaving the room interior.
static func _scan(
	data: FloorData, room: FloorData.Room, tile: Vector2i, step: Vector2i
) -> Vector2i:
	var cursor := tile
	while true:
		var next := cursor + step
		if not room.rect.has_point(next) or not data.is_walkable(next.x, next.y):
			break
		cursor = next
	return cursor


## Damage one hit of `kind` does on `floor_index` (`TrapDef.scaled_damage`), or 0 for an
## unknown kind — the caller only reaches this for kinds the registry already knows.
static func _trap_damage(registry: TrapRegistry, kind: StringName, floor_index: int) -> float:
	var def := registry.get_def(kind)
	return def.scaled_damage(floor_index) if def != null else 0.0


static func _spawn(
	registry: TrapRegistry, kind: StringName, world: Vector2, parent: Node2D, extra: Dictionary
) -> TrapBase:
	var trap := registry.create(kind, world, extra)
	if trap == null:
		return null
	parent.add_child(trap)
	trap.global_position = world
	return trap
