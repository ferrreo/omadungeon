## Test double for the player: an Entity on team PLAYER exposing `flags` and `equipment` so
## the abilities module's optional integrations (owner flags, Dotfiles) can be exercised.
class_name DummyPlayer
extends Entity

var flags: Dictionary = {}
## RefCounted like Player.equipment, so a test can swap in the real Equipment.
var equipment: RefCounted = DummyEquipment.new()


func _init() -> void:
	team = Layers.Team.PLAYER


func _ready() -> void:
	super()
	add_to_group(&"player")
