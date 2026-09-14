class_name ClassSelectTest
extends GdUnitTestSuite


func _select() -> ClassSelect:
	var select: ClassSelect = auto_free(
		(load("res://src/ui/class_select.tscn") as PackedScene).instantiate()
	)
	add_child(select)
	return select


func test_four_classes_in_design_order() -> void:
	var select := _select()
	assert_int(select.classes.size()).is_equal(4)
	assert_that(select.classes[0]["id"]).is_equal(&"fighter")
	assert_that(select.classes[3]["id"]).is_equal(&"oligarch")


func test_navigation_wraps_and_confirm_emits() -> void:
	var select := _select()
	var monitor := monitor_signals(select)
	select.select(-1)
	assert_that(select.selected_id()).is_equal(&"oligarch")
	select.select(1)
	select.confirm()
	await assert_signal(monitor).is_emitted("class_chosen", [&"ranger"])


func test_locked_class_cannot_be_chosen() -> void:
	var select := _select()
	select.locked_ids = [&"oligarch"]
	select.select(3)
	var monitor := monitor_signals(select)
	select.confirm()
	await assert_signal(monitor).wait_until(200).is_not_emitted("class_chosen")


func test_locked_ids_set_after_ready_refreshes_the_card() -> void:
	var select := _select()
	select.locked_ids = [&"oligarch"]
	var card := select._cards[3]
	assert_str((card.find_child("Lock", true, false) as Label).text).is_equal("Locked")
	assert_bool((card.find_child("LockIcon", true, false) as Control).visible).is_true()


func test_class_ids_cover_the_shipped_definitions() -> void:
	var ids := ClassSelect.class_ids()
	assert_bool(ids.has(&"fighter")).is_true()
	assert_bool(ids.has(&"oligarch")).is_true()


func _description(select: ClassSelect, index: int) -> Label:
	return select._cards[index].find_child("Description", true, false) as Label


## Regression: the Oligarch - the locked class, whose blurb is the only place its economy
## gimmick is explained - was clipped to "delegates dodging to a..." because the "Locked"
## stamp was overlaid on the blurb block. The unlocked pass alone never saw it, so the lock
## state is part of the assertion now.
func test_every_blurb_is_shown_in_full_at_the_native_resolution() -> void:
	await _assert_blurbs_fit([])
	await _assert_blurbs_fit([&"oligarch"])


func _assert_blurbs_fit(locked: Array[StringName]) -> void:
	var select := _select()
	select.locked_ids = locked
	select.size = Vector2(480, 270)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in select.classes.size():
		var desc := _description(select, i)
		(
			assert_int(desc.get_visible_line_count())
			. override_failure_message(
				(
					"%s blurb is clipped (locked %s): %d of %d lines fit in %s"
					% [
						select.classes[i]["id"],
						locked,
						desc.get_visible_line_count(),
						desc.get_line_count(),
						desc.size
					]
				)
			)
			. is_greater_equal(desc.get_line_count())
		)


func test_the_locked_stamp_costs_no_blurb_line_and_no_card_row() -> void:
	var select := _select()
	select.size = Vector2(480, 270)
	await get_tree().process_frame
	var free_height := _description(select, 3).size.y
	var grid := select._cards[3].get_child(0).get_child(3) as Control
	var grid_y := grid.position.y
	select.locked_ids = [&"oligarch"]
	await get_tree().process_frame
	var lock := select._cards[3].find_child("Lock", true, false) as Label
	# The stamp rides the portrait badge, so locking a card costs the description nothing
	# and still never moves its stat grid.
	assert_str(str(lock.text)).is_equal("Locked")
	assert_bool(lock.is_ancestor_of(_description(select, 3))).is_false()
	assert_float(_description(select, 3).size.y).is_equal(free_height)
	assert_float(grid.position.y).is_equal(grid_y)


## Owner report 7 / verifier: the four cards ran on three different vertical rhythms. The
## selected card was scaled about its centre, which lifted its portrait about eight native
## pixels above the other three, and the Oligarch's trait block sat a full line below everyone
## else's because its ability name is short enough not to wrap and the difference was handed to
## its blurb box. Every block on every card has to start on the same line, whichever card the
## selection is on.
func test_the_four_cards_share_one_vertical_grid() -> void:
	var select := _select()
	select.locked_ids = [&"oligarch"]
	for selected: int in [0, 1, 3]:
		select.select(selected)
		await get_tree().process_frame
		await get_tree().process_frame
		for block: String in ["Portrait", "Name", "DescBox", "Traits"]:
			var tops := _tops_of(select, block)
			(
				assert_array(tops)
				. override_failure_message(
					"selection on card %d: %s tops are %s" % [selected, block, tops]
				)
				. contains_exactly([tops[0], tops[0], tops[0], tops[0]])
			)


## ... and the stat bars, which are the bottom of the card and the block a player actually
## reads across. Measured separately so a failure says which end of the card drifted.
func test_the_stat_bars_line_up_across_the_four_cards() -> void:
	var select := _select()
	select.select(2)
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: Array[float] = []
	for card: PanelContainer in select._cards:
		var bar := card.find_child("*ProgressBar*", true, false) as Control
		if bar == null:
			bar = _first_bar(card)
		assert_object(bar).is_not_null()
		rows.append(bar.get_global_rect().position.y)
	assert_array(rows).contains_exactly([rows[0], rows[0], rows[0], rows[0]])


## Moving the selection must not move anything: the pop that used to mark it was a scale, and
## a scaled card lifts its own contents off the shared baseline.
func test_moving_the_selection_moves_no_content() -> void:
	var select := _select()
	select.select(0)
	await get_tree().process_frame
	await get_tree().process_frame
	var before := _tops_of(select, "Portrait")
	select.select(1)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(_tops_of(select, "Portrait")).contains_exactly(before)


## Global y of one named block on each of the four cards.
func _tops_of(select: ClassSelect, block: String) -> Array[float]:
	var out: Array[float] = []
	for card: PanelContainer in select._cards:
		var node := card.find_child(block, true, false) as Control
		assert_object(node).override_failure_message("no %s on a card" % block).is_not_null()
		out.append(node.get_global_rect().position.y)
	return out


static func _first_bar(node: Node) -> Control:
	for child: Node in node.get_children():
		if child is ProgressBar:
			return child as Control
		var found := _first_bar(child)
		if found != null:
			return found
	return null
