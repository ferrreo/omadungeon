class_name FxPoolTest
extends GdUnitTestSuite

## Enough puffs to force the pool to grow past anything a previous test left behind.
const WAVE := 12

var _pool: FxPool


func before_test() -> void:
	_pool = FxPool.instance(get_tree())
	_pool.clear()


func after_test() -> void:
	_pool.clear()


func test_a_second_wave_of_puffs_allocates_nothing() -> void:
	for i in range(WAVE):
		_pool.puff(Vector2(i * 8, 0), Color.WHITE)
	var high_water := _pool.allocations()
	assert_int(_pool.active_count()).is_equal(WAVE)
	assert_int(high_water).is_greater_equal(WAVE)
	_pool.clear()
	assert_int(_pool.idle_count()).is_greater_equal(WAVE)
	for i in range(WAVE):
		_pool.puff(Vector2(i * 8, 0), Color.WHITE)
	assert_int(_pool.allocations()).is_equal(high_water)


func test_puffs_return_themselves_to_the_pool_when_they_are_done() -> void:
	_pool.puff(Vector2.ZERO, Color.WHITE)
	assert_int(_pool.active_count()).is_equal(1)
	var guard := 0
	while _pool.active_count() > 0 and guard < 600:
		guard += 1
		await get_tree().process_frame
	assert_int(_pool.active_count()).is_equal(0)
	assert_int(_pool.idle_count()).is_greater(0)


func test_a_trail_follows_its_target_and_drains_when_the_target_dies() -> void:
	var mover := auto_free(Node2D.new()) as Node2D
	add_child(mover)
	mover.global_position = Vector2(40, 12)
	var emitter := _pool.trail(mover, Color.RED)
	assert_object(emitter).is_not_null()
	assert_bool(emitter.emitting).is_true()
	mover.global_position = Vector2(90, 30)
	await get_tree().process_frame
	assert_vector(emitter.global_position).is_equal(Vector2(90, 30))
	# The plume must outlive the projectile it belonged to instead of blinking out with it.
	mover.get_parent().remove_child(mover)
	await get_tree().process_frame
	assert_bool(emitter.emitting).is_false()
	assert_int(_pool.active_count()).is_equal(1)
	var guard := 0
	while _pool.active_count() > 0 and guard < 600:
		guard += 1
		await get_tree().process_frame
	assert_int(_pool.active_count()).is_equal(0)
	mover.queue_free()


func test_release_hands_a_trail_back_early() -> void:
	var mover := auto_free(Node2D.new()) as Node2D
	add_child(mover)
	var emitter := _pool.trail(mover, Color.GREEN)
	_pool.release(emitter)
	assert_bool(emitter.emitting).is_false()
	var guard := 0
	while _pool.active_count() > 0 and guard < 600:
		guard += 1
		await get_tree().process_frame
	assert_int(_pool.active_count()).is_equal(0)


func test_prewarm_pays_the_allocation_cost_up_front() -> void:
	_pool.clear()
	var before := _pool.allocations()
	_pool.prewarm(before + 4)
	var after := _pool.allocations()
	assert_int(after).is_greater_equal(before)
	assert_int(_pool.idle_count()).is_greater_equal(4)
	for i in range(4):
		_pool.puff(Vector2(i, 0), Color.WHITE)
	assert_int(_pool.allocations()).is_equal(after)


func test_a_new_floor_returns_every_borrowed_emitter() -> void:
	for i in range(4):
		_pool.puff(Vector2(i * 4, 0), Color.WHITE)
	assert_int(_pool.active_count()).is_equal(4)
	EventBus.floor_started.emit(1)
	assert_int(_pool.active_count()).is_equal(0)


func test_a_trail_survives_its_target_being_freed_outright() -> void:
	# Projectiles are freed mid-flight all the time; holding the follower by reference and
	# casting it once it is gone is a runtime error ("Trying to cast a freed object").
	var mover := Node2D.new()
	add_child(mover)
	var emitter := _pool.trail(mover, Color.BLUE)
	await get_tree().process_frame
	mover.free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(emitter.emitting).is_false()
	var guard := 0
	while _pool.active_count() > 0 and guard < 600:
		guard += 1
		await get_tree().process_frame
	assert_int(_pool.active_count()).is_equal(0)
	assert_int(_pool.idle_count()).is_greater(0)
