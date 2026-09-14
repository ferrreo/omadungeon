## What the dungeon actually throws at the player, measured off the shipped content.
##
## The fight model used to answer three questions with hand-set constants: how hard a floor
## hits, how much of that is melee (which is all `Thorns` reflects) and how much of it carries
## an element (which is all `resist_*` reduces). None of those are opinions — they are facts
## about `data/enemies/**` and `data/traps/**`, and reading them here is what lets the offer
## policy see a defensive card at all.
##
## Everything is computed once from the registries and cached, because it is a property of the
## content and not of a run.
class_name SimThreat
extends RefCounted

## Elemental damage tags `resist_*` reduces. `physical` has no resistance stat, and anything
## carrying `true` (status ticks, pit falls) skips resistances entirely in `Health`.
const RESISTED_TAGS: Array[StringName] = [
	DamageInfo.TAG_FIRE,
	DamageInfo.TAG_FROST,
	DamageInfo.TAG_SHOCK,
	DamageInfo.TAG_POISON,
	DamageInfo.TAG_ARCANE,
]

static var _shared: SimThreat

## Raw incoming damage per second of an ordinary COMBAT pack, per floor index.
var pack_dps: Array[float] = []
## Gold one ordinary COMBAT pack pays, per floor index (before `gold_find`).
var pack_gold: Array[float] = []
## Melee attacks an ordinary pack throws per second, per floor index. Thorns retaliates once
## per blow taken and part of what it returns is a slice of the wearer's own health pool, so
## the card is priced in hits and not only in damage.
var pack_melee_hits: Array[float] = []
## Share of that pack's damage that is tagged `melee` — the only damage `Thorns` reflects.
var melee_share: float = 1.0
## Share of trap damage that carries an element and is therefore cut by `resist_*`, weighted
## by how often `TrapRegistry.pick()` places each kind. `true`-tagged kinds (the pit) are
## excluded because `Health` skips both armour and resistances for them.
var trap_elemental_share: float = 0.0
## Damage tag each placeable trap kind deals, so the elemental share above is read rather than
## assumed. Kinds absent from the table are treated as physical.
var _trap_tags: Dictionary = {
	&"fire_vent": DamageInfo.TAG_FIRE,
	&"laser_grid": DamageInfo.TAG_ARCANE,
	&"pit": DamageInfo.TAG_TRUE,
}


## The threat model of the shipped registries, built once.
static func shared() -> SimThreat:
	if _shared == null:
		_shared = SimThreat.of(
			load("res://data/enemies/registry.tres") as EnemyRegistry, TrapRegistry.load_default()
		)
	return _shared


## Builds the model from explicit registries (the form tests use).
static func of(enemies: EnemyRegistry, traps: TrapRegistry) -> SimThreat:
	var out := SimThreat.new()
	out._measure_enemies(enemies)
	out._measure_traps(traps)
	return out


## Raw pack damage per second on `floor_index`, before anything the player does about it.
func dps_on(floor_index: int) -> float:
	return DifficultyCurve.at(pack_dps, floor_index, 0.0)


## Gold one ordinary pack pays on `floor_index`, before `gold_find`.
func gold_on(floor_index: int) -> float:
	return DifficultyCurve.at(pack_gold, floor_index, 0.0)


## Melee blows an ordinary pack throws per second on `floor_index`, before avoidance.
func melee_hits_on(floor_index: int) -> float:
	return DifficultyCurve.at(pack_melee_hits, floor_index, 0.0)


## Share of incoming trap damage `stats` turns away with its `resist_*` values. 1.0 means the
## build resists nothing; 0.8 means it takes four fifths of what a trap room deals.
func trap_resist_multiplier(stats: Stats) -> float:
	if trap_elemental_share <= 0.0:
		return 1.0
	var average := 0.0
	for tag: StringName in RESISTED_TAGS:
		average += clampf(stats.get_value(StringName("resist_" + String(tag))), 0.0, 0.9)
	average /= float(RESISTED_TAGS.size())
	return 1.0 - trap_elemental_share * average


## Weighted mean of `scaled_damage / attack_cycle` over the pack a floor's budget buys, plus
## the share of it that is melee. Both come from `EnemyDef`, never from a constant here.
func _measure_enemies(registry: EnemyRegistry) -> void:
	pack_dps.resize(RunSimulator.FLOOR_COUNT)
	pack_gold.resize(RunSimulator.FLOOR_COUNT)
	pack_melee_hits.resize(RunSimulator.FLOOR_COUNT)
	if registry == null:
		pack_dps.fill(0.0)
		pack_gold.fill(0.0)
		pack_melee_hits.fill(0.0)
		return
	var melee := 0.0
	var total := 0.0
	for index in range(RunSimulator.FLOOR_COUNT):
		var defs := registry.candidates(index, false)
		var weight := 0.0
		var dps := 0.0
		var gold := 0.0
		var cost := 0.0
		var swings := 0.0
		for def: EnemyDef in defs:
			if def == null or def.weight <= 0.0:
				continue
			var one := def.scaled_damage(index) / SimEncounter.attack_cycle(def)
			weight += def.weight
			dps += one * def.weight
			gold += float(def.gold_min + def.gold_max) * 0.5 * def.weight
			cost += maxf(0.1, def.cost) * def.weight
			total += one * def.weight
			if _is_melee(def):
				melee += one * def.weight
				swings += def.weight / SimEncounter.attack_cycle(def)
		if weight <= 0.0:
			pack_dps[index] = 0.0
			pack_gold[index] = 0.0
			pack_melee_hits[index] = 0.0
			continue
		# One pack is as many average enemies as the floor's budget affords.
		var size := EnemySpawner.budget_for(FloorData.RoomType.COMBAT, index) / (cost / weight)
		pack_dps[index] = dps / weight * size
		pack_gold[index] = gold / weight * size
		pack_melee_hits[index] = swings / weight * size
	melee_share = clampf(melee / maxf(0.001, total), 0.0, 1.0)


## An enemy that holds a distance is a thrower; everything else closes and swings, and
## `MeleeLunge` / `Charge` / `AoeBurst` all tag their damage `melee`.
static func _is_melee(def: EnemyDef) -> bool:
	return def.preferred_range <= 0.0 and not def.retreat_when_close


func _measure_traps(registry: TrapRegistry) -> void:
	if registry == null:
		return
	var elemental := 0.0
	var resistable := 0.0
	for kind: StringName in registry.kinds():
		var def := registry.get_def(kind)
		if def == null or def.is_hazard or def.weight <= 0.0 or def.damage <= 0.0:
			continue
		var tag := StringName(str(_trap_tags.get(kind, DamageInfo.TAG_PHYSICAL)))
		if tag == DamageInfo.TAG_TRUE:
			continue
		resistable += def.damage * def.weight
		if RESISTED_TAGS.has(tag):
			elemental += def.damage * def.weight
	trap_elemental_share = clampf(elemental / maxf(0.001, resistable), 0.0, 1.0)
