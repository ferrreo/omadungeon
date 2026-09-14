## Rendered check for prop readability: the guarantee measured on a *drawn frame*, not on the
## colour model that produced it. Runs as its own main scene inside the nested headless sway
## harness (never on the real session):
##
##   OMADUNGEON_OMARCHY_STATE_DIR=tests/fixtures/omarchy/tokyo-night/state \
##   tools/headless-sway.sh godot --path . --rendering-driver opengl3 \
##       res://tests/unit/rooms/prop_frame_capture.tscn
##
## It builds a real `FloorRoot` - real tiles, the real accent prop material, the room's own
## additive `PointLight2D` torches - inside a 480x270 SubViewport at native scale, saves
## `tests/out/prop_frame_<biome>[_<theme>].png`, and then *reads that PNG back* and measures
## every prop in it against the floor tile beside it. `prop_render_test` computes what the
## shader will emit; this one looks at what the compositor actually emitted, which is where the
## owner's verifier read 1.87 off a coffin the model said was at 2.2.
##
## **One frame per biome, every kind in it.** It used to draw six of the crypt's eight kinds and
## nothing else, so thirty-four of the forty cells the game can put on screen were covered by
## the model alone - and the model is exactly what missed the coffin. A biome is a different
## prop *sheet* under a different tile atlas and a different palette variant, so a rung that
## clears the floor in the crypt says nothing about the same rung in the forge. The floor is
## rebuilt once per `Biome.ALL_IDS` entry, filled with every name `Prop.kind_names()` gives that
## biome, and measured on its own capture.
##
## **What it guarantees, since the dungeon went dark.** Unlit ground is now near black
## (`LightingProfile.unlit_floor`) and a crate standing in it is near black too - deliberately,
## and there is nothing to read there for anyone. So the frame is lit the way the game lights it:
## the room's own door torches and wall lanterns, plus a pool standing in the middle of the props
## at the energy, radius and palette role the emitter table gives the **player's own light**,
## because a player reading a crate is a player standing next to it. Every prop whose floor the
## light has actually reached (`MIN_LIT_SHARE` of the colour the room's tile material carries) is
## measured and has to clear its ladder; a prop the light has not reached is reported and
## skipped, and at least `MIN_LIT_PROPS` of each biome's kinds have to be lit or the frame fails
## for measuring nothing.
##
## The guarantee is therefore: **a prop you can see at all is a prop you can read.** That is
## weaker than the old "every prop in the room is readable" in exactly one way - it says nothing
## about props standing in the dark - and that is the point of the round rather than a concession
## in it.
##
## **And it is measured as a share of what the palette authored, not as an absolute ratio.** A
## contrast ratio is `(L1 + 0.05) / (L2 + 0.05)`, and the 0.05 is screen flare: it is a constant,
## so the same two colours drawn at a third of their exposure report a far lower ratio than they
## do at full. That is not a rounding artefact, it is true - a player in a dark room does see less
## contrast - and it means an absolute target written for a fully exposed frame cannot be met on a
## lit-in-pockets one by any art at all. Measured on `prop_frame` tokyo-night: the crypt barrel's
## r3 and r4 are 1.11 apart at full exposure and 1.03 apart drawn, with the *same colours in the
## same order*. So each rung is compared against the same rung's own authored contrast
## (`Prop.ramp_targets`, the colours the room's tile material carries), and what is guaranteed is
## `MIN_CONTRAST_SHARE` of it, never falling under `MIN_DRAWN_RATIO` outright. A prop that goes
## flat under the light still fails, because the share falls; a prop the light merely dims does
## not, because the share does not.
##
## It fails (exit 2) rather than merely reporting, so the numbers cannot rot unlooked-at.
class_name PropFrameCapture
extends Node

const VIEW_SIZE := Vector2i(480, 270)
## Where the floor is pinned inside the viewport, in pixels.
const FLOOR_ORIGIN := Vector2i(64, 6)
## Longest the capture waits for the frame to stop changing, and the gap between the two
## readings it compares (see `_settle`).
const SETTLE_DEADLINE := 8.0
const SETTLE_STEP := 0.15
## Slack on a ratio read back out of an 8-bit PNG. One code point at the dark end of the sRGB
## curve moves a contrast ratio by more than a rounding error does. The model pays for this at
## the other end too - `Prop.ANCHOR_CLEARANCE_MARGIN` places the one rung with no tolerance a
## little clear of its target, because the frame does not reproduce the model to the last
## decimal.
const EPSILON := 0.05
## Pixels a ramp entry must cover in a cell before the frame is asked about it: fewer than
## this is a highlight dot, not a surface.
const MIN_RUN := 3
## Key the drawn floor is filed under in `_rung_pixels`, beside the integer ramp indices, and
## the index it is gathered under while counting (the ramp has no negative entries).
const FLOOR_KEY := &"floor"
const FLOOR_INDEX := -2
## How much of what the pool *can* put on the floor beside a prop has to have landed there before
## the prop counts as lit: 1.0 is a tile at the pool's centre, 0 is one the light never reached.
##
## Normalised against the light rather than against the tile material's own colour, because a
## pool restores a surface to `material x flame`, not to `material` - a flame carries chroma, and
## chroma costs luminance. Measured against the bare material, catppuccin-latte's paper floor read
## a third of itself at a pool's dead centre and four of the crypt's nine kinds were skipped as
## "unlit" while standing directly under the light.
const MIN_LIT_SHARE := 0.35
## Least of a biome's prop kinds that have to be lit before the frame is a measurement at all.
## Without it a floor that lit nothing would pass by measuring nothing.
const MIN_LIT_PROPS := 5
## How much of the contrast the palette authored a rung with has to survive being drawn under the
## room's own light, and the ratio it may never fall under whatever the share says. The share is
## the guarantee; the absolute is the floor beneath it, so "a lot of very little" cannot pass.
##
## Three tenths rather than a half, and the reason is the flare term rather than the art. A
## contrast ratio is `(L1 + 0.05) / (L2 + 0.05)`; dim both colours and the constant 0.05 takes a
## larger and larger share of both, so the ratio walks toward 1 with nothing having changed about
## the pixels' relationship. A prop measured at half the light it was authored under keeps
## somewhere between a third and two thirds of its authored ratio for that reason alone. The
## binding fixture is catppuccin-latte, whose props are dark ink on paper: its frost sack's top
## rung keeps 29% at a lit share of 0.39. Under a quarter a prop has stopped standing off its
## floor for a reason the flare cannot explain, which is the thing worth failing on - and
## `MIN_DRAWN_RATIO` is underneath it either way, so a prop that has merged with its floor fails
## whatever share it kept of a contrast that was small to begin with.
const MIN_CONTRAST_SHARE := 0.25
const MIN_DRAWN_RATIO := 1.15
## The ladder *inside* a body is reported here and guaranteed by `prop_render_test`, not by this
## frame, and that is a deliberate line rather than an omission.
##
## Two neighbouring body rungs are a few code points apart by design - `Prop.LIT_BODY_STEP` is
## 1.12, which on a mid-grey is about three values of 255. Multiply a surface by a third and those
## three values become one, and the two rungs quantise onto the same drawn pixel: measured on
## `prop_frame` frost, the sack's r2 and r3 both drew #41676e, exactly. That is not the art going
## flat and it is not the light going wrong - it is what an eight-bit frame does to fine shading
## in a dark room, and it is what a player sees there too.
##
## So the drawn frame guarantees the thing a player can actually judge in a dungeon lit in
## pockets - **the object stands off the floor it is standing on** - and `prop_render_test` goes
## on guaranteeing the interior ladder in the colour model, at the exposure the palette authors
## its ramps at. The step is printed on every line so a real collapse is still visible to a person
## reading the log; what it is not any more is an assertion a dark room cannot satisfy.

var _atlases: Dictionary = {}
var _grounds: Dictionary = {}
## Biome -> how many props that frame measured, for the closing tally.
var _counted: Dictionary = {}


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
	var bad: PackedStringArray = []
	for biome: StringName in Biome.ALL_IDS:
		if not await _capture_biome(view, biome):
			bad.append(String(biome))
	var total := 0
	for biome: StringName in _counted:
		total += int(_counted[biome])
	print(
		(
			"prop frame: %d lit props over %d biomes, %d biome(s) under target%s"
			% [
				total,
				_counted.size(),
				bad.size(),
				"" if bad.is_empty() else ": " + ", ".join(bad),
			]
		)
	)
	QuitGuard.request(get_tree(), 0 if bad.is_empty() else 2)


## Builds one biome's floor in `view`, saves its PNG and measures it. Returns false when the
## frame is under target or never landed on disk.
##
## The floor is rebuilt rather than retinted: the tile atlas, the prop sheet and the room's
## palette variant all change with the biome, and a retint would leave the previous biome's
## art standing under the new colours.
func _capture_biome(view: SubViewport, biome: StringName) -> bool:
	var root := FloorRoot.new()
	root.position = Vector2(FLOOR_ORIGIN)
	view.add_child(root)
	root.build_with_biome(_floor_data(biome), Biome.load_by_id(biome), null, null)
	_stand_in_the_room(root)
	var image := await _settle(view, root)
	var path := ProjectSettings.globalize_path(_out_path(biome))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := image.save_png(path)
	print("prop frame -> %s (%s)" % [path, error_string(saved)])
	var ok := _measure(root, image)
	view.remove_child(root)
	root.queue_free()
	await get_tree().process_frame
	return ok and saved == OK


## Puts the light a player carries in the middle of the prop room.
##
## Not a fixture invention: it is the `player` row of `LightingProfile.emitters` - the same
## energy, radius and palette role `LightRig` drives the real player's light at - standing where
## a player reading the crates would stand. Before the dungeon went dark this capture needed no
## such thing, because an ambient wash lit every prop in the room whether anything was there or
## not. That wash is gone, so the light has to be in the room, and a light in the room is a thing
## the player can point at.
static func _stand_in_the_room(root: FloorRoot) -> void:
	var room: FloorData.Room = root.data.rooms[1]
	var spec := LightingProfile.resolve().emitter_spec(&"player")
	var color := pool_color(root)
	var texture := DungeonLight.make_texture(DungeonLight.resolve().light_texture_size)
	# One pool, at the pool's own energy and radius. Four of them - one per row of props - was
	# tried and every rung of every prop clipped to #ffffff: four overlapping pools each at the
	# dark exactly undone is four times the light the game ever puts on a tile, which measures
	# a frame the game cannot draw.
	var light := PointLight2D.new()
	light.name = "PlayerPool"
	light.texture = texture
	light.texture_scale = float(spec["radius"])
	light.energy = float(spec["energy"])
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.range_item_cull_mask = LightRig.LIT_MASK
	light.shadow_enabled = false
	light.color = color
	light.position = (Vector2(room.rect.get_center()) + Vector2(0.5, 0.5)) * float(Layers.TILE)
	root.add_child(light)


## Waits until the viewport has drawn the same frame twice, and returns it.
##
## A floor does not finish arriving on the frame it is built: the tile and prop materials
## crossfade into the live palette (`FloorRoot._retint_layers`), the wallpaper analysis that
## sets the room's ambient lands when it lands, and the torches flicker. A fixed settle shot
## whatever phase all of that happened to be in - the same nord room measured a drawn floor of
## `77788b` on one run and `797a8c` on the next, and moved four props in and out of failing
## between two runs of the same code. A number that changes between runs cannot tell a
## regression from a frame. Two identical frames is the wait (docs: poll with a deadline, never
## count frames); the flicker never stops on its own, so it is pinned on every pass.
func _settle(view: SubViewport, root: FloorRoot) -> Image:
	var previous := PackedByteArray()
	var image: Image = null
	var waited := 0.0
	while waited < SETTLE_DEADLINE:
		await get_tree().create_timer(SETTLE_STEP).timeout
		_freeze_torches(root)
		await RenderingServer.frame_post_draw
		image = view.get_texture().get_image()
		var data := image.get_data()
		if not previous.is_empty() and data == previous:
			return image
		previous = data
		waited += SETTLE_STEP
	push_error("prop frame: %s never settled in %.1f s" % [root.data.biome, SETTLE_DEADLINE])
	return image


## Pins every torch at the energy the colour model is written against.
##
## The torches flicker - `DungeonLight.torch_flicker` swings them 14% either way at 2.3 Hz - so
## a capture taken after a real-time settle shoots at whatever phase the machine's frame pacing
## happened to land on. The same gruvbox prop measured r2 3.80 on one run and 3.53 on the next,
## and a check whose numbers move between runs cannot tell a regression from a frame. The
## guarantee is made against `Prop.bloom_for()`, which is the *base* energy with no flicker on
## it, so that is the energy the frame is taken at.
static func _freeze_torches(root: FloorRoot) -> void:
	root.set_process(false)
	var energy := root.torch_light_energy()
	for light: PointLight2D in root.torch_lights():
		if is_instance_valid(light):
			light.energy = energy


## The fixture layout with every one of `biome`'s prop kinds laid across the combat room, so
## one frame carries each kind at a different distance from the room's own torches instead of
## a single lucky one. Eight kinds fit the 5x4 room on every other column.
func _floor_data(biome: StringName) -> FloorData:
	var data := RoomsTestFixtures.three_rooms()
	data.biome = biome
	var room: FloorData.Room = data.rooms[1]
	room.prop_positions = []
	room.prop_kinds = []
	var kinds: Array = Prop.kind_names(biome)
	var i := 0
	for y in range(room.rect.position.y, room.rect.end.y):
		for x in range(room.rect.position.x, room.rect.end.x, 2):
			if i >= kinds.size() or not data.is_walkable(x, y):
				continue
			room.prop_positions.append(Vector2i(x, y))
			room.prop_kinds.append(StringName(kinds[i]))
			i += 1
	if i < kinds.size():
		push_error(
			"prop frame: only %d of %d %s kinds fit the fixture room" % [i, kinds.size(), biome]
		)
	return data


## `tests/out/prop_frame_<biome>.png`, with `_<theme>` appended for any fixture but the
## default, the way `tools/run-scenario.sh` names its captures.
static func _out_path(biome: StringName) -> String:
	# The fixture directory, not `palette.name`: the palette calls itself "Tokyo Night", and a
	# capture filename with a space in it is a capture nobody can pass to a script.
	var state := OS.get_environment("OMADUNGEON_OMARCHY_STATE_DIR")
	var theme := state.trim_suffix("/").get_base_dir().get_file() if not state.is_empty() else ""
	if theme.is_empty() or theme == "tokyo-night":
		return "res://tests/out/prop_frame_%s.png" % biome
	return "res://tests/out/prop_frame_%s_%s.png" % [biome, theme]


## Colour histogram of one 16x16 tile of the capture, keyed by its 8-bit value.
static func _tile(image: Image, tile: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	var base := Vector2i(FLOOR_ORIGIN) + tile * Layers.TILE
	for y in range(Layers.TILE):
		for x in range(Layers.TILE):
			var px := image.get_pixel(base.x + x, base.y + y)
			var key := px.to_html(false)
			out[key] = int(out.get(key, 0)) + 1
	return out


static func _modal(histogram: Dictionary) -> String:
	var best := ""
	var best_count := -1
	for key: String in histogram:
		if int(histogram[key]) > best_count:
			best_count = int(histogram[key])
			best = key
	return best


## Every prop measured on the pixels the frame carries, rung by rung.
##
## Which pixels belong to the object is read off the *art*, not guessed from the colours: the
## atlas cell says which 16x16 positions the prop paints and which ramp entry each one is, so a
## body rung is compared against the floor showing through beside it, under the same torch, in
## the same tile. Matching by colour instead was the first attempt and it does not work - the
## light is a gradient, so the floor inside the prop's tile is not quite the floor in the tile
## next door, and the difference reads as prop pixels that fail their own target.
func _measure(root: FloorRoot, image: Image) -> bool:
	var ok := true
	var lit_count := 0
	for prop: Prop in root.props:
		var tile := FloorRoot.tile_of(prop.position)
		var cells := _rung_pixels(root, prop, image, tile)
		var floor_colour: Color = cells.get(FLOOR_KEY, Color.MAGENTA)
		var share := _lit_share(root, prop, floor_colour)
		if share < MIN_LIT_SHARE:
			# Nothing is lighting this prop, so there is nothing here a player could judge.
			print(
				(
					"%-7s %-8s tile %s: floor %s at x%.2f of the room's own - unlit, not measured"
					% [prop.biome, prop.kind, tile, floor_colour.to_html(false), share]
				)
			)
			continue
		lit_count += 1
		# Only the rungs the frame actually drew: the interior ladder is compared step for step,
		# and an authored ladder with four rungs against a drawn one with two is not a comparison.
		var authored := _authored_cells(root, prop, cells)
		var reported: Array[String] = []
		var worst_share := 99.0
		var worst_ratio := 99.0
		for rung: int in Prop.BODY_RUNGS:
			if not cells.has(rung) or not authored.has(rung):
				continue
			var drawn: Color = cells[rung]
			var ratio := ThemePalette.contrast_ratio(drawn, floor_colour)
			var want := ThemePalette.contrast_ratio(
				authored[rung] as Color, authored[FLOOR_KEY] as Color
			)
			var kept := ratio / maxf(want, 0.0001)
			worst_share = minf(worst_share, kept)
			worst_ratio = minf(worst_ratio, ratio)
			reported.append(
				(
					"r%d %.2f/%.2f=%.0f%% [%s]"
					% [rung, ratio, want, kept * 100.0, drawn.to_html(false)]
				)
			)
		var step := _worst_step(cells)
		var want_step := _worst_step(authored)
		var step_share := (step - 1.0) / maxf(want_step - 1.0, 0.0001)
		var line := (
			"%-7s %-8s tile %s: floor %s at x%.2f | %s | interior step %.2f/%.2f = %.0f%%"
			% [
				prop.biome,
				prop.kind,
				tile,
				floor_colour.to_html(false),
				share,
				", ".join(reported),
				step,
				want_step,
				step_share * 100.0,
			]
		)
		if worst_share < MIN_CONTRAST_SHARE or worst_ratio < MIN_DRAWN_RATIO:
			ok = false
			line = "FAIL " + line
		print(line)
	if lit_count < MIN_LIT_PROPS:
		ok = false
		print(
			(
				(
					"FAIL %s: only %d prop(s) stood in any light, under the %d this frame has to "
					+ "measure before it is a measurement"
				)
				% [root.data.biome, lit_count, MIN_LIT_PROPS]
			)
		)
	_counted[root.data.biome] = lit_count
	return ok


## How much additive light is standing on this prop's tile, read straight out of the frame: the
## drawn floor beside it, less the floor colour the room's own tile material carries.
##
## It reads low on a light theme, where the floor is already at or near #ffffff and an additive
## torch leaves no room to show itself. That costs nothing here: on the two light fixtures every
## prop clears its target by a wide margin whatever the torches are doing, and the number exists
## to say which *dark*-theme props are standing inside a pool (see `Prop.BLOOM_MAX`).
## The colours the room's tile material authors for this prop's rungs, plus its floor under
## `FLOOR_KEY`: what the frame is compared against, rung for rung.
static func _authored_cells(root: FloorRoot, prop: Prop, drawn: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var room := root.room_at_world(prop.position)
	if room == null:
		return out
	# Two materials, because the frame draws two: the floor beside the prop wears the room's tile
	# material and the prop wears the accent one (`FloorRoot.prop_accent_material_for_room`).
	# Reading both rungs off the tile ramp reported a body rung at 1.00 against its own floor,
	# which is a prop painted in the floor's colours and is not a thing the game draws.
	var floors := Prop.ramp_targets(root.material_for_room(room.id))
	var bodies := Prop.ramp_targets(root.prop_accent_material_for_room(room.id))
	if floors.size() < TileRamp.RAMP_SIZE or bodies.size() < TileRamp.RAMP_SIZE:
		return out
	out[FLOOR_KEY] = floors[Prop.FLOOR_RAMP_INDEX]
	for rung: int in Prop.BODY_RUNGS:
		if drawn.has(rung):
			out[rung] = bodies[rung]
	return out


## How much of the colour the room's own tile material carries the drawn floor beside this prop
## still has: 1.0 is a surface a pool has fully restored, 0 is one nothing is lighting. Measured
## on relative luminance, so a flame's own colour counts against it - which is right, because a
## floor lit by a deep red light *is* darker than the same floor lit by a pale one, and a player
## reads what is drawn rather than what was intended.
static func _lit_share(root: FloorRoot, prop: Prop, drawn_floor: Color) -> float:
	var room := root.room_at_world(prop.position)
	if room == null:
		return 0.0
	var targets := Prop.ramp_targets(root.material_for_room(room.id))
	if targets.size() < TileRamp.RAMP_SIZE:
		return 0.0
	var dry: Color = targets[Prop.FLOOR_RAMP_INDEX]
	var flame := pool_color(root)
	var best := ThemePalette.relative_luminance(
		Color(dry.r * flame.r, dry.g * flame.g, dry.b * flame.b, 1.0)
	)
	if best <= 0.0:
		return 0.0
	return ThemePalette.relative_luminance(drawn_floor) / best


## The colour the fixture's pool burns in: the theme's accent made a light, the way `LightRig`
## makes the player's own. One definition, used to place the light and to normalise the reading
## taken under it.
static func pool_color(root: FloorRoot) -> Color:
	var role: StringName = LightingProfile.resolve().emitter_spec(&"player")["role"]
	return DungeonLight.resolve().light_color(root.lit_palette().get_color(role))


static func _bloom_at(root: FloorRoot, prop: Prop, drawn_floor: Color) -> float:
	var room := root.room_at_world(prop.position)
	if room == null:
		return 0.0
	var targets := Prop.ramp_targets(root.material_for_room(room.id))
	if targets.size() < TileRamp.RAMP_SIZE:
		return 0.0
	var dry: Color = targets[Prop.FLOOR_RAMP_INDEX]
	var delta := (drawn_floor.r - dry.r) + (drawn_floor.g - dry.g) + (drawn_floor.b - dry.b)
	return maxf(delta / 3.0, 0.0)


## The drawn colour of each ramp entry this prop paints, plus the drawn floor beside it under
## `FLOOR_KEY`. Modal per rung, so one antialiased or overdrawn pixel cannot set the answer.
##
## The floor entry is read the same way, off the *ground tile's* art: a floor cell is painted
## from the floor rung and the `floor_alt` rung both, and one in eight of them is a decorated
## cell that is mostly the latter. The ladder is guaranteed against the floor, so taking
## whichever colour the tile happened to have most of measured a gruvbox crate against
## `floor_alt` and reported 1.95 for a rung standing 2.45 off the floor it was placed against.
func _rung_pixels(root: FloorRoot, prop: Prop, image: Image, tile: Vector2i) -> Dictionary:
	var sheet := _atlas(prop.biome)
	var ground := _tile_atlas(root)
	var out: Dictionary = {}
	if sheet == null or ground == null:
		return out
	var cell := FloorBuilder.floor_coords(root.data.seed_value, tile.x, tile.y, true)
	var counts: Dictionary = {}
	var base := Vector2i(FLOOR_ORIGIN) + tile * Layers.TILE
	for y in range(Layers.TILE):
		for x in range(Layers.TILE):
			var src := sheet.get_pixel(prop.kind_index * Layers.TILE + x, y)
			var index := TileRamp.index_of(src) if src.a >= 0.5 else -1
			if src.a < 0.5:
				var under := ground.get_pixel(cell.x * Layers.TILE + x, cell.y * Layers.TILE + y)
				if TileRamp.index_of(under) != Prop.FLOOR_RAMP_INDEX:
					continue
				index = FLOOR_INDEX
			elif index < 0:
				continue
			var seen: Dictionary = counts.get(index, {})
			var drawn := image.get_pixel(base.x + x, base.y + y).to_html(false)
			seen[drawn] = int(seen.get(drawn, 0)) + 1
			counts[index] = seen
	for index: int in counts:
		var seen: Dictionary = counts[index]
		if _total(seen) < MIN_RUN:
			continue
		if index == FLOOR_INDEX:
			out[FLOOR_KEY] = Color(_modal(seen))
		else:
			out[index] = Color(_modal(seen))
	return out


## The biome tile sheet this floor is drawn from, loaded once per biome.
func _tile_atlas(root: FloorRoot) -> Image:
	var biome: StringName = root.data.biome
	if not _grounds.has(biome):
		_grounds[biome] = Image.load_from_file(FloorBuilder.atlas_path_for(biome))
	return _grounds[biome] as Image


## The narrowest gap between two neighbouring body rungs as the frame draws them. This is the
## "four interior shades collapsing to roughly one value" the owner reported, as a number.
static func _worst_step(cells: Dictionary) -> float:
	var shades: Array[float] = []
	for rung: int in Prop.BODY_RUNGS:
		if cells.has(rung):
			shades.append(ThemePalette.relative_luminance(cells[rung] as Color))
	if shades.size() < 2:
		return 99.0
	shades.sort()
	var worst := 99.0
	for i in range(1, shades.size()):
		worst = minf(worst, (shades[i] + 0.05) / (shades[i - 1] + 0.05))
	return worst


## The prop atlas of a biome, loaded once per run.
func _atlas(biome: StringName) -> Image:
	if not _atlases.has(biome):
		_atlases[biome] = Image.load_from_file("%s%s.png" % [Prop.PROPS_DIR, biome])
	return _atlases[biome] as Image


static func _total(histogram: Dictionary) -> int:
	var sum := 0
	for key: String in histogram:
		sum += int(histogram[key])
	return sum
