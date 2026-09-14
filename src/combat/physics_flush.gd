## The physics query flush window, made visible to the code that has to obey it.
##
## The rule this project states for itself - "anything reached from a hit that adds a node with
## a collision shape to the tree must defer the insertion" (`Hitbox`, `PickupBase`) - has no
## engine-side test to go with it. Godot exposes `Engine.is_in_physics_frame()`, which is *not*
## the same window: a collider added from `_physics_process` is accepted, while one added from
## inside an `area_entered`/`body_entered` callback has its `monitoring`, `monitorable`,
## `collision_layer` and `CollisionShape2D.shape` writes refused
## ("Can't change this state while flushing queries") and comes up half-built. Deferring on
## `is_in_physics_frame()` would therefore defer the legal case too, one frame late, for
## nothing.
##
## So the window is marked explicitly where it opens - the physics signal callbacks in
## `Hitbox` - and read here by the insertion points that a hit can reach. `enter()`/`exit()`
## nest, because one hit can start another.
##
## What this does **not** do is guess. If a new physics callback starts dealing damage without
## marking its window, code reached from it is back to inserting synchronously, so the marking
## belongs with the callback, next to the damage. `tests/unit/tools/physics_deferral_test.gd`
## is what notices when it is missing: it kills enemies through a real overlap and compares the
## spawned colliders against the same enemies killed outside one.
class_name PhysicsFlush
extends RefCounted

## Nesting depth of the open flush windows. Static: the physics server has one state and every
## caller is asking about that one.
static var _depth: int = 0


## Marks the start of a physics query flush (a `area_entered`/`body_entered` callback).
static func enter() -> void:
	_depth += 1


## Marks the end of one. Clamped at zero so a stray `exit()` cannot wedge the process into
## deferring every insertion for the rest of the run.
static func exit() -> void:
	_depth = maxi(0, _depth - 1)


## True while a physics callback marked by `enter()` is running, i.e. while the server refuses
## collider state changes.
static func is_flushing() -> bool:
	return _depth > 0


## Adds `node` under `parent` at world position `pos`, deferring the insertion when the server
## is flushing its queries. Returns true when it was deferred.
##
## The position is set after the insertion in both branches, so a caller reading
## `node.global_position` sees the same value either way once the frame's message queue has
## run (`SceneTree` flushes it at the end of the physics step, so nothing lands a frame late).
static func add_child_at(parent: Node, node: Node2D, pos: Vector2) -> bool:
	if parent == null or node == null:
		return false
	if is_flushing():
		_attach_at.call_deferred(parent, node, pos)
		return true
	_attach_at(parent, node, pos)
	return false


## Same, for a child that takes its place from the parent's transform (an attack's hitbox sits
## at the attack's origin) and must therefore *not* have a world position written over it.
static func add_child(parent: Node, node: Node) -> bool:
	if parent == null or node == null:
		return false
	if is_flushing():
		_attach.call_deferred(parent, node)
		return true
	_attach(parent, node)
	return false


## Deferred half of `add_child_at`.
static func _attach_at(parent: Node, node: Node2D, pos: Vector2) -> void:
	if not _reparent(parent, node):
		return
	node.global_position = pos


## Deferred half of `add_child`. A parent that went away between the hit and the flush (a room
## torn down, the boss arena freed) leaves the node with nowhere to go; it is freed rather than
## leaked, because an unparented node nobody holds is an orphan the test gate counts.
static func _attach(parent: Node, node: Node) -> void:
	_reparent(parent, node)


static func _reparent(parent: Node, node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		node.free()
		return false
	parent.add_child(node)
	return true
