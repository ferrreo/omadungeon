## The compare screen: the swap step of an offer board, drawn as one table rather than as
## two cards. The thing that comes off is on the left of every row and the thing that goes
## on is on the right, so "what do I lose, what do I gain" is answered by reading down one
## column of aligned numbers, each row coloured by which way it moves.
##
## Nothing here is ever elided. The old trade view cut its before/after list to "+N more"
## when a card ran out of room, which is the one thing a comparison must not do: the row it
## hid was the row the player was looking for. The table is built whole; when it is taller
## than the room it has it takes one **compact step** (the row gap closes) and, if that is
## still not enough, it scrolls inside its frame - so every row is reachable and none is
## cut. `is_scrollable()` tells the board to say so on the hint line.
##
## Purely presentational: `CompareRows` is the model, and the board (`ChestUi`) decides what
## the two sides are and what confirming does.
class_name CompareView
extends VBoxContainer

## Captions over the two heads. They name the direction of the trade, which is the one thing
## a player has to be certain of before pressing the button.
const OUT_CAPTION := "Yours - comes off"
const IN_CAPTION := "New - goes on"
## Caption for an incoming thing that does not go into the slot being emptied. A cursed chest
## pays for its prize with a Curse, so the thing on the right is what the player *takes*, not
## what lands in the passive slot the left card is leaving.
const TAKE_CAPTION := "New - to take"
## What the back key does on the offer step: nothing is taken and nothing is given up.
const KEEP_VERB := "keep mine"
## What it does once a price step is on screen: the whole trade is off, the prize with it.
const CANCEL_ALL_VERB := "cancel trade"
## Width of the label column and of each value column, on the 480 px frame.
const LABEL_WIDTH := 136.0
const VALUE_WIDTH := 108.0
const MARK_WIDTH := 12.0
## Height of one stat row, and the gap between rows before and after the compact step.
const ROW_GAP := UiTheme.GAP_TIGHT
const COMPACT_GAP := UiTheme.GAP_NONE
## Padding inside a head panel and the icon it leads with.
const HEAD_PAD := 4
const ICON := 16
## Pixels one pad press scrolls the table.
const SCROLL_STEP := 24
## Border widths of a head: the side the selection is on, and the other one.
const BORDER_SELECTED := 3
const BORDER_IDLE := 1
## Alpha of the stripe every other row sits on, so a long table reads as rows rather than as
## a column of numbers that has lost its labels.
const STRIPE_ALPHA := 0.35
## The width the table is laid out at inside an offer board (the dialog less its padding),
## and the height of the head block above it. Both are arithmetic rather than measurement:
## an autowrapped Label that has not been laid out yet reports the height it would need at
## *no* width, which is one line per word, so measuring the heads or a text row before the
## first layout charged the table for room it never spends.
const TABLE_WIDTH := 436.0
## Horizontal room a row spends on things other than its two value columns.
const ROW_CHROME := LABEL_WIDTH + MARK_WIDTH + UiTheme.GAP_WIDE * 3.0 + UiTheme.GAP * 2.0

## The two heads, for the board to style as the selection.
var out_head: PanelContainer
var in_head: PanelContainer
## Whether the left side is the one the selection is on (it is, whenever the view is up).
var selected: bool = true

var _outgoing: Variant = null
var _incoming: Variant = null
var _rows: Array[Dictionary] = []
var _heads: HBoxContainer
var _out_caption: Label
var _in_caption: Label
var _scroll: ScrollContainer
var _table: VBoxContainer
var _footer: Label
var _note: Label
var _row_panels: Array[PanelContainer] = []
var _compact: bool = false
var _max_height: float = 0.0


func _ready() -> void:
	add_theme_constant_override(&"separation", UiTheme.GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: _restyle())


## Rebuilds the table for taking `incoming` in place of `outgoing`. `index` and `count` say
## which of several candidates is on the left; `max_height` is the room the whole view has,
## which decides the compact step and whether the table scrolls. `note` is a warning printed
## under the heads (a cursed prize's curse), empty for a plain trade.
func build(
	outgoing: Variant,
	incoming: Variant,
	index: int,
	count: int,
	max_height: float,
	note: String = ""
) -> void:
	_clear()
	_outgoing = outgoing
	_incoming = incoming
	_max_height = max_height
	_rows = CompareRows.rows_for(outgoing, incoming)
	_heads = HBoxContainer.new()
	_heads.add_theme_constant_override(&"separation", UiTheme.GAP_WIDE)
	_heads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heads)
	_out_caption = _caption(OUT_CAPTION)
	out_head = _head(outgoing)
	_heads.add_child(_column(_out_caption, out_head))
	_heads.add_child(_arrow())
	_in_caption = _caption(in_caption_for(outgoing, incoming))
	in_head = _head(incoming)
	_heads.add_child(_column(_in_caption, in_head))
	if not note.is_empty():
		_note = Label.new()
		_note.theme_type_variation = &"Danger"
		_note.text = note
		_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_note)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	_table = VBoxContainer.new()
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.add_theme_constant_override(&"separation", ROW_GAP)
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_table)
	var stripe := false
	for row: Dictionary in _rows:
		var panel := _row(row, stripe)
		_table.add_child(panel)
		_row_panels.append(panel)
		if StringName(str(row["kind"])) != CompareRows.KIND_HEADING:
			stripe = not stripe
	_footer = Label.new()
	_footer.theme_type_variation = &"Dim"
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.text = footer_text(index, count)
	_footer.visible = not _footer.text.is_empty()
	add_child(_footer)
	_fit()
	_restyle()


## Spends the room the view has: the table gets whatever the heads and the footer leave, the
## row gap closes when that is not enough, and the frame scrolls when it still is not.
func _fit() -> void:
	_compact = false
	_table.add_theme_constant_override(&"separation", ROW_GAP)
	var room := _table_room()
	if room <= 0.0:
		return
	if table_height(ROW_GAP) > room:
		_compact = true
		_table.add_theme_constant_override(&"separation", COMPACT_GAP)
	_scroll.custom_minimum_size.y = minf(room, table_height(_gap()))


## Pixels the table may take: the view's budget less the heads, the note, the footer and the
## gaps between them.
func _table_room() -> float:
	if _max_height <= 0.0:
		return 0.0
	var line := line_height()
	var used := heads_height() + UiTheme.GAP
	if _note != null:
		var lines := CardFit.wrapped_lines(_note.text, UiTheme.body_font(), TABLE_WIDTH)
		used += float(lines) * line + UiTheme.GAP
	if _footer.visible:
		used += line + UiTheme.GAP
	return _max_height - used


## Height of one body line as a Label draws it (the font's own height, no leading).
static func line_height() -> float:
	return maxf(1.0, UiTheme.body_font().get_height(UiTheme.SIZE_S))


## Height of the head block: a caption line, the gap under it, and a head holding a two-line
## title over a kind line inside its padding.
static func heads_height() -> float:
	var heading := maxf(1.0, UiTheme.heading_font().get_height(UiTheme.SIZE_S))
	return line_height() * 2.0 + UiTheme.GAP_TIGHT + HEAD_PAD * 2.0 + heading * 2.0


## Height the table draws at with `gap` px between rows: one line per stat or heading row,
## the wrapped height of the longer side of a text row, plus the gaps.
func table_height(gap: int) -> float:
	var line := line_height()
	var column := (TABLE_WIDTH - ROW_CHROME) * 0.5
	var font := UiTheme.body_font()
	var total := 0.0
	for row: Dictionary in _rows:
		var kind := StringName(str(row["kind"]))
		if kind == CompareRows.KIND_TEXT:
			var lines := maxi(
				CardFit.wrapped_lines(str(row["old"]), font, column),
				CardFit.wrapped_lines(str(row["new"]), font, column)
			)
			total += float(lines) * line
		else:
			total += line
	if not _rows.is_empty():
		total += float(gap) * float(_rows.size() - 1)
	return total


func _gap() -> int:
	return COMPACT_GAP if _compact else ROW_GAP


## True when the table is taller than its frame and scrolls.
func is_scrollable() -> bool:
	if _scroll == null or _table == null:
		return false
	return table_height(_gap()) > _scroll.custom_minimum_size.y + 0.5


## True when the row gap was closed to fit.
func is_compact() -> bool:
	return _compact


## Scrolls the table by `steps` presses (negative is up). Returns the new offset.
func scroll_by(steps: int) -> int:
	if _scroll == null:
		return 0
	var limit := maxi(0, int(table_height(_gap()) - _scroll.custom_minimum_size.y))
	_scroll.scroll_vertical = clampi(_scroll.scroll_vertical + steps * SCROLL_STEP, 0, limit)
	return _scroll.scroll_vertical


## The rows the table shows, in order (the model, not the nodes).
func rows() -> Array[Dictionary]:
	return _rows


## Every row spelled out as "label  old -> new", for tests and the plain-text rendering.
func row_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for row: Dictionary in _rows:
		if StringName(str(row["kind"])) == CompareRows.KIND_HEADING:
			out.append(str(row["label"]))
		else:
			out.append("%s  %s %s %s" % [row["label"], row["old"], ItemCard.SWAP_ARROW, row["new"]])
	return out


## Title of the thing on the left / right, as the head prints it.
func out_title() -> String:
	return title_for(_outgoing)


func in_title() -> String:
	return title_for(_incoming)


## Captions as drawn (tests read them rather than the node path).
func out_caption() -> String:
	return "" if _out_caption == null else _out_caption.text


func in_caption() -> String:
	return "" if _in_caption == null else _in_caption.text


## The warning under the heads, or "" when the trade carries none.
func note() -> String:
	return "" if _note == null else _note.text


## Current caption under the table.
func footer() -> String:
	return "" if _footer == null else _footer.text


## The line under the pair: which of several candidates is on the left. Silent when the offer
## can only displace one thing - a caption counting to one is noise, and the dialog hint
## already says which buttons turn the page.
static func footer_text(index: int, count: int) -> String:
	if count <= 1:
		return ""
	return "Slot %d of %d" % [clampi(index + 1, 1, count), count]


## Caption over the right-hand head. "goes on" is a promise about the slot being emptied, so
## it is only made when the incoming thing is the same kind as the outgoing one.
static func in_caption_for(outgoing: Variant, incoming: Variant) -> String:
	var both_abilities := outgoing is Ability and incoming is Ability
	var both_items := outgoing is ItemInstance and incoming is ItemInstance
	return IN_CAPTION if both_abilities or both_items else TAKE_CAPTION


## What the swap view says it is asking. It states the *reason* the question exists - the slot
## is already taken - because "Replace which?" told a player nothing they did not already
## resent. Gear names its own slot ("Your weapon slot is full"), which is the fact a player
## picking up a sword they did not mean to take needs before they press the button.
static func subtitle_for(options: Array) -> String:
	var kind := "slot"
	if not options.is_empty():
		var first: Variant = options[0]
		if first is ItemInstance:
			kind = item_slot_name(first as ItemInstance)
		elif first is Ability:
			kind = "passive" if first is PassiveAbility else "active"
	if options.size() <= 1:
		return "Your %s slot is full" % kind
	return "Your %s slots are full - which one goes?" % kind


## The dialog's footer while the swap view is up. It names the way out as well as the way
## through: the old one said "or cancel" without saying what cancels, which on a gamepad is
## not a guess worth making.
##
## `cancels_trade` is the price step of a two-question board, where the back key is no longer
## an offer to keep your own thing: the offer's slot has already been answered and backing out
## there drops the whole trade, prize included. `scrolls` adds the up/down pair when the table
## is taller than its frame. `UiPrompt` markup: the buttons are drawn for the live device, so
## `pad` only decides whether the line names the stick as well as the cross.
static func hint_text(
	pad: bool, options: int, cancels_trade: bool = false, scrolls: bool = false
) -> String:
	var move := "{#dpad}{#lstick}" if pad else "{ui_left}{ui_right}"
	var back := "{ui_cancel} %s" % (CANCEL_ALL_VERB if cancels_trade else KEEP_VERB)
	var parts: PackedStringArray = []
	if options > 1:
		parts.append("%s choose" % move)
	if scrolls:
		parts.append("{ui_up}{ui_down} scroll")
	parts.append("{ui_accept} swap")
	parts.append(back)
	return "   ".join(parts)


## The slot an item occupies, in the words the subtitle says it in ("weapon", "ring").
static func item_slot_name(item: ItemInstance) -> String:
	if item == null or item.base == null:
		return "gear"
	return String(item.base.slot_name())


## Name a head prints for a thing: the item's rolled name, the ability's name with its tier.
static func title_for(thing: Variant) -> String:
	if thing is ItemInstance:
		return (thing as ItemInstance).display_name
	if thing is Ability:
		var ability := thing as Ability
		if ability.tier > 1:
			return "%s %s" % [ability.display_name, AbilityCard.tier_numeral(ability.tier)]
		return ability.display_name
	return "Empty"


## Second line of a head: "Epic ring", "Active - 6s cooldown", "Passive".
static func subtitle_text(thing: Variant) -> String:
	if thing is ItemInstance:
		var item := thing as ItemInstance
		var pips := Accessibility.rarity_mark(item.rarity)
		var text := (
			"%s %s"
			% [ItemInstance.RARITY_NAMES[item.rarity], String(item.base.slot_name()).capitalize()]
		)
		return text if pips.is_empty() else "%s %s" % [pips, text]
	if thing is ActiveAbility:
		return "Active - %ss cooldown" % ItemCard.num((thing as ActiveAbility).cooldown)
	if thing is Ability:
		return "Passive"
	return "Nothing worn"


## Palette role a head is bordered and titled in: rarity for gear, kind colour for abilities.
static func role_for(thing: Variant) -> StringName:
	if thing is ItemInstance:
		return (thing as ItemInstance).rarity_role()
	if thing is PassiveAbility:
		return &"magic"
	if thing is Ability:
		return &"accent"
	return &"text_dim"


## Picture a head leads with: the item's own sprite, the ability's icon.
static func icon_for(thing: Variant) -> Texture2D:
	if thing is ItemInstance:
		return ProcSprite.for_item(thing as ItemInstance)
	if thing is Ability:
		return UiTheme.icon_for(thing as Ability)
	return null


# ------------------------------------------------------------------ building


func _column(caption: Label, head: PanelContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", UiTheme.GAP_TIGHT)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(caption)
	column.add_child(head)
	return column


func _caption(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _arrow() -> Label:
	var arrow := Label.new()
	arrow.theme_type_variation = &"Heading"
	arrow.text = ItemCard.SWAP_ARROW
	arrow.size_flags_vertical = Control.SIZE_SHRINK_END
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return arrow


## One head: icon, name in its rarity colour, kind line under it.
func _head(thing: Variant) -> PanelContainer:
	var head := PanelContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.set_content_margin_all(HEAD_PAD)
	style.set_border_width_all(BORDER_IDLE)
	head.add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", UiTheme.GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = icon_for(thing)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	if thing is ItemInstance:
		var badge := ShapeBadge.new()
		badge.shape = Accessibility.rarity_shape((thing as ItemInstance).rarity)
		badge.role = role_for(thing)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -float(ShapeBadge.SIZE)
		badge.offset_top = -float(ShapeBadge.SIZE)
		icon.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", UiTheme.GAP_NONE)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(titles)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"Heading"
	title.text = title_for(thing)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CardFit.drop_leading(title)
	CardFit.fit_title(title, LABEL_WIDTH + VALUE_WIDTH * 0.5)
	titles.add_child(title)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.theme_type_variation = &"Dim"
	subtitle.text = subtitle_text(thing)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(subtitle)
	return head


## One row of the table: the label, the two values and the direction mark; or a heading.
func _row(row: Dictionary, stripe: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.set_content_margin_all(0)
	style.content_margin_left = UiTheme.GAP
	style.content_margin_right = UiTheme.GAP
	panel.add_theme_stylebox_override(&"panel", style)
	panel.set_meta(&"stripe", stripe)
	panel.set_meta(&"row", row)
	var kind := StringName(str(row["kind"]))
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", UiTheme.GAP_WIDE)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
	var label := Label.new()
	label.name = "RowLabel"
	label.text = str(row["label"])
	label.custom_minimum_size.x = LABEL_WIDTH
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CardFit.drop_leading(label)
	line.add_child(label)
	if kind == CompareRows.KIND_HEADING:
		label.theme_type_variation = &"Dim"
		label.text = str(row["label"]).to_upper()
		panel.set_meta(&"stripe", false)
		return panel
	var old := _value(str(row["old"]), kind, false, StringName(str(row["role"])))
	old.name = "Old"
	line.add_child(old)
	var new := _value(str(row["new"]), kind, true, StringName(str(row["role"])))
	new.name = "New"
	line.add_child(new)
	var mark := DeltaMark.new()
	mark.role = StringName(str(row["role"]))
	mark.custom_minimum_size = Vector2(MARK_WIDTH, UiTheme.SIZE_S)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(mark)
	return panel


## One value cell. The new side is coloured by the row's direction; the old side is plain,
## because it is the number the player already lives with. A side that is absent is dim on
## both.
func _value(text: String, kind: StringName, is_new: bool, role: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = VALUE_WIDTH
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# Every value cell expands the same way whatever its row holds, so the direction marks at
	# the end of a stat row and of a wrapped sentence land on the same column.
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if kind == CompareRows.KIND_TEXT:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		CardFit.drop_leading(label)
	if text == CompareRows.ABSENT:
		label.theme_type_variation = &"Dim"
	elif is_new:
		label.theme_type_variation = variation_for(role)
	else:
		label.theme_type_variation = &"Bright" if role == CompareRows.ROLE_SAME else &""
	return label


## Label variation for a direction role.
static func variation_for(role: StringName) -> StringName:
	match role:
		CompareRows.ROLE_UP:
			return &"Heal"
		CompareRows.ROLE_DOWN:
			return &"Danger"
		CompareRows.ROLE_SAME:
			return &"Bright"
	return &""


## Colours every stylebox from the live palette; called on build and on every retint.
func _restyle() -> void:
	if out_head == null or in_head == null:
		return
	_style_head(out_head, _outgoing, selected)
	_style_head(in_head, _incoming, not selected)
	var stripe := UiTheme.color(&"floor_alt")
	stripe.a = STRIPE_ALPHA
	for panel: PanelContainer in _row_panels:
		var style := panel.get_theme_stylebox(&"panel") as StyleBoxFlat
		if style == null:
			continue
		style.bg_color = stripe if bool(panel.get_meta(&"stripe", false)) else Color.TRANSPARENT


func _style_head(head: PanelContainer, thing: Variant, is_selected: bool) -> void:
	var style := head.get_theme_stylebox(&"panel") as StyleBoxFlat
	if style == null:
		return
	var role := role_for(thing)
	var base := UiTheme.color(&"floor_alt")
	style.bg_color = CardFit.selected_fill(base, UiTheme.color(&"select")) if is_selected else base
	style.border_color = UiTheme.color(role) if is_selected else UiTheme.color(role).darkened(0.25)
	style.set_border_width_all(BORDER_SELECTED if is_selected else BORDER_IDLE)
	var title := head.find_child("Title", true, false) as Label
	if title != null:
		title.add_theme_color_override(&"font_color", UiTheme.text_color(role))


## Marks which side the selection is on. The left is the half the player is choosing between
## candidates on; the right is the offer, which is never in doubt.
func set_selected(on_left: bool) -> void:
	selected = on_left
	_restyle()


func _clear() -> void:
	out_head = null
	in_head = null
	_heads = null
	_scroll = null
	_table = null
	_footer = null
	_note = null
	_out_caption = null
	_in_caption = null
	_row_panels.clear()
	_rows = []
	for child in get_children():
		remove_child(child)
		child.queue_free()


## The direction mark at the end of a row: a triangle up for better, down for worse, a dash
## for the same. A second channel beside the colour, so a row reads on a palette whose
## green and red are two greys (`white`) and with colour-blind glyphs on.
class DeltaMark:
	extends Control
	var role: StringName = CompareRows.ROLE_SAME:
		set(value):
			role = value
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: queue_redraw())

	func _draw() -> void:
		var color := (
			UiTheme.text_color(role)
			if role != CompareRows.ROLE_SAME
			else UiTheme.color(&"text_dim")
		)
		if role == CompareRows.ROLE_DIM:
			return
		var w := size.x
		var h := size.y
		var cx := floorf(w * 0.5)
		var cy := floorf(h * 0.5)
		if role == CompareRows.ROLE_UP:
			draw_colored_polygon(
				PackedVector2Array(
					[Vector2(cx - 3, cy + 2), Vector2(cx + 3, cy + 2), Vector2(cx, cy - 2)]
				),
				color
			)
		elif role == CompareRows.ROLE_DOWN:
			draw_colored_polygon(
				PackedVector2Array(
					[Vector2(cx - 3, cy - 2), Vector2(cx + 3, cy - 2), Vector2(cx, cy + 2)]
				),
				color
			)
		else:
			draw_rect(Rect2(cx - 3, cy, 6, 1), color)
