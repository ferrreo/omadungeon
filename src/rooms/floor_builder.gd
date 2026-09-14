## Turns a FloorData grid into TileMapLayers ("Ground", "Walls", "Pits") plus PitArea nodes.
## The TileSet is built at runtime from the biome atlas (see assets/tiles/README.md) so
## no .tres tileset needs maintaining. Rooms with a non-zero palette variant get their own
## Ground/Pits/Walls layer trio (one material per layer), named "Ground_r<id>" / "Pits_r<id>" /
## "Walls_r<id>", so a variant room's pits are tinted like the rest of it; the cost is a handful
## of extra layers per floor, which is negligible at 480x270.
class_name FloorBuilder
extends RefCounted

const ATLAS_COLS := 16
const ATLAS_ROWS := 5
const ROW_FLOOR := 0
const ROW_WALL := 1
const ROW_WALL_TOP := 2
const ROW_PIT := 3
const ROW_SPECIAL := 4
## Row 4 columns.
const SPECIAL_DOOR_CLOSED := 0
const SPECIAL_DOOR_OPEN := 1
const SPECIAL_STAIRS := 2
const SPECIAL_STAIRS_LOCKED := 3
const SPECIAL_ALTAR := 4
const SPECIAL_SHOP := 5
const SPECIAL_SHRINE := 6
const SPECIAL_TORCH_A := 7
const SPECIAL_TORCH_B := 8
## Wall lantern sprites the lighting layer hangs on the generator's anchors (`WallLantern`).
const SPECIAL_LANTERN := 9
const SPECIAL_BRAZIER := 10
const SPECIAL_CANDLE := 11
const SPECIAL_CRYSTAL := 12
## Neighbour bits for autotile masks.
const MASK_N := 1
const MASK_E := 2
const MASK_S := 4
const MASK_W := 8
const DECORATED_FLOOR_PERCENT := 12
const SOURCE_ID := 0
## Cells per tile-layer render chunk (see `_make_layer`).
const LIGHT_QUADRANT_CELLS := 4
const TILES_DIR := "res://assets/tiles/"
## 4-way neighbours, as a const so the pit flood fill allocates nothing per tile.
const NEIGHBORS_4: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

## atlas key -> TileSet. Building a tileset means creating eighty tiles and two rows of
## collision polygons; the result depends only on the atlas, so floors that share a biome
## share the set instead of rebuilding it on every descent.
static var _tileset_cache: Dictionary = {}


## Everything build() produced. Keep it around to retint on palette changes.
class Result:
	extends RefCounted
	var tileset: TileSet
	var atlas: Texture2D
	var ground: TileMapLayer
	var walls: TileMapLayer
	var pits: TileMapLayer
	## room_id -> {"ground", "walls", "pits": TileMapLayer} for variant rooms.
	var room_layers: Dictionary = {}
	var pit_areas: Array[PitArea] = []
	## [{material: ShaderMaterial, variant: int, seed: int}] for every tinted layer.
	var materials: Array[Dictionary] = []
	## Vector2i -> int autotile mask for every WALL tile (tests/debug).
	var wall_masks: Dictionary = {}
	var ground_count: int = 0
	var wall_count: int = 0
	var pit_count: int = 0

	## Crossfades every layer material to `palette`.
	func retint(palette: ThemePalette, host: Node) -> void:
		for entry: Dictionary in materials:
			var mat: ShaderMaterial = entry["material"]
			TileRamp.retint(mat, palette, int(entry["variant"]), int(entry["seed"]), host)

	## All TileMapLayers (base + per-room), for callers that want to hide/show them.
	func all_layers() -> Array[TileMapLayer]:
		var out: Array[TileMapLayer] = [ground, pits, walls]
		for id: int in room_layers:
			var pair: Dictionary = room_layers[id]
			out.append(pair["ground"])
			out.append(pair["pits"])
			out.append(pair["walls"])
		return out


## Builds layers under `parent`. `palette` defaults to the live Desktop palette.
func build(
	data: FloorData, biome_atlas: Texture2D, parent: Node2D, palette: ThemePalette = null
) -> Result:
	var pal := palette if palette != null else TileRamp.live_palette()
	var result := Result.new()
	result.atlas = biome_atlas
	result.tileset = tileset_for(biome_atlas)
	var base_seed := data.seed_value
	result.ground = _make_layer("Ground", result.tileset, false)
	result.pits = _make_layer("Pits", result.tileset, false)
	result.walls = _make_layer("Walls", result.tileset, true)
	var base_mat := TileRamp.make_material(pal, TileRamp.Variant.BASE, base_seed)
	result.ground.material = base_mat
	result.walls.material = base_mat
	result.pits.material = base_mat
	result.materials.append({"material": base_mat, "variant": 0, "seed": base_seed})
	parent.add_child(result.ground)
	# Tiles owned by rooms with a variant go on that room's own layer pair.
	var owner_of: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		if room.palette_variant == TileRamp.Variant.BASE:
			continue
		var ring := room.rect.grow(1)
		for y in range(ring.position.y, ring.end.y):
			for x in range(ring.position.x, ring.end.x):
				owner_of[Vector2i(x, y)] = room.id
		var room_seed := RunRng.hash_combine(base_seed, room.id + 1)
		var mat := TileRamp.make_material(pal, room.palette_variant, room_seed)
		var g := _make_layer("Ground_r%d" % room.id, result.tileset, false)
		var pit_layer := _make_layer("Pits_r%d" % room.id, result.tileset, false)
		var w := _make_layer("Walls_r%d" % room.id, result.tileset, true)
		g.material = mat
		pit_layer.material = mat
		w.material = mat
		result.room_layers[room.id] = {"ground": g, "pits": pit_layer, "walls": w}
		result.materials.append(
			{"material": mat, "variant": room.palette_variant, "seed": room_seed}
		)
		parent.add_child(g)
	parent.add_child(result.pits)
	for id: int in result.room_layers:
		parent.add_child((result.room_layers[id] as Dictionary)["pits"])
	parent.add_child(result.walls)
	for id: int in result.room_layers:
		parent.add_child((result.room_layers[id] as Dictionary)["walls"])
	for y in range(data.height):
		for x in range(data.width):
			var pos := Vector2i(x, y)
			var owner_id: int = owner_of.get(pos, -1)
			var ground_layer := result.ground
			var walls_layer := result.walls
			var pits_layer := result.pits
			if owner_id >= 0:
				var pair: Dictionary = result.room_layers[owner_id]
				ground_layer = pair["ground"]
				walls_layer = pair["walls"]
				pits_layer = pair["pits"]
			match data.get_tile(x, y):
				FloorData.Tile.FLOOR:
					ground_layer.set_cell(pos, SOURCE_ID, floor_coords(base_seed, x, y, true))
					result.ground_count += 1
				FloorData.Tile.CORRIDOR:
					ground_layer.set_cell(pos, SOURCE_ID, floor_coords(base_seed, x, y, false))
					result.ground_count += 1
				FloorData.Tile.DOOR:
					ground_layer.set_cell(pos, SOURCE_ID, Vector2i(0, ROW_FLOOR))
					result.ground_count += 1
				FloorData.Tile.WALL:
					var coords := wall_coords(data, base_seed, x, y)
					walls_layer.set_cell(pos, SOURCE_ID, coords)
					result.wall_masks[pos] = wall_mask(data, x, y)
					result.wall_count += 1
				FloorData.Tile.PIT:
					pits_layer.set_cell(pos, SOURCE_ID, Vector2i(pit_mask(data, x, y), ROW_PIT))
					result.pit_count += 1
	result.pit_areas = _build_pit_areas(data, parent)
	return result


## Cached `build_tileset`. The returned set is shared between every floor built from the same
## atlas and must not be mutated. Use `build_tileset()` directly when you need a private one.
static func tileset_for(atlas: Texture2D) -> TileSet:
	if atlas == null:
		return build_tileset(atlas)
	var key: Variant = (
		atlas.resource_path if not atlas.resource_path.is_empty() else atlas.get_instance_id()
	)
	var cached := _tileset_cache.get(key) as TileSet
	if cached != null:
		return cached
	var built := build_tileset(atlas)
	_tileset_cache[key] = built
	return built


## Drops every cached TileSet (tests, and anything that swaps atlases at runtime).
static func clear_tileset_cache() -> void:
	_tileset_cache.clear()


## Programmatic TileSet: one atlas source, physics layer 0 on WORLD for row-1/row-2 walls.
static func build_tileset(atlas: Texture2D) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(Layers.TILE, Layers.TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, Layers.WORLD)
	ts.set_physics_layer_collision_mask(0, 0)
	var source := TileSetAtlasSource.new()
	source.texture = atlas
	source.texture_region_size = Vector2i(Layers.TILE, Layers.TILE)
	var cols := mini(ATLAS_COLS, int(atlas.get_width()) / Layers.TILE)
	var rows := mini(ATLAS_ROWS, int(atlas.get_height()) / Layers.TILE)
	var half := float(Layers.TILE) / 2.0
	var box := PackedVector2Array(
		[Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	)
	# The source must belong to the set before TileData can reference its physics layer.
	ts.add_source(source, SOURCE_ID)
	for row in range(rows):
		for col in range(cols):
			var coords := Vector2i(col, row)
			source.create_tile(coords)
			if row == ROW_WALL or row == ROW_WALL_TOP:
				var td := source.get_tile_data(coords, 0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, box)
	return ts


## Loads `res://assets/tiles/<biome>.png`; falls back to a generated placeholder texture.
static func load_atlas(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			return ImageTexture.create_from_image(img)
	push_warning("FloorBuilder: atlas %s missing, using placeholder" % path)
	return ImageTexture.create_from_image(make_placeholder_atlas())


## Sprite2D showing one atlas cell (used by doors, stairs, altar, shop, shrine, torches).
static func atlas_sprite(atlas: Texture2D, col: int, row: int = ROW_SPECIAL) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = atlas
	sprite.region_enabled = true
	sprite.region_rect = atlas_cell(col, row)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite


static func atlas_cell(col: int, row: int) -> Rect2:
	return Rect2(col * Layers.TILE, row * Layers.TILE, Layers.TILE, Layers.TILE)


static func atlas_path_for(biome: StringName) -> String:
	return TILES_DIR + String(biome) + ".png"


## 4-bit mask of WALL/DOOR neighbours (N=1, E=2, S=4, W=8). Off-grid counts as open.
static func wall_mask(data: FloorData, x: int, y: int) -> int:
	var m := 0
	if _is_wallish(data.get_tile(x, y - 1)):
		m |= MASK_N
	if _is_wallish(data.get_tile(x + 1, y)):
		m |= MASK_E
	if _is_wallish(data.get_tile(x, y + 1)):
		m |= MASK_S
	if _is_wallish(data.get_tile(x - 1, y)):
		m |= MASK_W
	return m


## 4-bit mask of PIT neighbours, same bit order as wall_mask.
static func pit_mask(data: FloorData, x: int, y: int) -> int:
	var m := 0
	if data.get_tile(x, y - 1) == FloorData.Tile.PIT:
		m |= MASK_N
	if data.get_tile(x + 1, y) == FloorData.Tile.PIT:
		m |= MASK_E
	if data.get_tile(x, y + 1) == FloorData.Tile.PIT:
		m |= MASK_S
	if data.get_tile(x - 1, y) == FloorData.Tile.PIT:
		m |= MASK_W
	return m


## A wall with no walkable or pit tile in its 8-neighbourhood shows a cap (row 2).
static func is_deep_wall(data: FloorData, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var t := data.get_tile(x + dx, y + dy)
			if data.is_walkable(x + dx, y + dy) or t == FloorData.Tile.PIT:
				return false
	return true


static func wall_coords(data: FloorData, seed_value: int, x: int, y: int) -> Vector2i:
	if is_deep_wall(data, x, y):
		return Vector2i(tile_hash(seed_value, x, y) % 4, ROW_WALL_TOP)
	return Vector2i(wall_mask(data, x, y), ROW_WALL)


## Deterministic floor variant for a tile; `decorated` allows the decorated columns 4-7.
static func floor_coords(seed_value: int, x: int, y: int, decorated: bool) -> Vector2i:
	var h := tile_hash(seed_value, x, y)
	var col := h % 4
	if decorated and (h / 4) % 100 < DECORATED_FLOOR_PERCENT:
		col += 4
	return Vector2i(col, ROW_FLOOR)


static func tile_hash(seed_value: int, x: int, y: int) -> int:
	return absi(RunRng.hash_combine(RunRng.hash_combine(seed_value, x + 1), y + 1))


## Placeholder atlas painted with the ramp so the game runs before real art lands.
static func make_placeholder_atlas() -> Image:
	var img := Image.create(
		ATLAS_COLS * Layers.TILE, ATLAS_ROWS * Layers.TILE, false, Image.FORMAT_RGBA8
	)
	img.fill(Color(0, 0, 0, 0))
	for col in range(ATLAS_COLS):
		_fill_cell(img, col, ROW_FLOOR, TileRamp.RAMP[3])
		_fill_cell(img, col, ROW_WALL, TileRamp.RAMP[2], 1)
		_fill_cell(img, col, ROW_WALL_TOP, TileRamp.RAMP[5], 1)
		_fill_cell(img, col, ROW_PIT, TileRamp.RAMP[1])
		_fill_cell(img, col, ROW_SPECIAL, TileRamp.RAMP[6 + col % 2], 1)
	return img


static func _fill_cell(img: Image, col: int, row: int, c: Color, outline: int = 0) -> void:
	var t := Layers.TILE
	var rect := Rect2i(col * t, row * t, t, t)
	if outline > 0:
		img.fill_rect(rect, TileRamp.RAMP[1])
		rect = rect.grow(-outline)
	img.fill_rect(rect, c)


static func _is_wallish(t: FloorData.Tile) -> bool:
	return t == FloorData.Tile.WALL or t == FloorData.Tile.DOOR


static func _make_layer(layer_name: String, ts: TileSet, solid: bool) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = ts
	layer.collision_enabled = solid
	# Small quadrants: the renderer lights a canvas item with at most 16 lights, and a tile
	# layer chunked at 16x16 cells is one item 256 px wide - a room with lanterns on every wall
	# put more lights than that on one chunk and the rest silently lit nothing (`LightRig`).
	layer.rendering_quadrant_size = LIGHT_QUADRANT_CELLS
	return layer


## Flood-fills PIT tiles (4-way) into PitArea regions under `parent`.
func _build_pit_areas(data: FloorData, parent: Node2D) -> Array[PitArea]:
	var out: Array[PitArea] = []
	var seen: Dictionary = {}
	for y in range(data.height):
		for x in range(data.width):
			var start := Vector2i(x, y)
			if data.get_tile(x, y) != FloorData.Tile.PIT or seen.has(start):
				continue
			var area := PitArea.new()
			area.name = "Pit%d" % out.size()
			var room := data.room_at(start)
			area.room_id = room.id if room != null else -1
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				area.add_tile(p)
				for d: Vector2i in NEIGHBORS_4:
					var n := p + d
					if seen.has(n) or data.get_tile(n.x, n.y) != FloorData.Tile.PIT:
						continue
					seen[n] = true
					stack.append(n)
			parent.add_child(area)
			out.append(area)
	return out
