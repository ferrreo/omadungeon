## How the scripted player chooses between the cards a chest, altar, shop or shrine shows.
##
## There is no hand-written preference table: every card is scored by *simulating taking it*
## on a clone of the player and comparing `SimPlayer.power()` before and after. An option is
## therefore popular in the report because it is strong, not because this file says so — which
## is what makes "picked in more than 60% of runs" a usable signal about the content.
## `BalanceProfile.pick_temperature` keeps the policy a preference rather than a lookup table,
## and `power_offense_weight` says how much the player cares about damage over staying alive.
class_name SimOfferPolicy
extends RefCounted


## Picks a card. The scripted player is an *average* player, not an optimal one: cards are
## drawn with a softmax over the power gain they offer, so the strongest card usually wins but
## a close second regularly gets taken instead and a card that does nothing for this build
## (Ricochet on a sword) almost never does. `BalanceProfile.pick_temperature` is how fussy the
## player is - a small temperature is a min-maxer, a large one picks almost at random.
## Returns -1 when the row is empty.
static func pick_index(
	offers: Array, player: SimPlayer, profile: BalanceProfile, rng: RandomNumberGenerator
) -> int:
	if offers.is_empty():
		return -1
	var gains: Array[float] = []
	var best := -INF
	for offer: Variant in offers:
		var gain := score_of(offer, player, profile) - 1.0
		gains.append(gain)
		best = maxf(best, gain)
	var temperature := maxf(0.001, profile.pick_temperature)
	var weights: Array[float] = []
	var total := 0.0
	for gain: float in gains:
		var weight := exp((gain - best) / temperature)
		weights.append(weight)
		total += weight
	var roll := rng.randf() * total
	for i in range(weights.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1


## Best score in `offers` without the noise, for "would a free reroll be worth it" checks.
static func best_score(offers: Array, player: SimPlayer, profile: BalanceProfile) -> float:
	var best := 0.0
	for offer: Variant in offers:
		best = maxf(best, score_of(offer, player, profile))
	return best


## Power ratio the card would produce: 1.0 means it changes nothing.
##
## A `{"score": ratio}` card is one whose effect the caller already measured (a shrine's
## cleanse, which removes something rather than adding it); everything else is measured here
## by previewing it on a clone.
static func score_of(offer: Variant, player: SimPlayer, profile: BalanceProfile) -> float:
	if offer is int or offer is float:
		return 1.0 + float(offer) * profile.gold_power_per_coin
	if offer is Dictionary and (offer as Dictionary).has("score"):
		return float((offer as Dictionary)["score"])
	var before := player.power()
	var after := _apply_preview(offer, player)
	if after <= 0.0:
		return 0.0
	return after / maxf(0.01, before)


## Applies `offer` to a throwaway clone and returns the clone's power.
static func _apply_preview(offer: Variant, player: SimPlayer) -> float:
	var preview := player.clone()
	if offer is Dictionary:
		var entry := offer as Dictionary
		if not entry.has("stat"):
			return 0.0
		preview.add_stat(StringName(str(entry["stat"])), int(entry.get("points", 1)))
	elif offer is ItemInstance:
		preview.equip(offer as ItemInstance)
	elif offer is Ability:
		var ability := (offer as Ability).duplicate_ability()
		if not preview.take_ability(ability):
			preview.replace_ability(ability)
	else:
		return 0.0
	return preview.power()
