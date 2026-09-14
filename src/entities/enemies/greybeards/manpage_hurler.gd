## Slow greybeard that lobs heavy manpage tomes in an arc from range.
class_name ManpageHurler
extends EnemyBase

var _throw: ThrowProjectile


func _ready() -> void:
	super._ready()
	_throw = add_attack(ThrowProjectile.new()) as ThrowProjectile
	_throw.sprite_index = ProjectileSprites.TOME
	_throw.radius = 5.0


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_throw.count = 1
	_throw.speed = def.param(&"tome_speed", 120.0)
	_throw.lob_gravity = def.param(&"tome_gravity", 260.0)
	_throw.damage = base_damage()
	_throw.knockback = 140.0
	run_attack(_throw, target.global_position)
