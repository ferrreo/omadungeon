## Clown that charges; on impact (or a wall) it honks, stunning everything nearby.
class_name Honker
extends EnemyBase

var _charge: Charge
var _honk: AoEBurst


func _ready() -> void:
	super._ready()
	_charge = add_attack(Charge.new()) as Charge
	_charge.impact.connect(_on_impact)
	_charge.wall_hit.connect(_on_wall_hit)
	_honk = add_attack(AoEBurst.new()) as AoEBurst


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_charge.speed = def.param(&"charge_speed", 230.0)
	_charge.max_distance = def.param(&"charge_distance", 150.0)
	_charge.damage = base_damage()
	_charge.knockback = 150.0
	_charge.wall_stun = def.param(&"wall_stun", 1.0)
	run_attack(_charge, target.global_position)


func honk() -> void:
	_honk.radius = def.param(&"honk_radius", 26.0)
	_honk.damage = maxf(1.0, base_damage() * 0.3)
	_honk.knockback = 120.0
	_honk.statuses = [
		StatusEffect.make(StatusEffect.Kind.STUN, def.param(&"honk_stun", 0.5), 0.0, self)
	]
	_honk.burst()


func _on_impact(_who: Node2D) -> void:
	honk()


func _on_wall_hit() -> void:
	honk()
