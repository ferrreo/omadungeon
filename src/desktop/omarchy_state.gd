## Reads the Omarchy state directory (`~/.local/state/omarchy`).
## Override with the OMADUNGEON_OMARCHY_STATE_DIR env var or `--theme-state` CLI arg.
class_name OmarchyState
extends RefCounted

const ENV_OVERRIDE := "OMADUNGEON_OMARCHY_STATE_DIR"
const VIDEO_EXTENSIONS: PackedStringArray = ["mp4", "m4v", "mov", "webm", "mkv", "avi"]
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "gif", "bmp", "webp"]

var state_dir: String = ""


func _init(override_dir: String = "") -> void:
	if not override_dir.is_empty():
		state_dir = override_dir
	elif OS.has_environment(ENV_OVERRIDE):
		state_dir = OS.get_environment(ENV_OVERRIDE)
	else:
		var home := OS.get_environment("HOME")
		var xdg_state := OS.get_environment("XDG_STATE_HOME")
		if xdg_state.is_empty():
			xdg_state = home.path_join(".local/state")
		state_dir = xdg_state.path_join("omarchy")


func is_available() -> bool:
	return DirAccess.dir_exists_absolute(theme_dir())


func current_dir() -> String:
	return state_dir.path_join("current")


func theme_dir() -> String:
	return current_dir().path_join("theme")


func colors_path() -> String:
	return theme_dir().path_join("colors.toml")


func has_light_mode_file() -> bool:
	return FileAccess.file_exists(theme_dir().path_join("light.mode"))


func theme_name() -> String:
	var path := current_dir().path_join("theme.name")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var text := file.get_as_text().strip_edges()
			if not text.is_empty():
				return text
	# Fall back to the directory name the theme symlink points to.
	var target := resolve_link(theme_dir())
	if not target.is_empty():
		return target.get_file().replace("-", " ").capitalize()
	return "Unknown"


## Resolved path of the active background media, or "" when none.
func background_path() -> String:
	var link := current_dir().path_join("background")
	var target := resolve_link(link)
	if target.is_empty() and FileAccess.file_exists(link):
		return link
	return target


func background_is_video() -> bool:
	return VIDEO_EXTENSIONS.has(background_path().get_extension().to_lower())


func preview_path() -> String:
	return theme_dir().path_join("preview.png")


## Cheap change signature: symlink targets plus theme.name mtime.
func signature() -> String:
	return (
		"%s|%s|%d"
		% [
			resolve_link(theme_dir()),
			resolve_link(current_dir().path_join("background")),
			FileAccess.get_modified_time(current_dir().path_join("theme.name")),
		]
	)


func load_colors() -> ColorsToml:
	if not FileAccess.file_exists(colors_path()):
		return null
	return ColorsToml.load_file(colors_path(), has_light_mode_file())


## Follows a symlink (one level; Omarchy links are direct). Returns "" if not a link.
static func resolve_link(path: String) -> String:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return ""
	if not dir.is_link(path.get_file()):
		return ""
	var target := dir.read_link(path.get_file())
	if target.is_relative_path():
		target = path.get_base_dir().path_join(target)
	return target.simplify_path()
