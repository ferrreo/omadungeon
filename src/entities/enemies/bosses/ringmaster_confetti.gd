## Phase 3 finale: radial waves of confetti shrapnel with a block of safe lanes that shifts one
## lane per wave, so there is always a readable way out. Every wave is telegraphed by danger
## lines drawn along the lanes that are about to fire.
class_name RingmasterConfetti
extends EnemyAttack

enum Step { TELEGRAPH, WAVES }

const TAGS: Array[StringName] = [DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]

## Directions the barrage is split into.
var lanes: int = 14
## Consecutive lanes left empty (the safe corridor).
var safe_lanes: int = 3
var waves: int = 3
var wave_interval: float = 0.6
var telegraph_time: float = 0.6
var speed: float = 95.0
var lifetime: float = 2.4
var damage: float = 10.0
var knockback: float = 45.0
var radius: float = 3.0
## Radians the whole fan turns between waves (on top of the safe-lane shift).
var wave_spin: float = 0.12
## Projectiles from the last wave (tests/debug).
var last_fired: Array[Projectile] = []
## Waves fired since the last `_start()`.
var waves_fired: int = 0

var _step: Step = Step.TELEGRAPH
var _time: float = 0.0
var _offset: float = 0.0
var _safe_start: int = 0


func _start(_target_pos: Vector2) -> void:
	waves_fired = 0
	_time = 0.0
	_step = Step.TELEGRAPH
	_offset = enemy.rng.randf() * TAU
	_safe_start = enemy.rng.randi_range(0, maxi(1, lanes) - 1)
	telegraph_radius = 24.0
	_telegraph_wave()


func tick(delta: float) -> Vector2:
	_time += delta
	match _step:
		Step.TELEGRAPH:
			if _time >= telegraph_time:
				_step = Step.WAVES
				_time = 0.0
				_fire_wave()
		Step.WAVES:
			if _time >= wave_interval:
				_time = 0.0
				if waves_fired >= waves:
					finish()
				else:
					_fire_wave()
	return Vector2.ZERO


## True when lane `index` is part of the current safe corridor.
func is_safe_lane(index: int) -> bool:
	var count := maxi(1, lanes)
	for i in range(safe_lanes):
		if (_safe_start + i) % count == index % count:
			return true
	return false


func _lane_direction(index: int) -> Vector2:
	return Vector2.from_angle(_offset + TAU * float(index) / float(maxi(1, lanes)))


func _telegraph_wave() -> void:
	var boss := enemy as BossBase
	if boss == null:
		return
	var origin := enemy.global_position
	for i in range(lanes):
		if is_safe_lane(i):
			continue
		boss.telegraph_line(origin, origin + _lane_direction(i) * 34.0, telegraph_time, 2.0)


## Fires one radial wave, then shifts the safe corridor and spins the fan for the next one.
func _fire_wave() -> Array[Projectile]:
	last_fired = []
	for i in range(lanes):
		if is_safe_lane(i):
			continue
		last_fired.append(_spawn_shot(_lane_direction(i)))
	waves_fired += 1
	_safe_start = (_safe_start + 1) % maxi(1, lanes)
	_offset += wave_spin
	if has_node("/root/Audio"):
		Audio.play(&"clown_pop", enemy.global_position)
	return last_fired


func _spawn_shot(dir: Vector2) -> Projectile:
	var shot := Projectile.new()
	shot.name = "Confetti"
	shot.sprite_texture = ProjectileSprites.frame(ProjectileSprites.CONFETTI)
	shot.rotate_to_direction = false
	shot.setup(enemy, enemy.team, dir, damage_builder(damage, TAGS, knockback), speed, lifetime)
	var hitbox := Hitbox.new()
	hitbox.name = "Hitbox"
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	col.shape = circle
	hitbox.add_child(col)
	shot.add_child(hitbox)
	enemy.spawn_sibling(shot, enemy.global_position + dir * 8.0)
	return shot
