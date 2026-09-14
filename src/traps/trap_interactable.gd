## The mimic chest's interaction surface: a regular `Interactable` (Layers.INTERACTABLE, HUD
## prompt, `interact(by) -> bool`) so the player module treats it exactly like a real Chest.
## Forwards the interaction to its MimicChest parent.
class_name TrapInteractable
extends Interactable

## Same prompt and detection box as `Chest` so the decoy is indistinguishable.
const CHEST_PROMPT := "Open chest"
const CHEST_DETECT := Vector2(28, 28)


func _init() -> void:
	super()
	prompt_text = CHEST_PROMPT
	detect_size = CHEST_DETECT


## Reveals the mimic. Returns false once the chest is already sprung.
func _on_interact(by: Node2D) -> bool:
	var mimic := get_parent() as MimicChest
	if mimic == null:
		return false
	return mimic.interact(by)
