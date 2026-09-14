## The compare screen (owner report, round 5: "swap ui is still pretty ass", "'and 7 more' is
## not helpful when I am trying to see the difference between two items").
##
## Two promises. The model puts every number either side has on one row, both values on it,
## absent sides marked rather than dropped; and the view draws the whole model - it closes
## its row gap and then scrolls when it is taller than its frame, and never prints a count
## of rows it hid.
class_name CompareViewTest
extends GdUnitTestSuite

const SCENE := "res://src/ui/chest_ui.tscn"
## Trades rolled from the real item generator when measuring that nothing is ever cut.
const TRADE_SEEDS := 24
## Room a compare view has on an offer board.
const HEIGHT := ChestUi.COMPARE_HEIGHT
## Heights the board can hand the view, cramped first. 96 px is under the compact threshold, so
## the sweep below draws every generated trade scrolling as well as whole.
const HEIGHTS: Array[float] = [96.0, 140.0, HEIGHT, 400.0]


func after_test() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _view(outgoing: Variant, incoming: Variant, height: float = HEIGHT) -> CompareView:
	var view: CompareView = auto_free(CompareView.new())
	add_child(view)
	view.size = Vector2(436, height)
	view.build(outgoing, incoming, 0, 1, height)
	return view


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _row(rows: Array[Dictionary], label: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row["label"]) == label:
			return row
	return {}


# ------------------------------------------------------------------ the model


## Every stat either ring carries is a row, with the side that lacks it marked absent: losing
## the worn ring's Max HP is half of the trade, and the old card dropped the row.
func test_every_stat_of_both_sides_is_a_row_with_both_values() -> void:
	var worn := UiFakes.make_item(_rng(7), ItemInstance.Rarity.EPIC, ItemBase.Slot.RING)
	var offered := UiFakes.make_item(_rng(11), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.RING)
	var rows := CompareRows.stat_rows(CompareRows.rows_for(worn, offered))
	var labels: PackedStringArray = []
	for row: Dictionary in rows:
		labels.append(str(row["label"]))
	for item: ItemInstance in [worn, offered]:
		for total: Dictionary in ItemCard.stat_totals(item):
			var label := ItemCard.swap_label(StringName(str(total["stat"])))
			(
				assert_array(labels)
				. override_failure_message("%s has no row on the table" % label)
				. contains([label])
			)
	# A stat only one side has prints the other side as absent, never as a number.
	var absent := 0
	for row: Dictionary in rows:
		if str(row["old"]) == CompareRows.ABSENT or str(row["new"]) == CompareRows.ABSENT:
			absent += 1
	assert_int(absent).is_greater(0)
	# Nothing on the table is a delta: both sides are the item's own value.
	for row: Dictionary in rows:
		assert_str(str(row["old"])).not_contains(ItemCard.SWAP_ARROW)
		assert_str(str(row["new"])).not_contains(ItemCard.SWAP_ARROW)


## A row where nothing moves stays on the table, dimmed, rather than vanishing.
func test_rows_where_nothing_changes_are_kept_and_marked_same() -> void:
	var worn := UiFakes.make_item(_rng(5), ItemInstance.Rarity.RARE, ItemBase.Slot.WEAPON)
	var same := UiFakes.make_item(_rng(5), ItemInstance.Rarity.RARE, ItemBase.Slot.WEAPON)
	var rows := CompareRows.stat_rows(CompareRows.rows_for(worn, same))
	assert_int(rows.size()).is_greater(3)
	for row: Dictionary in rows:
		assert_that(StringName(str(row["role"]))).is_equal(CompareRows.ROLE_SAME)


## The weapon block is four rows on any trade that has a weapon on either side, and a ring
## against a ring has none.
func test_the_weapon_numbers_are_rows_only_when_a_weapon_is_involved() -> void:
	var sword := UiFakes.make_item(_rng(1), ItemInstance.Rarity.COMMON, ItemBase.Slot.WEAPON)
	var ring := UiFakes.make_item(_rng(2), ItemInstance.Rarity.COMMON, ItemBase.Slot.RING)
	var rows := CompareRows.rows_for(sword, sword)
	for label: String in CompareRows.WEAPON_LABELS:
		assert_bool(_row(rows, label).is_empty()).is_false()
	assert_bool(_row(CompareRows.rows_for(ring, ring), "Damage").is_empty()).is_true()
	# A sword against an empty hand: the old side is absent on every weapon row.
	var fresh := _row(CompareRows.rows_for(null, sword), "Damage")
	assert_str(str(fresh["old"])).is_equal(CompareRows.ABSENT)
	assert_that(StringName(str(fresh["role"]))).is_equal(CompareRows.ROLE_UP)


## A legendary's unique effect is printed in full on its side of the table.
func test_a_unique_effect_is_on_the_table_in_full() -> void:
	var worn := UiFakes.make_item(_rng(3), ItemInstance.Rarity.EPIC, ItemBase.Slot.RING)
	var legendary := UiFakes.make_item(_rng(4), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.RING)
	var unique := _row(CompareRows.rows_for(worn, legendary), CompareRows.UNIQUE_LABEL)
	assert_bool(unique.is_empty()).is_false()
	assert_that(StringName(str(unique["kind"]))).is_equal(CompareRows.KIND_TEXT)
	assert_str(str(unique["new"])).is_equal(CompareRows.unique_text(legendary))
	assert_str(str(unique["new"])).contains(UniqueEffects.find(legendary.unique_effect).description)
	assert_str(str(unique["old"])).is_equal(CompareRows.ABSENT)
	assert_that(StringName(str(unique["role"]))).is_equal(CompareRows.ROLE_UP)


## Abilities: kind, cooldown, damage, tier and both descriptions - and a longer cooldown is
## the one row where down is up.
func test_an_ability_trade_prints_its_numbers_and_both_descriptions() -> void:
	var quick := UiFakes.make_active("fireball", "Fireball", 6.0)
	var slow := UiFakes.make_active("whirlwind", "Whirlwind", 8.0)
	var rows := CompareRows.rows_for(quick, slow)
	assert_that(StringName(str(_row(rows, AbilityCard.COOLDOWN_LABEL)["role"]))).is_equal(
		CompareRows.ROLE_DOWN
	)
	assert_that(StringName(str(_row(rows, AbilityCard.DAMAGE_LABEL)["role"]))).is_equal(
		CompareRows.ROLE_UP
	)
	var effect := _row(rows, CompareRows.EFFECT_LABEL)
	assert_str(str(effect["old"])).is_equal(quick.describe())
	assert_str(str(effect["new"])).is_equal(slow.describe())
	# A passive against an active is still two full columns.
	var thorns := UiFakes.make_passive("thorns", "Thorns", "Reflect 20% of melee damage taken.")
	var mixed := CompareRows.rows_for(thorns, quick)
	assert_str(str(_row(mixed, CompareRows.KIND_LABEL)["old"])).is_equal("Passive")
	assert_str(str(_row(mixed, AbilityCard.COOLDOWN_LABEL)["old"])).is_equal(CompareRows.ABSENT)


# ------------------------------------------------------------------ the view


## The view draws the model whole: one row per model row, in order, and no row says "more".
func test_the_view_draws_every_row_of_the_model() -> void:
	var worn := UiFakes.make_item(_rng(7), ItemInstance.Rarity.EPIC, ItemBase.Slot.RING)
	var offered := UiFakes.make_item(_rng(11), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.RING)
	var view := _view(worn, offered)
	assert_array(view.rows()).is_equal(CompareRows.rows_for(worn, offered))
	var drawn := 0
	for node: Node in view.find_children("RowLabel", "Label", true, false):
		drawn += 1
	assert_int(drawn).is_equal(view.rows().size())
	for text: String in view.row_texts():
		assert_str(text.to_lower()).not_contains("more")
	assert_str(view.out_title()).is_equal(worn.display_name)
	assert_str(view.in_title()).is_equal(offered.display_name)
	assert_str(view.out_caption()).is_equal(CompareView.OUT_CAPTION)
	assert_str(view.in_caption()).is_equal(CompareView.IN_CAPTION)


## The two value columns share their x whatever the row holds, so a wrapped sentence and a
## number sit in the same column and the direction marks line up down the right edge.
func test_value_columns_are_aligned_across_stat_and_text_rows() -> void:
	var worn := UiFakes.make_item(_rng(7), ItemInstance.Rarity.EPIC, ItemBase.Slot.RING)
	var offered := UiFakes.make_item(_rng(11), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.RING)
	var view := _view(worn, offered)
	await get_tree().process_frame
	await get_tree().process_frame
	var xs: Dictionary = {}
	for node: Node in view.find_children("New", "Label", true, false):
		var x := (node as Label).global_position.x
		xs[x] = true
	assert_int(xs.size()).override_failure_message("New column at %s" % str(xs.keys())).is_equal(1)


## A table taller than its room takes the compact step and then scrolls - it never cuts.
func test_a_tall_table_closes_its_gap_and_scrolls_rather_than_cutting() -> void:
	var worn := UiFakes.make_item(_rng(7), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.WEAPON)
	var offered := UiFakes.make_item(_rng(11), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.WEAPON)
	var view := _view(worn, offered, 96.0)
	await get_tree().process_frame
	assert_bool(view.is_compact()).is_true()
	assert_bool(view.is_scrollable()).is_true()
	assert_int(view.rows().size()).is_equal(CompareRows.rows_for(worn, offered).size())
	var before := view.scroll_by(0)
	assert_int(view.scroll_by(1)).is_greater(before)
	# ... and the hint says so.
	assert_str(UiPrompt.render_plain(CompareView.hint_text(false, 1, false, true))).contains(
		"scroll"
	)
	assert_str(UiPrompt.render_plain(CompareView.hint_text(false, 1, false, false))).not_contains(
		"scroll"
	)
	# The same trade with room to spare neither compacts nor scrolls.
	var roomy := _view(worn, offered, 400.0)
	await get_tree().process_frame
	assert_bool(roomy.is_scrollable()).is_false()


## The head titles of `view` that are drawn with an ellipsis.
##
## The titles are the one place in this view that really does elide: they carry
## `OVERRUN_TRIM_ELLIPSIS` over a two-line budget, so a name needing a third line loses its tail
## with nothing in `text` to say so. The row labels have no line budget at all, which is why
## scanning *their* text for an ellipsis - the first shape of this test - could never have found
## anything. `test_the_elision_detector_can_see_an_elided_title` is what keeps this honest: a
## detector that has never been shown to fire is not evidence of absence.
static func _elided_titles(view: CompareView, where: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for node: Node in view.find_children("Title", "Label", true, false):
		var title := node as Label
		if title.max_lines_visible > 0 and title.get_line_count() > title.max_lines_visible:
			out.append(
				(
					"%s: the head title '%s' needs %d lines and is given %d"
					% [where, title.text, title.get_line_count(), title.max_lines_visible]
				)
			)
	return out


## The sweep above reports no elided title on any generated trade. That is only worth something
## if the detector can see one, so here is one it must: a name far past the two lines a head is
## given. Without this, a clean sweep and a broken detector look identical - which is exactly
## the state this test was in before, when it scanned the model's own text for an ellipsis the
## model can never contain.
func test_the_elision_detector_can_see_an_elided_title() -> void:
	var worn := UiFakes.make_item(_rng(7), ItemInstance.Rarity.EPIC, ItemBase.Slot.RING)
	var offered := UiFakes.make_item(_rng(11), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.RING)
	offered.display_name = (
		"Absolutely Preposterous Thoroughly Overdecorated Ceremonial Signet Ring of the "
		+ "Exceedingly Long Winded Appellation"
	)
	var view := _view(worn, offered)
	await get_tree().process_frame
	(
		assert_array(_elided_titles(view, "the long name"))
		. override_failure_message(
			(
				"a 120-character item name did not register as elided, so the sweep's clean "
				+ "result says nothing"
			)
		)
		. is_not_empty()
	)


## Over real generated gear: the model and the view agree, nothing elides, and every view
## that scrolls says so. This is the measurement the "+N more" complaint was about.
func test_no_generated_trade_is_ever_cut() -> void:
	var items := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	var offenders: PackedStringArray = []
	for seed_index in range(TRADE_SEEDS):
		rng.seed = 3000 + seed_index
		var worn := ItemGenerator.generate(items, 1 + seed_index % 9, rng, 0.0, [], -1)
		var offered := ItemGenerator.generate(items, 9, rng, 0.0, [], -1)
		if worn == null or offered == null:
			continue
		# Every height the board can hand the view, cramped first: cutting is a height
		# question, and a sweep that only ever runs at the roomy height is not a sweep.
		# `HEIGHTS[0]` is under `CompareView`'s own compact threshold, so these trades are
		# drawn scrolling as well as drawn whole.
		for height: float in HEIGHTS:
			_check_trade(worn, offered, height, seed_index, offenders)
	assert_array(offenders).override_failure_message("\n".join(offenders)).is_empty()


## One trade at one height: the drawn table carries every row of the model, in full.
func _check_trade(
	worn: Variant, offered: Variant, height: float, seed_index: int, offenders: PackedStringArray
) -> void:
	var view := _view(worn, offered, height)
	await get_tree().process_frame
	# Read off the *drawn* labels, not off `view.rows()`. `rows()` hands back the array the view
	# was handed, so comparing it with `CompareRows.rows_for(...)` compared a call with itself,
	# and `row_texts()` re-serialises that same array rather than the nodes. Proven by mutation:
	# drawing only the first four rows of every trade left this test - the one named for the
	# "+N more" complaint - completely green.
	var where := "seed %d at %.0f px" % [seed_index, height]
	var drawn: Array[Label] = []
	for node: Node in view.find_children("RowLabel", "Label", true, false):
		drawn.append(node as Label)
	if drawn.size() != view.rows().size():
		offenders.append(
			"%s: %d rows drawn, %d in the model" % [where, drawn.size(), view.rows().size()]
		)
	for label: Label in drawn:
		var text := label.text
		if text.to_lower().contains(" more") or text.contains("\u2026") or text.ends_with("..."):
			offenders.append("%s: '%s'" % [where, text])
		# A label set to trim with an ellipsis shows one the moment its text needs more lines
		# than it is allowed, and the text itself never says so. This is the only way to see it.
		if label.max_lines_visible > 0 and label.get_line_count() > label.max_lines_visible:
			offenders.append(
				(
					"%s: '%s' needs %d lines and is given %d"
					% [where, text, label.get_line_count(), label.max_lines_visible]
				)
			)
	offenders.append_array(_elided_titles(view, where))
	if CompareRows.stat_rows(view.rows()).is_empty():
		offenders.append("%s: an empty table" % where)


## The note under the heads is where a cursed prize's curse is stated, and it is empty for a
## plain trade.
func test_a_trade_note_is_printed_under_the_heads() -> void:
	var worn := UiFakes.make_item(_rng(7), ItemInstance.Rarity.EPIC, ItemBase.Slot.RING)
	var offered := UiFakes.make_item(_rng(11), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.RING)
	var plain := _view(worn, offered)
	assert_str(plain.note()).is_empty()
	var cursed: CompareView = auto_free(CompareView.new())
	add_child(cursed)
	cursed.build(worn, offered, 0, 2, HEIGHT, "Curse: Kernel Panic")
	assert_str(cursed.note()).is_equal("Curse: Kernel Panic")
	assert_str(cursed.footer()).is_equal("Slot 1 of 2")


## The board swaps its button row for Swap / Keep mine on the compare step, so the mouse has
## the same two answers the pad has, and Reroll is not offered on a question it cannot answer.
func test_the_board_offers_swap_and_keep_buttons_on_the_compare_step() -> void:
	var chest: ChestUi = auto_free((load(SCENE) as PackedScene).instantiate())
	add_child(chest)
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	chest.show_offers(
		ChestUi.Kind.ITEM, UiFakes.make_offers(ChestUi.Kind.ITEM), UiFakes.chest_context(player)
	)
	await get_tree().process_frame
	var swap := chest.get_node("%Swap") as Button
	var keep := chest.get_node("%Keep") as Button
	var reroll := chest.get_node("%Reroll") as Button
	assert_bool(swap.visible).is_false()
	assert_bool(keep.visible).is_false()
	chest.activate()
	await get_tree().process_frame
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.REPLACE)
	assert_bool(swap.visible).is_true()
	assert_bool(keep.visible).is_true()
	assert_bool(reroll.visible).is_false()
	assert_str(keep.text).is_equal(ChestUi.keep_label(false))
	var monitor := monitor_signals(chest)
	keep.pressed.emit()
	await get_tree().process_frame
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.OFFERS)
	await assert_signal(monitor).wait_until(100).is_not_emitted("chosen")
	chest.activate()
	await get_tree().process_frame
	swap.pressed.emit()
	await assert_signal(monitor).is_emitted("chosen", [chest.offers[0], 0, -1])
