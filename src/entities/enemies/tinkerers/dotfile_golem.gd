## Elite 32x32 tinkerer: slow, heavy slam; splits into three config gremlins on death.
class_name DotfileGolem
extends EnemyBase

var _slam: AoEBurst
var _split: Summon


func _ready() -> void:
	super._ready()
	_slam = add_attack(AoEBurst.new()) as AoEBurst
	_split = add_attack(Summon.new()) as Summon


## The slam is an area attack: the tell matches the blast radius.
func telegraph_radius() -> float:
	return def.param(&"slam_radius", 30.0) if def != null else super()


func _perform_attack() -> void:
	_slam.radius = def.param(&"slam_radius", 30.0)
	_slam.damage = base_damage()
	_slam.knockback = 200.0
	run_attack(_slam, global_position)


func _on_death(_killer: Node2D) -> void:
	_split.defs = def.summon_defs
	_split.count = def.param_int(&"split_count", 3)
	_split.ring_radius = 18.0
	_split.summon()
