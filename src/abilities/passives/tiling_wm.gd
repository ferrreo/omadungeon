## Tiling WM: bonus damage while at least `min_aligned` enemies share a row or column with
## the player (within `tolerance_px`). Master the layout, punish the stack.
class_name TilingWmPassive
extends PassiveAbility

@export var bonus: float = 0.15
@export var per_tier: float = 0.05
@export var min_aligned: int = 3
@export var tolerance_px: float = 16.0


func multiplier() -> float:
	return 1.0 + bonus + per_tier * (tier - 1)


## Number of enemies aligned with `player` on the best row or column.
func aligned_count(player: Entity) -> int:
	var rows := 0
	var cols := 0
	for e: Entity in AbilityUtil.enemies(player.get_tree()):
		var d := e.global_position - player.global_position
		if absf(d.y) <= tolerance_px:
			rows += 1
		if absf(d.x) <= tolerance_px:
			cols += 1
	return maxi(rows, cols)


func outgoing_damage_multiplier(player: Node2D, _target: Node2D, _info: DamageInfo) -> float:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return 1.0
	return multiplier() if aligned_count(entity) >= min_aligned else 1.0
