## Fireball: lobs a burning orb toward the aim; on impact or at max range it bursts into an
## AoE that burns everything inside.
class_name FireballAbility
extends ActiveAbility

@export var range_px: float = 80.0
@export var speed: float = 150.0
@export var burst_radius: float = 32.0
@export var knockback: float = 90.0
## Fraction of `damage` dealt by the orb itself on a direct hit (the burst deals the rest).
@export var direct_hit_fraction: float = 0.5
@export var burn_dps: float = 4.0
@export var burn_duration: float = 3.0
## Downward acceleration on the orb so it visibly arcs instead of flying flat.
@export var arc_gravity: float = 90.0


func _activate(player: Node2D, aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null:
		return false
	var dir := AbilityUtil.aim_dir(entity, aim)
	var world := AbilityUtil.world_of(entity)
	var burn := _burn(entity)
	var orb := AbilityUtil.spawn_projectile(
		entity,
		self,
		world,
		entity.global_position + dir * 6.0,
		dir,
		speed,
		range_px / speed,
		tags,
		knockback * 0.5,
		0.0,
		[burn],
		damage * direct_hit_fraction
	)
	if orb == null:
		return false
	orb.rotate_to_direction = false
	orb.arc_gravity = arc_gravity
	var sprite := Sprite2D.new()
	sprite.texture = AbilityFx.circle_texture(3)
	AbilityFx.bind_palette(sprite, &"heat")
	orb.add_child(sprite)
	AbilityFx.trail(orb, &"heat")
	LightEmitter.attach(orb, &"fire")
	orb.expired.connect(_on_orb_expired.bind(entity, world))
	AbilityFx.squash(entity, 0.15)
	return true


func _burn(entity: Entity) -> StatusEffect:
	return StatusEffect.make(
		StatusEffect.Kind.BURN, burn_duration, burn_dps * tier_damage_scale(), entity
	)


## The orb expires inside a physics callback (area_entered), where Area2D state cannot change,
## so the burst is deferred to the end of the frame.
func _on_orb_expired(orb: Projectile, entity: Entity, world: Node) -> void:
	_burst.bind(orb.global_position, entity, world).call_deferred()


func _burst(pos: Vector2, entity: Entity, world: Node) -> void:
	if not is_instance_valid(entity) or not is_instance_valid(world) or not world.is_inside_tree():
		return
	AbilityUtil.spawn_hitbox(
		entity, self, world, pos, burst_radius, 0.15, tags, knockback, [_burn(entity)]
	)
	AbilityFx.burst(world, pos, &"heat", 24, burst_radius)
	AbilityFx.ring(world, pos, burst_radius, &"heat")
	LightEmitter.flash(&"explosion", pos)
	AbilityFx.hit_stop(world.get_tree(), 0.04)
