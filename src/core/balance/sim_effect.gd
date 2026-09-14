## Everything one ability contributes to the scripted player that is not a plain `Stats`
## modifier. Effects from several abilities are folded together with `merge()`, so the order
## abilities were taken in never changes the result.
class_name SimEffect
extends RefCounted

## Flat damage per second added on top of the weapon.
var dps: float = 0.0
## Multiplier on every point of damage the player deals.
var damage_mult: float = 1.0
## Multiplier on the damage the player's *actives* deal (Overflow's free cast).
var ability_damage_mult: float = 1.0
## Multiplier on how often actives come off cooldown (Hotkey's refund, Overflow's free cast).
var ability_rate_mult: float = 1.0
## Share of the damage dealt that is healed back.
var lifesteal: float = 0.0
## Share of melee damage taken that is returned to the attacker.
var reflect: float = 0.0
## Flat damage every melee hit taken returns on top of that share (Thorns anchors part of its
## retaliation to the wearer's own max HP, so the card does not get weaker as the build gets
## better at not being hit hard).
var reflect_per_hit: float = 0.0
## HP restored per second of fighting (Reboot, Bulwark's shield).
var heal_per_second: float = 0.0
## Share of incoming damage removed by crowd control and conversions.
var mitigation: float = 0.0
## Added to the share of incoming attacks the player avoids outright.
var avoid: float = 0.0
## Extra damage fraction per gold coin carried (the Oligarch's Buyout), and the most that
## term may ever be worth. Folded in `SimPlayer.dps()` because it moves with the purse rather
## than with the loadout.
var damage_per_gold: float = 0.0
var damage_per_gold_cap: float = 0.0


## Folds `other` into this effect: rates and multipliers multiply, shares add.
func merge(other: SimEffect) -> void:
	dps += other.dps
	damage_mult *= other.damage_mult
	ability_damage_mult *= other.ability_damage_mult
	ability_rate_mult *= other.ability_rate_mult
	lifesteal += other.lifesteal
	reflect += other.reflect
	reflect_per_hit += other.reflect_per_hit
	heal_per_second += other.heal_per_second
	mitigation = 1.0 - (1.0 - mitigation) * (1.0 - other.mitigation)
	avoid += other.avoid
	damage_per_gold += other.damage_per_gold
	damage_per_gold_cap += other.damage_per_gold_cap
