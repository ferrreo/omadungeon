## kill -9: sends the enemy nearest your aim an unblockable signal. Ordinary targets take a
## heavy single hit; anything already below `execute_threshold` of its health is finished
## outright. Single-target burst, so it is the answer to an elite rather than to a crowd.
class_name KillNineAbility
extends ActiveAbility

## How far from the player a target may stand and still be signalled.
@export var range_px: float = 120.0
## Extra range per tier above 1.
@export var range_per_tier: float = 20.0
## HP fraction at or below which the hit is multiplied by `execute_multiplier`.
@export var execute_threshold: float = 0.35
@export var execute_multiplier: float = 2.5
@export var knockback: float = 120.0


## Reach at the ability's current tier.
func reach() -> float:
	return range_px + range_per_tier * float(tier - 1)


func _activate(player: Node2D, aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var dir := AbilityUtil.aim_dir(entity, aim)
	var target := _pick_target(entity, dir)
	if target == null:
		return false
	var fraction := target.health.fraction() if target.health != null else 1.0
	var multiplier := execute_multiplier if fraction <= execute_threshold else 1.0
	var info := AbilityUtil.make_damage(
		entity,
		self,
		tags,
		target.global_position - entity.global_position,
		knockback,
		target,
		0.0,
		damage * multiplier
	)
	AbilityUtil.hit_directly(target, info)
	var world := AbilityUtil.world_of(entity)
	var line := PackedVector2Array([entity.global_position, target.global_position])
	AbilityFx.bolt(world, line, &"danger", 0.18)
	AbilityFx.burst(world, target.global_position, &"danger", 16, 14.0, 0.35)
	AbilityFx.hit_stop(entity.get_tree(), 0.06 if multiplier > 1.0 else 0.03)
	return true


## The enemy in reach whose direction best matches `dir`, falling back to the nearest one.
func _pick_target(entity: Entity, dir: Vector2) -> Entity:
	var best: Entity = null
	var best_score := -INF
	for enemy: Entity in AbilityUtil.enemies_near(
		entity.get_tree(), entity.global_position, reach()
	):
		var to_enemy := enemy.global_position - entity.global_position
		var score := dir.dot(to_enemy.normalized()) - to_enemy.length() / maxf(1.0, reach())
		if score > best_score:
			best_score = score
			best = enemy
	return best
