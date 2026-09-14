## Persistent player profile (docs §12): unlocks, achievement counters and lifetime stats.
## Unlocks are cosmetic/option only, never stat boosts. Pure data; `SaveManager` owns I/O
## and the achievement rules that turn counters into unlocks.
##
## Unlock model: only the ids in `GATED_UNLOCKS` are ever locked. Every other id (classes,
## class actives, innates, abilities added later) is unlocked by default, so new content
## never needs a Profile edit. `unlocks` stores the explicit set (defaults + earned).
##
## A new player starts with the Fighter and earns the other three classes (docs §12): three
## classes used to be available on the first launch and only the Oligarch was gated, which left
## a first run with nothing to win. What each class costs lives in
## `data/progression/unlocks.tres` (`UnlockTable`); the *set* of gated ids is the constant
## below, so a data file that failed to load can never hand a new player everything.
class_name Profile
extends RefCounted

## Bump when the on-disk shape changes and add a step to `_migrate_step`.
const VERSION := 2

## Ids that stay locked until an achievement rule (`UnlockTable`) grants them.
const GATED_UNLOCKS: Array[StringName] = [
	&"ranger",
	&"wizard",
	&"oligarch",
	&"whirlwind",
	&"reboot",
	&"rm_rf",
	&"tiling_wm",
	&"lucky_coin",
]

## Listed explicitly in every profile: the starting class and the base ability pool.
const DEFAULT_UNLOCKS: Array[StringName] = [
	&"fighter",
	&"fireball",
	&"frost_nova",
	&"shadowstep",
	&"turret",
	&"warcry",
	&"thorns",
	&"glass_cannon",
	&"vampiric",
	&"dotfiles",
	&"ricochet",
	&"adrenaline",
	&"heavy_hands",
	&"hotkey",
]

var version: int = VERSION
var unlocks: Array[StringName] = []
## counter name (String) -> int. Keys are Strings so JSON round trips are lossless.
var counters: Dictionary = {}
var runs: int = 0
var wins: int = 0
## class id (String) -> highest floor number reached with that class.
var best_floor_per_class: Dictionary = {}
## theme name (String) -> number of wins under that theme.
var per_theme_wins: Dictionary = {}
## enemy id (String) -> number of deaths caused by it.
var deaths_by_enemy: Dictionary = {}


func _init() -> void:
	for id: StringName in DEFAULT_UNLOCKS:
		unlocks.append(id)


## True for every id that is not gated, and for gated ids once earned.
func is_unlocked(id: StringName) -> bool:
	return not GATED_UNLOCKS.has(id) or unlocks.has(id)


static func is_gated(id: StringName) -> bool:
	return GATED_UNLOCKS.has(id)


## Adds `id` to the unlock set. Returns true only when it was locked before (ungated ids
## are always unlocked, so unlocking them is a no-op that returns false).
func unlock(id: StringName) -> bool:
	if id == &"" or is_unlocked(id):
		return false
	unlocks.append(id)
	return true


## All gated ids still locked (UI: "locked" badges, stats page).
func locked_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in GATED_UNLOCKS:
		if not unlocks.has(id):
			out.append(id)
	return out


func get_counter(name: StringName) -> int:
	return int(counters.get(String(name), 0))


## Adds `amount` to a counter and returns the new value.
func add_counter(name: StringName, amount: int = 1) -> int:
	var value := get_counter(name) + amount
	counters[String(name)] = value
	return value


## Raises a counter to `value` if it is currently lower; returns the stored value.
func raise_counter(name: StringName, value: int) -> int:
	var stored := maxi(get_counter(name), value)
	counters[String(name)] = stored
	return stored


func best_floor(class_id: StringName) -> int:
	return int(best_floor_per_class.get(String(class_id), 0))


func theme_wins(theme_name: String) -> int:
	return int(per_theme_wins.get(theme_name, 0))


func to_dict() -> Dictionary:
	var unlock_list: Array = []
	for id: StringName in unlocks:
		unlock_list.append(String(id))
	return {
		"version": VERSION,
		"unlocks": unlock_list,
		"counters": counters.duplicate(),
		"stats":
		{
			"runs": runs,
			"wins": wins,
			"best_floor_per_class": best_floor_per_class.duplicate(),
			"per_theme_wins": per_theme_wins.duplicate(),
			"deaths_by_enemy": deaths_by_enemy.duplicate(),
		},
	}


## Builds a Profile from a (possibly older) dictionary. Unknown/garbage input yields a
## fresh default profile rather than null, so the game always has one.
static func from_dict(raw: Dictionary) -> Profile:
	var data := migrate(raw)
	var profile := Profile.new()
	if not is_valid(data):
		return profile
	for id: Variant in data.get("unlocks", []) as Array:
		var name := StringName(str(id))
		if not profile.unlocks.has(name):
			profile.unlocks.append(name)
	var counters := _dict(data.get("counters", {}))
	for key: Variant in counters.keys():
		profile.counters[str(key)] = _to_int(counters[key])
	var stats := _dict(data.get("stats", {}))
	profile.runs = _to_int(stats.get("runs", 0))
	profile.wins = _to_int(stats.get("wins", 0))
	profile.best_floor_per_class = _int_dict(stats.get("best_floor_per_class", {}))
	profile.per_theme_wins = _int_dict(stats.get("per_theme_wins", {}))
	profile.deaths_by_enemy = _int_dict(stats.get("deaths_by_enemy", {}))
	return profile


static func is_valid(data: Dictionary) -> bool:
	if _to_int(data.get("version", -1)) != VERSION:
		return false
	if not (data.get("unlocks", []) is Array):
		return false
	if not (data.get("counters", {}) is Dictionary):
		return false
	return data.get("stats", {}) is Dictionary


## Migration hook, one version at a time. Missing `version` means 0. A version-less dictionary
## that carries none of the v0 keys is not a profile at all (a truncated `{}`, a foreign file);
## it is returned untouched so `is_valid()` rejects it and `SaveManager` backs it up as
## `.corrupt` instead of silently replacing the player's progression with defaults.
static func migrate(raw: Dictionary) -> Dictionary:
	var data := raw.duplicate(true)
	var v := _to_int(data.get("version", 0))
	if v == 0 and not _looks_like_v0(data):
		return data
	while v < VERSION:
		data = _migrate_step(v, data)
		v += 1
		data["version"] = v
	return data


## True when `data` carries at least one key of the pre-release (v0) profile layout.
static func _looks_like_v0(data: Dictionary) -> bool:
	for key: String in [
		"unlocks", "counters", "runs", "wins", "best_floors", "theme_wins", "deaths"
	]:
		if data.has(key):
			return true
	return false


static func _migrate_step(from_version: int, data: Dictionary) -> Dictionary:
	match from_version:
		0:
			return _migrate_0_to_1(data)
		1:
			return _migrate_1_to_2(data)
	return data


## v1 handed out Ranger and Wizard to everybody; v2 gates them behind achievements. Anyone who
## already has a profile keeps both - a meta-progression change must never take a class away
## from a player who has been using it.
static func _migrate_1_to_2(old: Dictionary) -> Dictionary:
	var data := old.duplicate(true)
	var unlocks: Array = data.get("unlocks", []) if data.get("unlocks", []) is Array else []
	for id: String in ["ranger", "wizard"]:
		if not unlocks.has(id):
			unlocks.append(id)
	data["unlocks"] = unlocks
	return data


## v0 kept stats at the top level: {unlocks, counters, runs, wins, best_floors, theme_wins, deaths}.
static func _migrate_0_to_1(old: Dictionary) -> Dictionary:
	var stats := _dict(old.get("stats", {}))
	return {
		"unlocks": old.get("unlocks", []),
		"counters": old.get("counters", {}),
		"stats":
		{
			"runs": old.get("runs", stats.get("runs", 0)),
			"wins": old.get("wins", stats.get("wins", 0)),
			"best_floor_per_class": old.get("best_floors", stats.get("best_floor_per_class", {})),
			"per_theme_wins": old.get("theme_wins", stats.get("per_theme_wins", {})),
			"deaths_by_enemy": old.get("deaths", stats.get("deaths_by_enemy", {})),
		},
	}


static func _to_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return 0


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


static func _int_dict(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			out[str(key)] = _to_int(value[key])
	return out
