## The per-frame cost of enemy AI, pinned as behaviour rather than as a stopwatch reading.
##
## Forty enemies used to mean, every single physics frame and per enemy: one group array for
## the player scan, one for separation, a `NavigationServer2D.map_get_regions()` array asked
## twice, and up to three raycasts. These cases assert that each of those is now shared,
## latched or interval-gated, so a regression shows up as a failed test and not as a slow game.
class_name EnemyAiCostTest
extends GdUnitTestSuite


func test_enemy_group_is_scanned_once_per_physics_frame() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	EnemyTestHelpers.spawn(&"honker", root, Vector2(0, 0))
	EnemyTestHelpers.spawn(&"honker", root, Vector2(24, 0))
	await get_tree().physics_frame
	var first := EnemyBase.enemies_this_frame(get_tree())
	var again := EnemyBase.enemies_this_frame(get_tree())
	# Same frame, same array instance: every enemy shares one scan.
	assert_bool(is_same(first, again)).is_true()
	assert_int(first.size()).is_equal(2)
	await get_tree().physics_frame
	var next_frame := EnemyBase.enemies_this_frame(get_tree())
	assert_bool(is_same(first, next_frame)).is_false()
	assert_int(next_frame.size()).is_equal(2)


func test_retarget_is_interval_gated_but_a_lost_target_is_immediate() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var near := EnemyTestPlayer.new()
	root.add_child(near)
	near.global_position = Vector2(40, 0)
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	await _frames(2)
	assert_object(enemy.target).is_same(near)

	# A second, much closer hero appears: within the interval the enemy keeps chasing the one
	# it already picked, because retargeting is not a per-frame decision any more.
	var closer := EnemyTestPlayer.new()
	root.add_child(closer)
	closer.global_position = enemy.global_position + Vector2(4, 0)
	await get_tree().physics_frame
	assert_object(enemy.target).is_same(near)

	# Losing the target is not something the enemy may wait out: it rescans the same frame.
	near.queue_free()
	await _frames(2)
	assert_object(enemy.target).is_same(closer)


func test_retarget_catches_up_after_the_interval() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var first := EnemyTestPlayer.new()
	root.add_child(first)
	first.global_position = Vector2(60, 0)
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	await _frames(2)
	assert_object(enemy.target).is_same(first)
	var closer := EnemyTestPlayer.new()
	root.add_child(closer)
	closer.global_position = Vector2(8, 0)
	# One interval's worth of frames (60 Hz physics) and the scan happens again.
	await _frames(int(EnemyBase.RETARGET_INTERVAL * 60.0) + 4)
	assert_object(enemy.target).is_same(closer)


func test_line_of_sight_is_cached_inside_the_cache_window() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	await _frames(2)
	var open_point := Vector2(40, 0)
	assert_bool(enemy.has_line_of_sight(open_point)).is_true()
	# A wall appears across the same line. Inside the cache window the enemy keeps the answer
	# it already paid a raycast for — that reuse is the whole point.
	EnemyTestHelpers.wall(root, Vector2(20, 0), Vector2(8, 64))
	await get_tree().physics_frame
	assert_bool(enemy.has_line_of_sight(open_point)).is_true()
	# ...and after the window it pays for a fresh answer, which is now the correct one.
	await _frames(int(EnemyBase.LOS_CACHE_TIME * 60.0) + 4)
	assert_bool(enemy.has_line_of_sight(open_point)).is_false()


func test_line_of_sight_cache_does_not_cover_a_different_direction() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	EnemyTestHelpers.wall(root, Vector2(20, 0), Vector2(8, 64))
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	await _frames(2)
	assert_bool(enemy.has_line_of_sight(Vector2(40, 0))).is_false()
	# Far outside LOS_CACHE_TOLERANCE, so the cached "blocked" answer must not be reused.
	assert_bool(enemy.has_line_of_sight(Vector2(-40, 0))).is_true()


## The probe gets a navigation map of its own. `nav_ready()` answers from whatever map the
## agent is on, and the default World2D map is process-wide: a suite that leaves a baked
## `NavigationRegion2D` on it (every `FloorRoot` bakes into exactly that map) would flip this
## assertion from the other side of the tree. The map created here can only hold what this
## test put on it, which is nothing.
func test_nav_readiness_answers_a_missing_map_without_the_allocating_probe() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_active(map, true)
	enemy.nav_agent.set_navigation_map(map)
	await _frames(2)
	assert_bool(NavigationServer2D.map_get_regions(map).is_empty()).is_true()
	# With no baked region the answer is a cheap, repeatable false — and it must stay cheap
	# *and* immediate, because an enemy has to start pathing on the frame the region appears.
	assert_bool(enemy.nav_ready()).is_false()
	assert_bool(enemy.nav_ready()).is_false()
	await _frames(int(EnemyBase.NAV_READY_INTERVAL * 60.0) + 2)
	assert_bool(enemy.nav_ready()).is_false()
	NavigationServer2D.free_rid(map)


## ...and the other half of the same statement, which nothing asserted: a region on the map the
## agent is actually using flips it to true. Without this the case above passes just as happily
## against a `nav_ready()` that has been broken into always answering false.
func test_nav_readiness_turns_true_on_the_map_the_agent_uses() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_active(map, true)
	NavigationServer2D.map_set_cell_size(map, 1.0)
	enemy.nav_agent.set_navigation_map(map)
	await _frames(2)
	assert_bool(enemy.nav_ready()).is_false()
	var region := NavigationServer2D.region_create()
	NavigationServer2D.region_set_map(region, map)
	var poly := NavigationPolygon.new()
	poly.add_outline(
		PackedVector2Array([Vector2(-64, -64), Vector2(64, -64), Vector2(64, 64), Vector2(-64, 64)])
	)
	poly.make_polygons_from_outlines()
	NavigationServer2D.region_set_navigation_polygon(region, poly)
	# Past the interval the false answer above bought: the latch is re-asked, not cached.
	await _frames(int(EnemyBase.NAV_READY_INTERVAL * 60.0) + 4)
	assert_bool(enemy.nav_ready()).is_true()
	NavigationServer2D.free_rid(region)
	NavigationServer2D.free_rid(map)


func test_repath_is_interval_gated() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	await _frames(2)
	var far_a := Vector2(400, 0)
	var far_b := Vector2(-400, 0)
	enemy.steer_toward(far_a)
	var after_first := enemy.nav_agent.target_position
	assert_that(after_first).is_equal(far_a)
	# A second, very different destination in the same frame must not trigger a second path
	# recompute: repathing is interval-based (docs §14, "repath on an interval, not per frame").
	enemy.steer_toward(far_b)
	assert_that(enemy.nav_agent.target_position).is_equal(after_first)
	await _frames(int(EnemyBase.REPATH_INTERVAL * 60.0) + 4)
	enemy.steer_toward(far_b)
	assert_that(enemy.nav_agent.target_position).is_equal(far_b)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
