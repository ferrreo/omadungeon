## Stack Smash: a two-handed slam that overflows everything standing around you and leaves it
## stunned. Melee-tagged, so Might and every melee modifier in the build scale it — this is
## the active a close-range build is supposed to want.
class_name StackSmashAbility
extends ActiveAbility

@export var radius: float = 40.0
## Extra radius per tier above 1.
@export var radius_per_tier: float = 6.0
@export var stun_duration: float = 1.1
## Extra stun seconds per tier above 1.
@export var stun_per_tier: float = 0.25
@export var knockback: float = 140.0


func blast_radius() -> float:
	return radius + radius_per_tier * float(tier - 1)


func stun_seconds() -> float:
	return stun_duration + stun_per_tier * float(tier - 1)


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var world := AbilityUtil.world_of(entity)
	var statuses: Array[StatusEffect] = [
		StatusEffect.make(StatusEffect.Kind.STUN, stun_seconds(), 0.0, entity)
	]
	var reach := blast_radius()
	AbilityUtil.spawn_hitbox(
		entity, self, world, entity.global_position, reach, 0.18, tags, knockback, statuses
	)
	AbilityFx.ring(world, entity.global_position, reach, &"earth", 0.45)
	AbilityFx.burst(world, entity.global_position, &"earth", 24, reach * 0.8, 0.45)
	LightEmitter.flash(&"explosion", entity.global_position)
	AbilityFx.squash(entity, 0.35, 0.2)
	EventBus.screen_shake.emit(4.0, 0.2)
	AbilityFx.hit_stop(entity.get_tree(), 0.05)
	return true
