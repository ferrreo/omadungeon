## Hostile Takeover (Oligarch): converts the nearest non-elite enemy to fight for the player
## for a while (`enemy.convert(team, seconds)`), or stuns it when the enemy cannot be converted.
class_name HostileTakeoverAbility
extends ActiveAbility

@export var range_px: float = 128.0
@export var duration: float = 8.0
## Extra seconds per tier above 1.
@export var duration_per_tier: float = 2.0


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var target := find_target(entity)
	if target == null:
		return false
	var seconds := duration + duration_per_tier * (tier - 1)
	if target.has_method("convert"):
		target.call("convert", Layers.Team.PLAYER, seconds)
	else:
		target.status.apply(StatusEffect.make(StatusEffect.Kind.STUN, seconds, 0.0, entity))
	var world := AbilityUtil.world_of(entity)
	AbilityFx.burst(world, target.global_position, &"loot", 18, 14.0)
	AbilityFx.ring(world, target.global_position, 16.0, &"loot", 0.4)
	AbilityFx.flash(target, &"loot", 0.3)
	AbilityFx.bolt(
		world, PackedVector2Array([entity.global_position, target.global_position]), &"loot", 0.3
	)
	return true


## Nearest non-elite, non-boss enemy in range.
func find_target(entity: Entity) -> Entity:
	for e: Entity in AbilityUtil.enemies_near(entity.get_tree(), entity.global_position, range_px):
		if not AbilityUtil.is_elite(e):
			return e
	return null
