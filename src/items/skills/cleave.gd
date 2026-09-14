## Axe skill: a huge frontal arc with heavy knockback and a screen shake.
class_name SkillCleave
extends WeaponSkill

const RADIUS := 30.0
const HIT_DURATION := 0.15
const KNOCKBACK := 180.0


func _activate(player: Node2D, aim: Vector2) -> bool:
	if not can_cast(player):
		return false
	var entity := player as Entity
	var dir := aim_dir(entity, aim)
	entity.facing = dir
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	spawn_hitbox(entity, dir * 14.0, circle, 0.0, HIT_DURATION, KNOCKBACK)
	SkillFx.telegraph(
		world_of(entity),
		Vector2.ZERO,
		SkillFx.arc_points(RADIUS + 14.0, PI * 0.55),
		dir.angle(),
		SkillFx.accent_color(),
		0.25,
		entity
	)
	SkillFx.squash(SkillFx.sprite_of(entity), Vector2(0.75, 1.3), 0.25)
	SkillFx.burst(
		world_of(entity), entity.global_position + dir * 16.0, SkillFx.accent_color(), 12, 90.0
	)
	EventBus.screen_shake.emit(3.0, 0.15)
	return true
