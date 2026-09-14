## A generated item: base + rarity + rolled affixes. Serializable.
class_name ItemInstance
extends RefCounted

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES: PackedStringArray = ["Common", "Rare", "Epic", "Legendary"]
const RARITY_ROLES: Array[StringName] = [
	&"rarity_common", &"rarity_rare", &"rarity_epic", &"rarity_legendary"
]

var uid: int = 0
var base: ItemBase
var rarity: Rarity = Rarity.COMMON
var display_name: String = ""
## Array of {affix: Affix, value: float}.
var affixes: Array[Dictionary] = []
## Unique effect id for legendaries (implemented as a PassiveAbility id), or "".
var unique_effect: StringName = &""
var seed_hash: int = 0


func owner_id() -> StringName:
	return StringName("item:%d" % uid)


func slot() -> ItemBase.Slot:
	return base.slot


func is_weapon() -> bool:
	return base is WeaponBase


func rarity_role() -> StringName:
	return RARITY_ROLES[rarity]


## Registers all stat modifiers on `stats` under this item's owner id.
func apply_to(stats: Stats) -> void:
	var oid := owner_id()
	for stat: StringName in base.implicit_flat.keys():
		stats.add_flat(stat, oid, float(base.implicit_flat[stat]))
	for stat: StringName in base.implicit_percent.keys():
		stats.add_percent(stat, oid, float(base.implicit_percent[stat]))
	for entry: Dictionary in affixes:
		var affix: Affix = entry["affix"]
		var value: float = entry["value"]
		match affix.mode:
			Affix.Mode.FLAT:
				stats.add_flat(affix.stat, oid, value)
			Affix.Mode.PERCENT:
				stats.add_percent(affix.stat, oid, value)


func remove_from(stats: Stats) -> void:
	stats.remove_owner(owner_id())


## Affix lines for tooltips.
func describe_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for stat: StringName in base.implicit_flat.keys():
		lines.append("+%d %s" % [int(base.implicit_flat[stat]), String(stat).capitalize()])
	for stat: StringName in base.implicit_percent.keys():
		lines.append(
			(
				"+%d%% %s"
				% [
					int(roundf(float(base.implicit_percent[stat]) * 100.0)),
					String(stat).capitalize()
				]
			)
		)
	for entry: Dictionary in affixes:
		lines.append((entry["affix"] as Affix).describe(entry["value"]))
	return lines


func to_dict() -> Dictionary:
	var affix_data: Array = []
	for entry: Dictionary in affixes:
		affix_data.append({"id": String((entry["affix"] as Affix).id), "value": entry["value"]})
	return {
		"uid": uid,
		"base": String(base.id),
		"rarity": rarity,
		"name": display_name,
		"affixes": affix_data,
		"unique": String(unique_effect),
		"seed": seed_hash,
	}
