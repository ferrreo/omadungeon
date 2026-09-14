## The spacing grid (owner report 7: "lots of ui is sloppy e.g spacing").
##
## Before this, `src/ui` laid out on 1, 2, 3, 4, 6, 8, 12 and 16 px at the same time, with no
## rule saying which was which: two grids on one page had different row pitches, a heading sat
## 4 px from the block above it on one screen and 6 px on the next, and a status chip 1 px from
## its neighbour sat 2 px from the plate edge. None of it is a bug any assertion about
## behaviour could see, and all of it is what "sloppy" means when someone looks at the game.
##
## The rule is `UiTheme.GRID`. This suite reads the shipped screens - the scene files and the
## code that builds rows at runtime - and fails on any separation that is not on it. It is a
## source scan on purpose: a rendered check cannot tell 6 px from 8 px, and a per-screen
## assertion would have to be written again for every screen somebody adds.
class_name SpacingGridTest
extends GdUnitTestSuite

const UI_DIR := "res://src/ui"
## Separation constants a scene file can carry.
const SCENE_KEYS: PackedStringArray = [
	"theme_override_constants/separation",
	"theme_override_constants/h_separation",
	"theme_override_constants/v_separation",
	"theme_override_constants/margin_top",
	"theme_override_constants/margin_bottom",
	"theme_override_constants/margin_left",
	"theme_override_constants/margin_right",
]


func test_the_grid_is_a_four_pixel_rhythm_with_one_half_step() -> void:
	assert_array(UiTheme.GRID).contains_exactly([0, 2, 4, 8, 12, 16])
	assert_bool(UiTheme.on_grid(UiTheme.GAP)).is_true()
	assert_bool(UiTheme.on_grid(6)).is_false()
	assert_bool(UiTheme.on_grid(1)).is_false()
	assert_bool(UiTheme.on_grid(3)).is_false()


## Every separation baked into a UI scene file.
func test_no_scene_lays_out_off_the_grid() -> void:
	var offenders: PackedStringArray = []
	for path: String in _files(".tscn"):
		var lines := _text(path).split("\n")
		for i in lines.size():
			var line := (lines[i] as String).strip_edges()
			for key: String in SCENE_KEYS:
				if not line.begins_with(key + " ="):
					continue
				var value := int(line.split("=")[1].strip_edges())
				if not UiTheme.on_grid(value):
					offenders.append("%s:%d %s" % [path.get_file(), i + 1, line])
	(
		assert_array(offenders)
		. override_failure_message("separations off UiTheme.GRID: %s" % offenders)
		. is_empty()
	)


## Every separation a screen sets at runtime. A row built in code is as visible as one built
## in the editor, and all but one of the off-grid values the owner was looking at were here.
func test_no_screen_builds_a_row_off_the_grid() -> void:
	var finder := RegEx.create_from_string(
		'add_theme_constant_override\\(&?"[a-z_]*separation", *([0-9]+)\\)'
	)
	var offenders: PackedStringArray = []
	for path: String in _files(".gd"):
		for found: RegExMatch in finder.search_all(_text(path)):
			if not UiTheme.on_grid(int(found.get_string(1))):
				offenders.append("%s: %s" % [path.get_file(), found.get_string(0)])
	(
		assert_array(offenders)
		. override_failure_message("runtime separations off UiTheme.GRID: %s" % offenders)
		. is_empty()
	)


func _files(suffix: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(UI_DIR)
	assert_object(dir).is_not_null()
	for name: String in dir.get_files():
		var file := name.trim_suffix(".remap")
		if file.ends_with(suffix):
			out.append(UI_DIR.path_join(file))
	assert_array(out).is_not_empty()
	return out


func _text(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).override_failure_message("could not read %s" % path).is_not_empty()
	return text
