## End-to-end integration for the designed chest/shrine economy (docs §4.3, §8): the Oligarch's
## Buyout price, the Cursed chest's attached curse, the Shrine cleanse, non-gold shrine costs
## and the item chest's empty/weak-slot bias. `manage_scenes` is off so the gdUnit runner's
## `current_scene` is never swapped out.
class_name ChestEconomyIntegrationTest
extends GdUnitTestSuite

const SEED := 20250912
## Cursed boards rolled per class when measuring whether the chest is a real gamble.
const BOARD_SAMPLES := 40
## Last floor index of a run (RunManager.FLOOR_COUNT - 1): where the Legendary prize is biggest.
const FINAL_FLOOR := 8


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
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


# ---------------------------------------------------------------- Buyout (docs §4.3)


func test_oligarch_who_cannot_pay_keeps_the_chest() -> void:
	var live := await _start(&"oligarch")
	assert_bool(bool(live.flags.get("chest_costs_gold", false))).is_true()
	assert_bool(live.spend_gold(live.gold)).is_true()
	var price := RunManager.chest_open_price()
	assert_int(price).is_greater(0)
	var chest := await _add_chest(Chest.Kind.STAT)

	assert_bool(chest.interact(live)).is_false()
	await _frames(4)
	# The chest was never consumed: still closed, still enabled, still worth walking back to.
	assert_bool(chest.is_opened).is_false()
	assert_bool(chest.enabled).is_true()
	assert_bool(chest.can_interact()).is_true()
	assert_bool(_ui().is_open()).is_false()
	assert_int(live.gold).is_equal(0)

	# ... and once the gold is there the same chest opens and charges exactly the price.
	live.add_gold(price + 25)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	assert_bool(chest.is_opened).is_true()
	assert_bool(_ui().is_open()).is_true()
	assert_int(live.gold).is_equal(25)


func test_classes_without_buyout_pay_nothing() -> void:
	var live := await _start(&"fighter")
	assert_int(RunManager.chest_open_price()).is_equal(0)
	var gold := live.gold
	var chest := await _add_chest(Chest.Kind.STAT)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	assert_int(live.gold).is_equal(gold)


func test_oligarch_starts_with_one_active_and_a_slot_left_to_fill() -> void:
	# The Oligarch used to be handed Contract *on top of* Hostile Takeover, so it arrived on
	# floor 1 with both active slots full: for the rest of the run every active it was offered
	# was a forced downgrade of a class-defining ability, and it made one fewer build decision
	# than every other class. The defect was two grants, not which one; the round that removed
	# Contract removed the starting kit docs §4.3 promises along with it ("Start: Golden Cane
	# ... and a Contract"). So the Contract is the grant and Hostile Takeover - "a unique class
	# active available in its pool", §4.3 - is the class-only card that fills the open slot.
	var live := await _start(&"oligarch")
	var slots := live.ability_slots as AbilitySlots
	(
		assert_int(slots.index_of(&"contract"))
		. override_failure_message("the Oligarch does not start with its Contract")
		. is_greater_equal(0)
	)
	assert_int(slots.tier_of(&"contract")).is_equal(1)
	(
		assert_int(slots.index_of(&"hostile_takeover"))
		. override_failure_message("the Oligarch is handed Hostile Takeover as well")
		. is_equal(-1)
	)
	assert_int(_free_actives(slots)).is_equal(AbilitySlots.ACTIVE_COUNT - 1)


func test_every_class_starts_a_run_with_the_same_free_slots() -> void:
	var oligarch := await _start(&"oligarch")
	var oligarch_slots := oligarch.ability_slots as AbilitySlots
	var free_actives := _free_actives(oligarch_slots)
	var free_passives := _free_passives(oligarch_slots)
	for id: StringName in [&"fighter", &"ranger", &"wizard"]:
		var live := await _start(id)
		var slots := live.ability_slots as AbilitySlots
		(
			assert_int(_free_actives(slots))
			. override_failure_message("%s and the Oligarch get different active slots" % id)
			. is_equal(free_actives)
		)
		assert_int(_free_passives(slots)).is_equal(free_passives)


## Empty active sockets in `slots`.
func _free_actives(slots: AbilitySlots) -> int:
	var free := 0
	for i in range(AbilitySlots.ACTIVE_COUNT):
		if slots.get_ability(i) == null:
			free += 1
	return free


## Empty passive sockets in `slots` (the class innate is uncounted and never takes one).
func _free_passives(slots: AbilitySlots) -> int:
	var free := 0
	for i in range(AbilitySlots.PASSIVE_COUNT):
		if slots.get_ability(i + AbilitySlots.ACTIVE_COUNT) == null:
			free += 1
	return free


# ---------------------------------------------------------------- Cursed chest (docs §8)


func test_cursed_chest_prize_costs_a_passive_slot_and_the_card_says_so() -> void:
	var live := await _start(&"fighter")
	var slots := live.ability_slots as AbilitySlots
	assert_int(_curse_index(slots)).is_equal(-1)
	var chest := await _add_chest(Chest.Kind.CURSED)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	assert_bool(ui.is_open()).is_true()
	# One prize card: the curse is the price of that card, not a free fourth option.
	assert_int(ui.card_count()).is_equal(1)
	var prize := ui.offers[0] as ItemInstance
	assert_object(prize).is_not_null()
	assert_int(prize.rarity).is_equal(ItemInstance.Rarity.LEGENDARY)
	# The warning is a row the card actually draws, not a value buried in a dictionary: it is
	# read off `rows`, in the same order and with the same text the player sees.
	var warning := ""
	for row: Dictionary in ui.describe_offer(prize)["rows"] as Array:
		if str(row["text"]).begins_with("Curse:"):
			warning = str(row["text"])
	assert_str(warning).contains("passive slot")
	assert_str(warning).contains(RunManager.pending_curse().description)

	ui.select(0)
	ui.activate()
	await _frames(2)
	await _answer_open_questions(ui)
	await _frames(4)
	assert_object((live.equipment as Equipment).get_item(prize.base.slot_name())).is_not_null()
	assert_int(_curse_index(slots)).is_greater_equal(0)
	assert_bool(slots.is_passive_index(_curse_index(slots))).is_true()


## A cursed chest's prize is gear, and gear goes into a slot that may already be full. The
## board used to ask only about the passive its Curse wanted and then equip the prize through
## `Player.equip`, which fills the first slot of the family - so a player wearing two rings
## lost Ring 1 to a card that never mentioned it, and could not reach Ring 2 whatever they
## pressed. Both questions belong to the player, and they are asked in order on the same
## dialog: which ring comes off, then which passive the Curse takes.
func test_a_cursed_ring_asks_which_ring_goes_before_the_curse_takes_a_passive() -> void:
	var live := await _start(&"fighter")
	var gear := live.equipment as Equipment
	var slots := live.ability_slots as AbilitySlots
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ring_one := _any_item(RunManager.item_registry, ItemBase.Slot.RING, rng)
	var ring_two := _any_item(RunManager.item_registry, ItemBase.Slot.RING, rng)
	gear.equip(ring_one, live.stats, &"ring1")
	gear.equip(ring_two, live.stats, &"ring2")
	for id: StringName in [&"thorns", &"vampiric"]:
		assert_bool(slots.add(RunManager.ability_registry.instance(id))).is_true()
	var chest := await _add_chest(Chest.Kind.CURSED)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var curse := RunManager.pending_curse()
	assert_object(curse).is_not_null()
	# The prize the chest rolled may land in any slot; this run is about the ring family, which
	# is the one with two candidates and the one the old path destroyed in silence. The board's
	# own context (the live `needs_replace` / `price_replace` lookups) is kept.
	var prize := _any_item(RunManager.item_registry, ItemBase.Slot.RING, rng)
	prize.rarity = ItemInstance.Rarity.LEGENDARY
	ui.show_offers(ChestUi.Kind.CURSED, [prize], ui.context)
	await _frames(2)

	ui.select(0)
	ui.activate()
	await _frames(2)
	# First question: the ring. Both worn rings are candidates, so it can be answered "Ring 2".
	assert_int(ui.selected_row()).is_equal(ChestUi.Row.REPLACE)
	assert_int(ui.replace_step()).is_equal(ChestUi.Step.OFFER)
	assert_array(ui.replace_options_for(prize)).contains_exactly([ring_one, ring_two])
	ui.select(1)
	ui.activate()
	await _frames(2)

	# Second question: the price. Same dialog, still open, nothing taken yet.
	assert_bool(ui.is_open()).is_true()
	assert_int(ui.selected_row()).is_equal(ChestUi.Row.REPLACE)
	assert_int(ui.replace_step()).is_equal(ChestUi.Step.PRICE)
	assert_str((ui.get_node("%Subtitle") as Label).text).contains("passive")
	assert_object(gear.get_item(&"ring1")).is_same(ring_one)
	ui.select(0)
	ui.activate()
	await _frames(4)

	# Both answers were honoured: Ring 2 took the prize, Ring 1 was never touched, and the
	# Curse paid with the passive the player pointed at rather than the last one in the list.
	assert_object(gear.get_item(&"ring2")).is_same(prize)
	assert_object(gear.get_item(&"ring1")).is_same(ring_one)
	assert_int(slots.index_of(&"thorns")).is_equal(-1)
	assert_int(slots.index_of(&"vampiric")).is_greater_equal(0)
	assert_int(_curse_index(slots)).is_greater_equal(0)


func test_a_shrine_removes_the_curse() -> void:
	var live := await _start(&"fighter")
	var slots := live.ability_slots as AbilitySlots
	var chest := await _add_chest(Chest.Kind.CURSED)
	chest.interact(live)
	await _frames(4)
	_ui().select(0)
	_ui().activate()
	await _frames(2)
	await _answer_open_questions(_ui())
	await _frames(4)
	assert_int(_curse_index(slots)).is_greater_equal(0)

	var shrine := await _add_shrine()
	assert_bool(shrine.interact(live)).is_true()
	await _frames(4)
	var index := _offer_index_for_stat(&"cleanse")
	assert_int(index).is_greater_equal(0)
	_ui().select(index)
	_ui().activate()
	await _frames(4)
	assert_int(_curse_index(slots)).is_equal(-1)


# ---------------------------------------------------------------- curse economics (docs §8)


## The Cursed chest is the one chest kind with a stated price, and for two playtests running
## that price was a *buff*: `curse_1` was numerically the same card as the ordinary Glass
## Cannon and `curse_3` gave seven times the crit of Bit Shift, so the chest that carries the
## risk was simply the best chest in the game and the Shrine's cleanse was dead content. The
## only shipped test asserted the curse landed in a slot, which it always did.
##
## This measures the thing the player feels instead, with the balance simulation and the
## shipped `data/abilities/curse_*.tres`: taking a curse has to leave the build weaker.
func test_every_curse_costs_every_class_power() -> void:
	var abilities := AbilityRegistry.load_default()
	var profile := BalanceProfile.load_default()
	var curses := ChestOffers.curse_ids(abilities)
	assert_array(curses).is_not_empty()
	for def: ClassDef in _class_defs():
		var sim := _sim_player(def, abilities, profile)
		for id: StringName in curses:
			var score := SimOfferPolicy.score_of(abilities.instance(id), sim, profile)
			(
				assert_float(score)
				. override_failure_message(
					(
						"%s leaves %s at power x%.4f - a curse is supposed to be the price"
						% [id, def.id, score]
					)
				)
				. is_less(1.0)
			)


## ... and never as good a card as the ordinary passives it competes with for the same slot.
## `curse_3` used to outscore every normal passive in the pool; a curse that is merely "a bit
## below average" would pass the test above and still make the cursed chest a free win.
func test_no_curse_is_worth_more_than_the_weakest_ordinary_passive() -> void:
	var abilities := AbilityRegistry.load_default()
	var profile := BalanceProfile.load_default()
	for def: ClassDef in _class_defs():
		var sim := _sim_player(def, abilities, profile)
		var floor_score := 99.0
		var floor_id := &""
		for ability: Ability in abilities.abilities:
			if ability.kind != Ability.Kind.PASSIVE:
				continue
			if not abilities.is_offerable(ability, def.id, {}):
				continue
			var score := SimOfferPolicy.score_of(abilities.instance(ability.id), sim, profile)
			if score < floor_score:
				floor_score = score
				floor_id = ability.id
		for id: StringName in ChestOffers.curse_ids(abilities):
			var curse_score := SimOfferPolicy.score_of(abilities.instance(id), sim, profile)
			(
				assert_float(curse_score)
				. override_failure_message(
					(
						"%s (x%.4f) is a better %s passive than %s (x%.4f)"
						% [id, curse_score, def.id, floor_id, floor_score]
					)
				)
				. is_less(floor_score)
			)


## And the chest as a whole has to be a decision rather than a giveaway: the Legendary prize
## against the Curse that pays for it, over a spread of boards. Some boards have to be worth
## taking and some have to be worth walking away from - if every board landed on the same side
## of 1.0 there would be nothing to weigh - and the deal has to improve as the prize grows,
## which is what makes a cursed chest a late-run gamble rather than an early-run trap.
func test_a_cursed_chest_is_a_gamble_and_not_a_giveaway() -> void:
	var items := ItemRegistry.load_default()
	var abilities := AbilityRegistry.load_default()
	var profile := BalanceProfile.load_default()
	for def: ClassDef in _class_defs():
		var early := _cursed_board_outcomes(def, items, abilities, profile, 0)
		var late := _cursed_board_outcomes(def, items, abilities, profile, FINAL_FLOOR)
		for outcomes: Array[float] in [early, late]:
			var gains := 0
			var losses := 0
			for net: float in outcomes:
				if net > 1.0:
					gains += 1
				else:
					losses += 1
			var label := "%s (%d gains, %d losses)" % [def.id, gains, losses]
			assert_int(gains).override_failure_message("never worth taking: " + label).is_greater(0)
			assert_int(losses).override_failure_message("never a risk: " + label).is_greater(0)
		# A floor-1 Legendary barely outweighs a passive slot; a floor-9 one usually does.
		(
			assert_float(_mean(late))
			. override_failure_message("%s: the prize never grows into the price" % def.id)
			. is_greater(_mean(early))
		)


## The Shrine's cleanse is what makes a curse survivable, so lifting one has to be worth the
## 25 HP it costs (docs §8). While the curses were buffs this was a paid downgrade, which is
## why the simulation had to special-case it.
func test_lifting_a_curse_makes_the_build_stronger() -> void:
	var abilities := AbilityRegistry.load_default()
	var profile := BalanceProfile.load_default()
	for def: ClassDef in _class_defs():
		for id: StringName in ChestOffers.curse_ids(abilities):
			var cursed := _sim_player(def, abilities, profile)
			var before := cursed.power()
			assert_bool(cursed.take_ability(abilities.instance(id))).is_true()
			var carried := cursed.power()
			cursed.abilities.erase(id)
			cursed.recompute()
			(
				assert_float(cursed.power())
				. override_failure_message("cleansing %s gained %s nothing" % [id, def.id])
				. is_greater(carried)
			)
			assert_float(cursed.power()).is_equal_approx(before, 0.001)


## A Curse is `max_tier = 1`, so handing out one the player already carries installs nothing
## and the Legendary comes free - the second cursed chest of a run used to be pure profit.
func test_a_cursed_chest_never_rolls_a_curse_the_player_already_carries() -> void:
	var items := ItemRegistry.load_default()
	var abilities := AbilityRegistry.load_default()
	var carried := ChestOffers.curse_ids(abilities)[0]
	for seed_value in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED + seed_value
		var rolled := ChestOffers.roll(
			Chest.Kind.CURSED, 1, 3, rng, 0.0, items, abilities, null, &"fighter", {carried: 1}
		)
		assert_object(rolled.curse).is_not_null()
		assert_str(String(rolled.curse.id)).is_not_equal(String(carried))


## Every other slot-filling offer in the game opens a replace row and makes the player choose.
## The cursed prize used to take passive slot 1 on its own and name the casualty in a toast
## afterwards, so a Vampiric could be deleted by a card that never mentioned it.
func test_a_cursed_prize_asks_which_passive_it_replaces() -> void:
	var live := await _start(&"fighter")
	var slots := live.ability_slots as AbilitySlots
	for id: StringName in [&"thorns", &"vampiric"]:
		assert_bool(slots.add(RunManager.ability_registry.instance(id))).is_true()
	assert_bool(slots.is_full(Ability.Kind.PASSIVE)).is_true()
	var chest := await _add_chest(Chest.Kind.CURSED)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	# The card says a passive is going to pay for this, before anything is confirmed.
	var warning := _card_row_starting_with(ui, ui.offers[0], "Curse:")
	assert_str(warning).contains("passive slot")
	assert_str(warning).contains("you choose which one it replaces")

	ui.select(0)
	ui.activate()
	await _frames(2)
	# The prize is gear, so its own slot question is put first when that slot is already full;
	# the Curse's is the second half of the same trade, not a replacement for it.
	if ui.replace_step() == ChestUi.Step.OFFER:
		ui.activate()
		await _frames(2)
	assert_int(ui.replace_step()).is_equal(ChestUi.Step.PRICE)
	# The same replace prompt an ability card opens, not a silent deletion.
	assert_int(ui.selected_row()).is_equal(ChestUi.Row.REPLACE)
	assert_bool((ui.get_node("%ReplaceBox") as Control).visible).is_true()
	assert_bool(ui.is_open()).is_true()
	# A full-height Legendary card plus the replace row does not fit the 480x270 dialog, so the
	# board has to have been laid out short enough to ask the question at all.
	var wanted := (ui.get_node("%Panel") as Control).get_combined_minimum_size().y
	assert_float(wanted).is_less_equal(ChestUi.MAX_PANEL_HEIGHT)

	# Slot 0 is Thorns; the old code always took slot 1, so answering "the first one" is what
	# proves the player's answer is the one that counts.
	ui.select(0)
	ui.activate()
	await _frames(4)
	assert_int(slots.index_of(&"thorns")).is_equal(-1)
	assert_int(slots.index_of(&"vampiric")).is_greater_equal(0)
	assert_int(_curse_index(slots)).is_greater_equal(0)
	assert_object((live.equipment as Equipment).get_item(&"weapon")).is_not_null()


# ---------------------------------------------------------------- inert cards (docs §4.4)


## `projectile_count` is read by `WeaponController._spawn_projectiles()` and by nothing else,
## so Hardlink's "+1 projectile" is a blank card on a sword - and it is offered in roughly half
## of all runs. The card now says so instead of looking like a reward.
func test_a_card_that_cannot_help_this_build_says_so() -> void:
	var live := await _start(&"fighter")
	assert_bool((live.equipment as Equipment).weapon().is_projectile_style()).is_false()
	var chest := await _add_chest(Chest.Kind.ABILITY)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	var hardlink := RunManager.ability_registry.instance(&"hardlink")
	assert_object(hardlink).is_not_null()
	assert_array(_card_notes(ui, hardlink)).contains([ChestOffers.NO_EFFECT_NOTE])
	# ... and a card this build can use is not tarred with the same note.
	var thorns := RunManager.ability_registry.instance(&"thorns")
	assert_bool(_card_notes(ui, thorns).has(ChestOffers.NO_EFFECT_NOTE)).is_false()


func test_the_same_card_is_not_flagged_for_a_build_that_can_use_it() -> void:
	var live := await _start(&"ranger")
	assert_bool((live.equipment as Equipment).weapon().is_projectile_style()).is_true()
	var chest := await _add_chest(Chest.Kind.ABILITY)
	assert_bool(chest.interact(live)).is_true()
	await _frames(4)
	var hardlink := RunManager.ability_registry.instance(&"hardlink")
	assert_bool(_card_notes(_ui(), hardlink).has(ChestOffers.NO_EFFECT_NOTE)).is_false()


# ---------------------------------------------------------------- Shrine costs (docs §8)


func test_shrine_cards_state_every_cost_kind() -> void:
	var live := await _start(&"fighter")
	var shrine := await _add_shrine()
	assert_bool(shrine.interact(live)).is_true()
	await _frames(4)
	var ui := _ui()
	assert_int(ui.card_count()).is_equal(shrine.options.size())
	for i in range(ui.offers.size()):
		var option := shrine.options[i]
		var cost := int(option.get("cost", 0))
		var kind := StringName(str(option.get("cost_kind", &"gold")))
		var costs: Array[String] = []
		for row: Dictionary in ui.describe_offer(ui.offers[i])["rows"] as Array:
			if str(row["text"]).begins_with("Costs "):
				costs.append(str(row["text"]))
		# Every option states its price, whatever currency it is paid in.
		assert_array(costs).is_not_empty()
		assert_str(costs[0]).contains(str(cost))
		if kind != &"gold":
			# Non-gold costs have no gold price row at all, so the card text is all there is.
			assert_int(ui.price_for(i)).is_equal(0)
			assert_str(costs[0]).is_not_equal("Costs %d gold" % cost)


func test_shrine_cost_text_covers_every_kind() -> void:
	assert_str(ChestOffers.shrine_cost_text(&"gold", 40)).is_equal("Costs 40 gold")
	assert_str(ChestOffers.shrine_cost_text(&"hp", 25)).is_equal("Costs 25 HP")
	assert_str(ChestOffers.shrine_cost_text(&"max_hp", 10)).is_equal("Costs 10 max HP")
	assert_str(ChestOffers.shrine_cost_text(&"gold", 0)).is_equal("Free")


# ---------------------------------------------------------------- Item chest bias (docs §8)


func test_item_chest_offers_something_for_the_empty_slot() -> void:
	var registry := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var gear := Equipment.new()
	var stats := Stats.new()
	for slot: ItemBase.Slot in [ItemBase.Slot.WEAPON, ItemBase.Slot.RING, ItemBase.Slot.TRINKET]:
		for slot_name: StringName in Equipment.slot_names_for(slot):
			gear.equip(_any_item(registry, slot, rng), stats, slot_name)
	# Everything is worn except armour, so armour is what an offer has to cover.
	assert_int(gear.weakest_slot()).is_equal(int(ItemBase.Slot.ARMOR))

	var rolled := ChestOffers.roll(
		Chest.Kind.ITEM, 3, 4, rng, 0.0, registry, null, gear, &"fighter", {}
	)
	assert_int(rolled.offers.size()).is_equal(3)
	assert_int((rolled.offers[0] as ItemInstance).slot()).is_equal(int(ItemBase.Slot.ARMOR))


func test_a_full_loadout_biases_towards_its_weakest_item() -> void:
	var registry := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var gear := Equipment.new()
	var stats := Stats.new()
	for slot: ItemBase.Slot in [
		ItemBase.Slot.WEAPON, ItemBase.Slot.ARMOR, ItemBase.Slot.RING, ItemBase.Slot.TRINKET
	]:
		for slot_name: StringName in Equipment.slot_names_for(slot):
			var item := _any_item(registry, slot, rng)
			item.rarity = ItemInstance.Rarity.EPIC
			gear.equip(item, stats, slot_name)
	assert_array(gear.empty_slots()).is_empty()
	gear.get_item(&"trinket").rarity = ItemInstance.Rarity.COMMON
	assert_int(gear.weakest_slot()).is_equal(int(ItemBase.Slot.TRINKET))
	var rolled := ChestOffers.roll(
		Chest.Kind.ITEM, 3, 4, rng, 0.0, registry, null, gear, &"fighter", {}
	)
	assert_int((rolled.offers[0] as ItemInstance).slot()).is_equal(int(ItemBase.Slot.TRINKET))


func test_an_item_chest_keeps_offering_the_style_you_fight_with() -> void:
	# The class you picked has to keep mattering past floor 2. Chests used to bias by empty
	# slot alone, so a Ranger was handed a higher-tier sword, equipped it because it was an
	# upgrade, and every style-gated passive from then on paid a Ranger exactly what it paid a
	# Fighter. A weapon card is now pulled towards the style the player is already holding.
	var registry := ItemRegistry.load_default()
	var stats := Stats.new()
	var counts := {&"in_style": 0, &"off_style": 0}
	for class_id: StringName in [&"ranger", &"fighter", &"wizard"]:
		var def := load("%s/%s.tres" % [RunManager.CLASS_DIR, class_id]) as ClassDef
		var worn := registry.find_base(def.start_weapon_id) as WeaponBase
		assert_object(worn).is_not_null()
		for seed_value in range(BOARD_SAMPLES):
			var rng := RandomNumberGenerator.new()
			rng.seed = SEED + seed_value
			var gear := Equipment.new()
			gear.equip(ItemGenerator.instance_of(worn, rng), stats, &"weapon")
			var rolled := ChestOffers.roll(
				Chest.Kind.ITEM, 3, 5, rng, 0.0, registry, null, gear, class_id, {}
			)
			for offer: Variant in rolled.offers:
				var base := (offer as ItemInstance).base as WeaponBase
				if base == null:
					continue
				var key := (
					&"in_style"
					if base.is_projectile_style() == worn.is_projectile_style()
					else &"off_style"
				)
				counts[key] = int(counts[key]) + 1
	var total := int(counts[&"in_style"]) + int(counts[&"off_style"])
	assert_int(total).override_failure_message("no weapon cards were rolled at all").is_greater(20)
	# Not "always in style": a deliberate switch has to stay possible, so an off-style weapon
	# still reaches the board when the re-rolls do not find one. It is no longer the coin flip
	# the base pool makes it.
	var share := float(counts[&"in_style"]) / float(total)
	(
		assert_float(share)
		. override_failure_message(
			(
				"%.0f%% of weapon cards matched the weapon the player is holding (%d of %d)"
				% [share * 100.0, counts[&"in_style"], total]
			)
		)
		. is_greater(0.7)
	)
	(
		assert_int(int(counts[&"off_style"]))
		. override_failure_message("a style switch is never offered at all")
		. is_greater(0)
	)


# ---------------------------------------------------------------- helpers


## Every shipped class, so a new one is covered by the balance assertions the day it lands.
static func _class_defs() -> Array[ClassDef]:
	var out: Array[ClassDef] = []
	for id: StringName in RunManager.CLASS_IDS:
		var def := load("%s/%s.tres" % [RunManager.CLASS_DIR, id]) as ClassDef
		if def != null:
			out.append(def)
	return out


## A scripted player of `def` at its starting loadout, for the balance-simulation assertions.
static func _sim_player(
	def: ClassDef, abilities: AbilityRegistry, profile: BalanceProfile
) -> SimPlayer:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return SimPlayer.create(def, ItemRegistry.load_default(), abilities, profile, rng)


## Power ratio of taking the prize *and* the curse, one entry per rolled cursed board.
static func _cursed_board_outcomes(
	def: ClassDef,
	items: ItemRegistry,
	abilities: AbilityRegistry,
	profile: BalanceProfile,
	floor_index: int
) -> Array[float]:
	var out: Array[float] = []
	for seed_value in range(BOARD_SAMPLES):
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED + seed_value * 7919 + floor_index
		var sim := SimPlayer.create(def, items, abilities, profile, rng)
		var rolled := ChestOffers.roll(
			Chest.Kind.CURSED,
			1,
			floor_index,
			rng,
			0.0,
			items,
			abilities,
			sim.equipment,
			def.id,
			sim.owned_tiers()
		)
		var prize := rolled.offers[0] as ItemInstance
		if prize == null or rolled.curse == null:
			continue
		var taken := sim.clone()
		taken.equip(prize)
		if not taken.take_ability(rolled.curse.duplicate_ability()):
			taken.replace_ability(rolled.curse.duplicate_ability())
		out.append(taken.power() / sim.power())
	return out


static func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / maxf(1.0, float(values.size()))


## The note rows a card carries, in the order it draws them.
static func _card_notes(ui: ChestUi, offer: Variant) -> Array[String]:
	var out: Array[String] = []
	for note: Dictionary in ui.describe_offer(offer)["notes"] as Array:
		out.append(str(note["text"]))
	return out


## The first row the card actually draws whose text starts with `prefix` - read off `rows`, in
## the order and with the text the player sees, not off a dictionary behind it.
static func _card_row_starting_with(ui: ChestUi, offer: Variant, prefix: String) -> String:
	for row: Dictionary in ui.describe_offer(offer)["rows"] as Array:
		if str(row["text"]).begins_with(prefix):
			return str(row["text"])
	return ""


func _start(class_id: StringName) -> Player:
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


func _add_shrine() -> Shrine:
	var shrine := Shrine.new()
	RunManager.floor_root().add_child(shrine)
	shrine.global_position = RunManager.player().global_position
	await _frames(2)
	return shrine


## Answers whatever the board is still asking after a card has been taken, accepting the
## candidate the selection is already on. A cursed prize is gear like any other now, so a full
## weapon slot opens the same trade view an item chest does *before* the price is even named.
func _answer_open_questions(ui: ChestUi) -> void:
	for _step in range(2):
		if not ui.is_open() or ui.selected_row() != ChestUi.Row.REPLACE:
			return
		ui.activate()
		await _frames(2)


static func _curse_index(slots: AbilitySlots) -> int:
	for i in range(AbilitySlots.SLOT_COUNT):
		var ability := slots.get_ability(i)
		if ability != null and String(ability.id).begins_with("curse_"):
			return i
	return -1


func _offer_index_for_stat(stat: StringName) -> int:
	var ui := _ui()
	for i in range(ui.offers.size()):
		var entry := ui.offers[i] as Dictionary
		if entry != null and StringName(str(entry.get("stat", &""))) == stat:
			return i
	return -1


static func _any_item(
	registry: ItemRegistry, slot: ItemBase.Slot, rng: RandomNumberGenerator
) -> ItemInstance:
	var bases := registry.bases_for([int(slot)], 8)
	return ItemGenerator.instance_of(bases[0], rng)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
