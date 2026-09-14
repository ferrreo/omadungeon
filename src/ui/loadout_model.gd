## What a player has right now, as data: the class, the four ability slots, the innate and
## the weapon skill, every equipment slot, and the full stat sheet with where each number
## comes from. `LoadoutScreen` renders it; the compare screen and the floor tooltip read the
## same item and ability rows (`CompareRows`), so "what I have" and "what I would have" can
## never disagree.
##
## `player` is duck-typed the way the HUD reads it: `stats`, `equipment` (with `slots`),
## `ability_slots` (`actives`, `passives`, `innates`), `weapon_controller.skill` and
## `class_def`. Every key is optional; a fake with half of them still renders a screen.
class_name LoadoutModel
extends RefCounted

## Slot captions in the order the screen lists them, keyed by the `Equipment.SLOTS` name.
## The fakes spell the two ring slots `ring_1`/`ring_2`; both spellings resolve.
const SLOT_ROWS: Array[Dictionary] = [
	{"label": "Weapon", "keys": ["weapon"]},
	{"label": "Armor", "keys": ["armor"]},
	{"label": "Ring", "keys": ["ring1", "ring_1"]},
	{"label": "Ring", "keys": ["ring2", "ring_2"]},
	{"label": "Trinket", "keys": ["trinket"]},
]
## The derived numbers the sheet prints, in order, with how each is formatted.
const DERIVED: Array[Dictionary] = [
	{"stat": &"max_hp", "label": "Max HP", "fmt": "int"},
	{"stat": &"armor", "label": "Armor", "fmt": "int"},
	{"stat": &"move_speed", "label": "Move speed", "fmt": "int"},
	{"stat": &"attack_speed", "label": "Attack speed", "fmt": "mult"},
	{"stat": &"crit_chance", "label": "Crit chance", "fmt": "pct"},
	{"stat": &"crit_mult", "label": "Crit damage", "fmt": "mult"},
	{"stat": &"cooldown_reduction", "label": "Cooldowns", "fmt": "pct"},
	{"stat": &"dodge_chance", "label": "Dodge chance", "fmt": "pct"},
	{"stat": &"gold_find", "label": "Gold find", "fmt": "pct"},
	{"stat": &"damage_melee", "label": "Melee damage", "fmt": "bonus"},
	{"stat": &"damage_ranged", "label": "Ranged damage", "fmt": "bonus"},
	{"stat": &"damage_ability", "label": "Ability damage", "fmt": "bonus"},
	{"stat": &"lifesteal", "label": "Lifesteal", "fmt": "pct"},
	{"stat": &"life_on_kill", "label": "Life on kill", "fmt": "int"},
]
## Which primary each derived number grows from (docs 4.2), for the sources column.
const DERIVED_FROM: Dictionary = {
	&"max_hp": &"vitality",
	&"damage_melee": &"might",
	&"knockback": &"might",
	&"damage_ranged": &"precision",
	&"crit_chance": &"precision",
	&"damage_ability": &"arcana",
	&"cooldown_reduction": &"arcana",
	&"move_speed": &"swiftness",
	&"attack_speed": &"swiftness",
	&"gold_find": &"fortune",
	&"dodge_chance": &"fortune",
	&"luck": &"fortune",
}
## Name printed for a source the model cannot name (a modifier registered by something that
## is neither worn gear nor a slotted ability).
const OTHER_SOURCE := "Other"
const CLASS_SOURCE := "Class"
const ORBS_SOURCE := "Orbs"
const NO_CLASS := "Adventurer"
const EMPTY_SLOT := "Empty"


## The whole screen as one dictionary. See the class comment for the keys.
static func build(player: Node) -> Dictionary:
	var stats := stats_of(player)
	return {
		"class": class_name_of(player),
		"actives": ability_list(player, "actives", AbilitySlots.ACTIVE_COUNT),
		"passives": ability_list(player, "passives", AbilitySlots.PASSIVE_COUNT),
		"innates": ability_list(player, "innates", -1),
		"skill": weapon_skill(player),
		"equipment": equipment_rows(player),
		"stats": stat_rows(player, stats),
	}


## The class's display name, or a neutral word when the player carries no class definition.
static func class_name_of(player: Node) -> String:
	if player == null:
		return NO_CLASS
	var def := player.get("class_def") as ClassDef
	if def != null and not def.display_name.is_empty():
		return def.display_name
	return NO_CLASS


static func stats_of(player: Node) -> Stats:
	if player == null:
		return null
	return player.get("stats") as Stats


## `count` entries of `field` on the player's ability slots, padded with null; -1 takes the
## whole list as it is (the innates).
static func ability_list(player: Node, field: String, count: int) -> Array:
	var out: Array = []
	var slots: Variant = player.get("ability_slots") if player != null else null
	var list: Variant = (slots as Object).get(field) if slots is Object else null
	if list is Array:
		for entry: Variant in list as Array:
			out.append(entry if entry is Ability else null)
	if count < 0:
		return out
	while out.size() < count:
		out.append(null)
	return out.slice(0, count)


## The ability the weapon's secondary attack fires, or null.
static func weapon_skill(player: Node) -> Ability:
	if player == null:
		return null
	var controller: Variant = player.get("weapon_controller")
	if not (controller is Node) or not is_instance_valid(controller as Node):
		return null
	return (controller as Node).get("skill") as Ability


## One row per equipment slot: `{label, item}` with `item` null for an empty one.
static func equipment_rows(player: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var slots := _slots_of(player)
	for row: Dictionary in SLOT_ROWS:
		var item: ItemInstance = null
		for key: String in row["keys"] as Array:
			var found: Variant = slots.get(key, slots.get(StringName(key)))
			if found is ItemInstance:
				item = found as ItemInstance
				break
		out.append({"label": str(row["label"]), "item": item})
	return out


## The worn item dictionary, whatever shape the player keeps it in.
static func _slots_of(player: Node) -> Dictionary:
	if player == null:
		return {}
	var equipment: Variant = player.get("equipment")
	if equipment == null:
		return {}
	var slots: Variant = (equipment as Object).get("slots") if equipment is Object else equipment
	return slots as Dictionary if slots is Dictionary else {}


## The stat sheet: the six primaries, then `DERIVED`, each `{label, value, sources, primary}`.
## `sources` names where the number comes from in the order it was earned: the class base,
## stat orbs, then each item and ability by name.
static func stat_rows(player: Node, stats: Stats) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if stats == null:
		return out
	var names := source_names(player)
	var class_base := _class_base(player)
	for stat: StringName in Stats.PRIMARY:
		var parts: PackedStringArray = []
		var base := stats.get_base(stat)
		if class_base.has(stat):
			var from_class := float(class_base[stat])
			parts.append("%s %d" % [CLASS_SOURCE, int(from_class)])
			var orbs := int(roundf(base - from_class))
			if orbs != 0:
				parts.append("%s %+d" % [ORBS_SOURCE, orbs])
		elif base != 0.0:
			parts.append("%s %d" % [CLASS_SOURCE, int(base)])
		parts.append_array(_modifier_parts(stats, stat, names, true))
		(
			out
			. append(
				{
					"stat": stat,
					"label": String(stat).capitalize(),
					"value": str(stats.primary(stat)),
					"sources": ", ".join(parts),
					"primary": true,
				}
			)
		)
	for entry: Dictionary in DERIVED:
		var stat := StringName(str(entry["stat"]))
		var parts: PackedStringArray = []
		var from := StringName(str(DERIVED_FROM.get(stat, &"")))
		if from != &"":
			parts.append("%s %d" % [String(from).capitalize(), stats.primary(from)])
		parts.append_array(_modifier_parts(stats, stat, names, false))
		(
			out
			. append(
				{
					"stat": stat,
					"label": str(entry["label"]),
					"value": format_stat(stats, stat, str(entry["fmt"])),
					"sources": ", ".join(parts),
					"primary": false,
				}
			)
		)
	return out


## "Rusty Sword +2, Thorns +10%" for the modifiers on `stat`, named by `names`.
static func _modifier_parts(
	stats: Stats, stat: StringName, names: Dictionary, integer: bool
) -> PackedStringArray:
	var out: PackedStringArray = []
	var mods := stats.modifiers(stat)
	for owner: Variant in (mods["flat"] as Dictionary).keys():
		var value := float(mods["flat"][owner])
		if is_zero_approx(value):
			continue
		var who := str(names.get(owner, OTHER_SOURCE))
		if integer or ItemGenerator.INTEGER_STATS.has(stat):
			out.append("%s %+d" % [who, int(roundf(value))])
		else:
			out.append("%s %+d%%" % [who, int(roundf(value * 100.0))])
	for owner: Variant in (mods["percent"] as Dictionary).keys():
		var value := float(mods["percent"][owner])
		if is_zero_approx(value):
			continue
		out.append("%s %+d%%" % [str(names.get(owner, OTHER_SOURCE)), int(roundf(value * 100.0))])
	return out


## Owner id -> display name for everything the player carries that registers modifiers.
static func source_names(player: Node) -> Dictionary:
	var out: Dictionary = {}
	for row: Dictionary in equipment_rows(player):
		var item := row["item"] as ItemInstance
		if item != null:
			out[item.owner_id()] = ItemCard.worn_name(item)
	for field: String in ["actives", "passives", "innates"]:
		for ability: Variant in ability_list(player, field, -1):
			var passive := ability as PassiveAbility
			if passive != null:
				out[passive.owner_id()] = passive.display_name
	return out


static func _class_base(player: Node) -> Dictionary:
	if player == null:
		return {}
	var def := player.get("class_def") as ClassDef
	return def.base_stats() if def != null else {}


## One derived value as the sheet prints it.
static func format_stat(stats: Stats, stat: StringName, fmt: String) -> String:
	var v := stats.get_value(stat)
	match fmt:
		"pct":
			return "%d%%" % int(roundf(v * 100.0))
		"mult":
			return "x%.2f" % v
		"bonus":
			# A damage stat is a multiplier *bonus*: 0.24 is "+24% melee damage", not "24%".
			return "%+d%%" % int(roundf(v * 100.0))
	return str(int(roundf(v)))


## "Fireball II" - the ability's name plus the tier it reached; `EMPTY_SLOT` for none.
static func ability_title(ability: Ability) -> String:
	if ability == null:
		return EMPTY_SLOT
	return CompareView.title_for(ability)


## "Potion - heals 40% of max HP (1/2)": what the potion does and how many the run holds.
static func potion_text(player: Node) -> String:
	var percent := int(roundf(Player.POTION_HEAL_FRACTION * 100.0))
	var held: Variant = player.get("potions") if player != null else null
	var cap: Variant = player.get("max_potions") if player != null else null
	if held == null or cap == null:
		return "Heals %d%% of max HP" % percent
	return "Heals %d%% of max HP  (%d/%d)" % [percent, int(held), int(cap)]


## The one-line summary of an item as the loadout lists it: its own lines joined.
static func item_summary(item: ItemInstance) -> String:
	if item == null:
		return ""
	return ", ".join(ItemCard.item_lines(item))
