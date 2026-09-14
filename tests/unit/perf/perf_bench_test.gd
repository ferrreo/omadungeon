## The design target from docs §13.4, as far as a headless run can measure it: the
## CPU/simulation cost of the budgeted projectile and enemy load, inside a 60 fps frame.
## Nothing here rasterises a frame, so "60 fps" is a claim about script time and not about
## any GPU. The benchmark drives a real run, so this suite is also the end-to-end smoke test
## for "the game still simulates a full floor under load".
class_name PerfBenchTest
extends GdUnitTestSuite

var _bench: PerfBench


func before_test() -> void:
	_bench = PerfBench.new()
	add_child(_bench)


func after_test() -> void:
	if is_instance_valid(_bench):
		await _bench.teardown()
		_bench.queue_free()
	await _frames(2)


func test_target_load_holds_the_frame_budget() -> void:
	var report := await _bench.run_load()
	prints("\n" + PerfBench.format_report(report))
	var budget := _bench.budget
	assert_int(int(report["projectiles"])).is_greater_equal(budget.projectile_count - 10)
	assert_int(int(report["enemies"])).is_greater_equal(budget.enemy_count - 2)
	var frames: Dictionary = report["frames"]
	assert_float(float(frames["average_ms"])).is_less(budget.average_budget_ms)
	assert_float(float(frames["p95_ms"])).is_less(budget.p95_budget_ms)
	assert_float(float(frames["worst_ms"])).is_less(budget.worst_budget_ms)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
