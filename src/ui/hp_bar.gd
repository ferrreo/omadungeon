## Segmented HP bar with a trailing "chip" ghost and a danger pulse under 30%.
##
## The danger state is never only "the bar turned red": under DANGER_FRACTION the bar also
## grows a warning notch at the threshold, and with `colorblind_glyphs` on the remaining fill
## is hatched. `reduced_flash` damps the pulse and the hit flash; `reduce_motion` stops the
## chip ghost from sliding (it snaps instead).
class_name HpBar
extends Control

const DANGER_FRACTION := 0.3
const SEGMENT_HP := 10.0
const MAX_SEGMENTS := 20
const CHIP_SPEED := 1.6

var hp: float = 100.0
var max_hp: float = 100.0
var _ghost: float = 1.0
var _time: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(100, 8)
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: queue_redraw())


func _process(delta: float) -> void:
	# Redraw only while something actually moves: the chip ghost, the hit flash or the
	# low-health pulse. A full, settled bar costs nothing per frame.
	var target := fraction()
	var animating := _ghost > target or _flash > 0.0 or is_danger()
	if not animating:
		return
	_time += delta
	if _ghost > target:
		_ghost = (
			target if not Accessibility.animates() else maxf(target, _ghost - CHIP_SPEED * delta)
		)
	else:
		_ghost = target
	_flash = maxf(0.0, _flash - delta * 4.0)
	queue_redraw()


func set_hp(new_hp: float, new_max: float) -> void:
	if new_hp < hp:
		_flash = 1.0
	if new_max != max_hp:
		_ghost = clampf(new_hp / maxf(1.0, new_max), 0.0, 1.0)
	hp = new_hp
	max_hp = maxf(1.0, new_max)
	queue_redraw()


func fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func is_danger() -> bool:
	return fraction() < DANGER_FRACTION


func _draw() -> void:
	var w := size.x
	var h := size.y
	var segments := clampi(int(ceilf(max_hp / SEGMENT_HP)), 1, MAX_SEGMENTS)
	var bg := UiTheme.color_a(&"void", 0.75)
	var border := UiTheme.text_color(&"text_dim")
	# `signal_color`, not `color`: the fill has to be readable on the bar's own plate *and*
	# unmistakable for the danger fill. A theme whose green and red are two neutral greys
	# (the `white` fixture) otherwise renders a full bar and a dying one identically.
	var fill := UiTheme.signal_color(&"heal")
	var danger_c := UiTheme.signal_color(&"danger")
	if is_danger():
		var pulse := Accessibility.flash(0.5 + 0.5 * sin(_time * 7.0))
		fill = danger_c.lerp(UiTheme.color(&"text_bright"), pulse * 0.5)
		border = danger_c.lerp(border, 1.0 - pulse)
	draw_rect(Rect2(0, 0, w, h), bg)
	var inner := Rect2(1, 1, w - 2, h - 2)
	var ghost_w := floorf(inner.size.x * _ghost)
	var fill_w := floorf(inner.size.x * fraction())
	if ghost_w > fill_w:
		draw_rect(
			Rect2(inner.position, Vector2(ghost_w, inner.size.y)),
			UiTheme.color_a(&"text_bright", 0.7)
		)
	if fill_w > 0.0:
		var c := fill.lerp(Color.WHITE, Accessibility.flash(_flash) * 0.6)
		var filled := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		draw_rect(filled, c)
		draw_rect(Rect2(inner.position, Vector2(fill_w, 1)), c.lightened(0.25))
		# Colour-blind channel: a hatched remainder says "low" without saying "red".
		if is_danger() and Accessibility.glyphs():
			Accessibility.draw_hatch(self, filled, UiTheme.color_a(&"void", 0.8))
	var step := inner.size.x / float(segments)
	for i in range(1, segments):
		var x := floorf(inner.position.x + step * i)
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), bg, 1.0)
	_draw_danger_notch(inner)
	draw_rect(Rect2(0, 0, w, h), border, false, 1.0)


## A fixed tick at DANGER_FRACTION plus, once the fill has fallen past it, a triangle mark
## above the bar. Both are shape, not hue, so "you are nearly dead" survives any palette.
func _draw_danger_notch(inner: Rect2) -> void:
	var x := floorf(inner.position.x + inner.size.x * DANGER_FRACTION)
	var tick := UiTheme.signal_color(&"danger")
	draw_line(Vector2(x, inner.position.y - 1.0), Vector2(x, inner.end.y + 1.0), tick, 1.0)
	if not is_danger() or not Accessibility.glyphs():
		return
	Accessibility.draw_shape(
		self,
		Rect2(inner.position.x, inner.position.y, inner.size.y, inner.size.y),
		Accessibility.Shape.TRIANGLE,
		tick
	)
