## The visual grammar the world art is read by (docs §1 "readable chaos", §10), asserted on
## the shipped PNGs rather than on the generator that drew them.
##
## A player has to tell three things apart at a glance, on any theme, light or dark: scenery
## they may smash, a tile that will hurt them, and a box worth opening. Colour cannot carry
## that on its own - the environment ramp is recoloured at runtime from the desktop theme - so
## the grammar is *coverage and frame*, which survives every palette:
##
## | class     | footprint                          | palette                        |
## |-----------|------------------------------------|--------------------------------|
## | clutter   | inset: never paints the tile border | the 8-colour ramp, theme-tinted |
## | hazard    | full-bleed + warning frame          | its own colours, never tinted   |
## | reward    | inset, free-standing box            | its own wood and gold           |
##
## The ability icon half of the same question lives here too: a card the player cannot tell
## from another card is the interface version of a crate they cannot tell from a spike plate.
class_name ArtGrammarTest
extends GdUnitTestSuite

const BIOMES: PackedStringArray = ["crypt", "forge", "frost", "library", "void"]
const CELL := 16
## Traps that deliberately wear no warning frame, and why. Both are *meant* to be mistaken
## for something else - that is the mechanic (docs §9 "Mimic chest", §7 the Ricer's dropped
## props) - so framing them would delete the trap rather than make it readable.
const DISGUISED_TRAPS: PackedStringArray = ["mimic_chest", "ricer_trap"]
const TRAPS: PackedStringArray = [
	"spike_floor",
	"arrow_wall",
	"fire_vent",
	"pressure_plate",
	"ice_slide",
	"laser_grid",
	"kernel_spike",
	"pit",
]
## The 8-colour authoring ramp every environment sprite is drawn in (`tools/art/toolkit.py`).
const RAMP: PackedStringArray = [
	"101010", "303030", "505050", "707070", "909090", "b00000", "0000b0"
]
## Shape overlap (Jaccard of the drawn motif) above which two ability icons are the same
## drawing, and the mean per-channel colour difference below which they are the same colour.
## An icon needs to fail only one of the two to be distinct: a red bolt and a blue bolt read
## apart instantly, and so do two gold icons of different shapes. Failing both is one icon
## wearing two names, which is what the owner reported as "too many shared icons".
const ICON_SHAPE_OVERLAP := 0.85
const ICON_COLOUR_DISTANCE := 40.0
## Contrast the warning bracket has to keep against the tile it is stamped on: the lit corner
## pixels, then the tail and the edge ticks that finish the border.
const FRAME_CONTRAST := 2.4
const FRAME_TAIL_CONTRAST := 1.8
## Where `hazard_frame` puts the lit corner of each bracket, and where the tail of it lands.
const FRAME_CORNERS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(14, 1), Vector2i(1, 14), Vector2i(14, 14)
]
const FRAME_TAILS: Array[Vector2i] = [
	Vector2i(3, 1), Vector2i(12, 1), Vector2i(3, 14), Vector2i(12, 14), Vector2i(7, 1)
]


func _load(path: String) -> Image:
	assert_bool(FileAccess.file_exists(path)).override_failure_message("missing " + path).is_true()
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))).is_equal(OK)
	return img


## True when any pixel of the cell's outermost ring is opaque.
func _touches_border(img: Image, col: int, edge: int) -> bool:
	var x0 := col * CELL
	for i in range(CELL):
		for p: Vector2i in [
			Vector2i(x0 + i, 0), Vector2i(x0 + i, CELL - 1), Vector2i(x0 + edge, i)
		]:
			if img.get_pixelv(p).a > 0.0:
				return true
	return false


## Which of the cell's four edges carry paint.
func _painted_edges(img: Image, col: int) -> int:
	var x0 := col * CELL
	var edges := 0
	for i in range(CELL):
		if img.get_pixel(x0 + i, 0).a > 0.0:
			edges |= 1
		if img.get_pixel(x0 + i, CELL - 1).a > 0.0:
			edges |= 2
		if img.get_pixel(x0, i).a > 0.0:
			edges |= 4
		if img.get_pixel(x0 + CELL - 1, i).a > 0.0:
			edges |= 8
	return edges


func test_clutter_never_paints_the_tile_border() -> void:
	# Scenery is an object standing on the floor. Leaving the border ring clear is what keeps
	# a barrel from reading as a floor inlay - and a hazard always fills that ring.
	for biome: String in BIOMES:
		var img := _load("res://assets/sprites/props/%s.png" % biome)
		for col in range(Prop.KIND_COUNT):
			var kind: String = str(Prop.kind_names(StringName(biome))[col])
			(
				assert_bool(_touches_border(img, col, CELL - 1))
				. override_failure_message(
					"%s prop %s paints the tile border, which is the hazard grammar" % [biome, kind]
				)
				. is_false()
			)


func test_every_hazard_tile_is_full_bleed_and_framed() -> void:
	# A trap *is* the floor. Painting all four edges is what a player learns to read as
	# "this square is not scenery", whatever the theme has done to the colours around it.
	for kind: String in TRAPS:
		var img := _load("res://assets/sprites/traps/%s.png" % kind)
		(
			assert_int(_painted_edges(img, TrapBase.FRAME_IDLE))
			. override_failure_message("%s idle frame does not fill the tile" % kind)
			. is_equal(15)
		)


func test_the_two_disguised_traps_are_the_only_unframed_hazards() -> void:
	# The mimic and the Ricer's potted plant are supposed to be mistaken for something else.
	# Pinning that here means a future trap cannot quietly join them without saying so.
	for kind: String in DISGUISED_TRAPS:
		var img := _load("res://assets/sprites/traps/%s.png" % kind)
		(
			assert_int(_painted_edges(img, TrapBase.FRAME_IDLE))
			. override_failure_message("%s is framed, so its disguise is gone" % kind)
			. is_not_equal(15)
		)


func test_a_reward_is_inset_and_keeps_its_own_gold() -> void:
	# The chest is the one thing on the floor the theme does not recolour (docs §10), so it
	# has to carry colours the environment ramp does not contain, and it has to be a
	# free-standing box rather than a tile.
	var img := _load("res://assets/sprites/props/chest.png")
	assert_bool(_touches_border(img, 0, CELL - 1)).is_false()
	var off_ramp := 0
	for y in range(CELL):
		for x in range(CELL):
			var px := img.get_pixel(x, y)
			if px.a > 0.0 and not RAMP.has(px.to_html(false)):
				off_ramp += 1
	(
		assert_int(off_ramp)
		. override_failure_message("the chest is drawn in the environment ramp, so it retints")
		. is_greater(40)
	)


func test_clutter_hazards_and_rewards_are_separable_by_coverage_alone() -> void:
	# The claim the three tests above add up to, asserted as one thing a reviewer can read:
	# strip every colour and the three classes still fall into different buckets.
	var chest := _load("res://assets/sprites/props/chest.png")
	assert_int(_painted_edges(chest, 0)).is_equal(0)
	for biome: String in BIOMES:
		var img := _load("res://assets/sprites/props/%s.png" % biome)
		for col in range(Prop.KIND_COUNT):
			assert_int(_painted_edges(img, col)).is_equal(0)
	for kind: String in TRAPS:
		var img := _load("res://assets/sprites/traps/%s.png" % kind)
		assert_int(_painted_edges(img, TrapBase.FRAME_IDLE)).is_equal(15)


# --- ability icons ------------------------------------------------------------------------


func test_every_ability_has_its_own_icon_cell() -> void:
	var registry := AbilityRegistry.load_default()
	assert_object(registry).is_not_null()
	var seen: Dictionary = {}
	for ability: Ability in registry.abilities:
		if ability == null:
			continue
		var index := AbilityRegistry.icon_index(ability.id)
		(
			assert_int(index)
			. override_failure_message("ability %s has no icon cell" % ability.id)
			. is_greater_equal(0)
		)
		(
			assert_bool(seen.has(index))
			. override_failure_message(
				"abilities %s and %s share icon cell %d" % [seen.get(index, ""), ability.id, index]
			)
			. is_false()
		)
		seen[index] = ability.id


func test_no_two_ability_icons_are_the_same_drawing() -> void:
	var img := _load(AbilityRegistry.ICON_SHEET_PATH)
	var ids := AbilityRegistry.ICON_ORDER
	var motifs: Array = []
	for i in range(ids.size()):
		motifs.append(_motif(img, i))
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			var shape: float = _overlap(motifs[a], motifs[b])
			var colour := _colour_distance(img, a, b)
			(
				assert_bool(shape >= ICON_SHAPE_OVERLAP and colour <= ICON_COLOUR_DISTANCE)
				. override_failure_message(
					(
						"%s and %s are the same icon: shape overlap %.2f, colour distance %.1f"
						% [ids[a], ids[b], shape, colour]
					)
				)
				. is_false()
			)


func test_every_ability_icon_actually_draws_something() -> void:
	var img := _load(AbilityRegistry.ICON_SHEET_PATH)
	for i in range(AbilityRegistry.ICON_ORDER.size()):
		var ink := 0
		for painted: bool in _motif(img, i):
			if painted:
				ink += 1
		(
			assert_int(ink)
			. override_failure_message("%s is a bare backplate" % AbilityRegistry.ICON_ORDER[i])
			. is_greater(16)
		)


## Mask of one icon's drawn motif: interior pixels that are not the shared backplate.
func _motif(img: Image, index: int) -> Array:
	return _motif_at(img, index * CELL)


## Same, for a cell at an arbitrary x offset (an item sheet's cells are addressed by region).
func _motif_at(img: Image, x0: int) -> Array:
	var counts: Dictionary = {}
	for y in range(CELL):
		for x in range(CELL):
			var key := img.get_pixel(x0 + x, y).to_html()
			counts[key] = int(counts.get(key, 0)) + 1
	var plate := ""
	var best := -1
	for key: String in counts:
		if int(counts[key]) > best:
			best = int(counts[key])
			plate = key
	var out: Array = []
	for y in range(CELL):
		for x in range(CELL):
			var px := img.get_pixel(x0 + x, y)
			var inside := x >= 1 and x <= CELL - 2 and y >= 1 and y <= CELL - 2
			out.append(inside and px.a > 0.0 and px.to_html() != plate)
	return out


## Jaccard overlap of two motifs: 1.0 means the same silhouette.
func _overlap(a: Array, b: Array) -> float:
	var both := 0
	var either := 0
	for i in range(a.size()):
		if bool(a[i]) and bool(b[i]):
			both += 1
		if bool(a[i]) or bool(b[i]):
			either += 1
	return float(both) / float(either) if either > 0 else 1.0


## Mean per-channel difference between two icon cells, 0 (identical) to 255.
func _colour_distance(img: Image, a: int, b: int) -> float:
	var total := 0.0
	for y in range(CELL):
		for x in range(CELL):
			var pa := img.get_pixel(a * CELL + x, y)
			var pb := img.get_pixel(b * CELL + x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
	return total * 255.0 / float(CELL * CELL * 3)


# --- one icon, one thing --------------------------------------------------------------------


## Everything the player can be shown an icon for, as `id -> AtlasTexture`: every ability, every
## weapon skill (a weapon's `skill` is an ability in its own right and sits in the same HUD row)
## and every item base. Weapon skills reach the player through the weapon that carries them, so
## they are collected from the item registry rather than from a directory listing.
func _icon_bearers() -> Dictionary:
	var out: Dictionary = {}
	var abilities := AbilityRegistry.load_default()
	assert_object(abilities).override_failure_message("no ability registry").is_not_null()
	for ability: Ability in abilities.abilities:
		if ability != null and ability.icon is AtlasTexture:
			out[ability.id] = ability.icon
	var items := ItemRegistry.load_default()
	assert_object(items).override_failure_message("no item registry").is_not_null()
	for base: ItemBase in items.bases:
		if base == null:
			continue
		if base.icon is AtlasTexture:
			out[base.id] = base.icon
		var weapon := base as WeaponBase
		if weapon != null and weapon.skill != null and weapon.skill.icon is AtlasTexture:
			out[weapon.skill.id] = weapon.skill.icon
	assert_int(out.size()).override_failure_message("nothing carries an icon").is_greater(60)
	return out


## The cell an atlas icon points at, as a key two icons can only share by being the same cell.
func _cell_key(icon: AtlasTexture) -> String:
	var atlas := icon.atlas
	var path := atlas.resource_path if atlas != null else "<none>"
	return "%s@%d,%d" % [path, int(icon.region.position.x), int(icon.region.position.y)]


## The one the owner asked for. All 48 abilities had their own cell after the last pass, but
## seven weapon skills were still pointing at ability cells - a lunge drew Shadowstep, a barrier
## drew Bulwark - and seven weapon families shared an item cell with a cheaper sibling. Both
## sets sit next to each other on the HUD and the pause page, so this checks the whole set at
## once rather than each sheet on its own.
func test_nothing_that_can_appear_together_shares_an_icon_cell() -> void:
	var seen: Dictionary = {}
	for id: StringName in _icon_bearers():
		var key := _cell_key(_icon_bearers()[id] as AtlasTexture)
		(
			assert_bool(seen.has(key))
			. override_failure_message(
				"%s and %s are drawn from the same icon cell (%s)" % [seen.get(key, ""), id, key]
			)
			. is_false()
		)
		seen[key] = id


## A cell of its own is not an icon of its own if the cell is a copy. Compared pixel for pixel,
## which is the cheap half of the same question `test_no_two_ability_icons_are_the_same_drawing`
## asks by shape and colour.
func test_no_two_icon_cells_are_pixel_identical() -> void:
	var bearers := _icon_bearers()
	var ids: Array = bearers.keys()
	var images: Dictionary = {}
	var pixels: Dictionary = {}
	for id: StringName in ids:
		var icon: AtlasTexture = bearers[id]
		var path: String = icon.atlas.resource_path
		if not images.has(path):
			images[path] = _load(path)
		pixels[id] = _cell_pixels(images[path], int(icon.region.position.x))
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			(
				assert_bool(pixels[ids[a]] == pixels[ids[b]])
				. override_failure_message(
					"%s and %s are the same drawing in two cells" % [ids[a], ids[b]]
				)
				. is_false()
			)


## The seven weapon skills are the pairing the owner named: they are drawn on the HUD beside the
## actives, so they are held to the same "not the same drawing" bar the abilities are.
func test_weapon_skill_icons_are_not_redrawn_abilities() -> void:
	var img := _load(AbilityRegistry.ICON_SHEET_PATH)
	var bearers := _icon_bearers()
	var skills: Array = []
	for id: StringName in bearers:
		if String(id).begins_with("skill_"):
			skills.append(id)
	assert_int(skills.size()).override_failure_message("no weapon skills found").is_equal(7)
	for id: StringName in skills:
		var icon: AtlasTexture = bearers[id]
		var mine := _motif_at(img, int(icon.region.position.x))
		for i in range(AbilityRegistry.ICON_ORDER.size()):
			var shape := _overlap(mine, _motif(img, i))
			var colour := _colour_distance_at(img, int(icon.region.position.x), i * CELL)
			(
				assert_bool(shape >= ICON_SHAPE_OVERLAP and colour <= ICON_COLOUR_DISTANCE)
				. override_failure_message(
					(
						"%s and ability %s are the same icon: shape %.2f, colour %.1f"
						% [id, AbilityRegistry.ICON_ORDER[i], shape, colour]
					)
				)
				. is_false()
			)


## Every pixel of one cell, as a comparable array.
func _cell_pixels(img: Image, x0: int) -> PackedColorArray:
	var out := PackedColorArray()
	for y in range(CELL):
		for x in range(CELL):
			out.append(img.get_pixel(x0 + x, y))
	return out


## `_colour_distance` between two cells given by x offset rather than by index.
func _colour_distance_at(img: Image, xa: int, xb: int) -> float:
	var total := 0.0
	for y in range(CELL):
		for x in range(CELL):
			var pa := img.get_pixel(xa + x, y)
			var pb := img.get_pixel(xb + x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
	return total * 255.0 / float(CELL * CELL * 3)


# --- hazard warning frames ------------------------------------------------------------------


## The warning frame the last pass added only warns if it can be seen. The ice slide's cold-blue
## bracket was stamped on its own #a8e8ff ice at a contrast ratio of 1.19 - the one hazard whose
## fill is closest to the warning colour was the one wearing an invisible warning. Measured on
## the drawn pixels of the shipped strips against each tile's own modal fill.
func test_every_warning_frame_stands_off_the_tile_it_frames() -> void:
	for kind: String in TRAPS:
		var img := _load("res://assets/sprites/traps/%s.png" % kind)
		var fill := _modal_fill(img, TrapBase.FRAME_IDLE)
		for p: Vector2i in FRAME_CORNERS:
			var px := img.get_pixel(TrapBase.FRAME_IDLE * CELL + p.x, p.y)
			(
				assert_float(ThemePalette.contrast_ratio(px, fill))
				. override_failure_message(
					(
						"%s: warning bracket %s on a fill of %s"
						% [kind, px.to_html(false), fill.to_html(false)]
					)
				)
				. is_greater_equal(FRAME_CONTRAST)
			)
		for p: Vector2i in FRAME_TAILS:
			var px := img.get_pixel(TrapBase.FRAME_IDLE * CELL + p.x, p.y)
			(
				assert_float(ThemePalette.contrast_ratio(px, fill))
				. override_failure_message(
					"%s: the bracket tail at %s vanishes into the tile" % [kind, p]
				)
				. is_greater_equal(FRAME_TAIL_CONTRAST)
			)


## Most common opaque colour inside a cell, ignoring the two-pixel border the frame occupies.
func _modal_fill(img: Image, col: int) -> Color:
	var counts: Dictionary = {}
	var best := ""
	var most := 0
	for y in range(2, CELL - 2):
		for x in range(2, CELL - 2):
			var px := img.get_pixel(col * CELL + x, y)
			if px.a == 0.0:
				continue
			var key := px.to_html()
			counts[key] = int(counts.get(key, 0)) + 1
			if int(counts[key]) > most:
				most = int(counts[key])
				best = key
	return Color.BLACK if best.is_empty() else Color(best)
