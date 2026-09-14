## Reads otter-wallpaper's runtime state file and otter-theme's colours.
## Contract: `$XDG_RUNTIME_DIR/otter-shell/wallpaper-state`, legacy `/tmp/<uid>/otter-wallpaper-state`.
## Lines are `OUTPUT=/absolute/path`; primary output is first; `#` lines are comments.
class_name OtterWallpaper
extends RefCounted

const OTTER_COLOR_KEYS: PackedStringArray = [
	"background",
	"surface",
	"surface_alt",
	"foreground",
	"muted",
	"accent",
	"on_accent",
	"selected",
	"border",
	"success",
	"warning",
	"danger",
]


static func state_file_candidates() -> PackedStringArray:
	var out: PackedStringArray = []
	var runtime := OS.get_environment("XDG_RUNTIME_DIR")
	if not runtime.is_empty():
		out.append(runtime.path_join("otter-shell/wallpaper-state"))
	var uid := OS.get_environment("UID")
	if uid.is_empty() and not runtime.is_empty():
		uid = runtime.get_file()
	if not uid.is_empty():
		out.append("/tmp/%s/otter-wallpaper-state" % uid)
	return out


static func state_file() -> String:
	for candidate: String in state_file_candidates():
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## Parses the state file text into {output_name: absolute_path}, in file order.
static func parse_state(text: String) -> Dictionary:
	var out: Dictionary = {}
	for line: String in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue
		var eq := stripped.find("=")
		if eq <= 0:
			continue
		var output := stripped.substr(0, eq).strip_edges()
		var path := stripped.substr(eq + 1).strip_edges()
		if not is_valid_wallpaper_path(path):
			continue
		out[output] = path
	return out


static func is_valid_wallpaper_path(path: String) -> bool:
	if not path.begins_with("/"):
		return false
	for part: String in path.split("/"):
		if part == "..":
			return false
	return true


## First (primary) wallpaper path from the live state file. When the daemon is not running
## (no state file) falls back to the configured single wallpaper (path + filename) from
## otter-wallpaper.conf. Returns "" when nothing is known.
static func current_wallpaper() -> String:
	var path := state_file()
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var entries := parse_state(file.get_as_text())
			if not entries.is_empty():
				return entries.values()[0]
	return configured_wallpaper()


## Single-wallpaper fallback from ~/.config/otter-shell/otter-wallpaper.conf (or /etc).
static func configured_wallpaper() -> String:
	for conf: String in [
		config_dir().path_join("otter-wallpaper.conf"), "/etc/otter-shell/otter-wallpaper.conf"
	]:
		var raw := parse_conf_file(conf)
		if raw.is_empty():
			continue
		var base := str(raw.get("path", "")).replace("~", OS.get_environment("HOME"))
		var filename := str(raw.get("filename", ""))
		if base.is_empty():
			continue
		var candidate := base
		if not filename.is_empty():
			candidate = base.path_join(filename)
		if FileAccess.file_exists(candidate) and is_valid_wallpaper_path(candidate):
			return candidate
	return ""


static func config_dir() -> String:
	var xdg := OS.get_environment("XDG_CONFIG_HOME")
	if xdg.is_empty():
		xdg = OS.get_environment("HOME").path_join(".config")
	return xdg.path_join("otter-shell")


static func generated_colors_path() -> String:
	return config_dir().path_join("generated-colors.conf")


## Resolves otter-theme's active colours file via theme.conf `colors_path`.
static func theme_colors_path() -> String:
	var theme_conf := config_dir().path_join("theme.conf")
	var parsed := parse_conf_file(theme_conf)
	var colors_path := str(parsed.get("colors_path", ""))
	if colors_path.is_empty():
		return ""
	if colors_path.is_relative_path():
		colors_path = theme_conf.get_base_dir().path_join(colors_path)
	return colors_path


## Parses an otter-conf `key = value` file into a Dictionary of strings.
static func parse_conf_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	return ColorsToml._parse_raw(file.get_as_text())


## Loads a 12-key otter colours file into {key: Color}.
static func load_colors(path: String) -> Dictionary:
	var raw := parse_conf_file(path)
	var out: Dictionary = {}
	for key: String in OTTER_COLOR_KEYS:
		var value := str(raw.get(key, ""))
		if Color.html_is_valid(value):
			out[key] = Color.html(value)
	return out


## Change signature: "<wallpaper part>|<colours part>". Wallpaper part = state file + mtime +
## resolved wallpaper path; colours part = theme.conf mtime, its colors_path target and mtime.
## generated-colors.conf only matters when it *is* the active colors_path.
static func signature() -> String:
	var state := state_file()
	var theme_conf := config_dir().path_join("theme.conf")
	var colors := theme_colors_path()
	return (
		"%s,%d,%s|%d,%s,%d"
		% [
			state,
			FileAccess.get_modified_time(state) if not state.is_empty() else 0,
			current_wallpaper(),
			FileAccess.get_modified_time(theme_conf),
			colors,
			FileAccess.get_modified_time(colors) if not colors.is_empty() else 0,
		]
	)


## True when otter-theme provides a usable colours file.
static func has_theme_colors() -> bool:
	var path := theme_colors_path()
	return not path.is_empty() and FileAccess.file_exists(path)
