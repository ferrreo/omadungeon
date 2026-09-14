## BeatDetector on synthetic energy series: onsets at pulses, refractory period, BPM estimate.
class_name BeatDetectorTest
extends GdUnitTestSuite


func test_detects_pulses_at_120_bpm() -> void:
	var d := BeatDetector.new()
	var onsets := 0
	var dt := 1.0 / 60.0
	var t := 0.0
	for i in 600:
		var beat_phase := fmod(t, 0.5)
		var e := 0.1
		if beat_phase < 0.05:
			e = 1.0
		if d.feed(e, t):
			onsets += 1
		t += dt
	assert_int(onsets).is_between(17, 20)
	assert_float(d.bpm()).is_between(115.0, 125.0)
	assert_float(d.last_strength()).is_between(0.3, 1.0)


func test_silence_and_constant_signal_never_trigger() -> void:
	var d := BeatDetector.new()
	var dt := 1.0 / 60.0
	for i in 300:
		assert_bool(d.feed(0.0, i * dt)).is_false()
	d.reset()
	for i in 300:
		assert_bool(d.feed(0.5, i * dt)).is_false()
	assert_float(d.bpm()).is_equal(0.0)


func test_refractory_period_blocks_double_hits() -> void:
	var d := BeatDetector.new()
	var dt := 1.0 / 60.0
	for i in 30:
		d.feed(0.1, i * dt)
	assert_bool(d.feed(1.0, 30 * dt)).is_true()
	assert_bool(d.feed(1.0, 31 * dt)).is_false()
	assert_bool(d.feed(1.0, 36 * dt)).is_false()
	assert_int(d.onset_count()).is_equal(1)
