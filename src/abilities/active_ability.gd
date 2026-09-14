## Cooldown-based ability. Subclass and override `_activate`.
class_name ActiveAbility
extends Ability

@export var cooldown: float = 8.0
@export var damage: float = 20.0
@export var tags: Array[StringName] = [DamageInfo.TAG_ABILITY, DamageInfo.TAG_ARCANE]
var cooldown_left: float = 0.0


func _init() -> void:
	kind = Kind.ACTIVE


func effective_cooldown(player: Entity) -> float:
	return cooldown * (1.0 - player.stats.get_value(&"cooldown_reduction")) * tier_cooldown_scale()


## Tier 2/3 shorten cooldown slightly; subclasses may override scaling.
func tier_cooldown_scale() -> float:
	return 1.0 - 0.1 * (tier - 1)


func tier_damage_scale() -> float:
	return 1.0 + 0.25 * (tier - 1)


func is_ready() -> bool:
	return cooldown_left <= 0.0


func tick(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = maxf(0.0, cooldown_left - delta)


## Tries to use; returns true if activated. `aim` is a world-space direction.
func try_activate(player: Node2D, aim: Vector2, free_cast: bool = false) -> bool:
	if not is_ready():
		return false
	if not _activate(player, aim):
		return false
	if not free_cast:
		cooldown_left = effective_cooldown(player as Entity)
	return true


## Override. Return false to refuse (e.g. no valid target) without starting cooldown.
func _activate(_player: Node2D, _aim: Vector2) -> bool:
	push_warning("ActiveAbility %s has no _activate" % id)
	return false


func refund(fraction: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - cooldown * fraction)
