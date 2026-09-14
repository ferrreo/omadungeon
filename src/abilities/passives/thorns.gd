## Thorns: melee attackers take a retaliation hit built from the player's own max HP plus a
## share of the blow they landed.
##
## The max-HP term is the whole point. Reflecting a share of *incoming* damage alone made
## Thorns dead content: it scaled with how hard the dungeon hits, which is exactly the number
## the player spends the run reducing, so the better the build got the less Thorns did. A
## floor-5 elite hitting for 30 gave back 6 a hit against its 328 HP pool — a hundred and fifty
## seconds of standing still. Anchoring it to max HP makes it a real defensive card: the
## tankier you build, the more it hurts to hit you, and the number moves when the player's
## own stats move rather than when the enemy's do.
class_name ThornsPassive
extends PassiveAbility

## Share of the melee damage taken that comes straight back.
@export var reflect_fraction: float = 0.2
## Extra reflected share per tier above 1.
@export var per_tier: float = 0.1
## Share of the player's own max HP every retaliation carries on top of the reflected damage.
@export var max_hp_fraction: float = 0.05
## Extra max-HP share per tier above 1.
@export var max_hp_per_tier: float = 0.025
@export var knockback: float = 40.0


## Share of the incoming hit that is reflected at the current tier.
func fraction() -> float:
	return reflect_fraction + per_tier * (tier - 1)


## Share of the wearer's max HP every retaliation carries at the current tier.
func max_hp_share() -> float:
	return max_hp_fraction + max_hp_per_tier * (tier - 1)


## Damage one retaliation deals: a slice of the wearer's own pool plus a slice of the blow.
func retaliation_damage(max_hp: float, damage_taken: float) -> float:
	return maxf(1.0, maxf(0.0, max_hp) * max_hp_share() + maxf(0.0, damage_taken) * fraction())


func on_hit_received(player: Node2D, info: DamageInfo) -> void:
	if info == null or not info.has_tag(DamageInfo.TAG_MELEE):
		return
	var attacker := info.source as Entity
	var entity := player as Entity
	if attacker == null or entity == null or attacker == entity or not is_instance_valid(attacker):
		return
	if attacker.hurtbox == null or attacker.is_dying:
		return
	var dealt := info.applied if info.applied > 0.0 else info.amount
	var reflected := retaliation_damage(entity.stats.get_value(&"max_hp"), dealt)
	var tags: Array[StringName] = [DamageInfo.TAG_ABILITY, DamageInfo.TAG_PHYSICAL]
	var out := DamageInfo.create(reflected, tags, entity, entity.team)
	out.with_knockback(attacker.global_position - entity.global_position, knockback)
	AbilityUtil.hit_directly(attacker, out)
	if entity.is_inside_tree():
		AbilityFx.burst(
			AbilityUtil.world_of(entity), entity.global_position, &"earth", 6, 8.0, 0.25
		)
