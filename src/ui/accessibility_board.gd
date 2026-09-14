## Development board that puts every colour-coded channel of the game side by side: the left
## column as colour alone, the right column with the `colorblind_glyphs` shapes on top.
##
## It exists to be screenshotted and pushed through `tools/colourblind_check.py`: the tool
## needs swatches at known coordinates, and `swatch_rects()` is where those coordinates come
## from, so the check can never drift from the layout. It is never part of a real run — the
## UI gallery (`tools/ui-gallery.sh`) is the only thing that instantiates it.
class_name AccessibilityBoard
extends Control

## One channel of the board: a heading and the chips under it.
const ROWS: Array[Dictionary] = [
	{"title": "Rarity", "kind": "rarity"},
	{"title": "Status", "kind": "status"},
	{"title": "Rooms", "kind": "room"},
	{"title": "Health", "kind": "health"},
]
## Rarity chips, in ItemInstance.Rarity order (the same palette roles the game uses).
const RARITY_ROLES: Array[StringName] = ItemInstance.RARITY_ROLES
const RARITY_LABELS: PackedStringArray = Accessibility.RARITY_MARKS
## Status chips: StatusEffect.Kind values that actually show up on a player.
const STATUS_KINDS: Array[int] = [0, 1, 2, 3, 9]
## Room chips: Minimap.RoomKind values with their own shape.
const ROOM_KINDS: Array[int] = [2, 4, 6, 8, 9]
const ROOM_LABELS: PackedStringArray = ["Elite", "Loot", "Shop", "Down", "Boss"]
## Health chips: fraction of max HP.
const HEALTH_FRACTIONS: PackedFloat32Array = [0.85, 0.5, 0.18, 0.06]

const MARGIN := 8.0
const COLUMN_GAP := 12.0
const ROW_HEIGHT := 46.0
const HEADING_HEIGHT := 12.0
const CHIP := Vector2(26.0, 18.0)
const CHIP_GAP := 6.0
const TITLE_HEIGHT := 16.0
## Baseline of the tag caption under a chip. The tag goes below rather than beside the shape:
## at 26 px a chip has room for one or the other, never both.
const TAG_BASELINE := 9.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: queue_redraw())


## Width of one of the two columns at the current size.
func column_width() -> float:
	return floorf((size.x - MARGIN * 2.0 - COLUMN_GAP) * 0.5)


## Every chip on the board as `"<column>_<kind>_<index>" -> Rect2i`, in image pixels.
## `column` is "colour" or "glyph". This is what feeds `tools/colourblind_check.py --swatch`.
func swatch_rects() -> Dictionary:
	var out: Dictionary = {}
	var width := column_width()
	for column in 2:
		var prefix := "glyph" if column == 1 else "colour"
		var x0 := MARGIN + float(column) * (width + COLUMN_GAP)
		for r in ROWS.size():
			var kind := str(ROWS[r]["kind"])
			var top := TITLE_HEIGHT + float(r) * ROW_HEIGHT + HEADING_HEIGHT
			for i in _chip_count(kind):
				var rect := Rect2(x0 + float(i) * (CHIP.x + CHIP_GAP), top, CHIP.x, CHIP.y)
				out["%s_%s_%d" % [prefix, kind, i]] = Rect2i(rect)
	return out


## Chip labels in the same order as `swatch_rects`, for a human reading the report.
static func chip_label(kind: String, index: int) -> String:
	match kind:
		"rarity":
			return RARITY_LABELS[index]
		"status":
			return Accessibility.status_mark(STATUS_KINDS[index])
		"room":
			return ROOM_LABELS[index]
		"health":
			return "%d%%" % int(roundf(HEALTH_FRACTIONS[index] * 100.0))
	return ""


static func _chip_count(kind: String) -> int:
	match kind:
		"rarity":
			return RARITY_ROLES.size()
		"status":
			return STATUS_KINDS.size()
		"room":
			return ROOM_KINDS.size()
		"health":
			return HEALTH_FRACTIONS.size()
	return 0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.color(&"floor"))
	var font := UiTheme.body_font()
	var ink := UiTheme.text_color(&"text")
	draw_string(
		font, Vector2(MARGIN, 11), "Colour only", HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S, ink
	)
	var width := column_width()
	draw_string(
		font,
		Vector2(MARGIN + width + COLUMN_GAP, 11),
		"With glyphs",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiTheme.SIZE_S,
		ink
	)
	for column in 2:
		var x0 := MARGIN + float(column) * (width + COLUMN_GAP)
		for r in ROWS.size():
			var kind := str(ROWS[r]["kind"])
			var top := TITLE_HEIGHT + float(r) * ROW_HEIGHT
			if column == 0:
				draw_string(
					font,
					Vector2(x0, top + 8.0),
					str(ROWS[r]["title"]),
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					UiTheme.SIZE_S,
					UiTheme.text_color(&"text_dim")
				)
			for i in _chip_count(kind):
				var rect := Rect2(
					x0 + float(i) * (CHIP.x + CHIP_GAP), top + HEADING_HEIGHT, CHIP.x, CHIP.y
				)
				_draw_chip(rect, kind, i, column == 1)


func _draw_chip(rect: Rect2, kind: String, index: int, glyphs: bool) -> void:
	var role := _chip_role(kind, index)
	var fill := UiTheme.color(role)
	draw_rect(rect, fill)
	draw_rect(rect, UiTheme.readable_on(UiTheme.color(&"void"), fill, 3.0), false, 1.0)
	if not glyphs:
		return
	var mark := UiTheme.readable_on(UiTheme.color(&"void"), fill, 4.5)
	var shape := _chip_shape(kind, index)
	if shape >= 0:
		Accessibility.draw_shape(self, rect.grow(-3.0), shape, mark)
	var label := chip_label(kind, index)
	if label.is_empty():
		return
	var font := UiTheme.body_font()
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S).x
	draw_string(
		font,
		rect.position + Vector2(floorf((rect.size.x - width) * 0.5), rect.size.y + TAG_BASELINE),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiTheme.SIZE_S,
		UiTheme.text_color(&"text")
	)


static func _chip_role(kind: String, index: int) -> StringName:
	match kind:
		"rarity":
			return RARITY_ROLES[index]
		"status":
			return Accessibility.status_role(STATUS_KINDS[index])
		"room":
			return StringName(str(Minimap.KIND_ROLES.get(ROOM_KINDS[index], &"text")))
		"health":
			return &"danger" if HEALTH_FRACTIONS[index] < HpBar.DANGER_FRACTION else &"heal"
	return &"text"


static func _chip_shape(kind: String, index: int) -> int:
	match kind:
		"rarity":
			return Accessibility.rarity_shape(index)
		"status":
			return Accessibility.status_shape(STATUS_KINDS[index])
		"room":
			return Accessibility.room_shape(ROOM_KINDS[index])
		"health":
			return (
				Accessibility.Shape.TRIANGLE
				if HEALTH_FRACTIONS[index] < HpBar.DANGER_FRACTION
				else Accessibility.Shape.BAR
			)
	return -1
