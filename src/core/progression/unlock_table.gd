## The achievement table (docs §12), as data: every gated unlock with its counter, threshold
## and the line the player reads while it is still locked.
##
## `SaveManager` evaluates it; `ClassSelect` and `RunSummary` display it. The thresholds are
## the tunable part and live in `data/progression/unlocks.tres`; the *set* of gated ids stays a
## constant in `Profile.GATED_UNLOCKS`, because a data file that failed to load must not be
## able to hand a new player everything at once. `matches_profile_gates()` is the guard that
## keeps the two in step.
class_name UnlockTable
extends Resource

const PATH := "res://data/progression/unlocks.tres"

## Fallback table, used only when `data/progression/unlocks.tres` cannot be loaded. Kept in
## step with the .tres by `tests/unit/save/unlock_table_test.gd`.
const FALLBACK: Array[Dictionary] = [
	{
		"id": &"ranger",
		"title": "The Ranger",
		"description": "Clear a floor.",
		"class": true,
		"counter": &"best_floor",
		"threshold": 1,
		"order": 10,
	},
	{
		"id": &"wizard",
		"title": "The Wizard",
		"description": "Defeat 120 enemies.",
		"class": true,
		"counter": &"kills",
		"threshold": 120,
		"order": 20,
	},
	{
		"id": &"oligarch",
		"title": "The Oligarch",
		"description": "Clear three floors in one run.",
		"class": true,
		"counter": &"best_floor",
		"threshold": 3,
		"order": 30,
	},
	{
		"id": &"tiling_wm",
		"title": "Tiling WM",
		"description": "Clear a floor without taking a hit.",
		"class": false,
		"counter": &"flawless_floors",
		"threshold": 1,
		"order": 40,
	},
	{
		"id": &"whirlwind",
		"title": "Whirlwind",
		"description": "Defeat 50 clowns.",
		"class": false,
		"counter": &"clowns_killed",
		"threshold": 50,
		"order": 50,
	},
	{
		"id": &"reboot",
		"title": "Reboot",
		"description": "Defeat 50 greybeards.",
		"class": false,
		"counter": &"greybeards_killed",
		"threshold": 50,
		"order": 60,
	},
	{
		"id": &"rm_rf",
		"title": "rm -rf",
		"description": "Defeat 50 tinkerers.",
		"class": false,
		"counter": &"tinkerers_killed",
		"threshold": 50,
		"order": 70,
	},
	{
		"id": &"lucky_coin",
		"title": "Lucky Coin",
		"description": "Earn 1000 gold across your runs.",
		"class": false,
		"counter": &"gold_earned",
		"threshold": 1000,
		"order": 80,
	},
]

@export var entries: Array[UnlockDef] = []


## The tuned table from `data/progression/`, or the built-in fallback when it is missing.
static func load_default() -> UnlockTable:
	if ResourceLoader.exists(PATH):
		var res := load(PATH) as UnlockTable
		if res != null and not res.entries.is_empty():
			return res
	return from_fallback()


## The built-in table as a resource, for the fallback path and for tests.
static func from_fallback() -> UnlockTable:
	var table := UnlockTable.new()
	for row: Dictionary in FALLBACK:
		var def := UnlockDef.new()
		def.id = row["id"]
		def.title = row["title"]
		def.description = row["description"]
		def.kind = UnlockDef.Kind.CLASS if bool(row["class"]) else UnlockDef.Kind.ABILITY
		def.counter = row["counter"]
		def.threshold = int(row["threshold"])
		def.order = int(row["order"])
		table.entries.append(def)
	return table


## Entries in board order (`UnlockDef.order`, then id).
func ordered() -> Array[UnlockDef]:
	var out := entries.duplicate()
	out.sort_custom(
		func(a: UnlockDef, b: UnlockDef) -> bool:
			if a.order != b.order:
				return a.order < b.order
			return String(a.id) < String(b.id)
	)
	var typed: Array[UnlockDef] = []
	for def: UnlockDef in out:
		typed.append(def)
	return typed


func find(id: StringName) -> UnlockDef:
	for def: UnlockDef in entries:
		if def != null and def.id == id:
			return def
	return null


## Every id the table gates.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def: UnlockDef in ordered():
		if def != null and def.id != &"":
			out.append(def.id)
	return out


## Only the class unlocks, in board order: the ladder a new player is shown.
func class_entries() -> Array[UnlockDef]:
	var out: Array[UnlockDef] = []
	for def: UnlockDef in ordered():
		if def != null and def.grants_class():
			out.append(def)
	return out


## True when the table gates exactly the ids `Profile.GATED_UNLOCKS` says are gated. A
## mismatch means either an unlock nothing can ever earn, or an id the profile hands out free.
func matches_profile_gates() -> bool:
	var mine := ids()
	if mine.size() != Profile.GATED_UNLOCKS.size():
		return false
	for id: StringName in Profile.GATED_UNLOCKS:
		if not mine.has(id):
			return false
	return true
