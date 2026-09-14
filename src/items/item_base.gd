## Base type of an item (Rusty Sword, Leather Armor, ...). Generated ItemInstances reference one.
class_name ItemBase
extends Resource

enum Slot { WEAPON, ARMOR, RING, TRINKET }

@export var id: StringName = &""
@export var display_name: String = "Item"
@export var slot: Slot = Slot.WEAPON
@export var icon: Texture2D
## Implicit stat bonuses every instance has: {stat: flat}.
@export var implicit_flat: Dictionary = {}
@export var implicit_percent: Dictionary = {}
## Minimum floor before it can drop.
@export var min_floor: int = 0
## Power tier on the item ladder (0 = starting gear, 1 = mid-run, 2 = late run). For weapons
## this is a contract: a tier-`t` base is authored to `ItemTuning.weapon_tier_dps[t]` and is
## gated behind `ItemTuning.weapon_tier_min_floor[t]`, so a later base is never a downgrade.
@export var tier: int = 0
@export var weight: float = 1.0
## Author-time sprite variant hint for procedural icons.
@export var proc_sprite_family: StringName = &""


func slot_name() -> StringName:
	return StringName((Slot.keys()[slot] as String).to_lower())
