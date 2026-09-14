## Pooled projectiles: a recycled shot must be indistinguishable from a fresh `Projectile.new()`
## and must not accumulate signal connections, and an unclaimed pooled shot must still be freed.
class_name ProjectilePoolTest
extends GdUnitTestSuite


func test_default_projectiles_still_free_themselves_on_expiry() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var shot := Projectile.new()
	shot.setup(null, Layers.Team.PLAYER, Vector2.RIGHT, Callable(), 100.0, 0.02)
	root.add_child(shot)
	assert_bool(shot.pooled).is_false()
	await _frames(4)
	assert_bool(is_instance_valid(shot) and not shot.is_queued_for_deletion()).is_false()


func test_pooled_shot_is_handed_back_and_reused() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var pool := NodePool.new(func() -> Node: return Projectile.new(), Projectile.reset_for_pool)
	var caught: Array[Projectile] = []
	var first := pool.acquire() as Projectile
	first.setup(null, Layers.Team.PLAYER, Vector2.RIGHT, Callable(), 100.0, 0.02)
	first.pooled = true
	# The contract: the owner recycles the shot from inside `expired`. A listener that only
	# looks is not an owner, and the shot frees itself instead (see the unclaimed case below).
	first.expired.connect(
		func(p: Projectile) -> void:
			caught.append(p)
			pool.release(p)
	)
	root.add_child(first)
	await _frames(4)
	assert_int(caught.size()).is_equal(1)
	assert_bool(is_instance_valid(first)).is_true()
	assert_object(first.get_parent()).is_null()
	assert_int(pool.size()).is_equal(1)
	var second := pool.acquire() as Projectile
	assert_object(second).is_same(first)
	assert_int(pool.created).is_equal(1)
	second.free()
	pool.clear()


func test_reset_returns_every_field_to_the_class_default() -> void:
	var shot := auto_free(Projectile.new()) as Projectile
	shot.speed = 999.0
	shot.lifetime = 42.0
	shot.pierce = 7
	shot.bounces = 3
	shot.arc_gravity = 500.0
	shot.homing_strength = 4.0
	shot.rotate_to_direction = false
	shot.modulate = Color.RED
	var owner_node := auto_free(Node2D.new()) as Node2D
	shot.setup(
		owner_node, Layers.Team.ENEMY, Vector2.UP, func(_t: Node2D) -> DamageInfo: return null
	)
	shot.pooled = true
	Projectile.reset_for_pool(shot)
	var fresh := auto_free(Projectile.new()) as Projectile
	assert_float(shot.speed).is_equal(fresh.speed)
	assert_float(shot.lifetime).is_equal(fresh.lifetime)
	assert_int(shot.pierce).is_equal(fresh.pierce)
	assert_int(shot.bounces).is_equal(fresh.bounces)
	assert_float(shot.arc_gravity).is_equal(fresh.arc_gravity)
	assert_float(shot.homing_strength).is_equal(fresh.homing_strength)
	assert_bool(shot.rotate_to_direction).is_equal(fresh.rotate_to_direction)
	assert_bool(shot.pooled).is_false()
	assert_object(shot.source).is_null()
	assert_bool(shot.damage_builder.is_valid()).is_false()
	assert_that(shot.direction).is_equal(fresh.direction)
	assert_that(shot.team).is_equal(fresh.team)
	assert_that(shot.modulate).is_equal(Color.WHITE)


func test_reuse_does_not_stack_signal_connections() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var pool := NodePool.new(func() -> Node: return Projectile.new(), Projectile.reset_for_pool)
	var recycle := func(p: Projectile) -> void: pool.release(p)
	var shot := pool.acquire() as Projectile
	for i in range(3):
		shot.setup(null, Layers.Team.PLAYER, Vector2.RIGHT, Callable(), 100.0, 0.02)
		shot.pooled = true
		if not shot.expired.is_connected(recycle):
			shot.expired.connect(recycle)
		root.add_child(shot)
		await _frames(1)
		# `_ready()` runs again on every re-add, so a connection made there would double up.
		assert_int(shot.hitbox.hit_dealt.get_connections().size()).is_equal(1)
		assert_int(shot.body_entered.get_connections().size()).is_equal(1)
		assert_int(shot.expired.get_connections().size()).is_equal(1)
		await _frames(4)
		shot = pool.acquire() as Projectile
	assert_int(pool.created).is_equal(1)
	shot.free()
	pool.clear()


func test_acquire_parks_the_shot_again_without_the_caller_doing_anything() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	Projectile.clear_pool()
	var before := Projectile.pool().created
	var first := Projectile.acquire()
	assert_bool(first.pooled).is_true()
	first.setup(null, Layers.Team.PLAYER, Vector2.RIGHT, Callable(), 100.0, 0.02)
	root.add_child(first)
	await _frames(6)
	# Nobody listened to `expired`, and the shot is neither leaked in the tree nor freed: it
	# put itself back. That is the whole point of `acquire()` being a drop-in for `new()`.
	assert_bool(is_instance_valid(first)).is_true()
	assert_object(first.get_parent()).is_null()
	assert_int(Projectile.pool().size()).is_greater(0)
	var second := Projectile.acquire()
	assert_object(second).is_same(first)
	assert_int(Projectile.pool().created - before).is_equal(1)
	second.free()
	Projectile.clear_pool()


func test_a_recycled_shot_carries_nothing_over_from_its_last_flight() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	Projectile.clear_pool()
	var first := Projectile.acquire()
	first.pierce = 4
	first.bounces = 2
	first.arc_gravity = 300.0
	first.modulate = Color.RED
	first.setup(self_as_node2d(), Layers.Team.ENEMY, Vector2.UP, Callable(), 100.0, 0.02)
	root.add_child(first)
	await _frames(6)
	var again := Projectile.acquire()
	assert_object(again).is_same(first)
	var fresh := auto_free(Projectile.new()) as Projectile
	assert_int(again.pierce).is_equal(fresh.pierce)
	assert_int(again.bounces).is_equal(fresh.bounces)
	assert_float(again.arc_gravity).is_equal(fresh.arc_gravity)
	assert_that(again.modulate).is_equal(Color.WHITE)
	assert_that(again.team).is_equal(fresh.team)
	assert_bool(again.visible).is_true()
	assert_object(again.source).is_null()
	again.free()
	Projectile.clear_pool()


## A Node2D owned by the suite, for calls that need a real Node2D source.
func self_as_node2d() -> Node2D:
	var node := auto_free(Node2D.new()) as Node2D
	add_child(node)
	return node


func test_default_hitboxes_share_one_shape_resource() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var shapes: Array[Shape2D] = []
	for i in range(3):
		var shot := Projectile.new()
		shot.setup(null, Layers.Team.PLAYER, Vector2.RIGHT, Callable(), 100.0, 5.0)
		root.add_child(shot)
		var collider := shot.hitbox.get_child(0) as CollisionShape2D
		shapes.append(collider.shape)
	assert_object(shapes[1]).is_same(shapes[0])
	assert_object(shapes[2]).is_same(shapes[0])
	assert_float((shapes[0] as CircleShape2D).radius).is_equal(Projectile.HIT_RADIUS)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
