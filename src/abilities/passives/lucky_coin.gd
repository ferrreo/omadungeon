## Lucky Coin: one free chest reroll every floor (flag `free_reroll_per_floor`, which
## RunManager honours) plus luck that grows with the tier, so higher tiers sweeten the offers
## themselves rather than relying on a reroll counter nothing reads.
class_name LuckyCoinPassive
extends PassiveAbility

@export var luck_per_tier: float = 0.15


func luck_bonus() -> float:
	return luck_per_tier * tier


func apply(player: Node2D) -> void:
	var entity := player as Entity
	if entity != null:
		entity.stats.add_flat(&"luck", owner_id(), luck_bonus())
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		slots.set_flag(&"free_reroll_per_floor", true)


func remove(player: Node2D) -> void:
	super(player)
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		slots.clear_flag(&"free_reroll_per_floor")
