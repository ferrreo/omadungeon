## sudo: run the next few seconds as root. A flat, enormous damage buff with a long cooldown —
## the ability you hold for the boss arena rather than spend on a corridor pack. The speed
## burst that comes with it is what lets you stay in range long enough to use it.
class_name SudoAbility
extends ActiveAbility

@export var duration: float = 5.0
## Extra seconds per tier above 1.
@export var duration_per_tier: float = 1.0
## Fraction of extra damage while it runs.
@export var empower: float = 0.8
## Extra empower per tier above 1.
@export var empower_per_tier: float = 0.15
## Fraction of extra move speed while it runs.
@export var haste: float = 0.3


func root_seconds() -> float:
	return duration + duration_per_tier * float(tier - 1)


func empower_magnitude() -> float:
	return empower + empower_per_tier * float(tier - 1)


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or entity.status == null:
		return false
	var seconds := root_seconds()
	entity.status.apply(
		StatusEffect.make(StatusEffect.Kind.EMPOWER, seconds, empower_magnitude(), entity)
	)
	entity.status.apply(StatusEffect.make(StatusEffect.Kind.HASTE, seconds, haste, entity))
	if not entity.is_inside_tree():
		return true
	var world := AbilityUtil.world_of(entity)
	AbilityFx.ring(world, entity.global_position, 26.0, &"loot", 0.45)
	AbilityFx.burst(world, entity.global_position, &"loot", 20, 16.0, 0.5)
	AbilityFx.flash(entity, &"loot", 0.35)
	AbilityFx.squash(entity, 0.3, 0.2)
	return true
