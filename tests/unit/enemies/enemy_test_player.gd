## Minimal player stand-in for enemy tests: group "player", records gold/stat calls.
class_name EnemyTestPlayer
extends Entity

var gold: int = 0
var stats_added: Dictionary = {}
var stats_stolen: Array[StringName] = []
var heals: float = 0.0


func _init() -> void:
	team = Layers.Team.PLAYER


func _ready() -> void:
	super._ready()
	add_to_group(&"player")
	health.healed.connect(func(amount: float) -> void: heals += amount)


func add_gold(amount: int) -> void:
	gold += amount


func add_stat(stat: StringName, amount: int) -> void:
	stats_added[stat] = int(stats_added.get(stat, 0)) + amount


func steal_stat(stat: StringName) -> void:
	stats_stolen.append(stat)
