## Frost Nova: a radial burst around the player that chills (stacks frost toward a freeze).
class_name FrostNovaAbility
extends ActiveAbility

@export var radius: float = 40.0
@export var knockback: float = 50.0
@export var frost_duration: float = 3.0
## Frost stacks applied per cast at tier 1; tier 3 applies one more.
@export var frost_stacks: int = 1


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null:
		return false
	var world := AbilityUtil.world_of(entity)
	var statuses: Array[StatusEffect] = []
	var stacks := frost_stacks + (1 if tier >= 3 else 0)
	for _i in range(stacks):
		statuses.append(StatusEffect.make(StatusEffect.Kind.FROST, frost_duration, 0.0, entity))
	AbilityUtil.spawn_hitbox(
		entity, self, world, entity.global_position, radius, 0.15, tags, knockback, statuses
	)
	AbilityFx.ring(world, entity.global_position, radius, &"cold", 0.4)
	AbilityFx.burst(world, entity.global_position, &"cold", 28, radius)
	LightEmitter.flash(&"frost", entity.global_position)
	AbilityFx.squash(entity, 0.2)
	AbilityFx.hit_stop(world.get_tree(), 0.04)
	return true
