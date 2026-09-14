## Reboot: a hard restart. Heals a large share of maximum HP over a couple of seconds, clears
## every status effect on the way through, and slows the player while it runs.
##
## The old version healed a fifth of the pool over three seconds on a 26 s cooldown, which was
## less than one floor-5 pack costs — a slot spent to fall behind more slowly. The heal is now
## big enough to be a comeback, and purging the burn or frost that is killing you is the other
## half of what "reboot" should mean.
class_name RebootAbility
extends ActiveAbility

@export var heal_fraction: float = 0.35
## Extra heal fraction per tier above 1.
@export var heal_per_tier: float = 0.07
@export var duration: float = 2.0
@export var self_slow: float = 0.25


## Share of maximum HP one cast restores at the current tier.
func healed_share() -> float:
	return heal_fraction + heal_per_tier * float(tier - 1)


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree() or entity.health == null:
		return false
	var amount := entity.health.max_hp * healed_share()
	var existing := entity.get_node_or_null("RebootHeal") as HealOverTime
	if existing != null:
		existing.queue_free()
	var heal := HealOverTime.new().setup(amount, duration)
	heal.name = "RebootHeal"
	entity.add_child(heal)
	if entity.status != null:
		entity.status.clear()
		entity.status.apply(StatusEffect.make(StatusEffect.Kind.SLOW, duration, self_slow, entity))
	AbilityFx.ring(AbilityUtil.world_of(entity), entity.global_position, 18.0, &"heal", 0.5)
	LightEmitter.flash(&"heal", entity.global_position)
	AbilityFx.flash(entity, &"heal", 0.3)
	return true
