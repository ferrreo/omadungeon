## Fires one or more `Projectile`s from the enemy toward a point. `spread_degrees` fans
## `count` shots; `lob_gravity` > 0 arcs them so they land on the target.
class_name ThrowProjectile
extends EnemyAttack

const TAGS: Array[StringName] = [DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]

var count: int = 1
var spread_degrees: float = 0.0
var speed: float = 160.0
var lifetime: float = 2.0
var damage: float = 6.0
var knockback: float = 40.0
var radius: float = 4.0
var tags: Array[StringName] = TAGS
var sprite_index: int = ProjectileSprites.BOLT
var lob_gravity: float = 0.0
var pierce: int = 0
## Ignore spread and fire `count` shots evenly around the enemy (shrapnel).
var radial: bool = false
## Projectiles spawned by the last `fire()` (tests/debug).
var last_fired: Array[Projectile] = []


func _start(target_pos: Vector2) -> void:
	fire(target_pos)
	finish()


## Spawns the projectiles immediately and returns them.
func fire(target_pos: Vector2) -> Array[Projectile]:
	last_fired = []
	var base_dir := direction_to(target_pos)
	var dist := maxf(8.0, enemy.global_position.distance_to(target_pos))
	for i in range(count):
		var angle := 0.0
		if radial:
			angle = TAU * float(i) / count
		elif count > 1:
			angle = deg_to_rad(
				lerpf(-spread_degrees * 0.5, spread_degrees * 0.5, float(i) / (count - 1))
			)
		var dir := base_dir.rotated(angle)
		var shot := Projectile.new()
		shot.name = "EnemyProjectile"
		shot.sprite_texture = ProjectileSprites.frame(sprite_index)
		shot.pierce = pierce
		var shot_speed := speed
		var life := lifetime
		if lob_gravity > 0.0:
			var t := dist / speed
			var vel := dir * speed + Vector2(0.0, -0.5 * lob_gravity * t)
			shot.arc_gravity = lob_gravity
			shot_speed = vel.length()
			dir = vel.normalized()
			life = t
			shot.rotate_to_direction = false
		shot.setup(
			enemy, enemy.team, dir, damage_builder(damage, tags, knockback), shot_speed, life
		)
		var hitbox := Hitbox.new()
		hitbox.name = "Hitbox"
		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = radius
		col.shape = circle
		hitbox.add_child(col)
		shot.add_child(hitbox)
		enemy.spawn_sibling(shot, enemy.global_position + dir * 6.0)
		last_fired.append(shot)
	return last_fired
