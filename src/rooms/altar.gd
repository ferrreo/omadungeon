## Ability altar: one use per floor. interact() emits EventBus.altar_used(self); the UI opens
## the ability choice and calls `consume()` once the player picked (or skipped).
class_name Altar
extends Interactable

## Colour a spent altar is dimmed to.
const SPENT_TINT := Color(0.6, 0.6, 0.6, 1.0)

var used: bool = false
var sprite: Sprite2D


func _init() -> void:
	super()
	prompt_text = "Pray"
	detect_size = Vector2(34, 34)


func setup(atlas: Texture2D, tint: Material) -> void:
	if sprite != null:
		sprite.queue_free()
	sprite = FloorBuilder.atlas_sprite(atlas, FloorBuilder.SPECIAL_ALTAR)
	sprite.material = tint
	add_child(sprite)


## Marks the altar spent (dims it and disables the prompt).
func consume() -> void:
	used = true
	enabled = false
	if sprite != null and is_inside_tree():
		var t := create_tween()
		t.tween_property(sprite, ^"modulate", SPENT_TINT, 0.4)


## Contract name RunManager uses once the offer flow it started has finished.
func mark_taken() -> void:
	consume()
	super()


## Resume: this altar was already prayed at in the previous session (docs §12). Same end
## state as `consume()`, without the dim-down tween — the player never saw it light up.
func restore_used() -> void:
	used = true
	enabled = false
	if sprite != null:
		sprite.modulate = SPENT_TINT


func _on_interact(_by: Node2D) -> bool:
	if used:
		return false
	EventBus.altar_used.emit(self)
	return true
