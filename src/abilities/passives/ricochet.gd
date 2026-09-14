## Ricochet: player projectiles bounce off walls. Sets flag `projectile_bounces` (= tier);
## weapon code and AbilityUtil.spawn_projectile read it into `Projectile.bounces`.
class_name RicochetPassive
extends PassiveAbility

@export var bounces_per_tier: int = 1


func apply(player: Node2D) -> void:
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		slots.set_flag(&"projectile_bounces", bounces_per_tier * tier)


func remove(player: Node2D) -> void:
	super(player)
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		slots.clear_flag(&"projectile_bounces")
