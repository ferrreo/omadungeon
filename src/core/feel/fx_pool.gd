## Recycling pool for the two particle effects a busy screen spawns dozens of: projectile
## trails and impact puffs. One `FxPool` node lives under the tree root and owns every emitter;
## callers borrow one and it returns itself when it has finished, so a fight that fires forty
## bolts allocates only as many `CPUParticles2D` as were ever alive at once (`allocations()`
## stops rising once the high-water mark is reached).
##
## Emitters use `local_coords = false` and are driven from here, so a trail keeps its plume
## behind a projectile that is freed mid-flight instead of vanishing with it.
class_name FxPool
extends Node2D

const NODE_NAME := "FxPool"
## Virtual resource path the shared 2x2 particle texture is cached under.
const TEXTURE_KEY := "res://.fx_pool/dot"
## Drawn above the floor and props, below the UI canvas layers.
const Z_INDEX := 10

var profile: FeelProfile

var _idle: Array[CPUParticles2D] = []
var _live: Array[Dictionary] = []
var _allocations: int = 0


func _init() -> void:
	profile = FeelProfile.load_default()


func _ready() -> void:
	z_index = Z_INDEX
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.floor_started.connect(_on_floor_started)


## The shared pool, created under the tree root on first use. Null only without a tree.
static func instance(tree: SceneTree) -> FxPool:
	if tree == null or tree.root == null:
		return null
	var node := tree.root.get_node_or_null(NODE_NAME) as FxPool
	if node == null:
		node = FxPool.new()
		node.name = NODE_NAME
		tree.root.add_child(node)
	return node


## Convenience for any node already in the tree (null when it is not).
static func of(node: Node) -> FxPool:
	if node == null or not node.is_inside_tree():
		return null
	return instance(node.get_tree())


## One-shot impact puff at a world position. Returns the borrowed emitter (already emitting).
func puff(pos: Vector2, tint: Color, count: int = -1, radius: float = 14.0) -> CPUParticles2D:
	var p := _borrow()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, count if count > 0 else profile.puff_count)
	p.lifetime = profile.puff_lifetime
	p.spread = 180.0
	p.initial_velocity_min = radius * 1.5
	p.initial_velocity_max = radius * 3.0
	p.damping_min = radius * 2.0
	p.damping_max = radius * 4.0
	p.scale_amount_min = profile.puff_scale_min
	p.scale_amount_max = profile.puff_scale_max
	p.self_modulate = tint
	p.global_position = pos
	p.restart()
	p.emitting = true
	_live.append({"p": p, "target": 0, "left": profile.puff_lifetime * 2.0})
	return p


## Continuous trail that follows `target` until it leaves the tree, then drains and recycles.
func trail(target: Node2D, tint: Color, radius: float = 6.0) -> CPUParticles2D:
	if target == null:
		return null
	var p := _borrow()
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = maxi(1, profile.trail_count)
	p.lifetime = profile.trail_lifetime
	p.spread = 180.0
	p.initial_velocity_min = radius * 0.5
	p.initial_velocity_max = radius * 1.5
	p.damping_min = radius
	p.damping_max = radius * 2.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.self_modulate = tint
	p.global_position = target.global_position
	p.restart()
	p.emitting = true
	# The follower is held by id, never by reference: a projectile can be freed at any moment
	# and casting a freed object is a runtime error.
	_live.append({"p": p, "target": target.get_instance_id(), "left": -1.0})
	return p


## Stops a borrowed emitter early; it drains its live particles before returning to the pool.
func release(emitter: CPUParticles2D) -> void:
	for entry: Dictionary in _live:
		if entry["p"] != emitter:
			continue
		entry["target"] = 0
		var left := float(entry["left"])
		entry["left"] = profile.trail_lifetime if left < 0.0 else minf(left, profile.trail_lifetime)
		emitter.emitting = false
		return


## Emitters currently lent out.
func active_count() -> int:
	return _live.size()


## Emitters waiting in the pool.
func idle_count() -> int:
	return _idle.size()


## How many `CPUParticles2D` this pool has ever created. Flat across a steady fight is the
## whole point of the pool.
func allocations() -> int:
	return _allocations


## Creates `count` emitters up front so the first busy frame does not allocate.
func prewarm(count: int) -> void:
	while _idle.size() + _live.size() < count:
		_idle.append(_make_emitter())


## Returns every lent emitter to the pool at once (floor change, tests).
func clear() -> void:
	for entry: Dictionary in _live:
		_recycle(entry["p"] as CPUParticles2D)
	_live.clear()


func _on_floor_started(_floor_index: int) -> void:
	clear()


func _process(delta: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var entry: Dictionary = _live[i]
		var p := entry["p"] as CPUParticles2D
		var target_id := int(entry["target"])
		if target_id != 0:
			var target := instance_from_id(target_id) as Node2D
			if target != null and target.is_inside_tree():
				p.global_position = target.global_position
			else:
				# The thing being trailed is gone: stop emitting, let the plume fade out.
				entry["target"] = 0
				entry["left"] = profile.trail_lifetime
				p.emitting = false
		if float(entry["left"]) >= 0.0:
			entry["left"] = float(entry["left"]) - delta
			if float(entry["left"]) <= 0.0:
				_recycle(p)
				_live.remove_at(i)
		i -= 1


func _borrow() -> CPUParticles2D:
	if _idle.is_empty():
		return _make_emitter()
	var p := _idle.pop_back() as CPUParticles2D
	p.visible = true
	return p


func _make_emitter() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Fx%d" % _allocations
	p.local_coords = false
	p.gravity = Vector2.ZERO
	p.emitting = false
	p.texture = dot_texture()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(p)
	_allocations += 1
	return p


func _recycle(p: CPUParticles2D) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.emitting = false
	p.visible = false
	_idle.append(p)


## Shared 2x2 white dot every pooled emitter draws (tint with `self_modulate`).
static func dot_texture() -> Texture2D:
	if ResourceLoader.has_cached(TEXTURE_KEY):
		return ResourceLoader.load(TEXTURE_KEY) as Texture2D
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	tex.take_over_path(TEXTURE_KEY)
	return tex
