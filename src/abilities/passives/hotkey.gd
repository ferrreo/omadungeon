## Hotkey: every kill refunds a fraction of each active's cooldown.
class_name HotkeyPassive
extends PassiveAbility

@export var refund_fraction: float = 0.2
@export var per_tier: float = 0.1


func fraction() -> float:
	return refund_fraction + per_tier * (tier - 1)


func on_kill(player: Node2D, _victim: Node2D) -> void:
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		slots.refund_all(fraction())
