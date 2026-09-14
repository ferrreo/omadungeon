## The floor tooltip (owner report 9, round 5: "when there is an item on the floor its tooltip
## always shows and blocks half the screen"). Near a drop the HUD shows a tag; standing on it,
## a compare card on the left edge of the screen that never covers the player and never more
## than a quarter of the frame.
class_name ItemTooltipTest
extends GdUnitTestSuite

const VIEW := Vector2(480, 270)


func _tooltip() -> ItemTooltip:
	var tooltip: ItemTooltip = auto_free(ItemTooltip.new())
	add_child(tooltip)
	tooltip.size = VIEW
	return tooltip


func _drop() -> Node2D:
	var drop: Node2D = auto_free(Node2D.new())
	add_child(drop)
	drop.position = Vector2(200, 120)
	return drop


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_near_a_drop_only_the_tag_shows_and_nothing_is_compared() -> void:
	var tooltip := _tooltip()
	var item := UiFakes.make_item(_rng(1), ItemInstance.Rarity.RARE, ItemBase.Slot.RING)
	tooltip.show_item(_drop(), item, ItemTooltip.Level.NEAR, null, null)
	assert_bool(tooltip.visible).is_true()
	assert_int(tooltip.level).is_equal(ItemTooltip.Level.NEAR)
	assert_array(tooltip.rows).is_empty()
	assert_that(tooltip.card_size()).is_equal(Vector2.ZERO)


func test_standing_on_a_drop_builds_the_compare_card_against_the_worn_gear() -> void:
	var tooltip := _tooltip()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var gear := UiFakes.worn_gear(player)
	var offered := UiFakes.make_offers(ChestUi.Kind.ITEM)[0] as ItemInstance
	tooltip.show_item(_drop(), offered, ItemTooltip.Level.CLOSE, gear, player.stats)
	assert_int(tooltip.level).is_equal(ItemTooltip.Level.CLOSE)
	assert_array(tooltip.rows).is_not_empty()
	var labels: PackedStringArray = []
	for row: Dictionary in tooltip.rows:
		labels.append(str(row["label"]))
	assert_array(labels).contains(["Damage", "Dps"])
	# The same rows the compare screen would print for this pair.
	var worn := gear.get_item(gear.target_slot(offered))
	var model := CompareRows.stat_rows(CompareRows.rows_for(worn, offered))
	assert_array(tooltip.rows).is_equal(ItemTooltip.fit_rows(model, model.size()))


## The card is capped: never more than a quarter of the frame, whatever the item carries.
func test_the_card_never_exceeds_a_quarter_of_the_screen() -> void:
	var tooltip := _tooltip()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var gear := UiFakes.worn_gear(player)
	var items := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	for seed_index in range(16):
		rng.seed = 5000 + seed_index
		var item := ItemGenerator.generate(items, 9, rng, 0.0, [], -1)
		if item == null:
			continue
		tooltip.show_item(_drop(), item, ItemTooltip.Level.CLOSE, gear, player.stats)
		var card := tooltip.card_size()
		(
			assert_bool(ItemTooltip.within_budget(card, VIEW))
			. override_failure_message(
				"%s: card %s is over a quarter of %s" % [item.display_name, card, VIEW]
			)
			. is_true()
		)
		assert_float(card.y).is_less_equal(tooltip.max_height(card.x))
		# Against the *screen*, not against `ItemTooltip.MAX_WIDTH`. Measuring production's own
		# output against production's own constant passes whatever that constant happens to
		# say: proven by mutation, doubling MAX_WIDTH to 336 left this whole suite green. Half
		# the frame is the widest a card beside the player can be without becoming the screen.
		(
			assert_float(card.x)
			. override_failure_message(
				(
					"%s: card is %.0f px wide, over half of the %.0f px frame"
					% [item.display_name, card.x, VIEW.x]
				)
			)
			. is_less_equal(VIEW.x * 0.5)
		)


## The card sits on the left edge, inside the band between the HP block and the ability bar,
## and never over the centre of the screen, which is where the player standing on the drop is.
func test_the_card_sits_on_the_left_edge_beside_the_player() -> void:
	var tooltip := _tooltip()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var offered := UiFakes.make_item(_rng(9), ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.WEAPON)
	tooltip.set_band(52.0, VIEW.y - 46.0)
	tooltip.show_item(_drop(), offered, ItemTooltip.Level.CLOSE, UiFakes.worn_gear(player), null)
	var rect := tooltip.card_rect()
	assert_float(rect.position.x).is_equal(ItemTooltip.EDGE_GAP)
	assert_float(rect.position.y).is_greater_equal(52.0)
	assert_float(rect.end.y).is_less_equal(VIEW.y - 46.0)
	# The player sprite is 16 px around the centre: the card ends well before it.
	var player_box := Rect2(VIEW * 0.5 - Vector2(8, 8), Vector2(16, 16))
	assert_bool(rect.intersects(player_box)).is_false()
	assert_bool(ItemTooltip.within_budget(rect.size, VIEW)).is_true()


## Every stat row of a real trade is on the card: with the HUD's band nothing is cut, and the
## values are the compare screen's own.
func test_the_card_carries_every_row_of_the_trade_with_the_hud_band() -> void:
	var tooltip := _tooltip()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var gear := UiFakes.worn_gear(player)
	var items := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	tooltip.set_band(52.0, VIEW.y - 46.0)
	for seed_index in range(24):
		rng.seed = 7000 + seed_index
		var item := ItemGenerator.generate(items, 9, rng, 0.0, [], -1)
		if item == null:
			continue
		tooltip.show_item(_drop(), item, ItemTooltip.Level.CLOSE, gear, player.stats)
		var worn := gear.get_item(gear.target_slot(item))
		var model := CompareRows.stat_rows(CompareRows.rows_for(worn, item))
		(
			assert_int(tooltip.rows.size())
			. override_failure_message(
				"%s: %d of %d rows shown" % [item.display_name, tooltip.rows.size(), model.size()]
			)
			. is_equal(model.size())
		)
		assert_bool(ItemTooltip.within_budget(tooltip.card_size(), VIEW)).is_true()


## Leaving the drop hides everything, and a stale "left" from another drop is ignored by the
## HUD (the tooltip only ever shows one).
func test_leaving_hides_and_fit_rows_drops_unchanged_rows_first() -> void:
	var tooltip := _tooltip()
	var item := UiFakes.make_item(_rng(1), ItemInstance.Rarity.RARE, ItemBase.Slot.RING)
	tooltip.show_item(_drop(), item, ItemTooltip.Level.NEAR, null, null)
	tooltip.hide_item()
	assert_bool(tooltip.visible).is_false()
	assert_int(tooltip.level).is_equal(ItemTooltip.Level.NONE)
	var rows: Array[Dictionary] = [
		CompareRows.stat("A", "1", "1", CompareRows.ROLE_SAME),
		CompareRows.stat("B", "1", "2", CompareRows.ROLE_UP),
		CompareRows.stat("C", "2", "1", CompareRows.ROLE_DOWN),
	]
	var kept := ItemTooltip.fit_rows(rows, 2)
	assert_int(kept.size()).is_equal(2)
	assert_str(str(kept[0]["label"])).is_equal("B")
	assert_str(str(kept[1]["label"])).is_equal("C")


## The HUD wires the bus to the widget: a hover reaches the tooltip with the bound player's
## gear, and an equip on the same drop rebuilds it.
func test_the_hud_routes_hover_events_to_its_tooltip() -> void:
	var hud: Hud = auto_free((load("res://src/ui/hud.tscn") as PackedScene).instantiate())
	add_child(hud)
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	hud.bind(player)
	var drop := _drop()
	var item := UiFakes.make_offers(ChestUi.Kind.ITEM)[2] as ItemInstance
	EventBus.item_hover.emit(drop, item, ItemTooltip.Level.NEAR)
	assert_bool(hud.item_tooltip().visible).is_true()
	assert_int(hud.item_tooltip().level).is_equal(ItemTooltip.Level.NEAR)
	EventBus.item_hover.emit(drop, item, ItemTooltip.Level.CLOSE)
	assert_int(hud.item_tooltip().level).is_equal(ItemTooltip.Level.CLOSE)
	# Another drop saying "left" does not take this one's tooltip down.
	EventBus.item_hover.emit(_drop(), item, ItemTooltip.Level.NONE)
	assert_bool(hud.item_tooltip().visible).is_true()
	EventBus.item_hover.emit(drop, item, ItemTooltip.Level.NONE)
	assert_bool(hud.item_tooltip().visible).is_false()
