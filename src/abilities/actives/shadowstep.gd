## Shadowstep: blink up to N tiles toward the aim (stopping at walls); the next hit is a
## guaranteed crit and the seconds after the blink are empowered.
##
## The blink plus one crit was not worth a slot next to an ability that deals damage every
## cast: it repositioned, and repositioning is something a dodge already does for free. The
## empower window is what turns it from an escape into an opening.
class_name ShadowstepAbility
extends ActiveAbility

@export var max_tiles: float = 4.0
## Extra tiles per tier above 1.
@export var tiles_per_tier: float = 0.5
@export var wall_margin: float = 6.0
## Fraction of extra damage for `empower_duration` seconds after the blink lands.
@export var empower: float = 0.35
## Extra empower per tier above 1.
@export var empower_per_tier: float = 0.1
@export var empower_duration: float = 3.0


func _activate(player: Node2D, aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var dir := AbilityUtil.aim_dir(entity, aim)
	var origin := entity.global_position
	var dest := find_destination(entity, dir)
	if dest.distance_to(origin) < 2.0:
		return false
	var world := AbilityUtil.world_of(entity)
	AbilityFx.burst(world, origin, &"magic", 14, 12.0)
	entity.global_position = dest
	entity.facing = dir
	AbilityFx.burst(world, dest, &"magic", 14, 12.0)
	LightEmitter.flash(&"arcane", dest)
	AbilityFx.squash(entity, 0.3)
	var slots := AbilityUtil.slots_of(entity)
	if slots != null:
		slots.queue_next_hit(AbilitySlots.BUFF_CRIT)
	if entity.status != null:
		var magnitude := empower + empower_per_tier * float(tier - 1)
		entity.status.apply(
			StatusEffect.make(StatusEffect.Kind.EMPOWER, empower_duration, magnitude, entity)
		)
	return true


## Farthest reachable point along `dir`: ray-stops at world geometry, then backs off until
## the body fits.
func find_destination(entity: Entity, dir: Vector2) -> Vector2:
	var distance := (max_tiles + tiles_per_tier * (tier - 1)) * Layers.TILE
	var origin := entity.global_position
	var dest := origin + dir * distance
	var space := entity.get_world_2d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters2D.create(origin, dest, Layers.WORLD)
		query.exclude = [entity.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			dest = (hit["position"] as Vector2) - dir * wall_margin
	for _i in range(8):
		var xform := Transform2D(entity.global_rotation, dest)
		if not entity.test_move(xform, Vector2.ZERO):
			break
		dest -= dir * 4.0
		if dir.dot(dest - origin) <= 0.0:
			return origin
	return dest
