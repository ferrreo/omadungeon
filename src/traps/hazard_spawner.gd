## Spawns runtime hazards (ricer traps, kernel spikes, fire zones...) in response to
## `EventBus.spawn_hazard(kind, pos, duration)`. Instances go under `parent_node` (set by the
## game scene to the live FloorRoot), else `parent_path`, else this node; they join group
## "hazard" and are cleared when a new floor starts.
## Assigning `parent_node` a built FloorRoot also places that floor's generator traps through
## `TrapPlacer` (see `place_floor_traps`), so `Game.load_floor` needs no extra wiring.
class_name HazardSpawner
extends Node

signal hazard_spawned(trap: TrapBase)

const GROUP_HAZARD := &"hazard"

## Node the hazards are added under when `parent_node` is unset; defaults to this node.
@export var parent_path: NodePath
## Registry to instantiate from; defaults to data/traps/registry.tres.
@export var registry: TrapRegistry
## Place the floor's generator traps (FloorData trap_positions + PIT tiles) when `parent_node`
## is assigned a built FloorRoot. Turn off when the rooms module places them itself.
@export var place_floor_traps: bool = true

## Runtime parent (the current FloorRoot); takes precedence over `parent_path`. Freed parents are
## ignored, so the game may simply assign it after every floor build. Setting it to a FloorRoot
## that already carries its `FloorData` also builds that floor's traps (once per floor root).
var parent_node: Node:
	set(value):
		parent_node = value
		_place_floor_traps()

var _spawned: Array[TrapBase] = []
var _floor_traps: Array[TrapBase] = []
var _placed_for: int = 0


func _ready() -> void:
	if registry == null:
		registry = TrapRegistry.load_default()
	EventBus.spawn_hazard.connect(_on_spawn_hazard)
	EventBus.floor_started.connect(_on_floor_started)


## Where hazards are parented: `parent_node`, then `parent_path`, then this node.
func spawn_parent() -> Node:
	if parent_node != null and is_instance_valid(parent_node) and parent_node.is_inside_tree():
		return parent_node
	if not parent_path.is_empty():
		var node := get_node_or_null(parent_path)
		if node != null:
			return node
	return self


## Spawns `kind` at world position `pos`. `duration` <= 0 keeps the def default.
func spawn(
	kind: StringName, pos: Vector2, duration: float = 0.0, extra: Dictionary = {}
) -> TrapBase:
	if registry == null:
		registry = TrapRegistry.load_default()
	var options := extra.duplicate()
	if duration > 0.0:
		options["duration"] = duration
	var trap := registry.create(kind, pos, options)
	if trap == null:
		return null
	trap.add_to_group(GROUP_HAZARD)
	var parent := spawn_parent()
	var parent_2d := parent as Node2D
	if parent_2d != null:
		trap.position = parent_2d.to_local(pos)
	parent.add_child(trap)
	_spawned.append(trap)
	trap.tree_exited.connect(_on_trap_gone.bind(trap))
	hazard_spawned.emit(trap)
	return trap


## Traps placed for the current floor (empty until a FloorRoot is assigned).
func floor_traps() -> Array[TrapBase]:
	var out: Array[TrapBase] = []
	for trap: TrapBase in _floor_traps:
		if is_instance_valid(trap) and trap.is_inside_tree():
			out.append(trap)
	return out


## Builds the generator traps of the FloorRoot in `parent_node` (idempotent per floor root).
func _place_floor_traps() -> void:
	if not place_floor_traps or parent_node == null or not is_instance_valid(parent_node):
		return
	var root := parent_node as Node2D
	if root == null or root.get_instance_id() == _placed_for:
		return
	var floor_data: Variant = root.get("data")
	if not (floor_data is FloorData):
		return
	_placed_for = root.get_instance_id()
	if registry == null:
		registry = TrapRegistry.load_default()
	_floor_traps = TrapPlacer.populate(floor_data as FloorData, root, registry)


## Live hazards spawned by this node.
func active_hazards() -> Array[TrapBase]:
	var out: Array[TrapBase] = []
	for trap: TrapBase in _spawned:
		if is_instance_valid(trap) and trap.is_inside_tree():
			out.append(trap)
	return out


## Removes every hazard (floor change, Rm -rf ability...).
func clear_all() -> void:
	for trap: TrapBase in _spawned.duplicate():
		if is_instance_valid(trap):
			trap.queue_free()
	_spawned.clear()


func _on_spawn_hazard(kind: StringName, pos: Vector2, duration: float) -> void:
	spawn(kind, pos, duration)


func _on_floor_started(_floor_index: int) -> void:
	clear_all()


func _on_trap_gone(trap: TrapBase) -> void:
	_spawned.erase(trap)
