## Tinkerer that drops decorative props which become traps (hazard spawned by the traps module),
## and pings weak sparks between drops.
class_name Ricer
extends EnemyBase

## Traps dropped so far (tests/debug).
var traps_dropped: int = 0
var _shot: ThrowProjectile
var _trap_cooldown_left: float = 0.0


func _ready() -> void:
	super._ready()
	_shot = add_attack(ThrowProjectile.new()) as ThrowProjectile
	_shot.sprite_index = ProjectileSprites.SPARK


func _physics_process(delta: float) -> void:
	if _trap_cooldown_left > 0.0:
		_trap_cooldown_left -= delta
	super._physics_process(delta)


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	if _trap_cooldown_left <= 0.0:
		_trap_cooldown_left = def.param(&"trap_cooldown", 6.0)
		drop_trap()
		return
	_shot.count = 1
	_shot.speed = def.param(&"shot_speed", 170.0)
	_shot.damage = maxf(1.0, base_damage() * 0.6)
	_shot.knockback = 30.0
	run_attack(_shot, target.global_position)


func drop_trap() -> void:
	traps_dropped += 1
	var pos := (
		(global_position / Layers.TILE).floor() * Layers.TILE + Vector2.ONE * (Layers.TILE * 0.5)
	)
	EventBus.spawn_hazard.emit(&"ricer_trap", pos, def.param(&"trap_duration", 8.0))
	knockback_velocity += -facing * 90.0
