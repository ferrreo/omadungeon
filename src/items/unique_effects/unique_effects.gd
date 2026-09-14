## Registry of legendary unique effects: each is a PassiveAbility subclass under this folder.
## `find(id)` returns a fresh instance so every legendary item owns its own state.
class_name UniqueEffects
extends RefCounted

const SCRIPTS: Dictionary = {
	&"fork_bomb": preload("res://src/items/unique_effects/fork_bomb.gd"),
	&"sudo": preload("res://src/items/unique_effects/sudo.gd"),
	&"omakase": preload("res://src/items/unique_effects/omakase.gd"),
	&"yacht": preload("res://src/items/unique_effects/yacht.gd"),
}


## All unique effect ids in a stable order.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in SCRIPTS.keys():
		out.append(key)
	return out


## New PassiveAbility for `id`, or null when unknown.
static func find(id: StringName) -> PassiveAbility:
	if not SCRIPTS.has(id):
		return null
	var script: GDScript = SCRIPTS[id]
	return script.new() as PassiveAbility


## Picks a unique effect id with the given RNG (uniform).
static func pick(rng: RandomNumberGenerator) -> StringName:
	var all := ids()
	return all[rng.randi_range(0, all.size() - 1)]
