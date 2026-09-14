## Elite 32x32 car: first spills four random clowns, then rams the player repeatedly.
class_name ClownCar
extends EnemyBase

var _summon: Summon
var _ram: Charge
var _summon_cooldown_left: float = 0.0
var _has_summoned: bool = false


func _ready() -> void:
	super._ready()
	_summon = add_attack(Summon.new()) as Summon
	_ram = add_attack(Charge.new()) as Charge
	_ram.radius = 14.0


func _physics_process(delta: float) -> void:
	if _summon_cooldown_left > 0.0:
		_summon_cooldown_left -= delta
	super._physics_process(delta)


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	if not _has_summoned or _summon_cooldown_left <= 0.0:
		_has_summoned = true
		_summon_cooldown_left = def.param(&"summon_interval", 15.0)
		_summon.defs = def.summon_defs
		_summon.count = def.param_int(&"summon_count", 4)
		_summon.ring_radius = 28.0
		run_attack(_summon, target.global_position)
		return
	_ram.speed = def.param(&"ram_speed", 200.0)
	_ram.max_distance = def.param(&"ram_distance", 160.0)
	_ram.damage = base_damage()
	_ram.knockback = 220.0
	_ram.wall_stun = 1.2
	run_attack(_ram, target.global_position)
