## Dagger / thrown skill: a fan of knives (5, +2 per tier) across ±30°.
class_name SkillFanOfKnives
extends WeaponSkill

const BASE_KNIVES := 5
const KNIVES_PER_TIER := 2
const HALF_SPREAD := PI / 6.0
const SPEED := 300.0
const LIFETIME := 0.6
const KNOCKBACK := 30.0


func _activate(player: Node2D, aim: Vector2) -> bool:
	if not can_cast(player):
		return false
	var entity := player as Entity
	var dir := aim_dir(entity, aim)
	entity.facing = dir
	var count := BASE_KNIVES + KNIVES_PER_TIER * (tier - 1)
	var texture := SkillFx.dot_texture(Color("d7dde8"), 1)
	for i in range(count):
		var t := float(i) / float(count - 1) if count > 1 else 0.5
		var angle := -HALF_SPREAD + 2.0 * HALF_SPREAD * t
		var knife_dir := dir.rotated(angle)
		spawn_projectile(
			entity,
			entity.global_position + knife_dir * 8.0,
			knife_dir,
			SPEED,
			LIFETIME,
			KNOCKBACK,
			[],
			texture
		)
	SkillFx.squash(SkillFx.sprite_of(entity), Vector2(1.2, 0.85), 0.15)
	SkillFx.burst(
		world_of(entity), entity.global_position + dir * 8.0, Color("d7dde8"), 6, 50.0, 0.2
	)
	return true
