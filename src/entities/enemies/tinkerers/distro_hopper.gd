## Tinkerer that teleports to a free spot nearby every few seconds and fires weak fast bolts.
class_name DistroHopper
extends EnemyBase

## Number of hops performed (tests/debug).
var hops: int = 0
var _shot: ThrowProjectile
var _hop_left: float = 1.5


func _ready() -> void:
	super._ready()
	_shot = add_attack(ThrowProjectile.new()) as ThrowProjectile
	_shot.sprite_index = ProjectileSprites.BOLT


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if def == null:
		return
	if (
		state == State.DEAD
		or state == State.STUNNED
		or state == State.ATTACK
		or state == State.WINDUP
	):
		return
	# A hopper that has not noticed anybody stays where it was posted. Teleporting around an
	# empty room reads, from across the floor, exactly like being hunted.
	if is_asleep():
		return
	_hop_left -= delta
	if _hop_left <= 0.0:
		_hop_left = def.param(&"hop_interval", 3.0)
		hop()


## Teleports within `hop_range` px to a navigable spot with line of sight from here.
func hop() -> void:
	var range_px := def.param(&"hop_range", Layers.TILE * 6.0)
	for attempt in range(8):
		var offset := (
			Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(range_px * 0.4, range_px)
		)
		var dest := walkable_point(global_position + offset)
		if dest.distance_to(global_position) < Layers.TILE or not has_line_of_sight(dest):
			continue
		_teleport_to(dest)
		return


func _teleport_to(dest: Vector2) -> void:
	hops += 1
	death_burst.restart()
	global_position = dest
	sprite.scale = Vector2(0.4, 1.5)
	var t := create_tween()
	t.tween_property(sprite, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	nav_agent.target_position = global_position


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_shot.count = 1
	_shot.speed = def.param(&"shot_speed", 240.0)
	_shot.damage = base_damage()
	_shot.knockback = 25.0
	_shot.lifetime = 1.2
	run_attack(_shot, target.global_position)
