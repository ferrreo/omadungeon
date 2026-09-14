## Cursed-chest pact: a `StatPassive` that trades a downside for an upside. Weight 0 keeps
## curses out of normal offers; RunManager only hands them out from a CURSED chest, and
## `AbilityRegistry.is_offerable()` refuses anything whose id starts with `curse_`.
##
## It is its own class rather than a bare `StatPassive` because several systems ask "is this
## thing a curse?" — the shrine's cleanse option, the run summary and the balance simulation.
class_name CursePassive
extends StatPassive

## Fraction of *all* outgoing damage the pact removes (0.2 = the card's "-20% damage dealt").
## It is a multiplier on the finished hit rather than a `damage_melee`/`damage_ranged`/
## `damage_ability` modifier, because those are additive *bonus* stats consumed as
## `1.0 + value`: subtracting 0.2 from them cuts a Might-6 Fighter by 16% and a Might-25 build
## by 10%, so the curse would get cheaper exactly as the build it is pricing gets stronger.
@export var damage_penalty: float = 0.0


## Applies the pact's flat damage cut to every hit the carrier lands. Curses are `max_tier`
## 1, so the penalty does not scale with tier.
func outgoing_damage_multiplier(_player: Node2D, _target: Node2D, _info: DamageInfo) -> float:
	return maxf(0.0, 1.0 - damage_penalty)
