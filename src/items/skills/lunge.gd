## Sword skill: dash forward with a piercing thrust hitbox.
class_name SkillLunge
extends WeaponSkill

const DASH_IMPULSE := 240.0
const HIT_DURATION := 0.22
const KNOCKBACK := 90.0


func _activate(player: Node2D, aim: Vector2) -> bool:
	if not can_cast(player):
		return false
	var entity := player as Entity
	var dir := aim_dir(entity, aim)
	entity.facing = dir
	entity.knockback_velocity += dir * DASH_IMPULSE
	var rect := RectangleShape2D.new()
	rect.size = Vector2(36.0, 14.0)
	spawn_hitbox(entity, dir * 18.0, rect, dir.angle(), HIT_DURATION, KNOCKBACK)
	SkillFx.telegraph(
		world_of(entity),
		dir * 18.0,
		SkillFx.rect_points(rect.size),
		dir.angle(),
		SkillFx.accent_color(),
		0.2,
		entity
	)
	SkillFx.squash(SkillFx.sprite_of(entity), Vector2(1.35, 0.7), 0.2)
	SkillFx.burst(
		world_of(entity), entity.global_position - dir * 6.0, SkillFx.accent_color(), 8, 70.0
	)
	return true
