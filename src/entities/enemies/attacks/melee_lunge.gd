## Short lunge with a rectangular hitbox in front of the enemy.
class_name MeleeLunge
extends EnemyAttack

const TAGS: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]

## Hitbox length in front of the enemy (px) and width.
var reach: float = 14.0
var width: float = 12.0
var lunge_speed: float = 140.0
var lunge_time: float = 0.12
## Seconds after start before the hitbox turns on.
var hit_delay: float = 0.02
var hit_duration: float = 0.12
var damage: float = 8.0
var knockback: float = 90.0
var tags: Array[StringName] = TAGS

var hitbox: Hitbox
var _shape: CollisionShape2D
var _dir: Vector2 = Vector2.RIGHT
var _time: float = 0.0
var _armed: bool = false


func _ready() -> void:
	var rect := RectangleShape2D.new()
	rect.size = Vector2(reach, width)
	hitbox = make_hitbox(rect, Vector2(reach * 0.5, 0.0))
	_shape = hitbox.get_child(0) as CollisionShape2D


func _start(target_pos: Vector2) -> void:
	_dir = direction_to(target_pos)
	_time = 0.0
	_armed = false
	hitbox.position = Vector2.ZERO
	hitbox.rotation = _dir.angle()
	(_shape.shape as RectangleShape2D).size = Vector2(reach, width)
	_shape.position = Vector2(reach * 0.5, 0.0)
	sync_hitbox(hitbox)
	hitbox.damage_builder = damage_builder(damage, tags, knockback)
	telegraph_radius = reach + width * 0.5
	if hit_delay <= 0.0:
		_arm()


func _arm() -> void:
	_armed = true
	hitbox.activate(hit_duration)


func tick(delta: float) -> Vector2:
	_time += delta
	if not _armed and _time >= hit_delay:
		_arm()
	if _time >= hit_delay + hit_duration:
		finish()
		return Vector2.ZERO
	return _dir * lunge_speed if _time < lunge_time else Vector2.ZERO


func _stop() -> void:
	hitbox.deactivate()
