## Rendered check for pickup readability: every kind of drop the game can leave on the floor,
## measured on a *drawn frame* against the pixels it is actually covering. Runs as its own main
## scene inside the nested headless sway harness (never on the real session):
##
##   tools/capture-scene.sh pickup_frame [theme-fixture]
##
## **Why it exists.** The world contrast guard was added for gold, hearts and stat orbs, and it
## fixed all three at once because all three are `PickupBase` and the fix went in the base. The
## fourth kind - the item drop an elite leaves - is an `Interactable`, not a `PickupBase`, so it
## was not on that path and went on reading the unguarded role. It stayed invisible on a light
## floor next to a coin that had just been fixed, and nothing in the tree noticed, because every
## check that existed was written against the list of roles the fix had moved rather than
## against the set of things the game draws. This capture is written the other way round: it
## enumerates the *nodes*, draws each of them on each surface the dungeon paints, and reads the
## answer off the frame - so the next kind that is added, or the next one that is forgotten,
## fails here instead of shipping.
##
## **What it found on its first run.** Every pickup was painted from `Desktop.palette` while the
## room around it was painted from `FloorRoot.lit_palette()` - the same theme exposed into the
## dungeon's light band - and nothing had ever compared the two, because every check measured a
## palette against itself. On tokyo-night the drawn wall cap is `707bae` where the theme authors
## `565f89`, and five kind/surface pairs measured between 2.08:1 and 2.98:1 on a frame while the
## whole unit suite was green. The fix is in `PickupBase.world_palette_for()`: a drop reads the
## palette of the floor it is lying on.
##
## **How a reading is taken.** The floor is built and settled twice: once empty, once with the
## drops in it. A pixel that changed between the two frames is a pixel this drop painted, and
## the *first* frame says what was underneath it. There is no colour matching and no guessing:
## the pair (what is drawn, what it covered) comes straight out of the two images. Which surface
## a covered pixel belongs to is read off the tile art - the atlas cell the tile is drawn from,
## and the ramp index of that pixel inside it - exactly the way `prop_frame_capture` does it.
## Asking a pixel's *colour* which surface it is would be circular (two surfaces one rung apart
## are meant to be close) and would break the moment a room variant shifted the ramp; the art
## knows regardless. A floor cell therefore measures against `floor` and `floor_alt` at once,
## which is what the player sees.
##
## A drop passes on a surface when *some* substantial part of it reads at
## `ThemePalette.WORLD_MIN_CONTRAST` against that surface. Substantial is `MIN_RUN` pixels of
## one colour: a drop is a shape, not a pixel, and an antialiased edge is not a reading. The
## shadow every drop paints under itself cannot fake a pass - a 30% black wash over a surface
## tops out near 2:1 against that same surface, whatever the surface is - and neither can the
## stat orb's glow, which is its own body colour at a quarter alpha and so can only ever read
## worse than the body it surrounds.
##
## **A floor placement measures three surfaces, not one.** Every floor cell in the atlas is
## painted out of three rungs and not one: measured on the crypt sheet a plain cell is 139 px of
## the floor rung, 53 px of floor detail and 64 px of the wall rung, which is the dark speckle.
## So a drop standing on an ordinary floor tile is already lying across `floor`, `floor_alt` and
## `wall`, and the readings are filed per surface rather than per drop. Wall faces carry the wall
## and wall-cap rungs the same way. That is why four placements cover five surfaces.
##
## **Outline and accent pixels are reported, not required.** The guard is defined over
## `ThemePalette.WORLD_SURFACES`, the five surfaces the room is built out of. A 1px art outline
## inside a tile is a line, not a surface a drop lands on, and no colour clears both it and the
## floor it borders on a light theme. They are printed so the frame is never silently narrowed.
##
## The four rarities an item can drop at rotate across the item column's placements, so each of
## them is drawn and read somewhere in the frame. The full rarity-by-surface matrix is the colour
## model's to answer and `PickupWorldRolesTest` answers it on all six fixtures; what the frame is
## here to prove is that the node is painted from that model at all.
##
## One biome, six themes. The biome narrows the palette and `PickupWorldRolesTest` /
## `PickupWorldContrastTest` already hold the guard across `derive_environment`; what only a
## frame can answer is whether the node on screen is painted from the guarded colour at all, and
## that does not change per prop sheet. It fails (exit 2) rather than merely reporting.
class_name PickupFrameCapture
extends Node

const VIEW_SIZE := Vector2i(480, 270)
## Where the floor is pinned inside the viewport, in pixels.
const FLOOR_ORIGIN := Vector2i(64, 6)
## Biome the frame is built in. See the class comment for why one is enough.
const BIOME := &"crypt"
## Fixture grid. 22x16 tiles is 352x256 px, which fits the 480x270 view with the origin above.
const GRID := Vector2i(22, 16)
## The single room: floor inside, a ring of wall faces around it, and a second ring outside that
## which every tile of is a *deep* wall, so the frame carries wall caps as well as wall faces.
const ROOM := Rect2i(3, 3, 16, 9)
## Fixture seed. Only picks which of the four floor variants each cell is drawn from; all four
## carry the same three rungs, so nothing about the coverage depends on it.
const SEED_VALUE := 20250913
## Tiles between two kinds' columns. Wider than the box a reading is taken in, so one kind's
## pixels can never be read into another's.
const KIND_STRIDE := 3
## Where in its tile a drop is put down, so the body it draws above itself lands in the middle
## of that tile rather than in the one above.
const TILE_ANCHOR := Vector2(8.0, 13.0)
## Box around a drop the diff is taken in: wide enough for the widest kind (the stat orb's glow
## is 1.8 radii) with room for the shadow below and the bob above.
const BOX_MIN := Vector2i(-13, -18)
const BOX_MAX := Vector2i(13, 10)
## Longest the capture waits for a frame to stop changing, and the gap between the two readings
## it compares (see `_settle`).
const SETTLE_DEADLINE := 8.0
const SETTLE_STEP := 0.15
## Slack on a ratio read back out of an 8-bit PNG. One code point at the dark end of the sRGB
## curve moves a contrast ratio by more than a rounding error does.
const EPSILON := 0.05
## Pixels of one drawn colour before the frame is asked about it: fewer than this is an edge,
## not a reading.
const MIN_RUN := 4
## Alpha of the drop-shadow every kind paints under itself, and how far a drawn pixel may sit
## from the composite of that shadow and still be recognised as one (see `_is_own_shadow`).
##
## Matched per *pixel* rather than against the surface's modal colour (see `_measure`). A tile
## carries a grout line, a speckle and a highlight dot as well as its body, so a shadow lying
## across the darker half of a wall tile misses the modal composite by three or four values and
## was read as the drop having painted a dark pixel. That did not matter while loot was exempt
## from the lighting layer, because the drop's own bright body always won the best-ratio search;
## loot takes the dark like every other body now (`LightRig.loot_mask`), so a shadow that escapes
## the test is a shadow's ratio against its own surface, reported as the drop's.
const SHADOW_ALPHA := 0.3
const SHADOW_EPSILON := 2.0 / 255.0
## Pixels of one surface a kind has to cover, added up over its placements, before the pair
## counts as measured. Below it the drop is clipping the corner of a neighbouring tile, which is
## not a placement.
const MIN_SURFACE := 12
## Ramp index -> the surface role that rung paints. 1 is the art outline and 6/7 are the accent
## rungs; both are reported and neither is required (see the class comment).
const RUNG_SURFACES: Dictionary = {2: &"wall", 3: &"floor", 4: &"floor_alt", 5: &"wall_top"}
## The surround, which is painted by the void backdrop rather than by any tile.
const VOID_SURFACE := &"void"
## Every kind of drop the game can leave lying in a room, in the order they are drawn across the
## frame. `gold`, `heart` and `stat_orb` are `PickupBase`; `item` is the `ItemPickup` an elite
## leaves, which is the one this check was written for.
const KINDS: PackedStringArray = ["gold", "heart", "stat_orb", "item"]
## Surfaces every kind has to be measured against. Only `wall_top` and `void` need a placement
## of their own; the other three all live inside a floor or wall cell's art (see the class
## comment).
const REQUIRED_SURFACES: PackedStringArray = ["floor", "floor_alt", "wall", "wall_top", "void"]

var _data: FloorData
var _atlas: Image
## kind -> surface -> {"drawn": {html -> px}, "under": {html -> px}}: every pixel a kind painted
## on that surface and every pixel it covered, added up over all of that kind's placements.
var _pixels: Dictionary = {}
var _failures: PackedStringArray = []


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var view := SubViewport.new()
	view.size = VIEW_SIZE
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(view)
	_data = _floor_data()
	var root := FloorRoot.new()
	root.position = Vector2(FLOOR_ORIGIN)
	view.add_child(root)
	root.build_with_biome(_data, Biome.load_by_id(BIOME), null, null)
	_atlas = Image.load_from_file(FloorBuilder.atlas_path_for(BIOME))
	# The light goes in before the *empty* frame, not after it: the reading is a drop against the
	# surface it covered, and a surface photographed unlit against a drop photographed lit is a
	# comparison between two different rooms.
	_light_every_drop(root)
	var empty := await _settle(view, root)
	var drops := await _place_drops(root)
	var filled := await _settle(view, root)
	var path := ProjectSettings.globalize_path(_out_path())
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := filled.save_png(path)
	print("pickup frame -> %s (%s)" % [path, error_string(saved)])
	# The two frames have to be two frames. `Viewport.get_texture().get_image()` hands back the
	# render target's own image, so holding the first one across the second capture gives the
	# second frame twice and every reading comes out as "nothing changed" - which from the
	# outside is indistinguishable from a check that passed. `_settle` duplicates on the way out
	# for that reason; this says so out loud rather than trusting it.
	if empty.get_data() == filled.get_data():
		print("FAIL the drops did not change the frame - the two captures are the same image")
		QuitGuard.request(get_tree(), 2)
		return
	for entry: Dictionary in drops:
		print(
			(
				"placed %-9s at tile %s chose %s halo %s"
				% [
					entry["kind"],
					entry["tile"],
					(entry["chose"] as Color).to_html(false),
					(entry["halo"] as Color).to_html(true),
				]
			)
		)
		_measure(entry, empty, filled)
	var ok := _report()
	QuitGuard.request(get_tree(), 0 if ok and saved == OK else 2)


## The fixture: one room big enough to hold four drops on each surface, walled twice over.
##
## The second wall band is what puts wall *caps* in the frame. A wall tile shows a cap only when
## nothing walkable touches it (`FloorBuilder.is_deep_wall`), so a single ring around a room is
## all faces and a check built on one would never measure `wall_top` - which on a dark theme is
## the brightest surface in the room and the one the drop colours come closest to.
func _floor_data() -> FloorData:
	var d := FloorData.new()
	d.seed_value = SEED_VALUE
	d.floor_index = 0
	d.biome = BIOME
	d.width = GRID.x
	d.height = GRID.y
	d.tiles.resize(d.width * d.height)
	d.tiles.fill(FloorData.Tile.VOID)
	RoomsTestFixtures.add_room(d, 0, FloorData.RoomType.START, ROOM)
	var outer := ROOM.grow(2)
	for y in range(outer.position.y, outer.end.y):
		for x in range(outer.position.x, outer.end.x):
			if d.get_tile(x, y) == FloorData.Tile.VOID:
				d.set_tile(x, y, FloorData.Tile.WALL)
	d.start_room = 0
	d.stairs_room = -1
	d.boss_room = -1
	return d


## Puts one drop of every kind on every placement and freezes them.
##
## Frozen because both families animate for ever - a coin bobs, an orb pulses, an item drop
## hovers - and `_settle` waits for two identical frames, which an animation never produces.
## Homing is in the same `_physics_process`, so stopping it also stops four drops from
## converging on each other.
##
## Stopping the clock is not enough to pin the *phase*, and this check spent its whole life
## believing it was. `PickupBase._bob_phase` is `randf() * TAU`, rolled per drop in `_ready`, so
## a frozen coin sits at `sin(_bob_phase)` - anywhere in a one-pixel band, different on every
## run - and `_age` is a frame old by the time processing is switched off. One pixel is not
## nothing here: a reading is taken per surface from the tile art under each drawn pixel, and a
## drop that sits a pixel higher puts a different share of its rim on the wall speckle. Measured
## on catppuccin-latte, `gold on wall` read 4.31:1 on one run and 2.42:1 on the next with no
## change to the tree in between - the same disease as the flickering torches in
## `prop_frame_capture`, and pinned here the same way. The phase the colour model is written
## against is `_age` 0 with no phase offset, which is bob 0 and the orb's glow at its base
## alpha, so that is what every drop is set to before the frame is taken.
func _place_drops(root: FloorRoot) -> Array[Dictionary]:
	var container := Node2D.new()
	container.name = "Drops"
	root.add_child(container)
	var registry := ItemRegistry.load_default()
	var out: Array[Dictionary] = []
	var placements := _placements()
	for k in range(KINDS.size()):
		var kind := StringName(KINDS[k])
		for p in range(placements.size()):
			var tile: Vector2i = placements[p][k]
			var pos := Vector2(tile * Layers.TILE) + TILE_ANCHOR
			var node := _make_drop(kind, container, registry, pos, k * placements.size() + p)
			if node == null:
				continue
			out.append({"kind": kind, "node": node, "at": pos, "tile": tile})
	await get_tree().process_frame
	for entry: Dictionary in out:
		var node: Node2D = entry["node"]
		node.set_physics_process(false)
		node.set_process(false)
		node.scale = Vector2.ONE
		_pin_phase(node)
		entry["chose"] = _chosen_color(node)
		entry["halo"] = _chosen_halo(node)
	return out


## Puts one frozen drop at the phase the colour model is written against: age 0, no bob offset.
## Both families draw from `_age`, and `PickupBase` adds a per-instance random `_bob_phase`, so
## neither is at a known phase merely because its processing has been switched off.
static func _pin_phase(node: Node2D) -> void:
	node.set("_age", 0.0)
	if node is PickupBase:
		node.set("_bob_phase", 0.0)
	node.queue_redraw()


## The colour a drop picked for itself, straight off the node. Printed beside the reading so the
## frame says which colour the model handed out as well as how it measured: a kind that is
## suddenly painted in its plain role again shows up here before it shows up as a ratio.
static func _chosen_color(node: Node2D) -> Color:
	var pickup := node as PickupBase
	if pickup != null:
		return pickup.color
	var drop := node as ItemPickup
	return drop.draw_color() if drop != null else Color.MAGENTA


## The rim the drop solved for itself (`LootInk`), or a transparent colour when it needs none.
## Printed for the same reason the ink is: a drop that has quietly lost its halo on one theme
## shows up here rather than only as a ratio nobody can explain.
static func _chosen_halo(node: Node2D) -> Color:
	var pickup := node as PickupBase
	if pickup != null:
		return pickup.halo
	var drop := node as ItemPickup
	return drop.draw_halo() if drop != null else Color.TRANSPARENT


## One drop of `kind` under `parent`, already in the tree. `index` varies the item a drop
## carries so the four item placements are not all the same rarity.
func _make_drop(
	kind: StringName, parent: Node2D, registry: ItemRegistry, pos: Vector2, index: int
) -> Node2D:
	if kind == &"item":
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED_VALUE + index
		var rarity := index % ItemInstance.RARITY_NAMES.size()
		var item := ItemGenerator.generate(registry, 4, rng, 0.0, [ItemBase.Slot.WEAPON], rarity)
		var drop := ItemPickup.drop(parent, item, pos, null, false)
		# `ItemPickup.drop` takes a *global* position, and every other placement here is local
		# to the floor root. Restated so one kind is not offset from the rest by the origin.
		drop.position = pos
		return drop
	var pickup := PickupSpawner.make(kind)
	if pickup == null:
		push_error("pickup frame: no class for kind %s" % kind)
		return null
	pickup.settle_time = 9999.0
	parent.add_child(pickup)
	pickup.position = pos
	return pickup


## Seven tiles per kind, as `[placement][kind]`: four rows of floor, a wall face, a wall cap and
## the surround outside the bands.
##
## Only `wall_top` and `void` need a placement of their own. `floor`, `floor_alt` and `wall` are
## all painted inside an ordinary floor cell (see the class comment), so a drop standing on one
## is lying across all three and is measured against all three.
##
## **Four floor rows and not one**, because the smallest kind is the one the coverage has to
## carry. A coin is five pixels across, and the rungs it has to be measured against are a
## quarter and a fifth of the cell it stands on - so one placement puts two or three body pixels
## on the floor-detail rung, which is under `MIN_RUN` and reads as "never measured" rather than
## as a reading. Four rows is the sampling that makes the smallest sprite answerable on the
## thinnest rung; the numbers do not change with it, only whether there are enough of them.
##
## The columns are three tiles apart and the rows two, both wider than the box a reading is
## taken in, so no two drops can be read into each other.
func _placements() -> Array:
	var rows: Array[int] = [
		ROOM.position.y + 1,
		ROOM.position.y + 3,
		ROOM.position.y + 5,
		ROOM.position.y + 7,
		ROOM.end.y,
		ROOM.end.y + 1,
		GRID.y - 1,
	]
	var out: Array = []
	for row: int in rows:
		var tiles: Array[Vector2i] = []
		for k in range(KINDS.size()):
			tiles.append(Vector2i(ROOM.position.x + 1 + k * KIND_STRIDE, row))
		out.append(tiles)
	return out


## Waits until the viewport has drawn the same frame twice, and returns it. Same rule and same
## reason as `prop_frame_capture`: the tile and prop materials crossfade into the live palette
## when the palette arrives, so a fixed settle shoots whatever phase that happened to be in.
## The torches are doused on every pass, because the flicker never stops on its own (see
## `_douse_torches`).
func _settle(view: SubViewport, root: FloorRoot) -> Image:
	var previous := PackedByteArray()
	var image: Image = null
	var waited := 0.0
	while waited < SETTLE_DEADLINE:
		await get_tree().create_timer(SETTLE_STEP).timeout
		_douse_torches(root)
		await RenderingServer.frame_post_draw
		# Duplicated on the way out: the frame this returns has to stay the frame it was when
		# it was taken, and the caller holds two of them at once to diff against each other.
		image = (view.get_texture().get_image() as Image).duplicate(true) as Image
		var data := image.get_data()
		if not previous.is_empty() and data == previous:
			return image
		previous = data
		waited += SETTLE_STEP
	push_error("pickup frame: the frame never settled in %.1f s" % SETTLE_DEADLINE)
	return image


## Takes the room's own torches out of the frame, and keeps them out on every pass.
##
## Not a convenience and not a way to make a number nicer. The guarantee is made about the room's
## five surfaces against the drop lying on them, and a door torch is an *additive* light that
## happens to reach some of the placements and not others - a reading that changed with how close
## the fixture's grid landed to a doorway would be a reading about the fixture. The light that
## *does* belong in the measurement is put there deliberately instead (`_light_every_drop`), one
## pool per drop, so every kind is read on every surface at the same exposure.
##
## It is also what makes the frame settle: the flicker swings every torch 14% at 2.3 Hz and
## never stops on its own, so a check that waits for two identical frames has to pin them
## somewhere, and zero is the only place that does not change with the theme's exposure.
static func _douse_torches(root: FloorRoot) -> void:
	root.set_process(false)
	for light: PointLight2D in root.torch_lights():
		if is_instance_valid(light):
			light.energy = 0.0


## Lights the whole fixture, evenly, at the energy a pool gives at its centre.
##
## Since the dungeon went dark (`LightingProfile.unlit_floor`), unlit ground keeps a twentieth of
## itself, and on a light theme so does the drop lying on it (`LightRig.loot_mask` puts loot with
## the surface there). Two near-blacks have no contrast to measure and nobody can see either of
## them, so a frame with no light in it measures nothing: on catppuccin-latte and white every kind
## on every surface came back between 1.02 and 1.44 against a 3.0 line, with the art unchanged.
##
## One **flat** light over the whole grid at `LightingProfile.lantern_energy` - the dark exactly
## undone - in the colour the theme's own fire burns. Not a pool per drop, which was tried: a
## pool's falloff varies by a third across a sixteen-pixel drop, so every pixel of the drop drew a
## slightly different colour, no colour reached `MIN_RUN` pixels and the reading came back empty
## on every kind. A flat light is the same amount of light a pool puts at its centre, everywhere,
## so every kind is read on every surface at the one exposure a player can judge a drop at: with
## a light on it.
func _light_every_drop(root: FloorRoot) -> void:
	var grid := Rect2(Vector2.ZERO, Vector2(_data.width, _data.height) * float(Layers.TILE)).grow(
		float(Layers.TILE) * 2.0
	)
	var light := PointLight2D.new()
	light.name = "FixtureLight"
	light.texture = LightRig.shade_texture(1.0)
	light.position = grid.get_center()
	light.scale = grid.size / float(LightRig.SHADE_TEXTURE_SIZE)
	light.energy = LightingProfile.resolve().lantern_energy
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.range_item_cull_mask = LightRig.LIT_MASK
	light.shadow_enabled = false
	# Half way to white: the theme's fire, paled. A fully saturated flame decides part of the
	# answer - on catppuccin-latte, whose loot is dark ink on paper, a warm light crushed the
	# gold's blue channel to #04 and its reading against a wall cap came out at 2.95 against a
	# 3.0 line with the art unchanged. The question this frame asks is the palette's, and the
	# flame's own tint is asked about where it belongs, in `prop_frame`, which normalises every
	# reading against what the light can give.
	var flame := DungeonLight.resolve().light_color(root.lit_palette().get_color(&"heat"))
	light.color = flame.lerp(Color.WHITE, 0.5)
	root.add_child(light)


## Files one drop's pixels: every pixel it painted, and the pixel it covered, under the surface
## that pixel belongs to. Counted rather than judged here - a kind's reading on a surface is the
## sum of what all of its placements landed on, which is what makes a thin rung like the floor
## detail inside a floor cell add up to a measurement instead of a handful of pixels.
func _measure(entry: Dictionary, empty: Image, filled: Image) -> void:
	var kind: StringName = entry["kind"]
	var at: Vector2 = entry["at"]
	var origin := FLOOR_ORIGIN + Vector2i(at.round())
	var per_kind: Dictionary = _pixels.get(kind, {})
	for dy in range(BOX_MIN.y, BOX_MAX.y):
		for dx in range(BOX_MIN.x, BOX_MAX.x):
			var px := origin + Vector2i(dx, dy)
			if px.x < 0 or px.y < 0 or px.x >= VIEW_SIZE.x or px.y >= VIEW_SIZE.y:
				continue
			var under := empty.get_pixel(px.x, px.y).to_html(false)
			var drawn := filled.get_pixel(px.x, px.y).to_html(false)
			if drawn == under:
				continue
			# The drop's own shadow, against the pixel it actually fell on rather than against
			# the surface's modal colour: exact, so a body colour that happens to be dark is
			# never mistaken for one and a shadow over a tile's darker half is never missed.
			if _is_own_shadow(Color(drawn), Color(under)):
				continue
			var surface := _surface_at(px)
			var cell: Dictionary = per_kind.get(surface, {"drawn": {}, "under": {}})
			var drawn_counts: Dictionary = cell["drawn"]
			var under_counts: Dictionary = cell["under"]
			drawn_counts[drawn] = int(drawn_counts.get(drawn, 0)) + 1
			under_counts[under] = int(under_counts.get(under, 0)) + 1
			per_kind[surface] = cell
	_pixels[kind] = per_kind


## The reading for one kind on one surface: the best ratio any substantial colour it painted
## reaches against that surface as the frame draws it.
##
## The surface is its modal covered pixel rather than its palette colour, because the torches
## put a gradient across the room and the pixel a drop is actually sitting on is the one the
## question is about. The drop is its own modal colours rather than one of them, because a drop
## is a shape: body, highlight and shadow are all drawn, and it is visible when a substantial
## part of it reads. `MIN_RUN` is what "substantial" means, and it is why an antialiased edge
## cannot answer for the whole.
static func _reading(cell: Dictionary) -> Dictionary:
	var under_counts: Dictionary = cell["under"]
	var drawn_counts: Dictionary = cell["drawn"]
	var reference := Color(_modal(under_counts))
	var best := 0.0
	var best_colour := reference
	for key: String in drawn_counts:
		if int(drawn_counts[key]) < MIN_RUN:
			continue
		var drawn := Color(key)
		if _is_own_shadow(drawn, reference):
			continue
		var ratio := ThemePalette.contrast_ratio(drawn, reference)
		if ratio > best:
			best = ratio
			best_colour = drawn
	return {
		"ratio": best,
		"drawn": best_colour,
		"under": reference,
		"covered": _total(under_counts),
	}


## True when a drawn pixel is the drop's own drop-shadow rather than any part of the drop.
##
## Every kind paints `Color(0, 0, 0, SHADOW_ALPHA)` under itself before it paints anything else,
## which composites to exactly `surface * (1 - SHADOW_ALPHA)`. It is a pixel the drop changed, so
## the diff picks it up, and on the sparser rungs it can be the only run of the drop's that
## clears `MIN_RUN` - which is how a coin standing on a brick once reported 1.27:1 for its own
## shadow while its body read 8.9:1 two pixels away. A shadow is not how you see a thing; it
## cannot answer for one. Matched exactly rather than approximately, so a body colour that
## happens to be dark is never mistaken for one.
static func _is_own_shadow(drawn: Color, surface: Color) -> bool:
	var lit := 1.0 - SHADOW_ALPHA
	for channel in range(3):
		if absf(drawn[channel] - surface[channel] * lit) > SHADOW_EPSILON:
			return false
	return true


## Every colour a drop painted on one surface with at least `MIN_RUN` pixels, best contrast
## against `under` first, as "rrggbb x123 (2.51)".
static func _palette_of(cell: Dictionary, under: Color) -> String:
	var rows: Array = []
	for key: String in cell["drawn"] as Dictionary:
		var count := int((cell["drawn"] as Dictionary)[key])
		if count < MIN_RUN:
			continue
		rows.append([ThemePalette.contrast_ratio(Color(key), under), key, count])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var out: PackedStringArray = []
	for row: Array in rows.slice(0, 6):
		out.append("%s x%d (%.2f)" % [row[1], int(row[2]), float(row[0])])
	return ", ".join(out)


## Most common key of a count histogram.
static func _modal(histogram: Dictionary) -> String:
	var best := ""
	var best_count := -1
	for key: String in histogram:
		if int(histogram[key]) > best_count:
			best_count = int(histogram[key])
			best = key
	return best


static func _total(histogram: Dictionary) -> int:
	var sum := 0
	for key: String in histogram:
		sum += int(histogram[key])
	return sum


## Which surface the room paints at one screen pixel, read off the tile art rather than off the
## colour: the tile the pixel falls in says which atlas cell is drawn there, and the ramp index
## of that cell's pixel says which rung. A pixel no tile paints is the surround.
func _surface_at(px: Vector2i) -> StringName:
	var local := px - FLOOR_ORIGIN
	var tile := Vector2i(local.x / Layers.TILE, local.y / Layers.TILE)
	if local.x < 0 or local.y < 0 or tile.x >= GRID.x or tile.y >= GRID.y:
		return VOID_SURFACE
	var t := _data.get_tile(tile.x, tile.y)
	var cell := Vector2i(-1, -1)
	if t == FloorData.Tile.WALL:
		cell = FloorBuilder.wall_coords(_data, SEED_VALUE, tile.x, tile.y)
	elif _data.is_walkable(tile.x, tile.y):
		cell = FloorBuilder.floor_coords(SEED_VALUE, tile.x, tile.y, true)
	else:
		return VOID_SURFACE
	if _atlas == null:
		return &"other"
	var inner := local - tile * Layers.TILE
	var src := _atlas.get_pixel(cell.x * Layers.TILE + inner.x, cell.y * Layers.TILE + inner.y)
	if src.a < 0.5:
		# A transparent tile pixel shows whatever is behind that layer, which is the backdrop
		# under a wall and the floor under a prop cell. Not a surface this check can name.
		return &"other"
	var index := TileRamp.index_of(src)
	return RUNG_SURFACES.get(index, &"other")


## Prints the tally and says whether the frame holds. Coverage is part of the finding: a run
## that measured three of the four kinds is a run that proves nothing about the fourth, which is
## the exact hole this check was written to close.
func _report() -> bool:
	var gaps: PackedStringArray = []
	for kind: String in KINDS:
		var per_kind: Dictionary = _pixels.get(StringName(kind), {})
		var measured: Dictionary = {}
		for surface: StringName in per_kind:
			var reading := _reading(per_kind[surface] as Dictionary)
			var covered := int(reading["covered"])
			if covered < MIN_SURFACE:
				continue
			var drawn: Color = reading["drawn"]
			var under: Color = reading["under"]
			var ratio := float(reading["ratio"])
			print(
				(
					"%-9s on %-10s %5.2f:1  %s on %s  (%d px)"
					% [kind, surface, ratio, drawn.to_html(false), under.to_html(false), covered]
				)
			)
			if not REQUIRED_SURFACES.has(String(surface)):
				continue
			measured[surface] = true
			if ratio < ThemePalette.WORLD_MIN_CONTRAST - EPSILON:
				# What the drop actually painted there, best ratio first. A failure is nearly
				# always "the colour that was supposed to carry this surface is not in the
				# frame", and the ratio alone cannot say that.
				print("    painted: %s" % _palette_of(per_kind[surface] as Dictionary, under))
				(
					_failures
					. append(
						(
							"%s on %s: %.2f:1 (%s on %s), needs %.1f:1"
							% [
								kind,
								surface,
								ratio,
								drawn.to_html(false),
								under.to_html(false),
								ThemePalette.WORLD_MIN_CONTRAST,
							]
						)
					)
				)
		for surface: String in REQUIRED_SURFACES:
			if not measured.has(StringName(surface)):
				gaps.append("%s was never measured on %s" % [kind, surface])
	for line: String in _failures:
		print("FAIL " + line)
	for line: String in gaps:
		print("GAP  " + line)
	print(
		(
			"pickup frame: %d kinds x %d surfaces, %d under target, %d not measured"
			% [KINDS.size(), REQUIRED_SURFACES.size(), _failures.size(), gaps.size()]
		)
	)
	return _failures.is_empty() and gaps.is_empty()


## `tests/out/pickup_frame.png`, with `_<theme>` appended for any fixture but the default, the
## way `tools/run-scenario.sh` and `prop_frame_capture` name their captures.
static func _out_path() -> String:
	var state := OS.get_environment("OMADUNGEON_OMARCHY_STATE_DIR")
	var theme := state.trim_suffix("/").get_base_dir().get_file() if not state.is_empty() else ""
	if theme.is_empty() or theme == "tokyo-night":
		return "res://tests/out/pickup_frame.png"
	return "res://tests/out/pickup_frame_%s.png" % theme
