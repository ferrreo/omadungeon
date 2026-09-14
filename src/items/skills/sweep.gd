## Spear skill: a full spin that knocks back and slows everything around the player.
class_name SkillSweep
extends WeaponSkill

const RADIUS := 34.0
const HIT_DURATION := 0.2
const KNOCKBACK := 140.0
const SLOW_DURATION := 2.0
const SLOW_AMOUNT := 0.4


func _activate(player: Node2D, aim: Vector2) -> bool:
	if not can_cast(player):
		return false
	var entity := player as Entity
	var dir := aim_dir(entity, aim)
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var statuses: Array[StatusEffect] = [
		StatusEffect.make(StatusEffect.Kind.SLOW, SLOW_DURATION, SLOW_AMOUNT, entity)
	]
	spawn_hitbox(entity, Vector2.ZERO, circle, 0.0, HIT_DURATION, KNOCKBACK, statuses)
	SkillFx.telegraph(
		world_of(entity),
		Vector2.ZERO,
		SkillFx.circle_points(RADIUS),
		dir.angle(),
		SkillFx.accent_color(),
		0.3,
		entity
	)
	var sprite := SkillFx.sprite_of(entity)
	if sprite != null and sprite.is_inside_tree():
		var tween := sprite.create_tween()
		tween.tween_property(sprite, "rotation", TAU, 0.25).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func() -> void: sprite.rotation = 0.0)
	SkillFx.burst(world_of(entity), entity.global_position, SkillFx.accent_color(), 14, 100.0)
	return true
