## The Ringmaster's whip. A telegraphed line snaps out and *yanks* whatever it touches toward
## the boss (knockback points inward). `hits` > 1 makes it a combo (phase 2), `sweep` turns the
## strike into a full circle around the boss (phase 3).
class_name RingmasterWhip
extends EnemyAttack

enum Step { TELEGRAPH, STRIKE, GAP }

const TAGS: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]

## Length of the lash in px.
var reach: float = 88.0
## Thickness of the lash hitbox in px.
var width: float = 11.0
## Seconds the danger line is drawn before the lash lands.
var telegraph_time: float = 0.45
var strike_time: float = 0.18
## Pause between the hits of a combo (the second hit re-aims and re-telegraphs).
var gap_time: float = 0.3
var damage: float = 16.0
## Impulse (px/s) applied toward the boss on hit.
var pull_strength: float = 280.0
## Number of lashes per attack (2 = the phase 2 combo).
var hits: int = 1
## Sweep the lash a full turn around the boss instead of snapping in one direction.
var sweep: bool = false
var sweep_time: float = 1.2

var hitbox: Hitbox
var _shape: CollisionShape2D
var _dir: Vector2 = Vector2.RIGHT
var _step: Step = Step.TELEGRAPH
var _time: float = 0.0
var _hits_left: int = 0
var _sweep_from: float = 0.0


func _ready() -> void:
	var rect := RectangleShape2D.new()
	rect.size = Vector2(reach, width)
	hitbox = make_hitbox(rect, Vector2(reach * 0.5, 0.0))
	_shape = hitbox.get_child(0) as CollisionShape2D


func _start(target_pos: Vector2) -> void:
	_hits_left = maxi(1, hits)
	_dir = direction_to(target_pos)
	telegraph_radius = reach
	_begin_telegraph()


func _begin_telegraph() -> void:
	_step = Step.TELEGRAPH
	_time = 0.0
	var boss := enemy as BossBase
	if boss == null:
		return
	var origin := enemy.global_position
	if sweep:
		boss.telegraph_arc(origin, reach * 0.9, 0.0, TAU, telegraph_time, width * 0.5)
	else:
		boss.telegraph_line(origin, origin + _dir * reach, telegraph_time, width * 0.5)


func _begin_strike() -> void:
	_step = Step.STRIKE
	_time = 0.0
	sync_hitbox(hitbox)
	hitbox.damage_builder = Callable(self, "build_pull_damage")
	(_shape.shape as RectangleShape2D).size = Vector2(reach, width)
	_shape.position = Vector2(reach * 0.5, 0.0)
	hitbox.multi_hit_interval = 0.25 if sweep else 0.0
	hitbox.position = Vector2.ZERO
	_sweep_from = _dir.angle()
	hitbox.rotation = _sweep_from
	hitbox.activate(_strike_duration())
	enemy.face(enemy.global_position + _dir)


func _strike_duration() -> float:
	return sweep_time if sweep else strike_time


func tick(delta: float) -> Vector2:
	_time += delta
	match _step:
		Step.TELEGRAPH:
			if _time >= telegraph_time:
				_begin_strike()
		Step.STRIKE:
			if sweep:
				hitbox.rotation = (
					_sweep_from + TAU * clampf(_time / maxf(0.05, sweep_time), 0.0, 1.0)
				)
			if _time >= _strike_duration():
				_end_strike()
		Step.GAP:
			if _time >= gap_time:
				_begin_telegraph()
	return Vector2.ZERO


func _end_strike() -> void:
	hitbox.deactivate()
	_hits_left -= 1
	if _hits_left <= 0:
		finish()
		return
	if is_instance_valid(enemy.target):
		_dir = direction_to(enemy.target.global_position)
	_step = Step.GAP
	_time = 0.0


## Damage whose knockback points *toward* the boss, so the lash drags the target in.
func build_pull_damage(target: Node2D) -> DamageInfo:
	var pull := enemy.global_position - target.global_position
	var dir := pull.normalized() if pull.length_squared() > 0.01 else -enemy.facing
	var info := enemy.make_damage(damage, TAGS, dir, pull_strength, enemy.rng)
	for effect: StatusEffect in statuses:
		info.with_status(effect)
	return info


func _stop() -> void:
	hitbox.deactivate()
