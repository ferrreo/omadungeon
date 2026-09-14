## Radial hitbox around the enemy (slam, scream, honk). Shows a disc telegraph on impact.
class_name AoEBurst
extends EnemyAttack

const TAGS: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]

var radius: float = 28.0
var damage: float = 8.0
var knockback: float = 180.0
var hit_duration: float = 0.12
var tags: Array[StringName] = TAGS

var hitbox: Hitbox
## Seconds left of the current burst window; drives `finish()` without a stray SceneTreeTimer.
var _window_left: float = 0.0


func _ready() -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	hitbox = make_hitbox(circle)
	set_physics_process(false)


func _start(_target_pos: Vector2) -> void:
	burst()


## Fires the burst immediately (also usable outside the ATTACK state).
func burst() -> void:
	running = true
	((hitbox.get_child(0) as CollisionShape2D).shape as CircleShape2D).radius = radius
	sync_hitbox(hitbox)
	hitbox.damage_builder = damage_builder(damage, tags, knockback)
	telegraph_radius = radius
	hitbox.activate(hit_duration)
	enemy.telegraph.show_area(0.25, radius)
	LightEmitter.flash(&"enemy_burst", enemy.global_position)
	_window_left = maxf(0.01, hit_duration)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_window_left -= delta
	if _window_left <= 0.0:
		set_physics_process(false)
		finish()


func _stop() -> void:
	_window_left = 0.0
	set_physics_process(false)
	hitbox.deactivate()
