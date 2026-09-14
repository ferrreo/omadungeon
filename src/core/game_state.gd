## Cross-scene game state (current run, settings). Persisted via SaveManager.
extends Node

const SETTINGS_PATH := "user://settings.json"
const SaveManagerScript := preload("res://src/core/save_manager.gd")

## Where settings are read and written. Redirected into SaveManager's throwaway sandbox for
## gdUnit4 runs and `--test-scenario` captures, so no test can change the developer's real
## settings.json (docs §12: testing never disturbs the real session).
var settings_path: String = SETTINGS_PATH

var settings: Dictionary = {
	"screen_shake": true,
	"damage_numbers": true,
	"music_lights": true,
	"music_lights_amount": 1.0,
	"explicit_music": true,
	"wallpaper_influence": true,
	"rumble": true,
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
}

var run_seed: int = 0
var floor_index: int = 0
var class_id: StringName = &"fighter"
var cli_args: Dictionary = {}


func _ready() -> void:
	cli_args = _parse_cli_args()
	if SaveManagerScript.is_test_run():
		settings_path = SaveManagerScript.test_sandbox_dir() + "/settings.json"
	load_settings()


func load_settings() -> void:
	if not FileAccess.file_exists(settings_path):
		return
	var file := FileAccess.open(settings_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for key: String in (parsed as Dictionary).keys():
			settings[key] = parsed[key]


func save_settings() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(settings_path).get_base_dir()
	)
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write settings to %s" % settings_path)
		return
	file.store_string(JSON.stringify(settings, "\t"))


## Parses `--key value` and `--flag` user args into a dictionary.
func _parse_cli_args() -> Dictionary:
	var result: Dictionary = {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg.begins_with("--"):
			var key := arg.trim_prefix("--")
			if "=" in key:
				var parts := key.split("=", true, 1)
				result[parts[0]] = parts[1]
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				result[key] = args[i + 1]
				i += 1
			else:
				result[key] = true
		i += 1
	return result
