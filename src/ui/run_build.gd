## Turns a live `Player` into the rows the run summary renders: worn gear, the four ability
## slots, the class innate, the weapon skill and the final primaries.
##
## It lives with the UI rather than with the run because it is a presentation shape - a list
## of `{slot, name, role}` dictionaries - not simulation state. `RunManager` calls `snapshot`
## once, while the player still exists, and hands the result to `RunSummary`.
class_name RunBuild
extends RefCounted

## Slot labels printed for `Equipment.SLOTS`, in that order.
const SLOT_NAMES: Dictionary = {
	&"weapon": "Weapon",
	&"armor": "Armor",
	&"ring1": "Ring 1",
	&"ring2": "Ring 2",
	&"trinket": "Trinket",
}
const TIER_NUMERALS: PackedStringArray = ["I", "II", "III"]


## `{equipment, abilities, stats, innate}` for `live`, or an empty dictionary when there is
## no player left to read (an abandoned run). Every key is optional for the UI.
static func snapshot(live: Player) -> Dictionary:
	if live == null:
		return {}
	var out := {
		"equipment": equipment_rows(live),
		"abilities": ability_rows(live),
		"stats": stat_totals(live),
	}
	var slots := live.ability_slots as AbilitySlots
	if slots != null and not slots.innates.is_empty():
		out["innate"] = slots.innates[0].display_name
	return out


## One row per equipment slot, plus a "Skill" row naming the weapon's secondary attack.
static func equipment_rows(live: Player) -> Array:
	var out: Array = []
	var equipment := live.equipment as Equipment
	if equipment == null:
		return out
	for slot: StringName in Equipment.SLOTS:
		var item := equipment.get_item(slot)
		(
			out
			. append(
				{
					"slot": str(SLOT_NAMES.get(slot, String(slot).capitalize())),
					"name": item.display_name if item != null else "",
					"role": String(item.rarity_role()) if item != null else "",
				}
			)
		)
	var skill := weapon_skill_name(live)
	if not skill.is_empty():
		out.append({"slot": "Skill", "name": skill, "role": "accent"})
	return out


## The two active and two passive slots, named with the tier the run got them to.
static func ability_rows(live: Player) -> Array:
	var out: Array = []
	var slots := live.ability_slots as AbilitySlots
	if slots == null:
		return out
	for i in AbilitySlots.ACTIVE_COUNT:
		out.append({"slot": "Active %d" % (i + 1), "name": label(slots.actives[i]), "role": ""})
	for i in AbilitySlots.PASSIVE_COUNT:
		out.append(
			{"slot": "Passive %d" % (i + 1), "name": label(slots.passives[i]), "role": "magic"}
		)
	return out


static func stat_totals(live: Player) -> Dictionary:
	var out: Dictionary = {}
	for stat: StringName in Stats.PRIMARY:
		out[stat] = live.stats.primary(stat)
	return out


## Display name of the equipped weapon's secondary-attack skill, or "" when it has none.
static func weapon_skill_name(live: Player) -> String:
	if live == null or live.weapon_controller == null:
		return ""
	var skill := live.weapon_controller.skill
	return skill.display_name if skill != null else ""


## "Fireball II" - the ability's name plus the tier it reached. "" for an empty slot.
static func label(ability: Ability) -> String:
	if ability == null:
		return ""
	if ability.tier <= 1:
		return ability.display_name
	return "%s %s" % [ability.display_name, TIER_NUMERALS[clampi(ability.tier - 1, 0, 2)]]


## Human name for whatever dealt a hit: the enemy's `EnemyDef.display_name` when it has one,
## else the node name tidied up. Empty when the source is gone or anonymous (a scenario's
## synthetic killing blow), which the summary reads as "no killer recorded".
static func source_name(source: Node2D) -> String:
	if source == null or not is_instance_valid(source):
		return ""
	var def := source.get(&"def") as EnemyDef
	if def != null and not def.display_name.is_empty():
		return def.display_name
	var raw := String(source.name)
	return raw.capitalize() if not raw.is_empty() else ""
