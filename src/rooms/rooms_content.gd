## Tuning data for the rooms module (docs §1: content is data, code is behaviour).
## `res://data/rooms/rooms_content.tres` holds the numbers a designer balances — chest kind
## weights, shrine offers, prop kind names and durability, shop prices — and wins over the
## script constants that mirror them. Every field has an "unset" value (empty collection, or a
## negative number), so a partially authored file only overrides what it actually defines and a
## missing file leaves the constants in force.
class_name RoomsContent
extends Resource

const PATH := "res://data/rooms/rooms_content.tres"

## FloorData.RoomType (int) -> {Chest.Kind (int): weight (int)}. Empty = use Chest.WEIGHTS.
@export var chest_weights: Dictionary = {}
## Extra CURSED chest weight per floor index. Negative = use Chest.CURSED_PER_FLOOR.
@export var chest_cursed_per_floor: int = -1
## Odds a Treasure-room chest is trapped (0..1). Negative = use FloorRoot.TREASURE_TRAP_CHANCE.
@export var treasure_trap_chance: float = -1.0
## Shrine options: {id, label, cost_kind, cost, buff, amount}. Empty = Shrine.DEFAULT_OPTIONS.
@export var shrine_options: Array[Dictionary] = []
## Biome id -> Array[StringName] of `Prop.KIND_COUNT` prop kind names. Empty = Prop.KINDS.
@export var prop_kinds: Dictionary = {}
## Prop kinds that take two hits to break. Empty = Prop.STURDY.
@export var prop_sturdy_kinds: Array[StringName] = []
## Prop kind name -> bool: true blocks movement and breaks, false is walk-over decoration
## (docs: assets/tiles/README.md, "Solid or flat"). Empty = Prop.SOLID.
@export var prop_solid: Dictionary = {}
## Odds a broken prop drops gold (0..1). Negative = use Prop.GOLD_CHANCE.
@export var prop_gold_chance: float = -1.0
## Expected props per free interior tile at `GenParams.prop_density` 1.0, before the room-type
## multiplier. Negative = use PropPlacement.PER_FREE_TILE.
@export var prop_per_free_tile: float = -1.0
## Fewest / most solid props in one wall cluster (docs §10 "clutter"). Non-positive = use
## PropPlacement.CLUSTER_MIN / CLUSTER_MAX.
@export var prop_cluster_min: int = -1
@export var prop_cluster_max: int = -1
## Share of a room's prop budget spent on flat kinds scattered in the open (0..1); the rest is
## solid clusters against the walls. Negative = use PropPlacement.OPEN_FLAT_SHARE.
@export var prop_open_flat_share: float = -1.0
## How much likelier a cluster starts in a corner than beside a plain wall (>= 1).
## Non-positive = use PropPlacement.CORNER_WEIGHT.
@export var prop_corner_weight: float = -1.0
## Minimum contrast ratio of each ramp index against the room's floor colour for props,
## hazards and interactables (8 entries, index 0 unused). Empty = use Prop.READABLE_CONTRAST.
@export var prop_contrast: Array[float] = []
## Saturation each ramp index of a *prop* is re-hued onto the room's accent at (8 entries; 0
## leaves that rung alone). Empty = use Prop.ACCENT_BODY_SATURATION.
@export var prop_accent_saturation: Array[float] = []
## Gold cost of a shop's first reroll. Non-positive = use Shop.BASE_REROLL_PRICE.
@export var shop_reroll_base_price: int = -1
## Multiplier applied to the reroll price per use. Non-positive = use Shop.REROLL_GROWTH.
@export var shop_reroll_growth: float = -1.0
## Shop price multiplier per ItemInstance.Rarity index. Empty = Shop.RARITY_PRICE_MULT.
@export var shop_rarity_price_mult: Array[float] = []


## The project's content resource, or null when it has not been authored yet.
## ResourceLoader caches it, so callers may resolve it per use.
static func load_default() -> RoomsContent:
	if not ResourceLoader.exists(PATH):
		return null
	return load(PATH) as RoomsContent


## `content` when given, else the shipped resource (possibly null). Every rooms-module lookup
## goes through this so tests can inject a resource without writing to data/.
static func resolve(content: RoomsContent = null) -> RoomsContent:
	return content if content != null else load_default()


## Chest weight table for a room type, or an empty Dictionary when this resource has none.
func weights_for(room_type: int) -> Dictionary:
	return chest_weights.get(room_type, {})


## Prop kind names for a biome, or an empty Array when this resource has none.
func kinds_for(biome: StringName) -> Array:
	return prop_kinds.get(biome, [])
