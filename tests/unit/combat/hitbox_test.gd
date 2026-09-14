## `Hitbox` and the physics server's flush rules.
##
## Damage is dealt synchronously inside `area_entered`, which fires while the server is
## flushing its queries, and the server refuses `monitoring` changes there. `Charge` reaches
## `deactivate()` straight out of that callback (`_on_hit_dealt` -> `finish` -> `_stop`) and
## `honker`/`clown_car` re-`activate()` the next one, so the shipping game hit both halves of
## the rule on every charge: two engine errors per hit and a `monitoring` flag left out of sync
## with `_active`.
##
## Both properties are pinned here, and so is the one the fix could have destroyed: a target
## already inside the shape when the box opens still gets hit, even though the sweep that finds
## it can no longer run at the instant of `activate()`.
class_name HitboxTest
extends GdUnitTestSuite

const HIT_RADIUS := 8.0
const DUMMY_HP := 500.0

var _root: Node2D
var _hitbox: Hitbox
var _dummy: Entity
## Filled by the `hit_dealt` handler under test, so the awaited half can be a plain method
## (`assert_error()` takes a Callable and a multi-line lambda cannot carry an await).
var _reentrant: Hitbox
## Hit counter for the callback tests. A GDScript lambda captures locals by value, so a
## counter incremented inside one has to live on the suite.
var _hits: int = 0


func before_test() -> void:
	_root = auto_free(Node2D.new()) as Node2D
	add_child(_root)
	_hitbox = _make_hitbox(Vector2(100, 100))
	_dummy = null
	_reentrant = null
	_hits = 0


## A player-team hitbox with a circular shape, parented to the scratch root.
func _make_hitbox(pos: Vector2) -> Hitbox:
	var box := Hitbox.new()
	box.team = Layers.Team.PLAYER
	box.damage = 5.0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HIT_RADIUS
	shape.shape = circle
	box.add_child(shape)
	_root.add_child(box)
	box.global_position = pos
	return box


## An enemy-team Entity with a hurtbox, sitting at `pos` with enough HP to survive the test.
func _make_dummy(pos: Vector2) -> Entity:
	var dummy := Entity.new()
	dummy.team = Layers.Team.ENEMY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 8)
	shape.shape = rect
	dummy.add_child(shape)
	_root.add_child(dummy)
	dummy.global_position = pos
	dummy.health.max_hp = DUMMY_HP
	dummy.health.hp = DUMMY_HP
	dummy.health.dodge_chance = 0.0
	dummy.set_physics_process(false)
	return dummy


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


# ---------------------------------------------------------------- the flush rule


## The reported crash pair, exactly: deactivate from inside the hit callback, then activate a
## second box from inside the same callback. Before the fix this printed
## `Function blocked during in/out signal. Use set_deferred("monitoring", ...)` followed by
## `Can't find overlapping bodies when monitoring is off`.
func _swing_with_a_reentrant_callback() -> void:
	_reentrant = _make_hitbox(Vector2(100, 100))
	_hitbox.hit_dealt.connect(
		func(_target: Hurtbox, _info: DamageInfo) -> void:
			_hitbox.deactivate()
			_reentrant.activate(1.0)
	)
	_hitbox.activate(2.0)
	await _physics_frames(2)
	# The kill has to land on the *signal*, so the callback runs inside the query flush.
	_dummy = _make_dummy(Vector2(400, 400))
	await _physics_frames(2)
	_dummy.global_position = _hitbox.global_position
	await _physics_frames(6)


func test_toggling_a_hitbox_inside_a_hit_callback_logs_no_engine_error() -> void:
	await assert_error(_swing_with_a_reentrant_callback).is_success()


func test_a_hitbox_activated_inside_a_hit_callback_really_starts_monitoring() -> void:
	await _swing_with_a_reentrant_callback()
	(
		assert_bool(_reentrant.is_live())
		. override_failure_message("the box re-opened inside the callback is not live")
		. is_true()
	)
	(
		assert_bool(_reentrant.monitoring)
		. override_failure_message("`monitoring` desynced from `_active`: the server refused it")
		. is_true()
	)
	# ... and the box that closed inside the callback really closed.
	assert_bool(_hitbox.is_live()).is_false()
	assert_bool(_hitbox.monitoring).is_false()


func test_deactivating_inside_a_hit_callback_stops_the_damage_at_once() -> void:
	_dummy = _make_dummy(Vector2(400, 400))
	_hitbox.multi_hit_interval = 0.05
	_hitbox.hit_dealt.connect(
		func(_target: Hurtbox, _info: DamageInfo) -> void:
			_hits += 1
			_hitbox.deactivate()
	)
	_hitbox.activate(5.0)
	await _physics_frames(2)
	_dummy.global_position = _hitbox.global_position
	await _physics_frames(20)
	(
		assert_int(_hits)
		. override_failure_message("a box closed from its own callback kept dealing damage")
		. is_equal(1)
	)


# ---------------------------------------------------------------- what the fix must not break


## The property the deferred `monitoring` could have destroyed. A target standing inside the
## shape before the box opens never emits `area_entered`, so it is found by a sweep; the sweep
## can no longer run at the instant of `activate()` (the query is illegal while monitoring is
## off) and was moved onto the first physics frame. If that move had been dropped, this hit
## would simply never land and nothing else in the suite would have noticed.
func test_a_target_already_inside_the_shape_is_still_hit() -> void:
	_dummy = _make_dummy(Vector2(100, 100))
	await _physics_frames(2)
	assert_float(_dummy.health.hp).is_equal(DUMMY_HP)
	_hitbox.activate(1.0)
	await _physics_frames(4)
	(
		assert_float(_dummy.health.hp)
		. override_failure_message("the overlap present at activation time was never swept")
		. is_less(DUMMY_HP)
	)


## Re-activating a box that is still monitoring must not wait a frame either: the sweep runs
## immediately when the server is already watching.
func test_reactivating_a_live_box_sweeps_at_once() -> void:
	_dummy = _make_dummy(Vector2(100, 100))
	_hitbox.activate(5.0)
	await _physics_frames(4)
	var after_first := _dummy.health.hp
	assert_float(after_first).is_less(DUMMY_HP)
	assert_bool(_hitbox.monitoring).is_true()
	# A fresh activation clears the per-target dedupe, so the same target is hit again - now.
	_hitbox.activate(5.0)
	assert_float(_dummy.health.hp).is_less(after_first)


## A closed box deals no damage, deferred flag or not: `_can_hit` reads `_active`, which is
## false the instant `deactivate()` returns.
func test_a_closed_box_deals_no_damage_in_the_frame_it_closes() -> void:
	_dummy = _make_dummy(Vector2(100, 100))
	_hitbox.multi_hit_interval = 0.05
	_hitbox.activate(5.0)
	await _physics_frames(4)
	var frozen := _dummy.health.hp
	assert_float(frozen).is_less(DUMMY_HP)
	_hitbox.deactivate()
	assert_bool(_hitbox.is_live()).is_false()
	await _physics_frames(10)
	assert_float(_dummy.health.hp).is_equal(frozen)
