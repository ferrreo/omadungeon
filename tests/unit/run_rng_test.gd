class_name RunRngTest
extends GdUnitTestSuite


func test_streams_are_independent_and_deterministic() -> void:
	var a := RunRng.new(1234)
	var b := RunRng.new(1234)
	var gen_a := a.stream(&"gen").randi()
	a.stream(&"combat").randi()
	a.stream(&"combat").randi()
	var gen_b := b.stream(&"gen").randi()
	assert_int(gen_a).is_equal(gen_b)
	assert_int(a.stream(&"gen").randi()).is_equal(b.stream(&"gen").randi())
	assert_int(a.stream(&"gen").seed).is_not_equal(a.stream(&"loot").seed)


func test_floor_streams_differ_per_floor() -> void:
	var r := RunRng.new(99)
	assert_int(r.floor_stream(&"gen", 0).seed).is_not_equal(r.floor_stream(&"gen", 1).seed)
	assert_int(r.floor_stream(&"gen", 2).randi()).is_equal(
		RunRng.new(99).floor_stream(&"gen", 2).randi()
	)


func test_seed_from_string() -> void:
	assert_int(RunRng.seed_from_string("42")).is_equal(42)
	assert_int(RunRng.seed_from_string("gruvbox")).is_equal(RunRng.seed_from_string("gruvbox"))
