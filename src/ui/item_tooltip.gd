## What a ground drop says about itself, drawn on the HUD rather than in the world.
##
## The old `ItemCompareCard` was a world-space plate beside the drop that appeared the moment
## the player entered the pickup's detection box and stayed up for as long as they stood
## anywhere near it - half a screen of comparison over the room the player was still fighting
## in. This widget has two sizes and neither of them is that:
##   * **near** (`LEVEL_NEAR`) - a one-line tag above the drop: its name in its rarity colour
##     and its kind. Follows the drop on screen. Small enough to ignore.
##   * **close** (`LEVEL_CLOSE`) - the compare card, only while the player is standing on the
##     drop (`ItemPickup.CLOSE_RADIUS`). It sits on the **left edge** of the screen, in the
##     band between the HP block and the ability bar (`set_band`), so it is beside the player
##     rather than under or over them, and never more than `MAX_AREA_FRACTION` of the frame.
##     One column, every row `CompareRows` gives the pair: the band is tall enough for the
##     longest real trade, and picking a drop up equips it at once with no second screen, so
##     a row hidden here would be a difference the player never saw.
## Both read the same rows the compare screen does (`CompareRows`), so a drop and a chest
## never disagree about what a swap is worth.
##
## Fed through `EventBus.item_hover(pickup, item, level)`; the HUD owns one of these.
class_name ItemTooltip
extends Control

enum Level { NONE, NEAR, CLOSE }

## The card may never cover more than this share of the viewport.
const MAX_AREA_FRACTION := 0.25
## Widest the card may be, on the 480x270 frame: a third of the width, well clear of the
## screen's centre column where the player stands.
const MAX_WIDTH := 168.0
## Narrowest it draws, so a trinket with two rows is still a plate and not a sliver.
const MIN_WIDTH := 112.0
## Gap between the card and the screen edge, and between the card and the band's ends.
const EDGE_GAP := 4.0
## Padding inside either plate.
const PAD := 4.0
## Height of one text line (the body font is 8 px, drawn without leading).
const LINE := 8.0
## Gap between the tag and the drop.
const TAG_LIFT := 14.0
## Gap between a row's label and its values.
const VALUE_GAP := 8.0
## Plate opacity: high enough that the floor never shows through the text.
const PLATE_ALPHA := 0.96
## Lines the head takes: name, kind, what it replaces.
const HEAD_LINES := 3
## The band the card sits in when the HUD has not said otherwise: under a top plate and above a
## bottom bar of the default HUD's size.
const DEFAULT_BAND_TOP := 56.0
const DEFAULT_BAND_BOTTOM_INSET := 48.0
const REPLACES_TEXT := "replaces %s"
const EMPTY_SLOT_TEXT := "fills an empty slot"

var level: int = Level.NONE
var item: ItemInstance
## The drop the tag follows; null once it is gone.
var pickup: Node2D
## Rows of the card, `{label, old, new, role}` from `CompareRows`, cut to what fits.
var rows: Array[Dictionary] = []
## The unique-effect sentence, "" for none.
var unique_text: String = ""
var _replaces: String = ""
var _card_size: Vector2 = Vector2.ZERO
## Screen y of the top and bottom of the free band the card may sit in.
var _band_top: float = -1.0
var _band_bottom: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: queue_redraw())


func _process(_delta: float) -> void:
	if level == Level.NEAR and visible:
		# The tag follows the drop as the camera moves.
		queue_redraw()


## Shows `new_item` lying under `new_pickup` at `new_level`; `gear` and `stats` are the
## player's, for the close card's comparison (either may be null; `stats` is kept on the
## signature for the sheet-aware card a later round may draw). `Level.NONE` hides.
func show_item(
	new_pickup: Node2D, new_item: ItemInstance, new_level: int, gear: Equipment, _stats: Stats
) -> void:
	level = new_level
	pickup = new_pickup
	item = new_item
	rows = []
	unique_text = ""
	_replaces = ""
	if level == Level.NONE or item == null or item.base == null:
		level = Level.NONE
		visible = false
		queue_redraw()
		return
	if level == Level.CLOSE:
		var current: ItemInstance = null
		if gear != null:
			current = gear.get_item(gear.target_slot(item))
		_replaces = (
			REPLACES_TEXT % ItemCard.worn_name(current) if current != null else EMPTY_SLOT_TEXT
		)
		unique_text = CompareRows.unique_text(item)
		var font := _font()
		var all := CompareRows.stat_rows(CompareRows.rows_for(current, item))
		var width := card_width(all, font, head_lines())
		rows = fit_rows(all, capacity(width, font))
		_card_size = measure(rows, unique_text, font, width)
	visible = true
	queue_redraw()


func hide_item() -> void:
	show_item(null, null, Level.NONE, null, null)


## The free band (screen y of its top and bottom) the close card is placed in: the HUD passes
## the bottom of its top-left plate and the top of its ability bar.
func set_band(top: float, bottom: float) -> void:
	_band_top = top
	_band_bottom = bottom
	queue_redraw()


## The band in use: what the HUD set, or the default HUD geometry.
func band() -> Vector2:
	if _band_top >= 0.0 and _band_bottom > _band_top:
		return Vector2(_band_top, _band_bottom)
	return Vector2(DEFAULT_BAND_TOP, size.y - DEFAULT_BAND_BOTTOM_INSET)


## The card's size in pixels, as last measured.
func card_size() -> Vector2:
	return _card_size


## Where the close card draws: on the left edge, centred in the band.
func card_rect() -> Rect2:
	var b := band()
	var room := b.y - b.x - EDGE_GAP * 2.0
	var y := b.x + EDGE_GAP + maxf(0.0, (room - _card_size.y) * 0.5)
	return Rect2(Vector2(EDGE_GAP, floorf(y)), _card_size)


## Tallest the card may be: the band less its gaps, and never past the area cap at `width`.
func max_height(width: float) -> float:
	var b := band()
	var by_band := b.y - b.x - EDGE_GAP * 2.0
	if size.x <= 0.0 or size.y <= 0.0:
		return by_band
	return minf(by_band, floorf(size.x * size.y * MAX_AREA_FRACTION / maxf(1.0, width)))


## How many rows the card can hold under its cap: what `max_height` leaves after the head and
## the unique effect's lines.
func capacity(width: float, font: Font) -> int:
	var body := max_height(width) - PAD * 2.0 - LINE * HEAD_LINES
	body -= LINE * unique_lines(unique_text, font, width)
	return maxi(2, int(floorf(body / LINE)))


## Lines the unique-effect sentence wraps to inside a card `width` wide; 0 for none.
static func unique_lines(unique: String, font: Font, width: float) -> int:
	if unique.is_empty():
		return 0
	return CardFit.wrapped_lines(unique, font, width - PAD * 2.0)


## The three lines of the head: name, kind, what the drop replaces.
func head_lines() -> PackedStringArray:
	return PackedStringArray([item.display_name, CompareView.subtitle_text(item), _replaces])


## The width the card draws at for `card_rows` under `head`: enough for the widest head line
## and the widest row (label, gap, both values), between `MIN_WIDTH` and `MAX_WIDTH`. A head
## line wider than `MAX_WIDTH` ("replaces Vital Copper Ring of Root") is clipped by the
## plate's own width rather than growing the card past its cap.
static func card_width(
	card_rows: Array[Dictionary], font: Font, head: PackedStringArray = []
) -> float:
	var widest := 0.0
	for line: String in head:
		widest = maxf(widest, _width(line, font))
	for row: Dictionary in card_rows:
		var w := _width(str(row["label"]), font) + VALUE_GAP + _width(values_text(row), font)
		widest = maxf(widest, w)
	return clampf(widest + PAD * 2.0, MIN_WIDTH, MAX_WIDTH)


## `rows` cut to `capacity`: rows where the number changes come first, so a card that has to
## drop something drops a "no change" row rather than the reason to pick the item up. With
## the band the HUD gives it no real trade is cut; this is the guard for a screen so short
## that the cap bites.
static func fit_rows(all: Array[Dictionary], capacity: int) -> Array[Dictionary]:
	if all.size() <= capacity:
		return all
	var moved: Array[Dictionary] = []
	var same: Array[Dictionary] = []
	for row: Dictionary in all:
		if StringName(str(row["role"])) == CompareRows.ROLE_SAME:
			same.append(row)
		else:
			moved.append(row)
	var out: Array[Dictionary] = []
	for row: Dictionary in moved + same:
		if out.size() >= capacity:
			break
		out.append(row)
	return out


## Size of the close card: one column of rows under a three-line head, the unique effect's
## wrapped lines under them, at `width`.
static func measure(
	card_rows: Array[Dictionary], unique: String, font: Font, width: float = MAX_WIDTH
) -> Vector2:
	var height := PAD * 2.0 + LINE * HEAD_LINES + LINE * float(card_rows.size())
	height += LINE * unique_lines(unique, font, width)
	return Vector2(width, height)


## Whether a card of `card` px inside a `view` px frame keeps under the area cap.
static func within_budget(card: Vector2, view: Vector2) -> bool:
	if view.x <= 0.0 or view.y <= 0.0:
		return true
	return card.x * card.y <= view.x * view.y * MAX_AREA_FRACTION


## "Damage 12 -> 8" as one line.
static func row_text(row: Dictionary) -> String:
	return "%s %s" % [row["label"], values_text(row)]


## "12 -> 8": the two values of a row.
static func values_text(row: Dictionary) -> String:
	return "%s %s %s" % [row["old"], ItemCard.SWAP_ARROW, row["new"]]


func _draw() -> void:
	if level == Level.NONE or item == null:
		return
	if level == Level.NEAR:
		_draw_tag()
	else:
		_draw_card()


## The near tag: name and kind on a small plate above the drop.
func _draw_tag() -> void:
	if pickup == null or not is_instance_valid(pickup) or not pickup.is_inside_tree():
		return
	var font := _font()
	var name := item.display_name
	var kind := CompareView.subtitle_text(item)
	var plate_size := Vector2(
		maxf(_width(name, font), _width(kind, font)) + PAD * 2.0, LINE * 2.0 + PAD * 2.0
	)
	var screen := pickup.get_viewport().get_canvas_transform() * pickup.global_position
	var top_left := Vector2(
		floorf(screen.x - plate_size.x * 0.5), floorf(screen.y - TAG_LIFT - plate_size.y)
	)
	top_left.x = clampf(top_left.x, 0.0, maxf(0.0, size.x - plate_size.x))
	top_left.y = clampf(top_left.y, 0.0, maxf(0.0, size.y - plate_size.y))
	_plate(Rect2(top_left, plate_size), item.rarity_role())
	var x := top_left.x + PAD
	var y := top_left.y + PAD + LINE - 1.0
	_text(font, Vector2(x, y), name, UiTheme.text_color(item.rarity_role()))
	_text(font, Vector2(x, y + LINE), kind, _dim())


## The close card: head, then one row per line with the values right-aligned, then the
## unique effect in full.
func _draw_card() -> void:
	var font := _font()
	var rect := card_rect()
	_plate(rect, item.rarity_role())
	var x := rect.position.x + PAD
	var right := rect.end.x - PAD
	var y := rect.position.y + PAD + LINE - 1.0
	var inner := rect.size.x - PAD * 2.0
	var head := head_lines()
	_clipped(font, Vector2(x, y), head[0], inner, UiTheme.text_color(item.rarity_role()))
	y += LINE
	_clipped(font, Vector2(x, y), head[1], inner, _dim())
	y += LINE
	_clipped(font, Vector2(x, y), head[2], inner, _dim())
	y += LINE
	for row: Dictionary in rows:
		var values := values_text(row)
		_text(font, Vector2(x, y), str(row["label"]), _dim())
		_text(
			font,
			Vector2(right - _width(values, font), y),
			values,
			_role_color(StringName(str(row["role"])))
		)
		y += LINE
	if not unique_text.is_empty():
		draw_multiline_string(
			font,
			Vector2(x, y),
			unique_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - PAD * 2.0,
			UiTheme.SIZE_S,
			-1,
			UiTheme.text_color(&"magic")
		)


func _plate(rect: Rect2, border_role: StringName) -> void:
	var plate := UiTheme.plate_color(PLATE_ALPHA)
	draw_rect(rect, plate)
	draw_rect(rect, UiTheme.readable_on(UiTheme.color(border_role), plate, 3.0), false, 1.0)


func _text(font: Font, at: Vector2, text: String, color: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S, color)


## A line cut with an ellipsis at `width`: only the head uses it, and only for a name longer
## than the card's cap - the rows are what may never be cut.
func _clipped(font: Font, at: Vector2, text: String, width: float, color: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, width, UiTheme.SIZE_S, color)


static func _width(text: String, font: Font) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S).x


func _role_color(role: StringName) -> Color:
	if role == CompareRows.ROLE_UP or role == CompareRows.ROLE_DOWN:
		return UiTheme.signal_color(role)
	if role == CompareRows.ROLE_SAME:
		return UiTheme.on(&"text", &"void", 4.5)
	return _dim()


func _dim() -> Color:
	return UiTheme.on(&"text_dim", &"void", 4.5)


func _font() -> Font:
	var font := UiTheme.body_font()
	return font if font != null else ThemeDB.fallback_font
