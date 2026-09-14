## What a reward board actually does to the live player once a card is taken: handing over the
## gear or the ability (`grant_item` / `grant_ability`), the Shrine's buff-for-a-cost (docs §8)
## and the Cursed chest's pact.
##
## The two grant calls are deliberately the only way anything reaches the player's loadout. A
## multi-slot family makes "which one goes?" a real question the trade view asks, and a caller
## that grew its own `Equipment.equip()` line is a caller that answers it with -1: the cursed
## chest did, then the shop did, each discovered separately.
##
## `ChestOffers` describes those boards; this describes their consequences. The two halves are
## split because the descriptions are pure content that a simulation can roll thousands of
## times, while these need a `Player` in a scene tree to charge HP and install passives.
## RunManager owns *when* they happen; nothing here knows about the run.
class_name RewardEffects
extends RefCounted

## Seconds the "Cursed: ..." toast stays up. Longer than an ordinary pickup toast: it names a
## passive the player has just lost, which is the one line they may want to read twice.
const CURSE_TOAST_SECONDS := 2.0


## Charges one Shrine option and applies its buff. Returns false when nothing was charged and
## nothing happened, so the caller can leave the board open instead of spending the shrine.
static func apply_shrine_option(option: Dictionary, live: Player) -> bool:
	# Checked before a single point of the cost is paid: a shrine that cannot do what the card
	# says must not charge for it (cleansing with no curse cost 25 HP and gave nothing).
	if not ChestOffers.shrine_option_is_usable(option, live):
		EventBus.toast.emit("Nothing to cleanse", 1.5)
		return false
	if not _charge(option, live):
		return false
	var buff := StringName(str(option.get("buff", &"might")))
	var amount := int(option.get("amount", 1))
	if buff == &"potion":
		live.add_potion(amount)
	elif buff == &"cleanse":
		cleanse_curse(live.ability_slots as AbilitySlots)
	else:
		live.add_stat(buff, amount)
	return true


## Deducts a shrine option's price in whichever currency it is quoted. False (nothing charged)
## only when the player cannot pay the gold.
static func _charge(option: Dictionary, live: Player) -> bool:
	var cost := int(option.get("cost", 0))
	match str(option.get("cost_kind", "gold")):
		"gold":
			if not live.spend_gold(cost):
				EventBus.toast.emit("Not enough gold", 1.2)
				return false
		"hp":
			live.health.hp = maxf(1.0, live.health.hp - float(cost))
			live.health.hp_changed.emit(live.health.hp, live.health.max_hp)
		"max_hp":
			live.stats.add_flat(&"max_hp", &"shrine", -float(cost))
			live.health.setup(live.stats.get_value(&"max_hp"), true)
	return true


## Installs the Curse a cursed chest's prize was bought with (docs §8) and says so in a toast.
## `replace_index` is the passive the player chose to give up when both passive slots were
## full, or -1 when a slot was free. False when there was nothing to install.
static func attach_curse(slots: AbilitySlots, curse: Ability, replace_index: int = -1) -> bool:
	if curse == null or slots == null:
		return false
	var text := "Cursed: %s" % curse.display_name
	if not slots.add(curse):
		var index := replace_index if replace_index >= 0 else AbilitySlots.PASSIVE_COUNT - 1
		var displaced := slots.replace(index, curse)
		if displaced != null:
			text = "Cursed: %s replaced %s" % [curse.display_name, displaced.display_name]
	EventBus.toast.emit(text, CURSE_TOAST_SECONDS)
	return true


## Grants a taken item to the live player, honouring the trade view's answer. `replace_index`
## indexes the list `needs_replace()` returned; -1 is "nothing was asked". Every route that
## hands the player gear goes through here: a ring family has two slots, so the answer is real
## data, and it has now been dropped on the way to `Equipment.equip()` once per caller that
## grew its own equip line.
static func grant_item(live: Player, item: ItemInstance, replace_index: int = -1) -> void:
	if live == null or item == null:
		return
	var gear := live.equipment as Equipment
	# `&""` is "the slot this item would take anyway", which is the ordinary path:
	# `Player.equip` keeps the weapon controller in step with the weapon slot.
	var slot_name: StringName = &"" if gear == null else gear.chosen_slot(item, replace_index)
	if slot_name == &"":
		live.equip(item)
	else:
		gear.equip(item, live.stats, slot_name)


## Grants a taken ability, honouring the same answer: `replace_index` is the slot the player
## chose to give up, -1 while one was free.
static func grant_ability(live: Player, ability: Ability, replace_index: int = -1) -> void:
	var slots := live.ability_slots as AbilitySlots if live != null else null
	if slots == null or ability == null:
		return
	if replace_index >= 0:
		slots.replace(replace_index, ability)
	else:
		slots.add(ability)


## What taking `offer` would displace, for the picker's trade view: every full slot of the
## family an item goes into - both rings, so "which one goes?" is answerable and Ring 2 is
## never destroyed in silence - or the ability slots a new ability would have to take.
##
## A cursed chest's prize is asked about here like any other item. It used to answer with the
## Curse's passive instead, which is a different question about a different slot: the prize
## still went on through `Player.equip`, and a player wearing two rings lost one of them
## without being shown either.
static func needs_replace(live: Player, offer: Variant) -> Array:
	if live == null:
		return []
	if offer is ItemInstance:
		var gear := live.equipment as Equipment
		return [] if gear == null else gear.occupied_items_for(offer as ItemInstance)
	var slots := live.ability_slots as AbilitySlots
	if slots == null or not (offer is Ability):
		return []
	return slots.would_need_replace(offer)


## The passives `curse` would have to displace: the *second* question a cursed board asks,
## because its prize can cost a ring and a passive slot at once and both are the player's to
## answer. Empty while a passive slot is free (the Curse simply takes it) or with no Curse.
static func curse_needs_replace(live: Player, curse: Ability) -> Array:
	if live == null or curse == null:
		return []
	var slots := live.ability_slots as AbilitySlots
	return [] if slots == null else slots.would_need_replace(curse)


## Shrine "cleanse" option: removes the first Curse passive the player carries. False when
## there was none, which the card and `ChestOffers.shrine_option_is_usable()` already refuse.
static func cleanse_curse(slots: AbilitySlots) -> bool:
	var index := ChestOffers.curse_slot_index(slots)
	if index < 0:
		return false
	slots.remove(index)
	EventBus.toast.emit("Curse lifted", 1.5)
	return true


## What the cursed chest's prize card says the prize costs. Named *and* spelled out: "Curse:
## Kernel Panic" tells a first-time player nothing about what they are agreeing to, and this is
## the one card whose price is not a number. With both passive slots full it also says the
## prize will cost one of them, because taking it then opens the replace prompt.
static func curse_card_text(curse: Ability, slots: AbilitySlots) -> String:
	if curse == null:
		return ""
	var seat := "takes a passive slot"
	if slots != null and not slots.would_need_replace(curse).is_empty():
		seat = "takes a passive slot - you choose which one it replaces"
	return "Curse: %s (%s) - %s" % [curse.display_name, seat, curse.description]
