class_name FloorGeneratorTest
extends GdUnitTestSuite

const SEEDS_PER_THEME := 300


func _generate(theme: String, seed_value: int, floor_index: int) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
	return FloorGenerator.generate(params, rng)


func test_same_seed_same_layout_hash() -> void:
	for seed_value: int in [1, 42, 9001, -77]:
		for floor_index: int in [0, 2, 4, 7]:
			var a := _generate("gruvbox", seed_value, floor_index)
			var b := _generate("gruvbox", seed_value, floor_index)
			assert_int(a.layout_hash()).is_equal(b.layout_hash())
			assert_str(a.to_ascii()).is_equal(b.to_ascii())
			assert_int(a.rooms.size()).is_equal(b.rooms.size())
			for i in range(a.rooms.size()):
				assert_int(a.rooms[i].palette_variant).is_equal(b.rooms[i].palette_variant)
				assert_str(String(a.rooms[i].fill_template)).is_equal(
					String(b.rooms[i].fill_template)
				)
				assert_array(a.rooms[i].prop_kinds).is_equal(b.rooms[i].prop_kinds)


func test_different_seeds_differ() -> void:
	var a := _generate("nord", 1, 3)
	var b := _generate("nord", 2, 3)
	assert_int(a.layout_hash()).is_not_equal(b.layout_hash())


func test_validator_passes_for_every_theme_and_seed() -> void:
	var failures: Array[String] = []
	var checked := 0
	for theme: String in GenParamsTest.THEMES:
		var profile := GenParamsTest.profile_for(theme)
		for seed_value in range(SEEDS_PER_THEME):
			var floor_index := seed_value % 9
			var params := GenParams.from_profile(profile, floor_index, float(seed_value % 5) / 4.0)
			var rng := RunRng.new(seed_value * 7919 + 13).floor_stream(&"gen", floor_index)
			var data := FloorGenerator.generate(params, rng)
			var violations := FloorValidator.validate(data)
			checked += 1
			if not violations.is_empty():
				failures.append(
					"%s seed %d floor %d: %s" % [theme, seed_value, floor_index, violations]
				)
				if failures.size() > 8:
					break
	assert_int(checked).is_equal(SEEDS_PER_THEME * GenParamsTest.THEMES.size())
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_first_attempt_is_valid_most_of_the_time() -> void:
	# Retries are a safety net, not the normal path: the first pass must validate nearly always.
	var profile := GenParamsTest.profile_for("tokyo-night")
	var ok := 0
	var total := 120
	for seed_value in range(total):
		var floor_index := seed_value % 9
		var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
		var data := FloorGenerator.generate_once(GenParams.from_profile(profile, floor_index), rng)
		if data != null and FloorValidator.validate(data).is_empty():
			ok += 1
	assert_int(ok).is_greater_equal(int(total * 0.9))


func test_room_type_guarantees_and_stairs_distance() -> void:
	for seed_value in range(60):
		var floor_index := seed_value % 9
		var data := _generate("catppuccin", seed_value, floor_index)
		var counts: Dictionary = {}
		for room: FloorData.Room in data.rooms:
			counts[room.type] = int(counts.get(room.type, 0)) + 1
		assert_int(int(counts.get(FloorData.RoomType.START, 0))).is_equal(1)
		# An altar or a shrine, never both; a shop only where the floor budget allows one.
		var blessings := (
			int(counts.get(FloorData.RoomType.ALTAR, 0))
			+ int(counts.get(FloorData.RoomType.SHRINE, 0))
		)
		assert_int(blessings).is_equal(1)
		assert_int(int(counts.get(FloorData.RoomType.SHOP, 0))).is_less_equal(
			RoomBudget.max_count(floor_index, FloorData.RoomType.SHOP)
		)
		assert_int(data.rooms[data.stairs_room].graph_distance).is_greater_equal(3)
		assert_int(data.rooms[data.start_room].graph_distance).is_equal(0)
		if GenParams.is_boss_floor_index(floor_index):
			assert_int(data.boss_room).is_greater_equal(0)
			var boss := data.rooms[data.boss_room]
			assert_int(boss.type).is_equal(FloorData.RoomType.BOSS)
			assert_int(boss.neighbors.size()).is_equal(1)
			assert_int(boss.doors.size()).is_equal(1)
			assert_int(boss.graph_distance).is_between(3, 4)
			# The boss's spot first, then the fallback pack's (`ArenaSpawns`).
			assert_int(boss.enemy_spawns.size()).is_between(1, ArenaSpawns.PACK_SPOTS + 1)
			assert_bool(boss.rect.size == FloorLayout.SIZE_ARENA).is_true()
			assert_int(data.stairs_room).is_equal(data.boss_room)
		else:
			assert_int(data.boss_room).is_equal(-1)
			assert_int(data.rooms[data.stairs_room].type).is_equal(FloorData.RoomType.STAIRS)


func test_grid_bounds_and_room_separation() -> void:
	for seed_value in range(60):
		var data := _generate("white", seed_value, 8)
		assert_int(data.width).is_between(1, FloorLayout.MAX_WIDTH)
		assert_int(data.height).is_between(1, FloorLayout.MAX_HEIGHT)
		assert_int(data.tiles.size()).is_equal(data.width * data.height)
		for a: FloorData.Room in data.rooms:
			(
				assert_bool(Rect2i(1, 1, data.width - 2, data.height - 2).encloses(a.rect.grow(1)))
				. is_true()
			)
			for b: FloorData.Room in data.rooms:
				if a.id < b.id:
					assert_int(GenUtil.rect_gap(a.rect, b.rect)).is_greater_equal(3)


func test_no_spawns_near_doors_and_no_overlaps() -> void:
	for seed_value in range(60):
		var data := _generate("gruvbox", seed_value, seed_value % 9)
		for room: FloorData.Room in data.rooms:
			var occupied: Dictionary = {}
			for p: Vector2i in room.enemy_spawns:
				assert_bool(room.rect.has_point(p)).is_true()
				assert_bool(data.is_walkable(p.x, p.y)).is_true()
				assert_bool(occupied.has(p)).is_false()
				occupied[p] = true
				for door: Vector2i in room.door_tiles():
					assert_int(GenUtil.chebyshev(door, p)).is_greater_equal(3)
			for p: Vector2i in room.prop_positions:
				assert_bool(occupied.has(p)).is_false()
				occupied[p] = true
			for trap: Dictionary in room.trap_positions:
				var p: Vector2i = trap["pos"]
				assert_bool(occupied.has(p)).is_false()
				occupied[p] = true
			assert_int(room.prop_kinds.size()).is_equal(room.prop_positions.size())
			if room.type == FloorData.RoomType.START:
				assert_array(room.enemy_spawns).is_empty()
				assert_array(room.trap_positions).is_empty()


func test_traps_and_props_respect_biome() -> void:
	for floor_index: int in [0, 4, 7]:
		var data := _generate("tokyo-night", 5, floor_index)
		var biome := Biome.load_by_id(data.biome)
		for room: FloorData.Room in data.rooms:
			for trap: Dictionary in room.trap_positions:
				var kind: StringName = trap["kind"]
				(
					assert_bool(biome.allows_trap(kind))
					. override_failure_message(String(kind))
					. is_true()
				)
			for kind: StringName in room.prop_kinds:
				assert_bool(kind in biome.prop_kinds).is_true()


func test_palette_variants_roughly_60_20_15_5() -> void:
	var counts := PackedInt32Array([0, 0, 0, 0])
	var total := 0
	for seed_value in range(120):
		var data := _generate("nord", seed_value, seed_value % 9)
		for room: FloorData.Room in data.rooms:
			counts[room.palette_variant] += 1
			total += 1
	assert_float(float(counts[0]) / total).is_between(0.5, 0.7)
	assert_float(float(counts[1]) / total).is_between(0.12, 0.28)
	assert_float(float(counts[2]) / total).is_between(0.08, 0.22)
	assert_float(float(counts[3]) / total).is_between(0.01, 0.1)


func test_fill_templates_are_used() -> void:
	var seen: Dictionary = {}
	for seed_value in range(40):
		var data := _generate("gruvbox", seed_value, 1)
		for room: FloorData.Room in data.rooms:
			seen[room.fill_template] = true
	assert_int(seen.size()).is_greater_equal(4)


func test_corridors_are_ringed_and_doors_open() -> void:
	var data := _generate("catppuccin-latte", 3, 4)
	for y in range(data.height):
		for x in range(data.width):
			if data.get_tile(x, y) != FloorData.Tile.CORRIDOR:
				continue
			for d: Vector2i in GenUtil.DIRS8:
				assert_int(data.get_tile(x + d.x, y + d.y)).is_not_equal(FloorData.Tile.VOID)
	for corridor: FloorData.Corridor in data.corridors:
		assert_bool(corridor.path.is_empty()).is_false()
		var door_a: Vector2i = data.rooms[corridor.from_room].doors[corridor.to_room]
		var door_b: Vector2i = data.rooms[corridor.to_room].doors[corridor.from_room]
		assert_int(GenUtil.manhattan(corridor.path[0], door_a)).is_equal(1)
		assert_int(GenUtil.manhattan(corridor.path[corridor.path.size() - 1], door_b)).is_equal(1)


func test_performance_100_floors_under_3_seconds() -> void:
	var profile := GenParamsTest.profile_for("gruvbox")
	var start := Time.get_ticks_msec()
	for i in range(100):
		var floor_index := i % 9
		var rng := RunRng.new(1000 + i).floor_stream(&"gen", floor_index)
		var data := FloorGenerator.generate(GenParams.from_profile(profile, floor_index), rng)
		assert_bool(data.rooms.is_empty()).is_false()
	var elapsed := Time.get_ticks_msec() - start
	# The bound is a statement about a player's machine; a shared runner gets
	# `PerfBudget.allowance` (see there for the measurements that made it necessary).
	var allowed := PerfBudget.allowance(3.0) * 1000.0
	print("100 floors generated in %d ms (budget %d ms)" % [elapsed, int(allowed)])
	assert_float(float(elapsed)).is_less(allowed)


func test_print_one_floor_for_eyeballing() -> void:
	var data := _generate("gruvbox", 7, 4)
	print(
		(
			"\nfloor %d biome %s %dx%d rooms=%d corridors=%d"
			% [
				data.floor_index,
				data.biome,
				data.width,
				data.height,
				data.rooms.size(),
				data.corridors.size()
			]
		)
	)
	print(data.to_ascii_annotated())
	assert_array(FloorValidator.validate(data)).is_empty()
