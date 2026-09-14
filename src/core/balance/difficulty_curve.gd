## The shape of the run's difficulty ramp, as data (`data/balance/difficulty_curve.tres`).
##
## Before this resource existed the ramp was three magic numbers buried in scripts —
## `EnemyDef.scaled_hp()`'s 0.18, `scaled_damage()`'s 0.12 and `EnemySpawner`'s
## `BASE_BUDGET + 1.2 * floor` — which made the curve impossible to shape per floor. They
## produced a sawtooth: a boss floor stacked a boss on top of a full pack budget, the floor
## after it lost the boss and gained only 12% scaling, and the run got *easier* going from
## floor 6 to floor 7.
##
## Everything here is a per-floor array of nine entries (floor index 0..8). A floor past the
## end of an array reuses its last entry, so a longer run degrades gracefully rather than
## crashing. Multipliers are absolute, not incremental: `enemy_hp[3]` is what floor 4's
## enemies are multiplied by, full stop.
class_name DifficultyCurve
extends Resource

const PATH := "res://data/balance/difficulty_curve.tres"

static var _cached: DifficultyCurve

## Multiplier on `EnemyDef.max_hp` for each floor.
@export var enemy_hp: Array[float] = [1.0, 1.18, 1.36, 1.54, 1.72, 1.9, 2.08, 2.26, 2.44]
## Multiplier on `EnemyDef.damage` for each floor.
@export var enemy_damage: Array[float] = [1.0, 1.12, 1.24, 1.36, 1.48, 1.6, 1.72, 1.84, 1.96]
## Difficulty budget one ordinary COMBAT room is worth on each floor.
@export var pack_budget: Array[float] = [3.0, 4.2, 5.4, 6.6, 7.8, 9.0, 10.2, 11.4, 12.6]
## Multiplier on `TrapDef.damage` for each floor: hazards have to keep pace with the HP pool
## or the trap layer stops mattering exactly when the generator turns its density up.
@export var trap_damage: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
## Multiplier applied on top of `enemy_hp` / `enemy_damage` for elites.
@export var elite_hp_multiplier: float = 3.0
@export var elite_damage_multiplier: float = 1.0


## The shipped curve, loaded once. Falls back to a fresh default when the resource is absent
## so a stripped export (or a unit test with no data dir) still runs.
static func shared() -> DifficultyCurve:
	if _cached != null:
		return _cached
	if ResourceLoader.exists(PATH):
		_cached = load(PATH) as DifficultyCurve
	if _cached == null:
		_cached = DifficultyCurve.new()
	return _cached


## Entry `index` of `series`, clamped to its ends. Empty series read as `fallback`.
static func at(series: Array[float], index: int, fallback: float) -> float:
	if series.is_empty():
		return fallback
	return series[clampi(index, 0, series.size() - 1)]


func hp_multiplier(floor_index: int) -> float:
	return at(enemy_hp, floor_index, 1.0)


func damage_multiplier(floor_index: int) -> float:
	return at(enemy_damage, floor_index, 1.0)


func budget_for(floor_index: int) -> float:
	return at(pack_budget, floor_index, 3.0)


func trap_multiplier(floor_index: int) -> float:
	return at(trap_damage, floor_index, 1.0)
