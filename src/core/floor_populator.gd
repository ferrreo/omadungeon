## Fills a floor's rooms with enemies (docs §10.2) — and leaves out the ones the player has
## already killed on this floor and already been paid for (docs §12, `PackLedger`).
##
## Pulled out of `RunManager`, which only says when. Everything it needs is handed to it, so
## the spawn rules can be exercised without a live run.
class_name FloorPopulator
extends RefCounted

## Room types whose `enemy_spawns` are filled by the normal spawner.
const COMBAT_TYPES: Array[int] = [
	FloorData.RoomType.COMBAT, FloorData.RoomType.ELITE, FloorData.RoomType.TRAP
]

var registry: EnemyRegistry
## Enemies already killed and paid for, per room. Never null.
var packs := PackLedger.new()
var floor_index: int = 0
## `GenParams.enemy_count_scale`: the music energy's grip on pack size.
var count_scale: float = 1.0
## `GenParams.sight_scale/cadence_scale/loot_scale`: the music energy's grip on how keen the
## regular enemies are and what they drop (`EnemyBase.set_mood`). Bosses are left alone.
var sight_scale: float = 1.0
var cadence_scale: float = 1.0
var loot_scale: float = 1.0
## Boss of this floor, or &"" for a floor with no arena.
var boss_id: StringName = &""
## `ThemeProfile.faction_weights`: which factions this desktop leans toward.
var faction_weights: Dictionary = {}


## Takes the music levers off the floor's `GenParams` (docs 10.2); a null leaves them at 1.0.
func apply_params(params: GenParams) -> void:
	if params == null:
		return
	count_scale = params.enemy_count_scale
	sight_scale = params.sight_scale
	cadence_scale = params.cadence_scale
	loot_scale = params.loot_scale


## World centre of a grid tile.
static func tile_center(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * float(Layers.TILE)


## Radius a boss is confined to inside its arena.
static func arena_radius(room: FloorData.Room) -> float:
	return minf(room.rect.size.x, room.rect.size.y) * 0.5 * float(Layers.TILE)


## Spawns every room's enemies and hands them to the RoomNode so the lock/clear flow runs.
## Rooms in `cleared` are skipped whole; `spawn_rng` is the floor's `spawn` stream, and only
## its seed is read (see `room_stream`).
func populate(
	root: FloorRoot, data: FloorData, cleared: Array[int], spawn_rng: RandomNumberGenerator
) -> void:
	if root == null or data == null or spawn_rng == null or registry == null:
		return
	var base := spawn_rng.seed
	for room: FloorData.Room in data.rooms:
		var room_node := root.get_room(room.id)
		if room_node == null or cleared.has(room.id):
			continue
		var room_rng := room_stream(base, room.id)
		var enemies: Array[Node2D] = []
		if room.type == FloorData.RoomType.BOSS:
			enemies = spawn_boss(root, room, room_rng)
			# The arena runs the intro: the boss waits until the player is well inside, then
			# the doors seal, it roars and the fight starts (docs 7.4, `BossArena`).
			BossArena.attach(room_node)
		elif COMBAT_TYPES.has(int(room.type)) and not room.enemy_spawns.is_empty():
			enemies = spawn_pack(room, room_rng)
		for enemy: Node2D in enemies:
			room_node.add_child(enemy)
		room_node.populate(enemies)


## One RNG stream per room, derived from the floor's spawn seed and the room id — the same
## rule `FloorRoot` gives each prop, and for the same reason.
##
## Sharing one stream across the floor made a room's pack depend on which rooms were drawn
## before it, and a resume skips every cleared room, so continuing a run silently re-rolled
## the composition of every room still standing. That was a save-scum lever of its own (quit
## until the room ahead of you is cheap), and it is also what would let a pack the player had
## half-killed come back as different enemies, out from under `PackLedger`.
static func room_stream(base_seed: int, room_id: int) -> RandomNumberGenerator:
	var out := RandomNumberGenerator.new()
	out.seed = RunRng.hash_combine(base_seed, room_id + 1)
	return out


## One enemy per generated spawn point, never two on the same tile. The generator already
## scaled the number of spawn points by the music energy (GenParams.enemy_count_scale), so
## that count is the pack size; the budget is scaled by the same factor and anything it buys
## beyond the available tiles is dropped rather than stacked (docs 10.2).
func spawn_pack(room: FloorData.Room, spawn_rng: RandomNumberGenerator) -> Array[Node2D]:
	var defs := EnemySpawner.pick_for_room(
		registry, int(room.type), floor_index, faction_weights, spawn_rng, count_scale
	)
	var out := _place(room, packs.remaining(room.id, defs), spawn_rng)
	for node: Node2D in out:
		var enemy := node as EnemyBase
		if enemy != null:
			enemy.set_mood(sight_scale, cadence_scale, loot_scale)
	return out


## The floor's boss, or an elite pack when that boss is not implemented yet. Either waits on
## the generator's arena spawns, which sit across the room from the door (`ArenaSpawns`); the
## fallback pack takes the extra spots and wraps round them when it is bigger.
func spawn_boss(
	root: FloorRoot, room: FloorData.Room, spawn_rng: RandomNumberGenerator
) -> Array[Node2D]:
	var def := registry.find(boss_id) if boss_id != &"" else null
	var pos := room.center_world()
	if not room.enemy_spawns.is_empty():
		pos = tile_center(room.enemy_spawns[0])
	if def != null:
		var boss := EnemySpawner.instantiate(def, floor_index, pos, spawn_rng)
		if boss != null:
			if boss.has_method(&"set_arena"):
				boss.call(&"set_arena", room.center_world(), arena_radius(room))
			if boss.has_method(&"sleep_until_engaged"):
				boss.call(&"sleep_until_engaged")
			return [boss] as Array[Node2D]
	push_warning("FloorPopulator: boss %s missing, falling back to an elite pack" % boss_id)
	var defs := EnemySpawner.pick_for_room(
		registry, FloorData.RoomType.ELITE, floor_index, faction_weights, spawn_rng
	)
	var out: Array[Node2D] = []
	var live := packs.remaining(room.id, defs)
	# The fallback pack wraps around the arena's spawn tiles rather than capping at them: an
	# arena is one big room and may carry fewer spawn points than a bought elite pack needs,
	# and a boss room that spawned nothing would clear itself the moment the player walked in.
	for i in range(live.size()):
		var tile := (
			room.enemy_spawns[i % room.enemy_spawns.size()]
			if not room.enemy_spawns.is_empty()
			else room.center()
		)
		var enemy := EnemySpawner.instantiate(live[i], floor_index, tile_center(tile), spawn_rng)
		if enemy != null:
			enemy.set_meta(&"pack_room", room.id)
			out.append(enemy)
	# No real boss means no `is_boss` death to unlock the stairs; open them with the room.
	if root != null and root.stairs != null:
		root.stairs.unlock()
	return out


## Instantiates `defs` onto the room's spawn tiles, tagging each with the room it belongs to.
##
## `defs` has already been thinned by the ledger: docs §12 resets mid-fight state, so the pack
## comes back — but the enemies the player already killed had already paid their gold, hearts
## and elite drops, and since round six those drops stay banked across a resume. Dropping one
## entry per recorded kill is what stops Save & Quit -> Continue being an unbounded loot loop,
## and it costs an honest player nothing: they keep the progress they made on the room instead
## of having to re-fight it.
func _place(
	room: FloorData.Room, defs: Array[EnemyDef], spawn_rng: RandomNumberGenerator
) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if room.enemy_spawns.is_empty():
		return out
	for i in range(mini(defs.size(), room.enemy_spawns.size())):
		var tile: Vector2i = room.enemy_spawns[i]
		var enemy := EnemySpawner.instantiate(defs[i], floor_index, tile_center(tile), spawn_rng)
		if enemy != null:
			enemy.set_meta(&"pack_room", room.id)
			out.append(enemy)
	return out
