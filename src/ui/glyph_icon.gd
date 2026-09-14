## A 16x16 input glyph for one action; keycaps get the key label drawn on top.
##
## A multi-character label ("Spc", "Tab", "Esc") does not fit the 16 px key-cap sprite, so the
## cap is widened for it - three-sliced, keeping its rounded ends - and the control's minimum
## size grows to match. Before that, the label was simply centred in a 16 px cell with no
## clipping and no widening: DODGE read as a fragment plus "p", MAP read "AB" and PAUSE read
## "SC" on the Controls page, which is the only place the game teaches its controls.
##
## Draws one of three things, in this order of precedence: `literal` (a key-cap carrying that
## label), `cell` (a sheet cell by index, for a control that is not an action - the d-pad),
## or `action` (the binding on `device`, or on the active device when that is -1).
##
## Re-draws and re-measures when the active device or a binding changes.
class_name GlyphIcon
extends Control

@export var action: StringName = &"interact":
	set(value):
		action = value
		_refresh()
## Sheet cell to draw instead of the action's binding; -1 draws the action.
@export var cell: int = -1:
	set(value):
		cell = value
		_refresh()
## Label to draw on a blank key-cap instead of anything bound; empty draws the action.
@export var literal: String = "":
	set(value):
		literal = value
		_refresh()
## `InputGlyphs.Device` to draw the binding for; -1 follows the active device.
@export var device: int = -1:
	set(value):
		device = value
		_refresh()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.input_device_changed.connect(func(_d: int) -> void: _refresh())
	EventBus.settings_changed.connect(_on_setting_changed)
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: _refresh())
	_refresh()


## Width this glyph needs: 16 px for a cap that fits, wider for a label that does not.
func glyph_width() -> float:
	return InputGlyphs.width_for_label(drawn_label())


## Whether the current binding is drawn on a widened cap rather than the plain sprite.
func is_wide() -> bool:
	return glyph_width() > float(InputGlyphs.CELL)


## The sheet cell this glyph draws right now.
func drawn_cell() -> int:
	if not literal.is_empty():
		return InputGlyphs.Cell.KEYCAP
	if cell >= 0:
		return cell
	return InputGlyphs.cell_for(action, device)


## The label this glyph writes over its cap right now; empty for a sprite with its own face.
func drawn_label() -> String:
	if not literal.is_empty():
		return literal
	if cell >= 0:
		return ""
	return InputGlyphs.label_for(action, device)


## One string per distinct drawing, so two glyphs that would look the same can be told apart
## from two that would not (`UiPrompt` collapses a run of the former).
func drawn_key() -> String:
	return "%d|%s" % [drawn_cell(), drawn_label()]


func _on_setting_changed(key: String) -> void:
	if key == "bindings":
		_refresh()


func _refresh() -> void:
	custom_minimum_size = Vector2(glyph_width(), InputGlyphs.CELL)
	queue_redraw()


func _draw() -> void:
	var cell_px := float(InputGlyphs.CELL)
	var label := drawn_label()
	var drawn := drawn_cell()
	var width := InputGlyphs.width_for_label(label)
	var origin := Vector2(floorf((size.x - width) * 0.5), floorf((size.y - cell_px) * 0.5))
	if label.is_empty() or drawn != InputGlyphs.Cell.KEYCAP:
		draw_texture(InputGlyphs.cell_texture(drawn), origin)
		if label.is_empty():
			return
	else:
		InputGlyphs.draw_keycap(self, Rect2(origin, Vector2(width, cell_px)))
	var font := UiTheme.body_font()
	var text_size := InputGlyphs.label_size(label)
	var pos := origin + Vector2(floorf((width - text_size.x) * 0.5), floorf(cell_px * 0.5 + 3.0))
	# Themed, with a contrast floor against the key-cap *sprite* - the thing the label is
	# actually drawn on. Measuring against a palette role instead put light-grey ink on a
	# near-white cap at 1.5:1 on every light theme.
	var ink := InputGlyphs.keycap_ink(UiTheme.color(&"void"))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S, ink)
