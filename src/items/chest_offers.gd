## Rolls the cards a chest, altar or ability pick shows (docs §8). Pure content logic: every
## roll consumes the RandomNumberGenerator it is handed and nothing else, so the same
## (seed, floor, player state) always produces the same board.
##
## `roll()` returns this object rather than a bare Array because a CURSED chest rolls two
## things: the Legendary prize that goes on the board, and the Curse passive that is the
## price of taking it (`curse`), which RunManager attaches when the prize is picked.
class_name ChestOffers
extends RefCounted

## Extra ability draws per offer, so filtering out still-locked rewards leaves a full row.
const LOCKED_HEADROOM := 4
## Where `home_family_for()` reads a class's starting weapon from.
const CLASS_DIR := "res://data/classes"
## How each shrine `cost_kind` is worded on the offer card (docs §8).
const SHRINE_COST_NAMES: Dictionary = {&"gold": "gold", &"hp": "HP", &"max_hp": "max HP"}
## Why a shrine option that cannot do anything is greyed out.
const NOTHING_TO_CLEANSE := "No curse to cleanse"
## Stats only a projectile weapon can spend. `WeaponController._spawn_projectiles()` is the
## one reader of all four, so a melee build gains exactly nothing from any of them.
const PROJECTILE_STATS: Array[StringName] = [
	&"projectile_count", &"projectile_speed", &"projectile_size", &"pierce"
]
## What a card says about itself when its whole payload is inert for the worn weapon.
const NO_EFFECT_NOTE := "No effect with your current weapon"
## Gold in a gold chest: base, plus this much per floor, plus a roll of GOLD_SPREAD.
const GOLD_BASE := 30
const GOLD_PER_FLOOR := 20
const GOLD_SPREAD := 20

## The cards to show.
var offers: Array = []
## Curse a CURSED chest attaches to its prize; null for every other kind.
var curse: Ability


## Rolls `count` offers of `kind` (a `Chest.Kind`). `gear` biases item chests towards a slot
## the player has empty or weak and may be null; `owned_tiers` is `AbilitySlots.owned_tiers()`.
## `prefer_kind` is the `Ability.Kind` an ability chest is made of (see `prefer_kind_for`), or
## -1 to let the roll decide which of the two kinds the board shows.
static func roll(
	kind: int,
	count: int,
	floor_index: int,
	rng: RandomNumberGenerator,
	luck: float,
	items: ItemRegistry,
	abilities: AbilityRegistry,
	gear: Equipment,
	class_id: StringName,
	owned_tiers: Dictionary,
	prefer_kind: int = -1
) -> ChestOffers:
	var out := ChestOffers.new()
	match kind:
		Chest.Kind.STAT:
			for entry: Dictionary in ItemGenerator.generate_stat_offers(rng, luck, count):
				out.offers.append(entry)
		Chest.Kind.ITEM:
			out._roll_items(count, floor_index, rng, luck, items, gear, class_id)
		Chest.Kind.ABILITY:
			out._roll_abilities(count, rng, abilities, class_id, owned_tiers, prefer_kind)
		Chest.Kind.GOLD:
			out.offers.append(
				GOLD_BASE + floor_index * GOLD_PER_FLOOR + rng.randi_range(0, GOLD_SPREAD)
			)
		Chest.Kind.CURSED:
			out._roll_cursed(floor_index, rng, luck, items, abilities, owned_tiers)
	return out


## The board a chest (or an altar) rolls for the live player: `roll()` with every argument that
## comes off the player — the extra card the Oligarch's flag buys, luck, worn gear, the ability
## tiers already held and which ability kind has a free slot. Assembling those at the call site
## is how a board can quietly differ between the roll and the re-roll of the same chest.
static func for_player(
	kind: int,
	live: Player,
	floor_index: int,
	rng: RandomNumberGenerator,
	items: ItemRegistry,
	abilities: AbilityRegistry,
	class_id: StringName
) -> ChestOffers:
	var slots := live.ability_slots as AbilitySlots
	return roll(
		kind,
		4 if bool(live.flags.get("chest_extra_option", false)) else 3,
		floor_index,
		rng,
		live.stats.get_value(&"luck"),
		items,
		abilities,
		live.equipment as Equipment,
		class_id,
		slots.owned_tiers() if slots != null else {},
		prefer_kind_for(slots)
	)


## Docs §8: at least one item offer must suit a slot the player has empty or weak, so a
## player wearing no armour is never shown three rings. The first card carries that bias.
## Every card, first or not, also carries the weapon-family bias in `_roll_one_item()`.
func _roll_items(
	count: int,
	floor_index: int,
	rng: RandomNumberGenerator,
	luck: float,
	items: ItemRegistry,
	gear: Equipment,
	class_id: StringName
) -> void:
	var bias: Array[int] = []
	var worn := -1
	if gear != null:
		bias.append(gear.weakest_slot())
		var weapon := gear.weapon()
		if weapon != null:
			worn = int(weapon.family())
	var home := home_family_for(class_id, items)
	for i in range(count):
		var slot_filter: Array[int] = []
		if i == 0:
			slot_filter = bias
		var item := _roll_one_item(items, floor_index, rng, luck, slot_filter, home, worn)
		if item != null:
			offers.append(item)


## The `WeaponBase.Family` a class is built around — the family of its `start_weapon_id` — or
## -1 when the class cannot be resolved (a test with an invented id).
##
## docs §4.3 makes the starting weapon half of what a class *is*, so this is what a chest keeps
## the run supplied with. Read off `data/classes/<id>.tres` rather than tabulated here: a
## second copy of "which class is the melee one" is a thing that silently disagrees.
static func home_family_for(class_id: StringName, items: ItemRegistry) -> int:
	if class_id == &"" or items == null:
		return -1
	var path := "%s/%s.tres" % [CLASS_DIR, String(class_id)]
	if not ResourceLoader.exists(path):
		return -1
	var def := load(path) as ClassDef
	if def == null:
		return -1
	var weapon := items.find_base(def.start_weapon_id) as WeaponBase
	return int(weapon.family()) if weapon != null else -1


## One item card, with a weapon card pulled towards the *family* of `worn` (null: no
## preference). Non-weapon cards are returned untouched.
##
## Item chests used to bias by slot alone, so a Ranger was routinely handed a higher-tier
## sword, equipped it because it was an upgrade, and stopped being a Ranger by floor 3 - every
## style-gated passive (Ricochet, Close Quarters) then paid the same for all four classes and
## the class you picked stopped changing the build. The round-4 answer re-rolled the card a
## few times hoping for the right style; rejection sampling against a nineteen-base pool found
## one about half the time, which moved the number by a few points and held nothing.
##
## This asks the generator for the family outright (`style_filter`), so the re-roll cannot
## fail, and spends one roll of `ItemTuning.weapon_family_bias` deciding whether to do it at
## all. `home` is the class's own family and `worn` the family it is currently fighting with;
## a card in either is kept, and a re-roll lands in one of them
## (`ItemTuning.weapon_home_bias` picks which). Keeping both is what stops the bias becoming a
## ratchet - bias only towards the worn weapon and one good sword out of a shop ends a
## Ranger's career as a Ranger, because every chest afterwards reinforces the sword.
##
## The share that is *not* re-rolled is the deliberate offer of something else - a Wizard can
## still be handed a greatsword and choose to become a different run - and shops and elite
## drops carry no bias whatever, so the weapon slot is a preference rather than a cage.
static func _roll_one_item(
	items: ItemRegistry,
	floor_index: int,
	rng: RandomNumberGenerator,
	luck: float,
	slot_filter: Array[int],
	home: int,
	worn: int
) -> ItemInstance:
	var first := ItemGenerator.generate(items, floor_index, rng, luck, slot_filter)
	var offered := _weapon_of(first)
	if offered == null or (home < 0 and worn < 0):
		return first
	var family := int(offered.family())
	if family == home or family == worn:
		return first
	var tuning := ItemTuning.shared()
	if rng.randf() >= tuning.weapon_family_bias:
		return first
	var target := worn
	if home >= 0 and (worn < 0 or rng.randf() < tuning.weapon_home_bias):
		target = home
	var alt := ItemGenerator.generate(
		items,
		floor_index,
		rng,
		luck,
		[int(ItemBase.Slot.WEAPON)],
		-1,
		"",
		WeaponBase.styles_in_family(target as WeaponBase.Family)
	)
	return alt if alt != null else first


## The `WeaponBase` behind an offered item, or null when the card is not a weapon.
static func _weapon_of(item: ItemInstance) -> WeaponBase:
	return item.base as WeaponBase if item != null else null


## Docs §8: an ability chest "respects slots". The kind with a free slot is the one the player
## can actually take without throwing something away, so that is the kind to lead with; -1 when
## both sides are free or both are full and the choice is genuinely open.
static func prefer_kind_for(slots: AbilitySlots) -> int:
	if slots == null:
		return -1
	var actives_full := slots.is_full(Ability.Kind.ACTIVE)
	var passives_full := slots.is_full(Ability.Kind.PASSIVE)
	if actives_full == passives_full:
		return -1
	return int(Ability.Kind.PASSIVE) if actives_full else int(Ability.Kind.ACTIVE)


## The single `Ability.Kind` a board is made of: `prefer_kind` when exactly one kind has a
## free slot, otherwise a coin flip off `rng`. Static because the balance simulation draws its
## boards through the same rule (`RunSimulator._ability_cards`).
static func board_kind(prefer_kind: int, rng: RandomNumberGenerator) -> int:
	if prefer_kind >= 0:
		return prefer_kind
	return int(Ability.Kind.ACTIVE) if rng.randf() < 0.5 else int(Ability.Kind.PASSIVE)


## Over-draw: rewards the profile has not unlocked yet are dropped, and the player should
## still see a full row of cards.
##
## Every card on an ability board is of the *same* kind. A board that mixed one active with
## two passives was not a decision while an active slot stood open: an active is worth an
## order of magnitude more power than a passive, so the active won essentially every board it
## appeared on and the other two cards were scenery. Three cards of one kind are three
## comparable things, which is the only shape in which the choice is real. Which kind is
## `board_kind()`: the one with a free slot, or a coin flip when that does not decide it.
func _roll_abilities(
	count: int,
	rng: RandomNumberGenerator,
	abilities: AbilityRegistry,
	class_id: StringName,
	owned_tiers: Dictionary,
	prefer_kind: int = -1
) -> void:
	var kind := board_kind(prefer_kind, rng)
	var pool := abilities.offer(rng, count + LOCKED_HEADROOM, class_id, owned_tiers, kind)
	var unlocked: Array[Ability] = []
	for ability: Ability in pool:
		if SaveManager.is_unlocked(ability.id):
			unlocked.append(ability)
	for ability: Ability in unlocked:
		if offers.size() < count and int(ability.kind) == kind:
			offers.append(ability)
	_top_up(unlocked, count)


## The player's primary stats, keyed the way a stat card reads them (`current_stats`): what
## "+1 Might" is being added to, so the card can print "Might 4 -> 5" instead of a blurb.
static func current_stats(live: Player) -> Dictionary:
	var out: Dictionary = {}
	if live == null:
		return out
	for stat: StringName in Stats.PRIMARY:
		out[stat] = live.stats.primary(stat)
	return out


## What one point of `stat` buys, for a stat card with nothing to compare against (docs §4.2).
## Shown only when the board was not handed `current_stats`; otherwise the card prints the
## before-and-after, which is the same fact with the player's own numbers in it.
static func stat_blurb(stat: StringName) -> String:
	match stat:
		&"vitality":
			return "+5 max HP per point"
		&"might":
			return "+4% melee damage"
		&"precision":
			return "+4% ranged damage, +1% crit"
		&"arcana":
			return "+4% ability damage, -1.5% cooldowns"
		&"swiftness":
			return "+2% move speed, +1.5% attack speed"
		&"fortune":
			return "+1.5% crit, +2% loot rarity"
	return ""


## Fills a board the chosen kind could not fill on its own. Deep in a run every passive can be
## owned or maxed out, and a one-card board is worse than a mixed one.
func _top_up(unlocked: Array[Ability], count: int) -> void:
	for ability: Ability in unlocked:
		if offers.size() >= count:
			return
		if not offers.has(ability):
			offers.append(ability)


## Docs §8: one Legendary prize, and taking it attaches a Curse passive that holds a passive
## slot until a Shrine cleanses it. The curse is not a card of its own — it is the price of
## the card — so it is returned in `curse`, not appended to `offers`.
func _roll_cursed(
	floor_index: int,
	rng: RandomNumberGenerator,
	luck: float,
	items: ItemRegistry,
	abilities: AbilityRegistry,
	owned_tiers: Dictionary
) -> void:
	var prize := ItemGenerator.generate(
		items, floor_index, rng, luck, [], ItemInstance.Rarity.LEGENDARY
	)
	if prize != null:
		offers.append(prize)
	var pool := unowned_curse_ids(abilities, owned_tiers)
	if pool.is_empty():
		return
	curse = abilities.instance(pool[rng.randi_range(0, pool.size() - 1)])


## Every Curse the registry ships, in registry order. Curses carry `weight = 0` and are
## refused by `AbilityRegistry.is_offerable()`, so they are found by type rather than by
## being drawn: a new `data/abilities/curse_*.tres` joins the pool with no code change.
static func curse_ids(abilities: AbilityRegistry) -> Array[StringName]:
	var out: Array[StringName] = []
	if abilities == null:
		return out
	for ability: Ability in abilities.abilities:
		if ability is CursePassive:
			out.append(ability.id)
	return out


## The curses the player is not already carrying. A Curse is `max_tier = 1`, so handing out a
## second copy of one used to install nothing while still paying out the Legendary - a second
## cursed chest was a free prize. Two passive slots cannot hold the whole pool, so the
## fallback only fires for a hand-built loadout in a test.
static func unowned_curse_ids(
	abilities: AbilityRegistry, owned_tiers: Dictionary
) -> Array[StringName]:
	var all_ids := curse_ids(abilities)
	var fresh: Array[StringName] = []
	for id: StringName in all_ids:
		if not owned_tiers.has(id):
			fresh.append(id)
	return fresh if not fresh.is_empty() else all_ids


## The board description for a Shop counter (docs §8). A counter the player has bought out
## still opens - rerolling restocks it - but it used to do so as a full modal with no cards
## under the caption "Buy one (you have 99864g)"; `sold_out` turns it into the restock
## affordance it really is.
static func shop_context(shop: Shop) -> Dictionary:
	return {
		"shop": true,
		"prices": shop.prices.duplicate(),
		"title": "Shop",
		"sold_out": shop.offers.is_empty(),
	}


# ------------------------------------------------- build relevance (docs §4.4, §4.5)


## The note a card needs because nothing in it can do anything for this build, or "" when it
## does something. A "+1 projectile" passive is offered in nearly half of all runs and is a
## blank card on a sword; the player had no way to tell from the card.
static func inert_note(offer: Variant, weapon: WeaponBase) -> String:
	if weapon == null or weapon.is_projectile_style():
		return ""
	var stats := _stats_touched(offer)
	if stats.is_empty():
		return ""
	for stat: StringName in stats:
		if not PROJECTILE_STATS.has(stat):
			return ""
	return NO_EFFECT_NOTE


## Every stat an offer would change, or an empty array for a card whose payload is not a plain
## list of stats (an active ability, a gold pile, a shrine option) and so cannot be judged here.
static func _stats_touched(offer: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if offer is ItemInstance:
		var item := offer as ItemInstance
		if item.unique_effect != &"":
			return []
		for stat: StringName in item.base.implicit_flat.keys():
			out.append(stat)
		for stat: StringName in item.base.implicit_percent.keys():
			out.append(stat)
		for entry: Dictionary in item.affixes:
			var affix: Variant = entry.get("affix")
			if affix is Affix:
				out.append((affix as Affix).stat)
		return out
	if not (offer is StatPassive):
		return out
	var passive := offer as StatPassive
	for stat: StringName in passive.percent_stats:
		out.append(stat)
	for stat: StringName in passive.flat_stats:
		out.append(stat)
	return out


# ---------------------------------------------------------------- shrines (docs §8)


## The cards for a Shrine's fixed menu, in the shrine's own option order: `{offers, prices}`,
## where `offers[i]` is the card for `options[i]`. The order is load-bearing - RunManager
## charges option N when card N is taken - which is why the two are built in one place.
## `live` is the player the preconditions are checked against and may be null.
static func shrine_cards(options: Array[Dictionary], live: Player) -> Dictionary:
	var cards: Array = []
	var prices: Array[int] = []
	for option: Dictionary in options:
		var cost := int(option.get("cost", 0))
		var cost_kind := StringName(str(option.get("cost_kind", &"gold")))
		var card := {
			"stat": StringName(str(option.get("buff", &"might"))),
			"points": int(option.get("amount", 1)),
			"label": str(option.get("label", "")),
			"cost_kind": cost_kind,
			"cost": cost,
			"cost_text": shrine_cost_text(cost_kind, cost),
		}
		# Cleansing nothing used to cost 25 HP and give nothing back. The card says why it is
		# refused instead, and RunManager checks the same thing before charging.
		if not shrine_option_is_usable(option, live):
			card["unavailable"] = true
			card["note"] = NOTHING_TO_CLEANSE
		cards.append(card)
		# Only gold rides the card's price row; every other kind is spelled out in `cost_text`.
		prices.append(cost if cost_kind == &"gold" else 0)
	return {"offers": cards, "prices": prices}


## Plain-language price of a shrine option, for every `cost_kind` a shrine can charge. Only
## gold rides the card's price row; without this an HP or max-HP option reads as free even
## though the shrine deducts it (docs §8, "buff-for-a-cost").
static func shrine_cost_text(cost_kind: StringName, cost: int) -> String:
	if cost <= 0:
		return "Free"
	return "Costs %d %s" % [cost, SHRINE_COST_NAMES.get(cost_kind, String(cost_kind))]


## False for a shrine option that cannot do anything right now, so the card can grey it out and
## the shrine can refuse it instead of charging. Only "cleanse" has a precondition.
static func shrine_option_is_usable(option: Dictionary, live: Player) -> bool:
	if StringName(str(option.get("buff", &"might"))) != &"cleanse" or live == null:
		return true
	return curse_slot_index(live.ability_slots as AbilitySlots) >= 0


## Slot index of the first Curse passive the player carries, or -1.
static func curse_slot_index(slots: AbilitySlots) -> int:
	if slots == null:
		return -1
	for index in range(AbilitySlots.SLOT_COUNT):
		var ability := slots.get_ability(index)
		if ability != null and String(ability.id).begins_with("curse_"):
			return index
	return -1
