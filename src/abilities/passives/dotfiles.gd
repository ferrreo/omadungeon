## Dotfiles: every equipped item grants +1 (per tier) to the player's lowest primary stat —
## all the points land on the single stat that was lowest when the passive recomputed, not
## spread across several. Reads the real Equipment contract (`items()`), falling back to a
## `slots` Dictionary/Array, and re-applies whenever EventBus.item_equipped fires.
class_name DotfilesPassive
extends PassiveAbility

@export var points_per_item: int = 1
var _player: Entity
var _listener: Callable


func apply(player: Node2D) -> void:
	_player = player as Entity
	if _player == null:
		return
	_grant(_player)
	if not _listener.is_valid():
		_listener = _on_item_equipped
		EventBus.item_equipped.connect(_listener)


func remove(player: Node2D) -> void:
	super(player)
	if _listener.is_valid() and EventBus.item_equipped.is_connected(_listener):
		EventBus.item_equipped.disconnect(_listener)
	_listener = Callable()
	_player = null


func _on_item_equipped(_item: Resource, _slot: StringName) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.stats.remove_owner(owner_id())
	_grant(_player)


## Number of equipped items on `player` (0 when it wears no Equipment). `Equipment.items()`
## is the contract (src/items/equipment.gd); the `slots` branch covers test doubles.
static func equipped_count(player: Node) -> int:
	var equipment: Variant = player.get("equipment")
	if equipment == null or not (equipment is Object):
		return 0
	var object := equipment as Object
	if object.has_method("items"):
		var worn: Variant = object.call("items")
		if worn is Array:
			return _count_non_null(worn as Array)
	var slots: Variant = object.get("slots")
	if slots is Dictionary:
		return _count_non_null((slots as Dictionary).values())
	if slots is Array:
		return _count_non_null(slots as Array)
	return 0


static func _count_non_null(values: Array) -> int:
	var count := 0
	for value: Variant in values:
		if value != null:
			count += 1
	return count


static func lowest_primary(stats: Stats) -> StringName:
	var best := Stats.PRIMARY[0]
	var best_value := INF
	for stat: StringName in Stats.PRIMARY:
		var v := stats.get_value(stat)
		if v < best_value:
			best_value = v
			best = stat
	return best


func _grant(player: Entity) -> void:
	var items := equipped_count(player)
	if items <= 0:
		return
	# One stat chosen once: the spec is "+1 lowest primary per item", not a rebalancing spread.
	player.stats.add_flat(
		lowest_primary(player.stats), owner_id(), float(items * points_per_item * tier)
	)
