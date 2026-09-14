## Always-on ability. Override `apply`/`remove` for stat changes and the hooks for triggers.
## Modifiers must be registered under `owner_id()` so removal is exact.
class_name PassiveAbility
extends Ability


func _init() -> void:
	kind = Kind.PASSIVE


func owner_id() -> StringName:
	return StringName("passive:" + String(id))


func apply(_player: Node2D) -> void:
	pass


func remove(player: Node2D) -> void:
	(player as Entity).stats.remove_owner(owner_id())


## Called when tier changes (re-apply is the default strategy).
func on_tier_changed(player: Node2D) -> void:
	remove(player)
	apply(player)


## Hooks. Default no-ops. `info` is the outgoing/incoming DamageInfo.
func on_hit_dealt(_player: Node2D, _target: Node2D, _info: DamageInfo) -> void:
	pass


func on_hit_received(_player: Node2D, _info: DamageInfo) -> void:
	pass


func on_kill(_player: Node2D, _victim: Node2D) -> void:
	pass


func on_dodge(_player: Node2D) -> void:
	pass


func on_room_cleared(_player: Node2D) -> void:
	pass


func on_active_used(_player: Node2D, _ability: ActiveAbility) -> void:
	pass


## Return a multiplier applied to outgoing damage (1.0 = none). Used for conditional bonuses.
func outgoing_damage_multiplier(_player: Node2D, _target: Node2D, _info: DamageInfo) -> float:
	return 1.0
