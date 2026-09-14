## What the floor still holds when the player reaches the stairs, and where that is said.
##
## Descending used to be intercepted: the first Descend press at the stairs put up a toast
## ("2 rooms unexplored (Altar, Shop), 1 item on the floor - interact again to descend"),
## disarmed the staircase and asked for a second press, and the stairs prompt itself grew the
## whole sentence. The owner's verdict after playing was that the notice over the exit was
## annoying, and it was: it said at the worst moment, loudly and once, something the map
## should say all the time, quietly. So the interception is gone. The stairs say "Descend"
## (or "Descend to the BOSS floor", which is a different fact and one worth a heads-up), and
## the count of what is left moves to the minimap's strip (`Minimap.caption_text`), which the
## HUD keeps up to date from the room feed and from `EventBus.floor_leftovers`.
##
## `RunManager` still owns one of these and still calls `intercept` and `refresh_prompt` in
## the same places; only their meaning changed, so that file did not have to.
class_name DescendNotice
extends RefCounted

## Room types worth going back for: the ones whose contents are a build, not a fight.
const REWARD_ROOM_TYPES: Array[int] = [
	FloorData.RoomType.TREASURE,
	FloorData.RoomType.ALTAR,
	FloorData.RoomType.SHOP,
	FloorData.RoomType.SHRINE,
	FloorData.RoomType.ELITE,
]
const DESCEND := "Descend"
const DESCEND_BOSS := "Descend to the BOSS floor"


## Whether this exit request should be held back. It never is any more: the answer to "you
## are leaving things behind" is on the map, not in the way of the stairs. Kept so the run
## lifecycle's call site reads the same; `data` is what the map counts and is unused here.
func intercept(_root: FloorRoot, _data: FloorData) -> bool:
	return false


## Re-costs the stairs prompt and tells the HUD what is still lying on the floor. Cheap enough
## to call whenever the player changes room. `next_is_boss` says the staircase leads into a
## boss arena, which is the one thing a player wants to know *before* spending the descent.
func refresh_prompt(root: FloorRoot, _data: FloorData, next_is_boss: bool = false) -> void:
	EventBus.floor_leftovers.emit(loose_items(root))
	var stairs := root.stairs if root != null and is_instance_valid(root) else null
	if stairs == null or not is_instance_valid(stairs) or stairs.locked:
		return
	stairs.prompt_text = prompt(next_is_boss)


func reset() -> void:
	pass


## Reward-room type names on `data` the player has never entered, sorted for a stable
## message. `visited` is `FloorRoot.visited_ids()`.
static func unexplored(data: FloorData, visited: Array[int]) -> Array[String]:
	var out: Array[String] = []
	if data == null:
		return out
	for room: FloorData.Room in data.rooms:
		if visited.has(room.id) or not REWARD_ROOM_TYPES.has(room.type):
			continue
		out.append(FloorData.RoomType.keys()[room.type].capitalize())
	out.sort()
	return out


## Uncollected item drops lying on `root`. An `ItemPickup` frees itself on the next
## `EventBus.floor_started`, so anything still on the floor when the stairs are taken is
## destroyed. Gold, hearts and stat orbs are deliberately not counted: they home to the
## player on contact, so they are collected by walking past rather than abandoned by leaving.
static func loose_items(root: FloorRoot) -> int:
	if root == null or not is_instance_valid(root):
		return 0
	return FloorPickups.find_all(root).size()


## The stairs prompt. A boss floor below is named here rather than discovered on arrival, so
## "descend now or heal first" is a choice. Nothing else: the cost of leaving is on the map.
static func prompt(next_is_boss: bool = false) -> String:
	return DESCEND_BOSS if next_is_boss else DESCEND


## What descending costs, in one phrase: "2 rooms unexplored (Altar), 1 item on the floor".
## Empty when it costs nothing. No screen prints it any more; the run summary may.
static func cost_text(left: Array[String], items: int = 0) -> String:
	var parts: PackedStringArray = []
	if not left.is_empty():
		var word := "room" if left.size() == 1 else "rooms"
		parts.append("%d %s unexplored (%s)" % [left.size(), word, summary(left)])
	if items > 0:
		parts.append("%d %s on the floor" % [items, "item" if items == 1 else "items"])
	return ", ".join(parts)


## "Altar, 2 Treasure" from a list of room-type names.
static func summary(left: Array[String]) -> String:
	var counts: Dictionary = {}
	for name: String in left:
		counts[name] = int(counts.get(name, 0)) + 1
	var parts: PackedStringArray = []
	var keys := counts.keys()
	keys.sort()
	for key: Variant in keys:
		var n := int(counts[key])
		parts.append(str(key) if n == 1 else "%d %s" % [n, key])
	return ", ".join(parts)
