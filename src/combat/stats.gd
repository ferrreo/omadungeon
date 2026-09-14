## Layered stat container: base + flat modifiers + percent modifiers, tagged by owner id
## so equipment/abilities can remove exactly what they added.
## Primary stats (docs §4.2): vitality, might, precision, arcana, swiftness, fortune.
## Derived/secondary stats are also stored here as keys (armor, crit_chance, ...).
class_name Stats
extends RefCounted

signal changed(stat: StringName, value: float)

const PRIMARY: Array[StringName] = [
	&"vitality", &"might", &"precision", &"arcana", &"swiftness", &"fortune"
]

## Secondary keys: values are computed with primaries via `derived()`.
const SECONDARY: Array[StringName] = [
	&"max_hp",
	&"armor",
	&"move_speed",
	&"attack_speed",
	&"crit_chance",
	&"crit_mult",
	&"cooldown_reduction",
	&"dodge_chance",
	&"life_on_kill",
	&"pickup_radius",
	&"knockback",
	&"projectile_count",
	&"projectile_speed",
	&"projectile_size",
	&"pierce",
	&"gold_find",
	&"luck",
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
	&"dodge_distance",
	&"lifesteal",
]

var _base: Dictionary = {}
## stat -> {owner_id: flat}
var _flat: Dictionary = {}
## stat -> {owner_id: percent (0.1 = +10%)}
var _percent: Dictionary = {}
var _cache: Dictionary = {}
var _dirty: bool = true


func _init() -> void:
	for stat: StringName in PRIMARY:
		_base[stat] = 0.0
	_base[&"max_hp"] = 100.0
	_base[&"move_speed"] = 90.0  # px/s
	_base[&"attack_speed"] = 1.0
	_base[&"crit_chance"] = 0.05
	_base[&"crit_mult"] = 1.5
	_base[&"pickup_radius"] = 24.0
	_base[&"knockback"] = 1.0
	_base[&"projectile_count"] = 1.0
	_base[&"projectile_speed"] = 1.0
	_base[&"projectile_size"] = 1.0
	_base[&"dodge_distance"] = 1.0
	for stat: StringName in SECONDARY:
		if not _base.has(stat):
			_base[stat] = 0.0


func set_base(stat: StringName, value: float) -> void:
	_base[stat] = value
	_invalidate(stat)


func get_base(stat: StringName) -> float:
	return float(_base.get(stat, 0.0))


func add_primary(stat: StringName, points: int) -> void:
	assert(PRIMARY.has(stat), "not a primary stat: %s" % stat)
	_base[stat] = get_base(stat) + points
	_invalidate(stat)


func add_flat(stat: StringName, owner_id: StringName, value: float) -> void:
	if not _flat.has(stat):
		_flat[stat] = {}
	_flat[stat][owner_id] = float(_flat[stat].get(owner_id, 0.0)) + value
	_invalidate(stat)


func add_percent(stat: StringName, owner_id: StringName, value: float) -> void:
	if not _percent.has(stat):
		_percent[stat] = {}
	_percent[stat][owner_id] = float(_percent[stat].get(owner_id, 0.0)) + value
	_invalidate(stat)


## Every modifier on `stat` by the owner that registered it: `{"flat": {owner: value},
## "percent": {owner: fraction}}`, copies. This is what the loadout screen reads to say
## *where* a number comes from; nothing else needs the owner table and nothing may write it.
func modifiers(stat: StringName) -> Dictionary:
	var flat: Dictionary = (_flat.get(stat, {}) as Dictionary).duplicate()
	var percent: Dictionary = (_percent.get(stat, {}) as Dictionary).duplicate()
	return {"flat": flat, "percent": percent}


## Removes every modifier registered under `owner_id`.
func remove_owner(owner_id: StringName) -> void:
	for table: Dictionary in [_flat, _percent]:
		for stat: StringName in table.keys():
			if (table[stat] as Dictionary).erase(owner_id):
				_invalidate(stat)


## Final value including primaries' derived contributions (docs §4.2 per-point table).
func get_value(stat: StringName) -> float:
	if _cache.has(stat):
		return _cache[stat]
	var value := get_base(stat) + _derived_bonus(stat)
	if _flat.has(stat):
		for v: float in (_flat[stat] as Dictionary).values():
			value += v
	var pct := 0.0
	if _percent.has(stat):
		for v: float in (_percent[stat] as Dictionary).values():
			pct += v
	value *= maxf(0.0, 1.0 + pct)
	value = _clamp_stat(stat, value)
	_cache[stat] = value
	return value


func primary(stat: StringName) -> int:
	return int(get_value(stat))


func _derived_bonus(stat: StringName) -> float:
	var vit := get_base(&"vitality") + _flat_sum(&"vitality")
	var mgt := get_base(&"might") + _flat_sum(&"might")
	var prc := get_base(&"precision") + _flat_sum(&"precision")
	var arc := get_base(&"arcana") + _flat_sum(&"arcana")
	var swf := get_base(&"swiftness") + _flat_sum(&"swiftness")
	var fort := get_base(&"fortune") + _flat_sum(&"fortune")
	match stat:
		&"max_hp":
			return 5.0 * vit
		&"damage_melee":
			return 0.04 * mgt
		&"knockback":
			return 0.01 * mgt
		&"damage_ranged":
			return 0.04 * prc
		&"crit_chance":
			return 0.01 * prc + 0.015 * fort
		&"damage_ability":
			return 0.04 * arc
		&"cooldown_reduction":
			return 0.015 * arc
		&"move_speed":
			return get_base(&"move_speed") * 0.02 * swf
		&"attack_speed":
			return 0.015 * swf
		&"dodge_distance":
			return 0.2 * floorf(swf / 5.0)
		&"gold_find":
			return 0.02 * fort
		&"dodge_chance":
			return 0.01 * fort
		&"luck":
			return 0.02 * fort
	return 0.0


func _flat_sum(stat: StringName) -> float:
	var total := 0.0
	if _flat.has(stat):
		for v: float in (_flat[stat] as Dictionary).values():
			total += v
	return total


func _clamp_stat(stat: StringName, value: float) -> float:
	match stat:
		&"dodge_chance":
			return clampf(value, 0.0, 0.25)
		&"cooldown_reduction":
			return clampf(value, 0.0, 0.6)
		&"crit_chance":
			return clampf(value, 0.0, 1.0)
		&"max_hp":
			return maxf(1.0, value)
		&"move_speed":
			return maxf(20.0, value)
		&"attack_speed":
			return maxf(0.2, value)
		&"projectile_count":
			return maxf(1.0, roundf(value))
	return value


func _invalidate(stat: StringName) -> void:
	_cache.clear()
	changed.emit(stat, get_value(stat))


## Armor formula: dmg * 100 / (100 + armor).
static func armor_multiplier(armor: float) -> float:
	return 100.0 / (100.0 + maxf(0.0, armor))


func to_dict() -> Dictionary:
	return {
		"base": _base.duplicate(),
		"flat": _flat.duplicate(true),
		"percent": _percent.duplicate(true)
	}


func from_dict(data: Dictionary) -> void:
	for key: String in (data.get("base", {}) as Dictionary).keys():
		_base[StringName(key)] = float(data["base"][key])
	_flat = {}
	for key: String in (data.get("flat", {}) as Dictionary).keys():
		_flat[StringName(key)] = {}
		for owner_key: String in (data["flat"][key] as Dictionary).keys():
			_flat[StringName(key)][StringName(owner_key)] = float(data["flat"][key][owner_key])
	_percent = {}
	for key: String in (data.get("percent", {}) as Dictionary).keys():
		_percent[StringName(key)] = {}
		for owner_key: String in (data["percent"][key] as Dictionary).keys():
			_percent[StringName(key)][StringName(owner_key)] = float(
				data["percent"][key][owner_key]
			)
	_cache.clear()
