## The comparison as a table: one row per number either side has, both values on the row,
## and the direction the trade moves it in. This is the model behind the compare screen
## (`CompareView`), the floor tooltip (`ItemTooltip`) and the loadout's item lines, so the
## three can never disagree about what a stat is worth.
##
## It exists because the trade view drew two cards and printed the differences on one of
## them, cut to "+N more" when the card ran out of room. A player comparing two rings was
## reading a list of deltas against a number the other card had scrolled off. Here every stat
## line of *both* things sits on the same row, aligned, with rows where nothing moves kept and
## dimmed rather than dropped: "this ring has no crit" is half of the trade.
##
## Row shape: `{kind, label, old, new, role}`.
##   kind   &"stat" - two short values;  &"text" - two sentences (a unique effect, an ability's
##          description) that wrap;  &"heading" - a dim caption over a block
##   role   &"heal" (the new side is better), &"danger" (worse), &"same" (no change), &"dim"
class_name CompareRows
extends RefCounted

const KIND_STAT := &"stat"
const KIND_TEXT := &"text"
const KIND_HEADING := &"heading"
const ROLE_UP := &"heal"
const ROLE_DOWN := &"danger"
const ROLE_SAME := &"same"
const ROLE_DIM := &"dim"
## Printed on a side that has no such number at all. "-" and not "0": a ring has no damage,
## and "0 damage" reads as a broken weapon rather than as "not a weapon".
const ABSENT := "-"
## Printed on a side that has an on-hit affix or a unique effect the other side lacks.
const PRESENT := "yes"
## Labels of the blocks a comparison is made of.
const WEAPON_HEADING := "Weapon"
const STATS_HEADING := "Stats"
const EFFECTS_HEADING := "Effects"
const UNIQUE_LABEL := "Unique"
const SKILL_LABEL := "Skill"
const ON_HIT_LABEL := "On hit"
const KIND_LABEL := "Kind"
const EFFECT_LABEL := "Effect"
const WEAPON_LABELS: PackedStringArray = ["Damage", "Rate", "Dps", "Range"]


## Every row for taking `incoming` in place of `outgoing`. Either may be null (an empty
## slot), in which case that side prints `ABSENT` on every row. Items compare to items,
## abilities to abilities; a mixed pair (it cannot happen on a real board) prints each side's
## own rows with the other side absent.
static func rows_for(outgoing: Variant, incoming: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if outgoing is ItemInstance or incoming is ItemInstance:
		out.append_array(item_rows(outgoing as ItemInstance, incoming as ItemInstance))
	if outgoing is Ability or incoming is Ability:
		out.append_array(ability_rows(outgoing as Ability, incoming as Ability))
	return out


## Rows that carry a number on at least one side, in the order `rows_for` gives them.
static func stat_rows(rows: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		if StringName(str(row["kind"])) == KIND_STAT:
			out.append(row)
	return out


## How many rows move in the new side's favour, against it, or not at all.
static func tally(rows: Array[Dictionary]) -> Dictionary:
	var out := {"up": 0, "down": 0, "same": 0}
	for row: Dictionary in rows:
		match StringName(str(row["role"])):
			ROLE_UP:
				out["up"] = int(out["up"]) + 1
			ROLE_DOWN:
				out["down"] = int(out["down"]) + 1
			ROLE_SAME:
				out["same"] = int(out["same"]) + 1
	return out


# ------------------------------------------------------------------ items


## The item table: weapon numbers (when either side is a weapon), then every stat either side
## touches, then the on-hit affixes, the weapon skill and the unique effect.
static func item_rows(outgoing: ItemInstance, incoming: ItemInstance) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var old_weapon := _weapon_of(outgoing)
	var new_weapon := _weapon_of(incoming)
	if old_weapon != null or new_weapon != null:
		out.append(heading(WEAPON_HEADING))
		out.append_array(weapon_rows(old_weapon, new_weapon))
	var stats := _stat_union_rows(outgoing, incoming)
	if not stats.is_empty():
		out.append(heading(STATS_HEADING))
		out.append_array(stats)
	var effects: Array[Dictionary] = []
	effects.append_array(_on_hit_rows(outgoing, incoming))
	var skill_row := _skill_row(old_weapon, new_weapon)
	if not skill_row.is_empty():
		effects.append(skill_row)
	var unique_row := _unique_row(outgoing, incoming)
	if not unique_row.is_empty():
		effects.append(unique_row)
	if not effects.is_empty():
		out.append(heading(EFFECTS_HEADING))
		out.append_array(effects)
	return out


## The four weapon numbers, one row each, both sides. A side that is not a weapon prints
## `ABSENT` and the row counts as a change in whichever direction the weapon side points.
static func weapon_rows(old_weapon: WeaponBase, new_weapon: WeaponBase) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var old_values := _weapon_values(old_weapon)
	var new_values := _weapon_values(new_weapon)
	for i in WEAPON_LABELS.size():
		var old_v := old_values[i] if old_weapon != null else -INF
		var new_v := new_values[i] if new_weapon != null else -INF
		out.append(
			stat(
				WEAPON_LABELS[i],
				ItemCard.num(old_v) if old_weapon != null else ABSENT,
				ItemCard.num(new_v) if new_weapon != null else ABSENT,
				_role(old_v, new_v)
			)
		)
	return out


static func _weapon_values(weapon: WeaponBase) -> PackedFloat64Array:
	if weapon == null:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	return PackedFloat64Array(
		[weapon.base_damage, weapon.attacks_per_second, ItemCard.dps(weapon), weapon.range_px]
	)


## Every stat either item adds, incoming's first (the reason it is on the board) and then the
## ones only the worn item has. A stat both share at the same value stays on the table as
## `ROLE_SAME`: the row is what lets a player see that nothing is lost there.
static func _stat_union_rows(outgoing: ItemInstance, incoming: ItemInstance) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var before: Dictionary = {}
	var after: Dictionary = {}
	var order: Array[Dictionary] = []
	var seen: Dictionary = {}
	for row: Dictionary in ItemCard.stat_totals(incoming):
		after[_key(row)] = float(row["value"])
		order.append(row)
		seen[_key(row)] = true
	for row: Dictionary in ItemCard.stat_totals(outgoing):
		before[_key(row)] = float(row["value"])
		if not seen.has(_key(row)):
			order.append(row)
			seen[_key(row)] = true
	for row: Dictionary in order:
		var stat_name := StringName(str(row["stat"]))
		var percent := bool(row["percent"])
		var old_value := float(before.get(_key(row), 0.0))
		var new_value := float(after.get(_key(row), 0.0))
		out.append(
			stat(
				ItemCard.swap_label(stat_name),
				_stat_text(stat_name, old_value, percent, before.has(_key(row))),
				_stat_text(stat_name, new_value, percent, after.has(_key(row))),
				_role(old_value, new_value)
			)
		)
	return out


static func _stat_text(stat_name: StringName, value: float, percent: bool, present: bool) -> String:
	if not present:
		return ABSENT
	return ItemCard.stat_value_text(stat_name, value, percent)


## One row per distinct on-hit affix wording, marking which side carries it.
static func _on_hit_rows(outgoing: ItemInstance, incoming: ItemInstance) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var old_lines := ItemCard.on_hit_lines(outgoing)
	var new_lines := ItemCard.on_hit_lines(incoming)
	var order: PackedStringArray = []
	for line: String in new_lines:
		if not order.has(line):
			order.append(line)
	for line: String in old_lines:
		if not order.has(line):
			order.append(line)
	for line: String in order:
		var had := old_lines.has(line)
		var has := new_lines.has(line)
		out.append(
			stat(
				"%s: %s" % [ON_HIT_LABEL, line],
				PRESENT if had else ABSENT,
				PRESENT if has else ABSENT,
				_presence_role(had, has)
			)
		)
	return out


static func _skill_row(old_weapon: WeaponBase, new_weapon: WeaponBase) -> Dictionary:
	if old_weapon == null and new_weapon == null:
		return {}
	var old_name := _skill_name(old_weapon)
	var new_name := _skill_name(new_weapon)
	if old_name == ABSENT and new_name == ABSENT:
		return {}
	return stat(SKILL_LABEL, old_name, new_name, ROLE_SAME if old_name == new_name else ROLE_DIM)


static func _skill_name(weapon: WeaponBase) -> String:
	if weapon == null or weapon.skill == null:
		return ABSENT
	return weapon.skill.display_name


## The unique effect, in full, on whichever side carries one. Never cut: a legendary is chosen
## for this sentence, and the old card was cutting it to "Carries a unique effect".
static func _unique_row(outgoing: ItemInstance, incoming: ItemInstance) -> Dictionary:
	var old_text := unique_text(outgoing)
	var new_text := unique_text(incoming)
	if old_text.is_empty() and new_text.is_empty():
		return {}
	var role := ROLE_SAME
	if old_text != new_text:
		role = _presence_role(not old_text.is_empty(), not new_text.is_empty())
	return text(
		UNIQUE_LABEL,
		old_text if not old_text.is_empty() else ABSENT,
		new_text if not new_text.is_empty() else ABSENT,
		role
	)


## "Tiling WM: enemies take +15% damage when ..." for an item with a unique effect, "" otherwise.
static func unique_text(item: ItemInstance) -> String:
	if item == null or item.unique_effect == &"":
		return ""
	var passive := UniqueEffects.find(item.unique_effect)
	if passive == null:
		return ItemCard.UNKNOWN_UNIQUE
	return "%s: %s" % [passive.display_name, passive.description]


# ------------------------------------------------------------------ abilities


## The ability table: kind, cooldown, damage and tier, a data-only passive's stat lines, and
## then each side's description in full.
static func ability_rows(outgoing: Ability, incoming: Ability) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var old_active := outgoing as ActiveAbility
	var new_active := incoming as ActiveAbility
	out.append(
		stat(
			KIND_LABEL,
			kind_text(outgoing),
			kind_text(incoming),
			ROLE_SAME if kind_text(outgoing) == kind_text(incoming) else ROLE_DIM
		)
	)
	if old_active != null or new_active != null:
		var old_cd := old_active.cooldown if old_active != null else -INF
		var new_cd := new_active.cooldown if new_active != null else -INF
		(
			out
			. append(
				stat(
					AbilityCard.COOLDOWN_LABEL,
					_seconds(old_active),
					_seconds(new_active),
					# Down is up: a shorter cooldown is the improvement.
					(
						_role(new_cd, old_cd)
						if old_active != null and new_active != null
						else _role(old_cd, new_cd)
					)
				)
			)
		)
		var old_dmg := old_active.damage if old_active != null else -INF
		var new_dmg := new_active.damage if new_active != null else -INF
		out.append(
			stat(
				AbilityCard.DAMAGE_LABEL,
				_amount(old_active),
				_amount(new_active),
				_role(old_dmg, new_dmg)
			)
		)
	var old_tier := outgoing.tier if outgoing != null else 0
	var new_tier := incoming.tier if incoming != null else 0
	out.append(
		stat(
			AbilityCard.TIER_LABEL,
			AbilityCard.tier_numeral(old_tier),
			AbilityCard.tier_numeral(new_tier),
			_role(float(old_tier), float(new_tier))
		)
	)
	out.append_array(_passive_stat_rows(outgoing as StatPassive, incoming as StatPassive))
	out.append(
		text(
			EFFECT_LABEL,
			outgoing.describe() if outgoing != null else ABSENT,
			incoming.describe() if incoming != null else ABSENT,
			ROLE_DIM
		)
	)
	return out


## "Active" / "Passive" for the kind row.
static func kind_text(ability: Ability) -> String:
	if ability == null:
		return ABSENT
	return "Active" if ability is ActiveAbility else "Passive"


static func _seconds(ability: ActiveAbility) -> String:
	return ABSENT if ability == null else "%ss" % ItemCard.num(ability.cooldown)


static func _amount(ability: ActiveAbility) -> String:
	if ability == null:
		return ABSENT
	return "none" if is_zero_approx(ability.damage) else ItemCard.num(ability.damage)


## Stat lines of a data-only passive, union of both sides, incoming's order first.
static func _passive_stat_rows(outgoing: StatPassive, incoming: StatPassive) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if outgoing == null and incoming == null:
		return out
	var before := AbilityCard.stat_totals(outgoing)
	var after := AbilityCard.stat_totals(incoming)
	var order: Array[Array] = []
	for key: Array in AbilityCard.stat_order(incoming):
		order.append(key)
	for key: Array in AbilityCard.stat_order(outgoing):
		if not order.has(key):
			order.append(key)
	for key: Array in order:
		var stat_name := StringName(str(key[0]))
		var percent := bool(key[1])
		var map_key := "%s|%d" % [str(stat_name), int(percent)]
		var old_value := float(before.get(map_key, 0.0))
		var new_value := float(after.get(map_key, 0.0))
		out.append(
			stat(
				ItemCard.swap_label(stat_name),
				(
					AbilityCard.stat_value(stat_name, old_value, percent)
					if before.has(map_key)
					else ABSENT
				),
				(
					AbilityCard.stat_value(stat_name, new_value, percent)
					if after.has(map_key)
					else ABSENT
				),
				_role(old_value, new_value)
			)
		)
	return out


# ------------------------------------------------------------------ row builders


static func stat(label: String, old: String, new: String, role: StringName) -> Dictionary:
	return {"kind": KIND_STAT, "label": label, "old": old, "new": new, "role": role}


static func text(label: String, old: String, new: String, role: StringName) -> Dictionary:
	return {"kind": KIND_TEXT, "label": label, "old": old, "new": new, "role": role}


static func heading(label: String) -> Dictionary:
	return {"kind": KIND_HEADING, "label": label, "old": "", "new": "", "role": ROLE_DIM}


## Direction of a change: better, worse or the same. `-INF` on a side means "absent", which
## reads as worse than any number when the new side is absent and better when the old side is.
static func _role(old_value: float, new_value: float) -> StringName:
	if old_value == -INF and new_value == -INF:
		return ROLE_SAME
	if old_value == -INF:
		return ROLE_UP if new_value >= 0.0 else ROLE_DOWN
	if new_value == -INF:
		return ROLE_DOWN if old_value >= 0.0 else ROLE_UP
	if is_equal_approx(old_value, new_value):
		return ROLE_SAME
	return ROLE_UP if new_value > old_value else ROLE_DOWN


static func _presence_role(had: bool, has: bool) -> StringName:
	if had == has:
		return ROLE_SAME
	return ROLE_UP if has else ROLE_DOWN


static func _weapon_of(item: ItemInstance) -> WeaponBase:
	return item.base as WeaponBase if item != null and item.base != null else null


static func _key(row: Dictionary) -> String:
	return "%s|%d" % [str(row["stat"]), int(bool(row["percent"]))]
