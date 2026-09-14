## Rendered check for the profile statistics table. Runs as its own main scene inside the
## nested headless sway harness (never on the real session):
##
##   OMADUNGEON_OMARCHY_STATE_DIR=tests/fixtures/omarchy/tokyo-night/state \
##   tools/headless-sway.sh godot --path . --rendering-driver opengl3 \
##       res://tests/unit/ui/stats_capture.tscn
##
## It draws the real `StatsScreen` at the game's native 480x270 against the three profiles a
## player actually has - one that has never been played, one with a single run behind it, and a
## long history - and saves one PNG each, so "is this readable?" is answered by looking. A
## fresh profile is the state every machine starts in and the one that was never captured: the
## gallery's `stats` screen is built from a hand-written flat fixture, which is the shape the
## renderer always handled and not the shape `Profile.to_dict()` hands it.
class_name StatsCapture
extends Node

const SCENE := "res://src/ui/stats_screen.tscn"
const VIEW_SIZE := Vector2i(480, 270)
## Real seconds of settling before each screenshot, so the table has laid out.
const SETTLE := 0.15
## Enemies and milestones in the long-history profile: more than one screen holds, which is
## what the table's own scrolling is for.
const HISTORY_ENTRIES := 14


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var view := SubViewport.new()
	view.size = VIEW_SIZE
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	for entry: Dictionary in _profiles():
		await _capture(view, str(entry["name"]), entry["profile"] as Profile)
	get_tree().quit(0)


## Draws one profile and writes its PNG.
func _capture(view: SubViewport, name_part: String, profile: Profile) -> void:
	var screen := (load(SCENE) as PackedScene).instantiate() as StatsScreen
	view.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.show_stats(profile.to_dict())
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out_path(name_part))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("stats capture -> %s (%s)" % [path, error_string(image.save_png(path))])
	view.remove_child(screen)
	screen.queue_free()


## The three states, in the order they are captured.
static func _profiles() -> Array[Dictionary]:
	return [
		{"name": "fresh", "profile": Profile.new()},
		{"name": "one_run", "profile": _one_run()},
		{"name": "history", "profile": _long_history()},
	]


## A profile with a single unfinished run behind it.
static func _one_run() -> Profile:
	var profile := Profile.new()
	profile.runs = 1
	profile.best_floor_per_class = {"fighter": 3}
	profile.deaths_by_enemy = {"bit_rot": 1}
	profile.add_counter(&"rooms_cleared", 12)
	return profile


## A profile with more history than one screen holds.
static func _long_history() -> Profile:
	var profile := Profile.new()
	profile.runs = 140
	profile.wins = 31
	profile.best_floor_per_class = {"fighter": 9, "ranger": 4, "wizard": 11, "oligarch": 2}
	profile.per_theme_wins = {"Tokyo Night": 12, "Gruvbox": 9, "Nord": 6, "Catppuccin": 4}
	for i in range(HISTORY_ENTRIES):
		profile.deaths_by_enemy["enemy_%02d" % i] = i + 1
		profile.counters["milestone_%02d" % i] = (i + 1) * 7
	for id: StringName in Profile.GATED_UNLOCKS.slice(0, 3):
		profile.unlock(id)
	return profile


## `tests/out/ui_stats_<state>.png`, with `_<theme>` appended for any fixture but the default,
## so a second theme never overwrites the first (docs/TESTING.md tier 2).
static func _out_path(name_part: String) -> String:
	var state := OS.get_environment("OMADUNGEON_OMARCHY_STATE_DIR")
	var theme := state.trim_suffix("/").get_base_dir().get_file() if not state.is_empty() else ""
	if theme.is_empty() or theme == "tokyo-night":
		return "res://tests/out/ui_stats_%s.png" % name_part
	return "res://tests/out/ui_stats_%s_%s.png" % [name_part, theme]
