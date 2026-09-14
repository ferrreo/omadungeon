## FrameSampler is the thing every perf number in this module is read off, so its statistics
## are pinned here rather than trusted.
class_name FrameSamplerTest
extends GdUnitTestSuite


func test_empty_sampler_reports_zero_not_nan() -> void:
	var s := FrameSampler.new()
	assert_int(s.count()).is_equal(0)
	assert_float(s.average_ms()).is_equal(0.0)
	assert_float(s.worst_ms()).is_equal(0.0)
	assert_float(s.best_ms()).is_equal(0.0)
	assert_float(s.percentile_ms(0.95)).is_equal(0.0)
	assert_float(s.average_fps()).is_equal(0.0)


func test_seconds_in_milliseconds_out() -> void:
	var s := FrameSampler.new()
	s.feed(0.016)
	s.feed(0.008)
	assert_float(s.average_ms()).is_equal_approx(12.0, 0.001)
	assert_float(s.worst_ms()).is_equal_approx(16.0, 0.001)
	assert_float(s.best_ms()).is_equal_approx(8.0, 0.001)
	assert_float(s.average_fps()).is_equal_approx(1000.0 / 12.0, 0.001)


func test_percentile_is_nearest_rank() -> void:
	var s := FrameSampler.new()
	for i in range(1, 101):
		s.feed(float(i) / 1000.0)
	# 100 samples of 1..100 ms: the 95th percentile is the 95th value, not an interpolation.
	assert_float(s.percentile_ms(0.95)).is_equal_approx(95.0, 0.001)
	assert_float(s.percentile_ms(0.5)).is_equal_approx(50.0, 0.001)
	assert_float(s.percentile_ms(1.0)).is_equal_approx(100.0, 0.001)
	assert_float(s.percentile_ms(0.0)).is_equal_approx(1.0, 0.001)


func test_over_budget_counts_only_frames_past_the_budget() -> void:
	var s := FrameSampler.new()
	s.feed(0.010)
	s.feed(0.020)
	s.feed(0.030)
	assert_int(s.over_budget(16.67)).is_equal(2)
	assert_int(s.over_budget(100.0)).is_equal(0)


func test_capacity_keeps_the_most_recent_window() -> void:
	var s := FrameSampler.new(3)
	for i in range(10):
		s.feed(float(i) / 1000.0)
	assert_int(s.count()).is_equal(3)
	assert_float(s.best_ms()).is_equal_approx(7.0, 0.001)
	assert_float(s.worst_ms()).is_equal_approx(9.0, 0.001)


func test_negative_samples_are_clamped_not_recorded_as_negative_time() -> void:
	var s := FrameSampler.new()
	s.feed(-1.0)
	assert_float(s.worst_ms()).is_equal(0.0)


func test_to_dict_and_format_line_carry_the_reported_numbers() -> void:
	var s := FrameSampler.new()
	s.feed(0.004)
	var d := s.to_dict()
	assert_int(int(d["frames"])).is_equal(1)
	assert_float(float(d["average_ms"])).is_equal_approx(4.0, 0.001)
	assert_str(s.format_line("sim")).contains("sim: 1 frames avg 4.00 ms")
