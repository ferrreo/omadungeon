## Registry of every TrapDef (`data/traps/registry.tres`). Instantiates traps by kind and picks
## them per biome deterministically.
class_name TrapRegistry
extends Resource

const DEFAULT_PATH := "res://data/traps/registry.tres"

@export var defs: Array[TrapDef] = []


## Loads the default registry (ResourceLoader caches it by path).
static func load_default() -> TrapRegistry:
	var registry := load(DEFAULT_PATH) as TrapRegistry
	if registry == null:
		push_error("TrapRegistry: missing " + DEFAULT_PATH)
		return TrapRegistry.new()
	return registry


## Creates a trap of `kind` at `pos` (local to the parent you add it to). Not added to the tree.
## `extra` keys: duration, direction, to, length, size, linked_group, plate_id, latching,
## enemies_immune, room_id, damage, enemy_id, enabled.
static func instantiate(kind: StringName, pos: Vector2, extra: Dictionary = {}) -> TrapBase:
	return load_default().create(kind, pos, extra)


func create(kind: StringName, pos: Vector2, extra: Dictionary = {}) -> TrapBase:
	var def := get_def(kind)
	if def == null:
		push_error("TrapRegistry: unknown trap kind '%s'" % kind)
		return null
	var node: Node = null
	if def.scene != null:
		node = def.scene.instantiate()
	elif def.script_class != null:
		node = def.script_class.new()
	var trap := node as TrapBase
	if trap == null:
		push_error("TrapRegistry: def '%s' does not produce a TrapBase" % kind)
		if node != null:
			node.free()
		return null
	trap.apply_def(def)
	trap.position = pos
	trap.configure(extra)
	trap.name = String(kind).to_pascal_case()
	return trap


func get_def(kind: StringName) -> TrapDef:
	for def: TrapDef in defs:
		if def != null and def.id == kind:
			return def
	return null


func has_kind(kind: StringName) -> bool:
	return get_def(kind) != null


func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for def: TrapDef in defs:
		if def != null:
			out.append(def.id)
	return out


## Defs the generator may place in `biome` (hazards excluded unless requested).
## `data/biomes/<biome>.tres` is authoritative: when that resource exists only its
## `trap_kinds` are eligible, and `TrapDef.biomes` narrows the list further. Biomes with no
## resource file (tests, ad-hoc ids) fall back to `TrapDef.biomes` alone.
func defs_for_biome(biome: StringName, include_hazards: bool = false) -> Array[TrapDef]:
	var allowed := biome_trap_kinds(biome)
	var out: Array[TrapDef] = []
	for def: TrapDef in defs:
		if def == null or (def.is_hazard and not include_hazards):
			continue
		# Hazards are spawned at runtime, so biome resources never list them.
		if not def.is_hazard and not allowed.is_empty() and not allowed.has(def.id):
			continue
		if def.allows_biome(biome):
			out.append(def)
	return out


## Trap kinds `data/biomes/<biome>.tres` allows, or an empty array when there is no such biome
## resource (then only `TrapDef.biomes` gates placement).
static func biome_trap_kinds(biome: StringName) -> Array[StringName]:
	var path := Biome.BIOMES_DIR + String(biome) + ".tres"
	if not ResourceLoader.exists(path):
		return []
	var res := load(path) as Biome
	if res == null:
		return []
	return res.trap_kinds


## Weighted deterministic pick for `biome`; null when nothing fits.
func pick(biome: StringName, rng: RandomNumberGenerator) -> TrapDef:
	var pool := defs_for_biome(biome)
	if pool.is_empty():
		return null
	var total := 0.0
	for def: TrapDef in pool:
		total += maxf(def.weight, 0.0)
	if total <= 0.0:
		return pool[0]
	var roll := rng.randf() * total
	for def: TrapDef in pool:
		roll -= maxf(def.weight, 0.0)
		if roll <= 0.0:
			return def
	return pool[pool.size() - 1]
