## Floating clown: ignores pits, bumps the player, and pops into confetti shrapnel on death.
class_name BalloonClown
extends EnemyBase

var _bump: MeleeLunge
var _confetti: ThrowProjectile


func _ready() -> void:
	super._ready()
	_bump = add_attack(MeleeLunge.new()) as MeleeLunge
	_confetti = add_attack(ThrowProjectile.new()) as ThrowProjectile
	_confetti.radial = true
	_confetti.sprite_index = ProjectileSprites.CONFETTI


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_bump.damage = base_damage()
	_bump.knockback = 110.0
	_bump.reach = 14.0
	run_attack(_bump, target.global_position)


func _on_death(_killer: Node2D) -> void:
	_confetti.count = def.param_int(&"confetti_count", 6)
	_confetti.speed = def.param(&"confetti_speed", 150.0)
	_confetti.damage = def.param(&"confetti_damage", 5.0) * (1.0 + 0.12 * floor_index)
	_confetti.knockback = 40.0
	_confetti.lifetime = 0.9
	_confetti.radius = 3.0
	_confetti.fire(global_position + Vector2.RIGHT)
