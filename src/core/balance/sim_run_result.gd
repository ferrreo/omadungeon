## Everything one simulated run recorded. `SimReport` aggregates these across many runs.
class_name SimRunResult
extends RefCounted

var class_id: StringName = &""
var run_seed: int = 0
## True when the run beat the last floor (docs §15: nine floors, The Suit on floor 9).
var victory: bool = false
## 0-based floor the run died on, or -1 when it did not.
var death_floor: int = -1
## 0-based index of the deepest floor the run set foot on.
var deepest_floor: int = 0

## Per-floor series, one entry per floor entered.
var floor_seconds: Array[float] = []
var floor_hp_fraction: Array[float] = []
var floor_damage_taken: Array[float] = []
var floor_damage_dealt: Array[float] = []
var floor_gold: Array[int] = []
## Max HP at the end of each floor, so damage taken can be read as a share of the pool.
var floor_max_hp: Array[float] = []

var total_seconds: float = 0.0
var total_damage_taken: float = 0.0
var total_damage_dealt: float = 0.0
var total_gold: int = 0
var kills: int = 0
var potions_drunk: int = 0
## Seconds spent in, and damage taken from, each boss arena (indexed like
## `RunSimulator.BOSS_FLOORS`). Bosses are the spikes in the difficulty curve, so they are
## measured on their own rather than hidden inside their floor's total.
var boss_seconds: Array[float] = [0.0, 0.0, 0.0]
var boss_damage: Array[float] = [0.0, 0.0, 0.0]
var boss_kills: Array[int] = [0, 0, 0]

## Counts by `ItemInstance.Rarity` of the items the run was offered and the ones it wore.
var rarity_offered: Array[int] = [0, 0, 0, 0]
var rarity_equipped: Array[int] = [0, 0, 0, 0]
## Ability id -> how often it appeared on a card / was taken, within this run.
var abilities_offered: Dictionary = {}
var abilities_taken: Dictionary = {}
## Ability id -> tier at the end of the run.
var final_loadout: Dictionary = {}
## `ItemBase.id` of the weapon the run finished holding, and its `WeaponBase.Style` (-1 when
## the run somehow ended bare-handed). The weapon is half of what a class *is* (docs §4.3), so
## "did the class you picked survive the run?" cannot be answered without recording it: every
## other field here is blind to the single item that decides how the build fights.
var final_weapon_id: StringName = &""
var final_weapon_style: int = -1


## Records a finished floor.
func add_floor(
	seconds: float, hp_fraction: float, taken: float, dealt: float, gold: int, max_hp: float
) -> void:
	floor_max_hp.append(max_hp)
	floor_seconds.append(seconds)
	floor_hp_fraction.append(hp_fraction)
	floor_damage_taken.append(taken)
	floor_damage_dealt.append(dealt)
	floor_gold.append(gold)
	total_seconds += seconds
	total_damage_taken += taken
	total_damage_dealt += dealt
	total_gold += gold


func note_offered(id: StringName) -> void:
	abilities_offered[id] = int(abilities_offered.get(id, 0)) + 1


func note_taken(id: StringName) -> void:
	abilities_taken[id] = int(abilities_taken.get(id, 0)) + 1


## Net HP the boss of floor `index` cost this run, or 0 for an ordinary floor. Lets a report
## split what a floor charged for its rooms from what it charged for its boss, so the two can
## be asserted without either moving the other.
func boss_damage_on_floor(index: int) -> float:
	var slot := RunSimulator.BOSS_FLOORS.find(index)
	return boss_damage[slot] if slot >= 0 else 0.0


## Floors the run actually cleared: every floor on a win, all but the fatal one on a loss.
func floors_cleared() -> int:
	return deepest_floor + 1 if victory else deepest_floor


## The build this run ended with, as one comparable string: the worn weapon plus every
## ability and its tier, in a stable order.
##
## Two runs with the same signature ended as the same build. Counting distinct signatures is
## the half of "build variety" that the weapon-identity assertions could otherwise destroy: a
## chest that only ever offers the family the player started in would read as perfect class
## identity and as one build per class, and nothing in the suite could tell the two apart.
func loadout_signature() -> String:
	var parts := PackedStringArray()
	var ids: Array = final_loadout.keys()
	ids.sort()
	for id: Variant in ids:
		parts.append("%s:%d" % [String(id as StringName), int(final_loadout[id])])
	return "%s|%s" % [String(final_weapon_id), ",".join(parts)]
