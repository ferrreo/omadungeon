## HUD strip of the status effects currently on the player.
##
## Every chip answers "what is on me?" without any setting turned on: it takes its own palette
## role (`Accessibility.STATUS_ROLES` - burn is hot, frost is cold, poison is not either) and
## it always carries its three-letter tag (`Accessibility.STATUS_MARKS`). Ten identical red
## squares told a player how many things were wrong and never which, and frost - whose third
## stack freezes you - was the same square as a slow.
##
## With `colorblind_glyphs` on each chip also gets its own shape, so the hue stops mattering
## at all. Stacks are a digit drawn *inside* the chip; it used to hang over the right border
## and be clipped by it, which is how "2 frost stacks" became a half-glyph.
##
## `bind(entity)` duck-types the entity: it wants a `status` that exposes `effects`
## (Kind -> StatusEffect) and the `status_added` / `status_removed` signals.
class_name StatusRow
extends Control

const CHIP := 12
const CHIP_GAP := 2
const TAG_GAP := 2
## Right-hand padding after the tag, so two chips never touch letters.
const TAG_PAD := 2
## Widest tag in `Accessibility.STATUS_MARKS`; every tag is three capitals, so one measurement
## sizes them all and the row does not jitter as effects come and go.
const WIDEST_TAG := "WKN"
## Inset of the stack digit from the chip's right and bottom edges. The digit is placed from
## its measured size, so it stays inside the border on every font the theme may load.
const STACK_INSET := 1.0
## Chips fade for the last stretch of their duration; a chip that never fades reads as stuck.
const FADE_AT := 0.25

var _entity: Node
var _status: Node
## Sorted by StatusEffect.Kind so the row does not reshuffle between frames.
var _kinds: Array[int] = []
var _remaining: Dictionary = {}
var _durations: Dictionary = {}
var _stacks: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, CHIP)
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: queue_redraw())
	EventBus.settings_changed.connect(_on_setting_changed)


func _process(_delta: float) -> void:
	# The controller owns the countdown; this only mirrors it, so sampling is enough.
	if _status == null or not is_instance_valid(_status):
		if not _kinds.is_empty():
			_sample()
		return
	_sample()


## Binds to the entity whose statuses are shown. Pass null to clear the row.
func bind(entity: Node) -> void:
	_entity = entity
	_status = null
	if entity != null and is_instance_valid(entity):
		var status: Variant = entity.get("status")
		if status is Node:
			_status = status as Node
	_sample()


## Kinds currently drawn, lowest StatusEffect.Kind first.
func shown_kinds() -> Array[int]:
	return _kinds.duplicate()


## Width one chip takes: the square plus the widest three-letter tag. The tag is drawn
## whatever the accessibility setting says - it is the only channel that names the effect -
## so the width no longer depends on a setting either.
func chip_width() -> float:
	return float(CHIP + TAG_GAP + TAG_PAD) + ceilf(tag_width())


## Width reserved for the tag text, measured once off the widest tag so the row keeps its
## shape as effects come and go.
func tag_width() -> float:
	var font := UiTheme.body_font()
	return font.get_string_size(WIDEST_TAG, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S).x


func _on_setting_changed(key: String) -> void:
	if key == Accessibility.SETTING_GLYPHS:
		queue_redraw()


func _sample() -> void:
	var kinds: Array[int] = []
	_remaining.clear()
	_durations.clear()
	_stacks.clear()
	if _status != null and is_instance_valid(_status):
		var effects: Variant = _status.get("effects")
		if effects is Dictionary:
			for key: Variant in (effects as Dictionary).keys():
				var effect: Variant = (effects as Dictionary)[key]
				if not (effect is StatusEffect):
					continue
				var kind := int(key)
				kinds.append(kind)
				_remaining[kind] = (effect as StatusEffect).remaining
				_durations[kind] = maxf(0.001, (effect as StatusEffect).duration)
				_stacks[kind] = (effect as StatusEffect).stacks
	kinds.sort()
	var changed := kinds != _kinds
	_kinds = kinds
	custom_minimum_size = Vector2(
		_kinds.size() * chip_width() + maxi(0, _kinds.size() - 1) * CHIP_GAP, CHIP
	)
	if changed or not _kinds.is_empty():
		queue_redraw()


func _draw() -> void:
	if _kinds.is_empty():
		return
	var glyphs := Accessibility.glyphs()
	var width := chip_width()
	var plate := UiTheme.plate_color(0.8)
	var x := 0.0
	for kind: int in _kinds:
		var rect := Rect2(x, 0.0, width, float(CHIP))
		_draw_chip(rect, kind, glyphs, plate)
		x += width + CHIP_GAP


func _draw_chip(rect: Rect2, kind: int, glyphs: bool, plate: Color) -> void:
	var role := Accessibility.status_role(kind)
	var ink := UiTheme.readable_on(UiTheme.color(role), plate, 3.5)
	var left := float(_remaining.get(kind, 0.0))
	var total := float(_durations.get(kind, 1.0))
	var fraction := clampf(left / total, 0.0, 1.0)
	var alpha := 1.0 if fraction > FADE_AT else 0.45 + 0.55 * (fraction / FADE_AT)
	draw_rect(rect, plate)
	var border := ink
	border.a = alpha
	var square := Rect2(rect.position, Vector2(CHIP, CHIP))
	draw_rect(square, border, false, 1.0)
	if glyphs:
		var shape_rect := Rect2(square.position + Vector2(1, 1), Vector2(CHIP - 2, CHIP - 2))
		Accessibility.draw_shape(self, shape_rect, Accessibility.status_shape(kind), border)
	else:
		var fill := Rect2(square.position + Vector2(2, 2), Vector2(CHIP - 4, CHIP - 4))
		draw_rect(fill, border)
	# The tag is what actually names the effect, so it is never behind a setting.
	_draw_tag(rect, Accessibility.status_mark(kind), border)
	# Duration drain: a bar under the chip, which is position, not hue.
	var drain := Rect2(rect.position + Vector2(0, rect.size.y - 1), Vector2(rect.size.x, 1))
	draw_rect(drain, UiTheme.color_a(&"void", 0.6))
	draw_rect(Rect2(drain.position, Vector2(drain.size.x * fraction, 1)), border)
	var stacks := int(_stacks.get(kind, 1))
	if stacks > 1:
		_draw_stacks(square, stacks)


## Rectangle the stack digit occupies, always inside the chip square. Exposed so a test can
## prove the digit is not hanging over the border again without sampling pixels.
func stack_rect(chip_origin: Vector2, stacks: int) -> Rect2:
	var font := UiTheme.body_font()
	var size := font.get_string_size(str(stacks), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S)
	var width := minf(ceilf(size.x), float(CHIP) - 2.0 * STACK_INSET)
	# The digit's ink, not the font's line box: a full line box is 10 of the chip's 12 pixels
	# and its backing plate ate the chip colour it was supposed to sit on.
	var height := minf(ceilf(font.get_ascent(UiTheme.SIZE_S)), float(CHIP) - 2.0 * STACK_INSET)
	var pos := chip_origin + Vector2(float(CHIP) - STACK_INSET - width, float(CHIP) - 1.0 - height)
	return Rect2(pos.floor(), Vector2(width, height))


func _draw_stacks(square: Rect2, stacks: int) -> void:
	var box := stack_rect(square.position, stacks)
	# A plate behind the digit: with glyphs off the chip interior is the status colour, and a
	# white "3" on a yellow shock chip was as unreadable as no digit at all.
	var backing := UiTheme.plate_color(0.9)
	draw_rect(box.grow(STACK_INSET * 0.5), backing)
	var ink := UiTheme.readable_on(UiTheme.color(&"text_bright"), backing, 4.5)
	draw_string(
		UiTheme.body_font(),
		Vector2(box.position.x, box.end.y),
		str(stacks),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiTheme.SIZE_S,
		ink
	)


## Draws the three-letter tag beside the shape. The shape carries at a glance; the tag is
## what makes two similar shapes unambiguous.
func _draw_tag(rect: Rect2, tag: String, ink: Color) -> void:
	var font := UiTheme.body_font()
	var pos := rect.position + Vector2(CHIP + TAG_GAP, floorf(rect.size.y * 0.5 + 3.0))
	draw_string(font, pos.floor(), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S, ink)
