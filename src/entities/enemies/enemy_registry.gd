## All enemy definitions available to the spawner. Saved as data/enemies/registry.tres.
class_name EnemyRegistry
extends Resource

@export var defs: Array[EnemyDef] = []


func find(id: StringName) -> EnemyDef:
	for def: EnemyDef in defs:
		if def != null and def.id == id:
			return def
	return null


## Non-boss defs allowed on `floor_index`, optionally filtered by elite flag.
func candidates(floor_index: int, elite: bool) -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for def: EnemyDef in defs:
		if def == null or def.is_boss or def.is_elite != elite:
			continue
		if floor_index < def.min_floor or floor_index > def.max_floor:
			continue
		out.append(def)
	return out


## Every non-boss def (the pool the room spawner draws from).
func regular_defs() -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for def: EnemyDef in defs:
		if def != null and not def.is_boss:
			out.append(def)
	return out


## Every boss def, in registry order.
func boss_defs() -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for def: EnemyDef in defs:
		if def != null and def.is_boss:
			out.append(def)
	return out
