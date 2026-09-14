## Smoke Bomb: a cloud that blinds and slows everything standing in it and covers your exit.
## No damage at all — it is the ability you take because you keep dying in the middle of a
## room, and it is worth a slot only if the rest of the build can convert the opening.
class_name SmokeBombAbility
extends ActiveAbility

@export var radius: float = 56.0
## Extra radius per tier above 1.
@export var radius_per_tier: float = 8.0
@export var duration: float = 4.0
## Extra seconds per tier above 1.
@export var duration_per_tier: float = 1.0
## Fraction of their speed enemies in the cloud lose.
@export var slow_magnitude: float = 0.45
## Fraction of their damage enemies in the cloud lose.
@export var weaken_magnitude: float = 0.35
## Fraction of extra move speed the player gets while the cloud stands.
@export var self_haste: float = 0.3


func cloud_radius() -> float:
	return radius + radius_per_tier * float(tier - 1)


func cloud_seconds() -> float:
	return duration + duration_per_tier * float(tier - 1)


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var seconds := cloud_seconds()
	var reach := cloud_radius()
	var caught := 0
	for enemy: Entity in AbilityUtil.enemies_near(entity.get_tree(), entity.global_position, reach):
		if enemy.status == null:
			continue
		enemy.status.apply(
			StatusEffect.make(StatusEffect.Kind.SLOW, seconds, slow_magnitude, entity)
		)
		enemy.status.apply(
			StatusEffect.make(StatusEffect.Kind.WEAKEN, seconds, weaken_magnitude, entity)
		)
		AbilityFx.flash(enemy, &"text_dim", 0.25)
		caught += 1
	if entity.status != null:
		entity.status.apply(StatusEffect.make(StatusEffect.Kind.HASTE, seconds, self_haste, entity))
	var world := AbilityUtil.world_of(entity)
	AbilityFx.ring(world, entity.global_position, reach, &"text_dim", 0.5)
	AbilityFx.burst(world, entity.global_position, &"text_dim", 30, reach * 0.6, 0.7)
	AbilityFx.flash(entity, &"text_dim", 0.3)
	if caught > 0:
		AbilityFx.hit_stop(entity.get_tree(), 0.03)
	return true
