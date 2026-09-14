## Fork Bomb `:(){ :|:& };:` — forks a ring of runaway processes that fly outward and detonate
## on whatever they touch. Covers the whole room rather than one lane, so it is the answer to
## being surrounded; each individual process is small.
class_name ForkBombAbility
extends ActiveAbility

## Processes forked per cast at tier 1.
@export var process_count: int = 8
## Extra processes per tier above 1.
@export var processes_per_tier: int = 3
@export var speed: float = 150.0
@export var lifetime: float = 1.1
@export var knockback: float = 45.0
## Radius of the burst under the player's feet on cast.
@export var burst_radius: float = 20.0


## Processes forked at the ability's current tier.
func forks() -> int:
	return maxi(1, process_count + processes_per_tier * (tier - 1))


func _activate(player: Node2D, aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return false
	var world := AbilityUtil.world_of(entity)
	var count := forks()
	var start := AbilityUtil.aim_dir(entity, aim).angle()
	for i in range(count):
		var dir := Vector2.from_angle(start + TAU * float(i) / float(count))
		var shot := AbilityUtil.spawn_projectile(
			entity,
			self,
			world,
			entity.global_position + dir * 6.0,
			dir,
			speed,
			lifetime,
			tags,
			knockback
		)
		if shot == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = AbilityFx.circle_texture(2)
		AbilityFx.bind_palette(sprite, &"magic")
		shot.add_child(sprite)
	AbilityFx.ring(world, entity.global_position, burst_radius, &"magic", 0.35)
	LightEmitter.flash(&"arcane", entity.global_position)
	AbilityFx.squash(entity, 0.25, 0.16)
	return true
