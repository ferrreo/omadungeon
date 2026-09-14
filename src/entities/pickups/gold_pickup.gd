## Coin: homes to the player and calls `player.add_gold(amount)` when they expose it.
class_name GoldPickup
extends PickupBase


func _init() -> void:
	kind = &"gold"
	color_role = &"loot"
	radius = 2.5


func _collect(player: Node2D) -> void:
	if not PickupBase.call_player(player, &"add_gold", [amount]):
		push_warning("GoldPickup: player has no add_gold(amount)")
