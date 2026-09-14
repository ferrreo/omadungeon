## Vampiric: heals the player for a fraction of every hit they land (via
## EventBus.player_hit_dealt). The `lifesteal` stat is intentionally left alone so weapon code
## and this passive never double-heal.
class_name VampiricPassive
extends PassiveAbility

@export var lifesteal: float = 0.03
@export var per_tier: float = 0.02


func fraction() -> float:
	return lifesteal + per_tier * (tier - 1)


func on_hit_dealt(player: Node2D, _target: Node2D, info: DamageInfo) -> void:
	var entity := player as Entity
	if entity == null or info == null or entity.health == null:
		return
	var dealt := info.applied if info.applied > 0.0 else info.amount
	var gained := entity.health.heal(dealt * fraction())
	if gained > 0.0 and entity.is_inside_tree():
		AbilityFx.burst(AbilityUtil.world_of(entity), entity.global_position, &"heal", 3, 6.0, 0.3)
