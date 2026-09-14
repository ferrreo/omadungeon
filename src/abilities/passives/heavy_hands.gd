## Heavy Hands: melee attacks knock enemies much further. Implemented inside the outgoing-hit
## path (`AbilitySlots.outgoing_damage_multiplier`, which the player's weapon code and every
## ability hitbox already call once per hit) so only `melee`-tagged hits are affected — the
## Stats `knockback` percent would also scale ranged and ability knockback.
class_name HeavyHandsPassive
extends PassiveAbility

@export var multiplier: float = 2.0
@export var per_tier: float = 0.5


func value() -> float:
	return multiplier + per_tier * (tier - 1)


## Scales the hit's knockback in place and leaves the damage alone.
func outgoing_damage_multiplier(_player: Node2D, _target: Node2D, info: DamageInfo) -> float:
	if info != null and info.has_tag(DamageInfo.TAG_MELEE):
		info.knockback *= value()
	return 1.0
