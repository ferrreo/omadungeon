## A prompt that mixes words and buttons, drawn with the same glyphs the HUD uses.
##
## Every hint line in the game used to be a `Label` holding a sentence with the button's
## *name* typed into it - "A pick   B skip" on a pad, "Enter pick   Esc back" on a keyboard -
## while the HUD beside it drew the real sprite from `assets/sprites/ui/glyphs.png`. Two
## languages for one control, and the typed one was the one a player playing with a real pad
## complained about. This is the one way a screen says "press this": the markup names the
## *action*, and the glyph for it on the device in the player's hands is drawn inline.
##
## Markup: plain words, with `{token}` where a button goes.
##   `{ui_accept}`       the action's binding on the active device (A, or an "Ent" key-cap)
##   `{ui_accept@pad}`   the same, pinned to one device (`@pad` / `@kb`), for a line that
##                       talks about the *other* device
##   `{#dpad}`           a sheet cell by name, for a control that is not an action (the d-pad,
##                       the left stick) - see `CELLS`
##   `{=Start}`          a key-cap carrying a literal label
## Two or more spaces between words is a gap between groups ("{ui_accept} pick   {ui_cancel}
## skip"); one space is a space. Two glyphs written back to back that draw the same thing on
## the current device collapse to one, so "{ui_left}{ui_right}" is two key-caps on a keyboard
## and a single d-pad on a pad.
##
## Each word is its own `Label` and each glyph a `GlyphIcon`, laid out here on one line - or,
## with `wrap`, folded at the container's edge the way the settings hint has to be. It is not
## an `HFlowContainer`: that reports its minimum *height* from whatever width it was last laid
## out at, and a prompt inside a plate that starts hidden has never been laid out at all, so
## the engine reserved a line per word for it and a run summary grew 112 px past the fold.
## `plain()` is the same prompt spelled out ("A pick   B skip"), which is what tests read and
## what a screen reader would want.
class_name UiPrompt
extends Container

## Named sheet cells a prompt may draw without an action behind them.
const CELLS: Dictionary = {
	"a": InputGlyphs.Cell.A,
	"b": InputGlyphs.Cell.B,
	"x": InputGlyphs.Cell.X,
	"y": InputGlyphs.Cell.Y,
	"lb": InputGlyphs.Cell.LB,
	"rb": InputGlyphs.Cell.RB,
	"lt": InputGlyphs.Cell.LT,
	"rt": InputGlyphs.Cell.RT,
	"lstick": InputGlyphs.Cell.LSTICK,
	"rstick": InputGlyphs.Cell.RSTICK,
	"dpad": InputGlyphs.Cell.DPAD,
	"mouse_left": InputGlyphs.Cell.MOUSE_LEFT,
	"mouse_right": InputGlyphs.Cell.MOUSE_RIGHT,
}
## How `plain()` spells those cells.
const CELL_WORDS: Dictionary = {
	"a": "A",
	"b": "B",
	"x": "X",
	"y": "Y",
	"lb": "LB",
	"rb": "RB",
	"lt": "LT",
	"rt": "RT",
	"lstick": "Stick",
	"rstick": "Right stick",
	"dpad": "D-pad",
	"mouse_left": "Mouse L",
	"mouse_right": "Mouse R",
}
const CELL_PREFIX := "#"
const LITERAL_PREFIX := "="
const DEVICE_SEP := "@"
const DEVICE_PAD := "pad"
const DEVICE_KB := "kb"
## Spaces in the plain rendering of a group gap, and the fewest that make one in markup.
const GAP_SPACES := 3
const GAP_MIN := 2
## Width of the spacer between two groups.
const GROUP_GAP := UiTheme.GAP_WIDE
## Vertical gap between two folded lines.
const LINE_GAP := UiTheme.GAP_TIGHT

## Theme variation every word is drawn in.
@export var label_variation: StringName = &"Dim"
## Whether the line may fold at the edge of its container. Off, the prompt asks for the width
## of one line, like a `Label` without autowrap.
@export var wrap: bool = false:
	set(value):
		wrap = value
		update_minimum_size()
		queue_sort()
## Where a line sits in a container wider than it: 0 left, 1 centre, 2 right (the values
## `BoxContainer.AlignmentMode` uses, so a scene can say `alignment = 1`).
@export_enum("Begin", "Center", "End") var alignment: int = 0:
	set(value):
		alignment = value
		queue_sort()

var text: String:
	set = set_text,
	get = get_text

var _markup: String = ""
var _connected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _connected:
		_connected = true
		EventBus.input_device_changed.connect(func(_d: int) -> void: _rebuild())
		EventBus.settings_changed.connect(_on_setting_changed)
	_rebuild()


## Replaces the prompt. Setting the same markup again is a no-op, so a screen may refresh its
## hint every frame without tearing the line down every frame.
func set_text(markup: String) -> void:
	if markup == _markup and get_child_count() > 0:
		return
	_markup = markup
	if is_inside_tree():
		_rebuild()


## The markup as it was set.
func get_text() -> String:
	return _markup


## The prompt spelled out for the active device: "A pick   B skip", "Enter pick   Escape skip".
func plain() -> String:
	return render_plain(_markup)


## Height one line of this prompt takes: the taller of a word and a glyph.
func line_height() -> float:
	var probe := _word("X")
	add_child(probe)
	var height := maxf(probe.get_line_height(), float(InputGlyphs.CELL))
	remove_child(probe)
	probe.free()
	return height


## Width of one space in the body font, which is the separation between two words.
static func space_width() -> float:
	return InputGlyphs.label_size(" ").x


## One line's width when nothing folds; with `wrap`, the widest single part and the height of
## the lines the current width folds it into (one line before the first layout).
func _get_minimum_size() -> Vector2:
	var lines := _lines(size.x if wrap and size.x > 0.0 else INF)
	var out := Vector2.ZERO
	for line: Array in lines:
		out.x = maxf(out.x, _line_width(line))
		out.y += _line_height(line)
	if not lines.is_empty():
		out.y += LINE_GAP * (lines.size() - 1)
	if wrap:
		out.x = 0.0
		for child: Control in _parts():
			out.x = maxf(out.x, child.get_combined_minimum_size().x)
	return out


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var lines := _lines(size.x if wrap else INF)
	var y := 0.0
	for line: Array in lines:
		var line_w := _line_width(line)
		var line_h := _line_height(line)
		var x := 0.0
		if alignment == BoxContainer.ALIGNMENT_CENTER:
			x = floorf((size.x - line_w) * 0.5)
		elif alignment == BoxContainer.ALIGNMENT_END:
			x = size.x - line_w
		for child: Control in line:
			var wanted := child.get_combined_minimum_size()
			var top := y + floorf((line_h - wanted.y) * 0.5)
			fit_child_in_rect(child, Rect2(Vector2(x, top), wanted))
			x += wanted.x + _gap()
		y += line_h + LINE_GAP
	if wrap:
		# The height this asks for depends on the width it was just given.
		update_minimum_size()


## The visible parts, folded greedily into lines no wider than `width`.
func _lines(width: float) -> Array[Array]:
	var lines: Array[Array] = []
	var line: Array[Control] = []
	var used := 0.0
	for child: Control in _parts():
		var w := child.get_combined_minimum_size().x
		if not line.is_empty() and used + _gap() + w > width:
			lines.append(line)
			line = []
			used = 0.0
		if not line.is_empty():
			used += _gap()
		line.append(child)
		used += w
	if not line.is_empty():
		lines.append(line)
	return lines


func _parts() -> Array[Control]:
	var out: Array[Control] = []
	for child: Node in get_children():
		var control := child as Control
		if control != null and control.visible:
			out.append(control)
	return out


func _line_width(line: Array) -> float:
	var width := 0.0
	for child: Control in line:
		width += child.get_combined_minimum_size().x
	return width + _gap() * maxi(line.size() - 1, 0)


func _line_height(line: Array) -> float:
	var height := 0.0
	for child: Control in line:
		height = maxf(height, child.get_combined_minimum_size().y)
	return height


func _gap() -> float:
	return ceilf(space_width())


## `markup` spelled out with the binding names for `device` (-1 for the active one).
static func render_plain(markup: String, device: int = -1) -> String:
	var out := ""
	var last_glyph := false
	for part: Dictionary in parse(markup):
		match str(part["kind"]):
			"word":
				out += ("" if out.is_empty() or out.ends_with(" ") else " ") + str(part["text"])
				last_glyph = false
			"gap":
				out = out.strip_edges(false, true) + " ".repeat(GAP_SPACES)
				last_glyph = false
			"glyph":
				var joiner := (
					"/" if last_glyph else ("" if out.is_empty() or out.ends_with(" ") else " ")
				)
				out += joiner + _plain_name(part, device)
				last_glyph = true
	return out


## Splits markup into parts: {kind: "word", text}, {kind: "gap"} and
## {kind: "glyph", action | cell | literal, device}.
static func parse(markup: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var word := ""
	var spaces := 0
	var i := 0
	while i < markup.length():
		var c := markup[i]
		if c == "{":
			var close := markup.find("}", i)
			if close > i + 1:
				_flush(out, word, spaces)
				word = ""
				spaces = 0
				out.append(_token(markup.substr(i + 1, close - i - 1)))
				i = close + 1
				continue
		if c == " ":
			if not word.is_empty():
				out.append({"kind": "word", "text": word})
				word = ""
			spaces += 1
		else:
			if spaces >= GAP_MIN:
				out.append({"kind": "gap"})
			spaces = 0
			word += c
		i += 1
	_flush(out, word, 0)
	return out


static func _flush(out: Array[Dictionary], word: String, spaces: int) -> void:
	if not word.is_empty():
		out.append({"kind": "word", "text": word})
	if spaces >= GAP_MIN:
		out.append({"kind": "gap"})


static func _token(body: String) -> Dictionary:
	var device := -1
	var name := body
	var at := body.rfind(DEVICE_SEP)
	if at >= 0:
		var suffix := body.substr(at + 1)
		if suffix == DEVICE_PAD:
			device = InputGlyphs.Device.GAMEPAD
		elif suffix == DEVICE_KB:
			device = InputGlyphs.Device.KEYBOARD
		if device >= 0:
			name = body.substr(0, at)
	if name.begins_with(CELL_PREFIX):
		return {"kind": "glyph", "cell": name.substr(1).to_lower(), "device": device}
	if name.begins_with(LITERAL_PREFIX):
		return {"kind": "glyph", "literal": name.substr(1), "device": device}
	return {"kind": "glyph", "action": StringName(name), "device": device}


static func _plain_name(part: Dictionary, device: int) -> String:
	if part.has("cell"):
		return str(CELL_WORDS.get(part["cell"], part["cell"]))
	if part.has("literal"):
		return str(part["literal"])
	var pinned := int(part["device"])
	var for_device := pinned if pinned >= 0 else device
	if for_device < 0:
		for_device = int(InputGlyphs.current_device())
	return InputGlyphs.binding_name(part["action"], for_device as InputGlyphs.Device)


func _on_setting_changed(key: String) -> void:
	if key == "bindings":
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var last_key := ""
	for part: Dictionary in parse(_markup):
		match str(part["kind"]):
			"word":
				add_child(_word(str(part["text"])))
				last_key = ""
			"gap":
				add_child(_spacer())
				last_key = ""
			"glyph":
				var glyph := _glyph(part)
				var key := glyph.drawn_key()
				if key == last_key:
					glyph.free()
					continue
				last_key = key
				add_child(glyph)
	update_minimum_size()
	queue_sort()


func _word(word: String) -> Label:
	var label := Label.new()
	label.text = word
	label.theme_type_variation = label_variation
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(GROUP_GAP, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _glyph(part: Dictionary) -> GlyphIcon:
	var glyph := GlyphIcon.new()
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.device = int(part["device"])
	if part.has("cell"):
		glyph.cell = int(CELLS.get(part["cell"], InputGlyphs.Cell.KEYCAP))
	elif part.has("literal"):
		glyph.literal = str(part["literal"])
	else:
		glyph.action = part["action"]
	return glyph
