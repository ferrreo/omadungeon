## Spawns enemies from `EnemyDef`s in a ring around the summoner.
class_name Summon
extends EnemyAttack

signal summoned(spawned: Array[EnemyBase])

var defs: Array[EnemyDef] = []
var count: int = 1
var ring_radius: float = 24.0
## Spawned enemies from the last `summon()`.
var last_summoned: Array[EnemyBase] = []


func _start(_target_pos: Vector2) -> void:
	summon()
	finish()


## Instantiates `count` enemies picked (uniformly, via the summoner's rng) from `defs`.
## `EnemySpawner.instantiate` derives a fresh child stream per summon, so the spawned enemies
## never share the summoner's generator (their loot rolls stay independent and reproducible).
func summon() -> Array[EnemyBase]:
	last_summoned = []
	if defs.is_empty():
		return last_summoned
	var start_angle := enemy.rng.randf() * TAU
	for i in range(count):
		var def: EnemyDef = defs[enemy.rng.randi_range(0, defs.size() - 1)]
		var angle := start_angle + TAU * float(i) / count
		var pos := enemy.walkable_point(
			enemy.global_position + Vector2.from_angle(angle) * ring_radius
		)
		var spawned := EnemySpawner.instantiate(def, enemy.floor_index, pos, enemy.rng)
		if spawned == null:
			continue
		enemy.spawn_sibling(spawned, pos)
		spawned.knockback_velocity = Vector2.from_angle(angle) * 80.0
		last_summoned.append(spawned)
	summoned.emit(last_summoned)
	return last_summoned
