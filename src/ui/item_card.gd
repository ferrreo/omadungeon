## What an item card says about an item, as data: the item's own numbers, and how it compares
## to the item the slot holds now. `ChestUi` renders it and `PauseMenu` reuses `item_lines()`,
## so the two screens can never disagree about what an item does.
##
## Two things live here rather than in `ItemInstance` / `Equipment`:
## * A weapon's damage, attack rate and reach are not `Stats`, so `Equipment.compare()` cannot
##   see them and `describe_lines()` never printed them. Without `weapon_lines()` the central
##   choice of the game (docs §4.5, "comparison tooltip shows deltas") is a coin flip.
## * The item's own lines and the vs-equipped deltas are two different blocks. They are
##   returned separately and never concatenated, so the card can label them.
class_name ItemCard
extends RefCounted

## Stats stored as fractions/multipliers: their deltas read as percentages, never units.
const FRACTION_STATS: Array[StringName] = [
	&"attack_speed",
	&"crit_chance",
	&"crit_mult",
	&"cooldown_reduction",
	&"dodge_chance",
	&"dodge_distance",
	&"gold_find",
	&"knockback",
	&"lifesteal",
	&"luck",
	&"projectile_size",
	&"projectile_speed",
	&"damage_melee",
	&"damage_ranged",
	&"damage_ability",
	&"damage_physical",
	&"damage_fire",
	&"damage_frost",
	&"damage_shock",
	&"damage_poison",
	&"damage_arcane",
	&"resist_fire",
	&"resist_frost",
	&"resist_shock",
	&"resist_poison",
	&"resist_arcane",
]
## Heading over the comparison block when the card cannot name what it would displace.
const COMPARE_HEADER := "vs equipped"
## Heading over a before/after block, filled with the name of the gear that would come off.
const REPLACES_HEADER := "Replaces %s"
## Shown instead of a comparison when the slot the item would go into is empty: without it the
## card would print the item's own affixes a second time as "deltas".
const EMPTY_SLOT_NOTE := "Fills an empty slot"
## Separator between the two halves of a before/after row. The stat-orb card already reads
## "Might 4 -> 5", so a swap row reads the same way.
const SWAP_ARROW := "->"
## Player-facing names for the stats a before/after row has to fit on one card line.
## `ItemGenerator.stat_label` capitalises the code identifier, which is how "Crit Mult" and
## "Cooldown Reduction" reached the screen; a card line is about twenty characters wide.
const SWAP_LABELS: Dictionary = {
	&"max_hp": "Max HP",
	&"move_speed": "Speed",
	&"attack_speed": "Rate",
	&"crit_chance": "Crit",
	&"crit_mult": "Crit dmg",
	&"cooldown_reduction": "Cooldowns",
	&"dodge_chance": "Dodge",
	&"dodge_distance": "Dodge range",
	&"gold_find": "Gold find",
	&"projectile_size": "Shot size",
	&"projectile_speed": "Shot speed",
	&"projectile_count": "Shots",
	&"pickup_radius": "Pickup range",
}
## Labels of the four weapon numbers a before/after block leads with.
const WEAPON_SWAP_LABELS: PackedStringArray = ["Damage", "Rate", "Dps", "Range"]
## What a legendary whose unique effect is not in the registry says about itself.
const UNKNOWN_UNIQUE := "Carries a unique effect"
## Pass as `max_rows` / `max_stat_rows` for "every row there is". A card that measures its own
## free space (`ChestUi.fit_rows`) has to be handed the whole list: a cap applied here cuts it
## before the card has run out of room, which is the bug this constant exists to name.
const ALL_ROWS := -1


## The item's own description rows: the weapon block first (damage, rate, dps, reach), then one
## row per stat, then the on-hit affixes and the unique effect.
##
## One row per stat matters: an item whose implicit and one of its affixes both give Might used
## to print "+2 Might" twice, which reads as a rendering bug rather than as +4.
static func item_lines(item: ItemInstance) -> PackedStringArray:
	var out: PackedStringArray = []
	if item == null or item.base == null:
		return out
	out.append_array(weapon_lines(item.base as WeaponBase))
	out.append_array(stat_lines(item))
	if item.unique_effect != &"":
		var passive := UniqueEffects.find(item.unique_effect)
		if passive != null:
			out.append("%s: %s" % [passive.display_name, passive.description])
		else:
			# A legendary whose effect is not registered must still say it has one - but it
			# may not print the effect's internal id at the player, which is what
			# `String(id).capitalize()` did ("Unique: Tiling Wm").
			out.append(UNKNOWN_UNIQUE)
	return out


## The item's stat rows, summed per (stat, mode) and in first-seen order: implicits first, then
## the affixes that rolled on it. On-hit affixes keep their own wording and are never merged.
static func stat_lines(item: ItemInstance) -> PackedStringArray:
	var out: PackedStringArray = []
	for row: Dictionary in stat_totals(item):
		out.append(
			stat_text(StringName(str(row["stat"])), float(row["value"]), bool(row["percent"]))
		)
	for text: String in on_hit_lines(item):
		out.append(text)
	return out


## Everything `item` adds to a stat, summed per (stat, mode) and in the order the item lists
## them: `[{stat: StringName, percent: bool, value: float}]`. This is the item's *own*
## contribution, which is what a before/after comparison needs on each side of the arrow -
## `Equipment.compare()` returns only the difference, and a difference cannot say what the
## number is now.
static func stat_totals(item: ItemInstance) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if item == null or item.base == null:
		return out
	var flat: Dictionary = {}
	var percent: Dictionary = {}
	var order: Array[Array] = []
	for stat: StringName in item.base.implicit_flat.keys():
		_add_stat(flat, order, stat, float(item.base.implicit_flat[stat]), false)
	for stat: StringName in item.base.implicit_percent.keys():
		_add_stat(percent, order, stat, float(item.base.implicit_percent[stat]), true)
	for entry: Dictionary in item.affixes:
		var affix: Affix = entry["affix"]
		var value := float(entry["value"])
		if affix.mode == Affix.Mode.FLAT:
			_add_stat(flat, order, affix.stat, value, false)
		elif affix.mode == Affix.Mode.PERCENT:
			_add_stat(percent, order, affix.stat, value, true)
	for key: Array in order:
		var stat := StringName(str(key[0]))
		var is_percent := bool(key[1])
		out.append(
			{
				"stat": stat,
				"percent": is_percent,
				"value": float(percent[stat]) if is_percent else float(flat[stat])
			}
		)
	return out


## The item's on-hit affix rows, which carry their own wording and never merge with a stat.
static func on_hit_lines(item: ItemInstance) -> PackedStringArray:
	var out: PackedStringArray = []
	if item == null:
		return out
	for entry: Dictionary in item.affixes:
		var affix: Affix = entry["affix"]
		if affix.mode == Affix.Mode.ON_HIT_STATUS:
			out.append(ItemGenerator.describe_affix(affix, float(entry["value"])))
	return out


## One stat row: "+2 Might", "-5% Max Hp", "+5% Physical Damage". A flat modifier on a stat that
## is stored as a fraction (damage_physical 0.05) is a percentage, never the int 0.
static func stat_text(stat: StringName, value: float, is_percent: bool) -> String:
	var sign_text := "+" if value >= 0.0 else "-"
	if is_percent or not ItemGenerator.INTEGER_STATS.has(stat):
		var shown := int(roundf(absf(value) * 100.0))
		return "%s%d%% %s" % [sign_text, shown, ItemGenerator.stat_label(stat)]
	return "%s%d %s" % [sign_text, int(absf(value)), ItemGenerator.stat_label(stat)]


static func _add_stat(
	totals: Dictionary, order: Array[Array], stat: StringName, value: float, is_percent: bool
) -> void:
	# `totals` is one of the two per-mode dictionaries, so a stat that appears as both a flat
	# and a percent keeps two rows - they are two different things.
	if not totals.has(stat):
		order.append([stat, is_percent])
	totals[stat] = float(totals.get(stat, 0.0)) + value


## The numbers a weapon lives or dies by, as two rows: "8 damage  2/s" and "16 dps  20 range",
## plus the name of its secondary attack when it has one. Empty for anything that is not a
## weapon. The reach row used to read "20 rng", which in a game with random rolls reads as the
## random number generator rather than as the weapon's reach.
static func weapon_lines(weapon: WeaponBase) -> PackedStringArray:
	if weapon == null:
		return []
	var out := PackedStringArray(
		[
			"%s damage  %s/s" % [num(weapon.base_damage), num(weapon.attacks_per_second)],
			"%s dps  %s range" % [num(dps(weapon)), num(weapon.range_px)]
		]
	)
	# The weapon skill is a whole secondary attack on its own cooldown, and the game named it
	# nowhere: not on the HUD, not on this card, not on the pause Equipment page.
	if weapon.skill != null:
		out.append("Skill: %s" % weapon.skill.display_name)
	return out


## Damage per second a weapon puts out before stats: base damage x attacks per second.
static func dps(weapon: WeaponBase) -> float:
	return weapon.base_damage * weapon.attacks_per_second if weapon != null else 0.0


## The comparison block: `{text, role}` rows for how `item` differs from `current` (the item in
## the slot it would take, null when the slot is empty) plus the `Equipment.compare()` stat
## deltas. Weapon rows come first because they are the decision on a weapon card.
## `max_stat_rows` caps the stat deltas; the weapon rows are never dropped.
static func compare_rows(
	item: ItemInstance, current: ItemInstance, stat_deltas: Dictionary, max_stat_rows: int = 4
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if item == null:
		return out
	out.append_array(weapon_delta_rows(item.base as WeaponBase, _weapon_of(current)))
	var stats := stat_delta_rows(stat_deltas)
	if max_stat_rows == ALL_ROWS:
		out.append_array(stats)
		return out
	for i in mini(stats.size(), maxi(0, max_stat_rows)):
		out.append(stats[i])
	return out


## Stat deltas hidden by `compare_rows`' cap, so the card can say how many it dropped.
static func hidden_stat_rows(stat_deltas: Dictionary, max_stat_rows: int = 4) -> int:
	return maxi(0, stat_delta_rows(stat_deltas).size() - maxi(0, max_stat_rows))


## Two rows of weapon deltas ("+4 dmg  +0.2/s", "+8 dps  +2 range"), signs always explicit.
## Empty when either side is not a weapon or nothing changed: a bow compared to a sword still
## differs in every number, but a ring compared to a ring has no weapon block at all.
static func weapon_delta_rows(item: WeaponBase, current: WeaponBase) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if item == null or current == null:
		return out
	var d_damage := item.base_damage - current.base_damage
	var d_rate := item.attacks_per_second - current.attacks_per_second
	var d_dps := dps(item) - dps(current)
	var d_range := item.range_px - current.range_px
	var first := _join_deltas([_delta_text(d_damage, " dmg"), _delta_text(d_rate, "/s")])
	if not first.is_empty():
		out.append({"text": first, "role": &""})
	var second := _join_deltas([_delta_text(d_dps, " dps"), _delta_text(d_range, " range")])
	if not second.is_empty():
		out.append({"text": second, "role": _role_for(d_dps)})
	return out


## Turns an `Equipment.compare()` dictionary into `{text, role}` rows. The unit comes from the
## stat (see FRACTION_STATS), never from the magnitude: a -0.6 armor delta is "-1 Armor",
## a +1.0 crit_mult delta is "+100% Crit mult". Rows that would render as "+0" are dropped.
static func stat_delta_rows(deltas: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys := deltas.keys()
	# Sorted by name: StringName's own `<` compares pointers, which is not stable across runs.
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for key: Variant in keys:
		var stat := StringName(str(key))
		var v := float(deltas[key])
		if is_zero_approx(v):
			continue
		var is_percent := FRACTION_STATS.has(stat)
		# Anything that would render as "+0" is noise, not information.
		var shown := int(roundf(v * 100.0)) if is_percent else int(roundf(v))
		if shown == 0:
			continue
		var sign_text := "+" if shown > 0 else ""
		var label := ItemGenerator.stat_label(stat)
		var text := (
			"%s%d%% %s" % [sign_text, shown, label]
			if is_percent
			else "%s%d %s" % [sign_text, shown, label]
		)
		out.append({"text": text, "role": _role_for(v)})
	return out


## A number as a player reads it: whole where it is whole, one decimal otherwise.
static func num(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else "%.1f" % v


static func _weapon_of(item: ItemInstance) -> WeaponBase:
	return item.base as WeaponBase if item != null and item.base != null else null


## "+4 dmg" / "-0.3/s", or "" when the change rounds away to nothing.
static func _delta_text(value: float, suffix: String) -> String:
	var shown := num(absf(value))
	if shown == "0":
		return ""
	return "%s%s%s" % ["+" if value > 0.0 else "-", shown, suffix]


static func _join_deltas(parts: PackedStringArray) -> String:
	var kept: PackedStringArray = []
	for part: String in parts:
		if not part.is_empty():
			kept.append(part)
	return "  ".join(kept)


static func _role_for(value: float) -> StringName:
	return &"heal" if value > 0.0 else &"danger"


## Player-facing name for a stat on a card line. `ItemGenerator.stat_label` capitalises the
## code identifier, which is how "Crit Mult" and "Cooldown Reduction" reached the screen.
static func swap_label(stat: StringName) -> String:
	if SWAP_LABELS.has(stat):
		return str(SWAP_LABELS[stat])
	return ItemGenerator.stat_label(stat)


## The before/after block: what each number **is now** and what it **becomes** if `item`
## replaces `current`, as `[{label, old, new, role}]` in the order a card draws them.
##
## This is not `compare_rows` with nicer wording. A delta ("-4 dmg") is the answer to a
## subtraction the player has to do in their head against a number the card never showed;
## these rows carry both sides, so the trade is readable without decoding anything. The values
## are each item's *own* contribution, which is exactly what changes when one comes off and the
## other goes on. Weapon numbers lead, because on a weapon card they are the decision.
## Rows where nothing moves are dropped; `max_rows` caps the list (see `hidden_swap_rows`).
static func swap_rows(
	item: ItemInstance, current: ItemInstance, max_rows: int = ALL_ROWS
) -> Array[Dictionary]:
	var all := all_swap_rows(item, current)
	if max_rows == ALL_ROWS:
		return all
	var out: Array[Dictionary] = []
	for i in mini(all.size(), maxi(0, max_rows)):
		out.append(all[i])
	return out


## Before/after rows `swap_rows` had to cut, so the card can say how many it dropped.
static func hidden_swap_rows(
	item: ItemInstance, current: ItemInstance, max_rows: int = ALL_ROWS
) -> int:
	if max_rows == ALL_ROWS:
		return 0
	return maxi(0, all_swap_rows(item, current).size() - maxi(0, max_rows))


## One before/after row as a card prints it: "Damage 12 -> 8".
static func swap_text(row: Dictionary) -> String:
	return "%s %s %s %s" % [str(row["label"]), str(row["old"]), SWAP_ARROW, str(row["new"])]


## Every before/after row there is for this trade, uncut. `swap_rows` is this list capped.
static func all_swap_rows(item: ItemInstance, current: ItemInstance) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if item == null:
		return out
	out.append_array(_weapon_swap_rows(item.base as WeaponBase, _weapon_of(current)))
	out.append_array(_stat_swap_rows(item, current))
	return out


## The four weapon numbers, before and after. Empty unless both sides are weapons: a ring
## compared to a ring has no weapon block, and a sword offered against an empty hand has no
## "before" to print.
static func _weapon_swap_rows(item: WeaponBase, current: WeaponBase) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if item == null or current == null:
		return out
	var pairs: Array[Vector2] = [
		Vector2(current.base_damage, item.base_damage),
		Vector2(current.attacks_per_second, item.attacks_per_second),
		Vector2(dps(current), dps(item)),
		Vector2(current.range_px, item.range_px),
	]
	for i in pairs.size():
		var pair := pairs[i]
		if is_equal_approx(pair.x, pair.y):
			continue
		out.append(
			{
				"label": WEAPON_SWAP_LABELS[i],
				"old": num(pair.x),
				"new": num(pair.y),
				"role": _role_for(pair.y - pair.x)
			}
		)
	return out


## Every stat either side touches, before and after, in "what the new item offers" order so
## the reason it is on the board comes first. A stat only the worn item has still gets a row -
## losing it is half the trade.
static func _stat_swap_rows(item: ItemInstance, current: ItemInstance) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var before: Dictionary = {}
	for row: Dictionary in stat_totals(current):
		before[_swap_key(row)] = float(row["value"])
	var seen: Dictionary = {}
	var order: Array[Dictionary] = []
	for row: Dictionary in stat_totals(item):
		order.append(row)
		seen[_swap_key(row)] = true
	for row: Dictionary in stat_totals(current):
		if not seen.has(_swap_key(row)):
			order.append({"stat": row["stat"], "percent": row["percent"], "value": 0.0})
	var after: Dictionary = {}
	for row: Dictionary in stat_totals(item):
		after[_swap_key(row)] = float(row["value"])
	for row: Dictionary in order:
		var key := _swap_key(row)
		var old_value := float(before.get(key, 0.0))
		var new_value := float(after.get(key, 0.0))
		if is_equal_approx(old_value, new_value):
			continue
		var stat := StringName(str(row["stat"]))
		var percent := bool(row["percent"])
		out.append(
			{
				"label": swap_label(stat),
				"old": _swap_value(stat, old_value, percent),
				"new": _swap_value(stat, new_value, percent),
				"role": _role_for(new_value - old_value)
			}
		)
	return out


static func _swap_key(row: Dictionary) -> String:
	return "%s|%d" % [str(row["stat"]), int(bool(row["percent"]))]


## One side of a before/after row, public: `CompareRows` prints the same value on the same
## row of the compare screen, so the two can never spell a stat two ways.
static func stat_value_text(stat: StringName, value: float, is_percent: bool) -> String:
	return _swap_value(stat, value, is_percent)


## One side of a before/after row. "None" rather than "+0": a slot the new item does not touch
## at all is a different fact from a zero roll, and "+0%" reads like a rendering bug.
static func _swap_value(stat: StringName, value: float, is_percent: bool) -> String:
	if is_zero_approx(value):
		return "none"
	if is_percent or not ItemGenerator.INTEGER_STATS.has(stat):
		return "%s%d%%" % ["+" if value > 0.0 else "-", int(roundf(absf(value) * 100.0))]
	return "%s%d" % ["+" if value > 0.0 else "-", int(roundf(absf(value)))]


## Heading over a card's comparison block. It names the thing that would come off whenever the
## board can tell the card what that is ("Replaces Rusty Sword"); "vs equipped" is the fallback
## for a board with no equipment lookup, and it is the reason the block used to be unreadable:
## a column of signed numbers against an item the card never named.
static func compare_header(replaces: String) -> String:
	if replaces.is_empty():
		return COMPARE_HEADER
	return REPLACES_HEADER % replaces


## The name a card uses for the gear it would displace: the base name ("Leather Jerkin"), not
## the rolled one ("Vital Leather Jerkin of Warding"), which is three lines of a card heading.
static func worn_name(item: ItemInstance) -> String:
	if item == null:
		return ""
	if item.base != null and not item.base.display_name.is_empty():
		return item.base.display_name
	return item.display_name
