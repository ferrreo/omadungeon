## Area2D that deals damage to Hurtboxes it overlaps. Enable with `activate()`; each target
## is hit at most once per activation unless `multi_hit_interval` > 0.
##
## Damage is applied *synchronously* inside the overlap callback, on purpose: `hurtbox.receive`
## returns how much landed, and `hit_dealt` carries it on. That callback runs while the physics
## server is flushing its queries, and so does everything the hit sets off - including an
## enemy's death and its loot. Anything reached from a hit that adds a node with a collision
## shape to the tree (a pickup, a dropped item, a hazard, an on-death split) must therefore
## *defer* the insertion: the server refuses shape and monitoring changes mid-flush and the new
## collider silently comes up empty. See `PickupSpawner._place`, `ItemPickup.drop` and
## `EnemyBase.spawn_sibling`.
##
## That rule used to be a comment and nothing else, and the on-death effects broke it. The
## window is now *marked* here (`_on_area_signal`/`_on_body_signal` -> `PhysicsFlush`) so the
## insertion points can read it instead of guessing, and
## `tests/unit/tools/physics_deferral_test.gd` kills enemies through a real overlap to check
## that they still obey it.
##
## **That rule binds this class too**, and it used to break it. `activate()`/`deactivate()` are
## routinely called from inside an overlap callback - `Charge._on_hit_dealt` -> `finish()` ->
## `deactivate()` is reached straight out of `_on_area_entered` - and a direct write to
## `monitoring` there is refused by the server with `Function blocked during in/out signal`,
## leaving the flag desynced from `_active`. Both methods therefore go through
## `set_deferred(&"monitoring", ...)`, which lands before the same frame's physics step
## (`SceneTree` flushes the message queue at the end of `physics_process`), so nothing is a
## frame late. `is_live()` - not `monitoring` - is the answer to "is this box swinging".
##
## The initial-overlap sweep moved with it. A target already inside the shape when the box
## turns on never emits `area_entered`, so it has to be found by hand; but the query that finds
## it is itself illegal while monitoring is off ("Can't find overlapping bodies when monitoring
## is off"), and the server does not populate the overlap list until the next physics step
## anyway. The sweep is queued (`_pending_sweep`) and runs on the first physics frame on which
## monitoring is really on. Re-hit dedupe (`_hit_times`) makes it idempotent against the
## `area_entered` the same step may deliver.
class_name Hitbox
extends Area2D

signal hit_dealt(target: Hurtbox, info: DamageInfo)

@export var team: Layers.Team = Layers.Team.PLAYER
@export var damage: float = 10.0
@export var tags: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
@export var knockback: float = 60.0
## 0 = hit each target once per activation; otherwise re-hit every N seconds.
@export var multi_hit_interval: float = 0.0
@export var one_shot_duration: float = 0.0
## Optional: custom DamageInfo builder `func(target: Hurtbox) -> DamageInfo`.
var damage_builder: Callable
var statuses: Array[StatusEffect] = []
var source: Node2D
var _hit_times: Dictionary = {}
var _active := false
var _time_left := 0.0
## True between `activate()` and the first physics frame that could look for the overlaps the
## box turned on inside of. See the class docstring.
var _pending_sweep := false


func _ready() -> void:
	monitorable = false
	monitoring = false
	collision_layer = 0
	collision_mask = Layers.hitbox_mask_for(team)
	area_entered.connect(_on_area_signal)
	body_entered.connect(_on_body_signal)
	if source == null:
		source = _find_entity()


func _find_entity() -> Node2D:
	var node: Node = self
	while node != null:
		if node is Entity:
			return node
		node = node.get_parent()
	return get_parent() as Node2D


## Turns the box on for `duration` seconds (0 = `one_shot_duration`). Safe to call from inside
## an overlap callback: `monitoring` is deferred and the initial-overlap sweep waits for it.
func activate(duration: float = 0.0) -> void:
	_hit_times.clear()
	_active = true
	_time_left = duration if duration > 0.0 else one_shot_duration
	_pending_sweep = true
	# Always queued, never assigned: a direct write is refused mid-flush, and a queued `false`
	# from an earlier deactivate() in the same frame must not land on top of this.
	set_deferred(&"monitoring", true)
	if monitoring:
		# Already on (a re-activation, or the box never closed): the server's overlap list is
		# live right now, so the sweep does not have to wait a frame.
		_sweep_overlaps(true)


## Turns the box off. Hits stop landing immediately (`_can_hit` reads `_active`); the physics
## flag follows one deferred flush later, because the caller is usually inside a hit callback.
func deactivate() -> void:
	_active = false
	_pending_sweep = false
	set_deferred(&"monitoring", false)


## True while the box is swinging. This - not `monitoring` - is the state callers care about:
## the physics flag is applied deferred, so it trails `activate()` until the frame's message
## queue is flushed.
func is_live() -> bool:
	return _active


## Hits everything already inside the shape. Only legal while the server is actually
## monitoring; every caller checks first. `include_bodies` is off for the multi-hit re-sweep,
## which has always been hurtboxes only - re-hitting a destructible prop sixty times a second
## is not what "multi hit" means.
func _sweep_overlaps(include_bodies: bool) -> void:
	for area: Area2D in get_overlapping_areas():
		_on_area_entered(area)
		if not _active:
			return
	if not include_bodies:
		return
	for body: Node2D in get_overlapping_bodies():
		_on_body_entered(body)
		if not _active:
			return


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _pending_sweep and monitoring:
		_pending_sweep = false
		_sweep_overlaps(true)
		if not _active:
			return
	if _time_left > 0.0:
		_time_left -= delta
		if _time_left <= 0.0:
			deactivate()
			return
	if multi_hit_interval > 0.0 and monitoring:
		_sweep_overlaps(false)


## Builds the `DamageInfo` for one hit on `target`.
##
## `source` is the only reference this box keeps to something it does not own, and a box
## routinely outlives its attacker: a projectile is still in the air a second and a half after
## the enemy that fired it was freed (`EnemyBase.DEATH_FALLBACK_TIME`), and so is a boss hazard
## parented to the floor rather than to the boss.
##
## A freed reference does not merely read wrong here, it **loses the hit**. `DamageInfo.create`
## declares `from: Node2D`, and GDScript refuses a freed instance at a statically typed
## parameter - "The Object-derived class of argument 3 (previously freed) is not a subclass of
## the expected argument class" - which abandons this whole call and returns null, so the shot
## passes through its target dealing nothing and the only trace is one line on stderr. So the
## attacker is validated once, here, and the fallback direction and the `DamageInfo` handed to
## every listener both use the validated local: nothing downstream is given a dangling
## reference to re-check for itself. (`is_instance_valid` rather than `!= null` because null and
## freed are two different states to report, not because `!= null` misses one.)
func build_info(target: Node2D) -> DamageInfo:
	if damage_builder.is_valid():
		return damage_builder.call(target)
	var attacker: Node2D = source if is_instance_valid(source) else null
	var info := DamageInfo.create(damage, tags, attacker, team)
	var dir := target.global_position - global_position
	if dir.length_squared() < 0.001 and attacker != null:
		dir = target.global_position - attacker.global_position
	info.with_knockback(dir, knockback)
	for s: StatusEffect in statuses:
		info.with_status(s)
	return info


func _can_hit(id: int) -> bool:
	if not _active:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if _hit_times.has(id):
		if multi_hit_interval <= 0.0:
			return false
		if now - float(_hit_times[id]) < multi_hit_interval:
			return false
	_hit_times[id] = now
	return true


## Signal-side entry points. These two - and only these two - run inside the physics query
## flush, so they mark the window (`PhysicsFlush`) for everything the hit goes on to reach: an
## enemy's death, its on-death split or shrapnel, and the colliders those insert. Nothing else
## can see that window; `Engine.is_in_physics_frame()` is also true in `_physics_process`,
## where those insertions are legal.
func _on_area_signal(area: Area2D) -> void:
	PhysicsFlush.enter()
	_on_area_entered(area)
	PhysicsFlush.exit()


func _on_body_signal(body: Node2D) -> void:
	PhysicsFlush.enter()
	_on_body_entered(body)
	PhysicsFlush.exit()


## Hits `area` if it is an enemy hurtbox. Called from the signal wrapper above *and* from
## `_sweep_overlaps`, which runs in `_physics_process`: the sweep deliberately does not mark a
## flush window, because there is none, and marking one would defer every initial-overlap
## spawn a frame for nothing.
func _on_area_entered(area: Area2D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null or not _can_hit(area.get_instance_id()):
		return
	var info := build_info(hurtbox)
	if hurtbox.receive(info) > 0.0:
		hit_dealt.emit(hurtbox, info)


func _on_body_entered(body: Node2D) -> void:
	# Destructible props expose `take_hit(info)`.
	if body.has_method("take_hit") and _can_hit(body.get_instance_id()):
		body.call("take_hit", build_info(body))
