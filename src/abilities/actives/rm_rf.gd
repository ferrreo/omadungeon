## rm -rf: deletes every enemy projectile and hazard on screen — and, since there is no
## confirmation, everything standing in the blast as well.
##
## The projectile wipe alone was worthless: the threat in this game is bodies, not bullets, so
## an ability that only cleaned the air was a slot spent on nothing. The sweep now does heavy
## damage to whatever it catches and finishes anything already below `execute_threshold`,
## which is what makes the long cooldown and the rare weight worth it.
class_name RmRfAbility
extends ActiveAbility

const GROUPS: Array[StringName] = [&"enemy_projectile", &"hazard"]

@export var sweep_radius: float = 130.0
## Extra radius per tier above 1.
@export var radius_per_tier: float = 15.0
@export var knockback: float = 90.0
## HP fraction at or below which a caught enemy is deleted outright.
@export var execute_threshold: float = 0.25
## Extra fraction per tier above 1.
@export var execute_per_tier: float = 0.05


## Sweep radius at the ability's current tier.
func reach() -> float:
	return sweep_radius + radius_per_tier * float(tier - 1)


## HP fraction below which a caught enemy is deleted, at the current tier.
func execute_fraction() -> float:
	return execute_threshold + execute_per_tier * float(tier - 1)


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var tree := entity.get_tree()
	var world := AbilityUtil.world_of(entity)
	_wipe_projectiles(tree, world)
	var radius := reach()
	AbilityUtil.spawn_hitbox(
		entity, self, world, entity.global_position, radius, 0.2, tags, knockback
	)
	_execute_the_weak(entity, radius)
	AbilityFx.ring(world, entity.global_position, radius, &"danger", 0.5)
	AbilityFx.burst(world, entity.global_position, &"text_bright", 26, radius * 0.7, 0.5)
	AbilityFx.flash(entity, &"text_bright", 0.2)
	EventBus.screen_shake.emit(5.0, 0.25)
	AbilityFx.hit_stop(tree, 0.06)
	return true


## Frees every enemy projectile and hazard in the tree, with a puff where each one stood.
func _wipe_projectiles(tree: SceneTree, world: Node) -> void:
	for group: StringName in GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if node is Node2D and world.is_inside_tree():
				AbilityFx.burst(world, (node as Node2D).global_position, &"text_dim", 6, 6.0, 0.3)
			node.queue_free()


## Deletes every non-boss enemy in reach that is already below the execute threshold.
func _execute_the_weak(entity: Entity, radius: float) -> void:
	var cutoff := execute_fraction()
	for enemy: Entity in AbilityUtil.enemies_near(
		entity.get_tree(), entity.global_position, radius
	):
		if enemy.health == null or AbilityUtil.is_elite(enemy):
			continue
		if enemy.health.fraction() > cutoff:
			continue
		var dir := enemy.global_position - entity.global_position
		var info := AbilityUtil.make_damage(
			entity, self, tags, dir, knockback, enemy, 0.0, enemy.health.max_hp * 2.0
		)
		AbilityUtil.hit_directly(enemy, info)
