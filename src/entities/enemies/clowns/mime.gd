## Fragile clown that raises an invisible 1x3-tile wall between itself and the player and
## mimes a thrown knife while the wall is on cooldown.
class_name Mime
extends EnemyBase

## Sideways slide after raising a wall, so the mime keeps a firing lane past it.
const SLIDE_SPEED := 130.0
## Step the wall's facing is quantised to. The wall used to be rotated to the exact angle
## toward the player, which put a soft-edged diagonal slab on a screen that promises 16x16
## tiles, integer scaling and snapped 2D transforms (docs §10) - it was the one object on the
## floor that did not read as pixel art, and on a light theme it is a large flat lozenge lying
## across an aligned grid. A quarter turn costs the mime nothing: the wall is 1x3 tiles at any
## angle and the player still has to walk around it.
const WALL_FACING_STEP := TAU / 4.0

## Walls placed so far (tests/debug).
var walls_placed: int = 0
var _knife: ThrowProjectile
var _wall_cooldown_left: float = 0.0


func _ready() -> void:
	super._ready()
	_knife = add_attack(ThrowProjectile.new()) as ThrowProjectile
	_knife.sprite_index = ProjectileSprites.KNIFE


func _physics_process(delta: float) -> void:
	if _wall_cooldown_left > 0.0:
		_wall_cooldown_left -= delta
	super._physics_process(delta)


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	var dist := global_position.distance_to(target.global_position)
	if _wall_cooldown_left <= 0.0 and dist > Layers.TILE * 1.5:
		place_wall(target.global_position)
		_wall_cooldown_left = def.param(&"wall_cooldown", 5.0)
		var side := (target.global_position - global_position).orthogonal().normalized()
		knockback_velocity += side * (SLIDE_SPEED if rng.randf() < 0.5 else -SLIDE_SPEED)
		return
	# The mime kites at preferred_range, so the fallback must reach: an invisible knife.
	_knife.count = 1
	_knife.speed = def.param(&"knife_speed", 180.0)
	_knife.damage = base_damage()
	_knife.knockback = 60.0
	_knife.lifetime = 1.4
	run_attack(_knife, target.global_position)


## Places the wall perpendicular to the line toward `toward`, a short way in front of the mime.
##
## The wall's *position* follows the exact line; only its facing is quantised to a quarter turn
## (`WALL_FACING_STEP`), so it still lands between the mime and its target but stays on the tile
## grid the rest of the screen is drawn on.
func place_wall(toward: Vector2) -> MimeWall:
	var to := toward - global_position
	var dir := to.normalized() if to.length_squared() > 0.01 else facing
	var offset := clampf(to.length() * 0.5, 14.0, 32.0)
	var wall := MimeWall.new()
	wall.name = "MimeWall"
	wall.size = Vector2(Layers.TILE, Layers.TILE * 3)
	wall.duration = def.param(&"wall_duration", 4.0)
	wall.rotation = snappedf(dir.angle(), WALL_FACING_STEP)
	spawn_sibling(wall, global_position + dir * offset)
	walls_placed += 1
	return wall
