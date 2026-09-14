## Attack tell drawn under an enemy: a pulsing ring in the theme `danger` colour during
## windup, or a translucent disc for AoE attacks. Retints on palette change.
##
## Every number it draws with comes from `DangerTell`, the one visual language shared with trap
## arming, so an enemy winding up and a spike floor about to fire pulse at the same rate, in the
## same colour, with the same "brighter and faster as it lands" ramp.
class_name Telegraph
extends Node2D

const RETINT_TIME := 0.6

var color: Color = DangerTell.FALLBACK
var _time_left: float = 0.0
var _duration: float = 0.0
var _radius: float = 16.0
var _filled: bool = false
var _retint: Tween


func _ready() -> void:
	# z 0, not -1: the floor tilemaps sit at z 0, and a negative index hides the tell under the
	# ground (the same trap `TrapBase` documents). Drawing under the body is handled by being
	# the parent's first child instead, so the ring never paints over the enemy it belongs to.
	z_index = 0
	z_as_relative = true
	_sink_under_siblings()
	color = _palette_color()
	EventBus.palette_changed.connect(_on_palette_changed)
	set_process(false)


## Makes this the parent's first child so the tell draws under the body it belongs to. The
## parent is still building its children during `_ready`, so the move is deferred one frame —
## the tell is never active that early.
func _sink_under_siblings() -> void:
	if _needs_sinking():
		_sink_now.call_deferred()


## The deferred half. The parent is looked up again rather than carried across the frame
## boundary in a bound argument: a deferred call is dropped when the object it is *bound to*
## has been freed, but a freed node passed as an argument is not checked, and the enemy this
## tell belongs to can die between the two halves.
func _sink_now() -> void:
	if not _needs_sinking():
		return
	get_parent().move_child(self, 0)


func _needs_sinking() -> bool:
	var parent := get_parent()
	return parent != null and parent.get_child(0) != self


## Flashes a growing ring of `radius` px for `duration` seconds (windup tell).
func flash(duration: float, radius: float) -> void:
	_duration = maxf(0.05, duration)
	_time_left = _duration
	_radius = maxf(6.0, radius)
	_filled = false
	set_process(true)
	queue_redraw()


## Shows a translucent disc of `radius` px for `duration` seconds (AoE tell/impact).
func show_area(duration: float, radius: float) -> void:
	flash(duration, radius)
	_filled = true


func cancel() -> void:
	_time_left = 0.0
	set_process(false)
	queue_redraw()


func is_active() -> bool:
	return _time_left > 0.0


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		cancel()
		return
	queue_redraw()


## Seconds this tell has been running (0 when idle).
func elapsed() -> float:
	return maxf(0.0, _duration - _time_left)


func _draw() -> void:
	if _time_left <= 0.0:
		return
	var t := elapsed()
	var pulse := DangerTell.pulse(t)
	var urgency := DangerTell.urgency(t, _duration)
	var alpha := DangerTell.alpha(t, _duration)
	if _filled:
		var fill := color
		fill.a = alpha * 0.6
		draw_circle(Vector2.ZERO, _radius, fill)
		var edge := color
		edge.a = minf(1.0, alpha + 0.35)
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 32, edge, 1.0)
		return
	# Same three ingredients as a trap's floor tell: a danger-coloured area, a pulsing edge,
	# and (enemies only) the mark over the head that says which body is about to swing.
	var r := DangerTell.ring_radius(t, _duration, _radius)
	var wash := color
	wash.a = alpha * DangerTell.AREA_ALPHA_SCALE
	draw_circle(Vector2.ZERO, r, wash)
	var ring := color
	ring.a = minf(1.0, alpha + 0.35 + 0.15 * urgency)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, ring, DangerTell.RING_WIDTH + pulse)
	var mark := color
	mark.a = minf(1.0, alpha + 0.45 + 0.25 * pulse)
	draw_rect(DangerTell.MARK_STEM, mark)
	draw_rect(DangerTell.MARK_DOT, mark)


func _palette_color() -> Color:
	return DangerTell.color()


func _on_palette_changed(_palette: ThemePalette) -> void:
	if _retint != null:
		_retint.kill()
	_retint = create_tween()
	_retint.tween_method(_set_color, color, _palette_color(), RETINT_TIME)


func _set_color(c: Color) -> void:
	color = c
	queue_redraw()
