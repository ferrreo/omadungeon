## Siphon: a tether to the nearest enemy that drains it over a couple of seconds and pours a
## share of the damage back into you. The only generic active that is also a heal, so it is
## what a build with no lifesteal takes to survive a long floor.
class_name SiphonAbility
extends ActiveAbility

@export var range_px: float = 110.0
## Drain ticks per cast; the ability's `damage` is split evenly between them.
@export var ticks: int = 6
@export var tick_interval: float = 0.2
## Share of the damage drained that is healed back.
@export var heal_fraction: float = 0.5
## Extra healed share per tier above 1.
@export var heal_per_tier: float = 0.1


## Share of the drained damage healed at the ability's current tier.
func healed_share() -> float:
	return heal_fraction + heal_per_tier * float(tier - 1)


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	if AbilityUtil.nearest_enemy(entity.get_tree(), entity.global_position, range_px) == null:
		return false
	for i in range(maxi(1, ticks)):
		var delay := tick_interval * float(i)
		if delay <= 0.0:
			_drain(entity)
			continue
		entity.get_tree().create_timer(delay).timeout.connect(
			func() -> void:
				if is_instance_valid(entity) and entity.is_inside_tree():
					_drain(entity)
		)
	return true


## One drain tick: hits the nearest enemy for a share of `damage` and heals the player.
func _drain(entity: Entity) -> void:
	var target := AbilityUtil.nearest_enemy(entity.get_tree(), entity.global_position, range_px)
	if target == null:
		return
	var share := damage / float(maxi(1, ticks))
	var info := AbilityUtil.make_damage(
		entity, self, tags, target.global_position - entity.global_position, 0.0, target, 0.0, share
	)
	var dealt := AbilityUtil.hit_directly(target, info)
	if dealt > 0.0 and entity.health != null:
		entity.health.heal(dealt * healed_share())
	var world := AbilityUtil.world_of(entity)
	var line := PackedVector2Array([target.global_position, entity.global_position])
	AbilityFx.bolt(world, line, &"heal", 0.16)
	AbilityFx.burst(world, entity.global_position, &"heal", 4, 6.0, 0.25)
