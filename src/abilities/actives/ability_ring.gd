## Expanding, fading ring drawn with the node's modulate colour (see AbilityFx.ring).
class_name AbilityRing
extends Node2D

var radius: float = 24.0
var duration: float = 0.35
var width: float = 2.0
var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var f := clampf(_t / duration, 0.0, 1.0)
	var eased := 1.0 - (1.0 - f) * (1.0 - f)
	var col := Color(1, 1, 1, 1.0 - f)
	draw_arc(Vector2.ZERO, maxf(1.0, radius * eased), 0.0, TAU, 32, col, width, false)
