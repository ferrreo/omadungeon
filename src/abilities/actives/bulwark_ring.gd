## Shield gauge drawn around the player while Bulwark is up (`fill` 0..1).
class_name BulwarkRing
extends Node2D

var radius: float = 12.0
var fill: float = 1.0
var _pulse: float = 0.0


func _process(delta: float) -> void:
	_pulse += delta * 6.0
	queue_redraw()


func _draw() -> void:
	var r := radius + sin(_pulse) * 0.8
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(1, 1, 1, 0.25), 1.0, false)
	if fill > 0.0:
		draw_arc(
			Vector2.ZERO,
			r,
			-PI / 2.0,
			-PI / 2.0 + TAU * clampf(fill, 0.0, 1.0),
			24,
			Color.WHITE,
			2.0
		)
