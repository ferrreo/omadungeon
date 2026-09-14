## Auto-scrolling credits built from docs/CREDITS.md and the radio playlist manifest.
class_name Credits
extends Control

signal back_pressed

const CREDITS_PATH := "res://docs/CREDITS.md"
const PLAYLIST_PATH := "res://assets/music/radio/playlist.json"
const SCROLL_SPEED := 12.0
## Seconds the credits rest at the top before they start crawling.
const START_HOLD := 1.6

var _scroll_pos: float = 0.0
var _hold_left: float = START_HOLD
var _paused: bool = false

@onready var _scroll: ScrollContainer = %Scroll
@onready var _text: RichTextLabel = %Text
@onready var _back: Button = %Back


func _ready() -> void:
	UiTheme.apply(self)
	# Left stick -> ui_up/ui_down for the scroll (see UiStickNav).
	UiStickNav.serve(self)
	_back.pressed.connect(func() -> void: back_pressed.emit())
	_text.bbcode_enabled = true
	_text.text = build_bbcode()
	_back.grab_focus()


func _process(delta: float) -> void:
	if _paused:
		return
	if _hold_left > 0.0:
		_hold_left -= delta
		return
	_scroll_pos += SCROLL_SPEED * delta
	var max_scroll := maxf(0.0, _text.size.y - _scroll.size.y)
	if _scroll_pos > max_scroll + 24.0:
		_scroll_pos = 0.0
		_hold_left = START_HOLD
	_scroll.scroll_vertical = int(minf(_scroll_pos, max_scroll))


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		back_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"ui_up"):
		_paused = true
		_scroll_pos += 24.0 if event.is_action_pressed(&"ui_down") else -24.0
		_scroll_pos = maxf(0.0, _scroll_pos)
		_scroll.scroll_vertical = int(_scroll_pos)
		get_viewport().set_input_as_handled()


func text_content() -> String:
	return _text.get_parsed_text()


## Builds the credits body; safe when both source files are missing.
static func build_bbcode() -> String:
	var accent := UiTheme.color(&"accent").to_html(false)
	var dim := UiTheme.color(&"text_dim").to_html(false)
	var out := "[center][b][color=#%s]OMADUNGEON[/color][/b]\n" % accent
	out += "[color=#%s]A dungeon skinned by your desktop[/color]\n\n" % dim
	var md := _read_text(CREDITS_PATH)
	if md.is_empty():
		md = "# Made with\nGodot Engine 4\ngdUnit4\n\n# Thanks\nThe Omarchy community"
	out += _markdown_to_bbcode(md, accent)
	var tracks := _playlist_lines()
	if not tracks.is_empty():
		out += "\n[b][color=#%s]Radio playlist[/color][/b]\n" % accent
		for line: String in tracks:
			out += line + "\n"
	out += "\n[color=#%s]Thanks for playing.[/color][/center]" % dim
	return out


## Reads a res:// text file. The res:// path is tried first so it also works inside an
## exported .pck, where `globalize_path` points at a file that does not exist on disk.
static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		return file.get_as_text()
	var global := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(global):
		return ""
	var disk := FileAccess.open(global, FileAccess.READ)
	return disk.get_as_text() if disk != null else ""


static func _markdown_to_bbcode(md: String, accent: String) -> String:
	var out := ""
	var link := RegEx.new()
	link.compile("\\[([^\\]]+)\\]\\([^)]*\\)")
	for raw: String in md.split("\n"):
		var line := link.sub(raw.strip_edges(), "$1", true).replace("`", "")
		if line.begins_with("#"):
			var title := line.lstrip("#").strip_edges()
			out += "\n[b][color=#%s]%s[/color][/b]\n" % [accent, title]
		elif line.begins_with("- ") or line.begins_with("* "):
			out += line.substr(2).strip_edges() + "\n"
		elif line.is_empty():
			out += "\n"
		else:
			out += line.replace("**", "") + "\n"
	return out


static func _playlist_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	var text := _read_text(PLAYLIST_PATH)
	if text.is_empty():
		return lines
	var parsed: Variant = JSON.parse_string(text)
	var entries: Array = []
	if parsed is Array:
		entries = parsed
	elif parsed is Dictionary:
		var tracks: Variant = (parsed as Dictionary).get("tracks", [])
		if tracks is Array:
			entries = tracks
	for entry: Variant in entries:
		if entry is Dictionary:
			var d := entry as Dictionary
			var title := str(d.get("title", d.get("file", "Untitled")))
			var artist := str(d.get("artist", ""))
			var license_text := str(d.get("license", ""))
			var line := title if artist.is_empty() else "%s - %s" % [title, artist]
			if not license_text.is_empty():
				line += " (%s)" % license_text
			lines.append(line)
		else:
			lines.append(str(entry))
	return lines
