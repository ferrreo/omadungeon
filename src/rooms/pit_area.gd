## One connected region of PIT tiles. Passive Area2D on Layers.PIT: the player's own
## detector (or traps module) decides what falling means; this node only marks the hole.
class_name PitArea
extends Area2D

## Tiles (grid coords) covered by this region.
var tiles: Array[Vector2i] = []
## Id of the room whose interior contains the region, or -1 for corridor pits.
var room_id: int = -1


func _init() -> void:
	collision_layer = Layers.PIT
	collision_mask = 0
	monitoring = false
	monitorable = true


## Adds one tile-sized shape (slightly inset so brushing the rim is forgiving).
func add_tile(tile: Vector2i) -> void:
	tiles.append(tile)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(Layers.TILE - 2, Layers.TILE - 2)
	shape.shape = rect
	shape.position = (Vector2(tile) + Vector2(0.5, 0.5)) * Layers.TILE
	add_child(shape)


## World-space centre of the region (respawn helpers use the nearest floor to this).
func center_world() -> Vector2:
	if tiles.is_empty():
		return global_position
	var sum := Vector2.ZERO
	for t: Vector2i in tiles:
		sum += (Vector2(t) + Vector2(0.5, 0.5)) * Layers.TILE
	return sum / float(tiles.size())
