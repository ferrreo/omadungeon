## Catalogue of every item base and affix that can drop. Loaded from `data/items/registry.tres`.
## Pure lookups; the generator does the rolling.
class_name ItemRegistry
extends Resource

const DEFAULT_PATH := "res://data/items/registry.tres"
## How many weapon tiers below the floor's own tier may still drop (1 = the tier before this
## one is still fine, anything older is retired).
const OBSOLETE_TIER_GAP := 1

@export var bases: Array[ItemBase] = []
@export var affixes: Array[Affix] = []


## Loads the shipped registry (null if missing).
static func load_default() -> ItemRegistry:
	return load(DEFAULT_PATH) as ItemRegistry


func find_base(id: StringName) -> ItemBase:
	for base: ItemBase in bases:
		if base != null and base.id == id:
			return base
	return null


func find_affix(id: StringName) -> Affix:
	for affix: Affix in affixes:
		if affix != null and affix.id == id:
			return affix
	return null


## Bases droppable on `floor_index` for the given slots (ItemBase.Slot ints; empty = any).
## Falls back to ignoring the floor gate when nothing qualifies, so a filter never yields nothing.
##
## Weapons also fall off the bottom of the ladder: once `floor_index` reaches a tier, the
## tiers more than one step below it stop dropping, so a floor-7 chest cannot hand out a
## starting-tier weapon that is strictly worse than what the player already carries.
##
## `styles` narrows weapon bases to those `WeaponBase.Style` ints (empty = any style) and is
## what lets a chest offer a Ranger a weapon the Ranger can still be a Ranger with. A
## non-weapon base is never touched by it; a styles filter that matches nothing falls back
## with everything else.
func bases_for(
	slots: Array[int], floor_index: int, styles: PackedInt32Array = PackedInt32Array()
) -> Array[ItemBase]:
	var out: Array[ItemBase] = []
	var top_tier := ItemTuning.shared().tier_for_floor(floor_index)
	for base: ItemBase in bases:
		if base == null:
			continue
		if not slots.is_empty() and not slots.has(int(base.slot)):
			continue
		if base.min_floor > floor_index:
			continue
		var weapon := base as WeaponBase
		if weapon != null:
			if top_tier - base.tier > OBSOLETE_TIER_GAP:
				continue
			if not styles.is_empty() and not styles.has(int(weapon.style)):
				continue
		out.append(base)
	if out.is_empty():
		for base: ItemBase in bases:
			if base != null and (slots.is_empty() or slots.has(int(base.slot))):
				out.append(base)
	return out


## Affixes allowed on `slot_name` ("weapon"/"armor"/"ring"/"trinket") at `rarity` (0..3).
## Pass `base` as well whenever the concrete item is known: it applies `Affix.can_roll_on`,
## which drops affixes that would be inert on that base (projectile mods on a melee weapon,
## "+% Melee Damage" on a bow). Without it only the slot gate runs.
func affixes_for(slot_name: StringName, rarity: int, base: ItemBase = null) -> Array[Affix]:
	var out: Array[Affix] = []
	for affix: Affix in affixes:
		if affix == null or affix.min_rarity > rarity:
			continue
		if base != null:
			if not affix.can_roll_on(base):
				continue
		elif not affix.slots.is_empty() and not affix.slots.has(slot_name):
			continue
		out.append(affix)
	return out


## Every base whose slot matches (any floor).
func bases_in_slot(slot: ItemBase.Slot) -> Array[ItemBase]:
	var out: Array[ItemBase] = []
	for base: ItemBase in bases:
		if base != null and base.slot == slot:
			out.append(base)
	return out
