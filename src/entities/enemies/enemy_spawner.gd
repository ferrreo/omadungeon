## Pure helpers: pick a room's enemy set from a registry (budgeted, faction-weighted) and
## instantiate enemies from defs. Bosses are picked by the boss module, not here.
class_name EnemySpawner
extends RefCounted

const ELITE_BUDGET_MULT := 1.6
const TRAP_BUDGET_MULT := 0.4
## Faction name keys accepted in `faction_weights` besides the EnemyDef.Faction ints.
const FACTION_NAMES: Dictionary = {
	&"clowns": EnemyDef.Faction.CLOWNS,
	&"greybeards": EnemyDef.Faction.GREYBEARDS,
	&"tinkerers": EnemyDef.Faction.TINKERERS,
}


## Difficulty budget for a room type on a floor (0 for rooms that spawn nothing here).
## The per-floor budget is data (`data/balance/difficulty_curve.tres`) rather than a straight
## line in code, so the ramp can be shaped floor by floor — notably to stop the floor after a
## boss floor from being easier than the boss floor itself.
## `count_scale` is GenParams.enemy_count_scale (music energy, 0.85..1.15), so a loud track
## buys a bigger pack and a quiet one a smaller one.
static func budget_for(room_type: int, floor_index: int, count_scale: float = 1.0) -> float:
	var base := DifficultyCurve.shared().budget_for(floor_index) * maxf(count_scale, 0.0)
	match room_type:
		FloorData.RoomType.COMBAT:
			return base
		FloorData.RoomType.ELITE:
			return base * ELITE_BUDGET_MULT
		FloorData.RoomType.TRAP:
			return base * TRAP_BUDGET_MULT
	return 0.0


## Weight multiplier for a faction from a Dictionary keyed by Faction int or faction name.
static func faction_weight(weights: Dictionary, faction: EnemyDef.Faction) -> float:
	if weights.has(faction):
		return maxf(0.0, float(weights[faction]))
	for key: StringName in FACTION_NAMES.keys():
		if FACTION_NAMES[key] == faction and weights.has(key):
			return maxf(0.0, float(weights[key]))
	return 1.0


## Rolls the enemies for one room. ELITE rooms contain exactly one elite; TRAP rooms get
## 40% budget; START/TREASURE/... rooms get none. Deterministic in `rng`.
static func pick_for_room(
	registry: EnemyRegistry,
	room_type: int,
	floor_index: int,
	faction_weights: Dictionary,
	rng: RandomNumberGenerator,
	count_scale: float = 1.0
) -> Array[EnemyDef]:
	var picks: Array[EnemyDef] = []
	var budget := budget_for(room_type, floor_index, count_scale)
	if budget <= 0.0 or registry == null:
		return picks
	if room_type == FloorData.RoomType.ELITE:
		var elite := _weighted_pick(
			registry.candidates(floor_index, true), faction_weights, rng, budget
		)
		if elite == null:
			elite = _weighted_pick(
				registry.candidates(floor_index, true), faction_weights, rng, INF
			)
		if elite != null:
			picks.append(elite)
			budget -= elite.cost
	var regulars := registry.candidates(floor_index, false)
	var guard := 0
	while guard < 64:
		guard += 1
		var def := _weighted_pick(regulars, faction_weights, rng, budget)
		if def == null:
			break
		picks.append(def)
		budget -= def.cost
	if picks.is_empty():
		var cheapest := _weighted_pick(regulars, faction_weights, rng, INF)
		if cheapest != null:
			picks.append(cheapest)
	return picks


static func _weighted_pick(
	pool: Array[EnemyDef], weights: Dictionary, rng: RandomNumberGenerator, max_cost: float
) -> EnemyDef:
	var total := 0.0
	var eligible: Array[EnemyDef] = []
	var eligible_weights: Array[float] = []
	for def: EnemyDef in pool:
		if def.cost > max_cost:
			continue
		var w := def.weight * faction_weight(weights, def.faction)
		if w <= 0.0:
			continue
		eligible.append(def)
		eligible_weights.append(w)
		total += w
	if eligible.is_empty():
		return null
	var roll := rng.randf() * total
	for i in range(eligible.size()):
		roll -= eligible_weights[i]
		if roll <= 0.0:
			return eligible[i]
	return eligible[eligible.size() - 1]


## Instantiates the def's scene at `pos` (not yet in the tree; the caller must `add_child()` it
## and then set `global_position`). Returns null (with an error) for a broken def.
## Always pass a deterministic `rng` stream: without one the enemy seeds itself from
## (id, floor, position) instead of the run seed.
static func instantiate(
	def: EnemyDef, floor_index: int, pos: Vector2, rng: RandomNumberGenerator = null
) -> EnemyBase:
	if def == null or def.scene == null:
		push_error("EnemySpawner: def %s has no scene" % (def.id if def != null else &"<null>"))
		return null
	var enemy := def.scene.instantiate() as EnemyBase
	if enemy == null:
		push_error("EnemySpawner: %s scene root is not an EnemyBase" % def.id)
		return null
	enemy.name = String(def.id)
	enemy.position = pos
	enemy.setup(def, floor_index, rng)
	return enemy


## Convenience: instantiate, add under `parent` and place each def at the matching position.
## This is the call room builders should use; `instantiate()` alone leaves a detached node.
static func spawn_group(
	defs: Array[EnemyDef],
	positions: Array[Vector2],
	floor_index: int,
	parent: Node,
	rng: RandomNumberGenerator = null
) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for i in range(defs.size()):
		var pos := positions[i % positions.size()] if not positions.is_empty() else Vector2.ZERO
		var enemy := instantiate(defs[i], floor_index, pos, rng)
		if enemy == null:
			continue
		# Through PhysicsFlush for the same reason EnemyBase.spawn_sibling is: a group spawned
		# from inside a hit callback (a trap, a boss phase reached by a hit) would hand the
		# server its shapes mid-flush and have them refused.
		PhysicsFlush.add_child_at(parent, enemy, pos)
		out.append(enemy)
	return out
