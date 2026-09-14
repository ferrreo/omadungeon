## Clown that throws a fan of pins and keeps its distance.
class_name Juggler
extends EnemyBase

var _throw: ThrowProjectile


func _ready() -> void:
	super._ready()
	_throw = add_attack(ThrowProjectile.new()) as ThrowProjectile
	_throw.sprite_index = ProjectileSprites.PIN


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_throw.count = def.param_int(&"pin_count", 3)
	_throw.spread_degrees = def.param(&"spread", 30.0)
	_throw.speed = def.param(&"pin_speed", 150.0)
	_throw.damage = base_damage()
	_throw.knockback = 40.0
	_throw.lifetime = 1.6
	run_attack(_throw, target.global_position)
