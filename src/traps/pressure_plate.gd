## Pressure plate (docs §9): visible; stepping on it presses it, which fires/toggles every node in
## `linked_group` (TrapBase gets `on_plate_pressed`; doors/cages may implement the same method)
## and emits `EventBus.plate_pressed(plate_id)`.
class_name PressurePlate
extends TrapBase

signal pressed_changed(pressed: bool)

const FRAME_PRESSED := 1

@export var plate_id: StringName = &"plate"
## Group name of the nodes this plate controls.
@export var linked_group: StringName = &""
## Stay pressed after the body leaves.
@export var latching: bool = true

var pressed: bool = false
var area: Area2D
var _bodies: Array[Node2D] = []


func _init() -> void:
	kind = &"pressure_plate"
	damage = 0.0
	hitbox_size = Vector2(12.0, 12.0)
	# A plate reacts to bodies, never to another plate's `on_plate_pressed`.
	plate_controlled = false


func configure(extra: Dictionary) -> void:
	super.configure(extra)
	if extra.has("plate_id"):
		plate_id = StringName(str(extra["plate_id"]))
	if extra.has("linked_group"):
		linked_group = StringName(str(extra["linked_group"]))
	if extra.has("latching"):
		latching = bool(extra["latching"])


func _uses_hitbox() -> bool:
	return false


func _on_setup() -> void:
	if controlled_group() == &"":
		push_warning(
			"PressurePlate '%s' controls nothing: pass a 'linked_group' (or a 'room_id')" % plate_id
		)
	area = Area2D.new()
	area.name = "PlateArea"
	area.collision_layer = Layers.TRAP
	area.collision_mask = Layers.PLAYER | Layers.ENEMY
	area.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = hitbox_size - Vector2(4.0, 4.0)
	shape.shape = rect
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	particles.color = _palette_color(&"accent")


func _on_body_entered(body: Node2D) -> void:
	if not _bodies.has(body):
		_bodies.append(body)
	if not pressed:
		press()


func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)
	if _bodies.is_empty() and pressed and not latching:
		release()


## Presses the plate (also callable by scripted events).
func press() -> void:
	if pressed or not enabled:
		return
	pressed = true
	_set_frame(FRAME_PRESSED)
	if sprite != null and is_inside_tree():
		sprite.position = Vector2(0.0, 1.0)
		sprite.scale = Vector2(1.1, 0.85)
		var tween := create_tween()
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.12)
	if particles != null:
		particles.restart()
		particles.emitting = true
	_notify_linked(true)
	pressed_changed.emit(true)
	EventBus.plate_pressed.emit(plate_id)


## Releases a non-latching plate.
func release() -> void:
	if not pressed:
		return
	pressed = false
	_set_frame(FRAME_IDLE)
	if sprite != null:
		sprite.position = Vector2.ZERO
	_notify_linked(false)
	pressed_changed.emit(false)


## The group this plate controls: `linked_group`, else the room trap group when the plate was
## configured with a `room_id` (TrapBase.room_group), else empty.
func controlled_group() -> StringName:
	if linked_group != &"":
		return linked_group
	if room_id >= 0:
		return TrapBase.room_group(room_id)
	return &""


## Nodes controlled by this plate (members of `controlled_group()`).
func linked_nodes() -> Array[Node]:
	var out: Array[Node] = []
	var group := controlled_group()
	if group == &"" or not is_inside_tree():
		return out
	for node: Node in get_tree().get_nodes_in_group(group):
		if node != self:
			out.append(node)
	return out


func _notify_linked(is_pressed: bool) -> void:
	for node: Node in linked_nodes():
		if node.has_method("on_plate_pressed"):
			node.call("on_plate_pressed", plate_id, is_pressed)
