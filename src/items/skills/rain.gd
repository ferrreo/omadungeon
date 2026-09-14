## Bow skill: arrows rain onto the aimed spot after a short telegraph (more arrows per tier).
class_name SkillRain
extends WeaponSkill

const BASE_ARROWS := 6
const ARROWS_PER_TIER := 2
const RANGE := 90.0
const SCATTER := 26.0
const FALL_TIME := 0.35
const STAGGER := 0.05
const HIT_RADIUS := 9.0
const HIT_DURATION := 0.12
const KNOCKBACK := 40.0

var arrows_landed: int = 0


func _activate(player: Node2D, aim: Vector2) -> bool:
	if not can_cast(player):
		return false
	var entity := player as Entity
	var dir := aim_dir(entity, aim)
	var reach := minf(RANGE, aim.length()) if aim.length_squared() > 1.0 else RANGE
	var target := entity.global_position + dir * reach
	var rng := rng_of(entity)
	var world := world_of(entity)
	var count := BASE_ARROWS + ARROWS_PER_TIER * (tier - 1)
	var texture := SkillFx.dot_texture(Color("e6d3a3"), 1)
	for i in range(count):
		var offset := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * SCATTER
		var pos := target + offset
		var delay := FALL_TIME + STAGGER * float(i)
		SkillFx.telegraph(
			world, pos, SkillFx.circle_points(HIT_RADIUS, 10), 0.0, SkillFx.accent_color(), delay
		)
		SkillFx.drop_sprite(world, texture, pos + Vector2(0.0, -48.0), pos, delay)
		var landing := func() -> void: _land(entity, pos)
		world.get_tree().create_timer(delay).timeout.connect(landing)
	return true


func _land(entity: Entity, pos: Vector2) -> void:
	if not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	var circle := CircleShape2D.new()
	circle.radius = HIT_RADIUS
	spawn_hitbox(entity, pos, circle, 0.0, HIT_DURATION, KNOCKBACK, [], false)
	SkillFx.burst(world_of(entity), pos, Color("e6d3a3"), 4, 40.0, 0.25)
	arrows_landed += 1
