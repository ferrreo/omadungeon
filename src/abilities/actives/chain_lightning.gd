## Chain Lightning (Wizard): arcs from the player through the nearest enemies, shocking each.
## Applies damage directly to hurtboxes (no physics wait), so it refuses to cast with no target.
class_name ChainLightningAbility
extends ActiveAbility

@export var max_targets: int = 4
@export var first_range: float = 120.0
@export var jump_range: float = 96.0
## Damage multiplier applied per jump after the first target.
@export var falloff: float = 0.85
@export var shock_duration: float = 2.0
@export var knockback: float = 30.0


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var chain := find_chain(entity)
	if chain.is_empty():
		return false
	var points := PackedVector2Array([entity.global_position])
	var mult := 1.0
	var previous := entity.global_position
	for target: Entity in chain:
		var dir := target.global_position - previous
		var info := AbilityUtil.make_damage(
			entity, self, tags, dir, knockback, target, 0.0, damage * mult
		)
		info.with_status(StatusEffect.make(StatusEffect.Kind.SHOCK, shock_duration, 0.0, entity))
		AbilityUtil.hit_directly(target, info)
		AbilityFx.flash(target, &"cold", 0.15)
		points.append(target.global_position)
		previous = target.global_position
		mult *= falloff
	var world := AbilityUtil.world_of(entity)
	AbilityFx.bolt(world, points, &"cold", 0.25)
	for i in range(1, points.size()):
		AbilityFx.burst(world, points[i], &"cold", 8, 8.0, 0.3)
		LightEmitter.flash(&"shock", points[i])
	AbilityFx.hit_stop(world.get_tree(), 0.05)
	return true


## Nearest-neighbour chain of up to `max_targets` (+1 per tier above 1) enemies.
func find_chain(entity: Entity) -> Array[Entity]:
	var chain: Array[Entity] = []
	var pool := AbilityUtil.enemies(entity.get_tree())
	var from := entity.global_position
	var reach := first_range
	var wanted := max_targets + (tier - 1)
	while chain.size() < wanted:
		var best: Entity = null
		var best_d := reach * reach
		for e: Entity in pool:
			if chain.has(e):
				continue
			var d := e.global_position.distance_squared_to(from)
			if d <= best_d:
				best_d = d
				best = e
		if best == null:
			break
		chain.append(best)
		from = best.global_position
		reach = jump_range
	return chain
