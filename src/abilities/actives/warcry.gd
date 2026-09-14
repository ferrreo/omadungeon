## Warcry: empowers the player, hardens them and taunts every enemy nearby onto them.
##
## A taunt that only bought damage was a bad trade — pulling a pack onto yourself for +25%
## damage cost more health than it returned. It now hands out armour for the same window, so
## the bargain is "everything comes at me, and I can take it", which is the only shape in
## which a taunt is worth a slot.
class_name WarcryAbility
extends ActiveAbility

@export var duration: float = 8.0
@export var empower: float = 0.5
## Extra empower per tier above 1.
@export var empower_per_tier: float = 0.08
## Flat armour granted for the duration.
@export var armor_bonus: float = 30.0
## Extra armour per tier above 1.
@export var armor_per_tier: float = 10.0
@export var taunt_radius: float = 110.0


## Flat armour the shout grants at the current tier.
func armor_value() -> float:
	return armor_bonus + armor_per_tier * float(tier - 1)


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var magnitude := empower + empower_per_tier * (tier - 1)
	entity.status.apply(StatusEffect.make(StatusEffect.Kind.EMPOWER, duration, magnitude, entity))
	_grant_armor(entity)
	var taunted := 0
	for enemy: Entity in AbilityUtil.enemies_near(
		entity.get_tree(), entity.global_position, taunt_radius
	):
		if enemy.status == null:
			continue
		enemy.status.apply(StatusEffect.make(StatusEffect.Kind.TAUNT, duration, 0.0, entity))
		AbilityFx.flash(enemy, &"danger", 0.2)
		taunted += 1
	var world := AbilityUtil.world_of(entity)
	AbilityFx.ring(world, entity.global_position, taunt_radius, &"danger", 0.45)
	AbilityFx.burst(world, entity.global_position, &"danger", 18, 20.0)
	LightEmitter.flash(&"danger", entity.global_position)
	AbilityFx.flash(entity, &"danger", 0.25)
	AbilityFx.squash(entity, 0.25)
	AbilityFx.hit_stop(world.get_tree(), 0.03)
	return true


## Adds the shout's armour for `duration`, replacing any window still running.
func _grant_armor(entity: Entity) -> void:
	var oid := StringName("buff:" + String(id))
	entity.stats.remove_owner(oid)
	entity.stats.add_flat(&"armor", oid, armor_value())
	entity.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if is_instance_valid(entity) and entity.stats != null:
				entity.stats.remove_owner(oid)
	)
