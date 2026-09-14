class_name EnemySpawnerTest
extends GdUnitTestSuite

const ROLLS := 500


func _total_cost(defs: Array[EnemyDef]) -> float:
	var total := 0.0
	for def: EnemyDef in defs:
		total += def.cost
	return total


func test_combat_rooms_respect_budget_and_faction_weights() -> void:
	var registry := EnemyTestHelpers.registry()
	var rng := EnemyTestHelpers.seeded(42)
	var weights := {&"clowns": 6.0, &"greybeards": 0.2, &"tinkerers": 0.2}
	var clowns := 0
	var total := 0
	for floor_index in range(3):
		# The per-floor pack budget is data now (data/balance/difficulty_curve.tres), so the
		# ramp can be shaped floor by floor rather than being a straight line in code.
		var budget := EnemySpawner.budget_for(FloorData.RoomType.COMBAT, floor_index)
		assert_float(budget).is_equal_approx(
			DifficultyCurve.shared().budget_for(floor_index), 0.001
		)
		for _i in range(ROLLS):
			var picks := EnemySpawner.pick_for_room(
				registry, FloorData.RoomType.COMBAT, floor_index, weights, rng
			)
			assert_int(picks.size()).is_greater(0)
			assert_float(_total_cost(picks)).is_less_equal(budget + 0.001)
			for def: EnemyDef in picks:
				assert_bool(def.is_elite).is_false()
				total += 1
				if def.faction == EnemyDef.Faction.CLOWNS:
					clowns += 1
	assert_float(float(clowns) / total).is_greater(0.75)


func test_elite_rooms_have_exactly_one_elite() -> void:
	var registry := EnemyTestHelpers.registry()
	var rng := EnemyTestHelpers.seeded(7)
	var weights := {EnemyDef.Faction.CLOWNS: 1.0, EnemyDef.Faction.GREYBEARDS: 1.0}
	for _i in range(ROLLS):
		var elite_budget := DifficultyCurve.shared().budget_for(1) * EnemySpawner.ELITE_BUDGET_MULT
		var picks := EnemySpawner.pick_for_room(registry, FloorData.RoomType.ELITE, 1, weights, rng)
		var elites := 0
		for def: EnemyDef in picks:
			if def.is_elite:
				elites += 1
		assert_int(elites).is_equal(1)
		assert_float(_total_cost(picks)).is_less_equal(elite_budget + 0.001)


func test_trap_rooms_use_40_percent_and_others_none() -> void:
	var registry := EnemyTestHelpers.registry()
	var rng := EnemyTestHelpers.seeded(3)
	for _i in range(ROLLS):
		var picks := EnemySpawner.pick_for_room(registry, FloorData.RoomType.TRAP, 0, {}, rng)
		var trap_budget := DifficultyCurve.shared().budget_for(0) * EnemySpawner.TRAP_BUDGET_MULT
		assert_float(_total_cost(picks)).is_less_equal(trap_budget + 0.001)
		assert_int(picks.size()).is_greater(0)
	for room_type: int in [
		FloorData.RoomType.START,
		FloorData.RoomType.TREASURE,
		FloorData.RoomType.SHOP,
		FloorData.RoomType.BOSS
	]:
		assert_int(EnemySpawner.pick_for_room(registry, room_type, 0, {}, rng).size()).is_equal(0)


func test_zero_weight_faction_never_appears() -> void:
	var registry := EnemyTestHelpers.registry()
	var rng := EnemyTestHelpers.seeded(11)
	var weights := {&"tinkerers": 0.0}
	for _i in range(ROLLS):
		for def: EnemyDef in EnemySpawner.pick_for_room(
			registry, FloorData.RoomType.COMBAT, 4, weights, rng
		):
			assert_that(def.faction).is_not_equal(EnemyDef.Faction.TINKERERS)


func test_picks_are_deterministic() -> void:
	var registry := EnemyTestHelpers.registry()
	var a := EnemySpawner.pick_for_room(
		registry, FloorData.RoomType.COMBAT, 3, {}, EnemyTestHelpers.seeded(99)
	)
	var b := EnemySpawner.pick_for_room(
		registry, FloorData.RoomType.COMBAT, 3, {}, EnemyTestHelpers.seeded(99)
	)
	assert_int(a.size()).is_equal(b.size())
	for i in range(a.size()):
		assert_that(a[i].id).is_equal(b[i].id)
