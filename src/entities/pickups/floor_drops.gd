## Save/resume glue for the *homing* drops lying loose on a floor - gold, hearts and the stat
## orb every elite is guaranteed to leave (docs §8, §12: "quitting is always resumable").
##
## The sibling of `FloorPickups`, which does the same job for `ItemPickup`. They are separate
## because the two kinds of drop live in different places: an item is a node under the RoomNode
## it fell in, while a `PickupBase` is a child of `PickupSpawner`, off to the side of the floor
## root entirely. That is why the item half of this hole was closed and this half was not - a
## sweep of the floor root finds no coins, because there are none under it.
##
## Everything else about them is the same and just as fatal: nothing generates them, "the room
## is cleared" does not imply them, `PickupSpawner.clear_pickups()` empties the container on
## `EventBus.floor_started`, and a resume rebuilds the floor from the seed. A floor the save
## does not describe therefore comes back swept clean, and the elite orb, the loose gold and
## the hearts the player had not bent down for are gone without a word.
##
## `capture()` reads the live nodes; `apply()` puts them back where they lay. Static functions
## over (PickupSpawner, RunState): `RunManager` only says when, and it says it through
## `FloorRestore.capture_loose_loot()` / `apply_loose_loot()`, which drive both halves at once
## so one can never be updated without the other.
class_name FloorDrops
extends RefCounted


## The pickup spawner of the in-run scene, or null when there is no live run (`view` is
## `RunManager.game`). It is a sibling of the floor root, not a child of it, which is the whole
## reason a sweep of the floor for loose loot has to ask for it separately.
static func spawner_of(view: Node) -> PickupSpawner:
	if view == null or not is_instance_valid(view):
		return null
	var scene := view as Game
	return scene.pickup_spawner if scene != null else null


## Every uncollected drop on the live floor, as `RunState.floor_drops` entries. Empty when
## there is no spawner (outside a run).
static func capture(spawner: PickupSpawner) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if spawner == null or not is_instance_valid(spawner):
		return out
	for pickup: PickupBase in spawner.live_pickups():
		out.append(pickup.to_dict())
	return out


## Puts the saved drops back. Returns how many are on the floor when it returns - a fact, not
## a promise. It used to count every entry `restore()` handed back a node for, while the
## insertion was still sitting in the message queue, so a drop the spawner's generation guard
## went on to throw away was counted as restored. `restore()` now inserts synchronously
## outside a physics query flush, and `_build_floor` - the only thing that calls this - is not
## one; called from inside a flush an entry is still deferred and deliberately not counted.
##
## `bounds` is the floor's camera limits (`FloorRoot.camera_limits()`) when the caller knows
## them: an entry naming a position outside them is corruption and is skipped rather than
## planted. An empty rect leaves only the coarse bound in `PickupLimits`.
##
## Call it *after* `EventBus.floor_started`, for the reason `FloorPickups.apply` documents from
## the other side: the spawner empties its container on that signal so no drop follows the
## player down the stairs, and the ones a resume replays are exactly the drops that must
## survive it. Replaying them before would hand them straight to `clear_pickups()`.
static func apply(spawner: PickupSpawner, state: RunState, bounds: Rect2 = Rect2()) -> int:
	if spawner == null or not is_instance_valid(spawner) or state == null:
		return 0
	var restored := 0
	for entry: Dictionary in state.floor_drops:
		var pickup := spawner.restore(entry, bounds)
		if pickup != null and pickup.is_inside_tree():
			restored += 1
	return restored
