## Glass Cannon: much more damage, much less max HP. Higher tiers soften the HP penalty.
class_name GlassCannonPassive
extends PassiveAbility

@export var damage_bonus: float = 0.4
@export var damage_per_tier: float = 0.1
@export var hp_penalty: float = 0.3
@export var hp_penalty_relief_per_tier: float = 0.05


func damage_value() -> float:
	return damage_bonus + damage_per_tier * (tier - 1)


func hp_value() -> float:
	return -maxf(0.0, hp_penalty - hp_penalty_relief_per_tier * (tier - 1))


## `damage_*` stats are additive fractions (Entity.damage_multiplier uses 1 + value), so the
## bonus is a flat add; max_hp is a real number, so its penalty is a percent.
func apply(player: Node2D) -> void:
	var stats := (player as Entity).stats
	var oid := owner_id()
	for stat: StringName in [&"damage_melee", &"damage_ranged", &"damage_ability"]:
		stats.add_flat(stat, oid, damage_value())
	stats.add_percent(&"max_hp", oid, hp_value())
