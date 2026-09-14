## The minimap says what the floor still holds (owner report 10, round 5: "the 'you have
## missed crap' over the exit is annoying, maybe make the minimap better and more obvious that
## rooms have been missed"). A room the player has stood next to and not entered is drawn as
## its own channel, and a strip under the map counts rooms and drops left behind.
class_name MinimapMissedTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]


func after_test() -> void:
	UiTheme.rebuild(Desktop.palette)


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _map() -> Minimap:
	var map: Minimap = auto_free(Minimap.new())
	add_child(map)
	map.size = Vector2(96, 64)
	return map


func _room(id: int, kind: int, visited: bool) -> Dictionary:
	return {
		"id": id,
		"rect": Rect2i(id * 8, 0, 6, 5),
		"type": kind,
		"cleared": visited,
		"visited": visited,
		"current": false,
	}


func _edge(a: int, b: int) -> Vector4i:
	return Vector4i(a * 8 + 3, 2, b * 8 + 3, 2)


## A skipped room - reached by a corridor from somewhere the player has been - is known; a
## room two corridors away is still fog.
func test_a_room_next_to_a_visited_one_is_known_and_a_far_one_is_fog() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true),
		_room(1, Minimap.RoomKind.TREASURE, false),
		_room(2, Minimap.RoomKind.COMBAT, false),
	]
	map.set_rooms(rooms, [_edge(0, 1), _edge(1, 2)] as Array[Vector4i])
	assert_bool(map.is_known(rooms[1])).is_true()
	assert_bool(map.is_known(rooms[2])).is_false()
	assert_bool(map.is_known(rooms[0])).is_false()
	assert_int(map.unvisited_count()).is_equal(2)
	assert_int(map.unvisited_reward_count()).is_equal(1)


## The known outline is brighter than deep fog on every fixture, and still carries no kind.
func test_the_known_outline_is_brighter_than_fog_on_every_fixture() -> void:
	var map := _map()
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		var plate := map.plate()
		var fog := ThemePalette.contrast_ratio(map.mark(plate, 4.5, Minimap.FOG_MIX), plate)
		var known := ThemePalette.contrast_ratio(map.mark(plate, 4.5, Minimap.KNOWN_MIX), plate)
		(
			assert_float(known)
			. override_failure_message("%s: known %.2f is not above fog %.2f" % [theme, known, fog])
			. is_greater(fog)
		)
		assert_float(known).is_greater_equal(2.5)


## The strip: rooms left and drops left, in words, and nothing once the floor is clean.
func test_the_caption_counts_rooms_and_drops_and_falls_silent_when_clean() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true),
		_room(1, Minimap.RoomKind.SHOP, false),
		_room(2, Minimap.RoomKind.COMBAT, false),
	]
	map.set_rooms(rooms, [_edge(0, 1), _edge(1, 2)] as Array[Vector4i])
	assert_str(map.caption_text()).is_equal("2 rooms left")
	EventBus.floor_leftovers.emit(1)
	assert_int(map.items_left()).is_equal(1)
	assert_str(map.caption_text()).is_equal("2 rooms left, 1 item on the floor")
	var seen: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true),
		_room(1, Minimap.RoomKind.SHOP, true),
		_room(2, Minimap.RoomKind.COMBAT, true),
	]
	map.set_rooms(seen, [] as Array[Vector4i])
	assert_str(map.caption_text()).is_equal("1 item on the floor")
	# A new floor starts with nothing lying on it.
	EventBus.floor_started.emit(1)
	assert_int(map.items_left()).is_equal(0)
	assert_str(map.caption_text()).is_empty()


## Drawing with the strip and a known room must not throw on any fixture, and the HUD's map
## is big enough to read: not the 64x44 stamp it was.
func test_draws_with_a_caption_on_every_fixture_and_the_hud_map_grew() -> void:
	var map := _map()
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true), _room(1, Minimap.RoomKind.ALTAR, false)
	]
	map.set_rooms(rooms, [_edge(0, 1)] as Array[Vector4i])
	map.set_items_left(2)
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		map.queue_redraw()
		await get_tree().process_frame
	assert_float(map.custom_minimum_size.x).is_greater_equal(96.0)
	var hud: Hud = auto_free((load("res://src/ui/hud.tscn") as PackedScene).instantiate())
	add_child(hud)
	var widget := hud.get_node("%Minimap") as Minimap
	await get_tree().process_frame
	assert_float(widget.size.x).is_greater_equal(96.0)
	assert_float(widget.size.y).is_greater_equal(64.0)
