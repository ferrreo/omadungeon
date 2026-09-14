## One biome (docs/GAME_DESIGN.md 5.2): which floors it covers, which traps and props it
## allows and which theme keys tint it. Instances live in data/biomes/<id>.tres.
class_name Biome
extends Resource

const BIOMES_DIR := "res://data/biomes/"
const ALL_IDS: Array[StringName] = [&"crypt", &"forge", &"frost", &"library", &"void"]

@export var id: StringName = &"crypt"
@export var display_name: String = "Crypt"
## Inclusive 0-based floor range this biome normally covers.
@export var floor_min: int = 0
@export var floor_max: int = 2
## Trap kinds the filler may roll here (see docs 9).
@export var trap_kinds: Array[StringName] = [&"spike_floor", &"arrow_wall"]
## Prop kinds scattered in rooms; the builder maps them to sprites.
@export var prop_kinds: Array[StringName] = [&"barrel"]
## Theme colour keys this biome prefers for accent slots (docs 10).
@export var palette_keys: PackedStringArray = ["background", "muted"]
## Tile atlas drawn in the indexed ramp: assets/tiles/<id>.png.
@export var tileset_path: String = "res://assets/tiles/crypt.png":
	set(value):
		tileset_path = value
		atlas_path = value
## Fill template ids that suit this biome (empty = all).
@export var fill_templates: Array[StringName] = []
## Relative weight of trap rooms getting a hazard-heavy layout.
@export var hazard_weight: float = 1.0
## Tiles between two lantern anchors along one wall run (`LanternAnchors`, docs 5.1 #8): a
## forge and a library are lit closely, the void barely.
@export var lantern_spacing: int = LanternAnchors.DEFAULT_SPACING

## Alias of `tileset_path`, kept in sync by its setter. The rooms module reads the atlas as
## `atlas_path` (FloorRoot.build_from), so both names resolve to the same file.
var atlas_path: String = "res://assets/tiles/crypt.png"


## Loads data/biomes/<id>.tres (ResourceLoader caches it). Falls back to a default
## Biome carrying only the id so generation never stops on missing data.
static func load_by_id(biome_id: StringName) -> Biome:
	var path := BIOMES_DIR + String(biome_id) + ".tres"
	if ResourceLoader.exists(path):
		var res := load(path) as Biome
		if res != null:
			return res
	push_warning("Biome '%s' not found at %s; using defaults" % [biome_id, path])
	var fallback := Biome.new()
	fallback.id = biome_id
	fallback.display_name = String(biome_id).capitalize()
	fallback.tileset_path = "res://assets/tiles/%s.png" % biome_id
	return fallback


func allows_trap(kind: StringName) -> bool:
	return kind in trap_kinds


func allows_template(template_id: StringName) -> bool:
	return fill_templates.is_empty() or template_id in fill_templates
