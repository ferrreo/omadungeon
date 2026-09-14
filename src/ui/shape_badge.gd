## A single accessibility shape (optionally with a short text tag beside it), drawn in a
## palette role and re-drawn when the palette or the glyph setting changes.
##
## It is the reusable half of `Accessibility.draw_shape`: widgets that already custom-draw
## call the static helper, widgets built out of Controls (chest cards, menu rows) drop one of
## these in instead. It never paints when `colorblind_glyphs` is off unless `always` is set.
class_name ShapeBadge
extends Control

const SIZE := 8
const TAG_GAP := 2

## Which `Accessibility.Shape` to draw; -1 draws nothing.
@export var shape: int = -1:
	set(value):
		shape = value
		queue_redraw()

## Palette role the shape is tinted with.
@export var role: StringName = &"text":
	set(value):
		role = value
		queue_redraw()

## Optional short tag drawn to the right of the shape ("***", "BRN").
@export var tag: String = "":
	set(value):
		tag = value
		update_minimum_size()
		queue_redraw()

## Palette role the badge judges its contrast against.
@export var surface: StringName = &"floor_alt"

## When true the badge draws even with the glyph setting off (used by the UI gallery).
@export var always: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = _wanted_size()
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: queue_redraw())
	EventBus.settings_changed.connect(_on_setting_changed)


func _get_minimum_size() -> Vector2:
	return _wanted_size()


## True when this badge currently contributes a visible, non-colour channel.
func is_showing() -> bool:
	return shape >= 0 and (always or Accessibility.glyphs())


func _on_setting_changed(key: String) -> void:
	if key == Accessibility.SETTING_GLYPHS:
		update_minimum_size()
		queue_redraw()


func _wanted_size() -> Vector2:
	if not is_showing():
		return Vector2.ZERO
	var width := float(SIZE)
	if not tag.is_empty():
		var font := UiTheme.body_font()
		width += (
			TAG_GAP + font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S).x
		)
	return Vector2(width, float(SIZE))


func _draw() -> void:
	if not is_showing():
		return
	var ink := UiTheme.on(role, surface, 3.0)
	var box := Rect2(0.0, floorf((size.y - SIZE) * 0.5), float(SIZE), float(SIZE))
	Accessibility.draw_shape(self, box, shape, ink)
	if tag.is_empty():
		return
	var font := UiTheme.body_font()
	var pos := Vector2(box.end.x + TAG_GAP, floorf(size.y * 0.5 + 3.0))
	draw_string(font, pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S, ink)
