## The docs §2 step between class select and floor 1: "Pick 1 starting passive". Pure rolling
## logic, so the choice is a function of (registry, class, what the player already has, RNG)
## and nothing else; `RunManager` owns showing it and applying the pick.
class_name StartingPassive
extends RefCounted

## Cards the player chooses between.
const COUNT := 3
## Extra draws, because `AbilityRegistry.offer` tops a short passive pool up with actives and
## because rewards the profile has not unlocked yet are dropped: the row should still be full.
const HEADROOM := 4
## Offer-UI context for the pick: its own title, and no skip bonus (it cannot be skipped).
const CONTEXT: Dictionary = {"title": "Starting Passive", "skip_gold": 0}


## Up to `COUNT` distinct unlocked passives `class_id` may start with. `owned` is the
## id -> tier map of what the player already carries (innates included), so a class innate is
## never offered back. Draw from the run's `loot` stream: the opening decision is part of the
## seed, not of the wall clock.
static func roll(
	registry: AbilityRegistry,
	rng: RandomNumberGenerator,
	class_id: StringName,
	owned: Dictionary,
	is_unlocked: Callable = Callable()
) -> Array:
	var offers: Array = []
	if registry == null or rng == null:
		return offers
	var pool := registry.offer(rng, COUNT + HEADROOM, class_id, owned, Ability.Kind.PASSIVE)
	for ability: Ability in pool:
		if offers.size() >= COUNT:
			break
		if ability.kind != Ability.Kind.PASSIVE:
			continue
		if is_unlocked.is_valid() and not bool(is_unlocked.call(ability.id)):
			continue
		offers.append(ability)
	return offers
