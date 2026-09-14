class_name DangerTellTest
extends GdUnitTestSuite

## A windup long enough to sample the ramp at both ends.
const WINDUP := 0.6


func _profile() -> FeelProfile:
	return DangerTell.default_profile()


func test_enemy_windup_and_trap_arming_speak_the_same_language() -> void:
	var trap := auto_free(TrapBase.new()) as TrapBase
	trap.hitbox_size = Vector2(16, 16)
	add_child(trap)
	await get_tree().physics_frame
	# Same pulse rate...
	assert_float(TrapBase.TELL_PULSE_HZ).is_equal_approx(_profile().tell_pulse_hz, 0.0001)
	# ...same alpha band...
	assert_float(trap._tell_color(0.0).a).is_equal_approx(_profile().tell_alpha_min, 0.0001)
	assert_float(trap._tell_color(1.0).a).is_equal_approx(_profile().tell_alpha_max, 0.0001)
	# ...and the same theme role, so nothing that hurts is ever a different colour.
	assert_int(DangerTell.ROLE.hash()).is_equal(StringName("danger").hash())
	var expected := DangerTell.color()
	assert_float(trap._tell_color(1.0).r).is_equal_approx(expected.r, 0.001)
	assert_float(trap._tell_color(1.0).g).is_equal_approx(expected.g, 0.001)
	assert_float(trap._tell_color(1.0).b).is_equal_approx(expected.b, 0.001)


func test_the_tell_gets_brighter_as_the_hit_gets_closer() -> void:
	# Sampled at the same phase of the pulse so only urgency differs.
	var period := 1.0 / _profile().tell_pulse_hz
	var early := DangerTell.alpha(0.0, WINDUP)
	var late := DangerTell.alpha(period * 3.0, WINDUP)
	assert_float(late).is_greater(early)
	assert_float(DangerTell.urgency(0.0, WINDUP)).is_equal_approx(0.0, 0.0001)
	assert_float(DangerTell.urgency(WINDUP, WINDUP)).is_equal_approx(1.0, 0.0001)
	assert_float(DangerTell.urgency(WINDUP * 2.0, WINDUP)).is_equal_approx(1.0, 0.0001)


func test_alpha_never_leaves_the_profile_band() -> void:
	for i in range(40):
		var t := WINDUP * float(i) / 40.0
		var a := DangerTell.alpha(t, WINDUP)
		assert_float(a).is_greater_equal(_profile().tell_alpha_min - 0.0001)
		assert_float(a).is_less_equal(_profile().tell_alpha_max + 0.0001)


func test_the_pulse_is_time_based_so_long_and_short_tells_throb_alike() -> void:
	var period := 1.0 / _profile().tell_pulse_hz
	assert_float(DangerTell.pulse(0.0)).is_equal_approx(DangerTell.pulse(period), 0.001)
	assert_float(DangerTell.pulse(period * 0.75)).is_less(0.05)
	assert_float(DangerTell.pulse(period * 0.25)).is_greater(0.95)


func test_the_windup_ring_grows_into_its_radius() -> void:
	assert_float(DangerTell.ring_radius(0.0, WINDUP, 20.0)).is_equal_approx(
		20.0 * DangerTell.RING_START, 0.001
	)
	assert_float(DangerTell.ring_radius(WINDUP, WINDUP, 20.0)).is_equal_approx(20.0, 0.001)
	assert_float(DangerTell.ring_radius(WINDUP * 0.5, WINDUP, 20.0)).is_greater(
		DangerTell.ring_radius(0.0, WINDUP, 20.0)
	)


func test_an_enemy_windup_runs_the_shared_tell() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2(100, 100))
	await get_tree().physics_frame
	enemy.telegraph.flash(WINDUP, enemy.telegraph_radius())
	assert_bool(enemy.telegraph.is_active()).is_true()
	assert_float(enemy.telegraph.elapsed()).is_equal_approx(0.0, 0.001)
	# A poll with a deadline, not a fixed pair of frames. `Telegraph` ticks in `_process`, on the
	# engine's own idle schedule, and `SceneTree.process_frame` fires *before* the frame's
	# `_process` dispatch - so whether the tell has advanced when a two-frame wait returns depends
	# on where the awaits land in the iteration, which depends on machine load. Measured: 12 of 12
	# green run alone, 1 of 10 red under ten concurrent gates, failing `elapsed() > 0` with a flat
	# 0.0. That is a red gate naming a healthy suite, which docs/TESTING.md's waiting rule exists
	# to prevent ("a poll with a deadline reports one honest failure; a frame count reports a
	# different result depending on machine load"). The property asserted is unchanged.
	var elapsed := 0.0
	for _i in range(120):
		await get_tree().process_frame
		elapsed = enemy.telegraph.elapsed()
		if elapsed > 0.0:
			break
	(
		assert_float(elapsed)
		. override_failure_message("the windup tell never advanced in 120 frames")
		. is_greater(0.0)
	)
	var tint := enemy.telegraph.color
	var danger := DangerTell.color()
	assert_float(tint.r).is_equal_approx(danger.r, 0.001)
	assert_float(tint.g).is_equal_approx(danger.g, 0.001)
	assert_float(tint.b).is_equal_approx(danger.b, 0.001)


func test_the_windup_ring_draws_above_the_floor_and_below_its_own_body() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2(100, 100))
	await get_tree().process_frame
	await get_tree().physics_frame
	# The floor tilemaps sit at z 0: a negative index would bury the tell under the ground
	# (exactly what `TrapBase` documents for its own overlay), so it must stay at 0...
	assert_int(enemy.telegraph.z_index).is_equal(0)
	assert_bool(enemy.telegraph.z_as_relative).is_true()
	# ...and draw under the body it belongs to by being the first child instead.
	assert_object(enemy.get_child(0)).is_same(enemy.telegraph)
	assert_int(enemy.sprite.get_index()).is_greater(enemy.telegraph.get_index())
