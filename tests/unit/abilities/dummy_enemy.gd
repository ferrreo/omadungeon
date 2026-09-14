## Test double enemy: an Entity on team ENEMY in the "enemy" group with elite/boss flags.
class_name DummyEnemy
extends Entity

var is_elite: bool = false
var is_boss: bool = false


func _init() -> void:
	team = Layers.Team.ENEMY


func _ready() -> void:
	super()
	add_to_group(&"enemy")
