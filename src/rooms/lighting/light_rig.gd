## The dynamic lighting of one floor (docs 10, "Lighting"): a child of `FloorRoot` named
## `Lighting` that owns the dark the floor sits in, the wall lanterns hung on the generator's
## anchors, the occluders every wall casts shadow with, the shade over rooms nobody has
## entered, the fixture glows (stairs, altars, shrines), the shadow blobs under the player and
## the enemies, and the pool of gameplay emitters (`LightEmitter`).
##
## **Every lit pixel has a source you can point at.** The dark is one flat light over the whole
## floor holding every surface at `LightingProfile.unlit_floor` - near black, on every theme -
## and everything that lifts a pixel off it is a thing standing in the room: a lantern, a door
## torch, the player's own pool, a spell, a chest, the stairs. There is no ambient level to
## turn up, no per-theme exposure, and no lift over a cleared room; the owner's ruling deleted
## the idea rather than the number, so there is nothing left for a wash to come back through.
##
## Three sources drive every colour and level here, and nothing is authored:
##   * the theme - every light is a palette role through `light_color_for()`, so a swap
##     mid-run retints all of them from the same `palette_changed` the tiles follow;
##   * the music mood - through the live light contract on `DungeonLight` (`torch_color`,
##     `torch_energy_scale`, `torch_radius_scale`, `torch_flicker_amplitude`; docs 10.2),
##     which arrives crossfaded over seconds, reaches the *lights* and nothing else, and never
##     pulses (no beat path, anywhere);
##   * the settings - `lighting_quality` OFF is the floor as it was before this layer existed,
##     LOW is lights without shadows, HIGH casts them from the nearest few lights to the camera
##     (`LightingProfile.shadow_casters`), because a shadow-casting light is the one thing in
##     the 2D renderer that costs per light and per occluder.
##
## Freed with the floor: `FloorRoot.clear_floor()` frees every child, the emitters are this
## node's children, and `_exit_tree` drops every bus connection, so a cleared floor leaves no
## light behind (`tests/unit/rooms/lighting_rig_test.gd`).
class_name LightRig
extends Node2D

const NAME := "Lighting"
const GROUP := &"light_rig"
## Seconds between two passes of the shadow-caster cap.
const CASTER_TICK := 0.1
const BLOB_NAME := "ShadowBlob"
## Occluder light masks: walls on bit 1, props (and bosses) on bit 2, so a light can shadow
## from the walls without shadowing from every crate in the room.
const WALL_OCCLUDER_MASK := 1
const PROP_OCCLUDER_MASK := 2
## Item light masks. The dark is a light (a flat MIX toward black), so what it reaches is a
## `light_mask` question: the environment (bit 1, every CanvasItem's default) and every body -
## props, interactables, chests, enemies, the player (bit 3) - take it in full and identically;
## tells (bit 4: pickups on a dark theme, drops, traps, health bars, alert marks, telegraphs,
## damage numbers, the player marker) take none, because a tell is the game telling you
## something and not a surface in the room.
##
## Bodies used to take a *gentler* dark than the floor (`prop_exposure_power`: a crate at 0.85
## over a floor at 0.32), which is what let a prop read in an unlit room. At a floor this dark
## the same exponent would leave every prop in the dungeon at 0.65 of itself with nothing
## lighting it - the ambient wash again, wearing a prop's clothes - so it is gone, along with
## the second light every lantern carried to undo it. One dark, one pool: a light that reaches a
## body reaches it with exactly the pool it puts on the floor beside it, on `LIT_MASK`, one
## light. Door torches, lanterns and every emitter that lives with its host (a chest, an altar,
## the stairs, a fire, a bolt in flight, the player's own light) burn this way. An emitter with a
## fade of its own - a swing, a spell bloom, an explosion, any one-shot - stays on `ENV_MASK` and
## lights the ground only. Nothing lights a tell.
const ENV_MASK := 1
const PROP_MASK := 4
const TELL_MASK := 8
const LIT_MASK := ENV_MASK | PROP_MASK
const BODY_LIT_MASK := LIT_MASK
## Side of the flat white square every room shade and lift is drawn with.
const SHADE_TEXTURE_SIZE := 16
const SHADE_TEXTURE_KEY := "res://.lighting/shade"
const SHADE_ALPHA_STEP := 0.005
const BLOB_TEXTURE_KEY := "res://.lighting/blob"
## Node names of the tells that must never sit under the darkness: an enemy's health bar,
## its alert mark and its windup telegraph, the player's own marker ring. They are put on
## `TELL_MASK`, which no light - the darkness included - reaches.
const TELL_NAMES: PackedStringArray = ["HpBar", "AlertMark", "Telegraph", "Marker"]
## Node names of the sprites a body draws itself with (`PROP_MASK`).
const BODY_NAMES: PackedStringArray = ["Sprite", "Sprite2D", "Outline", "Glow"]

## One shared unshaded material (kept for callers that used it; the mask is what matters).
static var _unshaded: CanvasItemMaterial
## The flat shade squares, by path (`shade_texture`), held so they outlive the floor that
## first asked for one.
static var _shade_textures: Dictionary = {}

## The rig of the live floor, or null.
static var _current: LightRig

var profile: LightingProfile
var root: FloorRoot
## The dark the floor sits in: one flat MIX-toward-black point light the size of the whole
## floor and its surround, on `LIT_MASK` so the environment and the bodies standing in it take
## exactly the same amount. A point light, not a DirectionalLight2D: measured on a frame, the
## compatibility renderer's directional light reached items outside its `range_item_cull_mask`
## and darkened the props twice.
var darkness: PointLight2D
var lanterns: Array[WallLantern] = []
var occluders: Array[LightOccluder2D] = []
## The merged wall cores (`WallOccluders.runs_for`), kept for the caster pass.
var wall_runs: Array[WallOccluders.Run] = []
## Every emitter this rig ever made, alight or parked.
var emitters: Array[LightEmitter] = []
var _free: Array[LightEmitter] = []
var _lanterns_node: Node2D
var _occluders_node: Node2D
var _shades_node: Node2D
var _emitters_node: Node2D
## Room id -> shade light still standing over it.
var _shades: Dictionary = {}
var _unlit: float = 1.0
var _caster_clock: float = 0.0
var _light_texture: Texture2D
var _quality: LightingProfile.Quality = LightingProfile.Quality.HIGH
var _shadows: bool = true
## The strength the dark carries this frame (its texture's alpha).
var _darkness_strength: float = 0.0


## The rig lighting the live floor (the most recently built one), or null.
static func current() -> LightRig:
	if _current != null and is_instance_valid(_current) and _current.is_inside_tree():
		return _current
	return null


## The rig under `floor_root`, or null when the floor has none.
static func of(floor_root: Node) -> LightRig:
	if floor_root == null:
		return null
	return floor_root.get_node_or_null(NAME) as LightRig


## Builds the layer for `floor_root`, which must already be built. Reads the quality setting
## once; a later change (`EventBus.settings_changed`) rebuilds.
func build(floor_root: FloorRoot, tuning: LightingProfile = null) -> void:
	root = floor_root
	profile = LightingProfile.resolve(tuning)
	name = NAME
	add_to_group(GROUP)
	_current = self
	_quality = LightingProfile.quality()
	_shadows = LightingProfile.shadows_enabled()
	_teardown()
	if _quality == LightingProfile.Quality.OFF or root == null or root.data == null:
		if root != null and is_instance_valid(root):
			root.set_surround_dark(1.0)
		set_process(false)
		return
	_light_texture = DungeonLight.make_texture(DungeonLight.resolve().light_texture_size)
	_build_darkness()
	_build_occluders()
	_build_lanterns()
	_build_shades()
	_build_fixtures()
	_place_torch_lights()
	_prewarm()
	_blob_everyone()
	_mask_lights_and_bodies()
	_unlit = profile.unlit_level()
	relight()
	_apply_dark()
	_apply_casters()
	set_process(true)


func _ready() -> void:
	_connect(EventBus.palette_changed, _on_palette_changed)
	_connect(EventBus.room_entered, _on_room_entered)
	_connect(EventBus.room_cleared, _on_room_cleared)
	_connect(EventBus.settings_changed, _on_settings_changed)
	_connect(EventBus.enemy_spawned, _on_enemy_spawned)


func _exit_tree() -> void:
	for sig: Signal in [
		EventBus.palette_changed,
		EventBus.room_entered,
		EventBus.room_cleared,
		EventBus.settings_changed,
		EventBus.enemy_spawned
	]:
		_disconnect_all(sig)
	if _current == self:
		_current = null


# ---------------------------------------------------------------- queries


## Whether the layer is doing anything on this floor.
func active() -> bool:
	return darkness != null and is_instance_valid(darkness)


func quality() -> LightingProfile.Quality:
	return _quality


func shadows() -> bool:
	return _shadows


## What an unlit surface keeps of itself on this floor (1 when the layer is off). Not a lever
## and not a per-frame quantity: it is `LightingProfile.unlit_floor`, the same on every theme
## and under every track, and the only reason it is read through the rig at all is so a test can
## ask the thing that drew the frame rather than the resource behind it.
func unlit_level() -> float:
	return _unlit if active() else 1.0


## The colour a light in palette `role` burns in on this floor. Fire (`heat`) is exactly the
## contract's torch colour (`DungeonLight.torch_color`: the theme's fire turned toward its
## accent, made a light, graded by the mood); every other role is that role's lit colour put
## through the same two steps, so a frost light is the theme's `cold` the way a torch is its
## `heat`.
func light_color_for(role: StringName) -> Color:
	var pal := root.lit_palette() if root != null else TileRamp.live_palette()
	if pal == null:
		pal = ThemePalette.fallback()
	var light := DungeonLight.resolve()
	if role == &"heat":
		return light.torch_color(pal)
	return Music.mood_state().light_color(light.light_color(pal.get_color(role)))


## The light mask loot - a pickup, a dropped item - draws itself with.
##
## `TELL_MASK` on a dark theme: the exemption is what keeps a coin readable in an unlit corner,
## and there its ink is bright, so standing out of the dark only opens the gap between the coin
## and the floor under it.
##
## `PROP_MASK` on a light theme, where the same exemption *closes* that gap. A light theme's loot
## is dark ink on bright paper; the dark takes the surface down toward the ink and leaves the ink
## alone, so the drop lying on a wall lost its 3:1 on `pickup_frame` (catppuccin-latte 2.27,
## white 2.52, against a 3.0 line both cleared with the layer off).
##
## This is the one surface in the dungeon still drawn outside the lighting layer, and it is a
## *tell* rather than a surface - the same family as a health bar, an alert mark and a windup
## telegraph, which are all exempt for the same reason and none of which the owner's ruling
## names. Giving a coin its own emitter instead was tried in the round that took the ambient out:
## it is the right shape and it is not a one-line change, because the drop is read against the
## floor it covers and an emitter lights both.
static func loot_mask() -> int:
	var pal := TileRamp.live_palette()
	return PROP_MASK if pal != null and pal.is_light else TELL_MASK


## Puts every light of the floor on `LIT_MASK` and every body sprite on `PROP_MASK`: the
## props and interactables the floor built, and the player if one is in the tree.
func _mask_lights_and_bodies() -> void:
	for lantern: WallLantern in lanterns:
		if lantern.light != null:
			lantern.light.range_item_cull_mask = LIT_MASK
	for light: PointLight2D in root.torch_lights():
		if is_instance_valid(light):
			light.range_item_cull_mask = LIT_MASK
	for e: LightEmitter in emitters:
		e.range_item_cull_mask = LIT_MASK if e.lights_bodies() else ENV_MASK
	var bodies: Array[Node] = []
	for prop: Prop in root.props:
		bodies.append(prop)
	if root.stairs != null:
		bodies.append(root.stairs)
	bodies.append_array(root.get_altars())
	bodies.append_array(root.get_shrines())
	bodies.append_array(root.get_shops())
	for room: RoomNode in root.rooms:
		if room.chest != null and is_instance_valid(room.chest):
			bodies.append(room.chest)
	for body: Node in bodies:
		mask_body(body)
	var player := _player()
	if player != null:
		mask_body(player)
		var light := player.get_node_or_null(^"Light") as Light2D
		if light != null:
			light.range_item_cull_mask = BODY_LIT_MASK
	_drive_player_light()


## Puts the sprites `body` draws itself with on `PROP_MASK` and its tells on `TELL_MASK`.
## Idempotent; safe on any node.
static func mask_body(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	for child: Node in body.get_children():
		if not child is CanvasItem:
			continue
		var item := child as CanvasItem
		if BODY_NAMES.has(String(child.name)) and item.light_mask != 0:
			item.light_mask = PROP_MASK
	unshade_tells(body)


## The mood's multiplier on every light's energy (`DungeonLight.torch_energy_scale`).
func mood_energy() -> float:
	return DungeonLight.resolve().torch_energy_scale()


## The multiplier every *gameplay* light burns under: the mood, and nothing else. There used to
## be an `emitter_light_scale` turn-down on light themes, because an additive pool had nowhere
## to land on a floor that was already near white; there is no such floor now, on any theme
## (`LightingProfile.unlit_floor`), so a paper dungeon is lit by the same lights a navy one is.
func light_scale() -> float:
	return mood_energy()


## Energy the player's own pool burns at: the `player` row of the emitter table under the mood.
## The light itself is a node in `player.tscn`; the rig drives it from the table so the scene
## and the data cannot drift. In a room this dark it is the light the player sees *by*, and it
## is the one light that is always on screen - so it burns at the dark exactly undone, like a
## torch, and a player can always fight what is standing next to them.
func player_light_energy() -> float:
	return float(profile.emitter_spec(&"player")["energy"]) * light_scale()


## Radius the player's own pool reaches, as a `texture_scale`: the `player` row's radius under
## the mood's own radius lever. The scene authors 1.5 and the capture fixture authors 1.5, and
## for a round that was the only number that mattered, so the table's `radius` for the player
## did nothing at all. It matters now: in a room lit in pockets the pool the player carries is
## how the player sees between them, and it is the one light that is always on screen.
func player_light_reach() -> float:
	var spec := profile.emitter_spec(&"player")
	return float(spec["radius"]) * DungeonLight.resolve().torch_radius_scale()


## Puts the player's own light on that energy and that radius. Called on every build, every
## palette change and every caster tick rather than once: the player is not always in the tree
## when the floor is built (a capture adds it after, and a run swaps it between floors), and a
## light the rig set once at build time would be the scene's authored 0.7 and 1.5 for the whole
## of any floor it missed.
## The player's own pool, or null when no player is in the tree. Public because the frame
## capture has to leave the floor it lights out of "the floor between the pools".
func player_light() -> Light2D:
	return _player_light()


## Lights the player, from the motes the player is carrying.
##
## The scene's own bare `Light` node is switched off the moment the motes exist, and that is not
## tidying. `player.tscn` authors a `PointLight2D` with an energy, a `texture_scale` and no
## texture at all - so it emitted nothing, and the player had never actually carried a pool
## (measured on the `combat` scenario: the floor under the player read 0.0024 against 0.0021 two
## tiles away). The obvious repair is to hand it a texture, and that repair is the ambient wash
## again with a parent node: a lit disc with nothing on screen causing it. The owner's own answer
## was "the player and enemies are particles, from both should illuminate a bit", so the light
## belongs to something a player can see, and `EntitySparks` is that something.
func _drive_player_light() -> void:
	var player := _player()
	if player == null:
		return
	var sparks := add_sparks(player)
	if sparks != null:
		sparks.relight(
			light_color_for(_player_role(player)), player_light_energy(), player_light_reach()
		)
		sparks.apply_accessibility(Accessibility.reduce_motion(), profile.reduced_motion_motes)
	var scene_light := player.get_node_or_null(^"Light") as Light2D
	if scene_light != null:
		scene_light.enabled = sparks == null


## The palette role this player's motes burn in: their class's own, so each of the four carries a
## different colour and a player can find themselves in a dark room by it.
static func _player_role(player: Node2D) -> StringName:
	var def: Variant = player.get(&"class_def")
	if def is ClassDef:
		return EntitySparks.role_for_class((def as ClassDef).id)
	return &"accent"


## Radius one lantern's pool reaches, as a multiple of the light texture: the authored
## `lantern_texture_scale` under the mood's own radius lever (`DungeonLight.torch_radius_scale`,
## x0.78..x1.28 calm to loud). With a room lit in a few pockets rather than evenly, how wide a
## pocket is is one of the largest things on the screen, so the mood is given it.
func lantern_reach() -> float:
	return profile.lantern_texture_scale * DungeonLight.resolve().torch_radius_scale()


## Energy a lantern burns at on this floor, before the mood: the dark exactly undone
## (`LightingProfile.lantern_energy`, and `unlit_floor + lantern_energy = 1`). One number, every
## theme - there is no bright floor left anywhere for an additive pool to blow out.
func lantern_energy() -> float:
	return profile.lantern_energy


## Every light on the floor that may cast a shadow, nearest to `from` first. A light standing
## inside a wall core (a door torch on a corner cell with no open face) is left out: with
## shadows on it would light nothing at all, so it shines without them instead.
func shadow_candidates(from: Vector2) -> Array[Light2D]:
	var all: Array[Light2D] = []
	var out: Array[Light2D] = []
	var player := _player()
	if player != null:
		var light := player.get_node_or_null(^"Light") as Light2D
		if light != null:
			all.append(light)
	for lantern: WallLantern in lanterns:
		if lantern.light != null:
			all.append(lantern.light)
	if root != null:
		for light: PointLight2D in root.torch_lights():
			if is_instance_valid(light):
				all.append(light)
	for e: LightEmitter in emitters:
		if e.alive and e.may_shadow:
			all.append(e)
	for light: Light2D in all:
		if not inside_wall(
			light.global_position - (root.global_position if root != null else Vector2.ZERO)
		):
			out.append(light)
	out.sort_custom(
		func(a: Light2D, b: Light2D) -> bool:
			return (
				a.global_position.distance_squared_to(from)
				< b.global_position.distance_squared_to(from)
			)
	)
	return out


## True when `local` (floor-local px) lies inside a wall's occluder core.
func inside_wall(local: Vector2) -> bool:
	for run: WallOccluders.Run in wall_runs:
		if run.rect.has_point(local):
			return true
	return false


## The lights currently casting shadows.
func shadow_casters() -> Array[Light2D]:
	var out: Array[Light2D] = []
	for light: Light2D in shadow_candidates(_view_centre()):
		if light.shadow_enabled:
			out.append(light)
	return out


## Emitters alight right now.
func live_emitters() -> Array[LightEmitter]:
	var out: Array[LightEmitter] = []
	for e: LightEmitter in emitters:
		if e.alive:
			out.append(e)
	return out


## Rooms still under the unexplored shade.
func shaded_room_ids() -> Array[int]:
	var out: Array[int] = []
	for id: Variant in _shades.keys():
		out.append(int(id))
	return out


# ---------------------------------------------------------------- emitters


## Takes a light from the pool for `kind`. Null past the cap or when the layer is off.
func acquire_emitter(kind: StringName, host: Node2D, pos: Vector2) -> LightEmitter:
	if not active():
		return null
	var e: LightEmitter = null
	if not _free.is_empty():
		e = _free.pop_back()
	elif emitters.size() < profile.emitter_max:
		e = _make_emitter()
	if e == null:
		return null
	e.start(kind, profile.emitter_spec(kind), host, pos, self)
	return e


## Parks a light the emitter has already put out.
func release_emitter(e: LightEmitter) -> void:
	if e != null and not _free.has(e):
		_free.append(e)


# ---------------------------------------------------------------- relight


## Re-reads every colour and level from the theme and the mood (a palette swap, a rebuild).
func relight() -> void:
	if not active():
		return
	var energy := lantern_energy() * mood_energy()
	var reach := lantern_reach()
	for lantern: WallLantern in lanterns:
		lantern.relight(light_color_for(profile.lantern_role_for(lantern.kind)), energy, reach)
	for e: LightEmitter in emitters:
		e.retint()
	_drive_player_light()
	relight_sparks()
	var pal := root.lit_palette()
	if is_inside_tree():
		var blob_alpha := profile.blob_alpha * (0.6 if pal != null and pal.is_light else 1.0)
		for blob: Node in get_tree().get_nodes_in_group(BLOB_NAME):
			if blob is CanvasItem:
				(blob as CanvasItem).modulate.a = blob_alpha


func _process(delta: float) -> void:
	if not active():
		return
	# Energy, colour and reach, every frame. Colour and reach used to be set only on a build or
	# a theme swap, which meant the one lever the music had on the lights - the flame's own
	# temperature - never moved during a run at all: `light_color_for()` reads the live mood and
	# nothing called it between floors. That is most of why "the music STILL doesn't seem to do
	# anything" survived a round that measured the mapping and found it wide. All three arrive
	# already crossfaded over `MusicMoodLevers.crossfade_seconds`, so none of them can step.
	var energy := lantern_energy() * mood_energy()
	var reach := lantern_reach()
	# One colour lookup for the floor, not one per lantern: a floor hangs a single lantern kind
	# (`LightingProfile.lantern_kind_for`), so they all burn in the same role.
	var color := light_color_for(
		profile.lantern_role_for(profile.lantern_kind_for(root.data.biome))
	)
	for lantern: WallLantern in lanterns:
		if lantern.light != null:
			lantern.relight(color, energy, reach)
	_caster_clock += delta
	if _caster_clock >= CASTER_TICK:
		_caster_clock = 0.0
		_apply_casters()
		_drive_player_light()
		relight_sparks()
		_poll_visits()


# ---------------------------------------------------------------- build


func _teardown() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	darkness = null
	lanterns.clear()
	occluders.clear()
	wall_runs.clear()
	emitters.clear()
	_free.clear()
	_shades.clear()
	_lanterns_node = null
	_occluders_node = null
	_shades_node = null
	_emitters_node = null


func _build_darkness() -> void:
	var grid := Rect2(Vector2.ZERO, Vector2(root.data.width, root.data.height) * float(Layers.TILE))
	var rect := grid.grow(FloorRoot.VOID_MARGIN)
	darkness = _flat_light("Darkness", rect, 0.0)
	darkness.blend_mode = Light2D.BLEND_MODE_MIX
	darkness.color = Color(0, 0, 0, 1)
	darkness.range_item_cull_mask = LIT_MASK
	add_child(darkness)


func _build_occluders() -> void:
	_occluders_node = Node2D.new()
	_occluders_node.name = "Occluders"
	add_child(_occluders_node)
	wall_runs = WallOccluders.runs_for(root.data, profile.occluder_inset_px)
	occluders = WallOccluders.build(root.data, profile.occluder_inset_px)
	for occluder: LightOccluder2D in occluders:
		occluder.occluder_light_mask = WALL_OCCLUDER_MASK
		_occluders_node.add_child(occluder)
	_occluders_node.visible = _shadows
	for prop: Prop in root.props:
		if not is_instance_valid(prop) or not prop.solid:
			continue
		var prop_occluder := prop.occluder()
		if prop_occluder != null:
			prop_occluder.occluder_light_mask = PROP_OCCLUDER_MASK


func _build_lanterns() -> void:
	_lanterns_node = Node2D.new()
	_lanterns_node.name = "Lanterns"
	add_child(_lanterns_node)
	var data := root.data
	var kind := profile.lantern_kind_for(data.biome)
	var column := LightingProfile.lantern_column(kind)
	var light := DungeonLight.resolve()
	var lit := 0
	for anchor: Vector2i in anchors_for(data):
		var facing := facing_of(data, anchor)
		var room := data.room_at(anchor + Vector2i(facing))
		var room_id := room.id if room != null else -1
		var tint := (
			root.material_for_room(room_id)
			if kind == &"crystal"
			else root.torch_material_for_room(room_id)
		)
		var lantern := WallLantern.new()
		var texture := _light_texture if lit < profile.lantern_max_lights else null
		lantern.setup(
			anchor,
			facing,
			kind,
			root.atlas,
			column,
			tint,
			texture,
			profile.lantern_texture_scale * light.torch_texture_scale / 1.45,
			profile.lantern_lip_px
		)
		if texture != null:
			lit += 1
		_lanterns_node.add_child(lantern)
		lanterns.append(lantern)


## The generator's anchors when it rolled any, else the same rule run here (a floor built by
## hand in a test, or restored from a save older than the field).
static func anchors_for(data: FloorData) -> Array[Vector2i]:
	if data == null:
		return []
	if not data.lantern_anchors.is_empty():
		return data.lantern_anchors
	var rng := RandomNumberGenerator.new()
	rng.seed = RunRng.hash_combine(data.seed_value, 977)
	var spacing := Biome.load_by_id(data.biome).lantern_spacing
	return LanternAnchors.place(data, spacing, rng)


## Unit direction from a wall anchor into the open ground it faces: a FLOOR or DOOR neighbour
## first (the room), else any walkable one (a corridor), else down.
static func facing_of(data: FloorData, anchor: Vector2i) -> Vector2:
	var fallback := Vector2i.ZERO
	for d: Vector2i in GenUtil.DIRS4:
		var q := anchor + d
		if not data.is_walkable(q.x, q.y):
			continue
		if data.get_tile(q.x, q.y) == FloorData.Tile.FLOOR:
			return Vector2(d)
		if fallback == Vector2i.ZERO:
			fallback = d
	return Vector2(fallback) if fallback != Vector2i.ZERO else Vector2.DOWN


func _build_shades() -> void:
	_shades_node = Node2D.new()
	_shades_node.name = "Shades"
	add_child(_shades_node)
	for room: RoomNode in root.rooms:
		if room.visited or room.data == null:
			continue
		_shades[room.id] = _make_shade(room)


## The shade over a room nobody has entered: a flat MIX-toward-black light the size of the
## room's ring over the environment and the bodies alike (never a tell), a touch and no more.
func _make_shade(room: RoomNode) -> PointLight2D:
	var ring := room.data.ring()
	var rect := Rect2(
		Vector2(ring.position) * float(Layers.TILE), Vector2(ring.size) * float(Layers.TILE)
	)
	var shade := _flat_light("Shade_%d" % room.id, rect, profile.unexplored_shade)
	shade.blend_mode = Light2D.BLEND_MODE_MIX
	shade.color = Color(0, 0, 0, 1)
	# Over the bodies too: a shade on the floor alone stood the floor off the props in it
	# (`prop_frame`, unexplored rooms), and a room nobody has entered is a touch darker whole.
	shade.range_item_cull_mask = LIT_MASK
	_shades_node.add_child(shade)
	return shade


## A light drawn as a flat white rectangle exactly over `rect`, environment mask only. For a
## point light the blend amount is the *texture's* alpha (the colour's alpha only scales its
## rgb, like energy), so a MIX shade of 22% is a 22%-alpha texture: with an opaque one the
## room went black.
func _flat_light(light_name: String, rect: Rect2, alpha: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.name = light_name
	light.texture = shade_texture(alpha)
	light.position = rect.get_center()
	light.scale = rect.size / float(SHADE_TEXTURE_SIZE)
	light.range_item_cull_mask = ENV_MASK
	light.shadow_enabled = false
	return light


## A flat white square at `alpha` (quantised to `SHADE_ALPHA_STEP`), shared: a fading shade
## walks through at most 1/step of them, and every floor reuses the same squares.
##
## Held in a static dictionary, not in the resource cache alone. `ResourceLoader.has_cached()`
## answered yes for a path whose last reference had just gone with the previous floor, and the
## `load()` behind it then handed back null - which the renderer reported as `Parameter "t" is
## null` and which left the darkness with no texture at all, i.e. a floor with the lighting
## layer built and no darkness on it.
static func shade_texture(alpha: float) -> Texture2D:
	var steps := int(roundf(clampf(alpha, 0.0, 1.0) / SHADE_ALPHA_STEP))
	var key := "%s_%d" % [SHADE_TEXTURE_KEY, steps]
	var held: Variant = _shade_textures.get(key)
	if held is Texture2D:
		return held as Texture2D
	var img := Image.create(SHADE_TEXTURE_SIZE, SHADE_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, float(steps) * SHADE_ALPHA_STEP))
	var tex := ImageTexture.create_from_image(img)
	tex.take_over_path(key)
	_shade_textures[key] = tex
	return tex


## Sets a shade light's strength (its texture alpha).
static func set_shade_strength(light: PointLight2D, alpha: float) -> void:
	if light != null and is_instance_valid(light):
		light.texture = shade_texture(alpha)


static func _corners(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y)
		]
	)


func _build_fixtures() -> void:
	_emitters_node = Node2D.new()
	_emitters_node.name = "Emitters"
	add_child(_emitters_node)
	if root.stairs != null:
		acquire_emitter(&"stairs", root.stairs, root.stairs.global_position)
	for node: Node in root.get_altars():
		if node is Node2D:
			acquire_emitter(&"altar", node as Node2D, (node as Node2D).global_position)
	for node: Node in root.get_shrines():
		if node is Node2D:
			acquire_emitter(&"shrine", node as Node2D, (node as Node2D).global_position)


## Moves every door torch's light onto the wall's lip, the way the lanterns hang, so it is
## not inside the wall's occluder core.
func _place_torch_lights() -> void:
	for light: PointLight2D in root.torch_lights():
		if not is_instance_valid(light):
			continue
		var torch := light.get_parent() as Node2D
		if torch == null:
			continue
		var tile := FloorRoot.tile_of(torch.position)
		var facing := facing_of(root.data, tile)
		light.position = facing * profile.lantern_lip_px + Vector2(0, -2)


func _prewarm() -> void:
	while emitters.size() < mini(profile.emitter_prewarm, profile.emitter_max):
		_free.append(_make_emitter())


func _make_emitter() -> LightEmitter:
	var e := LightEmitter.new()
	e.texture = _light_texture
	e.range_item_cull_mask = ENV_MASK
	e.name = "Emitter_%d" % emitters.size()
	_emitters_node.add_child(e)
	emitters.append(e)
	return e


# ---------------------------------------------------------------- per frame


## The dark, applied once: how far every surface on the floor is mixed toward black where
## nothing is lighting it. It carries no tint of its own - a MIX toward black cannot - and it
## does not move, because there is no lever left to move it with.
func _apply_dark() -> void:
	if darkness == null:
		return
	_darkness_strength = clampf(1.0 - _unlit, 0.0, 1.0)
	set_shade_strength(darkness, _darkness_strength)
	# ...and the surround, which the dark cannot reach because it is a `Light2D` and the surround
	# is a shader on a `Polygon2D` (`FloorRoot.set_surround_dark`).
	if root != null and is_instance_valid(root):
		root.set_surround_dark(_unlit)


## How far the environment, and the bodies standing in it, are mixed toward black (0 when off).
func darkness_strength() -> float:
	return _darkness_strength if active() else 0.0


func _apply_casters() -> void:
	if not active():
		return
	var cap := profile.shadow_casters if _shadows else 0
	var i := 0
	var player_light := _player_light()
	for light: Light2D in shadow_candidates(_view_centre()):
		var on := i < cap
		var mask := WALL_OCCLUDER_MASK
		# Props shadow from the player's own light only: a lantern's pool shadowed by the
		# crate beside it left that crate's floor dark while the body light lit the crate, and
		# the prop's contrast against its own floor fell (`prop_frame`, the corner tile).
		if light == player_light and i < profile.prop_shadow_casters:
			mask |= PROP_OCCLUDER_MASK
		if light.shadow_enabled != on or light.shadow_item_cull_mask != mask:
			light.shadow_enabled = on
			light.shadow_item_cull_mask = mask
			light.shadow_color = Color(0, 0, 0, profile.shadow_alpha)
			light.shadow_filter = Light2D.SHADOW_FILTER_PCF13
			light.shadow_filter_smooth = profile.shadow_smooth
		i += 1


func _poll_visits() -> void:
	# A restored floor marks its rooms visited after the build; a room the shade still stands
	# over that is now visited (however that happened) loses it.
	for id: Variant in _shades.keys():
		var room := root.get_room(int(id))
		if room != null and room.visited:
			_uncover(int(id))


func _view_centre() -> Vector2:
	if is_inside_tree():
		var cam := get_viewport().get_camera_2d()
		if cam != null:
			return cam.get_screen_center_position()
	var player := _player()
	return player.global_position if player != null else global_position


func _player() -> Node2D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"player") as Node2D


## The player's own light: the glow of the motes they carry (`EntitySparks`), or the scene's own
## node on a floor whose rig never got to attach any.
func _player_light() -> Light2D:
	var player := _player()
	if player == null:
		return null
	var sparks := player.get_node_or_null(NodePath(EntitySparks.NODE_NAME)) as EntitySparks
	if sparks != null and sparks.light != null:
		return sparks.light
	return player.get_node_or_null(^"Light") as Light2D


func _uncover(room_id: int) -> void:
	if not _shades.has(room_id):
		return
	var shade := _shades[room_id] as PointLight2D
	_shades.erase(room_id)
	if shade == null or not is_instance_valid(shade):
		return
	var tween := shade.create_tween()
	var fade := func(alpha: float) -> void: set_shade_strength(shade, alpha)
	tween.tween_method(fade, profile.unexplored_shade, 0.0, profile.shade_fade_seconds)
	tween.tween_callback(shade.queue_free)


# ---------------------------------------------------------------- blobs


func _blob_everyone() -> void:
	var player := _player()
	if player != null:
		add_blob(player)
	if is_inside_tree():
		for enemy: Node in get_tree().get_nodes_in_group(&"enemy"):
			if enemy is Node2D:
				add_blob(enemy as Node2D)
				add_sparks(enemy as Node2D)


## Lays a soft shadow blob under `body` (once). The blob is the first child so every sprite
## draws over it.
func add_blob(body: Node2D) -> Sprite2D:
	if body == null or not is_instance_valid(body) or not active():
		return null
	var existing := body.get_node_or_null(BLOB_NAME) as Sprite2D
	if existing != null:
		return existing
	unshade_tells(body)
	var blob := Sprite2D.new()
	blob.name = BLOB_NAME
	blob.texture = blob_texture()
	blob.scale = profile.blob_size / Vector2(8.0, 4.0)
	blob.position = Vector2(0, 5)
	blob.light_mask = 0
	var pal := root.lit_palette() if root != null else null
	blob.modulate = Color(
		0, 0, 0, profile.blob_alpha * (0.6 if pal != null and pal.is_light else 1.0)
	)
	blob.add_to_group(BLOB_NAME)
	body.add_child(blob)
	body.move_child(blob, 0)
	return blob


## An unshaded material, for a caller that wants one; note that in the compatibility renderer
## a CanvasModulate reaches unshaded items too, which is why the darkness here is a light and
## exemption is a `light_mask` (`TELL_MASK`), not a material.
static func unshaded_material() -> CanvasItemMaterial:
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unshaded


## Puts every tell under `body` (by node name, `TELL_NAMES`, and every CanvasItem under each)
## on `TELL_MASK`, out of reach of every light and of the darkness. Idempotent.
static func unshade_tells(body: Node) -> int:
	if body == null or not is_instance_valid(body):
		return 0
	var n := 0
	for child: Node in body.get_children():
		if not TELL_NAMES.has(String(child.name)):
			continue
		n += _mask_tree(child, TELL_MASK)
	return n


static func _mask_tree(node: Node, mask: int) -> int:
	var n := 0
	if node is CanvasItem:
		(node as CanvasItem).light_mask = mask
		n += 1
	for child: Node in node.get_children():
		n += _mask_tree(child, mask)
	return n


## Hangs the motes a living thing carries on `body` (once), and the glow they give. The player
## carries the `player` row of the emitter table; an enemy carries `enemy_spark_*`, brighter once
## it has noticed you and brighter again if it is an elite or a boss - a light that is also a
## tell, which is what a glow arriving out of the dark before its owner does is.
func add_sparks(body: Node2D) -> EntitySparks:
	if body == null or not is_instance_valid(body) or not active():
		return null
	var existing := body.get_node_or_null(NodePath(EntitySparks.NODE_NAME)) as EntitySparks
	if existing != null:
		return existing
	var sparks := EntitySparks.new()
	var is_player := body == _player()
	var role := _player_role(body) if is_player else _enemy_role(body)
	var energy := player_light_energy() if is_player else _enemy_spark_energy(body)
	var radius := player_light_reach() if is_player else profile.enemy_spark_radius
	var motes := profile.player_motes if is_player else profile.enemy_motes
	var paleness := profile.player_glow_paleness if is_player else profile.enemy_glow_paleness
	sparks.setup(
		_light_texture,
		light_color_for(role),
		energy,
		radius,
		motes,
		profile.spark_spread_px,
		LIT_MASK,
		paleness
	)
	sparks.apply_accessibility(Accessibility.reduce_motion(), profile.reduced_motion_motes)
	body.add_child(sparks)
	return sparks


## The palette role an enemy's motes burn in: its faction's, so a clown, a greybeard and a
## tinkerer are three different glows coming at you.
static func _enemy_role(body: Node2D) -> StringName:
	var def: Variant = body.get(&"def")
	if def is EnemyDef:
		return EntitySparks.role_for_faction(int((def as EnemyDef).faction))
	return &"danger"


## What an enemy's motes burn at: fainter than the player's, lifted once it is awake and lifted
## again for an elite or a boss.
func _enemy_spark_energy(body: Node2D) -> float:
	var energy := profile.enemy_spark_energy
	var def: Variant = body.get(&"def")
	if def is EnemyDef:
		if (def as EnemyDef).is_boss:
			energy *= profile.boss_spark_scale
		elif (def as EnemyDef).is_elite:
			energy *= profile.elite_spark_scale
	if body.has_method(&"is_asleep") and not bool(body.call(&"is_asleep")):
		energy *= profile.enemy_alert_scale
	return energy * mood_energy()


## Re-reads every body's motes: their colour follows the theme and the mood, their energy follows
## whether the thing has noticed you, and their count follows the accessibility policy.
func relight_sparks() -> void:
	if not is_inside_tree():
		return
	var reduced := Accessibility.reduce_motion()
	var player := _player()
	for node: Node in get_tree().get_nodes_in_group(EntitySparks.GROUP):
		var sparks := node as EntitySparks
		if sparks == null or not is_instance_valid(sparks):
			continue
		var body := sparks.get_parent() as Node2D
		if body == null:
			continue
		if body == player:
			sparks.relight(
				light_color_for(_player_role(body)), player_light_energy(), player_light_reach()
			)
		else:
			sparks.relight(
				light_color_for(_enemy_role(body)),
				_enemy_spark_energy(body),
				profile.enemy_spark_radius
			)
		sparks.apply_accessibility(reduced, profile.reduced_motion_motes)


## Whether `body` carries a blob.
static func has_blob(body: Node) -> bool:
	return body != null and body.get_node_or_null(BLOB_NAME) != null


## A 16x8 soft ellipse, white, shared through the resource cache.
static func blob_texture() -> Texture2D:
	if ResourceLoader.has_cached(BLOB_TEXTURE_KEY):
		return ResourceLoader.load(BLOB_TEXTURE_KEY) as Texture2D
	var w := 16
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var u := (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(h) * 2.0 - 1.0
			var d := u * u + v * v
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var tex := ImageTexture.create_from_image(img)
	tex.take_over_path(BLOB_TEXTURE_KEY)
	return tex


# ---------------------------------------------------------------- signals


func _on_palette_changed(_palette: ThemePalette) -> void:
	relight()


func _on_room_entered(room_id: int) -> void:
	_uncover(room_id)


## Clearing a room lifts the shade off it and nothing else. It used to earn an additive
## `cleared_lift` over the whole room as well - a flat light the size of the room with nothing
## in the room casting it, which is exactly the thing the owner's ruling is about. A cleared
## room is now lit by the same lanterns it was lit by while the fight was on.
func _on_room_cleared(room_id: int) -> void:
	_uncover(room_id)


func _on_settings_changed(key: String) -> void:
	if key != LightingProfile.SETTING_QUALITY and key != LightingProfile.SETTING_SHADOWS:
		return
	if root != null and is_instance_valid(root) and root.data != null:
		build(root, profile)


func _on_enemy_spawned(enemy: Node2D) -> void:
	if enemy == null or not is_instance_valid(enemy) or not active():
		return
	add_blob(enemy)
	add_sparks(enemy)
	mask_body(enemy)
	if Stairs.is_boss_enemy(enemy) and enemy.get_node_or_null("Occluder") == null:
		var occluder := LightOccluder2D.new()
		occluder.name = "Occluder"
		occluder.occluder_light_mask = PROP_OCCLUDER_MASK
		var polygon := OccluderPolygon2D.new()
		polygon.closed = true
		polygon.polygon = _corners(Rect2(Vector2(-6, 0), Vector2(12, 4)))
		occluder.occluder = polygon
		enemy.add_child(occluder)


func _connect(sig: Signal, target: Callable) -> void:
	if not sig.is_connected(target):
		sig.connect(target)


func _disconnect_all(sig: Signal) -> void:
	for handler: Callable in [
		_on_palette_changed,
		_on_room_entered,
		_on_room_cleared,
		_on_settings_changed,
		_on_enemy_spawned
	]:
		if sig.is_connected(handler):
			sig.disconnect(handler)
