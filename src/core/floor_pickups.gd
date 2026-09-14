## Save/resume glue for the items lying loose on a floor (docs §12: "quitting is always
## resumable"). The sibling of `FloorRestore`, split off because a drop is not floor furniture:
## it is loot the player earned and has not picked up yet.
##
## An `ItemPickup` exists only as a node under the `RoomNode` it landed in. The generator does
## not know about it, "the room is cleared" does not imply it, and a resume rebuilds the floor
## from the seed with that room still cleared - so a floor the save does not describe comes
## back swept clean. That silently destroyed an elite's guaranteed Rare-or-better drop and
## anything an equip swap put back down: `ItemPickup`'s own docstring promises "nothing is ever
## destroyed", which was true inside a session and false across one. `capture()` reads the live
## nodes, `apply()` puts them back where they fell. Static functions over (FloorRoot, RunState).
class_name FloorPickups
extends RefCounted


## Every uncollected drop on the live floor, as `RunState.floor_pickups` entries.
static func capture(root: FloorRoot) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if root == null:
		return out
	for pickup: ItemPickup in find_all(root):
		var entry := {
			"room_id": FloorRestore.room_id_of(pickup),
			"x": pickup.global_position.x,
			"y": pickup.global_position.y,
			"item": pickup.item.to_dict(),
		}
		out.append(entry)
	return out


## The live, still-collectable `ItemPickup` nodes under `node`, depth first. One already queued
## for deletion (just equipped) is not on the floor any more and is left out.
static func find_all(node: Node) -> Array[ItemPickup]:
	var out: Array[ItemPickup] = []
	if node == null:
		return out
	for child: Node in node.get_children():
		var pickup := child as ItemPickup
		if pickup != null and pickup.item != null and not pickup.is_queued_for_deletion():
			out.append(pickup)
		out.append_array(find_all(child))
	return out


## Puts the saved drops back, into the room they fell in. Returns how many were restored.
##
## Call it *after* `EventBus.floor_started`: an ItemPickup frees itself on that signal, so a
## drop never follows the player down the stairs, and the ones a resume replays are exactly the
## drops that must survive it. The scatter hop is cleared too - it belongs to the moment of the
## drop, and replaying it would walk the item further from its saved spot on every Save & Quit.
static func apply(root: FloorRoot, state: RunState, registry: ItemRegistry) -> int:
	if root == null or state == null or registry == null:
		return 0
	var restored := 0
	for entry: Dictionary in state.floor_pickups:
		var raw: Variant = entry.get("item", {})
		if not (raw is Dictionary):
			continue
		var item := ItemGenerator.from_dict(raw as Dictionary, registry)
		if item == null:
			continue
		var room := root.get_room(int(entry.get("room_id", -1)))
		var parent: Node = room if room != null else root
		var pos := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
		# `scatter = false`, answered before the node enters the tree rather than cleared on the
		# way out: `ItemPickup._ready` performs the hop, and it now runs inside `drop()` when
		# there is no physics flush to defer for - which this call is never inside.
		var pickup := ItemPickup.drop(parent, item, pos, null, false)
		if pickup == null:
			continue
		restored += 1
	return restored
