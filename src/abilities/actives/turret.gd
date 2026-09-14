## Turret: drops an auto-firing turret one tile toward the aim for a while.
class_name TurretAbility
extends ActiveAbility

@export var duration: float = 10.0
@export var fire_interval: float = 0.5
@export var range_px: float = 140.0
@export var projectile_speed: float = 220.0
@export var knockback: float = 40.0


func _activate(player: Node2D, aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var dir := AbilityUtil.aim_dir(entity, aim)
	var world := AbilityUtil.world_of(entity)
	var turret := TurretNode.new().setup(entity, self, duration + 2.0 * (tier - 1))
	turret.name = "Turret"
	turret.fire_interval = fire_interval
	turret.range_px = range_px
	turret.projectile_speed = projectile_speed
	turret.knockback = knockback
	world.add_child(turret)
	turret.global_position = entity.global_position + dir * Layers.TILE
	AbilityFx.burst(world, turret.global_position, &"accent", 10, 8.0)
	return true
