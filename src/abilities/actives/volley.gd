## Volley (Ranger): a fan of arrows toward the aim, each with bonus crit chance.
class_name VolleyAbility
extends ActiveAbility

@export var arrow_count: int = 5
@export var spread_degrees: float = 40.0
@export var crit_bonus: float = 0.2
@export var speed: float = 260.0
@export var lifetime: float = 0.7
@export var knockback: float = 40.0


func _activate(player: Node2D, aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var dir := AbilityUtil.aim_dir(entity, aim)
	var world := AbilityUtil.world_of(entity)
	var count := arrow_count + (tier - 1)
	var spread := deg_to_rad(spread_degrees)
	for i in range(count):
		var t := 0.0 if count <= 1 else float(i) / float(count - 1) - 0.5
		var arrow_dir := dir.rotated(t * spread)
		var arrow := AbilityUtil.spawn_projectile(
			entity,
			self,
			world,
			entity.global_position + arrow_dir * 8.0,
			arrow_dir,
			speed,
			lifetime,
			tags,
			knockback,
			crit_bonus
		)
		if arrow == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = AbilityFx.bar_texture(7, 1)
		AbilityFx.bind_palette(sprite, &"loot")
		arrow.add_child(sprite)
	AbilityFx.squash(entity, 0.2, 0.15)
	AbilityFx.burst(world, entity.global_position + dir * 8.0, &"loot", 8, 6.0, 0.25)
	return true
