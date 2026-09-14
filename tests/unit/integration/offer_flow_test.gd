## The offer flow as a player meets it (docs §8): one board at a time, the run frozen behind it,
## every source still itself after a reroll, and no cost charged for something that cannot
## happen. Every case here reproduces a playtest finding that a green suite did not see, because
## each of them is about what the player ends up holding, not about a function returning.
class_name OfferFlowIntegrationTest
extends GdUnitTestSuite

const SEED := 20250913


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	# The docs §2 passive pick has its own suite; it would sit over every chest opened here.
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	get_tree().paused = false
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


# ---------------------------------------------------------------- modality


func test_an_open_offer_freezes_the_run_and_the_players_input() -> void:
	var live := await _start()
	assert_bool(get_tree().paused).is_false()
	assert_bool(live.input_enabled).is_true()
	var chest := await _add_chest(Chest.Kind.GOLD)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)

	# The cards are up: the player cannot walk, dodge or attack behind them, and the key that
	# confirms a card (ui_accept shares Space and gamepad A with `dodge`) cannot also roll.
	assert_bool(_ui().is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(live.input_enabled).is_false()

	_ui().select(0)
	_ui().activate()
	await _frames(4)
	assert_bool(get_tree().paused).is_false()
	assert_bool(live.input_enabled).is_true()


func test_a_second_interactable_cannot_eat_the_first_ones_reward() -> void:
	var live := await _start()
	var first := await _add_chest(Chest.Kind.GOLD)
	var second := await _add_chest(Chest.Kind.GOLD)
	assert_bool(first.interact(live)).is_true()
	await _frames(4)
	var offers := _ui().offers.duplicate()

	# Both chests are in reach. The second one is refused outright instead of consuming itself.
	assert_bool(second.interact(live)).is_false()
	await _frames(4)
	assert_bool(second.is_opened).is_false()
	assert_bool(second.enabled).is_true()
	assert_array(_ui().offers).is_equal(offers)

	var gold := live.gold
	_ui().select(0)
	_ui().activate()
	await _frames(4)
	# The first chest still paid out, and the second is still there to open.
	assert_int(live.gold).is_greater(gold)
	assert_bool(second.can_interact()).is_true()


# ---------------------------------------------------------------- shrines (docs §8)


func test_a_shrine_cannot_be_rerolled_into_something_else() -> void:
	var live := await _start()
	var shrine := await _add_shrine()
	assert_bool(shrine.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var before := ui.offers.duplicate()
	var gold := live.gold
	var max_hp := live.stats.get_value(&"max_hp")

	# The shrine's menu is the shrine's: there is no reroll button, and asking for one anyway
	# (a stale signal, a rebound key) changes nothing.
	assert_bool(bool(ui.context.get("can_reroll", true))).is_false()
	assert_bool((ui.get_node("%Reroll") as Button).visible).is_false()
	ui.rerolled.emit()
	await _frames(4)
	assert_array(ui.offers).is_equal(before)
	assert_int(live.gold).is_equal(gold)

	# ... and the cards still line up with the options, so card N charges card N's price.
	var index := _offer_index_for_cost_kind(&"max_hp")
	assert_int(index).is_greater_equal(0)
	var option := shrine.options[index]
	var buff := StringName(str(option["buff"]))
	var before_buff := live.stats.primary(buff)
	ui.select(index)
	ui.activate()
	await _frames(4)
	assert_float(live.stats.get_value(&"max_hp")).is_equal(max_hp - float(option["cost"]))
	assert_int(live.stats.primary(buff)).is_equal(before_buff + int(option["amount"]))


func test_cleansing_nothing_costs_nothing() -> void:
	var live := await _start()
	assert_int(ChestOffers.curse_slot_index(live.ability_slots as AbilitySlots)).is_equal(-1)
	var shrine := await _add_shrine()
	assert_bool(shrine.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var index := _offer_index_for_stat(&"cleanse")
	assert_int(index).is_greater_equal(0)

	# The card says why it is refused instead of charging 25 HP (19% of a Fighter) for nothing.
	assert_bool(ui.can_pick(index)).is_false()
	var texts: Array = []
	for note: Dictionary in ui.describe_offer(ui.offers[index])["notes"] as Array:
		texts.append(str(note["text"]))
	assert_array(texts).contains(["No curse to cleanse"])

	var hp := live.health.hp
	ui.select(index)
	ui.activate()
	await _frames(4)
	assert_float(live.health.hp).is_equal(hp)
	assert_bool(ui.is_open()).is_true()
	assert_bool(shrine.used).is_false()


# ------------------------------------------------- harmless exits (docs §5.1, §8)


## A button that reads like a harmless exit has to be one. The Altar's read "Skip (+10g)": it
## paid nothing, and it destroyed the floor's one guaranteed Altar (docs §5.1) - up to nine
## ability picks over a run, and the loss survived a resume.
func test_leaving_an_altar_costs_nothing_and_keeps_it() -> void:
	var live := await _start()
	var altar := await _add_altar()
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var gold := live.gold
	# Nothing is promised, because nothing is paid.
	assert_int(int(ui.context.get("skip_gold", -1))).is_equal(0)
	assert_str((ui.get_node("%Skip") as Button).text).is_equal("Leave")

	_press_skip(ui)
	await _frames(4)
	assert_bool(ui.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(live.gold).is_equal(gold)
	# The altar is still standing, and still hands out an ability when it is actually used.
	assert_bool(altar.used).is_false()
	assert_bool(altar.can_interact()).is_true()
	var slots := live.ability_slots as AbilitySlots
	var carried := _loadout_weight(slots)
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	_ui().select(0)
	_ui().activate()
	await _frames(4)
	# A new ability or a tier on one already held - either way the prayer was answered.
	assert_int(_loadout_weight(slots)).is_greater(carried)
	assert_bool(altar.used).is_true()


## Leaving an altar keeps the altar - which must not turn "leave and pray again" into the
## free reroll the Reroll button charges 25g for. The board an altar was left on is its board
## until it is spent.
func test_praying_again_at_an_altar_shows_the_board_it_was_left_on() -> void:
	var live := await _start()
	live.add_gold(500)
	var altar := await _add_altar()
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var board := ui.offers.duplicate()
	assert_array(board).is_not_empty()

	_press_skip(ui)
	await _frames(4)
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	assert_array(_ui().offers).is_equal(board)

	# Paying for a reroll still changes them, and the new board is the one that is kept.
	var gold := live.gold
	_ui().rerolled.emit()
	await _frames(4)
	var rerolled := _ui().offers.duplicate()
	assert_int(live.gold).is_less(gold)
	_press_skip(_ui())
	await _frames(4)
	assert_bool(altar.interact(live)).is_true()
	await _frames(4)
	assert_array(_ui().offers).is_equal(rerolled)


## The Shrine's button said "Leave" - the Shop's word for a genuine back-out - and spent the
## shrine, which is the only way to lift a Curse (docs §8). Two buttons with the same caption
## may not have opposite consequences.
func test_leaving_a_shrine_costs_nothing_and_keeps_it() -> void:
	var live := await _start()
	var shrine := await _add_shrine()
	assert_bool(shrine.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var gold := live.gold
	var hp := live.health.hp
	assert_str((ui.get_node("%Skip") as Button).text).is_equal("Leave")

	_press_skip(ui)
	await _frames(4)
	assert_bool(ui.is_open()).is_false()
	assert_int(live.gold).is_equal(gold)
	assert_float(live.health.hp).is_equal(hp)
	assert_bool(shrine.used).is_false()
	assert_bool(shrine.can_interact()).is_true()

	# ... and kneeling at it afterwards still works and still spends it.
	assert_bool(shrine.interact(live)).is_true()
	await _frames(4)
	var index := _offer_index_for_cost_kind(&"max_hp")
	assert_int(index).is_greater_equal(0)
	_ui().select(index)
	_ui().activate()
	await _frames(4)
	assert_bool(shrine.used).is_true()


## A shop's "Leave" always was harmless; this pins it so the three boards cannot drift apart
## again, and so a counter the player has bought out is a restock offer rather than an empty
## modal captioned "Buy one (you have 99864g)".
func test_a_bought_out_counter_offers_a_restock_not_an_empty_board() -> void:
	var live := await _start()
	live.add_gold(500)
	var shop := await _add_shop(0)
	assert_bool(shop.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	assert_bool(ui.is_open()).is_true()
	assert_int(ui.card_count()).is_equal(0)
	# Nothing to buy: the board says so, and offers the only thing that can help.
	assert_str((ui.get_node("%Subtitle") as Label).text).contains("Sold out")
	assert_str((ui.get_node("%Reroll") as Button).text).contains("Restock")
	assert_str((ui.get_node("%Skip") as Button).text).is_equal("Leave")
	# The selection starts where the only usable controls are.
	assert_int(ui.selected_row()).is_equal(ChestUi.Row.BUTTONS)

	var gold := live.gold
	ui.rerolled.emit()
	await _frames(4)
	assert_int(ui.card_count()).is_greater(0)
	assert_int(live.gold).is_less(gold)
	assert_str((ui.get_node("%Subtitle") as Label).text).contains("Buy one")

	# Leaving a restocked counter leaves it stocked.
	_press_skip(ui)
	await _frames(4)
	assert_bool(ui.is_open()).is_false()
	assert_array(shop.offers).is_not_empty()
	assert_bool(shop.can_interact()).is_true()


## The chest is the one board that is spent by closing it, and the only one that pays for it.
func test_only_a_chest_promises_gold_for_skipping() -> void:
	var live := await _start()
	var chest := await _add_chest(Chest.Kind.STAT)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	assert_int(RunManager.skip_gold()).is_greater(0)
	assert_str((ui.get_node("%Skip") as Button).text).is_equal(
		"Skip (+%dg)" % RunManager.skip_gold()
	)
	var gold := live.gold
	var bonus := RunManager.skip_gold()
	_press_skip(ui)
	await _frames(4)
	# ... and the promise is kept: the gold arrives and the chest is gone.
	assert_int(live.gold).is_equal(gold + bonus)
	assert_bool(chest.is_opened).is_true()
	assert_bool(chest.can_interact()).is_false()


# ---------------------------------------------------------------- economy (docs §8)


func test_a_rerolled_board_pays_no_skip_bonus() -> void:
	var live := await _start()
	live.add_gold(500)
	var chest := await _add_chest(Chest.Kind.STAT)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	assert_int(int(ui.context.get("skip_gold", 0))).is_equal(RunManager.skip_gold())
	assert_int(RunManager.skip_gold()).is_greater(0)

	var gold := live.gold
	var cost := int(ui.context.get("reroll_cost", 0))
	ui.rerolled.emit()
	await _frames(4)
	assert_int(live.gold).is_equal(gold - cost)
	# Reroll-then-skip used to be free money: the skip bonus scales with the floor while the
	# reroll price does not, so from floor 6 you got two boards and a profit.
	assert_int(RunManager.skip_gold()).is_equal(0)
	assert_str((ui.get_node("%Skip") as Button).text).is_equal("Skip")

	gold = live.gold
	ui.skipped.emit()
	await _frames(4)
	assert_int(live.gold).is_equal(gold)


func test_a_board_that_was_not_rerolled_still_pays_the_skip_bonus() -> void:
	var live := await _start()
	var chest := await _add_chest(Chest.Kind.STAT)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var gold := live.gold
	var bonus := RunManager.skip_gold()
	_ui().skipped.emit()
	await _frames(4)
	assert_int(bonus).is_greater(0)
	assert_int(live.gold).is_equal(gold + bonus)


## docs §2: the starting pick happens before the player has earned a single coin, and three of
## the four classes start with `start_gold = 0`. A reroll button they can only ever be refused
## by is not an offer.
func test_the_starting_pick_hides_a_reroll_nobody_can_pay_for() -> void:
	RunManager.offer_starting_passive = true
	var live := await _start()
	var ui := _ui()
	assert_bool(ui.is_open()).is_true()
	assert_int(live.gold).is_equal(0)
	assert_bool(bool(ui.context.get("can_reroll", true))).is_false()
	assert_bool((ui.get_node("%Reroll") as Button).visible).is_false()

	# ... and asking for one anyway cannot spend gold that is not there.
	var offers := ui.offers.duplicate()
	ui.rerolled.emit()
	await _frames(2)
	assert_int(live.gold).is_equal(0)
	assert_array(ui.offers).is_equal(offers)

	# The pick itself still works, and hands the run back when it is made.
	ui.select(0)
	ui.activate()
	await _frames(4)
	assert_bool(ui.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()


# ---------------------------------------------------------------- ability chests (docs §8)


func test_an_ability_chest_offers_the_kind_that_has_a_free_slot() -> void:
	var live := await _start()
	var slots := live.ability_slots as AbilitySlots
	for id: StringName in [&"fireball", &"frost_nova", &"warcry", &"turret"]:
		if slots.is_full(Ability.Kind.ACTIVE):
			break
		var active := RunManager.ability_registry.instance(id)
		if active != null:
			slots.add(active)
	assert_bool(slots.is_full(Ability.Kind.ACTIVE)).is_true()
	assert_bool(slots.is_full(Ability.Kind.PASSIVE)).is_false()
	assert_int(ChestOffers.prefer_kind_for(slots)).is_equal(int(Ability.Kind.PASSIVE))

	var chest := await _add_chest(Chest.Kind.ABILITY)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var passives := 0
	for offer: Variant in _ui().offers:
		if offer is PassiveAbility:
			passives += 1
	# Three actives against two full active slots is three cards that all cost you something.
	assert_int(_ui().offers.size()).is_greater(0)
	assert_int(passives).is_greater(0)


# ---------------------------------------------------------------- the item card (docs §4.5)


func test_the_live_item_card_compares_the_weapon_it_would_replace() -> void:
	var live := await _start()
	var worn := (live.equipment as Equipment).get_item(&"weapon")
	assert_object(worn).is_not_null()
	var chest := await _add_chest(Chest.Kind.ITEM)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var offered := ItemGenerator.generate(
		RunManager.item_registry, 3, rng, 0.0, [int(ItemBase.Slot.WEAPON)]
	)
	assert_object(offered).is_not_null()

	var info := _ui().describe_offer(offered)
	var weapon := offered.base as WeaponBase
	# The card states the offered weapon's own numbers ...
	assert_array(info["lines"]).contains(ItemCard.weapon_lines(weapon))
	# ... and, separately, what each of them is now and what it would become, under a heading
	# naming the weapon that would come off.
	var texts: Array = []
	for row: Dictionary in info["rows"] as Array:
		texts.append(str(row["text"]))
	assert_array(texts).contains([ItemCard.compare_header(ItemCard.worn_name(worn))])
	for row: Dictionary in ItemCard.swap_rows(offered, worn):
		assert_array(texts).contains([ItemCard.swap_text(row)])


# ------------------------------------------------- taking gear is a trade (owner report 6)


## Taking a weapon out of a chest used to swap in silence: the card named what it would
## replace and one press took it, with the old sword gone before the player had seen the two
## side by side. A real chest, a real weapon and the real equipment, driven the way a player
## drives it - the offer opens the trade, and only the second press spends it.
func test_taking_a_weapon_shows_the_trade_before_it_happens() -> void:
	var live := await _start()
	var gear := live.equipment as Equipment
	var worn := gear.get_item(&"weapon")
	assert_object(worn).is_not_null()
	var chest := await _add_chest(Chest.Kind.ITEM)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var index := _first_offer_for_a_filled_slot(ui, gear)
	(
		assert_int(index)
		. override_failure_message("no card on this board displaces gear")
		. is_greater_equal(0)
	)
	var offered := ui.offers[index] as ItemInstance
	var displaced := gear.get_item(gear.target_slot(offered))
	ui.select(index)
	ui.activate()
	await _frames(4)

	# The trade is up, nothing has been equipped, and both halves are on screen.
	assert_int(ui.selected_row()).is_equal(ChestUi.Row.REPLACE)
	assert_bool(ui.offers_visible()).is_false()
	assert_object(gear.get_item(gear.target_slot(offered))).is_same(displaced)
	var swap := ui.compare_view()
	assert_object(swap.out_head).is_not_null()
	assert_object(swap.in_head).is_not_null()
	assert_str((ui.get_node("%Subtitle") as Label).text).contains(
		CompareView.item_slot_name(displaced)
	)

	# Backing out keeps what the player had; the card is still on the board. Driven with the
	# real B button through the real InputMap, because "the pad can leave this dialog" is the
	# half of the question a direct call cannot answer.
	await _pad_press(JOY_BUTTON_B)
	await _frames(2)
	assert_object(gear.get_item(gear.target_slot(offered))).is_same(displaced)
	assert_bool(ui.offers_visible()).is_true()

	# Going through with it is what equips.
	ui.select(index)
	ui.activate()
	await _frames(2)
	ui.activate()
	await _frames(4)
	assert_object(gear.get_item(gear.target_slot(offered))).is_same(offered)
	assert_bool(ui.is_open()).is_false()


## The shop is the third board to be handed "which ring goes?" and the second to throw the
## answer away: the counter charged for the ring, opened the trade view, asked the question,
## and then equipped over Ring 1 whatever the player had said. The purchase path granted its
## own offer with a hard-coded -1; every board funnels into one grant site now.
func test_a_bought_ring_goes_into_the_slot_the_player_chose() -> void:
	var live := await _start()
	var gear := live.equipment as Equipment
	var rings := _wear_two_rings(gear, live)
	live.add_gold(500)
	var offered := _make_ring(3)
	var shop := await _add_stocked_shop([offered], 40)
	assert_bool(shop.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var gold := live.gold

	# The counter asks the same question a chest does, and both rings are reachable.
	ui.select(0)
	ui.activate()
	await _frames(2)
	assert_int(ui.selected_row()).is_equal(ChestUi.Row.REPLACE)
	assert_array(ui.replace_options_for(offered)).contains_exactly(rings)

	# Page two, then buy: the ring named on the second page is the one that comes off.
	ui.select(1)
	await _frames(1)
	assert_str(ui.compare_view().footer()).is_equal("Slot 2 of 2")
	ui.activate()
	await _frames(4)
	assert_object(gear.get_item(&"ring1")).is_same(rings[0])
	assert_object(gear.get_item(&"ring2")).is_same(offered)
	assert_int(live.gold).is_less(gold)
	assert_array(shop.offers).is_empty()


## The same answer on the same counter, on page one: Ring 1 goes and Ring 2 is left alone.
## The old path passed -1 for both pages, so page one was right for the wrong reason.
func test_buying_a_ring_on_the_first_page_still_replaces_the_first_ring() -> void:
	var live := await _start()
	var gear := live.equipment as Equipment
	var rings := _wear_two_rings(gear, live)
	live.add_gold(500)
	var offered := _make_ring(4)
	var shop := await _add_stocked_shop([offered], 40)
	assert_bool(shop.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	ui.select(0)
	ui.activate()
	await _frames(2)
	ui.activate()
	await _frames(4)
	assert_object(gear.get_item(&"ring1")).is_same(offered)
	assert_object(gear.get_item(&"ring2")).is_same(rings[1])


## A price the player cannot pay still leaves the board open and the gear untouched, after the
## trade view has been through - the refusal has to survive the extra question.
func test_an_unaffordable_ring_charges_nothing_and_takes_nothing() -> void:
	var live := await _start()
	var gear := live.equipment as Equipment
	var rings := _wear_two_rings(gear, live)
	var offered := _make_ring(5)
	var shop := await _add_stocked_shop([offered], 4000)
	assert_bool(shop.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var gold := live.gold
	ui.select(0)
	ui.activate()
	await _frames(4)
	# The card is refused on the board: an unaffordable offer never opens the trade at all.
	assert_int(ui.selected_row()).is_equal(ChestUi.Row.OFFERS)
	assert_int(live.gold).is_equal(gold)
	assert_object(gear.get_item(&"ring1")).is_same(rings[0])
	assert_object(gear.get_item(&"ring2")).is_same(rings[1])
	assert_array(shop.offers).contains([offered])


## The shape, not the instance. "Which ring goes?" has been answered by a player and thrown
## away twice now - once by the cursed chest, once by this counter - and both times because a
## caller had grown an equip line of its own and passed -1 down it. The run has exactly one
## place that hands the player gear, `RewardEffects.grant_item`, which takes the answer as an
## argument; this case fails the moment RunManager grows a second one.
func test_the_run_has_exactly_one_place_that_equips_the_player() -> void:
	var source := FileAccess.get_file_as_string("res://src/core/run_manager.gd")
	assert_str(source).is_not_empty()
	assert_str(source).not_contains(".equip(")
	assert_str(source).contains("RewardEffects.grant_item(")
	assert_str(source).contains("RewardEffects.grant_ability(")


## Fills both ring slots and returns [ring1, ring2].
func _wear_two_rings(gear: Equipment, live: Player) -> Array[ItemInstance]:
	var worn: Array[ItemInstance] = []
	for i in range(2):
		var ring := _make_ring(i)
		gear.equip(ring, live.stats)
		worn.append(ring)
	assert_object(gear.get_item(&"ring1")).is_same(worn[0])
	assert_object(gear.get_item(&"ring2")).is_same(worn[1])
	return worn


## A ring, rolled from the real registry with a seed of its own so the three in a case are
## distinct objects with distinct names.
func _make_ring(salt: int) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + salt
	var slots: Array[int] = [int(ItemBase.Slot.RING)]
	var ring := ItemGenerator.generate(RunManager.item_registry, 1, rng, 0.0, slots)
	assert_object(ring).is_not_null()
	return ring


## A counter holding exactly `stock`, so the case knows which card is which.
func _add_stocked_shop(stock: Array, base_price: int) -> Shop:
	var shop := Shop.new()
	RunManager.floor_root().add_child(shop)
	shop.global_position = RunManager.player().global_position
	shop.stock(stock, base_price)
	await _frames(2)
	return shop


## A real pad button, through the real InputMap and the real viewport.
func _pad_press(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(1)


## The first card on the board whose slot the player has already filled, or -1.
static func _first_offer_for_a_filled_slot(ui: ChestUi, gear: Equipment) -> int:
	for i in ui.offers.size():
		var item := ui.offers[i] as ItemInstance
		if item != null and gear.get_item(gear.target_slot(item)) != null:
			return i
	return -1


# ---------------------------------------------------------------- helpers


func _start(class_id: StringName = &"fighter") -> Player:
	assert_bool(RunManager.new_run(SEED, class_id)).is_true()
	await _frames(4)
	var live := RunManager.player()
	assert_object(live).is_not_null()
	live.health.invulnerable = true
	return live


func _ui() -> ChestUi:
	return (RunManager.game as Game).chest_ui


func _add_chest(kind: Chest.Kind) -> Chest:
	var chest := Chest.new()
	chest.kind = kind
	RunManager.floor_root().add_child(chest)
	chest.global_position = RunManager.player().global_position
	await _frames(2)
	return chest


## Total tiers across the slotted abilities: it rises when a card is taken, whether the card
## filled an empty slot or upgraded something already held.
static func _loadout_weight(slots: AbilitySlots) -> int:
	var total := 0
	for ability: Ability in slots.all():
		total += ability.tier
	return total


## Presses the picker's skip/leave button the way a player does, so the picker closes itself
## rather than the test emitting the signal behind it.
static func _press_skip(ui: ChestUi) -> void:
	(ui.get_node("%Skip") as Button).pressed.emit()


func _add_altar() -> Altar:
	var altar := Altar.new()
	RunManager.floor_root().add_child(altar)
	altar.global_position = RunManager.player().global_position
	await _frames(2)
	return altar


## A counter stocked with `count` items; 0 is a counter the player has bought out.
func _add_shop(count: int) -> Shop:
	var shop := Shop.new()
	RunManager.floor_root().add_child(shop)
	shop.global_position = RunManager.player().global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var stock: Array = []
	for _i in range(count):
		var item := ItemGenerator.generate(RunManager.item_registry, 1, rng, 0.0)
		if item != null:
			stock.append(item)
	shop.stock(stock, 40)
	await _frames(2)
	return shop


func _add_shrine() -> Shrine:
	var shrine := Shrine.new()
	RunManager.floor_root().add_child(shrine)
	shrine.global_position = RunManager.player().global_position
	await _frames(2)
	return shrine


func _offer_index_for_stat(stat: StringName) -> int:
	var ui := _ui()
	for i in range(ui.offers.size()):
		var entry := ui.offers[i] as Dictionary
		if entry != null and StringName(str(entry.get("stat", &""))) == stat:
			return i
	return -1


func _offer_index_for_cost_kind(kind: StringName) -> int:
	var ui := _ui()
	for i in range(ui.offers.size()):
		var entry := ui.offers[i] as Dictionary
		if entry != null and StringName(str(entry.get("cost_kind", &""))) == kind:
			return i
	return -1


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
