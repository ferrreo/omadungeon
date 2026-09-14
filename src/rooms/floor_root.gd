## Root node of one playable floor: tile layers (FloorBuilder), Room nodes with doors,
## interactables (stairs/altar/shop/shrine/treasure chest), props, wall torches and a
## NavigationRegion2D baked from the walkable tiles. Sits at the world origin; tile (x, y)
## maps to pixels (x, y) * Layers.TILE.
## RunManager/Game: `build_from(data, floor_index)`, place the player at
## `player_spawn_position()`, clamp the camera to `camera_limits()`, then `populate()` rooms
## (or `add_enemy()`), read `minimap()` for the HUD and `get_shops()` to stock the shops.
class_name FloorRoot
extends Node2D

signal built(root: FloorRoot)

const NAV_AGENT_RADIUS := 4.0
const TORCH_OFFSET := 2
## Light mask the torch sconces are drawn with. A Light2D reaches a CanvasItem only where
## `range_item_cull_mask & light_mask` is non-zero, so zero is "lit by nothing at all".
##
## A torch *is* a light; it is not a surface a light falls on. The additive PointLight2D that
## hangs on the sconce used to land on the sconce first, and an additive light over a flame
## clips it: the `heat`/`loot` rungs `TileRamp.flame_colors` had just put on the cell came out
## of the compositor as (255, 255, 235) on nord and pure white on gruvbox - a white candle on
## every dark theme, which is exactly where a torch is the only warmth in the room. Taking the
## sconce out of every light lets the flame render in the colours it is painted in, while the
## light still pools on the wall and floor around it.
const TORCH_SPRITE_LIGHT_MASK := 0
## How far past the floor grid the unlit surround is painted, in pixels. The floor owns the
## colour outside its rooms rather than leaving it to the engine clear colour, which is a
## global and knows nothing about this floor's light level; the camera is clamped to the grid,
## so this only has to out-run the viewport.
const VOID_MARGIN := 640.0
## Shader the surround is painted with (depth + grain over the lit `void` colour).
const SURROUND_SHADER := "res://src/rooms/void_surround.gdshader"
## Odds a Treasure-room chest is trapped (docs §8); tunable in data/rooms/rooms_content.tres.
const TREASURE_TRAP_CHANCE := 0.5
## Lowest and highest floor light level, from docs §3.4 ("ambient, clamped 0.55-1.0").
const AMBIENT_MIN := WallpaperAnalyzer.AMBIENT_MIN
const AMBIENT_MAX := WallpaperAnalyzer.AMBIENT_MAX

var data: FloorData
var built_layers: FloorBuilder.Result
var rooms: Array[RoomNode] = []
var props: Array[Prop] = []
var stairs: Stairs
## First altar/shop/shrine of the floor (the full lists are `altars`/`shops`/`shrines`).
var altar: Altar
var shop: Shop
var shrine: Shrine
var altars: Array[Altar] = []
var shops: Array[Shop] = []
var shrines: Array[Shrine] = []
var nav_region: NavigationRegion2D
var atlas: Texture2D
var player_spawn: Vector2 = Vector2.ZERO
var current_room_id: int = -1
## The music's multiplier on the floor light (`GenParams.light_scale`, docs 10.2). Set before
## the build; the product with the wallpaper's ambient stays inside the documented band, and
## a light theme keeps its pinned full light (docs 3.2).
var light_scale: float = 1.0
var _camera_limits: Rect2 = Rect2()
var _rooms_node: Node2D
var _props_node: Node2D
var _decor_node: Node2D
var _rng: RandomNumberGenerator
var _bound_player: Node2D
## room_id -> {"material": ShaderMaterial, "base": ShaderMaterial} for the readable prop tint.
var _prop_tints: Dictionary = {}
## room_id -> {"material": ShaderMaterial, "base": ShaderMaterial} for the torch flame tint.
var _flame_tints: Dictionary = {}
## room_id -> {"material": ShaderMaterial, "base": ShaderMaterial} for the accented prop tint.
var _prop_accent_tints: Dictionary = {}
## Tiles whose breakable prop is gone, live breaks and replayed ones alike. A prop frees
## itself when it breaks, so the floor is the only thing left that can remember the tile:
## `FloorRestore` writes this into the save and replays it on resume, and a rebuilt barrel
## never pays its (seed, tile, floor)-deterministic gold a second time.
var _broken_prop_tiles: Array[Vector2i] = []
## Tiles whose mimic chest the player already sprang. The decoy frees itself on reveal, so the
## same reasoning applies: without this the enemy it becomes is farmable by quitting.
var _revealed_mimic_tiles: Array[Vector2i] = []
## Every torch light on this floor, in placement order (see `_place_torches`).
var _torch_lights: Array[PointLight2D] = []
## Radial gradient shared by every light this floor owns.
var _light_texture: Texture2D
## Light tuning (`data/rooms/dungeon_light.tres`), resolved once per build.
var _light_profile: DungeonLight
## Seconds since the floor was built, driving the torch flicker.
var _light_time: float = 0.0
## The flicker's noise source: value noise read along time, so a torch wanders rather than
## cycling. It used to be a 2.3 Hz sine per torch, which is a periodic brightness change - the
## exact thing the music lights are forbidden to make (docs 10.2).
var _flicker_noise := FastNoiseLite.new()
## Theme palette the floor was built with, before the biome/wallpaper derivation.
var _base_palette: ThemePalette
## Biome/wallpaper-derived palette, before the floor light level (see `environment_palette()`).
var _env_palette: ThemePalette
## `_env_palette` under this floor's light level: the colours actually drawn (`lit_palette()`).
var _lit_palette: ThemePalette
## Flat fill behind every layer, painted in the lit `void`, so the surround is part of the
## floor's lighting model instead of a global clear colour nobody dims.
var _void_backdrop: Polygon2D
## Theme keys this floor's biome draws its accents from (docs §10). Empty = the whole pool.
var _biome_keys: PackedStringArray = PackedStringArray()
## Biome handed to `build_with_biome`, consumed by the `build_from_path` it delegates to.
## Survives `clear_floor()`, which runs between the two.
var _biome_override: Biome
## Wallpaper analysis captured at build time; drives floor detail colour and ambient light.
var _wallpaper: WallpaperAnalyzer.Result
## Current floor light level (docs §3.4 clamp). 1.0 until a wallpaper says otherwise.
var _ambient: float = 1.0


## Odds a Treasure-room chest is trapped: `data/rooms/rooms_content.tres` when it sets a
## non-negative value, else the TREASURE_TRAP_CHANCE constant. `content` is injectable for tests.
static func treasure_trap_chance(content: RoomsContent = null) -> float:
	var res := RoomsContent.resolve(content)
	if res != null and res.treasure_trap_chance >= 0.0:
		return res.treasure_trap_chance
	return TREASURE_TRAP_CHANCE


func _ready() -> void:
	if not EventBus.palette_changed.is_connected(_on_palette_changed):
		EventBus.palette_changed.connect(_on_palette_changed)
	if not EventBus.room_entered.is_connected(_on_room_entered):
		EventBus.room_entered.connect(_on_room_entered)
	if not EventBus.desktop_changed.is_connected(_on_desktop_changed):
		EventBus.desktop_changed.connect(_on_desktop_changed)


## Builds the floor. `floor_index` is informational (the index also lives in `floor_data`);
## the biome atlas is resolved from `data.biome` through `data/biomes/<id>.tres`.
func build_from(floor_data: FloorData, floor_index: int = -1) -> void:
	if floor_index >= 0:
		floor_data.floor_index = floor_index
	build_with_biome(floor_data, Biome.load_by_id(floor_data.biome))


## Same with an explicit Biome resource (its `tileset_path`, or the `atlas_path` alias, wins).
## `rng` drives build-time rolls (pass the run's loot stream); `palette` defaults to Desktop's.
func build_with_biome(
	floor_data: FloorData,
	biome: Biome = null,
	rng: RandomNumberGenerator = null,
	palette: ThemePalette = null
) -> void:
	_biome_override = biome
	build_from_path(floor_data, atlas_path_for_biome(floor_data, biome), rng, palette)


## Atlas path for a floor: the biome's `tileset_path`, its `atlas_path` alias, else
## `res://assets/tiles/<data.biome>.png`.
static func atlas_path_for_biome(floor_data: FloorData, biome: Resource) -> String:
	if biome != null:
		for field: StringName in [&"tileset_path", &"atlas_path"]:
			var value: Variant = biome.get(field)
			if value is String and not (value as String).is_empty():
				return value as String
	return FloorBuilder.atlas_path_for(floor_data.biome)


## Same as build_with_biome() with an explicit atlas path.
func build_from_path(
	floor_data: FloorData,
	atlas_path: String,
	rng: RandomNumberGenerator = null,
	palette: ThemePalette = null
) -> void:
	var biome := _biome_override
	clear_floor()
	data = floor_data
	if biome == null:
		biome = Biome.load_by_id(data.biome)
	_biome_keys = biome.palette_keys
	_rng = rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = RunRng.hash_combine(data.seed_value, data.floor_index + 101)
	atlas = FloorBuilder.load_atlas(atlas_path)
	_wallpaper = live_wallpaper()
	_base_palette = palette if palette != null else TileRamp.live_palette()
	_env_palette = _derive_palette(_base_palette)
	_light_profile = DungeonLight.resolve()
	_apply_ambient()
	_build_void_backdrop()
	built_layers = FloorBuilder.new().build(data, atlas, self, _lit_palette)
	_decor_node = Node2D.new()
	_decor_node.name = "Decor"
	add_child(_decor_node)
	_props_node = Node2D.new()
	_props_node.name = "Props"
	add_child(_props_node)
	_rooms_node = Node2D.new()
	_rooms_node.name = "Rooms"
	add_child(_rooms_node)
	for room_data: FloorData.Room in data.rooms:
		_build_room(room_data)
	_build_props()
	_build_nav()
	var start := data.room_by_id(data.start_room)
	player_spawn = start.center_world() if start != null else Vector2.ZERO
	_camera_limits = Rect2(Vector2.ZERO, Vector2(data.width, data.height) * Layers.TILE)
	current_room_id = data.start_room
	_auto_bind_player()
	var rig := LightRig.new()
	add_child(rig)
	rig.build(self)
	built.emit(self)


## Frees everything built so the node can be reused for the next floor.
func clear_floor() -> void:
	for room: RoomNode in rooms:
		if is_instance_valid(room):
			room.begin_teardown()
	unbind_player()
	Interactable.reset_prompt(get_tree())
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	rooms.clear()
	props.clear()
	_broken_prop_tiles.clear()
	_revealed_mimic_tiles.clear()
	altars.clear()
	shops.clear()
	shrines.clear()
	stairs = null
	altar = null
	shop = null
	shrine = null
	nav_region = null
	built_layers = null
	data = null
	_rooms_node = null
	_props_node = null
	_decor_node = null
	_prop_tints.clear()
	_prop_accent_tints.clear()
	_flame_tints.clear()
	_torch_lights.clear()
	_light_time = 0.0
	set_process(false)
	_void_backdrop = null
	_lit_palette = null
	_env_palette = null
	_base_palette = null
	_biome_keys = PackedStringArray()
	_biome_override = null
	_wallpaper = null
	_ambient = 1.0


## Connects the player's `interact_pressed` signal to the interaction dispatcher. Called
## automatically at build time for the first node in group "player"; call it explicitly when
## the player is spawned later.
func bind_player(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _bound_player == player:
		return
	unbind_player()
	if not player.has_signal(&"interact_pressed"):
		return
	_bound_player = player
	player.connect(&"interact_pressed", _on_interact_pressed)


## Drops the interact binding (floor teardown).
func unbind_player() -> void:
	if _bound_player != null and is_instance_valid(_bound_player):
		if _bound_player.is_connected(&"interact_pressed", _on_interact_pressed):
			_bound_player.disconnect(&"interact_pressed", _on_interact_pressed)
	_bound_player = null


func get_room(id: int) -> RoomNode:
	return rooms[id] if id >= 0 and id < rooms.size() else null


## Room whose interior contains a world position, or null (corridors).
func room_at_world(pos: Vector2) -> RoomNode:
	if data == null:
		return null
	var tile := Vector2i((pos / Layers.TILE).floor())
	var r := data.room_at(tile)
	return get_room(r.id) if r != null else null


func current_room() -> RoomNode:
	return get_room(current_room_id)


## Records the room the player is in. Fed by `EventBus.room_entered`, and called directly by
## RunManager *before* it refreshes the minimap: both nodes listen to the same signal and
## handlers run in connection order, so the autoload (connected in its own `_ready()`, long
## before this floor existed) would otherwise read `current_room_id` one room stale. Writing
## it here is idempotent, so the second call is a no-op.
func set_current_room(room_id: int) -> void:
	current_room_id = room_id
	if _bound_player == null:
		_auto_bind_player()


## Where the player starts on this floor (centre of the start room).
func player_spawn_position() -> Vector2:
	return player_spawn


## Where the player appears when they arrive in (or are pushed back into) a room: the
## interior tile next to its first door. Falls back to the floor spawn for unknown rooms.
func room_entry_position(room_id: int) -> Vector2:
	var room := get_room(room_id)
	return room.entry_position() if room != null else player_spawn


## Camera bounds for this floor, in pixels.
func camera_limits() -> Rect2:
	return _camera_limits


## True once this floor's navigation region is actually queryable.
##
## `build_nav_polygon()` bakes synchronously, but handing the finished polygon to a
## NavigationRegion2D only *queues* it: the NavigationServer folds regions into the map on its
## own sync step, so `map_get_path()` answers with an empty array for an indeterminate number
## of frames after `build_from()` returns. Counting frames is therefore never a correct wait -
## under load the count that worked yesterday returns nothing today. The three checks are the
## three ways the map can still be empty: never synced, no regions attached, or regions
## attached whose polygons are not folded in yet (which is what the closest-point probe
## catches - with no polygons the map answers `Vector2.ZERO` for every query).
func nav_ready() -> bool:
	if nav_region == null or not is_inside_tree() or data == null:
		return false
	var map := get_world_2d().navigation_map
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return false
	if NavigationServer2D.map_get_regions(map).is_empty():
		return false
	var probe := player_spawn
	return NavigationServer2D.map_get_closest_point(map, probe).distance_to(probe) < Layers.TILE


## Awaits `nav_ready()` with a deadline, one physics frame at a time. Returns false if the
## deadline passed without the map baking, so a caller reports one honest failure instead of
## asserting on an empty path. Use this instead of waiting a fixed number of frames.
func await_nav_ready(timeout_seconds: float = 5.0) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var deadline := Time.get_ticks_msec() + int(maxf(0.0, timeout_seconds) * 1000.0)
	while not nav_ready():
		if Time.get_ticks_msec() >= deadline:
			return false
		await tree.physics_frame
		if not is_instance_valid(self) or not is_inside_tree():
			return false
	return true


## Marks a room cleared without a fight (RunManager restoring rooms cleared before a
## floor rebuild). Never spawns a second chest.
func mark_cleared(room_id: int) -> void:
	var room := get_room(room_id)
	if room != null:
		room.force_clear(false)


## Shop counters on this floor (RunManager stocks them with `stock(offers, base_price)`).
func get_shops() -> Array[Node]:
	var out: Array[Node] = []
	for s: Shop in shops:
		out.append(s)
	return out


func get_altars() -> Array[Node]:
	var out: Array[Node] = []
	for a: Altar in altars:
		out.append(a)
	return out


func get_shrines() -> Array[Node]:
	var out: Array[Node] = []
	for s: Shrine in shrines:
		out.append(s)
	return out


## Adds a mid-fight spawn to a room: parents it under that room and registers it with the
## room's clear tracking (so summoned enemies keep the door locked).
func add_enemy(enemy: Node2D, room_id: int) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var room := get_room(room_id)
	if room == null:
		if enemy.get_parent() == null:
			add_child(enemy)
		return
	var list: Array[Node2D] = [enemy]
	room.populate(list)


## Ids of rooms whose fight is over (lockable rooms only).
func cleared_ids() -> Array[int]:
	var out: Array[int] = []
	for room: RoomNode in rooms:
		if room.state == RoomNode.State.CLEARED and room.is_lockable():
			out.append(room.id)
	return out


func visited_ids() -> Array[int]:
	var out: Array[int] = []
	for room: RoomNode in rooms:
		if room.visited:
			out.append(room.id)
	return out


## Everything the minimap widget needs: {"rooms": Array[Dictionary], "edges": Array[Vector4i],
## "links": Array[PackedVector2Array]}.
func minimap() -> Dictionary:
	return {"rooms": minimap_rooms(), "edges": minimap_edges(), "links": minimap_links()}


func minimap_rooms() -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	if data == null:
		return empty
	return MinimapModel.rooms(data, cleared_ids(), current_room_id, visited_ids())


func minimap_edges() -> Array[Vector4i]:
	var empty: Array[Vector4i] = []
	if data == null:
		return empty
	return MinimapModel.edges(data)


## The route each `minimap_edges()` connection actually takes, same order.
func minimap_links() -> Array[PackedVector2Array]:
	var empty: Array[PackedVector2Array] = []
	if data == null:
		return empty
	return MinimapModel.links(data)


## Palette-swap material shared by a room's tiles, doors and props.
func material_for_room(room_id: int) -> ShaderMaterial:
	if built_layers == null:
		return null
	if built_layers.room_layers.has(room_id):
		var pair: Dictionary = built_layers.room_layers[room_id]
		return (pair["ground"] as TileMapLayer).material as ShaderMaterial
	return built_layers.ground.material as ShaderMaterial


## Material props, hazards and interactables in a room are drawn with: the room's tile colours
## pushed off its own floor colour (Prop.readable_colors), so nothing the player must see or
## avoid is painted the same as the tile behind it. One material per room, retinted with the
## tiles on EventBus.palette_changed.
func prop_material_for_room(room_id: int) -> ShaderMaterial:
	if _prop_tints.has(room_id):
		return (_prop_tints[room_id] as Dictionary)["material"] as ShaderMaterial
	var base := material_for_room(room_id)
	# The base material already carries the lit colours, so the readable tint is judged at
	# full exposure: dimming it a second time is what used to paint props in wall colour.
	var mat := Prop.readable_material(base)
	if mat == null:
		return null
	_prop_tints[room_id] = {"material": mat, "base": base}
	return mat


## Material the breakable props of a room are drawn in: the readable prop colours with the
## body rungs pulled onto the room's own accent hue (`Prop.accent_colors`), so an urn is a
## different *colour* from the tile it stands on and not just a lighter value of it (docs
## §3.2: prop_a/prop_b carry the theme's accent into the level). Interactables keep the plain
## readable tint. One material per room, retinted with the tiles on EventBus.palette_changed.
func prop_accent_material_for_room(room_id: int) -> ShaderMaterial:
	if _prop_accent_tints.has(room_id):
		return (_prop_accent_tints[room_id] as Dictionary)["material"] as ShaderMaterial
	var base := material_for_room(room_id)
	var mat := Prop.accent_material(base)
	if mat == null:
		return null
	_prop_accent_tints[room_id] = {"material": mat, "base": base}
	return mat


## Material the wall torches of a room are drawn in: the readable prop colours with the two
## accent rungs replaced by the palette's own `heat` and `loot` (TileRamp.flame_colors), so a
## flame burns in the theme's fire colour instead of whatever accent the room happened to roll.
## One material per room, retinted with the tiles on EventBus.palette_changed.
func torch_material_for_room(room_id: int) -> ShaderMaterial:
	if _flame_tints.has(room_id):
		return (_flame_tints[room_id] as Dictionary)["material"] as ShaderMaterial
	var base := material_for_room(room_id)
	var mat := Prop.material_with(base, _flame_colors(base))
	if mat == null:
		return null
	_flame_tints[room_id] = {"material": mat, "base": base}
	return mat


func _flame_colors(base: ShaderMaterial) -> PackedColorArray:
	var pal := _lit_palette if _lit_palette != null else TileRamp.live_palette()
	var room := Prop.ramp_targets(base)
	if room.size() < TileRamp.RAMP_SIZE:
		return room
	return TileRamp.flame_colors(Prop.readable_colors(room), pal, room[Prop.FLOOR_RAMP_INDEX])


## The palette this floor is actually tinted with: the live theme narrowed to the biome's
## own accent keys and mixed with the wallpaper's dominant colours (docs §3.4, §10).
## Null before the first build. This is the *unlit* palette; `lit_palette()` is what is drawn.
func environment_palette() -> ThemePalette:
	return _env_palette


## `environment_palette()` under this floor's light level - the colours the tiles, props,
## doors, interactables and the surround are actually painted in. Null before the first build.
func lit_palette() -> ThemePalette:
	return _lit_palette


## Colour the world outside the rooms is painted (the lit `void`).
func void_color() -> Color:
	if _lit_palette == null:
		return Color.BLACK
	return _lit_palette.get_color(&"void")


## Floor light level in use, always inside [AMBIENT_MIN, AMBIENT_MAX]. Driven by the mean
## luminance of the wallpaper's top third; 1.0 when there is no wallpaper analysis.
func ambient_level() -> float:
	return _ambient


## Light level this floor will be drawn at, computable before the nodes that carry it exist.
## `_apply_ambient()` stores it in `_ambient` and applies it; the readable prop tint is judged
## against it so a dark wallpaper brightens props instead of swallowing them.
func ambient_target() -> float:
	var light := _env_palette != null and _env_palette.is_light
	if light:
		return AMBIENT_MAX
	var base := AMBIENT_MAX if _wallpaper == null else _wallpaper.ambient_level(false)
	return clampf(base * light_scale, AMBIENT_MIN, AMBIENT_MAX)


## Wallpaper analysis to build with. Reads the `Desktop` autoload when it exists (it always
## does in-game); tests build without it and get no wallpaper influence.
static func live_wallpaper() -> WallpaperAnalyzer.Result:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	var desktop: Node = loop.root.get_node_or_null(^"Desktop")
	if desktop == null:
		return null
	var value: Variant = desktop.get("wallpaper")
	return value as WallpaperAnalyzer.Result


## Theme keys the floor's biome restricts its accents to. Empty before the first build or for
## a biome that does not narrow the pool.
func biome_palette_keys() -> PackedStringArray:
	return _biome_keys


## Applies `override` as the wallpaper analysis for the next build/retint. Tests and the
## live-wallpaper path use this; pass null to drop back to no wallpaper influence.
func set_wallpaper(override: WallpaperAnalyzer.Result) -> void:
	_wallpaper = override
	if built_layers == null:
		return
	_env_palette = _derive_palette(_base_palette)
	_apply_ambient()
	_retint_layers()


func _derive_palette(base: ThemePalette) -> ThemePalette:
	if base == null:
		base = TileRamp.live_palette()
	# Biome keys only. The wallpaper shapes the floor (`GenParams`) and sets its light
	# level; the colours are the theme's, and nothing else gets a vote.
	return base.derive_environment(_biome_keys)


## Every CanvasItem the floor's lighting model reaches: the surround, tile layers, props, wall
## decor, doors and the placed interactables. Deliberately excludes enemies and the player,
## whose authored colours must stay readable under any wallpaper (docs §10). These nodes are
## lit through the palette their materials carry, not by a `modulate`.
func environment_nodes() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	if _void_backdrop != null and is_instance_valid(_void_backdrop):
		out.append(_void_backdrop)
	if built_layers != null:
		for layer: TileMapLayer in built_layers.all_layers():
			out.append(layer)
	for node: Node2D in [_props_node, _decor_node]:
		if node != null and is_instance_valid(node):
			out.append(node)
	for room: RoomNode in rooms:
		if not is_instance_valid(room):
			continue
		for door: Door in room.doors:
			out.append(door)
	var placed: Array[Node] = [stairs]
	placed.append_array(get_altars())
	placed.append_array(get_shops())
	placed.append_array(get_shrines())
	for node: Node in placed:
		if node is CanvasItem and is_instance_valid(node):
			out.append(node as CanvasItem)
	return out


## Lights the environment at the wallpaper's ambient level (docs §3.4). The light lives in the
## palette the materials are built from, not in a `modulate`: scaling the drawn pixels divides
## the relationships out along with the light, which is what once left the floor rendering at
## the same value as the void outside it. See `ThemePalette.light_environment`.
func _apply_ambient() -> void:
	_ambient = ambient_target()
	var source := _env_palette if _env_palette != null else TileRamp.live_palette()
	_lit_palette = source.light_environment(_ambient)
	if _void_backdrop != null and is_instance_valid(_void_backdrop):
		_void_backdrop.color = void_color()


## Paints the surround. Added before any tile layer, so it is behind all of them.
##
## The colour is the floor's lit `void`; the shader on top of it gives that colour somewhere to
## go. A flat fill was a third of the frame on many floors (30x17 tiles of viewport against a
## floor-1 room of about 11x12, docs §3.3) and it read as missing screen, worst on a light
## theme where the void role is a bright block. `void_surround.gdshader` darkens it with
## distance from the nearest built tile and puts a fine grain on it, and can only ever darken:
## `void_color()` stays the brightest the surround is drawn anywhere.
func _build_void_backdrop() -> void:
	var grid := Rect2(Vector2.ZERO, Vector2(data.width, data.height) * Layers.TILE)
	var rect := grid.grow(VOID_MARGIN)
	_void_backdrop = Polygon2D.new()
	_void_backdrop.name = "Void"
	_void_backdrop.z_index = -100
	_void_backdrop.color = void_color()
	_void_backdrop.polygon = PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y)
		]
	)
	_void_backdrop.material = surround_material(data, DungeonLight.resolve(_light_profile), grid)
	add_child(_void_backdrop)


## The surround's ShaderMaterial, or null when the shader is missing (a stripped export; the
## floor then paints the flat `void` it always did rather than nothing at all).
static func surround_material(
	floor_data: FloorData, profile: DungeonLight, grid: Rect2
) -> ShaderMaterial:
	if not ResourceLoader.exists(SURROUND_SHADER):
		return null
	var shader := load(SURROUND_SHADER) as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(
		"grid_rect", Vector4(grid.position.x, grid.position.y, grid.size.x, grid.size.y)
	)
	mat.set_shader_parameter(
		"depth_map", surround_field(floor_data, profile.surround_falloff_tiles)
	)
	mat.set_shader_parameter("depth_drop", clampf(profile.surround_depth_drop, 0.0, 1.0))
	mat.set_shader_parameter("grain", clampf(profile.surround_grain, 0.0, 1.0))
	mat.set_shader_parameter("grain_px", maxf(1.0, profile.surround_grain_px))
	return mat


## How much of itself the surround keeps: `LightRig` drives this from the dark it draws, because
## the dark is a `Light2D` and a `Polygon2D` with a shader on it is the one environment surface
## that light does not reach. 1.0 is the layer off.
func set_surround_dark(level: float) -> void:
	if _void_backdrop == null or not is_instance_valid(_void_backdrop):
		return
	var mat := _void_backdrop.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("dark", clampf(level, 0.0, 1.0))


## "How near is the dungeon?" as a one-channel texture the size of the floor grid: 1 on a tile
## the generator built something on, falling linearly to 0 `falloff_tiles` away from the
## nearest one. A two-pass chamfer distance transform, which is O(tiles) and runs once per
## floor build - the alternative, asking the same question per fragment, is a search per pixel.
##
## Sampled clamped by the shader, so the margin the backdrop covers beyond the grid reads the
## border texel. The generator leaves a void margin around the layout, so that texel is 0 and
## the world outside the floor is at full depth, which is what it should be.
static func surround_field(floor_data: FloorData, falloff_tiles: float) -> ImageTexture:
	var w := maxi(1, floor_data.width)
	var h := maxi(1, floor_data.height)
	var far := float(w + h)
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for y in range(h):
		for x in range(w):
			dist[y * w + x] = 0.0 if floor_data.get_tile(x, y) != FloorData.Tile.VOID else far
	const DIAGONAL := 1.41421356
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			var d := dist[i]
			if x > 0:
				d = minf(d, dist[i - 1] + 1.0)
			if y > 0:
				d = minf(d, dist[i - w] + 1.0)
				if x > 0:
					d = minf(d, dist[i - w - 1] + DIAGONAL)
				if x < w - 1:
					d = minf(d, dist[i - w + 1] + DIAGONAL)
			dist[i] = d
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var d := dist[i]
			if x < w - 1:
				d = minf(d, dist[i + 1] + 1.0)
			if y < h - 1:
				d = minf(d, dist[i + w] + 1.0)
				if x < w - 1:
					d = minf(d, dist[i + w + 1] + DIAGONAL)
				if x > 0:
					d = minf(d, dist[i + w - 1] + DIAGONAL)
			dist[i] = d
	var image := Image.create(w, h, false, Image.FORMAT_R8)
	var falloff := maxf(0.5, falloff_tiles)
	for y in range(h):
		for x in range(w):
			var near := clampf(1.0 - dist[y * w + x] / falloff, 0.0, 1.0)
			image.set_pixel(x, y, Color(near, near, near, 1.0))
	return ImageTexture.create_from_image(image)


## Navigation polygon covering FLOOR/DOOR/CORRIDOR tiles, baked synchronously (headless ok).
## `blocked` (tile -> true) is carved out so enemies never path into solid props.
static func build_nav_polygon(floor_data: FloorData, blocked: Dictionary = {}) -> NavigationPolygon:
	var poly := NavigationPolygon.new()
	poly.agent_radius = NAV_AGENT_RADIUS
	var geo := NavigationMeshSourceGeometryData2D.new()
	var t := float(Layers.TILE)
	for y in range(floor_data.height):
		var x := 0
		while x < floor_data.width:
			if not _is_navigable(floor_data, blocked, x, y):
				x += 1
				continue
			var x0 := x
			while x < floor_data.width and _is_navigable(floor_data, blocked, x, y):
				x += 1
			var outline := PackedVector2Array(
				[
					Vector2(x0 * t, y * t),
					Vector2(x * t, y * t),
					Vector2(x * t, (y + 1) * t),
					Vector2(x0 * t, (y + 1) * t),
				]
			)
			geo.add_traversable_outline(outline)
	NavigationServer2D.bake_from_source_geometry_data(poly, geo)
	return poly


static func _is_navigable(floor_data: FloorData, blocked: Dictionary, x: int, y: int) -> bool:
	return floor_data.is_walkable(x, y) and not blocked.has(Vector2i(x, y))


func _build_room(room_data: FloorData.Room) -> void:
	var room := RoomNode.new()
	room.setup(room_data, data)
	_rooms_node.add_child(room)
	rooms.append(room)
	var tint := material_for_room(room_data.id)
	var prop_tint := prop_material_for_room(room_data.id)
	for neighbor: int in room_data.doors:
		var tile: Vector2i = room_data.doors[neighbor]
		var door := Door.new()
		door.name = "Door_to_%d" % neighbor
		door.tile = tile
		door.room_id = room_data.id
		door.leads_to = neighbor
		var horizontal := tile.y < room_data.rect.position.y or tile.y >= room_data.rect.end.y
		door.setup(atlas, tint, horizontal)
		door.position = room.tile_to_local(tile)
		room.add_door(door)
		_place_torches(tile, horizontal, room_data.id)
	var center := room.free_tile_near_center()
	if room_data.id == data.stairs_room:
		stairs = Stairs.new()
		stairs.name = "Stairs"
		stairs.setup(atlas, prop_tint, data.boss_room >= 0)
		stairs.position = room.tile_to_local(center)
		room.blocked_tiles[center] = true
		room.add_child(stairs)
		center = room.free_tile_near_center()
	match room_data.type:
		FloorData.RoomType.ALTAR:
			var node := Altar.new()
			node.name = "Altar"
			node.setup(atlas, tint)
			node.position = room.tile_to_local(center)
			room.blocked_tiles[center] = true
			room.add_child(node)
			altars.append(node)
			if altar == null:
				altar = node
		FloorData.RoomType.SHOP:
			var node := Shop.new()
			node.name = "Shop"
			node.setup(atlas, tint)
			node.position = room.tile_to_local(center)
			room.blocked_tiles[center] = true
			room.add_child(node)
			shops.append(node)
			if shop == null:
				shop = node
		FloorData.RoomType.SHRINE:
			var node := Shrine.new()
			node.name = "Shrine"
			node.setup(atlas, tint)
			node.position = room.tile_to_local(center)
			room.blocked_tiles[center] = true
			room.add_child(node)
			shrines.append(node)
			if shrine == null:
				shrine = node
		FloorData.RoomType.TREASURE:
			room.spawn_chest(_rng.randf() < treasure_trap_chance())


## Puts one lit torch beside a door. The sconce is drawn in the room's flame material
## (`torch_material_for_room`) rather than in its tile material, and carries a PointLight2D, so
## a torch is the only thing in the dungeon that is both warm and a light source.
##
## One, not the pair it used to hang. A flanking pair is a handsome doorway on a floor that has
## an ambient wash under it; with the torches *being* the light it is the difference between a
## dungeon lit in pockets and one lit end to end. Measured on `lighting_frame` gruvbox: with two
## per door, not one floor tile in the whole viewport stood four tiles clear of a light, so there
## was no unlit ground on screen at all - which is the owner's "there should be no other light"
## arriving by the back door, as a hundred small ones. Which side gets it is the first side with
## a wall to hang it on, so a door always has a torch and never has two.
func _place_torches(door_tile: Vector2i, horizontal: bool, room_id: int) -> void:
	var axis := Vector2i.RIGHT if horizontal else Vector2i.DOWN
	var cols: Array[int] = [FloorBuilder.SPECIAL_TORCH_A, FloorBuilder.SPECIAL_TORCH_B]
	var tint := torch_material_for_room(room_id)
	for i in range(2):
		var side := -1 if i == 0 else 1
		var tile := door_tile + axis * side * TORCH_OFFSET
		if data.get_tile(tile.x, tile.y) != FloorData.Tile.WALL:
			continue
		var torch := FloorBuilder.atlas_sprite(atlas, cols[i])
		torch.name = "Torch_%d_%d" % [tile.x, tile.y]
		torch.material = tint
		torch.light_mask = TORCH_SPRITE_LIGHT_MASK
		torch.position = (Vector2(tile) + Vector2(0.5, 0.5)) * Layers.TILE
		_decor_node.add_child(torch)
		_add_torch_light(torch)
		return


## Hangs a point light on a torch, unless this floor has already spent its light budget.
func _add_torch_light(torch: Node2D) -> void:
	var profile := _light_profile
	if profile == null or _torch_lights.size() >= profile.torch_max_lights:
		return
	if _light_texture == null:
		_light_texture = DungeonLight.make_texture(profile.light_texture_size)
	var light := PointLight2D.new()
	light.name = "Light"
	light.texture = _light_texture
	light.texture_scale = profile.torch_texture_scale * profile.torch_radius_scale()
	light.position = profile.torch_offset
	light.shadow_enabled = false
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.color = profile.torch_color(_torch_palette())
	light.energy = torch_light_energy() * profile.torch_energy_scale()
	torch.add_child(light)
	_torch_lights.append(light)
	_update_flicker()


## Colour a torch's light burns in: the theme's own `heat` turned part of the way toward its
## `accent` (`DungeonLight.torch_role_color`), so the pool of light on the floor is the
## desktop's colour and not the same orange on every theme. The flame sprite itself stays on
## `heat`/`loot` - see `TileRamp.flame_colors` - so a torch still reads as fire.
func torch_light_color() -> Color:
	var profile := _light_profile if _light_profile != null else DungeonLight.resolve()
	return profile.torch_role_color(_torch_palette())


## The palette the torches are lit from: this floor's lit palette, else the live theme.
func _torch_palette() -> ThemePalette:
	return _lit_palette if _lit_palette != null else TileRamp.live_palette()


## Energy one torch light burns at on this floor, before the flicker and before the mood: the
## dark exactly undone (`DungeonLight.torch_energy`, and `LightingProfile.unlit_floor` plus it is
## 1). One number on every theme. It used to track the floor's own exposure and take a 0.4
## turn-down on a light theme, because an additive pool blew out a floor that was already lit by
## an ambient wash; no floor is, on any theme, so a paper dungeon is lit by the same fire a navy
## one is and the pool restores each of them to its own paper.
func torch_light_energy() -> float:
	var profile := _light_profile if _light_profile != null else DungeonLight.resolve()
	return profile.torch_energy


## The torch lights this floor owns (tests and the music module's beat pulse).
func torch_lights() -> Array[PointLight2D]:
	return _torch_lights


## How far the flicker may swing a torch's energy right now: `DungeonLight.torch_flicker_amplitude`
## - the tuned amount, scaled by the music's mood (a calm track's torches barely wander) and
## damped by the accessibility policy, which takes it to a tenth under reduced flash and to
## nothing under reduce motion. A floor with torches keeps processing at zero flicker while the
## music lights are on, because the mood still moves their colour and level; with both off
## there is nothing per frame to do and it stops.
func torch_flicker_amount() -> float:
	var profile := _light_profile if _light_profile != null else DungeonLight.resolve()
	return profile.torch_flicker_amplitude()


func _update_flicker() -> void:
	var live := torch_flicker_amount() > 0.0 or MusicReactiveLayer.enabled()
	set_process(not _torch_lights.is_empty() and live)


## One frame of the torches: slow noise for the flicker, and the music's mood on the colour
## and the level. The mood arrives from `MusicReactiveLayer` already crossfaded over seconds,
## so nothing here can step.
func _process(delta: float) -> void:
	if _torch_lights.is_empty():
		set_process(false)
		return
	_light_time += delta
	var profile := _light_profile if _light_profile != null else DungeonLight.resolve()
	var amount := torch_flicker_amount()
	var base := torch_light_energy() * profile.torch_energy_scale()
	var color := profile.torch_color(_torch_palette())
	# Typed rather than inferred: the mood contract reaches this file through the `Music`
	# autoload, and that cycle leaves the return type unresolved while the scripts load.
	var reach: float = profile.torch_texture_scale * profile.torch_radius_scale()
	# Noise along time at the tuned rate: a torch wanders, never cycles.
	var t := _light_time * profile.torch_flicker_hz * 40.0
	for i in range(_torch_lights.size()):
		var light := _torch_lights[i]
		if not is_instance_valid(light):
			continue
		# A per-torch offset, so a corridor of torches breathes rather than as one lamp.
		var n := _flicker_noise.get_noise_1d(t + float(i) * 173.0)
		light.energy = base * (1.0 + amount * n)
		light.color = color
		light.texture_scale = reach


## Spawns the generator's props: kind names come from FloorData.Room.prop_kinds (index-matched
## with prop_positions); a missing entry falls back to a deterministic tile hash. Every prop
## gets its own RNG stream so breaking one never shifts another roll — which is also what makes
## the roll *repeatable*, so each prop's break is recorded here (`_on_prop_broken`) for the save
## to carry and a resume to replay without paying again.
func _build_props() -> void:
	var pal := _lit_palette if _lit_palette != null else TileRamp.live_palette()
	for room_data: FloorData.Room in data.rooms:
		var tint := prop_accent_material_for_room(room_data.id)
		var burst := pal.get_color(&"wall_top")
		for i in range(room_data.prop_positions.size()):
			var pos: Vector2i = room_data.prop_positions[i]
			if not data.is_walkable(pos.x, pos.y):
				continue
			var hashed := FloorBuilder.tile_hash(data.seed_value, pos.x, pos.y)
			var prop := Prop.new()
			prop.name = "Prop_%d_%d" % [pos.x, pos.y]
			var prop_rng := RandomNumberGenerator.new()
			prop_rng.seed = RunRng.hash_combine(hashed, data.floor_index + 1)
			var fallback := hashed % Prop.KIND_COUNT
			if i < room_data.prop_kinds.size():
				prop.setup_by_kind(
					data.biome, room_data.prop_kinds[i], tint, prop_rng, burst, fallback
				)
			else:
				prop.setup(data.biome, fallback, tint, prop_rng, burst)
			prop.position = (Vector2(pos) + Vector2(0.5, 0.5)) * Layers.TILE
			prop.broken.connect(_on_prop_broken)
			_props_node.add_child(prop)
			props.append(prop)


## Tile the object standing at local position `world` occupies.
static func tile_of(world: Vector2) -> Vector2i:
	return Vector2i((world / float(Layers.TILE)).floor())


## Tiles whose breakable prop is gone (see `_broken_prop_tiles`). Fed to `RunState` by
## `FloorRestore.capture()`.
func broken_prop_tiles() -> Array[Vector2i]:
	return _broken_prop_tiles.duplicate()


## Resume: re-breaks the props the save says the player already smashed, without re-rolling
## their gold or re-firing their burst (`Prop.restore_broken`). Returns how many it matched;
## a tile with no prop on it any more is skipped rather than invented.
func restore_broken_props(tiles: Array[Vector2i]) -> int:
	if tiles.is_empty():
		return 0
	var wanted: Dictionary = {}
	for tile: Vector2i in tiles:
		wanted[tile] = true
	var matched := 0
	for prop: Prop in props.duplicate():
		if not is_instance_valid(prop):
			continue
		var tile := tile_of(prop.position)
		if not wanted.has(tile):
			continue
		prop.restore_broken()
		_note_broken_prop(tile)
		props.erase(prop)
		matched += 1
	return matched


## The live mimic chests of this floor. `TrapPlacer` parents every generator trap straight to
## the floor root, so the floor can carry their save state even though the traps module is
## what builds them.
func mimic_chests() -> Array[MimicChest]:
	var out: Array[MimicChest] = []
	for child: Node in get_children():
		var mimic := child as MimicChest
		if mimic != null and is_instance_valid(mimic) and not mimic.is_queued_for_deletion():
			out.append(mimic)
	return out


## Starts recording which mimic chests the player springs. `FloorRestore.apply()` calls it once
## per floor build, after the traps are placed; calling it again is harmless.
func watch_mimics() -> void:
	for mimic: MimicChest in mimic_chests():
		if not mimic.revealed.is_connected(_on_mimic_revealed):
			mimic.revealed.connect(_on_mimic_revealed)


## Tiles whose mimic chest has already been sprung (see `_revealed_mimic_tiles`).
func revealed_mimic_tiles() -> Array[Vector2i]:
	return _revealed_mimic_tiles.duplicate()


## Resume: removes the mimic chests the player already sprang, so the enemy each one turns
## into - and the gold, heart and elite drop that enemy pays - cannot be farmed by quitting
## and continuing. Returns how many it removed.
func restore_revealed_mimics(tiles: Array[Vector2i]) -> int:
	if tiles.is_empty():
		return 0
	var wanted: Dictionary = {}
	for tile: Vector2i in tiles:
		wanted[tile] = true
	var matched := 0
	for mimic: MimicChest in mimic_chests():
		var tile := tile_of(mimic.position)
		if not wanted.has(tile):
			continue
		_note_revealed_mimic(tile)
		mimic.queue_free()
		matched += 1
	return matched


func _on_prop_broken(prop: Prop) -> void:
	if prop == null:
		return
	_note_broken_prop(tile_of(prop.position))
	props.erase(prop)


func _on_mimic_revealed(mimic: MimicChest) -> void:
	if mimic != null:
		_note_revealed_mimic(tile_of(mimic.position))


func _note_broken_prop(tile: Vector2i) -> void:
	if not _broken_prop_tiles.has(tile):
		_broken_prop_tiles.append(tile)


func _note_revealed_mimic(tile: Vector2i) -> void:
	if not _revealed_mimic_tiles.has(tile):
		_revealed_mimic_tiles.append(tile)


func _build_nav() -> void:
	nav_region = NavigationRegion2D.new()
	nav_region.name = "Nav"
	nav_region.navigation_polygon = build_nav_polygon(data, _prop_tiles())
	add_child(nav_region)


## Tiles occupied by a solid prop (StaticBody2D on Layers.PROP blocks Entity movement). Flat
## kinds are walked over by enemies too, so they are not carved out of the nav polygon.
func _prop_tiles() -> Dictionary:
	var out: Dictionary = {}
	for prop: Prop in props:
		if prop.solid:
			out[tile_of(prop.position)] = true
	return out


func _auto_bind_player() -> void:
	if _bound_player != null and is_instance_valid(_bound_player):
		return
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(Interactable.PLAYER_GROUP):
		if node is Node2D and node.has_signal(&"interact_pressed"):
			bind_player(node as Node2D)
			return


func _on_interact_pressed() -> void:
	Interactable.dispatch(_bound_player)


func _on_palette_changed(palette: ThemePalette) -> void:
	_wallpaper = live_wallpaper()
	_base_palette = palette
	_env_palette = _derive_palette(palette)
	_apply_ambient()
	_retint_layers()


## Crossfades every tile-layer material to `_env_palette` and re-derives the readable prop
## tint that sits on top of it. Shared by theme changes and wallpaper changes.
func _retint_layers() -> void:
	if built_layers == null:
		return
	built_layers.retint(_lit_palette, self)
	for room_id: int in _prop_tints:
		var entry: Dictionary = _prop_tints[room_id]
		Prop.retint_readable(
			entry["material"] as ShaderMaterial, entry["base"] as ShaderMaterial, self
		)
	for room_id: int in _prop_accent_tints:
		var accent_entry: Dictionary = _prop_accent_tints[room_id]
		Prop.retint_accent(
			accent_entry["material"] as ShaderMaterial, accent_entry["base"] as ShaderMaterial, self
		)
	for room_id: int in _flame_tints:
		var entry: Dictionary = _flame_tints[room_id]
		var flame_base := entry["base"] as ShaderMaterial
		# Crossfaded like every other material rather than swapped on the spot: a torch that
		# jumps to the new fire colour a frame before the wall behind it starts moving is the
		# one thing in the room that gives the retint away.
		Prop.crossfade(
			entry["material"] as ShaderMaterial, flame_base, self, _flame_colors(flame_base)
		)
	_relight_torches()


## Puts the new palette's fire colour on every torch light. Lights are not materials, so the
## tile crossfade does not reach them; they swap with the theme the way the HUD does.
func _relight_torches() -> void:
	var profile := _light_profile if _light_profile != null else DungeonLight.resolve()
	var color := profile.torch_color(_torch_palette())
	var energy := torch_light_energy() * profile.torch_energy_scale()
	var reach: float = profile.torch_texture_scale * profile.torch_radius_scale()
	for light: PointLight2D in _torch_lights:
		if not is_instance_valid(light):
			continue
		light.color = color
		light.energy = energy
		light.texture_scale = reach
	_update_flicker()


## A new wallpaper analysis landed: swap prop colours and the light level with the same
## crossfade a theme change uses (docs §3.5). Theme changes arrive on `palette_changed`.
func _on_desktop_changed(kind: int) -> void:
	if kind & EventBus.DesktopChangeKind.WALLPAPER and built_layers != null:
		set_wallpaper(live_wallpaper())


func _on_room_entered(room_id: int) -> void:
	set_current_room(room_id)
