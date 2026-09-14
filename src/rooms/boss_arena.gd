## The boss fight's opening (docs 7.4): the boss waits across the arena, dormant, until the
## player crosses the arena's deep trigger (`RoomNode.BOSS_TRIGGER_INSET` tiles in). Then the
## room seals its doors, this node wakes every enemy in it, plays the roar, shakes the screen
## and puts the boss's name up through the HUD toast lane. One per boss RoomNode, attached by
## `FloorPopulator`; a room that is already cleared (a resume) never fires it.
class_name BossArena
extends Node

signal engaged

const INTRO_DURATION := 2.6
const INTRO_SHAKE := 6.0
const INTRO_SHAKE_TIME := 0.7
## Name shown when the arena holds an elite pack instead of a boss.
const PACK_LABEL := "The arena guard"

var room: RoomNode
var fired: bool = false


## Adds a BossArena under `room_node` (once) and returns it.
static func attach(room_node: RoomNode) -> BossArena:
	if room_node == null:
		return null
	for child: Node in room_node.get_children():
		var existing := child as BossArena
		if existing != null:
			return existing
	var arena := BossArena.new()
	arena.name = "BossArena"
	arena.room = room_node
	room_node.add_child(arena)
	arena.room.activated.connect(arena._on_room_activated)
	return arena


## The banner line for the fight: the boss's own name, or the pack label.
static func intro_text(boss_name: String) -> String:
	var who := boss_name.strip_edges()
	return "%s awakens" % (who if not who.is_empty() else PACK_LABEL)


## Name of the boss in `enemies` (a `BossBase` first, else the first enemy's def), or "".
static func boss_name_of(enemies: Array[Node2D]) -> String:
	var fallback := ""
	for enemy: Node2D in enemies:
		if not is_instance_valid(enemy):
			continue
		var boss := enemy as BossBase
		if boss != null:
			return boss.boss_name()
		if fallback.is_empty():
			var def := enemy.get(&"def") as EnemyDef
			if def != null:
				fallback = def.display_name
	return fallback


## Wakes the room's enemies and plays the intro. Idempotent.
func engage_all() -> void:
	if fired or room == null:
		return
	fired = true
	var enemies: Array[Node2D] = room.enemies.duplicate()
	for enemy: Node2D in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method(&"engage"):
			enemy.call(&"engage")
		elif enemy.has_method(&"alert"):
			enemy.call(&"alert")
	if has_node("/root/Audio"):
		Audio.play(&"boss_roar", room.center_world())
	EventBus.screen_shake.emit(INTRO_SHAKE, INTRO_SHAKE_TIME)
	EventBus.toast.emit(intro_text(boss_name_of(enemies)), INTRO_DURATION)
	engaged.emit()


func _on_room_activated(_room: RoomNode) -> void:
	engage_all()
