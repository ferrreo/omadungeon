## The trade view - the swap step of an offer board (`CompareView` inside `ChestUi`). Its job is
## to make "what goes, what arrives" answerable by looking, and a ring family gives it two
## pages to do that on. Both cases here are pages that said something untrue: a second page
## carrying the first ring's trade, and a back key promising to keep something it was about to
## throw away with everything else.
class_name TradeViewTest
extends GdUnitTestSuite

const SCENE := "res://src/ui/chest_ui.tscn"


## The picker frees its cards with `queue_free()`, and every page turn builds a new pair, so a
## case that ends on the frame it drew them leaves the whole board behind as orphans.
func after_test() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _chest() -> ChestUi:
	var chest: ChestUi = auto_free((load(SCENE) as PackedScene).instantiate())
	add_child(chest)
	return chest


## The trade view's second page showed the *first* ring's trade under the second ring. The
## outgoing card asked the board what it would displace, and `Equipment.worn_for()` answers
## that question about the incoming item's slot - Ring 1, whichever ring is on screen - so the
## player was shown one ring, read another ring's before/after numbers, and gave up a third
## thing. The card on the left is already worn: it is described on its own terms or not at all.
func test_the_trade_views_second_page_describes_the_ring_it_shows() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player_two_rings())
	add_child(player)
	var worn_one := player.equipment.slots["ring_1"] as ItemInstance
	var worn_two := player.equipment.slots["ring_2"] as ItemInstance
	worn_one.display_name = "Band of Alpha"
	worn_two.display_name = "Band of Omega"
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	var offered := offers[2] as ItemInstance
	assert_int(int(offered.slot())).is_equal(int(ItemBase.Slot.RING))
	chest.show_offers(ChestUi.Kind.ITEM, offers, UiFakes.chest_context(player))
	chest.select(2)
	chest.activate()
	assert_int(chest.selected_row()).is_equal(ChestUi.Row.REPLACE)
	var swap := chest.compare_view()

	# Page one: the first ring, and the table measured against it.
	assert_str(swap.footer()).is_equal("Slot 1 of 2")
	assert_str(swap.out_title()).is_equal("Band of Alpha")
	assert_array(swap.rows()).is_equal(CompareRows.rows_for(worn_one, offered))

	# Page two: the second ring, with nothing of the first one's on it, and the table now
	# measured against the ring that is actually coming off.
	chest.select(1)
	assert_str(swap.footer()).is_equal("Slot 2 of 2")
	assert_str(swap.out_title()).is_equal("Band of Omega")
	assert_str("\n".join(swap.row_texts())).not_contains("Band of Alpha")
	assert_array(swap.rows()).is_equal(CompareRows.rows_for(worn_two, offered))


## The price step's back key cancels the whole trade, prize included (`_cancel_replace`), and
## the hint offered to "keep mine" - a promise about the passive the player was looking at,
## while the ring they had already answered for went back on the board with it.
func test_the_price_step_says_the_back_key_cancels_the_whole_trade() -> void:
	var chest := _chest()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player_two_rings())
	add_child(player)
	var curse := UiFakes.make_passive("kernel_panic", "Kernel Panic", "Everything is worse.")
	var passives: Array = player.ability_slots.passives.duplicate()
	var context := UiFakes.chest_context(player)
	context["curse_text"] = "Curse: Kernel Panic (takes a passive slot)"
	context["price_offer"] = curse
	context["price_replace"] = func(_offer: Variant) -> Array: return passives
	var offers := UiFakes.make_offers(ChestUi.Kind.ITEM)
	chest.show_offers(ChestUi.Kind.CURSED, offers, context)
	chest.select(2)
	chest.activate()

	# The offer's own question first: the curse is stated as the trade's note, not as a row of
	# the ring being given up, and the way out still keeps what the player has.
	assert_int(chest.replace_step()).is_equal(ChestUi.Step.OFFER)
	assert_str(chest.compare_view().note()).contains("Curse:")
	assert_str("\n".join(chest.compare_view().row_texts())).not_contains("Curse:")
	assert_str(_hint(chest)).contains(CompareView.KEEP_VERB)

	# Answering it puts the price question up, where the same key now drops everything.
	chest.activate()
	assert_int(chest.replace_step()).is_equal(ChestUi.Step.PRICE)
	assert_str(chest.compare_view().note()).is_empty()
	assert_str(_hint(chest)).contains(CompareView.CANCEL_ALL_VERB)
	assert_str(_hint(chest)).not_contains(CompareView.KEEP_VERB)


func test_swap_hint_names_what_the_back_key_does() -> void:
	var pad := InputGlyphs.Device.GAMEPAD
	var kb := InputGlyphs.Device.KEYBOARD
	var esc := InputGlyphs.binding_name(&"ui_cancel", kb)
	assert_str(_plain(CompareView.hint_text(true, 2), pad)).contains("B %s" % CompareView.KEEP_VERB)
	assert_str(_plain(CompareView.hint_text(true, 2, true), pad)).contains(
		"B %s" % CompareView.CANCEL_ALL_VERB
	)
	assert_str(_plain(CompareView.hint_text(false, 1, true), kb)).contains(
		"%s %s" % [esc, CompareView.CANCEL_ALL_VERB]
	)
	assert_str(_plain(CompareView.hint_text(false, 1, false), kb)).contains(
		"%s %s" % [esc, CompareView.KEEP_VERB]
	)


## `markup` spelled out for `device`, which is how a test reads a prompt that draws glyphs.
static func _plain(markup: String, device: int) -> String:
	return UiPrompt.render_plain(markup, device)


func _hint(chest: ChestUi) -> String:
	return (chest.get_node("%Hint") as UiPrompt).plain()
