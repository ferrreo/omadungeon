## Runtime wrapper for one FloorData.Room (named RoomNode because FloorData.Room takes "Room"):
## entry trigger, doors, enemy tracking and the lock -> fight -> clear -> chest flow (docs §6).
## The room locks when the player is at least one tile inside and enemies are pending
## (`BOSS_TRIGGER_INSET` tiles inside for a boss arena, so the boss fight starts once the
## player is well past the door, docs 7.4); START/TREASURE/ALTAR/SHOP/SHRINE/STAIRS rooms
## never lock. RunManager calls `populate()`
## with the spawned enemies (orphan enemies are parented here).
class_name RoomNode
extends Node2D

signal activated(room: RoomNode)
signal cleared(room: RoomNode)
signal chest_spawned(chest: Chest)

enum State { UNVISITED, ACTIVE, CLEARED }

## Tiles the player must be inside an ordinary room, and inside a boss arena, to trip it.
const TRIGGER_INSET := 1
const BOSS_TRIGGER_INSET := 3

const NEVER_LOCK: Array[FloorData.RoomType] = [
	FloorData.RoomType.START,
	FloorData.RoomType.TREASURE,
	FloorData.RoomType.ALTAR,
	FloorData.RoomType.SHOP,
	FloorData.RoomType.SHRINE,
	FloorData.RoomType.STAIRS,
]

var data: FloorData.Room
var floor_data: FloorData
var id: int = -1
var type: FloorData.RoomType = FloorData.RoomType.COMBAT
var state: State = State.UNVISITED
var doors: Array[Door] = []
var enemies: Array[Node2D] = []
var chest: Chest
## True from the moment this room owes the player a reward chest. `_clear_room` spawns the
## chest a frame later (off the signal stack), and a Save & Quit inside that frame would
## otherwise record the room as chest-less and lose the reward for good.
var chest_pending: bool = false
## Kind of the reward chest, rolled once in setup() from a per-room stream so it never
## depends on when the room is cleared or how many props were smashed first.
var chest_kind: Chest.Kind = Chest.Kind.STAT
var visited: bool = false
var player_inside: bool = false
## Grid tiles inside the room that must stay free (props, traps, interactables).
var blocked_tiles: Dictionary = {}
var trigger: Area2D
var _floor_index: int = 0
## True once RunManager handed over its enemy list (even an empty one).
var _populated: bool = false
var _ever_had_enemies: bool = false
## Set by FloorRoot before a floor is torn down: no more locking/clearing from stray signals.
var _tearing_down: bool = false


## Wires the room to its data. The chest kind is rolled here from a per-room RNG stream.
func setup(room: FloorData.Room, floor: FloorData, _rng: RandomNumberGenerator = null) -> void:
	data = room
	floor_data = floor
	id = room.id
	type = room.type
	name = "Room%d" % id
	_floor_index = floor.floor_index if floor != null else 0
	var seed_value := floor.seed_value if floor != null else 0
	var kind_rng := RandomNumberGenerator.new()
	kind_rng.seed = RunRng.hash_combine(RunRng.hash_combine(seed_value, id + 1), 0x0C4E57)
	chest_kind = Chest.roll_kind(kind_rng, type, _floor_index)
	for p: Vector2i in room.prop_positions:
		blocked_tiles[p] = true
	for trap: Dictionary in room.trap_positions:
		if trap.has("pos"):
			blocked_tiles[trap["pos"]] = true
	if trigger == null:
		_build_trigger()
	if not EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.connect(_on_enemy_died)


## Registers a door owned by this room (positioned by FloorRoot).
func add_door(door: Door) -> void:
	doors.append(door)
	if door.get_parent() == null:
		add_child(door)


## RunManager hands over the spawned enemies (parented here when they have no parent yet).
## Locks immediately if the player is already inside; an empty list on a lockable room the
## player already stands in clears it right away.
func populate(new_enemies: Array[Node2D]) -> void:
	_populated = true
	for enemy: Node2D in new_enemies:
		if enemy == null or not is_instance_valid(enemy) or enemies.has(enemy):
			continue
		enemies.append(enemy)
		_ever_had_enemies = true
		if enemy.get_parent() == null:
			add_child(enemy)
		enemy.tree_exiting.connect(_on_enemy_removed.bind(enemy), CONNECT_ONE_SHOT)
		if enemy.has_signal(&"died"):
			enemy.connect(&"died", _on_enemy_died_signal.bind(enemy))
	if player_inside and state == State.UNVISITED:
		_try_lock()


func is_lockable() -> bool:
	return not NEVER_LOCK.has(type)


func pending_enemy_count() -> int:
	var n := 0
	for enemy: Node2D in enemies:
		if is_instance_valid(enemy):
			n += 1
	return n


func is_locked() -> bool:
	return state == State.ACTIVE


## Ends the fight without enemies dying (debug/cheat). `spawn_reward` false skips the chest
## (the room was already looted). Announces the clear like a real one; use `restore_cleared`
## when replaying a save.
func force_clear(spawn_reward: bool = true) -> void:
	enemies.clear()
	if state != State.CLEARED:
		_clear_room(spawn_reward)


## Puts the room back into its saved CLEARED state when a floor is rebuilt on resume
## (docs §12). The reward chest is not decided here — `restore_chest()` does that, because
## whether this room owes one is a saved fact, not something to guess from the room type.
##
## Deliberately silent: `force_clear` emits `EventBus.room_cleared`, and replaying that once
## per cleared room would fire the clear jingle and the screen flash five times over, run
## every `on_room_cleared` passive hook again for free, and queue an autosave per room. The
## player cleared these rooms in the previous session, not now.
func restore_cleared() -> void:
	enemies.clear()
	visited = true
	if state == State.CLEARED:
		return
	state = State.CLEARED
	if data != null:
		data.cleared = true
	for door: Door in doors:
		door.open()


## Resume: this room held a reward chest, `taken` telling whether the player had opened it.
## Puts it back immediately (not deferred like a real clear: the floor is being assembled,
## nothing is listening) and re-uses the one a Treasure room was built with.
func restore_chest(taken: bool) -> void:
	if _tearing_down or not is_inside_tree():
		return
	var reward := spawn_chest(false)
	if taken and reward != null:
		reward.mark_taken()


## True while this room owes the player a chest or already holds one, opened or not. The
## save records it per room: a lockable room the generator gave no enemies clears without a
## reward, and a resume must not invent one for it.
func has_reward_chest() -> bool:
	return chest_pending or (chest != null and is_instance_valid(chest))


## True when this room's reward chest has already been opened.
func chest_taken() -> bool:
	return chest != null and is_instance_valid(chest) and chest.is_opened


## Marks the room dead for signal purposes; FloorRoot calls it before freeing a floor.
func begin_teardown() -> void:
	_tearing_down = true


## Nearest free walkable tile to the room centre (chest placement, respawn).
func free_tile_near_center() -> Vector2i:
	return free_tile_near(data.center())


## Nearest free walkable tile to `from` inside this room (BFS, falls back to `from`).
func free_tile_near(from: Vector2i) -> Vector2i:
	if _is_free(from):
		return from
	var seen: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for d: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var n := p + d
			if seen.has(n) or not data.rect.has_point(n):
				continue
			seen[n] = true
			if _is_free(n):
				return n
			queue.append(n)
	return from


## Where the player appears when they arrive in this room: the interior tile next to the
## first door (falls back to the centre for door-less rooms).
func entry_position() -> Vector2:
	var tiles := data.door_tiles()
	if tiles.is_empty():
		return tile_to_local(free_tile_near_center())
	var door := tiles[0]
	var inside := door.clamp(data.rect.position, data.rect.end - Vector2i.ONE)
	return tile_to_local(free_tile_near(inside))


## Spawns the reward chest at the centre (or nearest free tile). Returns it.
func spawn_chest(trapped: bool = false) -> Chest:
	chest_pending = true
	if chest != null and is_instance_valid(chest):
		return chest
	var c := Chest.new()
	c.name = "Chest"
	c.kind = chest_kind
	c.is_trapped = trapped
	var tile := free_tile_near_center()
	blocked_tiles[tile] = true
	c.position = tile_to_local(tile)
	chest = c
	add_child(c)
	chest_spawned.emit(c)
	return c


## World position of the centre of a grid tile (this node sits at the world origin).
func tile_to_local(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * Layers.TILE


func center_world() -> Vector2:
	return data.center_world()


func _is_free(tile: Vector2i) -> bool:
	if blocked_tiles.has(tile) or not data.rect.has_point(tile):
		return false
	return floor_data == null or floor_data.is_walkable(tile.x, tile.y)


func _build_trigger() -> void:
	trigger = Area2D.new()
	trigger.name = "Trigger"
	trigger.collision_layer = 0
	trigger.collision_mask = Layers.PLAYER
	trigger.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# "At least one tile inside": shrink the interior by one tile per side (min one tile);
	# an arena shrinks by three, so the seal and the roar wait for the player to commit.
	var inset := BOSS_TRIGGER_INSET if type == FloorData.RoomType.BOSS else TRIGGER_INSET
	var inner := data.rect.grow(-inset)
	if inner.size.x < 1 or inner.size.y < 1:
		inner = Rect2i(data.center(), Vector2i.ONE)
	rect.size = Vector2(inner.size) * Layers.TILE
	shape.shape = rect
	shape.position = Vector2(inner.position) * Layers.TILE + rect.size / 2.0
	trigger.add_child(shape)
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)
	add_child(trigger)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(Interactable.PLAYER_GROUP):
		return
	player_inside = true
	_on_player_entered()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(Interactable.PLAYER_GROUP):
		player_inside = false


func _on_player_entered() -> void:
	visited = true
	EventBus.room_entered.emit(id)
	_try_lock()


## Locks the room when it has pending enemies; a lockable room that was populated and has
## nothing left to fight (splash kills before entry, or an empty spawn list) clears instead.
func _try_lock() -> void:
	if state != State.UNVISITED or _tearing_down:
		return
	if not is_lockable():
		state = State.CLEARED
		return
	if pending_enemy_count() == 0:
		if _populated:
			_clear_room(_ever_had_enemies)
		# else: nothing spawned yet (populate() may still run) — stay open.
		return
	state = State.ACTIVE
	for door: Door in doors:
		door.close()
	EventBus.room_locked.emit(id)
	activated.emit(self)


func _on_enemy_died(enemy: Node2D, _killer: Node2D) -> void:
	_on_enemy_gone(enemy)


func _on_enemy_died_signal(_killer: Node2D, enemy: Node2D) -> void:
	_on_enemy_gone(enemy)


## An enemy left the tree. Only drops the reference: teardown frees every enemy at once and
## must never look like a room clear. Deaths arrive through enemy_died / the `died` signal.
func _on_enemy_removed(enemy: Node2D) -> void:
	enemies.erase(enemy)


func _on_enemy_gone(enemy: Node2D) -> void:
	if not enemies.has(enemy):
		return
	enemies.erase(enemy)
	if _tearing_down or not is_inside_tree() or is_queued_for_deletion():
		return
	if pending_enemy_count() > 0:
		return
	if state == State.ACTIVE:
		_clear_room(true)
	elif state == State.UNVISITED and visited and _populated and is_lockable():
		_clear_room(true)


func _clear_room(spawn_reward: bool = true) -> void:
	state = State.CLEARED
	if data != null:
		data.cleared = true
	for door: Door in doors:
		door.open()
	EventBus.room_cleared.emit(id)
	cleared.emit(self)
	if not spawn_reward or _tearing_down or not is_inside_tree():
		return
	chest_pending = true
	# Spawning during a physics callback is fine, but keep it off the signal stack anyway.
	spawn_chest.call_deferred(false)
