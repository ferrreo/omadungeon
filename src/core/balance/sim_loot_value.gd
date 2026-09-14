## What a point of `luck` is worth, measured instead of assumed.
##
## `luck` does nothing to a fight and everything to the next card: it shifts
## `ItemGenerator.rarity_weights()` up the pyramid. A value function blind to it scores Verbose
## Logging and Lucky Coin at exactly 1.0000 for every class and every build, which is how two
## rounds of "no dead options" passed with four cards that could not move the number at all.
##
## Rather than invent a conversion constant, this rolls the shipped generator: the same seeds
## at luck 0 and at luck 1, equipped on a mid-run reference build, and the mean difference in
## `SimPlayer.combat_power()` is what one point of luck buys per offered item. The figure is a
## property of `data/items/**`, so retuning affixes or rarity weights retunes it.
class_name SimLootValue
extends RefCounted

## Items rolled per luck setting. Enough that the mean moves by about a point between seeds.
const SAMPLES := 240
const MEASURE_SEED := 0x10C7
## Floor the reference build is geared to: mid-run, so the baseline is neither naked nor
## already legendary.
const REFERENCE_FLOOR := 4

static var _power_per_luck: float = -1.0


## Power ratio one point of `luck` adds to one offered item. Cached: it is a property of the
## content, not of a run.
static func power_per_luck(
	items: ItemRegistry, abilities: AbilityRegistry, profile: BalanceProfile
) -> float:
	if _power_per_luck >= 0.0:
		return _power_per_luck
	# Set before measuring so a reference build that reaches back for this figure reads 0
	# rather than recursing.
	_power_per_luck = 0.0
	_power_per_luck = _measure(items, abilities, profile)
	return _power_per_luck


## Drops the cached figure, for a test that changes the content under it.
static func forget() -> void:
	_power_per_luck = -1.0


static func _measure(
	items: ItemRegistry, abilities: AbilityRegistry, profile: BalanceProfile
) -> float:
	var def := load("res://data/classes/fighter.tres") as ClassDef
	if def == null or items == null or profile == null:
		return 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = MEASURE_SEED
	var base := SimPlayer.create(def, items, abilities, profile, rng)
	for slot: int in ItemBase.Slot.values():
		var worn := ItemGenerator.generate(items, REFERENCE_FLOOR, rng, 0.0, [slot])
		if worn != null:
			base.equip(worn)
	var before := base.combat_power()
	if before <= 0.0:
		return 0.0
	var plain := 0.0
	var lucky := 0.0
	for i in range(SAMPLES):
		var index := i % RunSimulator.FLOOR_COUNT
		plain += _gain(base, before, items, index, i, 0.0)
		lucky += _gain(base, before, items, index, i, 1.0)
	return maxf(0.0, (lucky - plain) / float(SAMPLES))


## Power ratio the item seed `sample` rolls at `luck` would add to `base`, or 0 for an item
## the build would not wear (a card nobody takes is worth nothing, not a negative).
static func _gain(
	base: SimPlayer, before: float, items: ItemRegistry, index: int, sample: int, luck: float
) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = RunRng.hash_combine(MEASURE_SEED, sample)
	var item := ItemGenerator.generate(items, index, rng, luck)
	if item == null:
		return 0.0
	var preview := base.clone()
	preview.equip(item)
	return maxf(0.0, preview.combat_power() / before - 1.0)
