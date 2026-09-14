## A piece of clutter (barrel, coffin, crate, bones, rubble...). StaticBody2D on Layers.PROP so
## hitboxes reach it via `take_hit(info)`. Sprite cells come from
## assets/sprites/props/<biome>.png (16x16, `KIND_COUNT` kinds; row `DEBRIS_ROW` is the broken
## frame).
##
## One rule, and the player reads it off the sprite (`SOLID`): a kind drawn as an *upright*
## object wears an ink outline, stands on a contact shadow, blocks movement, casts a shadow
## (a `LightOccluder2D` child, `OCCLUDER`, the size of its base) and breaks - a burst of
## particles, maybe gold (EventBus.spawn_pickup), and its debris frame left on the floor with
## the collision and the occluder gone. A kind drawn *flat* on the floor (bones, rubble, a
## snowdrift) carries no ink at all and is walk-over decoration: its collision shape is
## disabled, it is on no layer, it casts nothing and there is nothing to break. `is_solid()` is
## the only place that decides it, from `prop_solid` in `data/rooms/rooms_content.tres` or the
## `SOLID` mirror below. Where props *go* is `PropPlacement`. A prop never carries a light of
## its own: a brazier lit by its own emitter brightened the floor beside it and measured
## under the readability target on every dark fixture (`prop_frame`), so fire and glow stay a
## drawn accent.
class_name Prop
extends StaticBody2D

signal broken(prop: Prop)

## Kinds per biome: the four `SHARED` kinds in the first four atlas columns, then five of the
## biome's own. Small on purpose - the third clutter report was "still makes little sense", and
## twenty-seven kinds that were all a grey rounded rectangle with a different texture inside it
## were the reason. Every kind here has a silhouette of its own (see `tools/art/prop_maps.py`).
const KIND_COUNT := 9
## Name of the `LightOccluder2D` a solid prop carries (see `OCCLUDER_BASE_ROWS`).
const OCCLUDER := &"Occluder"
## Rows of the sprite's opaque bounding box, counted up from its bottom, the occluder covers:
## the *base* of the object, the part that stands on the floor. A shadow cast from the whole
## sprite would be a wall's; one cast from the footprint is a barrel's.
const OCCLUDER_BASE_ROWS := 6
const PROPS_DIR := "res://assets/sprites/props/"
## Atlas row holding the broken frame of every solid kind (flat kinds leave theirs empty).
const DEBRIS_ROW := 1
## The kinds every biome carries, in atlas column order.
const SHARED: Array[StringName] = [&"barrel", &"crate", &"sack", &"rubble"]
## Readable kind names per biome, column order in the atlas.
const KINDS: Dictionary = {
	&"crypt":
	[
		&"barrel",
		&"crate",
		&"sack",
		&"rubble",
		&"coffin",
		&"gravestone",
		&"urn",
		&"candle",
		&"bones",
	],
	&"forge":
	[
		&"barrel",
		&"crate",
		&"sack",
		&"rubble",
		&"anvil",
		&"cart",
		&"brazier",
		&"chain",
		&"slag",
	],
	&"frost":
	[
		&"barrel",
		&"crate",
		&"sack",
		&"rubble",
		&"ice_block",
		&"lantern",
		&"snowman",
		&"boulder",
		&"snow",
	],
	&"library":
	[
		&"barrel",
		&"crate",
		&"sack",
		&"rubble",
		&"bookshelf",
		&"desk",
		&"lectern",
		&"globe",
		&"books",
	],
	&"void":
	[
		&"barrel",
		&"crate",
		&"sack",
		&"rubble",
		&"crystal",
		&"monolith",
		&"floater",
		&"orb",
		&"rift",
	],
}
## Kinds that take two hits: the heavy furniture and the stone.
const STURDY: Array[StringName] = [
	&"crate", &"coffin", &"anvil", &"ice_block", &"boulder", &"bookshelf", &"monolith"
]
## Kind name -> solid. Every name in KINDS has an entry. Upright objects are solid (they block
## and break); things drawn lying on the floor are not (walked over, never hit). The art is
## authored to the same table (`tools/art/props.py::SOLID`, exported to `prop_solid.json`) and
## `prop_test` reads the shipped PNG back against it: a solid kind wears ink and stands on a
## contact shadow, a flat one paints neither.
const SOLID: Dictionary = {
	&"anvil": true,
	&"barrel": true,
	&"bookshelf": true,
	&"boulder": true,
	&"brazier": true,
	&"candle": true,
	&"cart": true,
	&"coffin": true,
	&"crate": true,
	&"crystal": true,
	&"desk": true,
	&"floater": true,
	&"globe": true,
	&"gravestone": true,
	&"ice_block": true,
	&"lantern": true,
	&"lectern": true,
	&"monolith": true,
	&"orb": true,
	&"sack": true,
	&"snowman": true,
	&"urn": true,
	&"bones": false,
	&"books": false,
	&"chain": false,
	&"rift": false,
	&"rubble": false,
	&"slag": false,
	&"snow": false,
}
const GOLD_CHANCE := 0.2
## Ramp index holding the floor colour in a room's tile material (see TileRamp.RAMP).
const FLOOR_RAMP_INDEX := 3
## Minimum WCAG contrast ratio each ramp index must reach against the room's floor colour in
## the material props, hazards and interactables are drawn with, measured on what the screen
## actually shows - after the floor's ambient dimming, and in both readings of the room: unlit,
## and again with `bloom_for()` of one of its torches on top. The room tint maps indices 1-5 onto
## void/wall/floor/floor_alt/wall_top, so an untreated prop is painted in the exact colours of
## the tile it stands on: every index has to clear the floor or the sprite is invisible.
##
## Indices 2-5 are the body and take this as a floor, then `spread_rungs` opens them out well
## past it. Index 1 is the *ink* and clears the floor on the other side of it (`ink_color` /
## `INK_FLOOR_RATIO`), so this entry is the ratio it aims for going down rather than up. Index
## 0 is the transparent slot. Overridable through `prop_contrast` in
## `data/rooms/rooms_content.tres`.
##
## The body entries used to rise 2.6 -> 3.8 across the ramp. That is what flattened the sprite:
## chaining five rising minimums inside one luminance band left nothing between neighbours. A
## single floor per body rung plus a geometric spread delivers *more* separation from the floor
## for the upper rungs and an actual ladder between them.
const READABLE_CONTRAST: Array[float] = [1.0, 2.2, 2.2, 2.2, 2.2, 2.2, 2.6, 2.6]
## Saturation the body rungs of a *prop* are re-hued to, per ramp index (0 leaves the rung
## alone). Docs §3.2 gives props their own colour - "`prop_a`/`prop_b` rolled per room from
## the `red...brown` set" - but the prop atlas paints barrels, urns and coffins almost entirely
## in the *environment* rungs (1-5: 96% of the crypt sheet's opaque pixels), which the room tint
## maps onto void/wall/floor/floor_alt/wall_top. Contrast alone therefore only ever produced a
## lifted wall: a lavender room with lavender pots in it. These pull the body onto the room's
## own accent hue at its own luminance, so the contrast `readable_colors` just guaranteed is
## untouched and the pot is a different *colour* from the floor rather than a different value
## of it. Index 1 stays darker and less saturated: prop art uses it for outlines as well as
## fills, and a fully saturated outline reads as a glow.
const ACCENT_BODY_SATURATION: Array[float] = [0.0, 0.26, 0.40, 0.40, 0.40, 0.36, 0.0, 0.0]
## Bisection steps `ensure_visible` spends finding the exposure that clears a rung's target.
## 24 halvings put the answer inside 1/16 000 000 of a luminance, which is far below what a
## Color can hold.
const EXPOSURE_STEPS := 24
## The ramp index prop art paints its outline with. Handled apart from the ladder below.
const INK_RUNG := 1
## Ramp indices that carry a prop's *body*: shadow side, body, lit face and highlight. Index 1
## is the ink that wraps them (`INK_RUNG`); the two accent rungs are decals and keep their own
## colour.
const BODY_RUNGS: Array[int] = [2, 3, 4, 5]
## Contrast the ink rung aims for against the floor, on the *dark* side of it.
##
## The ink always goes down - that is what an outline is, on a dark theme and on a light one -
## and that is the whole reason a prop reads as an object again. The previous model pushed
## every rung the same way, up and off the floor, which is why a crate arrived as a rimless
## block: the ink had to clear the floor by 2.6 like everything else, which on a dark theme put
## it at 0.34 luminance with four more rungs stacked above it inside the 0.80 ceiling, so the
## outline and the fill it wrapped ended up 1.2-1.6 apart (the owner's verifier measured 1.17
## on a shipped crate). Sending it the other way costs nothing - a dungeon floor is lit into
## `ThemePalette.LIT_FLOOR_LUMINANCE_MIN`..`MAX`, so black clears 2.34 against the darkest one
## it can be - and it hands the whole luminance band back to the four body rungs.
const INK_FLOOR_RATIO := 2.2
## Contrast the ink keeps against the body rung next to it, whichever side of the floor it
## ended up on. This is the rim: below it a prop is a silhouette with no edge.
const INK_BODY_RATIO := 2.0
## The luminance band the four body rungs are opened out across, once the floor ladder has
## placed the one nearest the floor.
##
## The spread is *geometric in contrast*, not linear in luminance: each rung stands the same
## ratio off the one before it, because contrast is what an eye reads and a linear spread of a
## narrow band is still a flat sprite. The band is the limit rather than the target, so the
## rungs never reach the extremes: a colour taken to within a few percent of white or black
## holds no chroma at all, and a prop drawn in one is a grey prop in a themed room
## (`floor_lighting_test` fails the build for it).
## `MIN` is not zero on purpose: the ink goes below the darkest body rung on a light theme, and
## black has to stay `INK_BODY_RATIO` below it for the rim to exist at all.
##
## `MAX` is a guard on *chroma*, not on the light: a colour taken to within a few percent of
## white holds none, and a grey prop in a themed room is the bug `floor_lighting_test` fails the
## build for. The light is held off the top rung by `LIT_BODY_CEILING` instead, which is a
## ceiling on the *drawn* value and therefore the only one that can see a torch at all. Round 3
## pulled this to 0.65 to do that job dry; it cost the ladder headroom on every theme and still
## left the worst lit step at 1.09.
const BODY_LUMINANCE_MAX := 0.72
const BODY_LUMINANCE_MIN := 0.05
## A dungeon torch is a `PointLight2D` in `Light2D.BLEND_MODE_ADD` (`FloorRoot._add_torch_light`),
## and what it adds is *not* a flat value. Godot's default canvas light multiplies the light by
## the surface it lands on before adding it, so a lit pixel is drawn at
## `surface * (1 + energy * light_colour)`, per channel - a brighter surface takes more light
## than a darker one, and a warm torch takes the red channel up two and a half times as far as
## the blue. That is the one thing a contrast model cannot see, and modelling it as a flat grey
## offset is what hid the collapse for three rounds: the model predicted a crypt crate's top two
## rungs at 0.69 and 0.99 of drawn luminance and the compositor drew them at 0.95 and 1.00,
## because both had run their red and green channels into the clamp at 1.0 and arrived as the
## same pixel. `under_light` therefore multiplies the way the renderer does, and `bloom_for`
## hands it the per-channel gain rather than a scalar.
##
## `BLOOM_MAX` is the boundary of the guarantee, in the unit the rendered check measures: the
## mean channel delta a torch puts on the *floor* (`PropFrameCapture._bloom_at` reads exactly
## that off the frame - the drawn floor beside the prop, less the floor the tile material
## carries). At or under it the interior ladder is guaranteed; past it the prop is inside a
## torch pool, the light is a deliberate blow-out and the check reports the interior instead of
## failing it. `bloom_for` solves for the energy that puts this much light on this floor, so a
## dark theme's dim floor is judged under the same torch a light theme's paper one is, and the
## cap is what separates them: the same energy puts far less *relative* light on a bright floor.
##
## The number itself is the light the shipped `dungeon_light.tres` actually casts: the frames
## measure 0.00 to 0.15 across the five biome sheets, with the two brightest tiles (the ones a
## torch stands on) past it and everything else under.
const BLOOM_MAX := 0.13
## Largest channel value the framebuffer can still tell apart from white. A rung the room's own
## light pushes to or past this has lost its top end, and the rung under it catches up.
const CLIP_LEVEL := 1.0 - 0.5 / 255.0
## How many torches' worth of light a prop may be standing in.
##
## One pool is the dark exactly undone (`LightingProfile.unlit_floor` + `lantern_energy` = 1), so
## a prop at a pool's centre is back at the level the theme authored it at and no further; what
## can push it past that is a *second* source. The falloff says how much: at the generator's
## tightest spacing (6 tiles, forge) the tile half way between two lanterns takes (1 - 0.48)^2.5
## of each, about 0.40 in total, and a prop standing at one lantern takes that lantern whole and
## almost nothing of the next. So the worst case is a prop at one pool's centre with a door torch
## or the player's own pool reaching it as well: about 1.4 pools, which is this number and which
## the ladder is built for.
const TORCH_OVERLAP := 1.4
## The step each body rung keeps off the one below it *once the light has landed*. The floor
## clearance under the same light is not a separate number any more: the ladder is built on the
## drawn colours, so `readable_contrast()` is reached where the player reads it.
##
## Round 3 shipped a second, lower pair of targets (1.9 against the floor) because the ladder
## was built dry and the light then ate the difference - the owner's verifier measured a coffin
## at 1.87 where the model said 2.2. A target that is quietly lowered to match what the renderer
## does is not a guarantee; placing the rungs under the light is.
const LIT_BODY_STEP := 1.12
## Drawn luminance the topmost body rung is held under, so the light still has somewhere to
## land on it. Without a ceiling *in drawn space* the two brightest rungs both saturate to the
## same pixel value and the object loses its interior - which is the flattening the owner saw.
const LIT_BODY_CEILING := 0.95
## Chroma (brightest channel minus dimmest) a re-hued body rung keeps. A saturation alone does
## not survive the bottom of the band: HSV saturation is a *ratio*, so 40% of a rung sitting at
## 0.05 luminance is a channel spread of 0.09 - a grey, by the measure `floor_lighting_test`
## uses. Lifted at the rung's own luminance, so the ladder and the spread are untouched.
const BODY_MIN_CHROMA := TileRamp.ACCENT_MIN_CHROMA
## Extra clearance the anchor rung is *placed* with, as a multiple of the ratio it is guaranteed
## at.
##
## Every other body rung is spread away from the floor and lands well past its target. The anchor
## is placed exactly *on* its target, so it is the one rung in the prop with no tolerance at all -
## and a frame does not reproduce a model to the last decimal. Two things eat into it: the floor
## is 8-bit, so the drawn pair is quantised before the ratio is taken; and the room's light is a
## gradient, so the floor pixels beside a prop can be standing in a little more of it than the
## prop's own darkest rung is. `prop_frame_capture` read 2.07 to 2.12 against a 2.2 target off
## three barrels sitting in +0.00 of light on the dark fixtures, and 2.14 off the prop beside a
## torch on `white`, where a floor already at (or a code point under) white cannot be lifted by an
## torch at all - the light is a multiply, and white times anything is white - so the ratio
## closes from one side.
##
## It used to be given only where the body descends from the floor, because a rising body had no
## band to spare: the anchor sat at 0.58 of drawn luminance with a ceiling of 0.95 above it and
## three rungs to fit in between. It does now - the light the ladder is built against is the light
## `dungeon_light.tres` actually casts rather than a flat worst case (`bloom_for`), and the
## measured interior steps came back at 1.21 to 1.32 against a 1.12 target - so the margin is paid
## in both directions and the one rung with no tolerance gets some.
const ANCHOR_CLEARANCE_MARGIN := 1.08

## (biome, kind index) -> Rect2 of the sprite's base in local pixels, read once off the atlas.
static var _bases: Dictionary = {}

var biome: StringName = &"crypt"
var kind_index: int = 0
var kind: StringName = &"barrel"
var hp: int = 1
## Blocks movement and takes hits. Read from `is_solid(kind)` in `setup()`; never set by hand.
var solid: bool = true
var is_broken: bool = false
var sprite: Sprite2D
var _rng: RandomNumberGenerator
var _burst_color: Color = Color.WHITE


func _init() -> void:
	collision_layer = Layers.PROP
	collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(Layers.TILE - 4, Layers.TILE - 4)
	shape.shape = rect
	add_child(shape)


## `tint` is the room's palette-swap material; `rng` decides drops (deterministic per floor).
func setup(
	prop_biome: StringName, index: int, tint: Material, rng: RandomNumberGenerator, burst: Color
) -> void:
	biome = prop_biome
	kind_index = posmod(index, KIND_COUNT)
	var names := kind_names(biome)
	kind = names[kind_index]
	hp = hp_for_kind(kind)
	_rng = rng
	_burst_color = burst
	if sprite != null:
		sprite.queue_free()
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = load_atlas(biome)
	sprite.region_enabled = true
	sprite.region_rect = FloorBuilder.atlas_cell(kind_index, 0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = tint
	add_child(sprite)
	_apply_solidity()


## The base of a kind's sprite in the prop's local pixels: the opaque bounding box of its atlas
## cell, cut to its bottom `OCCLUDER_BASE_ROWS` rows. Read once per (biome, column) off the
## shipped PNG and cached; a cell that cannot be read (a stand-in atlas) is the collision box.
static func base_rect(prop_biome: StringName, index: int) -> Rect2:
	var key := "%s:%d" % [prop_biome, index]
	if _bases.has(key):
		return _bases[key]
	var half := Layers.TILE * 0.5
	var out := Rect2(-half + 2.0, half - 2.0 - OCCLUDER_BASE_ROWS, Layers.TILE - 4.0, 0.0)
	out.size.y = OCCLUDER_BASE_ROWS
	var tex := load_atlas(prop_biome)
	var img := tex.get_image() if tex != null else null
	if img != null:
		var cell := FloorBuilder.atlas_cell(index, 0)
		var box := img.get_region(Rect2i(cell)).get_used_rect()
		if box.size.x > 0 and box.size.y > 0:
			var rows := mini(OCCLUDER_BASE_ROWS, box.size.y)
			out = Rect2(box.position.x - half, box.end.y - rows - half, box.size.x, rows)
	_bases[key] = out
	return out


## The `LightOccluder2D` of a solid prop, built on first use.
func occluder() -> LightOccluder2D:
	var node := get_node_or_null(NodePath(OCCLUDER)) as LightOccluder2D
	if node != null:
		return node
	node = LightOccluder2D.new()
	node.name = OCCLUDER
	node.occluder = OccluderPolygon2D.new()
	add_child(node)
	return node


## Column of `kind_name` in this biome's prop atlas, or -1 when the biome does not list it.
static func column_for(prop_biome: StringName, kind_name: StringName) -> int:
	return kind_names(prop_biome).find(kind_name)


## Kind names of a biome in atlas column order: `data/rooms/rooms_content.tres` when it
## defines them, else the KINDS constant.
static func kind_names(prop_biome: StringName, content: RoomsContent = null) -> Array:
	var res := RoomsContent.resolve(content)
	if res != null:
		var names: Array = res.kinds_for(prop_biome)
		if not names.is_empty():
			return names
	return KINDS.get(prop_biome, KINDS[&"crypt"])


## Hit points of a prop kind: 2 for the sturdy kinds listed in `rooms_content.tres` (or, when
## it lists none, in the STURDY constant), 1 otherwise. `content` is injectable for tests.
static func hp_for_kind(kind_name: StringName, content: RoomsContent = null) -> int:
	var res := RoomsContent.resolve(content)
	if res != null and not res.prop_sturdy_kinds.is_empty():
		return 2 if res.prop_sturdy_kinds.has(kind_name) else 1
	return 2 if STURDY.has(kind_name) else 1


## Whether a kind blocks movement and can be hit: `prop_solid` in `rooms_content.tres` when it
## authors the table, else the SOLID constant. A name neither knows is solid - an unknown prop
## that lets the player through would be the inconsistency this table exists to end.
## `content` is injectable for tests.
static func is_solid(kind_name: StringName, content: RoomsContent = null) -> bool:
	var res := RoomsContent.resolve(content)
	if res != null and not res.prop_solid.is_empty():
		return bool(res.prop_solid.get(kind_name, true))
	return bool(SOLID.get(kind_name, true))


## The kinds of `prop_biome` that are solid (`want_solid`) or flat, in atlas order. This is the
## split `PropPlacement` builds clusters from: solids go against the walls, flats into the open.
static func kinds_where(
	prop_biome: StringName, want_solid: bool, content: RoomsContent = null
) -> Array[StringName]:
	var out: Array[StringName] = []
	for name: Variant in kind_names(prop_biome, content):
		var kind_name := StringName(name)
		if is_solid(kind_name, content) == want_solid:
			out.append(kind_name)
	return out


## Odds a broken prop drops gold: from `rooms_content.tres` when it sets a non-negative value,
## else the GOLD_CHANCE constant. `content` is injectable for tests.
static func gold_chance(content: RoomsContent = null) -> float:
	var res := RoomsContent.resolve(content)
	if res != null and res.prop_gold_chance >= 0.0:
		return res.prop_gold_chance
	return GOLD_CHANCE


## Minimum contrast ratios for the readable tint: `rooms_content.tres` when it authors eight
## values, else the READABLE_CONTRAST constant. `content` is injectable for tests.
static func readable_contrast(content: RoomsContent = null) -> Array[float]:
	var res := RoomsContent.resolve(content)
	if res != null and res.prop_contrast.size() == TileRamp.RAMP_SIZE:
		return res.prop_contrast
	return READABLE_CONTRAST


## Saturation each ramp index of a prop is re-hued to: `rooms_content.tres` when it authors
## eight values, else the ACCENT_BODY_SATURATION constant. `content` is injectable for tests.
static func accent_saturation(content: RoomsContent = null) -> Array[float]:
	var res := RoomsContent.resolve(content)
	if res != null and res.prop_accent_saturation.size() == TileRamp.RAMP_SIZE:
		return res.prop_accent_saturation
	return ACCENT_BODY_SATURATION


## Target colours of a palette-swap material (empty when it carries none).
static func ramp_targets(mat: ShaderMaterial) -> PackedColorArray:
	if mat == null:
		return PackedColorArray()
	var value: Variant = mat.get_shader_parameter(&"target_colors")
	return value as PackedColorArray if value is PackedColorArray else PackedColorArray()


## Colour a torch burns in, at full value: the theme's `heat` role turned into a light source by
## `DungeonLight.light_color()`, which is exactly what `FloorRoot._add_torch_light` hands the
## `PointLight2D`. Its brightest channel is 1.0 by construction (`light_color` forces the value),
## so an energy is the gain that channel multiplies a surface by and the others follow its hue.
##
## `heat` is re-guarded against `floor_c` first, because the palette the torch is lit from is the
## room's *lit* one and that is where the guard lands. It matters: nord's `heat` is dark enough
## to need the push, which takes it toward white and desaturates it, and the torch that comes out
## is half as chromatic as the theme's own fire colour. Reading the raw role instead modelled
## nord's torch at a red:green ratio of 1:0.50 where the frame measured 1:0.71, and a light model
## that is wrong about the hue is wrong about which channel clips first.
##
## `palette` is the room's own palette when the caller has one; with none it reads the live
## theme, the way `bloom_for` already reads the live `DungeonLight`.
static func light_tint(floor_c: Color, palette: ThemePalette = null) -> Color:
	var profile := DungeonLight.resolve()
	var pal := palette if palette != null else TileRamp.live_palette()
	if profile == null or pal == null:
		return Color.WHITE
	var guard: Array = ThemePalette.ROLE_GUARDS.get("heat", [PackedStringArray(), 1.0])
	var toward := Color.BLACK if pal.is_light else Color.WHITE
	var heat := ThemePalette.ensure_contrast_toward(
		pal.get_color(&"heat"), floor_c, float(guard[1]), toward
	)
	return profile.light_color(heat)


## The light a prop is judged under, as the per-channel **gain over the level the theme authored
## it at**: a lit pixel is drawn at `c * (1 + bloom)`, clamped (see `under_light`).
## `Color.BLACK` is a prop the room's own light cannot push past its authored colour at all.
##
## What the screen draws is `c * (unlit + overlap * energy * tint)`: the surface holds
## `LightingProfile.unlit_floor` of itself where nothing lights it, and every source adds its own
## energy through its own colour on top. One pool's worth of that is exactly 1 - the dark undone
## and no more - so the gain is what `TORCH_OVERLAP` puts on top, and it is negative on any
## channel the flame is not bright in, which `under_light` floors at no gain rather than
## modelling a prop as darker than it was authored.
##
## It is never more than the energy that would put `BLOOM_MAX` of light on this floor, because
## past that the rendered check stops asking for an interior and the model has no reason to spend
## band on it. Deriving it from the resource rather than from `BLOOM_MAX` alone is what lets the
## dungeon's own lighting be tuned: dim the torches in `dungeon_light.tres` and the ladder gets
## the band back, which is the trade the interior collapse was always about.
static func bloom_for(floor_c: Color, palette: ThemePalette = null) -> Color:
	var profile := DungeonLight.resolve()
	var tint := light_tint(floor_c, palette)
	var weight := (floor_c.r * tint.r + floor_c.g * tint.g + floor_c.b * tint.b) / 3.0
	if profile == null or weight <= 0.0:
		return Color.BLACK
	var dark := LightingProfile.resolve().unlit_level()
	var energy := profile.torch_energy * TORCH_OVERLAP
	var cap := BLOOM_MAX / weight
	return Color(
		minf(maxf(dark + tint.r * energy - 1.0, 0.0), cap),
		minf(maxf(dark + tint.g * energy - 1.0, 0.0), cap),
		minf(maxf(dark + tint.b * energy - 1.0, 0.0), cap),
		1.0
	)


## True when `bloom` carries any light at all, so the unlit reading can skip the lit one.
static func has_light(bloom: Color) -> bool:
	return bloom.r > 0.0 or bloom.g > 0.0 or bloom.b > 0.0


## `c` as the screen actually shows it: dimmed by the floor's light level, then with the room's
## own light on top. Every guard below is judged on this, never on the authored colour.
static func shown(c: Color, ambient: float, bloom: Color) -> Color:
	return under_light(lit(c, ambient), bloom)


## `shown()` measured, which is what the geometric spread walks along.
static func shown_luminance(c: Color, ambient: float, bloom: Color) -> float:
	return ThemePalette.relative_luminance(shown(c, ambient, bloom))


## True when the room's own light has driven any channel of `c` into the clamp at white. A rung
## that clips has lost its top end: the rung below it keeps rising until it lands on the same
## pixel value, which is the interior collapse the owner photographed.
static func clipped(c: Color, ambient: float, bloom: Color) -> bool:
	var base := lit(c, ambient)
	return (
		base.r * (1.0 + maxf(bloom.r, 0.0)) >= CLIP_LEVEL
		or base.g * (1.0 + maxf(bloom.g, 0.0)) >= CLIP_LEVEL
		or base.b * (1.0 + maxf(bloom.b, 0.0)) >= CLIP_LEVEL
	)


## The brightest colour of `c`'s hue the room's own light does not clip. This is the real ceiling
## on a rising body: above it the light takes the rung to white and the ladder ends, whatever the
## authored numbers say. `shown_luminance` and `clipped` both rise with the authored luminance,
## so one bisection answers it.
static func unclipped(c: Color, ambient: float, bloom: Color) -> Color:
	var low := 0.0
	var high := 1.0
	for _i in range(EXPOSURE_STEPS):
		var mid := (low + high) * 0.5
		if clipped(ThemePalette.with_luminance(c, mid), ambient, bloom):
			high = mid
		else:
			low = mid
	return ThemePalette.with_luminance(c, low)


## A room's tile colours pushed off its own floor colour, so every pixel of a prop, hazard or
## interactable separates from the tile behind it on any theme. Hue comes from the theme (the
## colours are only re-exposed, never lerped toward white), so the room keeps its theme look.
## `ambient` is the floor's light level (FloorRoot dims the whole environment by it): the
## contrast is judged on the dimmed colours, so a dark wallpaper brightens props instead of
## swallowing them.
static func readable_colors(
	room_colors: PackedColorArray, content: RoomsContent = null, ambient: float = 1.0
) -> PackedColorArray:
	var out := PackedColorArray(room_colors)
	if out.size() < TileRamp.RAMP_SIZE:
		return out
	var targets := readable_contrast(content)
	var floor_c := room_colors[FLOOR_RAMP_INDEX]
	var bloom := bloom_for(lit(floor_c, ambient))
	for i in range(2, TileRamp.RAMP_SIZE):
		out[i] = ensure_visible(room_colors[i], floor_c, targets[i], ambient, bloom)
	# The rung nearest the floor is *placed* at its minimum clearance rather than left wherever
	# the theme authored it. It is the anchor the other three are spread away from, and a theme
	# that happened to author it near the far end of the band (every light theme does: its wall
	# and void keys are already dark, so they pass the ladder untouched at 0.10-0.15 luminance
	# against a floor at 0.88) left no band to spread across and handed back four rungs of one
	# value. Moving it toward the floor never breaks the guarantee: it lands exactly on it - or
	# on it plus `ANCHOR_CLEARANCE_MARGIN`, the headroom a drawn frame needs (see there).
	var anchor: int = BODY_RUNGS[0]
	out[anchor] = at_clearance(
		room_colors[anchor], floor_c, targets[anchor] * ANCHOR_CLEARANCE_MARGIN, ambient, bloom
	)
	out = spread_rungs(out, floor_c, ambient, bloom)
	out[INK_RUNG] = ink_color(
		room_colors[INK_RUNG], floor_c, out, targets[INK_RUNG], ambient, bloom
	)
	# Accents are the dungeon's only saturated colour; re-exposing one for contrast can leave
	# it too close to black to read as a colour at all. Restored at its own luminance, so the
	# contrast this loop just guaranteed is untouched.
	for i: int in [TileRamp.FLAME_A, TileRamp.FLAME_B]:
		out[i] = TileRamp.ensure_chroma(out[i])
	return out


## `readable_colors` with the body rungs pulled onto the room's own accent hue: the colours a
## *prop* is drawn in (see `ACCENT_BODY_SATURATION`). Interactables keep the plain readable
## tint, because a chest or a shop counter is a piece of furniture the player has learnt the
## shape of, not a piece of set dressing carrying the biome's colour.
static func accent_colors(
	room_colors: PackedColorArray, content: RoomsContent = null, ambient: float = 1.0
) -> PackedColorArray:
	var out := readable_colors(room_colors, content, ambient)
	if out.size() < TileRamp.RAMP_SIZE:
		return out
	var accent := out[TileRamp.FLAME_A]
	if accent.s < TileRamp.ACCENT_MIN_HUE:
		# A greyscale theme has no hue to lend; painting one on would invent a colour the
		# player's desktop does not contain.
		return out
	var saturations := accent_saturation(content)
	var floor_c := room_colors[FLOOR_RAMP_INDEX]
	var bloom := bloom_for(lit(floor_c, ambient))
	var rising := rises_from(floor_c, ambient)
	for i in range(1, TileRamp.RAMP_SIZE):
		var saturation := saturations[i]
		if saturation <= 0.0:
			continue
		# The ladder is guaranteed in *both* readings of the room, so the re-hue has to put the
		# rung back in both. `recolor` holds the authored luminance, which answers the unlit
		# reading and not the lit one: the room's light multiplies each channel by a different
		# amount (`under_light`), so the same authored luminance in a different hue is drawn at a
		# different one - a re-hued rung arrived up to 0.04 short of the clearance the ladder had
		# bought it. Putting it back where it was *seen* answers the lit reading and loses the
		# unlit one instead: on nord the same rung then dropped from 2.38 to 2.12 dry. So the
		# rung is placed at whichever of the two is further from the floor, which costs nothing -
		# a rung is only ever moved away from the tile behind it, never toward it.
		var seen := shown_luminance(out[i], ambient, bloom)
		var written := ThemePalette.relative_luminance(out[i])
		out[i] = recolor(out[i], accent.h, saturation)
		if BODY_RUNGS.has(i):
			out[i] = TileRamp.ensure_chroma(out[i], BODY_MIN_CHROMA)
		var placed := dry_for_shown(out[i], seen, ambient, bloom)
		placed = maxf(placed, written) if rising else minf(placed, written)
		out[i] = ThemePalette.with_luminance(out[i], placed)
	return out


## `c` moved onto hue `hue` at no less than `saturation`, keeping the luminance it arrives
## with. Luminance is what every contrast guard in the lighting model measures, so a rung can
## change colour without changing how far it stands off the tile behind it.
static func recolor(c: Color, hue: float, saturation: float) -> Color:
	var lum := ThemePalette.relative_luminance(c)
	var tinted := Color.from_hsv(hue, maxf(c.s, saturation), maxf(c.v, 0.04), c.a)
	return ThemePalette.with_luminance(tinted, lum)


## The material a room's *props* are drawn in: `readable_material` plus the accent re-hue.
static func accent_material(
	base: ShaderMaterial, content: RoomsContent = null, ambient: float = 1.0
) -> ShaderMaterial:
	if base == null:
		return null
	return material_with(base, accent_colors(ramp_targets(base), content, ambient))


## Crossfades a prop material (see `accent_material`) to the colours `base` now carries.
static func retint_accent(
	mat: ShaderMaterial,
	base: ShaderMaterial,
	host: Node,
	content: RoomsContent = null,
	ambient: float = 1.0
) -> Tween:
	return crossfade(mat, base, host, accent_colors(ramp_targets(base), content, ambient))


## `fg` re-exposed - brighter or darker - until it reaches `target` contrast against `bg` once
## both are dimmed by `ambient`. Whichever of white/black can reach further past the dimmed
## floor sets the direction, so this works on light themes (where the dimmed floor is a mid
## grey) as well as dark.
##
## Re-exposed, not lerped toward white: scaling a colour's channels keeps its hue and the
## ratios between them, so a red urn on a near-black floor arrives as a brighter red. Lerping
## toward white is what used to arrive as a grey - and a dungeon of grey props is a dungeon
## with no theme in it, which is the whole point of the tinting.
static func ensure_visible(
	fg: Color, bg: Color, target: float, ambient: float = 1.0, bloom: Color = Color.BLACK
) -> Color:
	if reaches(fg, bg, target, ambient, bloom):
		return fg
	return exposed_until(fg, bg, target, ambient, rises_from(bg, ambient), bloom)


## `c` as the screen shows it: the floor's light level scales every environment colour, and
## every contrast guard here is judged on what is drawn, not on what was authored.
static func lit(c: Color, ambient: float) -> Color:
	var k := clampf(ambient, 0.05, 1.0)
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## `c` with the room's own light on it, the way the `PointLight2D` on a torch really draws it.
##
## Godot's default canvas light multiplies the light by the surface before adding it, so the
## light a pixel receives is proportional to the pixel: `c * (1 + gain)` per channel, clamped at
## white. That is why a flat offset was the wrong model - it lit a dark floor and a bright prop
## by the same amount, when the renderer lights the prop nearly twice as hard - and why the two
## brightest rungs of a prop beside a torch arrive as one pixel value. `bloom` is the gain from
## `bloom_for()`, carrying the torch's hue.
static func under_light(c: Color, bloom: Color) -> Color:
	return Color(
		minf(c.r * (1.0 + maxf(bloom.r, 0.0)), 1.0),
		minf(c.g * (1.0 + maxf(bloom.g, 0.0)), 1.0),
		minf(c.b * (1.0 + maxf(bloom.b, 0.0)), 1.0),
		c.a
	)


## True when `fg` stands `target` off `bg` in *both* readings of the room: dimmed by `ambient`
## with no torch on it, and again with `bloom` of one on top of that.
##
## One reading alone is not enough, and each was tried. Dry only is what shipped: the light then
## adds the same value to the prop and to the tile under it, the ratio collapses toward 1, and
## the owner's verifier measured a coffin at 1.87 against a model that said 2.2. Lit only trades
## the bug for its mirror - the rung lands where the torch flatters it and a prop in an unlit
## corner of the same room drops back under the target. A prop is seen in both, so it clears the
## target in both, and the placement functions below bisect on this conjunction.
static func reaches(
	fg: Color, bg: Color, target: float, ambient: float = 1.0, bloom: Color = Color.BLACK
) -> bool:
	if ThemePalette.contrast_ratio(lit(fg, ambient), lit(bg, ambient)) < target:
		return false
	if not has_light(bloom):
		return true
	var ratio := ThemePalette.contrast_ratio(shown(fg, ambient, bloom), shown(bg, ambient, bloom))
	return ratio >= target


## Whether a colour has to get *brighter* to stand off `bg`: true when white reaches further
## past the dimmed background than black does, which is what makes this work on light themes.
static func rises_from(bg: Color, ambient: float = 1.0) -> bool:
	var bg_lit := lit(bg, ambient)
	var up := ThemePalette.contrast_ratio(lit(Color.WHITE, ambient), bg_lit)
	var down := ThemePalette.contrast_ratio(lit(Color.BLACK, ambient), bg_lit)
	return up >= down


## The colour closest to `bg` that still clears `target` contrast against it, on whichever side
## of `bg` the body is travelling. This is the *minimum* clearance, which is what makes it an
## anchor: everything else is spread away from it.
static func at_clearance(
	fg: Color, bg: Color, target: float, ambient: float = 1.0, bloom: Color = Color.BLACK
) -> Color:
	if rises_from(bg, ambient):
		return exposed_until(fg, bg, target, ambient, true, bloom)
	return darkened_until(fg, bg, target, ambient, bloom)


## The brightest `fg` no brighter than `bg` that clears `target` contrast against it; black when
## even black cannot.
##
## `exposed_until` cannot answer this. Contrast against a fixed background is V-shaped in
## luminance - it grows in *both* directions away from `bg` - and that function bisects the
## whole 0..1 range, so asking it for the dark side of a dark background walks it up into the
## bright side instead and hands back a near-white "outline". Bounding the search at `bg`'s own
## luminance is what makes the answer monotone, and therefore correct.
static func darkened_until(
	fg: Color, bg: Color, target: float, ambient: float = 1.0, bloom: Color = Color.BLACK
) -> Color:
	var low := 0.0
	var high := ThemePalette.relative_luminance(bg)
	for _i in range(EXPOSURE_STEPS):
		var mid := (low + high) * 0.5
		if reaches(ThemePalette.with_luminance(fg, mid), bg, target, ambient, bloom):
			low = mid
		else:
			high = mid
	var out := ThemePalette.with_luminance(fg, low)
	if reaches(out, bg, target, ambient, bloom):
		return out
	return ThemePalette.with_luminance(fg, 0.0)


## `fg` re-exposed in the given direction until it clears `target` contrast against `bg`.
## Contrast against a fixed background is monotone in luminance on the side of it the caller
## is searching, so the smallest exposure that clears the target (or the largest, going down)
## is one bisection away. When nothing reaches the target the extreme is returned, which is as
## close as the colour can get.
static func exposed_until(
	fg: Color, bg: Color, target: float, ambient: float, rising: bool, bloom: Color = Color.BLACK
) -> Color:
	var low := 0.0
	var high := 1.0
	for _i in range(EXPOSURE_STEPS):
		var mid := (low + high) * 0.5
		if reaches(ThemePalette.with_luminance(fg, mid), bg, target, ambient, bloom) == rising:
			high = mid
		else:
			low = mid
	var out := ThemePalette.with_luminance(fg, high if rising else low)
	if reaches(out, bg, target, ambient, bloom):
		return out
	return ThemePalette.with_luminance(fg, 1.0 if rising else 0.0)


## The ink rung: always the darkest colour in the prop, because that is what an outline is.
##
## It is placed at whichever is darker of (a) `floor_ratio` clear of the floor on the dark side
## of it and (b) `INK_BODY_RATIO` clear of the body rung nearest to it. On a dark theme (a)
## wins and the ink sits *under* the floor, which is what frees the whole band above for the
## body; on a light theme the floor is paper and there is nothing darker than the body left to
## clear, so (b) wins and the ink sits under the darkest body rung. When neither is reachable -
## a floor already at black - the ink is black, which is as far as a colour can go.
static func ink_color(
	fg: Color,
	floor_c: Color,
	body: PackedColorArray,
	floor_ratio: float,
	ambient: float = 1.0,
	bloom: Color = Color.BLACK
) -> Color:
	var below_floor := darkened_until(fg, floor_c, floor_ratio, ambient, bloom)
	var nearest := nearest_body_rung(body, floor_c, ambient)
	var below_body := darkened_until(fg, nearest, INK_BODY_RATIO, ambient, bloom)
	var darker := below_floor
	if ThemePalette.relative_luminance(below_body) < ThemePalette.relative_luminance(darker):
		darker = below_body
	return darker


## The body rung the ink ends up next to: the one nearest the floor when the body rises off it
## (the ink is then below the floor), the darkest one when the body descends (the ink is below
## the body).
static func nearest_body_rung(
	body: PackedColorArray, floor_c: Color, ambient: float = 1.0
) -> Color:
	if body.size() < TileRamp.RAMP_SIZE:
		return floor_c
	var index: int = BODY_RUNGS[0] if rises_from(floor_c, ambient) else BODY_RUNGS[-1]
	return body[index]


## The body rungs opened out across the room's headroom, so a prop keeps its shading after the
## floor ladder has moved every rung onto roughly the same value. The rung nearest the floor
## stays exactly where the ladder put it; each one after it stands a fixed *contrast ratio*
## further away, and a rung is only ever moved away from the floor, never toward it, so the
## clearance `readable_colors` guaranteed can only grow.
##
## The walk is along the *drawn* luminance, not the authored one. The room's light multiplies
## each rung (`under_light`), which lifts the bright end of a dry ladder further than the dark
## end and then clamps it, squeezing the top rungs into one pixel value while the dry numbers
## still look like a ladder - the flattening the owner photographed. Two rungs a fixed ratio
## apart under the light are a fixed ratio apart on screen, which is the only place a ladder
## means anything.
static func spread_rungs(
	colors: PackedColorArray, floor_c: Color, ambient: float, bloom: Color = Color.BLACK
) -> PackedColorArray:
	var out := PackedColorArray(colors)
	if out.size() < TileRamp.RAMP_SIZE:
		return out
	var rising := rises_from(floor_c, ambient)
	var anchor := out[BODY_RUNGS[0]]
	var edge := BODY_LUMINANCE_MAX if rising else BODY_LUMINANCE_MIN
	var limit := shown_luminance(ThemePalette.with_luminance(anchor, edge), ambient, bloom)
	var lum := shown_luminance(anchor, ambient, bloom)
	var steps := float(BODY_RUNGS.size() - 1)
	if rising:
		limit = minf(limit, LIT_BODY_CEILING)
		# ...and under the clamp, as far as the ladder can afford it. `LIT_BODY_CEILING` is a
		# ceiling on drawn *luminance*, which a coloured light reaches long after it has pinned a
		# rung's brightest channel at 255: two saturated rungs draw as one pixel, which is the
		# interior collapse. `clip_free_limit` is the exact version of the same idea - but it is
		# only ever allowed to trim band the interior does not need, because a ladder that clears
		# `LIT_BODY_STEP` and clips its top rung still reads, and one that neither clips nor
		# steps does not.
		var needed := (lum + 0.05) * pow(LIT_BODY_STEP, steps) - 0.05
		limit = maxf(minf(limit, clip_free_limit(anchor, lum, steps, ambient, bloom)), needed)
	var span := (limit + 0.05) / (lum + 0.05) if rising else (lum + 0.05) / (limit + 0.05)
	if span <= 1.0:  # the ladder already put the first rung past the band
		return out
	var step := pow(span, 1.0 / steps)
	for i in range(1, BODY_RUNGS.size()):
		var rung: int = BODY_RUNGS[i]
		var want := (lum + 0.05) * step - 0.05 if rising else (lum + 0.05) / step - 0.05
		var have := shown_luminance(out[rung], ambient, bloom)
		# A rung the theme already authored past its slot keeps that lead, but never beyond the
		# band: the light needs somewhere to land on the topmost rung, and a rung that ran away
		# with the headroom is a rung the ones after it have none of.
		var placed := clampf(maxf(want, have), want, limit)
		if not rising:
			placed = clampf(minf(want, have), limit, want)
		out[rung] = ThemePalette.with_luminance(
			out[rung], dry_for_shown(out[rung], placed, ambient, bloom)
		)
		lum = placed
	return out


## The highest drawn luminance the band may end at when only the **topmost** rung is allowed to
## run into the clamp.
##
## One saturated rung costs little: its unclipped channels keep rising, so it still stands clear
## of the rung below it. Two is the collapse - a gruvbox urn beside a torch drew its top pair at
## `fcfa90` and `ffffb0`, red and green pinned at 255 in both, 1.02 apart. So the rung *below* the
## top is held at or under the light's clip point and the top one is given the one step that
## leaves: with `n` steps in the band, the last rung may stand `(clip/anchor)^(n/(n-1))` above the
## anchor and no further.
##
## Returns `INF` when the anchor is already past the clip point, which leaves the other ceilings
## to answer.
static func clip_free_limit(
	anchor: Color, lum: float, steps: float, ambient: float, bloom: Color
) -> float:
	if steps <= 1.0:
		return INF
	var clip := shown_luminance(unclipped(anchor, ambient, bloom), ambient, bloom)
	if clip <= lum:
		return INF
	var reach := (clip + 0.05) / (lum + 0.05)
	return (lum + 0.05) * pow(reach, steps / (steps - 1.0)) - 0.05


## The authored luminance whose *drawn* value is `want` once the floor's dimming and the room's
## own light have landed. `shown_luminance` rises with the authored one, so one bisection
## answers it; a `want` the light cannot reach (it clips at white) returns the closest there is.
##
## It returns the high end of the bracket, not its midpoint, because the curve has a step in it:
## `ThemePalette.with_luminance` scales a colour's channels while they fit and lerps it toward
## white once they do not, and the greyer colour the second branch hands back takes *more*
## luminance from the room's light at the same authored one. The midpoint can land on the dark
## side of that step - which is how a nord rung came out 0.03 of drawn luminance short of the
## clearance the ladder had already bought it.
static func dry_for_shown(c: Color, want: float, ambient: float, bloom: Color) -> float:
	var low := 0.0
	var high := 1.0
	for _i in range(EXPOSURE_STEPS):
		var mid := (low + high) * 0.5
		if shown_luminance(ThemePalette.with_luminance(c, mid), ambient, bloom) < want:
			low = mid
		else:
			high = mid
	return high


## A palette-swap material showing `targets`, sharing `base`'s shader and tolerance. Returns
## null for a null base.
static func material_with(base: ShaderMaterial, targets: PackedColorArray) -> ShaderMaterial:
	if base == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = base.shader
	mat.set_shader_parameter(&"ramp", PackedColorArray(TileRamp.RAMP))
	mat.set_shader_parameter(&"target_colors", targets)
	mat.set_shader_parameter(&"previous_colors", targets)
	mat.set_shader_parameter(&"blend", 1.0)
	var tol: Variant = base.get_shader_parameter(&"tolerance")
	mat.set_shader_parameter(&"tolerance", float(tol) if tol is float else 0.02)
	return mat


## Builds the material props and interactables use from the room's tile material. Same shader
## and ramp, colours run through `readable_colors()`. Returns null for a null base.
static func readable_material(
	base: ShaderMaterial, content: RoomsContent = null, ambient: float = 1.0
) -> ShaderMaterial:
	if base == null:
		return null
	return material_with(base, readable_colors(ramp_targets(base), content, ambient))


## Crossfades a readable material to the colours derived from `base`'s current targets, the way
## TileRamp.retint() crossfades the tiles themselves. `host` owns the tween; without one in the
## tree the new colours are applied at once. Returns the tween, or null.
static func retint_readable(
	mat: ShaderMaterial,
	base: ShaderMaterial,
	host: Node,
	content: RoomsContent = null,
	ambient: float = 1.0
) -> Tween:
	return crossfade(mat, base, host, readable_colors(ramp_targets(base), content, ambient))


## Crossfades `mat` from what it shows now to `targets` over `TileRamp.RETINT_SECONDS`, the
## way TileRamp.retint() crossfades the tiles themselves. `base` only has to exist - it is the
## tile material the targets were derived from. Without a `host` in the tree the new colours
## are applied at once. Returns the tween, or null.
static func crossfade(
	mat: ShaderMaterial, base: ShaderMaterial, host: Node, targets: PackedColorArray
) -> Tween:
	if mat == null or base == null:
		return null
	# has_meta first: reading an absent key with a NIL default is an engine error, and the key
	# is absent on the very first retint of every material.
	if mat.has_meta(TileRamp.RETINT_META):
		var running := mat.get_meta(TileRamp.RETINT_META) as Tween
		if running != null and running.is_valid():
			running.kill()
		mat.remove_meta(TileRamp.RETINT_META)
	var displayed := TileRamp.current_colors(mat)
	if not displayed.is_empty():
		mat.set_shader_parameter(&"previous_colors", displayed)
	mat.set_shader_parameter(&"target_colors", targets)
	mat.set_shader_parameter(&"blend", 0.0)
	if host == null or not host.is_inside_tree():
		mat.set_shader_parameter(&"blend", 1.0)
		return null
	var tween := host.create_tween()
	tween.tween_method(
		func(v: float) -> void: mat.set_shader_parameter(&"blend", v),
		0.0,
		1.0,
		TileRamp.RETINT_SECONDS
	)
	mat.set_meta(TileRamp.RETINT_META, tween)
	return tween


static func load_atlas(prop_biome: StringName) -> Texture2D:
	var path := PROPS_DIR + String(prop_biome) + ".png"
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if FileAccess.file_exists(path):
		var img_file := Image.load_from_file(path)
		if img_file != null:
			return ImageTexture.create_from_image(img_file)
	var img := Image.create(
		Layers.TILE * KIND_COUNT, Layers.TILE * (DEBRIS_ROW + 1), false, Image.FORMAT_RGBA8
	)
	img.fill(Color(0, 0, 0, 0))
	for i in range(KIND_COUNT):
		img.fill_rect(Rect2i(i * Layers.TILE + 3, 3, 10, 10), TileRamp.RAMP[6 + i % 2])
		var y := DEBRIS_ROW * Layers.TILE + 9
		img.fill_rect(Rect2i(i * Layers.TILE + 3, y, 4, 3), TileRamp.RAMP[6 + i % 2])
		img.fill_rect(Rect2i(i * Layers.TILE + 9, y + 1, 3, 3), TileRamp.RAMP[6 + i % 2])
	return ImageTexture.create_from_image(img)


## Sets the prop up from the kind name the generator chose (FloorData.Room.prop_kinds).
## Unknown names keep their name (so STURDY and SOLID still apply) and fall back to
## `fallback_index` for the sprite column.
func setup_by_kind(
	prop_biome: StringName,
	kind_name: StringName,
	tint: Material,
	rng: RandomNumberGenerator,
	burst: Color,
	fallback_index: int = 0
) -> void:
	var col := column_for(prop_biome, kind_name)
	setup(prop_biome, col if col >= 0 else fallback_index, tint, rng, burst)
	if col < 0 and not kind_name.is_empty():
		kind = kind_name
		hp = hp_for_kind(kind)
		_apply_solidity()


## The one place the rule becomes physics and light: a solid prop is on Layers.PROP with its
## shape live and an occluder the size of its base; a flat one (and a broken one) is on no
## layer, its shape disabled and its occluder hidden, so nothing collides with it, no hitbox
## finds it and no light is stopped by it.
func _apply_solidity() -> void:
	solid = is_solid(kind)
	var blocks := solid and not is_broken
	collision_layer = Layers.PROP if blocks else 0
	var shape := get_node_or_null(^"Shape") as CollisionShape2D
	if shape != null:
		shape.disabled = not blocks
	if not solid:
		var stale := get_node_or_null(NodePath(OCCLUDER))
		if stale != null:
			stale.queue_free()
		return
	var node := occluder()
	var base := base_rect(biome, kind_index)
	node.occluder.polygon = PackedVector2Array(
		[
			base.position,
			Vector2(base.end.x, base.position.y),
			base.end,
			Vector2(base.position.x, base.end.y)
		]
	)
	node.visible = blocks


## Called by Hitbox. Squashes on hit, breaks at 0 hp. Flat decoration ignores it (nothing
## reaches it through the layers anyway; this is the belt to that braces).
func take_hit(info: DamageInfo) -> void:
	if is_broken or not solid:
		return
	hp -= 1
	if hp > 0:
		_squash(info.knockback.normalized())
		return
	_break()


## Resume: puts a prop the player already smashed back into the state they left it in - its
## debris on the floor, its collision gone. It pays nothing — no gold roll, no particle burst,
## no `broken` signal — because the player was paid for this prop in the session that broke it
## (docs §12). Every prop is rebuilt from the seed on resume and its gold stream is derived
## from (run seed, tile, floor index), so a re-break would hand out the *same* coins again,
## forever. A live break goes through `take_hit()`; this is only ever called by the save
## replay (`FloorRoot.restore_broken_props`).
func restore_broken() -> void:
	if is_broken:
		return
	_leave_debris()


## What every break ends in: the prop stops being a body and shows its debris frame. The node
## stays - the debris *is* the sprite now, drawn flat and walked over like any flat kind.
func _leave_debris() -> void:
	is_broken = true
	hp = 0
	collision_layer = 0
	var shape := get_node_or_null(^"Shape") as CollisionShape2D
	if shape != null:
		shape.set_deferred(&"disabled", true)
	var node := get_node_or_null(NodePath(OCCLUDER)) as LightOccluder2D
	if node != null:
		node.visible = false
	if sprite != null:
		sprite.region_rect = FloorBuilder.atlas_cell(kind_index, DEBRIS_ROW)
		sprite.scale = Vector2.ONE
		sprite.position = Vector2.ZERO


func _squash(dir: Vector2) -> void:
	if sprite == null or not is_inside_tree():
		return
	sprite.scale = Vector2(0.75, 1.25)
	sprite.position = dir * 2.0
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(sprite, ^"scale", Vector2.ONE, 0.18)
	t.parallel().tween_property(sprite, ^"position", Vector2.ZERO, 0.18)


func _break() -> void:
	# Belt to `take_hit`'s braces, on the one path in this class that hands out money. The
	# caller already returns early on `is_broken`, so this is a no-op today and was verified as
	# one; it is here because a second break is not a cosmetic bug but a repeatable gold roll,
	# and the next caller of `_break()` should not have to know that. `prop_test` counts the
	# rolls directly and fails when both guards are gone.
	if is_broken:
		return
	_leave_debris()
	var rng := _rng if _rng != null else RandomNumberGenerator.new()
	if rng.randf() < gold_chance():
		EventBus.spawn_pickup.emit(&"gold", global_position, rng.randi_range(1, 3))
	broken.emit(self)
	if not is_inside_tree():
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.gravity = Vector2(0, 200)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = _burst_color
	add_child(p)
	var t := create_tween()
	t.tween_interval(p.lifetime + 0.1)
	t.tween_callback(p.queue_free)
