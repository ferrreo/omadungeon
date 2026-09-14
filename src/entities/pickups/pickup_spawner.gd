## Node that turns `EventBus.spawn_pickup(kind, pos, amount)` into pickup nodes.
## Kinds: `gold` (amount = coins, split into several pickups), `heart` (amount = heal),
## `stat_orb` (amount = index into Stats.PRIMARY). Pickups are children of `container`
## (defaults to this node). Place one under the floor root.
##
## It is also the kind -> class table a resume reads: `make()` builds a bare node of a kind and
## `from_dict()` / `restore()` put a saved drop back. `spawn()` goes through the same table, so
## a drop the game can create is always a drop a save can restore (`FloorDrops`, docs §12).
## A restored drop is data from disk and is bounded as such - see `PickupLimits`, which every
## kind `make()` answers to needs a row in.
class_name PickupSpawner
extends Node

const MAX_COINS := 5
## Mixed into the drop stream's seed so it cannot collide with another system's stream on the
## same run and floor.
const SEED_SALT := 5417
## Node the pickups are parented to; empty = this spawner.
@export var container_path: NodePath

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Bumped by `clear_pickups()`; a deferred drop from an older generation is thrown away.
var _generation: int = 0


func _ready() -> void:
	_reseed(GameState.run_seed, 0)
	EventBus.spawn_pickup.connect(spawn)
	EventBus.floor_started.connect(_on_floor_started)


## Pickups belong to the floor they dropped on: drop them when a new floor is built, otherwise
## coins from floor N would home to the player at their old coordinates on floor N+1.
func clear_pickups() -> void:
	_generation += 1
	for child: Node in _container().get_children():
		if child is PickupBase and not child.is_queued_for_deletion():
			child.queue_free()


func _on_floor_started(floor_index: int) -> void:
	_reseed(GameState.run_seed, floor_index)
	clear_pickups()


## Seeds the drop stream from the run and the floor, rather than `randomize()`.
##
## Everything else a floor lays down comes from the run seed; this was the exception, and it
## made two things worse than they needed to be. A capture of dropped loot was a different
## picture every run, so no pixel comparison could be made of it; and `PickupBase` drew its bob
## phase from the *global* RNG, the only unseeded global draw left in `src/`, which is what made
## `pickup_frame` flaky - a frozen coin sat anywhere in a one-pixel band and its rim landed on a
## different tile rung each time. The phase now comes from this stream (`_place`), so a drop on
## a given run and floor is the same drop every time it is replayed.
func _reseed(run_seed: int, floor_index: int) -> void:
	rng.seed = RunRng.hash_combine(RunRng.hash_combine(run_seed, floor_index), SEED_SALT)


func _container() -> Node:
	if not container_path.is_empty():
		var node := get_node_or_null(container_path)
		if node != null:
			return node
	return self


## Spawns pickups for a request. Returns the nodes created.
func spawn(kind: StringName, pos: Vector2, amount: int) -> Array[PickupBase]:
	var out: Array[PickupBase] = []
	match kind:
		&"gold":
			var coins := clampi(int(ceili(amount / 3.0)), 1, MAX_COINS)
			var left := amount
			for i in range(coins):
				var value := left if i == coins - 1 else int(roundf(float(amount) / coins))
				value = maxi(1, mini(value, left))
				left -= value
				var coin := make(&"gold")
				coin.amount = value
				out.append(_place(coin, pos, coins > 1))
				if left <= 0:
					break
		&"heart":
			var heart := make(&"heart")
			heart.amount = maxi(1, amount)
			out.append(_place(heart, pos, false))
		&"stat_orb":
			var orb := make(&"stat_orb") as StatOrbPickup
			orb.set_stat_index(amount)
			out.append(_place(orb, pos, false))
		_:
			push_warning("PickupSpawner: unknown pickup kind %s" % kind)
	return out


## A bare pickup node of `kind`, not yet in the tree, or null when no class answers to that
## name. The one place the kinds are mapped to classes: adding a pickup type here is what makes
## it both spawnable and restorable, so the two halves cannot drift apart.
static func make(kind: StringName) -> PickupBase:
	match kind:
		&"gold":
			return GoldPickup.new()
		&"heart":
			return HeartPickup.new()
		&"stat_orb":
			return StatOrbPickup.new()
	return null


## Rebuilds the drop a `PickupBase.to_dict()` entry describes, not yet in the tree. Null when
## the entry names a kind this build does not have - a save from a newer version resumes
## missing that one drop rather than failing to load at all.
##
## The entry is data from disk and is bounded as such (`PickupLimits`, injectable for tests).
## `amount` used only to be clamped to `>= 1`, which let a hand-edited or half-written
## `run.json` resume into a live stat orb worth `999` primary stat points - `StatOrbPickup`
## passes `amount` straight to `player.add_stat()`. Note the field is overloaded across the two
## paths: `EventBus.spawn_pickup(&"stat_orb", pos, amount)` means an *index* into
## `Stats.PRIMARY` and a restored orb means a *magnitude*, which is exactly why the magnitude
## needs a bound the index path never gave it.
static func from_dict(entry: Dictionary, limits: PickupLimits = null) -> PickupBase:
	var kind := StringName(str(entry.get("kind", "")))
	var pickup := make(kind)
	if pickup == null:
		return null
	var rules := PickupLimits.resolve(limits)
	var saved := int(entry.get("amount", pickup.amount))
	pickup.amount = rules.clamp_amount(kind, saved, pickup.amount)
	pickup.load_extra(entry)
	return pickup


## The live, still-collectable drops in the container: exactly what a save has to carry. One
## already taken (playing its fade-out) or queued for deletion is off the floor already, and
## recording it would resurrect collected loot on the next resume.
func live_pickups() -> Array[PickupBase]:
	var out: Array[PickupBase] = []
	for child: Node in _container().get_children():
		var pickup := child as PickupBase
		if pickup != null and not pickup.is_collected() and not pickup.is_queued_for_deletion():
			out.append(pickup)
	return out


## Puts one saved drop back, exactly as it was: the same kind, the same amount, where it lay.
##
## Deliberately not `spawn()`. That splits a gold request into up to `MAX_COINS` coins, so
## replaying five saved coins through it would make twenty-five and multiply the purse on every
## Save & Quit; and it adds a scatter pop, which belongs to the moment of the drop and would
## walk the coin further from its saved spot every time the player took a break.
##
## Returns the node, in the tree already when the physics server is not flushing its queries -
## a resume is driven from `RunManager._build_floor`, which is not a flush window, so the
## caller may count what it gets back instead of counting a promise. Null for an entry no kind
## matches, and for one whose position is not somewhere a drop could have been lying: a
## coordinate of `1e30` is finite, so it survived every earlier check, planted a pickup nowhere
## at all and was written straight back out on the next autosave, for ever. `bounds` is the
## floor's camera limits when the caller knows them; without them the coarse bound in
## `PickupLimits` still applies.
func restore(entry: Dictionary, bounds: Rect2 = Rect2(), limits: PickupLimits = null) -> PickupBase:
	var pos := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
	var rules := PickupLimits.resolve(limits)
	if not rules.accepts_position(pos, bounds):
		return null
	var pickup := from_dict(entry, rules)
	if pickup == null:
		return null
	_insert(pickup, pos)
	return pickup


## Gives `pickup` its spawn scatter and puts it in the container. A drop is almost always
## requested from inside a physics query flush - an enemy dies in a `Hitbox` overlap callback,
## which runs while the physics server is iterating its areas - and an Area2D that enters the
## tree at that moment has its shape and monitoring state refused by the server ("Can't change
## this state while flushing queries"), leaving a pickup with no collider. So inside that
## window `_insert` defers; outside one it inserts at once and the node the caller gets back is
## already in the tree.
func _place(pickup: PickupBase, pos: Vector2, scatter: bool) -> PickupBase:
	var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
	pickup.pop(dir, rng.randf_range(50.0, 90.0) if scatter else rng.randf_range(20.0, 40.0))
	pickup.set_bob_phase(rng.randf() * TAU)
	_insert(pickup, pos)
	return pickup


## Puts `pickup` in the container: deferred while the physics server is flushing its queries,
## immediately when it is not. This is the distinction `PhysicsFlush.add_child_at` makes for
## every other insertion site in the project, and it is made here by hand only because of the
## generation guard `_attach` carries. Deferring unconditionally was not merely late: a
## snapshot taken in the same frame as a resume - which `SaveManager` takes on
## `NOTIFICATION_WM_CLOSE_REQUEST`, with no debounce to hide behind - swept a container that
## was still empty and wrote an empty `floor_drops` over the drops it was about to restore.
func _insert(pickup: PickupBase, pos: Vector2) -> void:
	if PhysicsFlush.is_flushing():
		_attach.call_deferred(pickup, pos, _generation)
		return
	_attach(pickup, pos, _generation)


## The insertion itself, called directly by `_insert` outside a physics flush and deferred
## into the frame's message queue inside one. `generation` is the value `clear_pickups()` had
## bumped when the drop was requested, so a pickup whose floor was torn down in the meantime is
## dropped instead of landing on the new one.
func _attach(pickup: PickupBase, pos: Vector2, generation: int) -> void:
	if not is_instance_valid(pickup):
		return
	if generation != _generation or not is_inside_tree():
		pickup.free()
		return
	_container().add_child(pickup)
	pickup.global_position = pos
