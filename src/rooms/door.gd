## Lockable door on a room's wall ring. Closed = solid on Layers.WORLD with the closed tile;
## open = passable with the open tile. Animates with a quick squash on close and a fade on open.
class_name Door
extends StaticBody2D

signal opened
signal closed

const ANIM_SECONDS := 0.18

## Grid position of the door tile.
var tile: Vector2i = Vector2i.ZERO
## Room this door belongs to and the neighbour it leads to.
var room_id: int = -1
var leads_to: int = -1
## True when the door sits in a top/bottom wall (sprite unrotated).
var horizontal: bool = true
var is_open: bool = true
var sprite: Sprite2D
var _atlas: Texture2D
var _tween: Tween


func _init() -> void:
	collision_layer = 0
	collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(Layers.TILE, Layers.TILE)
	shape.shape = rect
	add_child(shape)


## Builds the sprite. `material` is the room's palette-swap material (shared).
func setup(atlas: Texture2D, tint: Material, is_horizontal: bool) -> void:
	_atlas = atlas
	horizontal = is_horizontal
	if sprite != null:
		sprite.queue_free()
	sprite = FloorBuilder.atlas_sprite(atlas, FloorBuilder.SPECIAL_DOOR_OPEN)
	sprite.material = tint
	sprite.rotation = 0.0 if horizontal else PI / 2.0
	add_child(sprite)
	_apply_state(false)


## Closes the door (solid). `animate` false snaps instantly (used at build time).
func close(animate: bool = true) -> void:
	if not is_open:
		return
	is_open = false
	_apply_state(animate)
	closed.emit()


## Opens the door (passable).
func open(animate: bool = true) -> void:
	if is_open:
		return
	is_open = true
	_apply_state(animate)
	opened.emit()


func _apply_state(animate: bool) -> void:
	collision_layer = 0 if is_open else Layers.WORLD
	if sprite == null:
		return
	var col := FloorBuilder.SPECIAL_DOOR_OPEN if is_open else FloorBuilder.SPECIAL_DOOR_CLOSED
	sprite.region_rect = FloorBuilder.atlas_cell(col, FloorBuilder.ROW_SPECIAL)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate or not is_inside_tree():
		sprite.scale = Vector2.ONE
		sprite.modulate.a = 1.0
		return
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_open:
		sprite.modulate.a = 0.4
		_tween.tween_property(sprite, ^"modulate:a", 1.0, ANIM_SECONDS)
	else:
		sprite.scale = Vector2(1.3, 0.6)
		_tween.tween_property(sprite, ^"scale", Vector2.ONE, ANIM_SECONDS)
