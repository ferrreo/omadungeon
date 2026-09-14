class_name FloorGraphTest
extends GdUnitTestSuite


func _params(floor_index: int) -> GenParams:
	return GenParams.from_profile(GenParamsTest.profile_for("catppuccin"), floor_index)


func _rng(seed_value: int) -> RandomNumberGenerator:
	return RunRng.new(seed_value).floor_stream(&"gen", 0)


func test_type_guarantees_hold_for_many_seeds() -> void:
	for seed_value in range(200):
		var floor_index := seed_value % 9
		var params := _params(floor_index)
		var g := FloorGraph.build(params, _rng(seed_value))
		assert_int(g.nodes.size()).is_equal(params.room_count)
		assert_int(g.count_type(FloorData.RoomType.START)).is_equal(1)
		# One blessing room per floor - an altar or a shrine, never both - and a shop only
		# where the per-floor budget allows one (docs 5.1 #4, `RoomBudget`).
		var blessings := (
			g.count_type(FloorData.RoomType.ALTAR) + g.count_type(FloorData.RoomType.SHRINE)
		)
		assert_int(blessings).is_equal(1)
		assert_int(g.count_type(FloorData.RoomType.SHOP)).is_less_equal(
			RoomBudget.max_count(floor_index, FloorData.RoomType.SHOP)
		)
		for optional: int in FloorGraph.OPTIONAL_TYPES:
			assert_int(g.count_type(optional as FloorData.RoomType)).is_less_equal(
				RoomBudget.max_count(floor_index, optional as FloorData.RoomType)
			)
		var free_pool := 0
		var fights := 0
		for node: FloorGraph.RoomVertex in g.nodes:
			if node.type in FloorGraph.STRUCTURAL_TYPES or node.type in FloorGraph.SERVICE_TYPES:
				continue
			free_pool += 1
			if node.type in FloorGraph.FIGHT_TYPES:
				fights += 1
		(
			assert_int(fights)
			. override_failure_message(
				(
					"seed %d floor %d: %d of %d free rooms are fights"
					% [seed_value, floor_index, fights, free_pool]
				)
			)
			. is_greater_equal(FloorGraph.combat_quota(free_pool))
		)


func test_every_special_type_the_budget_allows_can_appear_on_every_floor() -> void:
	# Regression: the combat quota used to eat every optional slot on floors 0-2, so elite,
	# trap gauntlet and treasure rooms were mathematically impossible for the whole first act.
	# Since the per-floor budget (docs 5.1 #4) the first floor deliberately has no elite and
	# no gauntlet, so the check is "whatever the table allows does turn up".
	for floor_index in range(9):
		var seen: Dictionary = {}
		for seed_value in range(150):
			var g := FloorGraph.build(_params(floor_index), _rng(seed_value * 31 + floor_index))
			for type: int in FloorGraph.OPTIONAL_TYPES:
				if g.count_type(type as FloorData.RoomType) > 0:
					seen[type] = true
		for type: int in FloorGraph.OPTIONAL_TYPES:
			var allowed := RoomBudget.max_count(floor_index, type as FloorData.RoomType) > 0
			(
				assert_bool(seen.has(type))
				. override_failure_message(
					(
						"room type %d allowed=%s on floor %d, seen=%s"
						% [type, allowed, floor_index, seen.has(type)]
					)
				)
				. is_equal(allowed)
			)


func test_stairs_at_least_three_edges_from_start() -> void:
	for seed_value in range(200):
		var params := _params(seed_value % 2)
		var g := FloorGraph.build(params, _rng(seed_value))
		assert_int(g.nodes[g.stairs_id].distance).is_greater_equal(3)
		assert_int(g.nodes[g.stairs_id].type).is_equal(FloorData.RoomType.STAIRS)
		assert_int(g.boss_id).is_equal(-1)


func test_boss_floor_is_linear_ish() -> void:
	for seed_value in range(100):
		var params := _params(2)
		var g := FloorGraph.build(params, _rng(seed_value))
		assert_int(g.boss_id).is_greater_equal(0)
		assert_int(g.stairs_id).is_equal(g.boss_id)
		var boss := g.nodes[g.boss_id]
		assert_int(boss.type).is_equal(FloorData.RoomType.BOSS)
		assert_int(boss.neighbors.size()).is_equal(1)
		assert_int(boss.distance).is_between(3, 4)
		# Every room hangs at most two branches off the spine.
		for node: FloorGraph.RoomVertex in g.nodes:
			assert_int(node.branch_depth).is_less_equal(2)


func test_tree_is_connected_and_spanning() -> void:
	for seed_value in range(50):
		var params := _params(seed_value % 9)
		var g := FloorGraph.build(params, _rng(seed_value))
		assert_int(g.tree_edges.size()).is_equal(g.nodes.size() - 1)
		for node: FloorGraph.RoomVertex in g.nodes:
			assert_int(node.distance).is_greater_equal(0)
		assert_int(g.bfs_order().size()).is_equal(g.nodes.size())


func test_loops_never_shorten_stairs_below_three() -> void:
	for seed_value in range(100):
		var params := _params(4)
		var rng := _rng(seed_value)
		var g := FloorGraph.build(params, rng)
		var all_pairs: Array[Vector2i] = []
		for a in range(g.nodes.size()):
			for b in range(a + 1, g.nodes.size()):
				all_pairs.append(Vector2i(a, b))
		g.add_loops(all_pairs, 3, rng)
		assert_int(g.loop_edges.size()).is_between(1, 3)
		assert_int(g.nodes[g.stairs_id].distance).is_greater_equal(3)
		for node: FloorGraph.RoomVertex in g.nodes:
			assert_int(node.neighbors.size()).is_less_equal(g.degree_cap(node.id))
