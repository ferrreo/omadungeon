## Rootkit: the first hit you land on any given enemy is an ambush. Rewards opening on a fresh
## target rather than tunnelling one down, and pays far more to a slow heavy weapon (one big
## first hit) than to a fast one — a real weapon-shape preference rather than a flat number.
class_name RootkitPassive
extends PassiveAbility

## Fraction of extra damage on the first hit against each enemy.
@export var first_hit_bonus: float = 1.2
## Extra fraction per tier above 1.
@export var per_tier: float = 0.4

## Instance ids of enemies already hit this run.
var _seen: Dictionary = {}


## Extra damage fraction at the current tier.
func bonus() -> float:
	return first_hit_bonus + per_tier * float(tier - 1)


## True when `target` has not been hit by this player yet.
func is_fresh(target: Node2D) -> bool:
	return target != null and not _seen.has(target.get_instance_id())


func outgoing_damage_multiplier(player: Node2D, target: Node2D, _info: DamageInfo) -> float:
	if target == null:
		return 1.0
	var key := target.get_instance_id()
	if _seen.has(key):
		return 1.0
	_seen[key] = true
	var entity := player as Entity
	if entity != null and entity.is_inside_tree() and target is Node2D:
		AbilityFx.burst(
			AbilityUtil.world_of(entity), (target as Node2D).global_position, &"magic", 8, 10.0, 0.3
		)
	return 1.0 + bonus()


func remove(player: Node2D) -> void:
	_seen.clear()
	super(player)
