## Shrine: buff-for-a-cost. `options` is a fixed list of dictionaries
## {id, label, cost_kind ("gold"|"hp"|"max_hp"), cost, buff (StringName stat or effect), amount}.
## interact() emits EventBus.shrine_used(self); the UI applies the pick and calls `consume()`.
class_name Shrine
extends Interactable

const DEFAULT_OPTIONS: Array[Dictionary] = [
	{
		"id": &"blood_might",
		"label": "Offer blood for Might",
		"cost_kind": &"max_hp",
		"cost": 10,
		"buff": &"might",
		"amount": 2,
	},
	{
		"id": &"gold_swiftness",
		"label": "Tithe gold for Swiftness",
		"cost_kind": &"gold",
		"cost": 40,
		"buff": &"swiftness",
		"amount": 2,
	},
	{
		"id": &"refill_potion",
		"label": "Refill potion",
		"cost_kind": &"gold",
		"cost": 30,
		"buff": &"potion",
		"amount": 1,
	},
	{
		"id": &"cleanse_curse",
		"label": "Cleanse a curse",
		"cost_kind": &"hp",
		"cost": 25,
		"buff": &"cleanse",
		"amount": 1,
	},
]

## Colour a spent shrine is dimmed to.
const SPENT_TINT := Color(0.6, 0.6, 0.6, 1.0)

var options: Array[Dictionary] = default_options()
var used: bool = false
var sprite: Sprite2D


func _init() -> void:
	super()
	prompt_text = "Kneel"
	detect_size = Vector2(34, 34)


## The shrine menu: `data/rooms/rooms_content.tres` when it defines options, else the
## DEFAULT_OPTIONS constant. `content` is injectable for tests.
static func default_options(content: RoomsContent = null) -> Array[Dictionary]:
	var res := RoomsContent.resolve(content)
	if res != null and not res.shrine_options.is_empty():
		return res.shrine_options.duplicate(true)
	return DEFAULT_OPTIONS.duplicate(true)


func setup(atlas: Texture2D, tint: Material) -> void:
	if sprite != null:
		sprite.queue_free()
	sprite = FloorBuilder.atlas_sprite(atlas, FloorBuilder.SPECIAL_SHRINE)
	sprite.material = tint
	add_child(sprite)


## Marks the shrine spent.
func consume() -> void:
	used = true
	enabled = false
	if sprite != null and is_inside_tree():
		var t := create_tween()
		t.tween_property(sprite, ^"modulate", SPENT_TINT, 0.4)


func option_by_id(id: StringName) -> Dictionary:
	for opt: Dictionary in options:
		if opt.get("id", &"") == id:
			return opt
	return {}


## Contract name RunManager uses once the offer flow it started has finished.
func mark_taken() -> void:
	consume()
	super()


## Resume: this shrine was already knelt at in the previous session (docs §12). Same end
## state as `consume()`, without the dim-down tween.
func restore_used() -> void:
	used = true
	enabled = false
	if sprite != null:
		sprite.modulate = SPENT_TINT


func _on_interact(_by: Node2D) -> bool:
	if used:
		return false
	EventBus.shrine_used.emit(self)
	return true
