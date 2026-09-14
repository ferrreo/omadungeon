## The per-floor room curation (docs 5.1 #4): not every room type on every floor. The first
## floor has no elite and no gauntlet, every floor has exactly one altar or shrine, the shop
## is guaranteed on the middle floor of each act and only rolled elsewhere, and the balance
## simulation rolls the very same mix.
class_name RoomBudgetTest
extends GdUnitTestSuite

const SEEDS := 100


func _generate(theme: String, seed_value: int, floor_index: int) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
	return FloorGenerator.generate(params, rng)


func _counts(data: FloorData) -> Dictionary:
	var counts: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		counts[room.type] = int(counts.get(room.type, 0)) + 1
	return counts


func test_the_table_covers_every_floor() -> void:
	assert_int(RoomBudget.TABLE.size()).is_equal(GenParams.LAST_FLOOR + 1)
	for i in range(RoomBudget.TABLE.size()):
		var row := RoomBudget.for_floor(i)
		for key: String in ["altar", "shop", "elite", "trap", "treasure"]:
			assert_bool(row.has(key)).is_true()
			assert_float(float(row[key])).is_between(0.0, 1.0)
	assert_dict(RoomBudget.for_floor(99)).is_equal(RoomBudget.for_floor(GenParams.LAST_FLOOR))


func test_the_first_floor_has_no_elite_no_gauntlet_and_no_shop() -> void:
	assert_int(RoomBudget.max_count(0, FloorData.RoomType.ELITE)).is_equal(0)
	assert_int(RoomBudget.max_count(0, FloorData.RoomType.TRAP)).is_equal(0)
	assert_int(RoomBudget.max_count(0, FloorData.RoomType.SHOP)).is_equal(0)
	for i in range(SEEDS):
		var counts := _counts(_generate("gruvbox", 2000 + i, 0))
		assert_int(int(counts.get(FloorData.RoomType.ELITE, 0))).is_equal(0)
		assert_int(int(counts.get(FloorData.RoomType.TRAP, 0))).is_equal(0)
		assert_int(int(counts.get(FloorData.RoomType.SHOP, 0))).is_equal(0)
		assert_int(int(counts.get(FloorData.RoomType.ALTAR, 0))).is_equal(1)


func test_every_floor_holds_one_altar_or_shrine_never_both() -> void:
	for floor_index in range(9):
		for i in range(SEEDS / 4):
			var counts := _counts(_generate("tokyo-night", 3000 + i * 7, floor_index))
			var altars := int(counts.get(FloorData.RoomType.ALTAR, 0))
			var shrines := int(counts.get(FloorData.RoomType.SHRINE, 0))
			assert_int(altars + shrines).is_equal(1)
			assert_int(int(counts.get(FloorData.RoomType.SHOP, 0))).is_less_equal(1)


func test_the_shop_is_guaranteed_on_the_middle_floor_of_each_act_and_rolled_elsewhere() -> void:
	for floor_index: int in [1, 4, 7]:
		assert_bool(RoomBudget.shop_guaranteed(floor_index)).is_true()
		for i in range(SEEDS / 4):
			var counts := _counts(_generate("catppuccin", 4000 + i * 3, floor_index))
			assert_int(int(counts.get(FloorData.RoomType.SHOP, 0))).is_equal(1)
	for floor_index: int in [3, 6]:
		assert_bool(RoomBudget.shop_guaranteed(floor_index)).is_false()
		var with_shop := 0
		for i in range(SEEDS / 2):
			var counts := _counts(_generate("catppuccin", 5000 + i * 3, floor_index))
			with_shop += int(counts.get(FloorData.RoomType.SHOP, 0))
		assert_int(with_shop).is_between(1, SEEDS / 2 - 1)


func test_optional_rooms_respect_their_floor_caps_and_still_turn_up() -> void:
	for floor_index in range(9):
		var seen: Dictionary = {}
		for i in range(SEEDS / 2):
			var counts := _counts(_generate("nord", 6000 + i * 11, floor_index))
			for type: int in FloorGraph.OPTIONAL_TYPES:
				var n := int(counts.get(type, 0))
				assert_int(n).is_less_equal(
					RoomBudget.max_count(floor_index, type as FloorData.RoomType)
				)
				if n > 0:
					seen[type] = true
		for type: int in FloorGraph.OPTIONAL_TYPES:
			var allowed := RoomBudget.max_count(floor_index, type as FloorData.RoomType) > 0
			(
				assert_bool(seen.has(type))
				. override_failure_message(
					"room type %d allowed on floor %d but never rolled" % [type, floor_index]
				)
				. is_equal(allowed)
			)


func test_the_fight_quota_still_holds() -> void:
	for i in range(SEEDS):
		var data := _generate("white", 7000 + i, i % 9)
		var free_pool := 0
		var fights := 0
		for room: FloorData.Room in data.rooms:
			if room.type in FloorGraph.STRUCTURAL_TYPES or room.type in FloorGraph.SERVICE_TYPES:
				continue
			free_pool += 1
			if room.type in FloorGraph.FIGHT_TYPES:
				fights += 1
		assert_int(fights).is_greater_equal(FloorGraph.combat_quota(free_pool))


func test_the_roll_itself_matches_the_table() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for floor_index in range(9):
		for _i in range(40):
			var types := RoomBudget.roll(floor_index, 9, rng)
			assert_int(types.size()).is_equal(9)
			for type: int in FloorGraph.OPTIONAL_TYPES:
				assert_int(types.count(type)).is_less_equal(
					RoomBudget.max_count(floor_index, type as FloorData.RoomType)
				)
			var blessings := (
				types.count(FloorData.RoomType.ALTAR) + types.count(FloorData.RoomType.SHRINE)
			)
			assert_int(blessings).is_equal(1)
			if RoomBudget.shop_guaranteed(floor_index):
				assert_int(types.count(FloorData.RoomType.SHOP)).is_equal(1)


func test_the_balance_simulation_rolls_the_same_mix() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for floor_index in range(9):
		var plan := SimFloorPlan.build(floor_index, rng)
		var altars := plan.rooms.count(FloorData.RoomType.ALTAR)
		var shrines := plan.rooms.count(FloorData.RoomType.SHRINE)
		assert_int(altars + shrines).is_equal(1)
		assert_int(plan.rooms.count(FloorData.RoomType.SHOP)).is_less_equal(
			RoomBudget.max_count(floor_index, FloorData.RoomType.SHOP)
		)
		assert_int(plan.rooms.count(FloorData.RoomType.ELITE)).is_less_equal(
			RoomBudget.max_count(floor_index, FloorData.RoomType.ELITE)
		)
		assert_int(plan.rooms.size()).is_equal(SimFloorPlan.room_count(floor_index))
