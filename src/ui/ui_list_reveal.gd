## Scrolls a focus-navigated list so the focused row lands somewhere a player can read it.
##
## `ScrollContainer.follow_focus` does half the job: it brings the focused control just inside
## the viewport and stops, flush against the edge. On a sectioned page - Settings is the one
## here - that leaves the section heading above the row sliced in half by the top edge, so all
## that shows under the page header is the bare rule with the word gone. A verifier read that
## as the list being drawn clipped under its own header, and they were right to.
##
## So this replaces the flag. It brings the heading along with the row whenever the two still
## fit together, and when they cannot it pushes the heading fully out of sight rather than
## leaving half of it: a heading shows whole or not at all.
##
## Static, and driven from a `gui_focus_changed` handler, so any scrolled list can use it.
class_name UiListReveal
extends RefCounted

## Theme type variation that marks a row as a section heading.
const HEADING_VARIATION := &"Heading"


## Scrolls `control` into view inside `scroll`, with its section heading when both fit, and
## with no heading left sliced by the top edge. `list` is the container holding the rows.
## Returns the resulting scroll offset.
static func reveal(scroll: ScrollContainer, list: VBoxContainer, control: Control) -> int:
	if scroll == null or list == null or control == null:
		return 0
	var view := scroll.size.y
	if view <= 0.0:
		# Nothing has been laid out yet; scrolling against a zero-height viewport would run the
		# list to its end and leave it there.
		return scroll.scroll_vertical
	# Measured against the scroll viewport rather than the content, so any gutter the list is
	# inset by is already in the numbers.
	var top := offset_in(scroll, control)
	var bottom := top + control.size.y
	var heading := heading_above(list, control)
	if heading != null:
		var heading_top := offset_in(scroll, heading)
		if bottom - heading_top <= view:
			top = heading_top
	var delta := 0
	if top < 0.0:
		delta = int(floorf(top))
	elif bottom > view:
		delta = int(ceilf(bottom - view))
	# One write, because a `ScrollContainer` re-lays its children on its own deferred sort:
	# read a child's position straight back after moving the scroll and it is still the old one.
	scroll.scroll_vertical += delta + _heading_push(scroll, list, control, delta)
	return scroll.scroll_vertical


## How far `control` sits below the top of `scroll`'s viewport, in the scroll's own units.
##
## Through the inverse transform rather than as a difference of `global_position`, so a screen
## that is mid-animation still measures correctly: the pause menu scales its panel as it opens,
## and a difference of scaled global pixels compared against an unscaled `size` is not a
## distance in either space.
static func offset_in(scroll: ScrollContainer, control: Control) -> float:
	return (scroll.get_global_transform().affine_inverse() * control.global_position).y


## The section heading above `control`, or null when it sits before the first one. Walks the
## list children backwards from the row `control` lives in, so it works for every row shape a
## page builds without any bookkeeping at build time.
static func heading_above(list: VBoxContainer, control: Control) -> Label:
	var row: Node = control
	while row != null and row.get_parent() != list:
		row = row.get_parent()
	if row == null:
		return null
	for i in range(row.get_index() - 1, -1, -1):
		var label := list.get_child(i) as Label
		if label != null and label.theme_type_variation == HEADING_VARIATION:
			return label
	return null


## Extra scroll, on top of `delta`, needed so no heading is left sliced by the top edge. A
## heading is a label and the rule under it; cut between the two, a player sees a bare rule
## hanging under the page header and nothing naming the section.
static func _heading_push(
	scroll: ScrollContainer, list: VBoxContainer, keep: Control, delta: int
) -> int:
	var count := list.get_child_count()
	for i in count:
		var label := list.get_child(i) as Label
		if label == null or label.theme_type_variation != HEADING_VARIATION:
			continue
		var block_top := offset_in(scroll, label) - float(delta)
		var block_bottom := block_top + label.size.y
		if i + 1 < count:
			var rule := list.get_child(i + 1) as HSeparator
			if rule != null:
				block_bottom = offset_in(scroll, rule) + rule.size.y - float(delta)
		if block_top >= 0.0 or block_bottom <= 0.0:
			continue
		var push := int(ceilf(block_bottom))
		if offset_in(scroll, keep) - float(delta) - float(push) >= 0.0:
			return push
		return 0
	return 0
