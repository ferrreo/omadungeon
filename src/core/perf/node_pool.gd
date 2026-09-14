## Reusable free-list for nodes that are created and destroyed in bursts (projectiles,
## pickups, damage numbers, particle bursts).
##
## The pool never owns tree membership: `acquire()` hands back a node that is *not* in the
## tree and `release()` takes one out of it. A released node gets `request_ready()` so its
## `_ready()` runs again on the next `add_child`, which is what makes an entry-point like
## `Projectile._ready()` safe to reuse — write `_ready()` so it is idempotent (guard signal
## connections with `is_connected`) and the rest follows.
##
##     var pool := NodePool.new(func() -> Node: return Projectile.new())
##     var shot := pool.acquire() as Projectile
##     ...
##     pool.release(shot)
class_name NodePool
extends RefCounted

## Nodes kept when released. Beyond this a release frees the node instead of storing it, so a
## pathological burst cannot pin memory forever.
const DEFAULT_MAX_SIZE := 256

## Upper bound on the free list.
var max_size: int = DEFAULT_MAX_SIZE
## Total nodes the factory was asked for (diagnostics: a healthy pool stops growing).
var created: int = 0
## Times `acquire()` handed back a recycled node.
var reused: int = 0

var _free: Array[Node] = []
var _factory: Callable
var _reset: Callable


## `factory` builds a fresh node; `reset` (optional) is called on a node as it is released,
## before it is stored, and must return it to a like-new state.
func _init(
	factory: Callable, reset: Callable = Callable(), size_limit: int = DEFAULT_MAX_SIZE
) -> void:
	_factory = factory
	_reset = reset
	max_size = maxi(0, size_limit)


## A node ready to be added to the tree, recycled when one is available.
func acquire() -> Node:
	while not _free.is_empty():
		var node := _free.pop_back() as Node
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			reused += 1
			return node
	created += 1
	return _factory.call() as Node


## Returns `node` to the pool. It is detached from its parent first; a node that would push
## the pool past `max_size` is freed instead. Returns true when it was actually stored.
func release(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	if _reset.is_valid():
		_reset.call(node)
	node.request_ready()
	if _free.size() >= max_size or _free.has(node):
		node.queue_free()
		return false
	_free.append(node)
	return true


## Builds `count` nodes up front so the first burst does not pay for them.
func prewarm(count: int) -> void:
	for i in range(count):
		if _free.size() >= max_size:
			return
		created += 1
		_free.append(_factory.call() as Node)


## Nodes currently parked in the pool.
func size() -> int:
	return _free.size()


## Frees every parked node and empties the free list.
func clear() -> void:
	for node: Node in _free:
		if is_instance_valid(node):
			node.free()
	_free.clear()
