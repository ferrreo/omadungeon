## Area2D that receives hits and forwards them to its Entity's Health.
class_name Hurtbox
extends Area2D

signal hit_received(info: DamageInfo)

@export var team: Layers.Team = Layers.Team.ENEMY
## When set, damage goes to this Health; otherwise the parent Entity's.
@export var health_override: Health
var entity: Entity


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = Layers.hurtbox_layer_for(team)
	collision_mask = 0
	entity = get_parent() as Entity


func get_health() -> Health:
	if health_override != null:
		return health_override
	return entity.health if entity != null else null


## Called by Hitbox. Returns damage applied.
func receive(info: DamageInfo) -> float:
	var health := get_health()
	if health == null:
		return 0.0
	var dealt := health.take_damage(info)
	if dealt > 0.0:
		if entity != null:
			entity.on_hit_received(info)
		hit_received.emit(info)
	return dealt
