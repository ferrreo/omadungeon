## The HUD's blocks never overlap (owner report, round 5 follow-up: the now-playing banner ran
## under the minimap's "rooms left" strip and the first-floor hint butted against the HP
## panel). The canvas is a fixed 480x270 stretched by integer scaling, so 1440x810 and
## 1280x720 are the same layout; one measurement covers both. Banners wrap to the lane the
## plates leave them rather than growing under a plate.
class_name HudLayoutTest
extends GdUnitTestSuite

const HUD_SCENE := "res://src/ui/hud.tscn"
const LONG_TRACK := "Now playing: No Title Bar - Obstinatus (quiet, fast and bright)"
const LONG_HINT := "Lit by your wallpaper - the floor is bright and the props are dense"


func _hud() -> Hud:
	var hud: Hud = auto_free((load(HUD_SCENE) as PackedScene).instantiate())
	add_child(hud)
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	hud.bind(player)
	return hud


func _room(id: int, kind: int, visited: bool) -> Dictionary:
	return {
		"id": id,
		"rect": Rect2i(id * 8, 0, 6, 5),
		"type": kind,
		"cleared": visited,
		"visited": visited,
		"current": id == 0,
	}


## Fills every block at once: a caption under the map, both banners at their longest, the
## interact prompt and the floor tooltip.
func _crowd(hud: Hud) -> void:
	var rooms: Array[Dictionary] = [
		_room(0, Minimap.RoomKind.START, true),
		_room(1, Minimap.RoomKind.SHOP, false),
		_room(2, Minimap.RoomKind.COMBAT, false),
	]
	var edges: Array[Vector4i] = [Vector4i(3, 2, 11, 2), Vector4i(11, 2, 19, 2)]
	hud.set_minimap(rooms, edges)
	(hud.get_node("%Minimap") as Minimap).set_items_left(2)
	hud.toast(LONG_HINT, 5.0)
	hud.toast_widget().push_track(LONG_TRACK, 5.0)
	hud.show_prompt("Open chest", true)


func test_the_project_stretches_one_fixed_canvas() -> void:
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_width"))).is_equal(480)
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_height"))).is_equal(
		270
	)
	assert_str(str(ProjectSettings.get_setting("display/window/stretch/scale_mode"))).is_equal(
		"integer"
	)


func test_no_two_hud_blocks_overlap_when_every_block_is_up() -> void:
	var hud := _hud()
	await get_tree().process_frame
	_crowd(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var rects := hud.block_rects()
	var names: Array = rects.keys()
	assert_bool((rects["track"] as Rect2).has_area()).is_true()
	assert_bool((rects["toast"] as Rect2).has_area()).is_true()
	var overlaps: PackedStringArray = []
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			if a.has_area() and b.has_area() and a.intersects(b):
				overlaps.append("%s %s x %s %s" % [names[i], a, names[j], b])
	assert_array(overlaps).override_failure_message("HUD blocks overlap: %s" % overlaps).is_empty()
	var view: Rect2 = hud.get_viewport().get_visible_rect()
	for name: String in names:
		var rect: Rect2 = rects[name]
		if rect.has_area():
			(
				assert_bool(view.encloses(rect))
				. override_failure_message("%s %s leaves the frame %s" % [name, rect, view])
				. is_true()
			)


## The banners sit inside their lanes: the top one between the two top plates, the radio one
## between the ability bar and the map, wrapped when the line is longer than the lane.
func test_banners_stay_inside_the_lanes_the_plates_leave() -> void:
	var hud := _hud()
	await get_tree().process_frame
	_crowd(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var lanes := hud.banner_lanes()
	var top: Vector2 = lanes["top"]
	var bottom: Vector2 = lanes["bottom"]
	var toast := hud.toast_widget().panel_rect()
	var track := hud.toast_widget().track_rect()
	assert_float(toast.position.x).is_greater_equal(top.x)
	assert_float(toast.end.x).is_less_equal(top.y)
	assert_float(track.position.x).is_greater_equal(bottom.x)
	assert_float(track.end.x).is_less_equal(bottom.y)
	# The long track line needed the wrap: two lines, not one line cut or one line too wide.
	assert_float(track.size.y).is_greater(16.0)
	# What the widget reports is the sentence as pushed, whatever the lane broke it into.
	assert_str(hud.toast_widget().track_text()).is_equal(LONG_TRACK)
	var font := UiTheme.body_font()
	var broken := Toast.wrap_words(LONG_TRACK, font, UiTheme.SIZE_S, 200.0)
	assert_str(broken).contains("\n")
	assert_str(broken.replace("\n", " ")).is_equal(LONG_TRACK)
