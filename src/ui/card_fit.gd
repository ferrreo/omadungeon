## How much text fits in a card, and what to do with the rest.
##
## Split out of `ChestUi` because these are the rules the offer board, the swap view and the
## shop counter all lay out by, and because none of them needs a node: they are arithmetic
## over a font, a width and a list of rows. Keeping them here means a change to "what fits"
## is one file, and that `ChestUi` stays under the file-length limit while the cards it draws
## grow the comparison blocks they were previously cutting short.
##
## The one rule worth stating up front: **nothing is cut to a row count**. A card is grown to
## its content first (`ChestUi.card_height_for`) and then filled to the pixels it actually got
## (`fit_rows`). Every fixed cap this file replaced - eight description lines, four stat
## deltas, six before/after rows - cut the list while there was still room on the card.
class_name CardFit
extends RefCounted

## Padding a card keeps between its border and its content, on every side. It is also the
## content margin of the card's own stylebox (`ChestUi._card_style`), so the width these
## measurements wrap text to is the width the labels are really drawn at: they used to differ
## by two pixels, and every row the estimate wrapped one line early was a line of the
## comparison spent on nothing.
const CARD_PAD := 5
## Width of the icon column left of a card title.
const ICON_COLUMN := 20
## Titles wrap to at most this many lines; longer ones drop to the narrower body font.
const TITLE_LINES := 2
## Body rows a card keeps even when its head block has to grow for a long name.
const MIN_BODY_LINES := 3
## Height of the rule line between two blocks of a card (an `HSeparator`).
const RULE_HEIGHT := 4.0
## Line-break flags a Label in `AUTOWRAP_WORD_SMART` uses, so a measurement of how many lines
## a string needs is the number the Label will actually draw.
const WRAP_FLAGS := (
	TextServer.BREAK_MANDATORY
	| TextServer.BREAK_WORD_BOUND
	| TextServer.BREAK_ADAPTIVE
	| TextServer.BREAK_TRIM_EDGE_SPACES
)
## Contrast the selected card's fill keeps against an unselected one. Small on purpose - the
## card is a surface, not a highlight - but never zero, which is what a `lerp` toward a
## `select` role that a light theme puts next to `floor_alt` collapses to.
const SELECTED_FILL_RATIO := 1.15


## Lines `text` wraps to in a body label `width` pixels wide (at least 1).
static func wrap_lines(text: String, width: float) -> int:
	return wrapped_lines(text, UiTheme.body_font(), width)


## Spends `capacity` wrapped text lines on `rows` (each `{text, role}`), in order: every row
## takes the lines `wrap_lines_for` says its text needs. Rows that no longer fit are dropped
## and added to `already_hidden`; whenever anything is hidden one line is reserved for the
## caller's "+N more" row.
##
## The row the budget runs out on is **truncated to the lines that are left** rather than
## dropped whole, which is what stops a card printing "+1 more" over blank space: a two-line
## row meeting one free line used to be dropped and its line left empty, and an offer board
## measured 1.6 body lines of daylight under the last row of a card that was hiding one. The
## label wearing the short budget draws what fits with an ellipsis, so the cut is visible and
## the rows stay in order - skipping ahead to a shorter row further down would reorder a
## comparison to save a line.
## Returns `{"rows": Array[Dictionary] (each with a "lines" budget), "hidden": int}`.
static func fit_rows(
	rows: Array[Dictionary], capacity: int, already_hidden: int, wrap_lines_for: Callable
) -> Dictionary:
	var empty: Array[Dictionary] = []
	if capacity <= 0:
		return {"rows": empty, "hidden": already_hidden + rows.size()}
	var out: Array[Dictionary] = []
	for reserve: int in [1 if already_hidden > 0 else 0, 1]:
		out = []
		var left := capacity - reserve
		var dropped := 0
		for i in range(rows.size()):
			var want := lines_for(rows[i], wrap_lines_for)
			if want <= left:
				var row: Dictionary = rows[i].duplicate()
				row["lines"] = want
				out.append(row)
				left -= want
				continue
			if left > 0:
				var row: Dictionary = rows[i].duplicate()
				row["lines"] = left
				out.append(row)
				left = 0
				dropped = rows.size() - i - 1
				break
			dropped = rows.size() - i
			break
		var hidden := already_hidden + dropped
		if hidden == 0 or reserve == 1:
			return {"rows": out, "hidden": hidden}
	return {"rows": out, "hidden": already_hidden}


## How many of `rows` draw as a separator rather than as text.
static func rule_rows(rows: Array[Dictionary]) -> int:
	var count := 0
	for row: Dictionary in rows:
		if StringName(str(row.get("role", &""))) == &"rule":
			count += 1
	return count


## Lines one row costs the budget. A `rule` row draws as a 4 px `HSeparator`, not as a line of
## text, so charging it a whole line spent a row of the trade on a hairline.
static func lines_for(row: Dictionary, wrap_lines_for: Callable) -> int:
	if StringName(str(row.get("role", &""))) == &"rule":
		return 0
	return maxi(1, int(wrap_lines_for.call(str(row["text"]))))


## Body lines that fit in `space` pixels once the hairlines in `rows` are paid for.
##
## `space` is the caller's arithmetic, not a measurement of the card: the head block holds two
## autowrapped Labels, and a Label that has not been laid out yet reports the minimum height it
## would need at *no* width, which is taller than what it draws. Measuring the box before the
## body went in therefore charged the body a line and a half it had not spent, and the card cut
## a row it had the room for.
static func body_capacity(space: float, line_h: float, rows: Array[Dictionary]) -> int:
	var left := space - float(rule_rows(rows)) * RULE_HEIGHT
	return maxi(0, int(floorf(left / maxf(1.0, line_h))))


## Draws `label`'s own wrapped lines exactly one font height apart, which is the distance two
## rows of a card already sit at (the body box runs at separation zero).
##
## Every measurement on a card counts in font heights: the height the card asks for, the line
## budget its body is filled to, the head block the title and subtitle have to fit inside. The
## theme's leading is not in any of them, so a wrapped row cost three pixels a line more than
## it was charged - enough for a two-line title to push the head block past the height reserved
## for it and clip the last row of the body off the bottom of the card.
static func drop_leading(label: Label) -> void:
	label.add_theme_constant_override(&"line_spacing", 0)


## Height of one body line, measured with a probe label so the box's own separation and the
## theme's label metrics are in it rather than assumed.
static func body_line_height(box: VBoxContainer) -> float:
	var used := box.get_combined_minimum_size().y
	var probe := Label.new()
	probe.text = "0"
	box.add_child(probe)
	var with_one := box.get_combined_minimum_size().y
	box.remove_child(probe)
	probe.queue_free()
	return maxf(1.0, with_one - used)


## Pixels a `fit_rows` result draws as: one `line_h` per granted line, the hairline every rule
## row draws instead of text, and the "+N more" row when anything is still hidden.
##
## This is what lets a caller spend a *pixel* budget with a function that counts in lines:
## `fit_rows` reserves a line for "+N more" and the row it cuts may not be able to use every
## line it is offered, so the line budget it was given can come back partly unspent - which on
## the card is empty space under an ellipsis.
static func body_height(fitted: Dictionary, line_h: float) -> float:
	var rows: Array[Dictionary] = fitted["rows"]
	var lines := 0
	for row: Dictionary in rows:
		lines += int(row.get("lines", 0))
	if int(fitted["hidden"]) > 0:
		lines += 1
	return float(lines) * line_h + float(rule_rows(rows)) * RULE_HEIGHT


## Lines `text` wraps to in `font` at `width` (at least 1), broken the way the Labels on a card
## break it: `AUTOWRAP_WORD_SMART` trims the spaces at a wrap and breaks adaptively, and the
## default flags of `get_multiline_string_size` do neither - so a measurement taken without
## them could count a line the card never draws, and spend the card's budget on it.
static func wrapped_lines(text: String, font: Font, width: float) -> int:
	var line_h := maxf(1.0, font.get_height(UiTheme.SIZE_S))
	var total := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, width, UiTheme.SIZE_S, -1, WRAP_FLAGS
	)
	return maxi(1, int(roundf(total.y / line_h)))


## Fill of the card the selection is on: `base` (the plain card) pushed toward the theme's
## `select`, and then pushed further when that theme leaves the two on top of each other.
## The direction comes from the card itself - a bright card darkens, a dark card lightens -
## so the rule holds on a palette nobody has looked at, and needs no live desktop to decide.
static func selected_fill(base: Color, select: Color) -> Color:
	var fill := base.lerp(select, 0.6)
	if ThemePalette.contrast_ratio(fill, base) >= SELECTED_FILL_RATIO:
		return fill
	var lum := ThemePalette.relative_luminance(base)
	var target := (
		(lum + 0.05) / SELECTED_FILL_RATIO - 0.05
		if lum > 0.5
		else (lum + 0.05) * SELECTED_FILL_RATIO - 0.05
	)
	return ThemePalette.with_luminance(fill, clampf(target, 0.0, 1.0))


## Width a card title may occupy before it wraps, on a card `card_w` wide.
static func title_width(card_w: float) -> float:
	return card_w - CARD_PAD * 2.0 - ICON_COLUMN


## Height reserved for the icon/title/subtitle block, so every card's rule line matches.
static func head_height() -> float:
	var heading := UiTheme.heading_font()
	var body := UiTheme.body_font()
	return heading.get_height(UiTheme.SIZE_S) * TITLE_LINES + body.get_height(UiTheme.SIZE_S)


## Height a whole row of cards shares: enough for the tallest card's rows, so a Legendary's
## affixes are not hidden behind "+N more" on the one card whose affixes are the point of it.
## Never below `floor_h` (a gold chest would look like a label) nor above `cap`.
##
## The rules are paid for in pixels here and charged nothing by `fit_rows`: a card carries the
## one under its head block plus one per block boundary in its rows. Counting only the first
## left a card with a comparison four pixels short of its own content, which is a whole row of
## that comparison when the arithmetic is exact to the line.
static func card_height_for(
	infos: Array[Dictionary], card_w: float, head_h: float, floor_h: float, cap: float
) -> float:
	var body := UiTheme.body_font()
	var line_h := maxf(1.0, body.get_height(UiTheme.SIZE_S))
	var width := maxf(1.0, card_w - CARD_PAD * 2.0)
	var want := floor_h
	for info: Dictionary in infos:
		var rows: Array[Dictionary] = info["rows"]
		var lines := 0.0
		for row: Dictionary in rows:
			lines += float(wrapped_lines(str(row["text"]), body, width))
		if int(info["hidden"]) > 0:
			lines += 1.0
		var rules := float(1 + rule_rows(rows)) * RULE_HEIGHT
		want = maxf(want, head_h + rules + lines * line_h + CARD_PAD * 2.0)
	return minf(want, cap)


## Head height a whole row of cards shares: tall enough for the longest name plus its full
## subtitle, so the rule lines still align and no subtitle loses letters on a four-card
## layout. Capped so every card keeps `MIN_BODY_LINES` rows of description.
static func head_height_for(infos: Array[Dictionary], card_w: float, cap: float) -> float:
	var body := UiTheme.body_font()
	var bh := body.get_height(UiTheme.SIZE_S)
	var width := title_width(card_w)
	var want := head_height()
	for info: Dictionary in infos:
		var font := title_font(str(info["title"]), card_w)
		var title_h := (
			font.get_height(UiTheme.SIZE_S)
			* mini(TITLE_LINES, wrapped_lines(str(info["title"]), font, width))
		)
		want = maxf(want, title_h + bh * wrapped_lines(str(info["subtitle"]), body, width))
	return minf(want, cap - CARD_PAD * 2.0 - MIN_BODY_LINES * bh - RULE_HEIGHT)


## Font a card title is drawn in: the heading font, or the narrower body font when the
## heading cannot fit the name in `TITLE_LINES` lines (or a single word is wider than a card).
static func title_font(text: String, card_w: float) -> Font:
	var heading := UiTheme.heading_font()
	var width := title_width(card_w)
	if wrapped_lines(text, heading, width) > TITLE_LINES:
		return UiTheme.body_font()
	for word: String in text.split(" ", false):
		if heading.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S).x > width:
			return UiTheme.body_font()
	return heading


## Drops a title to the narrower body font when the heading font cannot fit it in
## `TITLE_LINES` lines (or when a single word is wider than the card).
static func fit_title(label: Label, card_w: float) -> void:
	var font := title_font(label.text, card_w)
	if font != UiTheme.heading_font():
		label.add_theme_font_override(&"font", font)


## Body lines the subtitle may use: whatever the (already fitted) title leaves of the head
## block. A one-line title buys the subtitle a second line; a two-line one leaves it one.
static func subtitle_lines(title: Label, head_h: float, card_w: float) -> int:
	var body := UiTheme.body_font()
	# `fit_title` marks a title it had to shrink with a font override; the card is not in the
	# tree yet, so the theme cannot be asked.
	var font := body if title.has_theme_font_override(&"font") else UiTheme.heading_font()
	var used := (
		font.get_height(UiTheme.SIZE_S) * wrapped_lines(title.text, font, title_width(card_w))
	)
	return maxi(1, int(floorf((head_h - used) / maxf(1.0, body.get_height(UiTheme.SIZE_S)))))
