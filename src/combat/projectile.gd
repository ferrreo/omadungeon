## Generic projectile: moves in a direction, carries a Hitbox, dies on wall/lifetime/pierce.
## Configure via `setup()` then add to the tree. Both player weapons and enemies use it.
##
## Walls are found by sweeping each step, not by `body_entered`. The shot is an Area2D whose
## only collision shape belongs to its `Hitbox` child, so the shot's own area holds no shape
## and the physics server never reported the TileMapLayer walls to it: `body_entered` never
## fired, shots flew through solid geometry until `lifetime` ran out, and the `ricochet`
## passive bounced off nothing. Giving the area a shape would not be enough either: an overlap
## is only sampled at the end of a step, so any shot fast enough to cover more than the 16 px
## a wall is thick in one frame - about 1000 px/s at 60 Hz - lands past the wall and is never
## reported. `_advance()` therefore ray-casts the step against `Layers.WORLD` before taking
## it, which is exact at any speed and hands `_react_to_wall()` the real surface normal to
## bounce off.
##
## Trails and impact puffs are borrowed from the shared `FxPool`, so a screen full of bolts
## allocates no particle nodes beyond the high-water mark, and a trail keeps draining after the
## projectile that owned it is freed.
##
## Pooling: `Projectile.acquire()` is a drop-in replacement for `Projectile.new()` that
## recycles the node instead of allocating one. A shot taken from it parks itself back in the
## shared pool when it expires — the caller does nothing — and `reset_for_pool()` returns it to
## exactly the state `new()` would have produced. `Projectile.new()` still frees on expiry, so
## nothing that has not opted in changes behaviour.
class_name Projectile
extends Area2D

signal expired(projectile: Projectile)

## Directions `_probe_normal()` tries when a wall arrives through `body_entered` (a projectile
## scene that brought its own shape) instead of through the swept step, which knows the real
## normal. A const so the bounce path allocates nothing per hit.
const BOUNCE_PROBES: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
const BOUNCE_PROBE_LENGTH := 8.0
## Walls a single step may bounce off before the shot gives up and spends the rest of the step
## where it is. Two is a corner; more than that is a shot wedged in geometry, and it dies on
## `lifetime` like anything else rather than spinning in a corner for free.
const MAX_SWEEP_BOUNCES := 3
## Radius of the default hitbox circle. Every projectile that does not bring its own Hitbox
## shares one CircleShape2D of this size instead of allocating a resource per shot.
const HIT_RADIUS := 4.0
## Shots parked in the shared pool at once. Two hundred in the air is the design target and a
## shot is parked one frame after it expires, so a sustained barrage can have roughly twice
## that many nodes in circulation; this caps the free list well above it without letting a
## pathological burst pin memory forever.
const POOL_MAX := 512

## One CircleShape2D shared by every default projectile hitbox (nothing mutates it).
static var _shared_hit_shape: CircleShape2D
## Free list behind `acquire()`.
static var _pool: NodePool

@export var speed: float = 200.0
@export var lifetime: float = 2.0
@export var pierce: int = 0
@export var bounces: int = 0
## Downward acceleration (px/s²) for lobbed shots. Named arc_gravity because Area2D already
## defines `gravity`.
@export var arc_gravity: float = 0.0
@export var homing_strength: float = 0.0  # radians/s turn rate toward `homing_target`
@export var sprite_texture: Texture2D
@export var rotate_to_direction: bool = true
## Pooled particle trail behind the shot. Off for shots that carry their own art/FX.
@export var trail_enabled: bool = true
## Pooled puff when the shot ends. Off for shots whose owner spawns its own impact.
@export var impact_puff: bool = true

## True when this shot came from a pool: `_expire()` then parks it instead of freeing it.
## `acquire()` sets it; callers that use `Projectile.new()` never do and keep the old
## free-on-expire behaviour.
var pooled: bool = false

var direction: Vector2 = Vector2.RIGHT
var team: Layers.Team = Layers.Team.PLAYER
var source: Node2D
var homing_target: Node2D
var damage_builder: Callable
var hitbox: Hitbox
var _age: float = 0.0
var _hits_left: int = 0
var _bounces_left: int = 0
var _velocity_y_extra: float = 0.0
var _sprite: Sprite2D
var _trail: CPUParticles2D
var _recycling: bool = false


## Configures the projectile before adding it to the tree.
func setup(
	from: Node2D,
	from_team: Layers.Team,
	dir: Vector2,
	builder: Callable,
	spd: float = -1.0,
	life: float = -1.0
) -> Projectile:
	source = from
	team = from_team
	direction = dir.normalized() if dir.length_squared() > 0.0 else Vector2.RIGHT
	damage_builder = builder
	if spd > 0.0:
		speed = spd
	if life > 0.0:
		lifetime = life
	return self


func _ready() -> void:
	collision_layer = Layers.PROJECTILE
	collision_mask = Layers.WORLD | Layers.PROP
	monitorable = false
	_age = 0.0
	_velocity_y_extra = 0.0
	_hits_left = pierce
	_bounces_left = bounces
	hitbox = get_node_or_null("Hitbox") as Hitbox
	if hitbox == null:
		hitbox = Hitbox.new()
		hitbox.name = "Hitbox"
		var shape := CollisionShape2D.new()
		shape.shape = shared_hit_shape()
		hitbox.add_child(shape)
		add_child(hitbox)
	hitbox.team = team
	hitbox.collision_mask = Layers.hitbox_mask_for(team)
	hitbox.source = source
	hitbox.damage_builder = damage_builder
	# `_ready()` runs again for every pooled reuse, so every connection here is guarded.
	if not hitbox.hit_dealt.is_connected(_on_hit_dealt):
		hitbox.hit_dealt.connect(_on_hit_dealt)
	if not body_entered.is_connected(_on_body_signal):
		body_entered.connect(_on_body_signal)
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null and sprite_texture != null:
		_sprite = Sprite2D.new()
		_sprite.texture = sprite_texture
		add_child(_sprite)
	elif _sprite != null and sprite_texture != null:
		_sprite.texture = sprite_texture
	if _sprite != null:
		_sprite.visible = _sprite.texture != null
	if rotate_to_direction:
		rotation = direction.angle()
	hitbox.activate(0.0)
	if trail_enabled:
		var pool := FxPool.of(self)
		if pool != null:
			_trail = pool.trail(self, fx_tint())
	# A shot carries its own light (docs 10, lighting): the team's role, pooled, out with it.
	LightEmitter.attach(self, &"enemy_shot" if team == Layers.Team.ENEMY else &"shot")


## The CircleShape2D every default projectile hitbox uses. Shared on purpose: 200 shots in the
## air used to mean 200 identical shape resources.
static func shared_hit_shape() -> CircleShape2D:
	if _shared_hit_shape == null:
		_shared_hit_shape = CircleShape2D.new()
		_shared_hit_shape.radius = HIT_RADIUS
	return _shared_hit_shape


## The shared projectile pool. Exposed for diagnostics (`created` / `reused`) and for tests.
static func pool() -> NodePool:
	if _pool == null:
		_pool = NodePool.new(func() -> Node: return Projectile.new(), reset_for_pool, POOL_MAX)
	return _pool


## Drop-in replacement for `Projectile.new()` that recycles. Configure with `setup()` and add
## to the tree exactly as before; the shot returns itself to the pool when it expires.
static func acquire() -> Projectile:
	var shot := pool().acquire() as Projectile
	shot.pooled = true
	return shot


## Frees every parked shot. Tests call this; the game never needs to.
static func clear_pool() -> void:
	if _pool != null:
		_pool.clear()


## `NodePool` reset hook: puts a recycled shot back to class defaults so the next caller sees
## exactly what `Projectile.new()` would have given them.
static func reset_for_pool(node: Node) -> void:
	var shot := node as Projectile
	if shot == null:
		return
	shot.speed = 200.0
	shot.lifetime = 2.0
	shot.pierce = 0
	shot.bounces = 0
	shot.arc_gravity = 0.0
	shot.homing_strength = 0.0
	shot.rotate_to_direction = true
	shot.sprite_texture = null
	shot.direction = Vector2.RIGHT
	shot.team = Layers.Team.PLAYER
	shot.source = null
	shot.homing_target = null
	shot.damage_builder = Callable()
	shot.pooled = false
	shot.trail_enabled = true
	shot.impact_puff = true
	shot._trail = null
	shot._recycling = false
	shot.rotation = 0.0
	shot.modulate = Color.WHITE
	shot.scale = Vector2.ONE
	shot.visible = true
	shot._age = 0.0
	shot._hits_left = 0
	shot._bounces_left = 0
	shot._velocity_y_extra = 0.0
	if shot.hitbox != null and is_instance_valid(shot.hitbox):
		shot.hitbox.deactivate()
		shot.hitbox.damage_builder = Callable()
		shot.hitbox.source = null


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_expire()
		return
	if homing_strength > 0.0 and is_instance_valid(homing_target):
		var wanted := (homing_target.global_position - global_position).angle()
		var current := direction.angle()
		direction = Vector2.from_angle(rotate_toward(current, wanted, homing_strength * delta))
	if arc_gravity > 0.0:
		_velocity_y_extra += arc_gravity * delta
	_advance(direction * speed * delta + Vector2(0.0, _velocity_y_extra * delta))
	if rotate_to_direction and not _recycling:
		rotation = direction.angle()


## Takes one step, stopping at the first wall in the way instead of through it.
##
## The shot dies at the contact point, or - with `bounces` left - reflects off the surface
## normal and spends what is left of the step in the new direction. It comes to rest one
## `HIT_RADIUS` off the wall, so the impact puff pops on the wall face rather than inside it.
## A lobbed shot keeps the downward speed it had built up (`_velocity_y_extra`): a bounce
## redirects the shot, it does not cancel gravity.
func _advance(motion: Vector2) -> void:
	var remaining := motion
	for _step in range(MAX_SWEEP_BOUNCES + 1):
		if remaining.length_squared() <= 0.0:
			return
		var hit := _cast_wall(remaining)
		if hit.is_empty():
			global_position += remaining
			return
		var normal: Vector2 = hit["normal"]
		var contact: Vector2 = hit["position"]
		var left := maxf(remaining.length() - global_position.distance_to(contact), 0.0)
		global_position = contact + normal * HIT_RADIUS
		if not _react_to_wall(normal, 0.0):
			return
		remaining = direction * left


## First `Layers.WORLD` body along `motion`, looking one `HIT_RADIUS` past the end of the step
## so the shot reacts when its nose reaches the wall rather than when its centre is inside it.
## Empty when the way is clear. A shot that starts *inside* a wall is not reported against the
## wall it is in (`hit_from_inside` stays off), so a shot spawned in geometry flies out of it
## instead of dying on the spot.
func _cast_wall(motion: Vector2) -> Dictionary:
	var world := get_world_2d()
	if world == null:
		return {}
	var to := global_position + motion + motion.normalized() * HIT_RADIUS
	var query := PhysicsRayQueryParameters2D.create(global_position, to, Layers.WORLD)
	query.collide_with_areas = false
	return world.direct_space_state.intersect_ray(query)


func _on_hit_dealt(_target: Hurtbox, _info: DamageInfo) -> void:
	if _hits_left <= 0:
		_expire()
	else:
		_hits_left -= 1


## Signal-side entry point: this runs inside the physics query flush, so the window is marked
## the way `Hitbox` marks its own. `_expire()` goes out to `expired` listeners from here, and a
## listener that inserts a collider (an explosion, a split shot) has to be able to see it.
func _on_body_signal(body: Node2D) -> void:
	PhysicsFlush.enter()
	_on_body_entered(body)
	PhysicsFlush.exit()


## Overlap route into the wall reaction, for a projectile *scene* that brings a collision
## shape of its own. The swept step is what catches walls for the shots the game builds in
## code; this path adds nothing for them, because the sweep has already moved the shot clear
## of the wall before the server could report the overlap.
func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_hit"):
		return  # props handled by Hitbox
	_react_to_wall(_probe_normal(), 2.0)


## The shot met a wall: bounce off `normal` (and step `nudge` px clear of it) while bounces
## remain, otherwise die. Returns true when it bounced.
func _react_to_wall(normal: Vector2, nudge: float) -> bool:
	if _bounces_left <= 0:
		_expire()
		return false
	_bounces_left -= 1
	direction = direction.bounce(normal).normalized()
	global_position += normal * nudge
	# Re-open the hitbox so a bounced shot may hit a target it has already hit once.
	hitbox.activate(0.0)
	return true


## Nearest wall normal around the shot (approximate: test 4 directions). Only the overlap
## route needs this; the swept step gets the exact normal from the cast.
func _probe_normal() -> Vector2:
	var space := get_world_2d().direct_space_state
	var best_normal := -direction
	var best_dist := INF
	for probe: Vector2 in BOUNCE_PROBES:
		var query := PhysicsRayQueryParameters2D.create(
			global_position, global_position + probe * BOUNCE_PROBE_LENGTH, Layers.WORLD
		)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var d: float = (hit["position"] as Vector2).distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best_normal = hit["normal"]
	return best_normal


## Colour the pooled trail and puff are tinted with: the projectile's own art colour, so
## authored projectile colours still read (docs §10) instead of being themed.
func fx_tint() -> Color:
	var tint := modulate
	if _sprite != null:
		tint *= _sprite.modulate
	tint.a = 1.0
	return tint


## Hands the pooled trail back and pops an impact puff. Safe to call twice.
func _end_fx() -> void:
	var pool := FxPool.of(self)
	if pool == null:
		_trail = null
		return
	if _trail != null:
		pool.release(_trail)
		_trail = null
	if impact_puff:
		pool.puff(global_position, fx_tint(), -1, 10.0)


func _expire() -> void:
	if _recycling:
		return
	# Read `pooled` before the signal: a listener that recycles the shot into its own pool runs
	# `reset_for_pool`, which clears the flag, and this would then free a parked node.
	var was_pooled := pooled
	_end_fx()
	expired.emit(self)
	if not was_pooled:
		queue_free()
		return
	# A listener with its own pool may have taken the shot already (it is then unparented).
	# Otherwise the shot owns itself and goes back to the shared pool — deferred, because
	# `_expire()` runs inside the physics step and detaching a monitoring Area2D there is
	# exactly what `queue_free()` exists to avoid doing immediately.
	if get_parent() == null:
		return
	_recycling = true
	visible = false
	set_physics_process(false)
	if hitbox != null and is_instance_valid(hitbox):
		hitbox.deactivate()
	call_deferred(&"_recycle")


## Deferred half of a pooled expiry: park the shot, or free it when the pool is full.
func _recycle() -> void:
	_recycling = false
	set_physics_process(true)
	if not pool().release(self):
		queue_free()
