## Close Quarters: the compensator melee has been owed. A melee weapon fights inside every
## enemy's reach, so it eats far more hits than a bow does for the same damage dealt; this
## pays that back on both sides of the trade — melee hits land harder, and armour blunts what
## comes back. Only `melee`-tagged damage is boosted, so it does nothing for a ranged build.
class_name CloseQuartersPassive
extends PassiveAbility

## Fraction of extra damage on melee-tagged hits.
@export var melee_bonus: float = 0.25
## Extra fraction per tier above 1.
@export var per_tier: float = 0.1
## Flat armour granted while the passive is held.
@export var armor: float = 14.0
## Extra armour per tier above 1.
@export var armor_per_tier: float = 6.0


## Extra melee damage fraction at the current tier.
func bonus() -> float:
	return melee_bonus + per_tier * float(tier - 1)


## Flat armour at the current tier.
func armor_value() -> float:
	return armor + armor_per_tier * float(tier - 1)


func apply(player: Node2D) -> void:
	var entity := player as Entity
	if entity == null:
		return
	entity.stats.add_flat(&"armor", owner_id(), armor_value())


func outgoing_damage_multiplier(_player: Node2D, _target: Node2D, info: DamageInfo) -> float:
	if info != null and info.has_tag(DamageInfo.TAG_MELEE):
		return 1.0 + bonus()
	return 1.0
