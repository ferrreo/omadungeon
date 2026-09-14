## Ice slide (docs §9): visible icy tile; bodies on it get `set_slippery(true)` (momentum preserved)
## and `set_slippery(false)` when they leave. Never deals damage.
class_name IceSlide
extends TrapBase

## Meta key of the shared {instance id -> ice tiles overlapped} map (see `_slip_counts`).
const SLIP_META := &"trap_ice_slip_counts"

## Ice rectangle in pixels.
@export var size: Vector2 = Vector2(16.0, 16.0)

var area: Area2D
var _cold: Color = Color(0.6, 0.85, 1.0)
var _slipping: Array[Node2D] = []


func _init() -> void:
	kind = &"ice_slide"
	damage = 0.0
	# Ice is permanent terrain: a pressure plate must never run it through the trap cycle.
	plate_controlled = false
	hitbox_size = size


func configure(extra: Dictionary) -> void:
	super.configure(extra)
	if extra.has("size"):
		size = extra["size"]
	hitbox_size = size


func _uses_hitbox() -> bool:
	return false


func _on_setup() -> void:
	hitbox_size = size
	_rebuild_tell()
	_cold = _palette_color(&"cold")
	area = Area2D.new()
	area.name = "IceArea"
	area.collision_layer = Layers.TRAP
	area.collision_mask = Layers.PLAYER | Layers.ENEMY
	area.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	if sprite != null:
		sprite.scale = size / Vector2(16.0, 16.0)
		sprite.modulate = _cold.lerp(Color.WHITE, 0.5)
	particles.color = _cold


## {instance id -> number of ice tiles the body overlaps}, shared by every IceSlide so crossing
## the seam between two adjacent tiles never toggles sliding off. Lives on the SceneTree (the
## project forbids static vars).
func _slip_counts() -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	if not tree.has_meta(SLIP_META):
		tree.set_meta(SLIP_META, {})
	return tree.get_meta(SLIP_META)


func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("set_slippery") or _slipping.has(body):
		return
	_slipping.append(body)
	var id := body.get_instance_id()
	var counts := _slip_counts()
	var count := int(counts.get(id, 0)) + 1
	counts[id] = count
	if count == 1:
		body.call("set_slippery", true)


func _on_body_exited(body: Node2D) -> void:
	if not _slipping.has(body):
		return
	_slipping.erase(body)
	_release(body, true)


## Drops one reference for `body`. Crossing the seam between two ice tiles emits exit(A) and
## enter(B) in the same physics step in either order, so the "stop sliding" call is settled at
## the end of the step (`deferred`) and skipped when the body picked up another tile.
func _release(body: Node2D, deferred: bool) -> void:
	var id := body.get_instance_id()
	var counts := _slip_counts()
	counts[id] = maxi(0, int(counts.get(id, 0)) - 1)
	if deferred:
		_settle_slip.call_deferred(id)
	else:
		_settle_slip(id)


func _settle_slip(id: int) -> void:
	var counts := _slip_counts()
	if int(counts.get(id, 0)) > 0:
		return
	counts.erase(id)
	if not is_instance_id_valid(id):
		return
	var body := instance_from_id(id) as Node
	if body != null and body.has_method("set_slippery"):
		body.call("set_slippery", false)


func _on_palette_changed(palette: ThemePalette) -> void:
	super._on_palette_changed(palette)
	var target := palette.get_color(&"cold")
	if not is_inside_tree() or _tint_tween == null or not _tint_tween.is_valid():
		_cold = target
		return
	# Same (parallel) tween as the base crossfade: never a second, competing one.
	_tint_tween.tween_method(_set_cold, _cold, target, PALETTE_TWEEN)


func _set_cold(c: Color) -> void:
	_cold = c
	if sprite != null:
		sprite.modulate = c.lerp(Color.WHITE, 0.5)


func _exit_tree() -> void:
	for body: Node2D in _slipping.duplicate():
		_release(body, false)
	_slipping.clear()
