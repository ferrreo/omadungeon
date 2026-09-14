## Cron Job: a scheduled repair that runs every time a room falls quiet. Healing between
## fights rather than during them, so it rewards clearing rooms rather than fleeing through
## them, and it is the sustain option for a build that cannot afford lifesteal.
class_name CronJobPassive
extends PassiveAbility

## Share of maximum HP restored when a room is cleared.
@export var heal_fraction: float = 0.1
## Extra share per tier above 1.
@export var per_tier: float = 0.04


## Share of maximum HP one room clear restores at the current tier.
func fraction() -> float:
	return heal_fraction + per_tier * float(tier - 1)


func on_room_cleared(player: Node2D) -> void:
	var entity := player as Entity
	if entity == null or entity.health == null:
		return
	var gained := entity.health.heal(entity.health.max_hp * fraction())
	if gained > 0.0 and entity.is_inside_tree():
		AbilityFx.burst(
			AbilityUtil.world_of(entity), entity.global_position, &"heal", 10, 10.0, 0.5
		)
		AbilityFx.flash(entity, &"heal", 0.3)
