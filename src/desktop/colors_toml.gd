## Parser and resolver for Omarchy `colors.toml`.
## Mirrors the alias/fallback cascade of upstream `bin/omarchy-theme-color` so the
## game resolves the exact same palette as every other Omarchy consumer.
class_name ColorsToml
extends RefCounted

const KEYS_SEMANTIC: PackedStringArray = [
	"accent",
	"selection",
	"muted",
	"background",
	"dark_background",
	"darker_background",
	"lighter_background",
	"foreground",
	"dark_foreground",
	"light_foreground",
	"bright_foreground",
	"red",
	"yellow",
	"orange",
	"green",
	"cyan",
	"blue",
	"magenta",
	"brown",
	"bright_red",
	"bright_yellow",
	"bright_green",
	"bright_cyan",
	"bright_blue",
	"bright_magenta",
]

const LEGACY_ALIAS: Dictionary = {
	"red": "color1",
	"green": "color2",
	"yellow": "color3",
	"blue": "color4",
	"magenta": "color5",
	"cyan": "color6",
	"bright_red": "color9",
	"bright_green": "color10",
	"bright_yellow": "color11",
	"bright_blue": "color12",
	"bright_magenta": "color13",
	"bright_cyan": "color14",
}

## Raw string key/values as written in the file.
var raw: Dictionary = {}
## Fully resolved colours by semantic key (Color values).
var colors: Dictionary = {}
## "dark" or "light".
var mode: String = "dark"


## Parses a colors.toml file. `light_mode_beside` should be true when a `light.mode`
## file sits next to the toml (legacy mode hint).
static func load_file(path: String, light_mode_beside: bool = false) -> ColorsToml:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return parse(file.get_as_text(), light_mode_beside)


static func parse(text: String, light_mode_beside: bool = false) -> ColorsToml:
	var result := ColorsToml.new()
	result.raw = _parse_raw(text)
	result._resolve(light_mode_beside)
	return result


## Minimal TOML subset: `key = "value"` or `key = value` at top level, `#` comments.
static func _parse_raw(text: String) -> Dictionary:
	var out: Dictionary = {}
	for line: String in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#") or stripped.begins_with("["):
			continue
		var eq := stripped.find("=")
		if eq <= 0:
			continue
		var key := stripped.substr(0, eq).strip_edges()
		var value := stripped.substr(eq + 1).strip_edges()
		if value.begins_with('"') or value.begins_with("'"):
			var quote := value[0]
			var close := value.find(quote, 1)
			value = value.substr(1, close - 1) if close > 0 else value.substr(1)
		else:
			var comment := value.find("#")
			if comment >= 0:
				value = value.substr(0, comment).strip_edges()
		out[key] = value
	return out


func _val(key: String) -> String:
	return str(raw.get(key, ""))


func _present(key: String) -> bool:
	return not _val(key).is_empty()


func _alias(key: String, fallback: String) -> void:
	if not _present(key) and _present(fallback):
		raw[key] = raw[fallback]


func _default(key: String, value: String) -> void:
	if not _present(key) and not value.is_empty():
		raw[key] = value


func _resolve(light_mode_beside: bool) -> void:
	for key: String in LEGACY_ALIAS.keys():
		_alias(key, LEGACY_ALIAS[key])
	_alias("magenta", "purple")
	_alias("bright_magenta", "bright_purple")

	_default("light_foreground", _val("color7") if _present("color7") else _val("foreground"))
	_default("bright_foreground", _val("color15") if _present("color15") else _val("foreground"))
	_default("lighter_background", _val("color0") if _present("color0") else _val("background"))
	_default("dark_foreground", _val("color8") if _present("color8") else _val("foreground"))
	_default("muted", _val("color8") if _present("color8") else _val("dark_foreground"))
	if not _present("selection"):
		if _present("selection_background"):
			raw["selection"] = raw["selection_background"]
		elif _present("color8"):
			raw["selection"] = raw["color8"]
		elif _present("color0"):
			raw["selection"] = raw["color0"]
		else:
			raw["selection"] = _val("background")
	_default("orange", _val("yellow"))
	_default("accent", _val("blue"))
	_default("dark_background", _val("background"))
	_default("darker_background", _val("dark_background"))
	for key: String in ["red", "yellow", "green", "cyan", "blue", "magenta"]:
		_default("bright_" + key, _val(key))

	for key: String in KEYS_SEMANTIC:
		var hex := _val(key)
		if hex.is_empty():
			continue
		if Color.html_is_valid(hex):
			colors[key] = Color.html(hex)
	if not colors.has("brown") and colors.has("orange"):
		colors["brown"] = (colors["orange"] as Color).lerp(Color.BLACK, 0.5)

	_resolve_mode(light_mode_beside)


func _resolve_mode(light_mode_beside: bool) -> void:
	var explicit := _val("mode")
	if explicit.is_empty():
		explicit = _val("theme_type")
	if explicit == "light" or explicit == "dark":
		mode = explicit
		return
	if light_mode_beside:
		mode = "light"
		return
	if colors.has("background"):
		var bg: Color = colors["background"]
		var lum := bg.r8 + bg.g8 + bg.b8
		mode = "light" if lum > 382 else "dark"
		return
	mode = "dark"


func get_color(key: String, fallback: Color = Color.MAGENTA) -> Color:
	return colors.get(key, fallback)


func is_light() -> bool:
	return mode == "light"


## True when every key the game relies on is present.
func is_complete() -> bool:
	for key: String in [
		"background", "foreground", "red", "green", "yellow", "blue", "magenta", "cyan"
	]:
		if not colors.has(key):
			return false
	return true
