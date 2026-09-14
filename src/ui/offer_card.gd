## The card factory behind an offer board: builds one card from a `ChestUi.describe_offer`
## description, fills its body to the pixels it really has, and recolours it in place.
##
## Split out of `ChestUi` so the board stays under the file-length limit now that the swap
## step has a screen of its own (`CompareView`), and because a card is arithmetic over a
## description, a width and a height - none of it needs the board's state. `CardFit` is the
## arithmetic; this is the nodes.
class_name OfferCard
extends RefCounted

## Border thickness of the card the selection is on, and of every other card. Focus was one
## shade step of one hue: on catppuccin-latte the two borders measured 1.67:1 apart and the
## two fills 3/255 apart, so "which card am I on" was not answerable at a glance on paper.
## Thickness is a second channel that does not depend on the theme having a spare hue.
const BORDER_SELECTED := 3
const BORDER_IDLE := 1
## How many times the body fill may raise its line budget to spend the pixels a card has left.
## Four is well past what any measured card needed: the loop stops the moment one more line
## would not fit, so this only bounds a pathological row list.
const REFIT_PASSES := 4
## Meta key the description waits under until the card is in the tree and can be filled.
const INFO_META := &"info"
## The tail row when the cut lands inside the comparison block. "+N more" was the owner's
## complaint: a count of rows hidden is not a comparison. The full table is one press away
## (an offer that displaces something opens `CompareView` before it is taken), so the tail
## says that instead of counting what it hid.
const COMPARE_TAIL := "Pick to compare every row"


## Builds one card `card_w` by `card_h` for `info` (see `ChestUi.describe_offer`), headed by
## a block `head_h` tall so every card's rule line matches. `role` colours the title and the
## badge; `price` (empty for a free offer) is printed as its own row in `price_role`.
## The body is filled by `fill_body` once the card is in the tree, where the labels know
## their font and the exact number of rows that still fit can be measured.
static func make(
	info: Dictionary,
	role: StringName,
	card_w: float,
	card_h: float,
	head_h: float,
	price: String = "",
	price_role: StringName = &"loot"
) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, card_h)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.pivot_offset = card.custom_minimum_size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# Fixed size + clipping: no amount of affix text can push the buttons off-screen.
	card.clip_contents = true
	card.add_theme_stylebox_override("panel", style())
	# A plain Control does not propagate its children's minimum size, so the text block
	# inside can never make the card (or the dialog) grow; it is clipped instead.
	var frame := Control.new()
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := float(CardFit.CARD_PAD) * 2.0
	frame.custom_minimum_size = card.custom_minimum_size - Vector2(pad, pad)
	card.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.GAP_NONE)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.GAP)
	box.add_child(head)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = info["icon"] as Texture2D
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(icon)
	var badge := ShapeBadge.new()
	badge.shape = int(info.get("shape", -1))
	badge.role = role
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -float(ShapeBadge.SIZE)
	badge.offset_top = -float(ShapeBadge.SIZE)
	icon.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", UiTheme.GAP_NONE)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = str(info["title"])
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = CardFit.TITLE_LINES
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override("font_color", UiTheme.text_color(role))
	CardFit.drop_leading(title)
	CardFit.fit_title(title, card_w)
	titles.add_child(title)
	var subtitle := Label.new()
	subtitle.theme_type_variation = &"Dim"
	subtitle.text = str(info["subtitle"])
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	# "Common weapon" does not fit one line on a four-card layout: let it wrap into whatever
	# the title left of the head block, and mark the rest with an ellipsis rather than
	# dropping letters silently.
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	CardFit.drop_leading(subtitle)
	subtitle.max_lines_visible = CardFit.subtitle_lines(title, head_h, card_w)
	# A wrapped Label reports a one-line minimum, so the extra line has to be asked for.
	subtitle.custom_minimum_size.y = (
		subtitle.max_lines_visible * UiTheme.body_font().get_height(UiTheme.SIZE_S)
	)
	titles.add_child(subtitle)
	head.custom_minimum_size.y = head_h
	var sep := HSeparator.new()
	box.add_child(sep)
	if not price.is_empty():
		var spacer := Control.new()
		spacer.name = "Spacer"
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(spacer)
		var price_label := Label.new()
		price_label.theme_type_variation = &"Heading"
		price_label.text = price
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_label.add_theme_color_override("font_color", UiTheme.text_color(price_role))
		box.add_child(price_label)
	card.set_meta(INFO_META, info)
	return card


## Fills the body rows of a card that is already in the tree: the offer's own lines, then
## the comparison deltas, cut to what is left under the head block with a tail row
## (`tail_text`) when anything had to go.
## `head_h` is the height the head was built to.
static func fill_body(card: PanelContainer, head_h: float) -> void:
	if not card.has_meta(INFO_META):
		return
	var info: Dictionary = card.get_meta(INFO_META)
	card.remove_meta(INFO_META)
	var frame := card.get_child(0) as Control
	var box := frame.get_child(0) as VBoxContainer if frame != null else null
	if box == null:
		return
	var spacer := box.get_node_or_null(^"Spacer") as Control
	var insert_at := spacer.get_index() if spacer != null else box.get_child_count()
	var rows: Array[Dictionary] = info["rows"]
	# The rules between the blocks draw as hairlines rather than as text, so their pixels come
	# off the budget here and `fit_rows` charges them nothing: a 4 px separator used to cost a
	# whole row of the comparison.
	var dropped := int(info["hidden"])
	var body_width := maxf(1.0, frame.custom_minimum_size.x)
	var wrap := func(text: String) -> int: return CardFit.wrap_lines(text, body_width)
	var line_h := CardFit.body_line_height(box)
	# What is left under the head block and its rule (and the price row, when the counter put
	# one on the card). Taken from the geometry the card was built to rather than measured off
	# the box: the head is exactly `head_h` tall by construction, which is the number
	# `CardFit.card_height_for` reserved, while the box's own minimum before layout is the sum
	# of two autowrapped Labels at no width and is larger than either of them draws.
	var price_h := 0.0
	for i in range(insert_at, box.get_child_count()):
		price_h += (box.get_child(i) as Control).get_combined_minimum_size().y
	var space := frame.custom_minimum_size.y - head_h - CardFit.RULE_HEIGHT - price_h
	var capacity := CardFit.body_capacity(space, line_h, rows)
	var fitted := CardFit.fit_rows(rows, capacity, dropped, wrap)
	# The card is measured in pixels and filled in lines, and the two do not divide evenly: the
	# line `fit_rows` holds back for "+N more", and the lines the row it cuts cannot use, come
	# back as empty card under an ellipsis. So the budget is raised while the result still fits
	# the space the card really has - a card fills itself before it truncates anything.
	for _pass in range(REFIT_PASSES):
		var grown := CardFit.fit_rows(rows, capacity + 1, dropped, wrap)
		if CardFit.body_height(grown, line_h) > space:
			break
		capacity += 1
		fitted = grown
	var shown: Array[Dictionary] = fitted["rows"]
	var hidden: int = fitted["hidden"]
	if hidden > 0:
		shown.append({"text": tail_text(info, hidden), "role": &"dim", "lines": 1})
	for row: Dictionary in shown:
		var role_name := StringName(str(row["role"]))
		if role_name == &"rule":
			# The rule is what tells the two blocks apart; it is a row of its own so the
			# line budget above has already paid for it.
			var separator := HSeparator.new()
			separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(separator)
			box.move_child(separator, insert_at)
			insert_at += 1
			continue
		var label := Label.new()
		label.text = str(row["text"])
		# Descriptions are the point of the card: they wrap, and the row budget above is
		# measured in wrapped lines so the block still cannot overflow the card.
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		CardFit.drop_leading(label)
		label.max_lines_visible = maxi(1, int(row["lines"]))
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if role_name == &"heal":
			label.theme_type_variation = &"Heal"
		elif role_name == &"danger":
			label.theme_type_variation = &"Danger"
		elif role_name == &"dim":
			label.theme_type_variation = &"Dim"
		box.add_child(label)
		box.move_child(label, insert_at)
		insert_at += 1


## The tail row of a card that could not show everything. An offer that displaces something
## (`info["replaces"]` names it) never counts what it hid: every row, the offer's own included,
## is on the compare screen the pick opens, so the tail says where to look. Only an offer that
## displaces nothing - which has no comparison block, and whose own lines run past the tallest
## card the board can draw - still counts, and that is a description longer than any in the
## registry.
static func tail_text(info: Dictionary, hidden: int) -> String:
	if not str(info.get("replaces", "")).is_empty():
		return COMPARE_TAIL
	return "+%d more" % hidden


## One StyleBoxFlat per card, mutated in place by `restyle` (never re-allocated).
static func style() -> StyleBoxFlat:
	var out := StyleBoxFlat.new()
	out.bg_color = UiTheme.color(&"floor_alt")
	out.border_color = UiTheme.color(&"text_dim")
	out.set_border_width_all(BORDER_IDLE)
	out.set_content_margin_all(CardFit.CARD_PAD)
	return out


## Recolours one card in place for its `role` and whether it carries the selection. Only the
## stylebox's colours change here, so a retint does not allocate per frame.
static func restyle(card: PanelContainer, role: StringName, is_selected: bool) -> void:
	var box := card.get_theme_stylebox(&"panel") as StyleBoxFlat
	if box == null:
		return
	var base := UiTheme.color(&"floor_alt")
	box.bg_color = CardFit.selected_fill(base, UiTheme.color(&"select")) if is_selected else base
	box.border_color = UiTheme.color(role) if is_selected else UiTheme.color(role).darkened(0.35)
	# Three channels, not one: hue, fill and thickness all say the same thing, so the card
	# with focus is still obvious on a theme that has no bright accent to spare.
	box.set_border_width_all(BORDER_SELECTED if is_selected else BORDER_IDLE)


## The title Label of a card, for tests and the gallery.
static func title_label(card: PanelContainer) -> Label:
	var frame := card.get_child(0) as Control
	var box := frame.get_child(0) as VBoxContainer
	var head := box.get_child(0) as HBoxContainer
	var titles := head.get_child(1) as VBoxContainer
	return titles.get_child(0) as Label
