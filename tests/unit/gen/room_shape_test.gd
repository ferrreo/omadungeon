## Non-rectangular rooms (docs 5.1 #2): the cut shapes keep the centre the player, the stairs
## and the altar need, every door still opens onto floor, and at least two rooms in five on
## a generated floor are not plain boxes.
class_name RoomShapeTest
extends GdUnitTestSuite

const SEEDS := 200
const MIN_NON_RECT_SHARE := 0.4
const SIZES: Array[Vector2i] = [
	FloorLayout.SIZE_CLOSET,
	FloorLayout.SIZE_SMALL,
	FloorLayout.SIZE_MEDIUM,
	FloorLayout.SIZE_LARGE,
	FloorLayout.SIZE_HALL,
	FloorLayout.SIZE_GALLERY,
	FloorLayout.SIZE_ARENA,
	FloorLayout.SIZE_HUB,
	Vector2i(9, 13),
	Vector2i(7, 17),
]


func _generate(theme: String, seed_value: int, floor_index: int) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
	return FloorGenerator.generate(params, rng)


func test_every_shape_keeps_the_centre_three_by_three() -> void:
	for size: Vector2i in SIZES:
		for shape: StringName in RoomShape.ALL:
			if not RoomShape.fits(shape, size):
				continue
			var rect := Rect2i(Vector2i(10, 10), size)
			var centre := rect.position + rect.size / 2
			for variant in range(4):
				var cut := RoomShape.cut_tiles(shape, rect, variant)
				for p: Vector2i in cut:
					assert_bool(rect.has_point(p)).is_true()
					(
						assert_int(GenUtil.chebyshev(p, centre))
						. override_failure_message(
							"%s on %s cuts the centre at %s" % [shape, size, p]
						)
						. is_greater_equal(2)
					)


func test_cut_shapes_remove_something_and_rect_removes_nothing() -> void:
	var rect := Rect2i(Vector2i.ZERO, FloorLayout.SIZE_LARGE)
	assert_array(RoomShape.cut_tiles(RoomShape.RECT, rect, 0)).is_empty()
	for shape: StringName in [
		RoomShape.L_SHAPE, RoomShape.T_SHAPE, RoomShape.CROSS, RoomShape.OCTAGON
	]:
		var cut := RoomShape.cut_tiles(shape, rect, 0)
		assert_int(cut.size()).override_failure_message("%s cut nothing" % shape).is_greater(3)
		assert_int(RoomShape.floor_count(shape, rect)).is_equal(rect.get_area() - cut.size())
	# Too small to read: stays a rectangle rather than cutting a 1-tile nick.
	var closet := Rect2i(Vector2i.ZERO, FloorLayout.SIZE_CLOSET)
	for shape: StringName in RoomShape.ALL:
		if shape != RoomShape.RECT:
			assert_bool(RoomShape.fits(shape, closet.size)).is_false()
			assert_array(RoomShape.cut_tiles(shape, closet, 0)).is_empty()


func test_an_l_shape_loses_a_different_corner_per_variant() -> void:
	var rect := Rect2i(Vector2i(4, 4), FloorLayout.SIZE_MEDIUM)
	var seen: Dictionary = {}
	for variant in range(4):
		var cut := RoomShape.cut_tiles(RoomShape.L_SHAPE, rect, variant)
		assert_bool(cut.is_empty()).is_false()
		seen[cut[0]] = true
	assert_int(seen.size()).is_equal(4)


func test_generated_floors_are_at_least_two_fifths_non_rectangular() -> void:
	var rooms := 0
	var shaped := 0
	var seen: Dictionary = {}
	for theme: String in ["tokyo-night", "gruvbox", "white"]:
		for i in range(SEEDS / 3):
			var floor_index := i % 9
			var data := _generate(theme, 300 + i * 13, floor_index)
			for room: FloorData.Room in data.rooms:
				rooms += 1
				seen[room.shape] = true
				if room.shape != RoomShape.RECT:
					shaped += 1
	var share := float(shaped) / float(maxi(rooms, 1))
	(
		assert_float(share)
		. override_failure_message("only %.2f of %d rooms are non-rectangular" % [share, rooms])
		. is_greater_equal(MIN_NON_RECT_SHARE)
	)
	for shape: StringName in RoomShape.ALL:
		assert_bool(seen.has(shape)).override_failure_message("%s never rolled" % shape).is_true()


func test_a_shaped_room_is_stamped_and_every_door_opens_onto_floor() -> void:
	var checked := 0
	for i in range(60):
		var data := _generate("catppuccin", 700 + i, i % 9)
		for room: FloorData.Room in data.rooms:
			var cut := RoomShape.cut_tiles(room.shape, room.rect, 0).size()
			var walls := 0
			for p: Vector2i in GenUtil.rect_tiles(room.rect):
				if data.get_tile(p.x, p.y) == FloorData.Tile.WALL:
					walls += 1
			# Templates add walls of their own, never fewer than the shape cut.
			assert_int(walls).is_greater_equal(cut)
			for key: int in room.doors:
				var door: Vector2i = room.doors[key]
				var behind := room.trap_facing(door)
				assert_bool(behind != Vector2i.ZERO).is_true()
				var inside := door + behind
				assert_bool(data.is_walkable(inside.x, inside.y)).is_true()
				checked += 1
	assert_int(checked).is_greater(100)


func test_room_sizes_vary_on_one_floor() -> void:
	# Closets, galleries and halls on the same floor: the spread between the smallest and the
	# largest ordinary room should be well past two to one on most floors.
	var wide := 0
	var floors := 0
	for i in range(40):
		var data := _generate("tokyo-night", 900 + i, i % 9)
		var smallest := 1 << 30
		var largest := 0
		for room: FloorData.Room in data.rooms:
			if room.type == FloorData.RoomType.BOSS:
				continue
			smallest = mini(smallest, room.rect.get_area())
			largest = maxi(largest, room.rect.get_area())
		floors += 1
		if largest >= smallest * 2:
			wide += 1
	assert_int(wide).is_greater_equal(int(floors * 0.75))


func test_turned_rooms_exist() -> void:
	var tall := 0
	for i in range(30):
		var data := _generate("nord", 1100 + i, i % 9)
		for room: FloorData.Room in data.rooms:
			if room.rect.size.y > room.rect.size.x:
				tall += 1
	assert_int(tall).is_greater(10)
