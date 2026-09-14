## The deferral rule, measured instead of asserted in a comment.
##
## `Hitbox` states the rule for the whole codebase: anything reached from a hit that adds a
## node with a collision shape to the tree must defer the insertion, because the physics server
## refuses shape/monitoring writes while it is flushing its queries. Pickups and item drops
## obeyed it; the on-death effects (enemy splitting, death shrapnel) did not, and nothing
## noticed - every enemy suite kills through `entity.hurtbox.receive(info)` directly, which
## never opens a flush window, so the 1337-case gate was structurally blind to the one path the
## game actually uses.
##
## These tests kill enemies the way the game does, through a live `Hitbox` overlap, and compare
## what comes out against the same enemy killed outside the flush. Two different kinds of
## evidence, because the two paths damage differently:
##
## * **Shrapnel** diverges in node state that can be read back: confetti inserted mid-flush
##   comes up `monitorable` because `Projectile._ready`'s write to the contrary was refused.
##   That is asserted directly against the control.
## * **Splitting** does not, today. Measured both ways, a split gremlin's hurtbox ends up with
##   the same physics-server shape data and the same layers either way - what the server refuses
##   there is shape *flags* the node re-applies anyway. Its guarantee is therefore carried by
##   `assert_error(...).is_success()`, which fails on the engine's own
##   "Can't change this state while flushing queries" lines. That is a dynamic check, not a
##   scan of the source, and it is the only honest one available for that path: do not swap it
##   for a state assertion that passes in both worlds.
##
## Verified by reverting the fix and watching these fail, rather than assumed: with
## `EnemyBase.spawn_sibling` back to a bare `add_child`, 3 of the 7 fail (both error
## assertions and the confetti `monitorable` comparison); with `EnemyAttack.make_hitbox`
## reverted as well, 4 do, the extra one being the split gremlins' bite box coming up
## monitorable. Reverting `make_hitbox` *alone* is not caught here, and that is not a hidden
## failure: once `spawn_sibling` defers, a spawned enemy's `_ready` no longer runs inside a
## flush, so this scenario never reaches it. That guard is there for the callers that build an
## attack straight out of a hit, and nothing in the game does that yet.
class_name PhysicsDeferralTest
extends GdUnitTestSuite

## Splits into three ConfigGremlins on death (`DotfileGolem._on_death` -> `Summon.summon`).
const SPLITTER := &"dotfile_golem"
## Bursts into six confetti Projectiles on death (`BalloonClown._on_death` -> `ThrowProjectile`).
const SHRAPNEL := &"balloon_clown"
## Enough to kill anything here through any armour roll.
const KILL_DAMAGE := 9999.0
## Frames waited after a kill: the deferred insertions land at the end of the same physics
## step, and the extra frames give the spawned nodes their `_ready` and first step.
const SETTLE_FRAMES := 6
const HIT_RADIUS := 12.0


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## A scratch parent of its own, so one enemy's spawn cannot be counted as another's.
func _arena() -> Node2D:
	var arena := auto_free(Node2D.new()) as Node2D
	add_child(arena)
	return arena


## Kills `enemy` the way the game does: a player hitbox overlaps its hurtbox and the damage,
## the death and everything the death sets off all run inside the physics query flush.
##
## The box closes on `died`, which `Entity._on_died` emits *before* `_die` runs, so the box is
## already shut by the time the on-death effect spawns anything. Without that the swing was
## still open when the split gremlins landed in the ring and killed one of them at random,
## which is a coin toss inside a test that exists to compare two populations.
func _kill_through_overlap(enemy: EnemyBase) -> void:
	var box := Hitbox.new()
	box.team = Layers.Team.PLAYER
	box.damage = KILL_DAMAGE
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HIT_RADIUS
	shape.shape = circle
	box.add_child(shape)
	enemy.get_parent().add_child(box)
	box.global_position = enemy.global_position
	enemy.died.connect(func(_killer: Node2D) -> void: box.deactivate())
	box.activate(1.0)
	await _physics_frames(SETTLE_FRAMES + 2)
	box.deactivate()
	await _physics_frames(2)


## Kills `enemy` the way the enemy suites do, straight into the hurtbox with no overlap and so
## no flush window. This is the control: whatever it produces is what the game should produce.
func _kill_directly(enemy: EnemyBase) -> void:
	EnemyTestHelpers.hit(enemy, KILL_DAMAGE)
	await _physics_frames(SETTLE_FRAMES)


## Every child of `arena` that is an enemy other than `except`.
func _spawned_enemies(arena: Node2D, except: EnemyBase) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for child: Node in arena.get_children():
		var enemy := child as EnemyBase
		if enemy != null and enemy != except:
			out.append(enemy)
	return out


## Every Projectile child of `arena`.
func _spawned_projectiles(arena: Node2D) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child: Node in arena.get_children():
		var shot := child as Projectile
		if shot != null:
			out.append(shot)
	return out


## The shapes the *physics server* holds for `area`, as a string. Read from the server rather
## than from `CollisionShape2D.shape`, because the node property keeps whatever was assigned to
## it even when the server refused the write - reading the node back would be a measurement
## that cannot fail.
func _server_shapes(area: Area2D) -> String:
	var rid := area.get_rid()
	var out: Array[String] = []
	for i in range(PhysicsServer2D.area_get_shape_count(rid)):
		out.append(str(PhysicsServer2D.shape_get_data(PhysicsServer2D.area_get_shape(rid, i))))
	return ", ".join(out)


## `monitorable` of the Hitbox belonging to the enemy's first attack, or `true` when it has
## none - `true` is the Area2D default, i.e. the value a refused write leaves behind, so a
## missing box reads as the failure rather than as a pass.
func _attack_box_monitorable(enemy: EnemyBase) -> bool:
	for child: Node in enemy.get_children():
		var attack := child as EnemyAttack
		if attack == null:
			continue
		for node: Node in attack.get_children():
			var box := node as Hitbox
			if box != null:
				return box.monitorable
	return true


# ------------------------------------------------------------------ on-death splitting


func test_a_split_through_a_real_overlap_matches_one_outside_the_flush() -> void:
	var flushed := _arena()
	var golem := EnemyTestHelpers.spawn(SPLITTER, flushed, Vector2(100, 100))
	await _physics_frames(2)
	await _kill_through_overlap(golem)
	var in_flush := _spawned_enemies(flushed, golem)

	var control_arena := _arena()
	var control_golem := EnemyTestHelpers.spawn(SPLITTER, control_arena, Vector2(100, 100))
	await _physics_frames(2)
	await _kill_directly(control_golem)
	var control := _spawned_enemies(control_arena, control_golem)

	(
		assert_int(in_flush.size())
		. override_failure_message("a golem killed through a hitbox did not split the same way")
		. is_equal(control.size())
	)
	assert_int(control.size()).is_equal(3)
	for i in range(in_flush.size()):
		(
			assert_str(_server_shapes(in_flush[i].hurtbox))
			. override_failure_message(
				"split gremlin %d reached the physics server with the wrong hurtbox shape" % i
			)
			. is_equal(_server_shapes(control[i].hurtbox))
		)
		assert_str(_server_shapes(in_flush[i].hurtbox)).is_not_empty()
		(
			assert_bool(_attack_box_monitorable(in_flush[i]))
			. override_failure_message(
				(
					"split gremlin %d came up with a monitorable bite box: Hitbox._ready was refused"
					% i
				)
			)
			. is_equal(_attack_box_monitorable(control[i]))
		)
		assert_bool(_attack_box_monitorable(control[i])).is_false()


func test_a_split_through_a_real_overlap_logs_no_engine_error() -> void:
	await assert_error(_split_through_an_overlap).is_success()


func _split_through_an_overlap() -> void:
	var arena := _arena()
	var golem := EnemyTestHelpers.spawn(SPLITTER, arena, Vector2(100, 100))
	await _physics_frames(2)
	await _kill_through_overlap(golem)


# ------------------------------------------------------------------ on-death shrapnel


func test_shrapnel_through_a_real_overlap_matches_one_outside_the_flush() -> void:
	var flushed := _arena()
	var clown := EnemyTestHelpers.spawn(SHRAPNEL, flushed, Vector2(100, 100))
	await _physics_frames(2)
	await _kill_through_overlap(clown)
	var in_flush := _spawned_projectiles(flushed)

	var control_arena := _arena()
	var control_clown := EnemyTestHelpers.spawn(SHRAPNEL, control_arena, Vector2(100, 100))
	await _physics_frames(2)
	await _kill_directly(control_clown)
	var control := _spawned_projectiles(control_arena)

	(
		assert_int(in_flush.size())
		. override_failure_message("a clown killed through a hitbox did not burst the same way")
		. is_equal(control.size())
	)
	assert_int(control.size()).is_equal(6)
	for i in range(in_flush.size()):
		(
			assert_bool(in_flush[i].monitorable)
			. override_failure_message(
				"confetti %d came up monitorable: Projectile._ready's write was refused" % i
			)
			. is_equal(control[i].monitorable)
		)
		(
			assert_int(in_flush[i].collision_layer)
			. override_failure_message("confetti %d came up on the wrong physics layer" % i)
			. is_equal(control[i].collision_layer)
		)
	assert_bool(control.is_empty()).is_false()


func test_shrapnel_through_a_real_overlap_logs_no_engine_error() -> void:
	await assert_error(_shrapnel_through_an_overlap).is_success()


func _shrapnel_through_an_overlap() -> void:
	var arena := _arena()
	var clown := EnemyTestHelpers.spawn(SHRAPNEL, arena, Vector2(100, 100))
	await _physics_frames(2)
	await _kill_through_overlap(clown)


# ------------------------------------------------------- what the deferral must not break


## The property the fix could have destroyed: outside a flush, `spawn_sibling` still inserts
## synchronously, so the callers that read the node straight back (and the enemy suites that
## count children on the next line) keep working.
func test_spawn_sibling_outside_a_flush_is_still_synchronous() -> void:
	var arena := _arena()
	var mime := EnemyTestHelpers.spawn(&"mime", arena, Vector2(100, 100)) as Mime
	await _physics_frames(2)
	var wall := mime.place_wall(Vector2(160, 100))
	(
		assert_object(wall.get_parent())
		. override_failure_message("place_wall deferred an insertion with no flush in progress")
		. is_same(arena)
	)
	assert_float(wall.global_position.y).is_equal_approx(100.0, 0.01)


## And the window really is only the callback: `PhysicsFlush` reports no flush from ordinary
## code and from `_physics_process`, which is where a collider insertion is legal and must stay
## immediate.
func test_the_flush_window_is_closed_outside_a_physics_callback() -> void:
	assert_bool(PhysicsFlush.is_flushing()).is_false()
	await get_tree().physics_frame
	assert_bool(PhysicsFlush.is_flushing()).is_false()


## The counter nests and cannot be driven below zero by an unbalanced exit, because a leaked
## depth would silently defer every insertion in the process for the rest of the run.
func test_the_flush_window_nests_and_clamps() -> void:
	PhysicsFlush.enter()
	PhysicsFlush.enter()
	assert_bool(PhysicsFlush.is_flushing()).is_true()
	PhysicsFlush.exit()
	assert_bool(PhysicsFlush.is_flushing()).is_true()
	PhysicsFlush.exit()
	assert_bool(PhysicsFlush.is_flushing()).is_false()
	PhysicsFlush.exit()
	assert_bool(PhysicsFlush.is_flushing()).is_false()
