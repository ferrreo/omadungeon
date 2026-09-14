## NodePool is what keeps projectile churn from allocating; these cases pin the contract that
## makes reuse safe: acquire hands back a detached node, release resets it and re-arms
## `_ready()`, and a node is never parked twice or past the size limit.
class_name NodePoolTest
extends GdUnitTestSuite


func test_acquire_creates_then_reuses() -> void:
	var pool := NodePool.new(func() -> Node: return Node2D.new())
	var first := pool.acquire()
	assert_int(pool.created).is_equal(1)
	assert_int(pool.reused).is_equal(0)
	assert_bool(pool.release(first)).is_true()
	var second := pool.acquire()
	assert_object(second).is_same(first)
	assert_int(pool.created).is_equal(1)
	assert_int(pool.reused).is_equal(1)
	second.free()


func test_release_detaches_and_runs_the_reset_hook() -> void:
	var seen: Array[Node] = []
	var pool := NodePool.new(
		func() -> Node: return Node2D.new(), func(n: Node) -> void: seen.append(n)
	)
	var node := pool.acquire() as Node2D
	add_child(node)
	assert_object(node.get_parent()).is_same(self)
	pool.release(node)
	assert_object(node.get_parent()).is_null()
	assert_int(seen.size()).is_equal(1)
	assert_object(seen[0]).is_same(node)
	pool.clear()


func test_release_rearms_ready_so_reuse_reinitialises() -> void:
	var pool := NodePool.new(func() -> Node: return PoolReadyProbe.new())
	var probe := pool.acquire() as PoolReadyProbe
	add_child(probe)
	assert_int(probe.readies).is_equal(1)
	pool.release(probe)
	var again := pool.acquire() as PoolReadyProbe
	add_child(again)
	assert_object(again).is_same(probe)
	assert_int(again.readies).is_equal(2)
	again.queue_free()


func test_release_refuses_freed_and_duplicate_nodes() -> void:
	var pool := NodePool.new(func() -> Node: return Node2D.new())
	assert_bool(pool.release(null)).is_false()
	var node := pool.acquire()
	assert_bool(pool.release(node)).is_true()
	# A second release of an already-parked node must not put it in twice: two callers would
	# then acquire the same instance.
	assert_bool(pool.release(node)).is_false()
	assert_int(pool.size()).is_equal(1)
	pool.clear()


func test_size_limit_frees_instead_of_growing_without_bound() -> void:
	var pool := NodePool.new(func() -> Node: return Node2D.new(), Callable(), 2)
	var nodes: Array[Node] = [pool.acquire(), pool.acquire(), pool.acquire()]
	assert_bool(pool.release(nodes[0])).is_true()
	assert_bool(pool.release(nodes[1])).is_true()
	assert_bool(pool.release(nodes[2])).is_false()
	assert_int(pool.size()).is_equal(2)
	pool.clear()
	assert_int(pool.size()).is_equal(0)


func test_prewarm_fills_the_free_list() -> void:
	var pool := NodePool.new(func() -> Node: return Node2D.new())
	pool.prewarm(5)
	assert_int(pool.size()).is_equal(5)
	assert_int(pool.created).is_equal(5)
	var node := pool.acquire()
	assert_int(pool.created).is_equal(5)
	assert_int(pool.reused).is_equal(1)
	node.free()
	pool.clear()


## Counts how many times it entered the tree ready.
class PoolReadyProbe:
	extends Node2D
	var readies: int = 0

	func _ready() -> void:
		readies += 1
