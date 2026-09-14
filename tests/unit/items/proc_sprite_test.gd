class_name ProcSpriteTest
extends GdUnitTestSuite


func test_deterministic_per_seed_and_family() -> void:
	for family: StringName in ProcSprite.FAMILIES:
		var a := ProcSprite.generate_image(12345, family)
		var b := ProcSprite.generate_image(12345, family)
		assert_array(Array(a.get_data())).is_equal(Array(b.get_data()))
		var c := ProcSprite.generate_image(12346, family)
		assert_int(a.get_width()).is_equal(16)
		assert_int(c.get_height()).is_equal(16)


func test_mirror_symmetric() -> void:
	for family: StringName in ProcSprite.FAMILIES:
		for seed_value in range(20):
			var image := ProcSprite.generate_image(seed_value * 7919, family)
			var size := image.get_width()
			for y in range(size):
				for x in range(size / 2):
					(
						assert_object(image.get_pixel(x, y))
						. override_failure_message(
							"%s seed %d asymmetric at %d,%d" % [family, seed_value, x, y]
						)
						. is_equal(image.get_pixel(size - 1 - x, y))
					)


func test_not_empty_and_has_outline() -> void:
	for family: StringName in ProcSprite.FAMILIES:
		var image := ProcSprite.generate_image(99, family)
		var opaque := 0
		var outline := 0
		for y in range(16):
			for x in range(16):
				var px := image.get_pixel(x, y)
				if px.a > 0.0:
					opaque += 1
					if px.is_equal_approx(ProcSprite.DEFAULT_COLORS[family][0]):
						outline += 1
		assert_int(opaque).override_failure_message("%s empty" % family).is_greater(20)
		assert_int(outline).override_failure_message("%s no outline" % family).is_greater(4)


func test_seeds_produce_variety() -> void:
	var seen: Dictionary = {}
	for seed_value in range(30):
		seen[Array(ProcSprite.generate_image(seed_value, &"ring").get_data()).hash()] = true
	assert_int(seen.size()).is_greater(10)


func test_cache_returns_same_texture_and_custom_colors() -> void:
	ProcSprite.clear_cache()
	var a := ProcSprite.generate(5, &"wand")
	var b := ProcSprite.generate(5, &"wand")
	assert_object(a).is_same(b)
	var colors: Array[Color] = [
		Color.BLACK, Color.RED, Color.GREEN, Color.BLUE, Color.WHITE, Color.YELLOW
	]
	var c := ProcSprite.generate(5, &"wand", colors)
	assert_object(c).is_not_same(a)
	var d := ProcSprite.generate(5, &"wand", colors, 32)
	assert_int(d.get_width()).is_equal(32)
	assert_object(ProcSprite.generate(1, &"bogus")).is_not_null()


func test_for_item_prefers_authored_icon() -> void:
	var registry := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var sword := ItemGenerator.instance_of(registry.find_base(&"rusty_sword"), rng)
	assert_object(ProcSprite.for_item(sword)).is_same(sword.base.icon)
	var ring := ItemGenerator.instance_of(registry.find_base(&"ring_iron"), rng)
	var icon := ProcSprite.for_item(ring)
	assert_object(icon).is_not_null()
	assert_object(ProcSprite.for_item(ring)).is_same(icon)
	assert_object(ProcSprite.for_item(null)).is_not_null()


func test_cache_stays_bounded() -> void:
	ProcSprite.clear_cache()
	for i in range(1000):
		ProcSprite.generate(i, &"ring")
	var loop := Engine.get_main_loop()
	var cache: Dictionary = loop.get_meta(ProcSprite.CACHE_META)
	assert_int(cache.size()).is_less_equal(ProcSprite.CACHE_LIMIT)
	# the most recent entry is still cached (only the oldest are dropped)
	var last := ProcSprite.generate(999, &"ring")
	assert_object(ProcSprite.generate(999, &"ring")).is_same(last)
	ProcSprite.clear_cache()
