## Contract (Oligarch): hires a Bodyguard for a while. The hireling follows the player and
## melee-attacks the nearest enemy.
class_name ContractAbility
extends ActiveAbility

@export var duration: float = 20.0
@export var hireling_hp_fraction: float = 0.6
@export var hireling_damage: float = 8.0
@export var hireling_speed: float = 95.0


func _activate(player: Node2D, aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var dir := AbilityUtil.aim_dir(entity, aim)
	var world := AbilityUtil.world_of(entity)
	var hp := entity.health.max_hp * hireling_hp_fraction * (1.0 + 0.25 * (tier - 1))
	var bodyguard := Hireling.new().setup(
		entity, hp, hireling_damage * tier_damage_scale(), duration
	)
	bodyguard.name = "Bodyguard"
	bodyguard.move_speed = hireling_speed
	# Deterministic crits: share the owner's combat stream (docs §1).
	var slots := AbilityUtil.slots_of(entity)
	if slots != null:
		bodyguard.rng = slots.rng
	else:
		var owner_rng: Variant = entity.get("rng")
		if owner_rng is RandomNumberGenerator:
			bodyguard.rng = owner_rng
	world.add_child(bodyguard)
	bodyguard.global_position = entity.global_position - dir * Layers.TILE
	AbilityFx.burst(world, bodyguard.global_position, &"loot", 16, 12.0)
	AbilityFx.ring(world, bodyguard.global_position, 14.0, &"loot", 0.3)
	return true
