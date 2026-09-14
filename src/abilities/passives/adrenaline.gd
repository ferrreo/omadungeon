## Adrenaline: attack speed surge for a few seconds after every dodge.
class_name AdrenalinePassive
extends PassiveAbility

@export var attack_speed_bonus: float = 0.3
@export var per_tier: float = 0.1
@export var duration: float = 3.0
var _generation: int = 0
var _surging: bool = false


func bonus() -> float:
	return attack_speed_bonus + per_tier * (tier - 1)


func is_surging() -> bool:
	return _surging


func on_dodge(player: Node2D) -> void:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return
	entity.stats.remove_owner(owner_id())
	entity.stats.add_percent(&"attack_speed", owner_id(), bonus())
	_surging = true
	_generation += 1
	var generation := _generation
	AbilityFx.flash(entity, &"heat", 0.15)
	entity.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if generation == _generation and is_instance_valid(entity):
				entity.stats.remove_owner(owner_id())
				_surging = false
	)


func remove(player: Node2D) -> void:
	_generation += 1
	_surging = false
	super(player)
