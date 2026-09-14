## Where clutter goes (`PropPlacement`): solids in clusters against the walls, flats sparse in
## the open, nothing in a doorway or on the line between two doors. Checked on a hand-built
## room first, then on real generated floors, because the rule that matters is the one the
## generator actually applies.
class_name PropPlacementTest
extends GdUnitTestSuite

## A 9x6 interior with a door in the middle of the north wall and one in the south wall.
const RECT := Rect2i(2, 2, 9, 6)
const NORTH_DOOR := Vector2i(6, 1)
const SOUTH_DOOR := Vector2i(6, 8)
const SEEDS := [1, 2, 3, 5, 8, 13, 21, 34]


func _free() -> Array[Vector2i]:
	return GenUtil.rect_tiles(RECT)


## The crypt catalogue as the typed array `place` takes (`Prop.KINDS` holds untyped arrays).
func _kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for name: Variant in Prop.kind_names(&"crypt"):
		out.append(StringName(name))
	return out


## Wall-side map of the fixture: every tile on the rim of the rectangle, corners counted twice.
func _wall_side() -> Dictionary:
	var out: Dictionary = {}
	for p: Vector2i in _free():
		var walls := 0
		for d: Vector2i in GenUtil.DIRS4:
			if not RECT.has_point(p + d):
				walls += 1
		if walls > 0:
			out[p] = walls
	return out


func _passable() -> Dictionary:
	var out: Dictionary = {}
	for p: Vector2i in _free():
		out[p] = true
	out[NORTH_DOOR] = true
	out[SOUTH_DOOR] = true
	return out


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _place(seed_value: int, budget: int, content: RoomsContent = null) -> Array[Dictionary]:
	var doors: Array[Vector2i] = [NORTH_DOOR, SOUTH_DOOR]
	var avoid := PropPlacement.door_paths(_passable(), doors)
	return PropPlacement.place(
		_free(), _wall_side(), avoid, budget, _kinds(), &"", 0.0, _rng(seed_value), content
	)


## The spacing tests below measure against `PropPlacement.FLAT_SPACING` and `CLUSTER_GAP`, the
## same numbers the placer obeys, so the bound moves with the behaviour and neither test can
## see the spacing collapse. Set both to 0 and every prop may share a tile edge while those
## assertions still pass. These are the literals the constants have to clear, taken from what
## the constants promise rather than from today's values: a flat prop keeps two tiles from
## another flat prop and from any solid, which is what stops a room reading as one object, and
## clusters keep a tile between them so "a wall is never a continuous shelf" stays true.
func test_the_spacing_guarantees_are_numbers_not_tautologies() -> void:
	(
		assert_int(PropPlacement.FLAT_SPACING)
		. override_failure_message(
			(
				(
					"FLAT_SPACING is %d; the placement tests measure against this same constant, "
					+ "so lowering it lowers the guarantee with them and the room fuses into one mass"
				)
				% PropPlacement.FLAT_SPACING
			)
		)
		. is_greater_equal(2)
	)
	(
		assert_int(PropPlacement.CLUSTER_GAP)
		. override_failure_message(
			(
				"CLUSTER_GAP is %d; at 0 a wall becomes the continuous shelf it exists to prevent"
				% PropPlacement.CLUSTER_GAP
			)
		)
		. is_greater_equal(1)
	)


func test_door_paths_join_the_doors_through_the_room_and_exclude_the_doors() -> void:
	var doors: Array[Vector2i] = [NORTH_DOOR, SOUTH_DOOR]
	var path := PropPlacement.door_paths(_passable(), doors)
	assert_bool(path.has(NORTH_DOOR)).is_false()
	assert_bool(path.has(SOUTH_DOOR)).is_false()
	# The straight column between the two doors is the only shortest route.
	for y in range(RECT.position.y, RECT.end.y):
		assert_bool(path.has(Vector2i(6, y))).override_failure_message("row %d" % y).is_true()
	assert_int(path.size()).is_equal(RECT.size.y)
	var sealed := _passable()
	sealed.erase(Vector2i(6, 4))
	for x in range(RECT.position.x, RECT.end.x):
		sealed.erase(Vector2i(x, 4))
	assert_dict(PropPlacement.door_paths(sealed, doors)).is_empty()


func test_solids_cluster_against_walls_and_never_on_the_door_line() -> void:
	var doors: Array[Vector2i] = [NORTH_DOOR, SOUTH_DOOR]
	var avoid := PropPlacement.door_paths(_passable(), doors)
	var wall_side := _wall_side()
	for seed_value: int in SEEDS:
		var placed := _place(seed_value, 8)
		assert_int(placed.size()).is_between(1, 8)
		var solids: Array[Vector2i] = []
		var seen: Dictionary = {}
		for entry: Dictionary in placed:
			var p: Vector2i = entry[PropPlacement.KEY_POS]
			assert_bool(seen.has(p)).override_failure_message("%s placed twice" % p).is_false()
			seen[p] = true
			(
				assert_bool(avoid.has(p))
				. override_failure_message("%s is on the door line" % p)
				. is_false()
			)
			var kind: StringName = entry[PropPlacement.KEY_KIND]
			assert_bool(bool(entry[PropPlacement.KEY_SOLID])).is_equal(Prop.is_solid(kind))
			if Prop.is_solid(kind):
				(
					assert_bool(wall_side.has(p))
					. override_failure_message("solid %s at %s is in the open" % [kind, p])
					. is_true()
				)
				solids.append(p)
		# A cluster is at least two: no solid stands alone unless it is the last of the budget.
		for p: Vector2i in solids:
			var neighbours := 0
			for q: Vector2i in solids:
				if GenUtil.manhattan(p, q) == 1:
					neighbours += 1
			if solids.size() >= PropPlacement.CLUSTER_MIN:
				(
					assert_int(neighbours)
					. override_failure_message(
						"seed %d: solid at %s stands alone" % [seed_value, p]
					)
					. is_greater(0)
				)


## A room whose whole budget is one prop gets one solid, in a corner: a single object against
## a plain wall reads as dropped, in a corner as placed.
func test_a_budget_of_one_is_a_single_solid_in_a_corner() -> void:
	var wall_side := _wall_side()
	for seed_value: int in SEEDS:
		var placed := _place(seed_value, 1)
		assert_int(placed.size()).is_equal(1)
		var p: Vector2i = placed[0][PropPlacement.KEY_POS]
		assert_bool(bool(placed[0][PropPlacement.KEY_SOLID])).is_true()
		(
			assert_int(int(wall_side.get(p, 0)))
			. override_failure_message(
				"seed %d: the lone prop at %s is not in a corner" % [seed_value, p]
			)
			. is_equal(2)
		)


func test_flats_are_sparse_in_the_open_and_clear_of_solids() -> void:
	var wall_side := _wall_side()
	for seed_value: int in SEEDS:
		var placed := _place(seed_value, 8)
		var flats: Array[Vector2i] = []
		var solids: Array[Vector2i] = []
		for entry: Dictionary in placed:
			var p: Vector2i = entry[PropPlacement.KEY_POS]
			if bool(entry[PropPlacement.KEY_SOLID]):
				solids.append(p)
			else:
				flats.append(p)
		for p: Vector2i in flats:
			(
				assert_bool(wall_side.has(p))
				. override_failure_message("flat at %s hugs a wall" % p)
				. is_false()
			)
			for q: Vector2i in flats:
				if q != p:
					assert_int(GenUtil.chebyshev(p, q)).is_greater(PropPlacement.FLAT_SPACING)
			for q: Vector2i in solids:
				assert_int(GenUtil.chebyshev(p, q)).is_greater(PropPlacement.FLAT_SPACING)


func test_clusters_keep_a_gap_from_each_other() -> void:
	var content := RoomsContent.new()
	content.prop_cluster_min = 1
	content.prop_cluster_max = 1
	content.prop_open_flat_share = 0.0
	for seed_value: int in SEEDS:
		var placed := _place(seed_value, 6, content)
		var solids: Array[Vector2i] = []
		for entry: Dictionary in placed:
			solids.append(entry[PropPlacement.KEY_POS])
		assert_int(solids.size()).is_greater(1)
		for p: Vector2i in solids:
			for q: Vector2i in solids:
				if q != p:
					(
						assert_int(GenUtil.chebyshev(p, q))
						. override_failure_message("seed %d: %s touches %s" % [seed_value, p, q])
						. is_greater(PropPlacement.CLUSTER_GAP)
					)


func test_the_signature_kind_takes_its_share_of_the_slots() -> void:
	var pool: Array[StringName] = [&"barrel", &"crate", &"sack"]
	var names := PropPlacement.assign_kinds(10, pool, &"crate", 4, _rng(7))
	assert_int(names.size()).is_equal(10)
	assert_int(names.count(&"crate")).is_greater_equal(4)
	var none := PropPlacement.assign_kinds(10, pool, &"coffin", 4, _rng(7))
	assert_int(none.count(&"coffin")).is_equal(0)
	assert_array(PropPlacement.assign_kinds(0, pool, &"crate", 4, _rng(7))).is_empty()
	# Through `place`: a solid signature takes its share of the whole room off the wall slots.
	var doors: Array[Vector2i] = [NORTH_DOOR, SOUTH_DOOR]
	var avoid := PropPlacement.door_paths(_passable(), doors)
	var placed := PropPlacement.place(
		_free(), _wall_side(), avoid, 8, _kinds(), &"coffin", 0.4, _rng(3)
	)
	var coffins := 0
	for entry: Dictionary in placed:
		if entry[PropPlacement.KEY_KIND] == &"coffin":
			coffins += 1
	assert_int(coffins).is_greater_equal(roundi(placed.size() * 0.4))


func test_the_resource_overrides_the_constants_and_an_empty_one_does_not() -> void:
	var empty := RoomsContent.new()
	assert_float(PropPlacement.per_free_tile(empty)).is_equal(PropPlacement.PER_FREE_TILE)
	assert_int(PropPlacement.cluster_min(empty)).is_equal(PropPlacement.CLUSTER_MIN)
	assert_int(PropPlacement.cluster_max(empty)).is_equal(PropPlacement.CLUSTER_MAX)
	assert_float(PropPlacement.open_flat_share(empty)).is_equal(PropPlacement.OPEN_FLAT_SHARE)
	assert_float(PropPlacement.corner_weight(empty)).is_equal(PropPlacement.CORNER_WEIGHT)
	var tuned := RoomsContent.new()
	tuned.prop_per_free_tile = 0.2
	tuned.prop_cluster_min = 3
	tuned.prop_cluster_max = 2  # never below the minimum
	tuned.prop_open_flat_share = 0.5
	tuned.prop_corner_weight = 5.0
	assert_float(PropPlacement.per_free_tile(tuned)).is_equal(0.2)
	assert_int(PropPlacement.cluster_min(tuned)).is_equal(3)
	assert_int(PropPlacement.cluster_max(tuned)).is_equal(3)
	assert_float(PropPlacement.open_flat_share(tuned)).is_equal(0.5)
	assert_float(PropPlacement.corner_weight(tuned)).is_equal(5.0)
	assert_float(PropPlacement.expected_count(100, 0.5, 2.0, tuned)).is_equal_approx(20.0, 0.001)
	var shipped := RoomsContent.load_default()
	assert_object(shipped).is_not_null()
	assert_float(shipped.prop_per_free_tile).is_greater(0.0)
	assert_int(shipped.prop_cluster_min).is_greater(0)


## The rules on a real floor, every room of it: a solid prop hugs a wall of its room, no prop
## of any kind sits on a door apron, and the two doors of every pair stay joined by a route no
## prop is on (`RoomFiller.doors_connected` already prunes for that; this reads it back).
func test_generated_floors_keep_solids_on_the_walls_and_doorways_clear() -> void:
	for seed_value: int in [11, 23, 47]:
		for floor_index: int in [0, 4, 7]:
			var params := GenParams.from_profile(
				GenParamsTest.profile_for("tokyo-night"), floor_index
			)
			var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
			var data := FloorGenerator.generate(params, rng)
			var total := 0
			for room: FloorData.Room in data.rooms:
				var doors: Array = room.doors.values()
				for i in range(room.prop_positions.size()):
					var p: Vector2i = room.prop_positions[i]
					var kind: StringName = room.prop_kinds[i]
					total += 1
					for door: Vector2i in doors:
						(
							assert_int(GenUtil.chebyshev(door, p))
							. override_failure_message(
								(
									"seed %d floor %d room %d: %s at %s is in the doorway"
									% [seed_value, floor_index, room.id, kind, p]
								)
							)
							. is_greater(1)
						)
					if not Prop.is_solid(kind) or room.fill_template != &"empty":
						continue
					var hugs_wall := false
					for d: Vector2i in GenUtil.DIRS4:
						var q := p + d
						if (
							not room.rect.has_point(q)
							and data.get_tile(q.x, q.y) == FloorData.Tile.WALL
						):
							hugs_wall = true
					(
						assert_bool(hugs_wall)
						. override_failure_message(
							(
								"seed %d floor %d room %d: solid %s at %s is in the open"
								% [seed_value, floor_index, room.id, kind, p]
							)
						)
						. is_true()
					)
			assert_int(total).override_failure_message("a floor with no props").is_greater(0)


## The other half of the solid flag, which the test above never reaches.
##
## In the 9x6 fixture every entry the placer returns is a solid: the wall ring fills the budget,
## and `open_slots` blanks what is left of a 7x4 interior because every tile is within
## `FLAT_SPACING` of something already placed. So the flag assertion above only ever compares
## `true` with `true`. Proven by mutation: hard-coding `KEY_SOLID` to `true` in
## `PropPlacement.place` left that test green, while hard-coding it to `false` failed it - the
## assertion could catch a solid reported flat and never a flat reported solid.
##
## That is the direction that matters to the lighting layer, which hangs an occluder on exactly
## this flag: a flat prop wrongly marked solid grows a shadow it should not have
## (`Prop._apply_solidity`, docs 10). A room with an interior big enough to survive the spacing
## is what puts flats on the floor, so this case builds one.
func test_a_full_room_places_flats_too_and_the_flag_follows_the_kind() -> void:
	var rect := Rect2i(2, 2, 17, 13)
	var free := GenUtil.rect_tiles(rect)
	var wall_side: Dictionary = {}
	for p: Vector2i in free:
		var walls := 0
		for d: Vector2i in GenUtil.DIRS4:
			if not rect.has_point(p + d):
				walls += 1
		if walls > 0:
			wall_side[p] = walls
	var solids := 0
	var flats := 0
	for seed_value: int in SEEDS:
		var placed := PropPlacement.place(
			free, wall_side, {}, 12, _kinds(), &"", 0.0, _rng(seed_value), null
		)
		for entry: Dictionary in placed:
			var kind: StringName = entry[PropPlacement.KEY_KIND]
			var flagged := bool(entry[PropPlacement.KEY_SOLID])
			(
				assert_bool(flagged)
				. override_failure_message(
					(
						"seed %d: %s is flagged %s, the catalogue says %s"
						% [seed_value, kind, flagged, Prop.is_solid(kind)]
					)
				)
				. is_equal(Prop.is_solid(kind))
			)
			if flagged:
				solids += 1
			else:
				flats += 1
	(
		assert_int(flats)
		. override_failure_message(
			(
				"no flat prop was placed, so the flag was never checked in the direction "
				+ "that grows a shadow on a decoration"
			)
		)
		. is_greater(0)
	)
	assert_int(solids).is_greater(0)
