## Staff skill: an arcane wall in front of the player that swallows enemy projectiles and
## shoves anything that touches it. Lasts a few seconds, then fades.
## Projectiles are Areas that are not monitorable, so the wall queries the physics space for
## the PROJECTILE layer itself each physics frame instead of relying on area overlaps.
class_name SkillBarrier
extends WeaponSkill

const DURATION := 3.0
const DISTANCE := 20.0
const SIZE := Vector2(8.0, 40.0)
const KNOCKBACK := 110.0
const CONTACT_INTERVAL := 0.5
const CATCH_MARGIN := 4.0
const FADE := 0.3

var projectiles_blocked: int = 0


## The wall node: catches every enemy Projectile overlapping its rect, wherever it is parented.
class BarrierWall:
	extends Node2D
	var team: Layers.Team = Layers.Team.PLAYER
	var half_size: Vector2 = Vector2.ZERO
	var blocked: Callable
	var _query: PhysicsShapeQueryParameters2D

	func _physics_process(_delta: float) -> void:
		for projectile: Projectile in _candidates():
			if projectile.team == team or projectile.is_queued_for_deletion():
				continue
			var local := to_local(projectile.global_position)
			if absf(local.x) <= half_size.x + CATCH_MARGIN and absf(local.y) <= half_size.y:
				if blocked.is_valid():
					blocked.call(projectile.global_position)
				projectile.queue_free()

	## Projectiles overlapping the wall rect: a physics query on the PROJECTILE layer, with a
	## sibling scan as a fallback for projectiles the space state does not report.
	func _candidates() -> Array[Projectile]:
		var out: Array[Projectile] = []
		var space := get_world_2d().direct_space_state if is_inside_tree() else null
		if space != null:
			if _query == null:
				var rect := RectangleShape2D.new()
				rect.size = (half_size + Vector2(CATCH_MARGIN, 0.0)) * 2.0
				_query = PhysicsShapeQueryParameters2D.new()
				_query.shape = rect
				_query.collide_with_areas = true
				_query.collide_with_bodies = false
				_query.collision_mask = Layers.PROJECTILE
			_query.transform = global_transform
			for hit: Dictionary in space.intersect_shape(_query, 16):
				var node := hit.get("collider") as Node
				while node != null and not (node is Projectile):
					node = node.get_parent()
				var projectile := node as Projectile
				if projectile != null and not out.has(projectile):
					out.append(projectile)
		var parent := get_parent()
		if parent != null:
			for child: Node in parent.get_children():
				var sibling := child as Projectile
				if sibling != null and not out.has(sibling):
					out.append(sibling)
		return out


func _activate(player: Node2D, aim: Vector2) -> bool:
	if not can_cast(player):
		return false
	var entity := player as Entity
	var dir := aim_dir(entity, aim)
	var world := world_of(entity)
	var duration := DURATION * tier_damage_scale()
	var wall := BarrierWall.new()
	wall.name = "Barrier"
	wall.team = entity.team
	wall.half_size = SIZE * 0.5
	var visual := Polygon2D.new()
	visual.polygon = SkillFx.rect_points(SIZE)
	visual.color = Color(SkillFx.accent_color(), 0.55)
	wall.add_child(visual)
	wall.blocked = func(pos: Vector2) -> void:
		projectiles_blocked += 1
		SkillFx.burst(world, pos, SkillFx.accent_color(), 5, 50.0, 0.2)
	world.add_child(wall)
	wall.global_position = entity.global_position + dir * DISTANCE
	wall.rotation = dir.angle()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	spawn_hitbox(
		entity,
		wall.global_position,
		rect,
		dir.angle(),
		duration,
		KNOCKBACK,
		[],
		false,
		CONTACT_INTERVAL
	)
	# Pulse for the whole lifetime, then one fade-out; the wall is freed by its own timer so
	# the visual, the projectile catcher and the damaging hitbox all end together.
	var pulse := wall.create_tween().set_loops(maxi(1, int(duration / 0.8)))
	pulse.tween_property(visual, "color:a", 0.25, 0.4).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(visual, "color:a", 0.55, 0.4).set_ease(Tween.EASE_IN_OUT)
	var tree := wall.get_tree()
	tree.create_timer(maxf(0.05, duration - FADE)).timeout.connect(
		func() -> void:
			if not is_instance_valid(wall):
				return
			pulse.kill()
			wall.create_tween().tween_property(visual, "color:a", 0.0, FADE)
	)
	tree.create_timer(duration).timeout.connect(
		func() -> void:
			if is_instance_valid(wall):
				wall.queue_free()
	)
	SkillFx.burst(world, wall.global_position, SkillFx.accent_color(), 10, 60.0)
	return true
