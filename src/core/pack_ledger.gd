## Which enemies of each room on the current floor the player has already killed — and so has
## already been paid for (docs §12).
##
## A resume rebuilds the floor from the seed and respawns every room that is not fully
## cleared. That is the documented behaviour ("mid-fight state is not saved … enemies reset"),
## and it is fine on its own. What nobody had decided is that the *loot* resets with them:
## kill four of a pack of five, bank their gold, hearts and elite drops, quit, continue, and
## the whole pack is back while the drops stay banked. Repeat forever.
##
## This ledger is the decision. The pack still comes back the way docs §12 promises, but one
## enemy is removed from it per enemy the player already killed there, matched by
## `EnemyDef.id`. No enemy can pay twice, and an honest player who simply quits and comes back
## is not punished at all: they keep the progress they made on the room instead of having to
## re-fight it.
class_name PackLedger
extends RefCounted

## room id -> the `EnemyDef.id`s already killed in it, as Strings, one entry per kill.
var _rooms: Dictionary = {}


## The inverse of `to_entries()` (`RunState.defeated_spawns`). Entries that are not a room id
## plus a list of ids are skipped rather than guessed at.
static func from_entries(entries: Array[Dictionary]) -> PackLedger:
	var ledger := PackLedger.new()
	for entry: Dictionary in entries:
		var room_id := int(entry.get("room_id", -1))
		var raw: Variant = entry.get("enemy_ids", [])
		if room_id < 0 or not (raw is Array):
			continue
		for id: Variant in raw as Array:
			ledger.record(room_id, StringName(str(id)))
	return ledger


## Records that an enemy of `enemy_id` died in `room_id`. Kills are a multiset: two mimes
## killed out of a pack of three are two entries, and two of the resumed pack are dropped.
func record(room_id: int, enemy_id: StringName) -> void:
	if room_id < 0 or enemy_id.is_empty():
		return
	var ids: Array = _rooms.get(room_id, [])
	ids.append(String(enemy_id))
	_rooms[room_id] = ids


## Forgets `room_id`: it cleared, so its pack is never rebuilt and the record is dead weight
## in every later `run.json`.
func forget(room_id: int) -> void:
	_rooms.erase(room_id)


## Forgets the whole floor (a descent, or the end of a run).
func clear() -> void:
	_rooms.clear()


## True while nothing has been recorded.
func is_empty() -> bool:
	return _rooms.is_empty()


## The ids already killed in `room_id`, as a fresh copy.
func killed_in(room_id: int) -> Array:
	return (_rooms.get(room_id, []) as Array).duplicate()


## `defs` with one entry removed per enemy already killed in `room_id`, matched by id in the
## order the ids appear. A def the ledger has no record of is kept, so a resumed pack that
## rolled a different composition is thinned, never emptied by accident.
func remaining(room_id: int, defs: Array[EnemyDef]) -> Array[EnemyDef]:
	var spent := killed_in(room_id)
	if spent.is_empty():
		return defs
	var out: Array[EnemyDef] = []
	for def: EnemyDef in defs:
		var at := spent.find(String(def.id)) if def != null else -1
		if at >= 0:
			spent.remove_at(at)
			continue
		out.append(def)
	return out


## JSON-safe entries for `RunState.defeated_spawns`, rooms in ascending id order so two saves
## of the same state are byte-identical.
func to_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = _rooms.keys()
	ids.sort()
	for room_id: int in ids:
		out.append({"room_id": room_id, "enemy_ids": (_rooms[room_id] as Array).duplicate()})
	return out
