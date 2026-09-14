## Whirlwind: the player spins for a while, repeatedly hitting everything around them.
class_name WhirlwindAbility
extends ActiveAbility

@export var duration: float = 1.2
@export var radius: float = 24.0
@export var hit_interval: float = 0.2
@export var knockback: float = 70.0
@export var spin_speed: float = 14.0


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	AbilityUtil.spawn_hitbox(
		entity,
		self,
		entity,
		entity.global_position,
		radius,
		duration,
		tags,
		knockback,
		[],
		hit_interval
	)
	var blades := WhirlwindBlades.new()
	blades.name = "WhirlwindBlades"
	blades.radius = radius
	blades.duration = duration
	blades.spin_speed = spin_speed
	AbilityFx.bind_palette(blades, &"text_bright")
	entity.add_child(blades)
	AbilityFx.squash(entity, 0.2, 0.3)
	return true
