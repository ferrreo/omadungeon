class_name MinimapModelTest
extends GdUnitTestSuite


func test_rooms_and_edges() -> void:
	var data := RoomsTestFixtures.three_rooms()
	var rooms := MinimapModel.rooms(data, [1], 2, [0])
	assert_int(rooms.size()).is_equal(3)
	assert_that(rooms[0]["rect"]).is_equal(Rect2i(2, 2, 5, 4))
	assert_int(int(rooms[0]["type"])).is_equal(FloorData.RoomType.START)
	assert_bool(bool(rooms[0]["visited"])).is_true()
	assert_bool(bool(rooms[0]["cleared"])).is_false()
	assert_bool(bool(rooms[0]["current"])).is_false()
	assert_bool(bool(rooms[1]["cleared"])).is_true()
	assert_bool(bool(rooms[1]["visited"])).is_true()
	assert_bool(bool(rooms[2]["current"])).is_true()
	assert_bool(bool(rooms[2]["visited"])).is_true()
	var edges := MinimapModel.edges(data)
	assert_int(edges.size()).is_equal(2)
	var c0: Vector2i = data.rooms[0].center()
	var c1: Vector2i = data.rooms[1].center()
	assert_that(edges[0]).is_equal(Vector4i(c0.x, c0.y, c1.x, c1.y))
	assert_that(MinimapModel.bounds(data)).is_equal(Rect2i(2, 2, 15, 11))


func test_edges_fall_back_to_graph() -> void:
	var data := RoomsTestFixtures.three_rooms()
	data.corridors.clear()
	assert_int(MinimapModel.edges(data).size()).is_equal(2)


## `edges()` and `links()` describe the same connections in the same order, because the minimap
## reads the fog channel off one and draws the other.
func test_links_are_parallel_to_edges() -> void:
	var data := RoomsTestFixtures.three_rooms()
	var edges := MinimapModel.edges(data)
	var links := MinimapModel.links(data)
	assert_int(links.size()).is_equal(edges.size())
	assert_array(MinimapModel.pairs(data)).contains_exactly([Vector2i(0, 1), Vector2i(1, 2)])
	for link: PackedVector2Array in links:
		assert_int(link.size()).is_greater_equal(2)


## A link is drawn from door to door, not centre to centre: it must stop at the two room boxes
## instead of running across them.
func test_a_link_starts_and_ends_outside_the_rooms_it_joins() -> void:
	var data := _generated(0)
	var rooms := data.rooms
	var links := MinimapModel.links(data)
	var pairs := MinimapModel.pairs(data)
	for i in range(links.size()):
		var link := links[i]
		for room: FloorData.Room in rooms:
			if room.id != pairs[i].x and room.id != pairs[i].y:
				continue
			var box := Rect2(room.rect)
			for point: Vector2 in link:
				(
					assert_bool(box.has_point(point))
					. override_failure_message(
						"link %d runs through room %d at %s" % [i, room.id, str(point)]
					)
					. is_false()
				)


## ...and it has to *reach* both of them: a route that stops short is a corridor the player
## reads as a dead end. Both ends sit on the door tile, one tile out from the room box.
func test_a_link_touches_both_rooms_it_joins() -> void:
	var data := _generated(7)
	var links := MinimapModel.links(data)
	var pairs := MinimapModel.pairs(data)
	assert_int(links.size()).is_greater(3)
	for i in range(links.size()):
		var link := links[i]
		var ends := [
			[link[0], data.room_by_id(pairs[i].x)],
			[link[link.size() - 1], data.room_by_id(pairs[i].y)]
		]
		for pair: Array in ends:
			var gap := _distance_to_rect(
				pair[0] as Vector2, Rect2((pair[1] as FloorData.Room).rect)
			)
			(
				assert_float(gap)
				. override_failure_message(
					(
						"link %d ends %.2f tiles from room %d"
						% [i, gap, (pair[1] as FloorData.Room).id]
					)
				)
				. is_less_equal(1.0)
			)


## The corridor lines used to be straight room-centre to room-centre chords, so 1.8% of them
## crossed a room they did not connect and the panel read as a scribble over the boxes. The
## carver only ever routes through VOID, so the recorded path cannot: this is the assertion
## that stops a future "simplification" back to a chord.
func test_no_link_crosses_a_room_it_does_not_connect() -> void:
	var offenders := PackedStringArray()
	var checked := 0
	for theme: String in GenParamsTest.THEMES:
		for seed_value in range(4):
			for floor_index in range(9):
				var data := _generated(seed_value * 131 + floor_index * 7, theme, floor_index)
				var links := MinimapModel.links(data)
				var pairs := MinimapModel.pairs(data)
				checked += links.size()
				for i in range(links.size()):
					for room: FloorData.Room in data.rooms:
						if room.id == pairs[i].x or room.id == pairs[i].y:
							continue
						if not _crosses(links[i], Rect2(room.rect)):
							continue
						offenders.append(
							(
								"%s seed %d floor %d: link %d crosses room %d"
								% [theme, seed_value, floor_index, i, room.id]
							)
						)
	assert_int(checked).is_greater(500)
	(
		assert_array(offenders)
		. override_failure_message(
			(
				"%d of %d links cross a room they do not connect:\n%s"
				% [offenders.size(), checked, "\n".join(offenders)]
			)
		)
		. is_empty()
	)


func _generated(seed_value: int, theme: String = "tokyo-night", floor_index: int = 2) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	return FloorGenerator.generate(params, RunRng.new(seed_value).floor_stream(&"gen", floor_index))


## How far `point` lies outside `rect` (0 when inside).
static func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0)
	var dy := maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)
	return Vector2(dx, dy).length()


## Whether any segment of `points` enters `rect`.
static func _crosses(points: PackedVector2Array, rect: Rect2) -> bool:
	for i in range(points.size() - 1):
		if _segment_hits(points[i], points[i + 1], rect):
			return true
	return false


## Slab test: does the segment a-b intersect `rect`?
static func _segment_hits(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in range(2):
		var delta := d[axis]
		var lo := rect.position[axis]
		var hi := rect.end[axis]
		if absf(delta) < 0.00001:
			if a[axis] <= lo or a[axis] >= hi:
				return false
			continue
		var enter := (lo - a[axis]) / delta
		var exit_at := (hi - a[axis]) / delta
		t0 = maxf(t0, minf(enter, exit_at))
		t1 = minf(t1, maxf(enter, exit_at))
		if t0 >= t1:
			return false
	return true
