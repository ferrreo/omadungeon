## Test double: an Entity with a gold purse (mirrors the player's `spend_gold`/`add_gold`).
class_name GoldTestEntity
extends Entity

var gold: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true


func add_gold(amount: int) -> void:
	gold += amount
