## Dash toward a point with a circular hitbox; stops on impact or after `max_distance`.
## Hitting a WORLD body stuns the enemy for `wall_stun` seconds.
class_name Charge
extends EnemyAttack

signal impact(target: Node2D)
signal wall_hit

const TAGS: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]

var speed: float = 220.0
var max_distance: float = 140.0
var radius: float = 8.0
var damage: float = 10.0
var knockback: float = 160.0
var wall_stun: float = 1.0
var tags: Array[StringName] = TAGS
## Stop the charge when a target is hit.
var stop_on_impact: bool = true
var hitbox: Hitbox
## How many times this charge slammed into a wall (tests/debug).
var wall_hits: int = 0
var _dir: Vector2 = Vector2.RIGHT
var _travelled: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	hitbox = make_hitbox(circle)
	hitbox.hit_dealt.connect(_on_hit_dealt)


func _start(target_pos: Vector2) -> void:
	_dir = direction_to(target_pos)
	_travelled = 0.0
	_last_pos = enemy.global_position
	((hitbox.get_child(0) as CollisionShape2D).shape as CircleShape2D).radius = radius
	sync_hitbox(hitbox)
	hitbox.damage_builder = damage_builder(damage, tags, knockback)
	telegraph_radius = maxf(radius * 2.0, 16.0)
	hitbox.multi_hit_interval = 0.0
	hitbox.activate(0.0)


func tick(_delta: float) -> Vector2:
	if _travelled >= max_distance:
		finish()
		return Vector2.ZERO
	return _dir * speed


func after_move() -> void:
	var moved := enemy.global_position.distance_to(_last_pos)
	_last_pos = enemy.global_position
	_travelled += moved
	for i in range(enemy.get_slide_collision_count()):
		var col := enemy.get_slide_collision(i)
		var collider := col.get_collider() as CollisionObject2D
		if collider == null:
			continue
		if (collider.collision_layer & Layers.WORLD) != 0 and col.get_normal().dot(_dir) < -0.3:
			_on_wall()
			return


func _on_wall() -> void:
	wall_hits += 1
	enemy.status.apply(StatusEffect.make(StatusEffect.Kind.STUN, wall_stun, 0.0, enemy))
	enemy.knockback_velocity += -_dir * 60.0
	wall_hit.emit()
	finish()


func _on_hit_dealt(target: Hurtbox, _info: DamageInfo) -> void:
	impact.emit(target.entity if target.entity != null else target)
	if stop_on_impact:
		finish()


func _stop() -> void:
	hitbox.deactivate()
