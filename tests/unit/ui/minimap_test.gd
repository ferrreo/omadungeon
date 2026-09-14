## The minimap has to carry three channels at once - fog, progress and room kind - plus a
## "you are here" marker, on six very different palettes. Sampling drawn pixels headless is
## brittle, so `Minimap` exposes the colours it is about to draw and this suite asserts the
## channels stay apart on every fixture instead.
class_name MinimapTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _map() -> Minimap:
	var map: Minimap = auto_free(Minimap.new())
	add_child(map)
	map.size = Vector2(80, 56)
	return map


func _room(id: int, kind: int, visited: bool, cleared: bool, current: bool = false) -> Dictionary:
	return {
		"id": id,
		"rect": Rect2i(id * 8, 0, 6, 5),
		"type": kind,
		"cleared": cleared,
		"visited": visited,
		"current": current,
	}


func after_test() -> void:
	UiTheme.rebuild(Desktop.palette)


func test_fog_visited_and_cleared_are_three_distinct_channels() -> void:
	var map := _map()
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		var plate := map.plate()
		var fog := map.room_fill(_room(0, Minimap.RoomKind.COMBAT, false, false), plate)
		var seen := map.room_fill(_room(1, Minimap.RoomKind.COMBAT, true, false), plate)
		var done := map.room_fill(_room(2, Minimap.RoomKind.COMBAT, true, true), plate)
		for pair: Array in [[fog, seen], [seen, done], [fog, done]]:
			var gap := absf(pair[0].get_luminance() - pair[1].get_luminance())
			(
				assert_float(gap)
				. override_failure_message("%s: minimap channels collapsed (%.3f)" % [theme, gap])
				. is_greater(0.05)
			)
		var lit := ThemePalette.contrast_ratio(done, plate)
		(
			assert_float(lit)
			. override_failure_message("%s: cleared room %.2f on plate" % [theme, lit])
			. is_greater_equal(4.5)
		)


## Fog of war: an unentered treasure room must not give itself away with a loot tint.
func test_unvisited_rooms_hide_their_kind() -> void:
	var map := _map()
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		var plate := map.plate()
		var plain := map.room_fill(_room(0, Minimap.RoomKind.COMBAT, false, false), plate)
		for kind: int in [
			Minimap.RoomKind.TREASURE, Minimap.RoomKind.STAIRS, Minimap.RoomKind.BOSS
		]:
			var hidden := map.room_fill(_room(1, kind, false, false), plate)
			(
				assert_bool(hidden.is_equal_approx(plain))
				. override_failure_message("%s: kind %d leaks through fog" % [theme, kind])
				. is_true()
			)


func test_visited_special_rooms_take_their_kind_colour() -> void:
	var map := _map()
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		var plate := map.plate()
		var plain := map.room_fill(_room(0, Minimap.RoomKind.COMBAT, true, true), plate)
		for kind: int in [
			Minimap.RoomKind.TREASURE, Minimap.RoomKind.STAIRS, Minimap.RoomKind.BOSS
		]:
			var tinted := map.room_fill(_room(1, kind, true, true), plate)
			(
				assert_bool(tinted.is_equal_approx(plain))
				. override_failure_message("%s: kind %d not tinted" % [theme, kind])
				. is_false()
			)
			var ratio := ThemePalette.contrast_ratio(tinted, plate)
			(
				assert_float(ratio)
				. override_failure_message("%s: kind %d only %.2f on plate" % [theme, kind, ratio])
				. is_greater_equal(2.5)
			)


## The plate is opaque, for the reason docs §3.2 gives the HUD text blocks: room fills are
## judged against `void`, so the dungeon underneath must not change what they contrast with.
## At 0.94 it did - a tester sampling the panel interior found three near-identical colours
## (the wall courses behind it) and a torch glow inside the map instead of one flat surface.
func test_the_plate_is_opaque_so_the_dungeon_cannot_composite_through_it() -> void:
	var map := _map()
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		(
			assert_float(map.plate().a)
			. override_failure_message("%s: minimap plate is translucent" % theme)
			. is_equal_approx(1.0, 0.0001)
		)


func test_current_room_tracks_the_flag_and_animates() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true, true),
		_room(1, Minimap.RoomKind.COMBAT, true, false, true),
	]
	map.set_rooms(rooms, [] as Array[Vector4i])
	assert_int(map.room_count()).is_equal(2)
	assert_int(map.current_room_id()).is_equal(1)
	var none: Array[Dictionary] = [_room(0, Minimap.RoomKind.START, true, true)]
	map.set_rooms(none, [] as Array[Vector4i])
	assert_int(map.current_room_id()).is_equal(-1)


## Drawing must not throw on any fixture, with or without a current room.
func test_draws_on_every_fixture() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true, true),
		_room(1, Minimap.RoomKind.TREASURE, false, false),
		_room(2, Minimap.RoomKind.BOSS, true, false, true),
	]
	var edges: Array[Vector4i] = [Vector4i(3, 2, 11, 2), Vector4i(11, 2, 19, 2)]
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		map.set_rooms(rooms, edges)
		map.queue_redraw()
		await await_millis(20)
	assert_int(map.room_count()).is_equal(3)


## The channels the suite never measured. Fog room outlines and corridor edges are drawn with
## a *softened* mark, and softening used to be a plain sRGB lerp toward the plate: on
## tokyo-night a 28% mix still reads at ~3.3:1, on catppuccin-latte the identical feature
## landed at 1.55:1 and the explored map dissolved into the plate. The fade is now expressed
## as a contrast floor, so it means the same thing on a dark plate and a light one.
func test_softened_marks_keep_a_contrast_floor_on_every_fixture() -> void:
	var map := _map()
	# (target, strength) exactly as `_draw_room` / `_draw_edges` / `_draw` call them.
	var uses: Array[Vector2] = [
		Vector2(3.0, 0.85),  # visited-room outline
		Vector2(3.0, 0.7),  # corridor between two visited rooms
		Vector2(3.0, 0.55),  # the plate's own border
		Vector2(3.0, 0.28),  # corridor still under fog
		Vector2(4.5, Minimap.FOG_MIX),  # an unentered room's outline
	]
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		var plate := map.plate()
		for use: Vector2 in uses:
			var floor_ratio := Minimap.mark_floor(use.x, use.y)
			var got := ThemePalette.contrast_ratio(map.mark(plate, use.x, use.y), plate)
			(
				assert_float(got)
				. override_failure_message(
					(
						"%s: mark(%.2f, %.2f) is %.2f on the plate, floor is %.2f"
						% [theme, use.x, use.y, got, floor_ratio]
					)
				)
				. is_greater_equal(floor_ratio - 0.01)
			)


## The floor is not a way of saying "draw everything at full strength": a softened mark still
## has to be visibly softer than the unsoftened one, or fog and explored stop being channels.
func test_the_contrast_floor_does_not_flatten_the_fade() -> void:
	var map := _map()
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		var plate := map.plate()
		var full := ThemePalette.contrast_ratio(map.mark(plate, 3.0, 1.0), plate)
		var soft := ThemePalette.contrast_ratio(map.mark(plate, 3.0, 0.28), plate)
		(
			assert_float(soft)
			. override_failure_message(
				"%s: fogged edge %.2f is not softer than %.2f" % [theme, soft, full]
			)
			. is_less(full)
		)


## Light themes are the ones this went wrong on, so they get the number named: the tester
## measured 1.55:1 on catppuccin-latte where tokyo-night had 3.35:1.
func test_the_light_fixtures_no_longer_lose_the_explored_map() -> void:
	var map := _map()
	for theme: String in ["catppuccin-latte", "white"]:
		UiTheme.rebuild(_palette(theme))
		var plate := map.plate()
		var outline := ThemePalette.contrast_ratio(map.mark(plate, 3.0, 0.85), plate)
		(
			assert_float(outline)
			. override_failure_message("%s: room outline only %.2f on the plate" % [theme, outline])
			. is_greater_equal(2.0)
		)
		var fog := ThemePalette.contrast_ratio(
			map.room_fill(_room(0, Minimap.RoomKind.COMBAT, false, false), plate), plate
		)
		(
			assert_float(fog)
			. override_failure_message("%s: fogged room only %.2f on the plate" % [theme, fog])
			. is_greater_equal(1.8)
		)


## Corridor links used to be straight room-centre to room-centre chords, which cut diagonally
## across the boxes they joined. The feed now carries the route each corridor really takes;
## `route_for` is what gets drawn, and it has to start and end on the room borders.
func test_a_link_is_drawn_along_the_route_the_feed_supplies() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true, true),
		_room(1, Minimap.RoomKind.COMBAT, true, true),
	]
	var edges: Array[Vector4i] = [Vector4i(3, 2, 11, 2)]
	var links: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(6.5, 2.5), Vector2(6.5, 6.5), Vector2(8.0, 6.5)])
	]
	map.set_rooms(rooms, edges, links)
	assert_array(Array(map.route_for(0))).is_equal(Array(links[0]))
	assert_int(map.route_for(1).size()).is_equal(0)
	assert_int(map.route_for(-1).size()).is_equal(0)


## A feed with no route (the UI gallery's fixture, a hand-built test floor) is routed through
## the gap between the two rooms rather than straight across them.
func test_a_feed_without_routes_falls_back_to_an_elbow_not_a_chord() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true, true),
		_room(1, Minimap.RoomKind.COMBAT, true, true),
	]
	map.set_rooms(rooms, [Vector4i(3, 2, 11, 2)] as Array[Vector4i])
	var route := map.route_for(0)
	assert_int(route.size()).is_greater_equal(2)
	# `_room` lays its rooms out at x = id * 8, 6 wide: the gap is the two columns between them.
	# The route may touch a border - that is where a corridor meets a room - but never enter.
	for point: Vector2 in route:
		for room: Dictionary in rooms:
			var box := Rect2(room["rect"] as Rect2i).grow(-0.01)
			(
				assert_bool(box.has_point(point))
				. override_failure_message("the fallback route enters a room box at %s" % point)
				. is_false()
			)


## Rooms that do not face each other on either axis turn once instead of cutting the corner.
func test_the_elbow_leaves_and_enters_through_a_side() -> void:
	var a := Rect2i(0, 0, 6, 5)
	var b := Rect2i(20, 20, 6, 5)
	var route := Minimap.elbow(a, b)
	assert_int(route.size()).is_equal(3)
	for point: Vector2 in route:
		assert_bool(Rect2(a).grow(-0.01).has_point(point)).is_false()
		assert_bool(Rect2(b).grow(-0.01).has_point(point)).is_false()
	# Facing rooms need no corner at all: the straight segment across the gap.
	var facing := Minimap.elbow(Rect2i(0, 0, 6, 5), Rect2i(0, 12, 6, 5))
	assert_int(facing.size()).is_equal(2)
	assert_float(facing[0].y).is_equal(5.0)
	assert_float(facing[1].y).is_equal(12.0)
	assert_float(facing[0].x).is_equal(facing[1].x)
