## Second Wind (Fighter innate): standing armour, plus bonus damage while below a health
## threshold.
##
## The armour half is what makes the Fighter a melee class rather than a ranged class holding
## a sword. A melee weapon fights inside every enemy's reach and so takes far more hits per
## point of damage dealt than a bow does; a conditional damage bonus that only turns on when
## the run is already lost does not pay for that. The armour is always on.
class_name SecondWindPassive
extends PassiveAbility

@export var damage_bonus: float = 0.25
@export var per_tier: float = 0.1
@export var hp_threshold: float = 0.4
## Flat armour the Fighter carries at all times.
@export var armor: float = 12.0
## Extra armour per tier above 1.
@export var armor_per_tier: float = 4.0


func multiplier() -> float:
	return 1.0 + damage_bonus + per_tier * (tier - 1)


## Flat armour at the current tier.
func armor_value() -> float:
	return armor + armor_per_tier * float(tier - 1)


func apply(player: Node2D) -> void:
	var entity := player as Entity
	if entity == null:
		return
	entity.stats.add_flat(&"armor", owner_id(), armor_value())


func outgoing_damage_multiplier(player: Node2D, _target: Node2D, _info: DamageInfo) -> float:
	var entity := player as Entity
	if entity == null or entity.health == null:
		return 1.0
	return multiplier() if entity.health.fraction() < hp_threshold else 1.0
