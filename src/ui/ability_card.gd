## What an ability card says about a trade, as data: what each of an ability's numbers **is
## now** and what it **becomes** if another ability takes its slot. `ChestUi` renders it, the
## same way it renders `ItemCard.swap_rows` for gear, so the two halves of an offer board can
## never disagree about how a before/after row is written.
##
## This exists because the ability half of the picker printed no numbers at all. An item card
## has carried live deltas since the comparison work landed; an ability card carried a
## description and a subtitle, so a player weighing a six second cooldown against a ten second
## one was doing the arithmetic in their head against a number on the other card.
##
## Rows are the same shape `ItemCard` produces (`{label, old, new, role}`) and are printed with
## `ItemCard.swap_text`, so "Cooldown 10s -> 6s" reads exactly like "Damage 12 -> 8".
class_name AbilityCard
extends RefCounted

## Labels of the numbers an active ability lives or dies by.
const COOLDOWN_LABEL := "Cooldown"
const DAMAGE_LABEL := "Damage"
## Tier is the one number both kinds share, and a tier II card replacing a tier I one is a
## real upgrade the old board stated only inside the name.
const TIER_LABEL := "Tier"
const TIER_NUMERALS: PackedStringArray = ["I", "II", "III"]
## What a side of a row says when that ability has no such number at all (a passive has no
## cooldown, and "0s" would read as an instant recharge rather than as "not applicable").
const ABSENT := "-"


## The before/after rows for taking `incoming` in the slot `outgoing` occupies, in the order a
## card draws them: the numbers an active is chosen on first, then the stat contributions of a
## data-only passive, then the tier.
##
## Empty when the two sides share no comparable number - two rule-shaped passives ("reflect
## melee damage" against "kills refund cooldown") have nothing to subtract, and inventing a
## row for them would be a worse lie than printing none.
static func all_swap_rows(incoming: Ability, outgoing: Ability) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if incoming == null:
		return out
	out.append_array(_active_rows(incoming as ActiveAbility, outgoing as ActiveAbility))
	out.append_array(_stat_rows(incoming as StatPassive, outgoing as StatPassive))
	out.append_array(_tier_rows(incoming, outgoing))
	return out


## `all_swap_rows` cut to `max_rows` (negative = no cap, which is what a card that measures its
## own free space asks for).
static func swap_rows(
	incoming: Ability, outgoing: Ability, max_rows: int = -1
) -> Array[Dictionary]:
	var all := all_swap_rows(incoming, outgoing)
	if max_rows < 0 or all.size() <= max_rows:
		return all
	var out: Array[Dictionary] = []
	for i in maxi(0, max_rows):
		out.append(all[i])
	return out


## Rows `swap_rows` had to cut, so a card can say how many it dropped.
static func hidden_swap_rows(incoming: Ability, outgoing: Ability, max_rows: int = -1) -> int:
	if max_rows < 0:
		return 0
	return maxi(0, all_swap_rows(incoming, outgoing).size() - maxi(0, max_rows))


## The subtitle number an ability card leads with: "Active  CD 6s" / "Passive". Kept here so
## the swap rows and the subtitle can never quote two different cooldowns.
static func subtitle_for(ability: Ability) -> String:
	if ability == null:
		return ""
	var active := ability as ActiveAbility
	if active == null:
		return "Passive"
	# "CD", not "6s cooldown": the long form wraps the subtitle at the 140 px card width and
	# the line it costs comes out of the description. The pause page spells it out.
	return "Active  CD %ss" % ItemCard.num(active.cooldown)


## Cooldown and damage, before and after. A shorter cooldown and a bigger number are both
## improvements, so the cooldown row's role is inverted: it is the one number on either card
## where down is up.
static func _active_rows(incoming: ActiveAbility, outgoing: ActiveAbility) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if incoming == null and outgoing == null:
		return out
	var new_cd := incoming.cooldown if incoming != null else 0.0
	var old_cd := outgoing.cooldown if outgoing != null else 0.0
	if not is_equal_approx(new_cd, old_cd):
		out.append(
			{
				"label": COOLDOWN_LABEL,
				"old": _seconds(outgoing, old_cd),
				"new": _seconds(incoming, new_cd),
				"role": _role_for(old_cd - new_cd)
			}
		)
	var new_dmg := incoming.damage if incoming != null else 0.0
	var old_dmg := outgoing.damage if outgoing != null else 0.0
	if not is_equal_approx(new_dmg, old_dmg):
		out.append(
			{
				"label": DAMAGE_LABEL,
				"old": _amount(outgoing, old_dmg),
				"new": _amount(incoming, new_dmg),
				"role": _role_for(new_dmg - old_dmg)
			}
		)
	return out


## The stat contributions of a `StatPassive`, before and after - the passive equivalent of an
## item's affix rows. Only these passives can be compared numerically: every other one is a
## rule rather than a number, and its description is the comparison.
static func _stat_rows(incoming: StatPassive, outgoing: StatPassive) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if incoming == null and outgoing == null:
		return out
	var before := _stat_totals(outgoing)
	var after := _stat_totals(incoming)
	var order: Array[Array] = []
	for key: Array in _stat_order(incoming):
		order.append(key)
	for key: Array in _stat_order(outgoing):
		if not order.has(key):
			order.append(key)
	for key: Array in order:
		var stat := StringName(str(key[0]))
		var percent := bool(key[1])
		var map_key := _stat_key(stat, percent)
		var old_value := float(before.get(map_key, 0.0))
		var new_value := float(after.get(map_key, 0.0))
		if is_equal_approx(old_value, new_value):
			continue
		out.append(
			{
				"label": ItemCard.swap_label(stat),
				"old": _stat_value(stat, old_value, percent),
				"new": _stat_value(stat, new_value, percent),
				"role": _role_for(new_value - old_value)
			}
		)
	return out


static func _tier_rows(incoming: Ability, outgoing: Ability) -> Array[Dictionary]:
	var new_tier := incoming.tier if incoming != null else 0
	var old_tier := outgoing.tier if outgoing != null else 0
	if new_tier == old_tier or outgoing == null:
		return []
	return [
		{
			"label": TIER_LABEL,
			"old": tier_numeral(old_tier),
			"new": tier_numeral(new_tier),
			"role": _role_for(float(new_tier - old_tier))
		}
	]


## "II" for tier 2. Roman on purpose: it is how the ability's own name is written.
static func tier_numeral(tier: int) -> String:
	if tier <= 0:
		return ABSENT
	return TIER_NUMERALS[clampi(tier - 1, 0, TIER_NUMERALS.size() - 1)]


static func _seconds(ability: ActiveAbility, value: float) -> String:
	return ABSENT if ability == null else "%ss" % ItemCard.num(value)


static func _amount(ability: ActiveAbility, value: float) -> String:
	if ability == null:
		return ABSENT
	return "none" if is_zero_approx(value) else ItemCard.num(value)


## Public faces of the three helpers below, for `CompareRows`: the compare screen prints a
## passive's stat contribution on the same row, in the same spelling, as the offer card does.
static func stat_totals(passive: StatPassive) -> Dictionary:
	return _stat_totals(passive)


static func stat_order(passive: StatPassive) -> Array[Array]:
	return _stat_order(passive)


static func stat_value(stat: StringName, value: float, percent: bool) -> String:
	return _stat_value(stat, value, percent)


## Every stat a `StatPassive` touches at its current tier, summed per (stat, mode).
static func _stat_totals(passive: StatPassive) -> Dictionary:
	var out: Dictionary = {}
	if passive == null:
		return out
	for i in range(mini(passive.percent_stats.size(), passive.percent_values.size())):
		var key := _stat_key(passive.percent_stats[i], true)
		out[key] = float(out.get(key, 0.0)) + passive.percent_values[i] * passive.tier
	for i in range(mini(passive.flat_stats.size(), passive.flat_values.size())):
		var key := _stat_key(passive.flat_stats[i], false)
		out[key] = float(out.get(key, 0.0)) + passive.flat_values[i] * passive.tier
	return out


## The (stat, is_percent) pairs `passive` lists, in the order it lists them.
static func _stat_order(passive: StatPassive) -> Array[Array]:
	var out: Array[Array] = []
	if passive == null:
		return out
	for i in range(mini(passive.percent_stats.size(), passive.percent_values.size())):
		var key: Array = [passive.percent_stats[i], true]
		if not out.has(key):
			out.append(key)
	for i in range(mini(passive.flat_stats.size(), passive.flat_values.size())):
		var key: Array = [passive.flat_stats[i], false]
		if not out.has(key):
			out.append(key)
	return out


static func _stat_key(stat: StringName, percent: bool) -> String:
	return "%s|%d" % [str(stat), int(percent)]


## One side of a stat row. "none" rather than "+0%": a passive that does not touch the stat at
## all is a different fact from one that rolled a zero.
static func _stat_value(stat: StringName, value: float, percent: bool) -> String:
	if is_zero_approx(value):
		return "none"
	if percent or not ItemGenerator.INTEGER_STATS.has(stat):
		return "%s%d%%" % ["+" if value > 0.0 else "-", int(roundf(absf(value) * 100.0))]
	return "%s%d" % ["+" if value > 0.0 else "-", int(roundf(absf(value)))]


static func _role_for(value: float) -> StringName:
	return &"heal" if value > 0.0 else &"danger"
