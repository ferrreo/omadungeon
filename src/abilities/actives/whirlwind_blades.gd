## Spinning blade arcs drawn around the player during Whirlwind; frees itself when done.
class_name WhirlwindBlades
extends Node2D

var radius: float = 24.0
var duration: float = 1.2
var spin_speed: float = 14.0
var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	rotation += spin_speed * delta
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - clampf((_t - duration + 0.2) / 0.2, 0.0, 1.0)
	var col := Color(1, 1, 1, 0.8 * fade)
	for i in range(3):
		var start := i * TAU / 3.0
		draw_arc(Vector2.ZERO, radius, start, start + 1.2, 10, col, 2.0, false)
		draw_arc(
			Vector2.ZERO, radius * 0.6, start + 0.6, start + 1.4, 8, col * Color(1, 1, 1, 0.5), 1.0
		)
