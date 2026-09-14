class_name ProjectileFeelTest
extends GdUnitTestSuite

## Shots fired in the "busy screen" wave.
const WAVE := 10

var _pool: FxPool
var _root: Node2D


func before_test() -> void:
	_pool = FxPool.instance(get_tree())
	_pool.clear()
	_root = auto_free(Node2D.new()) as Node2D
	add_child(_root)


func after_test() -> void:
	_pool.clear()


func _shot(tint: Color = Color.WHITE, life: float = 2.0) -> Projectile:
	var proj := Projectile.new()
	proj.modulate = tint
	proj.lifetime = life
	_root.add_child(proj)
	return proj


func test_a_shot_borrows_a_pooled_trail_tinted_with_its_own_colour() -> void:
	var proj := _shot(Color(0.2, 0.6, 1.0))
	await get_tree().physics_frame
	assert_int(_pool.active_count()).is_equal(1)
	assert_bool(proj.trail_enabled).is_true()
	assert_float(proj.fx_tint().b).is_equal_approx(1.0, 0.001)
	assert_float(proj.fx_tint().a).is_equal_approx(1.0, 0.001)
	proj.queue_free()


func test_a_shot_that_ends_releases_its_trail_and_pops_a_puff() -> void:
	var proj := _shot(Color.WHITE, 0.05)
	await get_tree().physics_frame
	var borrowed := _pool.active_count()
	assert_int(borrowed).is_equal(1)
	# Lifetime expiry runs `_expire`, which hands the trail back and adds the impact puff.
	await FeelTestHelpers.physics_frames(get_tree(), 8)
	assert_bool(is_instance_valid(proj)).is_false()
	assert_int(_pool.active_count()).is_greater(0)
	var guard := 0
	while _pool.active_count() > 0 and guard < 600:
		guard += 1
		await get_tree().process_frame
	assert_int(_pool.active_count()).is_equal(0)


func test_a_busy_screen_of_shots_allocates_nothing_the_second_time() -> void:
	var first: Array[Projectile] = []
	for i in range(WAVE):
		var proj := _shot()
		proj.global_position = Vector2(i * 6, 0)
		first.append(proj)
	await get_tree().physics_frame
	assert_int(_pool.active_count()).is_equal(WAVE)
	for proj: Projectile in first:
		proj._expire()
	await FeelTestHelpers.physics_frames(get_tree(), 2)
	var guard := 0
	while _pool.active_count() > 0 and guard < 600:
		guard += 1
		await get_tree().process_frame
	# High-water mark of the first wave: its trails plus the puffs its deaths popped.
	var high_water := _pool.allocations()
	assert_int(high_water).is_greater_equal(WAVE)
	# Second wave: same number of shots, not one new particle node.
	for i in range(WAVE):
		var proj := _shot()
		proj.global_position = Vector2(i * 6, 0)
	await get_tree().physics_frame
	assert_int(_pool.allocations()).is_equal(high_water)


func test_trails_can_be_switched_off_for_shots_with_their_own_art() -> void:
	var proj := Projectile.new()
	proj.trail_enabled = false
	proj.impact_puff = false
	_root.add_child(proj)
	await get_tree().physics_frame
	assert_int(_pool.active_count()).is_equal(0)
	proj._expire()
	await get_tree().physics_frame
	assert_int(_pool.active_count()).is_equal(0)
