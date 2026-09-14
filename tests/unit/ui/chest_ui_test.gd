class_name ChestUiTest
extends GdUnitTestSuite

const SCENE := "res://src/ui/chest_ui.tscn"
const FIXTURES := "res://tests/fixtures/omarchy"
## Boards rolled per layout when measuring how much of a card is left empty under a cut.
const GAP_SEEDS := 16
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]


func _chest() -> ChestUi:
	var chest: ChestUi = auto_free((load(SCENE) as PackedScene).instantiate())
	add_child(chest)
	return chest


func _press(chest: ChestUi, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	chest._unhandled_input(event)


## `CardFit.SELECTED_FILL_RATIO` is both the contrast the selected card's fill is built to and
## the bound the fill test measures against, so setting it to 1.0 makes selection invisible
## while that test still passes. This is the literal. It is deliberately small - the card is a
## surface, not a highlight - but it may never reach 1.0, which is the flat "no difference at
## all" a lerp toward a `select` role collapses to on a light theme, and a player who cannot
## see which card is selected cannot use the chest at all.
func test_the_selected_fill_contrast_is_a_number_not_a_tautology() -> void:
	(
		assert_float(CardFit.SELECTED_FILL_RATIO)
		. override_failure_message("SELECTED_FILL_RATIO flattened; selection is invisible")
		. is_greater_equal(1.1)
	)


func test_renders_three_cards_from_fake_offers() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	chest.show_offers(
		ChestUi.Kind.ITEM, UiFakes.make_offers(ChestUi.Kind.ITEM), UiFakes.chest_context(player)
	)
	assert_int(chest.card_count()).is_equal(3)
	assert_bool(chest.is_open()).is_true()
	assert_str((chest.get_node("%Title") as Label).text).is_equal("Item chest")
	assert_str((chest.get_node("%Reroll") as Button).text).is_equal("Reroll (25g)")
	assert_str((chest.get_node("%Skip") as Button).text).is_equal("Skip (+10g)")


func test_ui_accept_emits_chosen_with_selected_offer() -> void:
	var chest := _chest()
	var offers := UiFakes.make_offers(ChestUi.Kind.STAT)
	chest.show_offers(ChestUi.Kind.STAT, offers, {"current_stats": {&"might": 4}})
	var monitor := monitor_signals(chest)
	_press(chest, &"ui_right")
	assert_int(chest.selected_index()).is_equal(1)
	_press(chest, &"ui_accept")
	await assert_signal(monitor).is_emitted("chosen", [offers[1], -1, -1])
	assert_bool(chest.is_open()).is_false()


func test_replace_flow_answers_with_the_chosen_slot() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var offers := UiFakes.make_offers(ChestUi.Kind.ABILITY)
	chest.show_offers(ChestUi.Kind.ABILITY, offers, UiFakes.chest_context(player))
	var monitor := monitor_signals(chest)
	_press(chest, &"ui_accept")
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.REPLACE)
	_press(chest, &"ui_right")
	_press(chest, &"ui_accept")
	await assert_signal(monitor).is_emitted("chosen", [offers[0], 1, -1])


func test_describe_offer_variants() -> void:
	var chest := _chest()
	chest.context = {"current_stats": {&"might": 4}}
	var stat := chest.describe_offer({"stat": &"might", "points": 1})
	assert_str(stat["title"]).is_equal("+1 Might")
	assert_str(stat["lines"][0]).is_equal("Might 4 -> 5")
	var gold := chest.describe_offer(40)
	assert_str(gold["title"]).is_equal("+40 gold")
	var active := chest.describe_offer(UiFakes.make_active("fireball", "Fireball", 6.0))
	assert_str(active["subtitle"]).is_equal("Active  CD 6s")
	assert_that(ChestUi.border_role_for(UiFakes.make_passive("t", "T", "d"))).is_equal(&"magic")


func test_skip_and_reroll_signals() -> void:
	var chest := _chest()
	chest.show_offers(ChestUi.Kind.GOLD, [10, 20, 30], {"reroll_cost": 25, "gold": 100})
	var monitor := monitor_signals(chest)
	(chest.get_node("%Reroll") as Button).pressed.emit()
	await assert_signal(monitor).is_emitted("rerolled")
	(chest.get_node("%Skip") as Button).pressed.emit()
	await assert_signal(monitor).is_emitted("skipped")


func test_four_offers_still_fit_the_screen() -> void:
	var chest := _chest()
	var offers := UiFakes.make_offers(ChestUi.Kind.STAT)
	offers.append({"stat": &"arcana", "points": 1})
	chest.show_offers(ChestUi.Kind.STAT, offers, {"current_stats": {&"might": 4}})
	assert_int(chest.card_count()).is_equal(4)
	var panel := chest.get_node("%Panel") as PanelContainer
	assert_float(panel.offset_right - panel.offset_left).is_less_equal(464.0)
	assert_float(ChestUi.card_width(4)).is_less(ChestUi.card_width(3))
	assert_float(ChestUi.card_width(3)).is_equal(ChestUi.CARD_SIZE.x)


func test_shop_prices_are_shown_and_block_unaffordable_picks() -> void:
	var chest := _chest()
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	chest.show_offers(
		ChestUi.Kind.ITEM, offers, {"shop": true, "prices": [250, 40, 10], "gold": 100}
	)
	assert_bool(chest.is_shop()).is_true()
	assert_int(chest.price_for(0)).is_equal(250)
	assert_bool(chest.can_afford(0)).is_false()
	assert_bool(chest.can_afford(1)).is_true()
	assert_str((chest.get_node("%Skip") as Button).text).is_equal("Leave")
	var monitor := monitor_signals(chest)
	chest.select(0)
	chest.activate()
	await assert_signal(monitor).wait_until(200).is_not_emitted("chosen")
	chest.select(1)
	chest.activate()
	await assert_signal(monitor).is_emitted("chosen", [offers[1], -1, -1])


## Cards grow with their content now, but only up to a height the 480x270 dialog can draw:
## a ten-stat comparison must still not push the buttons off the screen.
func test_long_cards_never_grow_past_the_dialog() -> void:
	var chest := _chest()
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	var deltas := {
		&"might": 3.0,
		&"vitality": 2.0,
		&"precision": 1.0,
		&"arcana": 4.0,
		&"swiftness": 2.0,
		&"fortune": 1.0,
		&"max_hp": 25.0,
		&"armor": 6.0,
		&"crit_chance": 0.08,
		&"crit_mult": 0.5,
	}
	chest.show_offers(
		ChestUi.Kind.ITEM,
		offers,
		{"compare": func(_item: ItemInstance) -> Dictionary: return deltas}
	)
	await await_idle_frame()
	var card := chest._cards[0]
	assert_float(card.get_combined_minimum_size().y).is_less_equal(ChestUi.MAX_CARD_HEIGHT)
	assert_float(card.get_combined_minimum_size().y).is_greater_equal(ChestUi.CARD_SIZE.y)
	var panel := chest.get_node("%Panel") as PanelContainer
	assert_float(panel.size.y).is_less_equal(270.0)


func test_reroll_button_stays_enabled_when_unaffordable() -> void:
	var chest := _chest()
	chest.show_offers(ChestUi.Kind.GOLD, [10, 20, 30], {"reroll_cost": 999, "gold": 5})
	var reroll := chest.get_node("%Reroll") as Button
	assert_bool(reroll.disabled).is_false()
	var monitor := monitor_signals(chest)
	reroll.pressed.emit()
	await assert_signal(monitor).wait_until(200).is_not_emitted("rerolled")


func test_fit_rows_gives_each_row_the_lines_its_text_needs() -> void:
	var rows: Array[Dictionary] = [
		{"text": "three", "role": &""},
		{"text": "one", "role": &""},
		{"text": "two", "role": &"dim"},
	]
	var needs := {"three": 3, "one": 1, "two": 2}
	var fitted := CardFit.fit_rows(rows, 6, 0, func(text: String) -> int: return needs[text])
	var out: Array = fitted["rows"]
	assert_int(fitted["hidden"]).is_equal(0)
	assert_int(out.size()).is_equal(3)
	assert_int(out[0]["lines"]).is_equal(3)
	assert_int(out[1]["lines"]).is_equal(1)
	assert_int(out[2]["lines"]).is_equal(2)


func test_fit_rows_reserves_a_line_for_the_more_row_when_it_drops_one() -> void:
	var rows: Array[Dictionary] = [
		{"text": "a", "role": &""}, {"text": "b", "role": &""}, {"text": "c", "role": &""}
	]
	var fitted := CardFit.fit_rows(rows, 3, 0, func(_t: String) -> int: return 2)
	var out: Array = fitted["rows"]
	# Capacity 3, one line kept for "+N more": only the first two-line row fits.
	assert_int(out.size()).is_equal(1)
	assert_int(out[0]["lines"]).is_equal(2)
	assert_int(fitted["hidden"]).is_equal(2)


func test_fit_rows_truncates_the_description_rather_than_showing_an_empty_card() -> void:
	var rows: Array[Dictionary] = [{"text": "long", "role": &""}]
	var fitted := CardFit.fit_rows(rows, 3, 0, func(_t: String) -> int: return 9)
	var out: Array = fitted["rows"]
	# The only row keeps every line there is; its own ellipsis says it was cut, so no line is
	# wasted on a "+N more" row.
	assert_int(out.size()).is_equal(1)
	assert_int(out[0]["lines"]).is_equal(3)
	assert_int(fitted["hidden"]).is_equal(0)


func test_fit_rows_carries_rows_the_caller_already_cut() -> void:
	var rows: Array[Dictionary] = [{"text": "a", "role": &""}]
	var fitted := CardFit.fit_rows(rows, 4, 3, func(_t: String) -> int: return 1)
	assert_int(fitted["hidden"]).is_equal(3)
	assert_int((fitted["rows"] as Array).size()).is_equal(1)


func test_ability_descriptions_wrap_instead_of_being_cut_after_two_words() -> void:
	var chest := _chest()
	var offers := UiFakes.make_offers(ChestUi.Kind.ABILITY)
	var ability := offers[0] as Ability
	ability.description = "Melee knockback doubles and every third hit staggers the target."
	chest.show_offers(ChestUi.Kind.ABILITY, offers, {})
	await get_tree().process_frame
	await get_tree().process_frame
	var body := _body_labels(chest._cards[0])
	assert_array(body).is_not_empty()
	var first := body[0] as Label
	assert_int(first.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
	assert_str(first.text).is_equal(ability.description)
	assert_int(first.max_lines_visible).is_greater(1)
	assert_int(first.get_line_count()).is_less_equal(first.max_lines_visible)


## Body rows of a card: every Label under the card that is not the title/subtitle head.
func _body_labels(card: PanelContainer) -> Array:
	var box := card.get_child(0).get_child(0) as VBoxContainer
	var out: Array = []
	for child: Node in box.get_children():
		if child is Label:
			out.append(child)
	return out


func test_card_subtitles_never_drop_letters_on_a_four_card_layout() -> void:
	var chest := _chest()
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	offers.append(offers[0])
	chest.show_offers(ChestUi.Kind.ITEM, offers, {"extra_option": true})
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(chest.card_count()).is_equal(4)
	for card: PanelContainer in chest._cards:
		var subtitle := _subtitle_label(card)
		assert_int(subtitle.max_lines_visible).is_greater_equal(1)
		assert_int(subtitle.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
		(
			assert_int(subtitle.get_visible_line_count())
			. override_failure_message(
				(
					"subtitle '%s' shows %d of %d lines"
					% [subtitle.text, subtitle.get_visible_line_count(), subtitle.get_line_count()]
				)
			)
			. is_greater_equal(subtitle.get_line_count())
		)


## Second label of a card's title column (icon | [title, subtitle]).
func _subtitle_label(card: PanelContainer) -> Label:
	var head := card.get_child(0).get_child(0).get_child(0) as HBoxContainer
	return head.get_child(1).get_child(1) as Label


# ---------------------------------------------------------------- the item card (docs §4.5)


## Body row texts of a card, in the order they are drawn (the price row is not one of them).
func _body_texts(card: PanelContainer) -> PackedStringArray:
	var out: PackedStringArray = []
	var box := card.get_child(0).get_child(0) as VBoxContainer
	for child: Node in box.get_children():
		if child is Label and child.get_parent() == box:
			out.append((child as Label).text)
	return out


func _item_board(chest: ChestUi) -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	chest.show_offers(
		ChestUi.Kind.ITEM, UiFakes.make_offers(ChestUi.Kind.ITEM), UiFakes.chest_context(player)
	)
	await get_tree().process_frame
	await get_tree().process_frame


## The blocker: a weapon card that never printed the weapon's damage, rate or reach made the
## central choice of the game a coin flip.
func test_a_weapon_card_prints_the_weapon_numbers() -> void:
	var chest := _chest()
	await _item_board(chest)
	var texts := _body_texts(chest._cards[0])
	assert_array(texts).contains(["8 damage  2/s", "16 dps  20 range"])


## The other half of it: the comparison could not show those numbers either, because
## Equipment.compare() only diffs Stats. It now shows both sides of each of them, headed by
## the name of the weapon that would come off - the owner could not read the old delta list.
func test_the_comparison_shows_both_sides_of_the_weapon_numbers() -> void:
	var chest := _chest()
	await _item_board(chest)
	var texts := _body_texts(chest._cards[0])
	var header := Array(texts).find("Replaces Rusty Sword")
	(
		assert_int(header)
		. override_failure_message("no heading naming the worn weapon in %s" % texts)
		. is_greater(0)
	)
	# Offered: 8 dmg 2.0/s 20 range. Worn: 12 dmg 1.8/s 24 range.
	assert_str(texts[header + 1]).is_equal("Damage 12 -> 8")
	assert_str(texts[header + 2]).is_equal("Rate 1.8 -> 2")
	assert_str(texts[header + 3]).is_equal("Dps 21.6 -> 16")
	assert_str(texts[header + 4]).is_equal("Range 24 -> 20")


## Nothing on the card may still be a bare delta: that is the thing the owner could not read.
func test_no_comparison_row_is_a_bare_delta() -> void:
	var chest := _chest()
	await _item_board(chest)
	for card: PanelContainer in chest._cards:
		var texts := _body_texts(card)
		var header := Array(texts).find("Replaces Rusty Sword")
		if header < 0:
			continue
		for i in range(header + 1, texts.size()):
			# The card's own "+N more" marker is not a comparison row.
			if texts[i].ends_with(" more"):
				continue
			(
				assert_str(texts[i])
				. override_failure_message("'%s' is a delta, not a before/after" % texts[i])
				. contains(ItemCard.SWAP_ARROW)
			)


## The card used to concatenate the item's own affixes and the comparison deltas into one
## unlabelled list, so the same line appeared two or three times with nothing to tell them apart.
func test_the_two_blocks_are_separated_by_a_rule_and_a_heading() -> void:
	var chest := _chest()
	await _item_board(chest)
	var card := chest._cards[0]
	var heading := "Replaces Rusty Sword"
	var texts := _body_texts(card)
	assert_int(Array(texts).count(heading)).is_equal(1)
	var box := card.get_child(0).get_child(0) as VBoxContainer
	var header_index := -1
	var rule_before := false
	var previous: Node = null
	for child: Node in box.get_children():
		if child is Label and (child as Label).text == heading:
			header_index = child.get_index()
			rule_before = previous is HSeparator
		previous = child
	assert_int(header_index).is_greater(0)
	assert_bool(rule_before).is_true()


func test_an_empty_slot_says_so_instead_of_repeating_the_affixes() -> void:
	var chest := _chest()
	await _item_board(chest)
	# The fake player wears a ring in ring_1 and nothing in ring_2, so the legendary ring goes
	# into a free slot: there is nothing to compare it against.
	var texts := _body_texts(chest._cards[2])
	assert_array(texts).contains([ItemCard.EMPTY_SLOT_NOTE])
	for text: String in texts:
		assert_str(text).not_contains("Replaces")
		assert_str(text).not_contains(ItemCard.COMPARE_HEADER)


## A Legendary is chosen for its affixes; they may not be the rows that end up behind "+N more".
func test_a_legendary_card_hides_nothing() -> void:
	var chest := _chest()
	await _item_board(chest)
	var legendary := chest.offers[2] as ItemInstance
	assert_int(legendary.rarity).is_equal(ItemInstance.Rarity.LEGENDARY)
	var texts := _body_texts(chest._cards[2])
	for line: String in ItemCard.item_lines(legendary):
		assert_array(texts).contains([line])
	for text: String in texts:
		assert_str(text).not_contains("more")


func test_describe_offer_keeps_the_blocks_apart() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	chest.context = UiFakes.chest_context(player)
	var info := chest.describe_offer(UiFakes.make_offers(ChestUi.Kind.ITEM)[0])
	assert_array(info["lines"]).is_not_empty()
	assert_array(info["deltas"]).is_not_empty()
	# `rows` is what the card draws: the lines, then the rule, the heading and the deltas.
	var rows: Array = info["rows"]
	assert_int(rows.size()).is_equal(
		(info["lines"] as Array).size() + (info["deltas"] as Array).size() + 2
	)


# ---------------------------------------------------------------- modality and refusals


## The picker itself never pauses: `RunManager` freezes the run around the offer, and
## `tests/unit/integration/offer_flow_test.gd` asserts that end to end. What matters here is
## that the picker keeps working while something else holds the tree paused.
func test_the_picker_still_takes_input_while_the_tree_is_paused() -> void:
	var chest := _chest()
	chest.show_offers(ChestUi.Kind.GOLD, [10, 20, 30], {})
	get_tree().paused = true
	_press(chest, &"ui_right")
	assert_int(chest.selected_index()).is_equal(1)
	assert_int(chest.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	get_tree().paused = false


func test_a_board_that_cannot_be_rerolled_shows_no_reroll_button() -> void:
	var chest := _chest()
	chest.show_offers(
		ChestUi.Kind.STAT, UiFakes.make_offers(ChestUi.Kind.STAT), {"can_reroll": false}
	)
	var reroll := chest.get_node("%Reroll") as Button
	assert_bool(reroll.visible).is_false()
	# ... and the button row then has one column, so "down, accept" cannot land on the hidden one.
	var monitor := monitor_signals(chest)
	_press(chest, &"ui_down")
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.BUTTONS)
	_press(chest, &"ui_accept")
	await assert_signal(monitor).is_emitted("skipped")
	await assert_signal(monitor).wait_until(100).is_not_emitted("rerolled")


func test_an_unavailable_offer_cannot_be_taken() -> void:
	var chest := _chest()
	var offers: Array = [
		{"stat": &"might", "points": 1},
		{
			"stat": &"cleanse",
			"points": 1,
			"label": "Cleanse a curse",
			"unavailable": true,
			"note": "No curse to cleanse",
		},
	]
	chest.show_offers(ChestUi.Kind.STAT, offers, {})
	await get_tree().process_frame
	assert_bool(chest.can_pick(0)).is_true()
	assert_bool(chest.can_pick(1)).is_false()
	assert_array(_body_texts(chest._cards[1])).contains(["No curse to cleanse"])
	var monitor := monitor_signals(chest)
	chest.select(1)
	chest.activate()
	await assert_signal(monitor).wait_until(200).is_not_emitted("chosen")
	chest.select(0)
	chest.activate()
	await assert_signal(monitor).is_emitted("chosen", [offers[0], -1, -1])


## An ability card that trims its own description with an ellipsis cannot show the effect the
## player is choosing, and the ability chest is the single most important decision screen in
## the game. `class_def_test` already holds this line for the four class cards; this is the
## same promise for `data/abilities`, and it is measured on the card the offer is actually
## drawn on - a character budget would have had to guess at the head block, the rule, the
## replace-row height cap and the wrap width, and every one of those moves.
##
## Each ability is put on a board of its own so the card row is sized by *its* title and *its*
## description, which is the height the game gives it whenever it is the longest card on the
## board - the case the ellipsis showed up in.
func test_no_ability_blurb_is_longer_than_its_card_can_show() -> void:
	var registry := AbilityRegistry.load_default()
	assert_object(registry).is_not_null()
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var context := UiFakes.chest_context(player)
	var trimmed: PackedStringArray = []
	for ability: Ability in registry.abilities:
		var offers: Array = [
			ability.duplicate_ability(), ability.duplicate_ability(), ability.duplicate_ability()
		]
		chest.show_offers(ChestUi.Kind.ABILITY, offers, context)
		await get_tree().process_frame
		await get_tree().process_frame
		var label := _body_labels(chest._cards[0])[0] as Label
		if label.get_line_count() > label.max_lines_visible:
			trimmed.append(
				(
					"%s: %d of %d lines"
					% [String(ability.id), label.max_lines_visible, label.get_line_count()]
				)
			)
	(
		assert_array(trimmed)
		. override_failure_message("ability cards that trim their own description: %s" % trimmed)
		. is_empty()
	)


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


## Which card has focus was carried by one shade step of one hue. On catppuccin-latte that came
## out as two dark greens 1.67:1 apart with fills 3/255 apart, which is not a difference anyone
## reads at a glance on paper. Focus now also moves the fill by a guaranteed amount and the
## border by a whole pixel of thickness, so it survives a theme with no accent to spare.
func test_the_selected_card_is_marked_on_more_than_one_channel() -> void:
	assert_int(OfferCard.BORDER_SELECTED).is_greater(OfferCard.BORDER_IDLE)
	for theme: String in THEMES:
		var palette := _palette(theme)
		UiTheme.rebuild(palette)
		var base := UiTheme.color(&"floor_alt")
		var fill := CardFit.selected_fill(base, UiTheme.color(&"select"))
		(
			assert_float(ThemePalette.contrast_ratio(fill, base))
			. override_failure_message("%s: the selected card's fill is the plain one" % theme)
			. is_greater_equal(CardFit.SELECTED_FILL_RATIO - 0.001)
		)
	UiTheme.rebuild(Desktop.palette)


## The guard for the channel this work was not about: the border still carries *rarity*, so
## making focus louder may not turn every card's edge into one focus colour.
func test_the_card_border_still_carries_the_offers_rarity() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var offers: Array = [
		UiFakes.make_item(rng, ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.WEAPON),
		UiFakes.make_item(rng, ItemInstance.Rarity.COMMON, ItemBase.Slot.ARMOR),
	]
	chest.show_offers(ChestUi.Kind.ITEM, offers, UiFakes.chest_context(player))
	await get_tree().process_frame
	var selected := chest._cards[0].get_theme_stylebox(&"panel") as StyleBoxFlat
	var other := chest._cards[1].get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_int(chest.selected_index()).is_equal(0)
	assert_int(selected.border_width_left).is_equal(OfferCard.BORDER_SELECTED)
	assert_int(other.border_width_left).is_equal(OfferCard.BORDER_IDLE)
	assert_that(selected.border_color).is_equal(UiTheme.color(ChestUi.border_role_for(offers[0])))
	(
		assert_float(UiTheme.color_distance(selected.border_color, other.border_color))
		. override_failure_message("both cards' borders have collapsed onto one colour")
		. is_greater(0.0)
	)


# ------------------------------------------------- the swap view (owner report 6)


## A real pad button, through the real InputMap and the real viewport. An `InputEventAction`
## fed straight to the handler proves the handler is wired to itself and nothing else, which
## is how eight rounds of review missed a pad that could not answer a dialog.
func _pad_press(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await get_tree().process_frame
	var up := InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _ability_board(chest: ChestUi) -> Array:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var offers := UiFakes.make_offers(ChestUi.Kind.ABILITY)
	chest.show_offers(ChestUi.Kind.ABILITY, offers, UiFakes.chest_context(player))
	await get_tree().process_frame
	await get_tree().process_frame
	return offers


## The swap step used to be a second row of small cards under the offers, captioned "Replace
## which?", with nothing on screen saying which offer was being taken - and then two cards
## with the differences printed on one of them. It is one table now: both halves on every
## row, headed by direction.
func test_the_swap_view_shows_what_goes_and_what_arrives() -> void:
	var chest := _chest()
	var offers := await _ability_board(chest)
	chest.activate()
	await get_tree().process_frame
	var swap := chest.compare_view()
	assert_bool(chest.offers_visible()).is_false()
	assert_object(swap.out_head).is_not_null()
	assert_object(swap.in_head).is_not_null()
	assert_array(swap.rows()).is_not_empty()
	# Left: the ability that would be given up. Right: the one being taken.
	assert_str(swap.out_title()).is_equal("Fireball")
	assert_str(swap.in_title()).is_equal((offers[0] as Ability).display_name)
	assert_str(swap.out_caption()).is_equal(CompareView.OUT_CAPTION)
	assert_str(swap.in_caption()).is_equal(CompareView.IN_CAPTION)
	# ... and the subtitle says why the question is being asked at all.
	assert_str((chest.get_node("%Subtitle") as Label).text).contains("full")


## Two filled slots means two trades; the view says so and shows one at a time.
func test_the_swap_view_names_which_slot_it_is_showing() -> void:
	var chest := _chest()
	await _ability_board(chest)
	chest.activate()
	await get_tree().process_frame
	var swap := chest.compare_view()
	assert_str(swap.footer()).contains("1 of 2")
	chest.select(1)
	await get_tree().process_frame
	assert_str(swap.footer()).contains("2 of 2")
	assert_str(swap.out_title()).is_equal("Frost Nova")
	# One candidate is not a choice, so it is not captioned as one.
	assert_str(CompareView.footer_text(0, 1)).is_empty()


## The whole trade, driven the way the owner drove it: D-pad and A, no keyboard anywhere.
func test_a_pad_can_walk_the_swap_view_and_take_the_trade() -> void:
	var chest := _chest()
	var offers := await _ability_board(chest)
	var monitor := monitor_signals(chest)
	await _pad_press(JOY_BUTTON_A)
	(
		assert_int(chest.selected_row())
		. override_failure_message("A did not open the swap view")
		. is_equal(ChestUi.Row.REPLACE)
	)
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	assert_str(chest.compare_view().footer()).contains("2 of 2")
	await _pad_press(JOY_BUTTON_A)
	await assert_signal(monitor).is_emitted("chosen", [offers[0], 1, -1])


## B backs out of the swap and hands the board back, rather than leaving the player stuck in
## a question they did not mean to open.
func test_b_leaves_the_swap_view_without_taking_anything() -> void:
	var chest := _chest()
	await _ability_board(chest)
	var board := chest.get_node("%Panel") as PanelContainer
	var width := board.offset_right - board.offset_left
	var monitor := monitor_signals(chest)
	await _pad_press(JOY_BUTTON_A)
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.REPLACE)
	await _pad_press(JOY_BUTTON_B)
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.OFFERS)
	assert_bool(chest.offers_visible()).is_true()
	# ... and the dialog is the board's size again, not the swap view's.
	var panel := chest.get_node("%Panel") as PanelContainer
	assert_float(panel.offset_right - panel.offset_left).is_equal(width)
	await assert_signal(monitor).wait_until(100).is_not_emitted("chosen")


## Rerolling is not an answer to "which one goes": the button belongs to the board behind.
func test_the_swap_view_does_not_offer_a_reroll() -> void:
	var chest := _chest()
	await _ability_board(chest)
	assert_bool((chest.get_node("%Reroll") as Button).visible).is_true()
	chest.activate()
	await get_tree().process_frame
	assert_bool((chest.get_node("%Reroll") as Button).visible).is_false()
	chest._cancel_replace()
	assert_bool((chest.get_node("%Reroll") as Button).visible).is_true()


## "Reroll (0g)" is a price tag with the number missing; a board that costs nothing to reroll
## says so in words.
func test_a_free_reroll_says_free_rather_than_zero_gold() -> void:
	assert_str(ChestUi.reroll_label({"reroll_cost": 0})).is_equal("Reroll (free)")
	assert_str(ChestUi.reroll_label({"reroll_cost": 0, "sold_out": true})).is_equal(
		"Restock (free)"
	)
	assert_str(ChestUi.reroll_label({"reroll_cost": 25, "gold": 100})).is_equal("Reroll (25g)")


# ------------------------------------- gear reaches the trade view (owner report 6, round 2)


## A weapon or a piece of armour used to swap in silence: the offer card named what it would
## replace and then a single press took it, with nothing on screen holding the two side by
## side. Gear goes through the same trade view an ability does now, driven with a real key.
func test_taking_gear_opens_the_trade_instead_of_swapping_in_silence() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	chest.show_offers(ChestUi.Kind.ITEM, offers, UiFakes.chest_context(player))
	await get_tree().process_frame
	var monitor := monitor_signals(chest)
	_press(chest, &"ui_accept")
	await get_tree().process_frame
	(
		assert_int(chest.selected_row())
		. override_failure_message("the weapon was taken without showing what came off")
		. is_equal(ChestUi.Row.REPLACE)
	)
	await assert_signal(monitor).wait_until(100).is_not_emitted("chosen")
	var swap := chest.compare_view()
	var worn := UiFakes.equipped_for(player, offers[0] as ItemInstance)
	assert_object(worn).is_not_null()
	assert_str(swap.out_title()).is_equal(worn.display_name)
	assert_str(swap.in_title()).is_equal((offers[0] as ItemInstance).display_name)
	assert_str(swap.out_caption()).is_equal(CompareView.OUT_CAPTION)
	assert_str(swap.in_caption()).is_equal(CompareView.IN_CAPTION)
	# ... and the subtitle names the slot that is about to be emptied, not "a slot".
	assert_str((chest.get_node("%Subtitle") as Label).text).contains("weapon")
	_press(chest, &"ui_accept")
	await assert_signal(monitor).is_emitted("chosen", [offers[0], 0, -1])


## An offer that fits an empty slot is not a trade and must not ask a question. The fake
## player wears no trinket, so the trinket card is taken on one press.
func test_gear_that_fills_an_empty_slot_is_taken_straight_away() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var offers: Array = [UiFakes.make_item(rng, ItemInstance.Rarity.RARE, ItemBase.Slot.TRINKET)]
	chest.show_offers(ChestUi.Kind.ITEM, offers, UiFakes.chest_context(player))
	await get_tree().process_frame
	var monitor := monitor_signals(chest)
	_press(chest, &"ui_accept")
	await assert_signal(monitor).is_emitted("chosen", [offers[0], -1, -1])


## The left column is the worn thing's own numbers, never a comparison against itself.
## `context["equipped"]` answers "the worn weapon" for the worn weapon too, so without a
## guard the left half of the old trade came up headed "Replaces Rusty Sword" with a column
## of rows where nothing had moved.
func test_the_column_coming_off_states_its_own_numbers_and_no_comparison() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	chest.show_offers(ChestUi.Kind.ITEM, offers, UiFakes.chest_context(player))
	await get_tree().process_frame
	_press(chest, &"ui_accept")
	await get_tree().process_frame
	var worn := UiFakes.equipped_for(player, offers[0] as ItemInstance)
	var weapon := worn.base as WeaponBase
	var olds: Dictionary = {}
	for row: Dictionary in CompareRows.stat_rows(chest.compare_view().rows()):
		olds[str(row["label"])] = str(row["old"])
	assert_str(str(olds.get("Damage"))).is_equal(ItemCard.num(weapon.base_damage))
	assert_str(str(olds.get("Range"))).is_equal(ItemCard.num(weapon.range_px))
	for text: String in chest.compare_view().row_texts():
		assert_str(text).not_contains(ItemCard.REPLACES_HEADER % "")


# ------------------------------- abilities print their numbers (owner report 6, round 2)


## Items printed live deltas and abilities printed none, so a player weighing a six second
## cooldown against a ten second one did the arithmetic in their head off two subtitles.
func test_an_ability_trade_prints_the_cooldown_and_damage_it_changes() -> void:
	var chest := _chest()
	var offers := await _ability_board(chest)
	chest.activate()
	await get_tree().process_frame
	var swap := chest.compare_view()
	var texts := swap.row_texts()
	# Fireball (6 s, 26 dmg) comes off; Whirlwind (8 s, 32 dmg) goes on - both on one row.
	assert_array(texts).contains(["Cooldown  6s -> 8s"])
	assert_array(texts).contains(["Damage  26 -> 32"])
	# ... and the longer cooldown reads as a loss, the bigger number as a gain.
	var roles: Dictionary = {}
	for row: Dictionary in swap.rows():
		roles[str(row["label"])] = StringName(str(row["role"]))
	assert_that(roles.get(AbilityCard.COOLDOWN_LABEL)).is_equal(CompareRows.ROLE_DOWN)
	assert_that(roles.get(AbilityCard.DAMAGE_LABEL)).is_equal(CompareRows.ROLE_UP)
	# Both descriptions are on the table in full.
	var effect := _row_named(swap.rows(), CompareRows.EFFECT_LABEL)
	assert_str(str(effect["old"])).is_equal(
		(chest.replace_options_for(offers[0])[0] as Ability).describe()
	)
	assert_str(str(effect["new"])).is_equal((offers[0] as Ability).describe())


## A longer cooldown is a loss and more damage is a gain, and the card has to colour them that
## way round: cooldown is the one number on either card where down is up.
func test_a_longer_cooldown_reads_as_a_loss_and_more_damage_as_a_gain() -> void:
	var slow := UiFakes.make_active("whirlwind", "Whirlwind", 8.0)
	var quick := UiFakes.make_active("fireball", "Fireball", 6.0)
	var roles: Dictionary = {}
	for row: Dictionary in AbilityCard.all_swap_rows(slow, quick):
		roles[str(row["label"])] = StringName(str(row["role"]))
	assert_that(roles.get(AbilityCard.COOLDOWN_LABEL)).is_equal(&"danger")
	assert_that(roles.get(AbilityCard.DAMAGE_LABEL)).is_equal(&"heal")
	# ... and the other direction, so the test cannot pass on a constant.
	roles = {}
	for row: Dictionary in AbilityCard.all_swap_rows(quick, slow):
		roles[str(row["label"])] = StringName(str(row["role"]))
	assert_that(roles.get(AbilityCard.COOLDOWN_LABEL)).is_equal(&"heal")
	assert_that(roles.get(AbilityCard.DAMAGE_LABEL)).is_equal(&"danger")


## Two rule-shaped passives share no number, and the card says nothing rather than inventing a
## row. A tier change is a number they do share.
func test_two_passives_with_no_shared_number_print_no_comparison() -> void:
	var thorns := UiFakes.make_passive("thorns", "Thorns", "Reflect melee damage.")
	var vampiric := UiFakes.make_passive("vampiric", "Vampiric", "Lifesteal on every hit.")
	assert_array(AbilityCard.all_swap_rows(thorns, vampiric)).is_empty()
	vampiric.tier = 2
	var labels: PackedStringArray = []
	for row: Dictionary in AbilityCard.all_swap_rows(thorns, vampiric):
		labels.append(str(row["label"]))
	assert_array(labels).contains([AbilityCard.TIER_LABEL])


# --------------------------- the card is filled to its pixels (owner report 6, round 2)


## The before/after list used to stop at six rows whatever the card's height was, so a card
## with room for nine printed six and "+3 more". The table carries every row of the model,
## every row both sides touch, and nothing on it ever says "more".
func test_the_trade_table_carries_every_row_uncut() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	chest.show_offers(ChestUi.Kind.ITEM, offers, UiFakes.chest_context(player))
	await get_tree().process_frame
	_press(chest, &"ui_accept")
	await get_tree().process_frame
	var view := chest.compare_view()
	var worn := UiFakes.equipped_for(player, offers[0] as ItemInstance)
	var all := CompareRows.rows_for(worn, offers[0])
	assert_int(CompareRows.stat_rows(all).size()).is_greater(4)
	assert_array(view.rows()).is_equal(all)
	for text: String in view.row_texts():
		assert_str(text).not_contains("more")
	# Every stat the worn weapon has is on the table even when the offer lacks it.
	var labels: PackedStringArray = []
	for row: Dictionary in view.rows():
		labels.append(str(row["label"]))
	for row: Dictionary in ItemCard.stat_totals(worn):
		assert_array(labels).contains([ItemCard.swap_label(StringName(str(row["stat"])))])


## And nothing is cut silently: `ItemCard` hands over every row by default, and the caps that
## used to live in `ChestUi` are gone.
func test_the_before_and_after_list_is_handed_over_uncut() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worn := UiFakes.make_item(rng, ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.WEAPON)
	var offered := UiFakes.make_item(rng, ItemInstance.Rarity.COMMON, ItemBase.Slot.WEAPON)
	var all := ItemCard.all_swap_rows(offered, worn)
	assert_int(all.size()).is_greater(6)
	assert_int(ItemCard.swap_rows(offered, worn).size()).is_equal(all.size())
	assert_int(ItemCard.hidden_swap_rows(offered, worn)).is_equal(0)


## A rule between two blocks draws as a four pixel hairline, not as a line of text, so it may
## not be charged a whole row of the comparison.
func test_a_rule_row_costs_the_budget_no_text_line() -> void:
	var rows: Array[Dictionary] = [
		{"text": "a", "role": &""}, {"text": "", "role": &"rule"}, {"text": "b", "role": &""}
	]
	var fitted := CardFit.fit_rows(rows, 2, 0, func(_t: String) -> int: return 1)
	assert_int(fitted["hidden"]).is_equal(0)
	assert_int((fitted["rows"] as Array).size()).is_equal(3)
	assert_int(CardFit.rule_rows(rows)).is_equal(1)


# ------------------- a full ring family is a choice (owner report 8, round 3)


## A ring offered to a player wearing two has two things it could displace, so the board pages
## them the way an ability replacement already does. It used to hand the trade view one
## candidate - Ring 1, always - so the answer was made for the player and Ring 2 was
## unreachable whatever they pressed.
func test_a_ring_offered_to_two_worn_rings_asks_which_one_goes() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player_two_rings())
	add_child(player)
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	chest.show_offers(ChestUi.Kind.ITEM, offers, UiFakes.chest_context(player))
	await get_tree().process_frame
	var ring := offers[2] as ItemInstance
	assert_int(int(ring.slot())).is_equal(int(ItemBase.Slot.RING))
	var monitor := monitor_signals(chest)
	chest.select(2)
	_press(chest, &"ui_accept")
	await get_tree().process_frame
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.REPLACE)
	(
		assert_str(chest.compare_view().footer())
		. override_failure_message("the board offered no choice of which ring goes")
		. is_equal("Slot 1 of 2")
	)
	assert_str((chest.get_node("%Subtitle") as Label).text).contains("which one goes")
	# ... and moving the selection really turns the page: the card on the left is the other ring.
	var first := chest.compare_view().out_title()
	_press(chest, &"ui_right")
	await get_tree().process_frame
	var second := chest.compare_view().out_title()
	assert_str(second).is_not_equal(first)
	assert_str(second).is_equal(player.equipment.slots["ring_2"].display_name)
	_press(chest, &"ui_accept")
	await assert_signal(monitor).is_emitted("chosen", [ring, 1, -1])


## A cursed board asks two questions and they are about two different slots: the prize is
## gear, the price is a passive. The board used to put only the second one and let the first
## answer itself - `Player.equip` filled Ring 1 - so the ring a player was wearing vanished
## behind a card whose only warning was about their passives.
func test_a_cursed_prize_asks_for_the_ring_and_then_for_the_passive() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player_two_rings())
	add_child(player)
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	var ring := offers[2] as ItemInstance
	var curse := UiFakes.make_passive("curse_1", "Glass Jaw", "Take 30% more damage.")
	var passives: Array = player.ability_slots.passives.duplicate()
	var context := UiFakes.chest_context(player)
	context["price_offer"] = curse
	context["price_replace"] = func(_offer: Variant) -> Array: return passives
	chest.show_offers(ChestUi.Kind.CURSED, [ring], context)
	await get_tree().process_frame
	var monitor := monitor_signals(chest)

	# First: which ring comes off. Both are candidates, so the page turns to the second.
	chest.select(0)
	_press(chest, &"ui_accept")
	await get_tree().process_frame
	assert_int(chest.replace_step()).is_equal(ChestUi.Step.OFFER)
	assert_str((chest.get_node("%Subtitle") as Label).text).contains("ring")
	assert_str(chest.compare_view().in_title()).is_equal(ring.display_name)
	_press(chest, &"ui_right")
	await get_tree().process_frame
	_press(chest, &"ui_accept")
	await get_tree().process_frame

	# Nothing is taken yet: the price is the second half of the same trade, and the card on the
	# right is the Curse itself - the thing that is about to sit in the slot on the left.
	await assert_signal(monitor).wait_until(100).is_not_emitted("chosen")
	assert_bool(chest.is_open()).is_true()
	assert_int(chest.replace_step()).is_equal(ChestUi.Step.PRICE)
	assert_str((chest.get_node("%Subtitle") as Label).text).contains("passive")
	assert_str(chest.compare_view().in_title()).is_equal(curse.display_name)
	assert_str(chest.compare_view().out_title()).is_equal(passives[0].display_name)
	_press(chest, &"ui_accept")
	await assert_signal(monitor).is_emitted("chosen", [ring, 1, 0])


## And backing out of the second question takes the whole trade with it: a player who says no
## to the price has not agreed to the prize either.
func test_leaving_the_price_question_leaves_the_whole_trade() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player_two_rings())
	add_child(player)
	var ring := UiFakes.make_offers(ChestUi.Kind.ITEM)[2] as ItemInstance
	var curse := UiFakes.make_passive("curse_1", "Glass Jaw", "Take 30% more damage.")
	var passives: Array = player.ability_slots.passives.duplicate()
	var context := UiFakes.chest_context(player)
	context["price_offer"] = curse
	context["price_replace"] = func(_offer: Variant) -> Array: return passives
	chest.show_offers(ChestUi.Kind.CURSED, [ring], context)
	await get_tree().process_frame
	var monitor := monitor_signals(chest)
	_press(chest, &"ui_accept")
	await get_tree().process_frame
	_press(chest, &"ui_accept")
	await get_tree().process_frame
	assert_int(chest.replace_step()).is_equal(ChestUi.Step.PRICE)
	_press(chest, &"ui_cancel")
	await get_tree().process_frame
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.OFFERS)
	assert_int(chest.replace_step()).is_equal(ChestUi.Step.OFFER)
	assert_bool(chest.offers_visible()).is_true()
	await assert_signal(monitor).wait_until(100).is_not_emitted("chosen")


# --------------- a card fills its height before it cuts anything (owner report 6, round 4)


## Cards that truncate something with more than one body line of empty space under the last
## row they drew, with the gap measured in native pixels. `tag` names the board.
func _crowded_cards(chest: ChestUi, tag: String, out: PackedStringArray) -> void:
	for i in chest.card_count():
		_measure_gap(chest._cards[i], "%s card %d" % [tag, i], out)


func _measure_gap(card: PanelContainer, tag: String, out: PackedStringArray) -> void:
	var frame := card.get_child(0) as Control
	var box := frame.get_child(0) as VBoxContainer
	var gap := frame.custom_minimum_size.y - box.get_combined_minimum_size().y
	var cut := 0
	for child: Node in box.get_children():
		var label := child as Label
		# The head block (index 0 is the head row) and the shop's price line are not body rows;
		# a price label carries no line budget (`max_lines_visible` 0) and cuts nothing.
		if label == null or label.get_index() == 0 or label.max_lines_visible <= 0:
			continue
		if label.get_line_count() > label.max_lines_visible or label.text.ends_with(" more"):
			cut += 1
	if cut > 0 and gap >= UiTheme.body_font().get_height(UiTheme.SIZE_S):
		out.append("%s: %d rows cut with %.0f px of empty body under them" % [tag, cut, gap])
	if gap < 0.0:
		out.append("%s: content overflows the card by %.0f px" % [tag, -gap])


## The round before this one stopped *dropping* the row a card ran out of room on and started
## ellipsising it instead. That made the cut visible without making the card use its own
## height: a verifier measured a card hiding rows behind an ellipsis with more than twenty
## native pixels of empty body below the cut.
##
## Everything a card is laid out by counts in whole font heights - the height it asks for, the
## line budget its body is filled to, the head block its title has to fit inside - and four
## separate things were not: the card's stylebox padding (measured as 6 px, drawn as 5), the
## theme's leading inside a wrapped Label, the head block measured before it had been laid out,
## and the line `fit_rows` holds back for a "+N more" row it then turns out not to need.
##
## So this is the measurement rather than a description of it, over the boards the game really
## builds: a card that cuts anything has to have less than one body line of daylight under its
## last row, and no card may overflow its own frame either.
func test_no_card_cuts_a_row_while_its_body_still_has_room() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var context := UiFakes.chest_context(player)
	var shop := UiFakes.shop_context(player)
	var items := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	var crowded: PackedStringArray = []
	for count: int in [3, 4]:
		for seed_index in range(GAP_SEEDS):
			rng.seed = 1000 + seed_index
			var offers: Array = []
			for _card in range(count):
				var item := ItemGenerator.generate(items, 1 + (seed_index % 8), rng, 0.0, [], -1)
				if item != null:
					offers.append(item)
			if offers.size() < count:
				continue
			chest.show_offers(ChestUi.Kind.ITEM, offers, context)
			await get_tree().process_frame
			await get_tree().process_frame
			_crowded_cards(chest, "%d-card board, seed %d" % [count, seed_index], crowded)
			# The shop counter draws the same cards with a price row under them, which is the
			# one thing on a card whose height the body budget has to leave alone.
			if count != 3:
				continue
			chest.show_offers(ChestUi.Kind.ITEM, offers, shop)
			await get_tree().process_frame
			await get_tree().process_frame
			_crowded_cards(chest, "shop counter, seed %d" % seed_index, crowded)
	(
		assert_array(crowded)
		. override_failure_message("cards cut content with room to spare: %s" % crowded)
		. is_empty()
	)


## The compare screen never cuts: over real generated trades, every row of the model is on the
## table, and a table taller than its frame scrolls (and says so) rather than eliding.
func test_no_trade_table_elides_a_row_whatever_the_gear() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player_two_rings())
	add_child(player)
	var context := UiFakes.chest_context(player)
	var items := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	var crowded: PackedStringArray = []
	for seed_index in range(GAP_SEEDS):
		rng.seed = 2000 + seed_index
		var offers: Array = []
		for _card in range(3):
			var item := ItemGenerator.generate(items, 6, rng, 0.0, [], -1)
			if item != null:
				offers.append(item)
		if offers.size() < 3:
			continue
		chest.show_offers(ChestUi.Kind.ITEM, offers, context)
		await get_tree().process_frame
		for i in chest.card_count():
			chest.select(i)
			chest.activate()
			await get_tree().process_frame
			await get_tree().process_frame
			if chest.selected_row() != ChestUi.Row.REPLACE:
				continue
			var tag := "trade view, seed %d, card %d" % [seed_index, i]
			var view := chest.compare_view()
			var model := CompareRows.rows_for(chest.replace_options_for(offers[i])[0], offers[i])
			if view.rows() != model:
				crowded.append("%s: the table is not the whole model" % tag)
			for text: String in view.row_texts():
				if text.contains("more"):
					crowded.append("%s: '%s' elides" % [tag, text])
			if view.is_scrollable() and not _hint_of(chest).contains("scroll"):
				crowded.append("%s: scrolls without saying so" % tag)
			_press(chest, &"ui_cancel")
			await get_tree().process_frame
	(
		assert_array(crowded)
		. override_failure_message("the trade table cut or hid content: %s" % crowded)
		. is_empty()
	)


func _hint_of(chest: ChestUi) -> String:
	return (chest.get_node("%Hint") as UiPrompt).plain()


## The row of a compare table carrying `label`, or an empty dictionary.
static func _row_named(rows: Array[Dictionary], label: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row["label"]) == label:
			return row
	return {}


## A sword, a jerkin and a ring have to be three different pictures on the board - that is the
## whole job of an icon. The fakes used to wear one rarity gem in three hues, so the gallery,
## the surface a reviewer asks "are these distinct?" on, could not answer; and the board read
## `item.base.icon`, which rings and trinkets do not author, so a real ring drew an empty box.
func test_every_item_card_carries_its_own_picture() -> void:
	var chest := _chest()
	await _item_board(chest)
	var seen: Array[PackedByteArray] = []
	for i in chest.card_count():
		var item := chest.offers[i] as ItemInstance
		var texture := _card_icon(chest._cards[i])
		(
			assert_object(texture)
			. override_failure_message("%s drew no icon at all" % item.display_name)
			. is_not_null()
		)
		var pixels := texture.get_image().get_data()
		for other: PackedByteArray in seen:
			(
				assert_bool(pixels == other)
				. override_failure_message(
					"%s is drawn with the same picture as another offer" % item.display_name
				)
				. is_false()
			)
		seen.append(pixels)


## The icon TextureRect of a card, first child of the head block.
func _card_icon(card: PanelContainer) -> Texture2D:
	var frame := card.get_child(0) as Control
	var box := frame.get_child(0) as VBoxContainer
	var head := box.get_child(0) as HBoxContainer
	return (head.get_child(0) as TextureRect).texture


## The same promise the trade card keeps, on the board a player actually meets first. A
## four-card board printed "+1 MORE" with two body lines still blank inside the same card:
## the claim "the card cuts where the pixels run out" was only ever tested on the swap card.
func test_every_offer_card_is_filled_to_the_room_it_has() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	offers.append(UiFakes.make_offers(ChestUi.Kind.STAT)[0])
	var context := UiFakes.chest_context(player)
	context["extra_option"] = true
	chest.show_offers(ChestUi.Kind.ITEM, offers, context)
	await get_tree().process_frame
	var line := UiTheme.body_font().get_height(UiTheme.SIZE_S)
	for i in chest.card_count():
		var card := chest._cards[i]
		var texts := _body_texts(card)
		var hides := false
		for text: String in texts:
			if text.begins_with("+") and text.ends_with("more"):
				hides = true
		if not hides:
			continue
		var frame := card.get_child(0) as Control
		var box := frame.get_child(0) as VBoxContainer
		var slack := frame.custom_minimum_size.y - box.get_combined_minimum_size().y
		(
			assert_float(slack)
			. override_failure_message(
				(
					"card %d hides rows behind '+N more' with %.0f px (%.1f lines) still free"
					% [i, slack, slack / line]
				)
			)
			. is_less(line)
		)
