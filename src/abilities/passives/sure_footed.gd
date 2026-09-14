## Sure-footed (Ranger innate): faster movement and immunity to floor traps while dodging
## (flag `trap_immune_dodge`, read by the trap module / dodge code).
class_name SureFootedPassive
extends PassiveAbility

@export var move_speed_bonus: float = 0.1
@export var per_tier: float = 0.05


func bonus() -> float:
	return move_speed_bonus + per_tier * (tier - 1)


func apply(player: Node2D) -> void:
	(player as Entity).stats.add_percent(&"move_speed", owner_id(), bonus())
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		slots.set_flag(&"trap_immune_dodge", true)


func remove(player: Node2D) -> void:
	super(player)
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		slots.clear_flag(&"trap_immune_dodge")
