## The Mime's barrier: a temporary StaticBody2D on Layers.WORLD that the player collides with
## and that fades after `duration`.
##
## It is drawn the way a thing you cannot walk through has to be drawn. The first version filled
## itself at 0.12-0.20 alpha with a 0.37-0.45 border in `text_bright`, which on a light theme is
## a faintly tinted pane of glass over a near-white floor: a first-time player walked into an
## invisible wall mid-fight and read it as a rendering artefact. That fails the game's first
## pillar ("everything on screen is legible at a glance") on the one object whose entire purpose
## is to change where you may stand. So: a near-opaque `danger` fill guarded for contrast
## against the floor it stands on, an opaque edge, and a hatch that survives on white. The
## shimmer moves the hatch only - the barrier is never see-through at any phase of it.
class_name MimeWall
extends StaticBody2D

const RETINT_TIME := 0.6
## Opacity of the barrier body. Solid enough to read as matter, short of 1.0 so the player can
## still see an enemy standing behind it.
const FILL_ALPHA := 0.86
## Opacity of the hatching and the edge. The edge never moves; the hatch breathes by SHIMMER.
const HATCH_ALPHA := 0.9
const EDGE_WIDTH := 2.0
## How far the shimmer swings the *hatch* alpha, and how fast. Damped by the reduced-flash
## accessibility setting and off entirely under reduce motion, like every other pulse.
const SHIMMER := 0.22
const SHIMMER_HZ := 0.9
## Spacing of the diagonal hatch, in pixels. At 16 px wide that is two full stripes across.
const HATCH_SPACING := 5.0
const HATCH_WIDTH := 1.0
## Contrast the barrier body keeps against the floor behind it, and the edge against the body.
const FLOOR_CONTRAST := 3.0
const EDGE_CONTRAST := 2.5

var size: Vector2 = Vector2(16, 48)
var duration: float = 4.0
var _color: Color = Color(0.8, 0.2, 0.25, 1.0)
var _edge: Color = Color(1, 1, 1, 1)
var _age: float = 0.0
var _retint: Tween


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	z_index = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	add_child(shape)
	_color = _palette_color()
	_edge = edge_color(_color)
	EventBus.palette_changed.connect(_on_palette_changed)
	get_tree().create_timer(duration).timeout.connect(_dissolve)


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(-size * 0.5, size)
	var body := _color
	body.a = FILL_ALPHA
	draw_rect(rect, body)
	var hatch := _edge
	hatch.a = (
		HATCH_ALPHA - Accessibility.flash(SHIMMER) * (0.5 + 0.5 * sin(_age * TAU * SHIMMER_HZ))
	)
	_draw_hatch(rect, hatch)
	var edge := _edge
	edge.a = 1.0
	draw_rect(rect, edge, false, EDGE_WIDTH)


## Diagonal stripes across the barrier. Hatching is what makes it read as a barrier rather than
## as a coloured pane on every theme: a flat fill can land close to some theme's floor, a
## repeating pattern cannot be mistaken for one.
func _draw_hatch(rect: Rect2, color: Color) -> void:
	var span := rect.size.x + rect.size.y
	var steps := int(span / HATCH_SPACING)
	for i in range(steps + 1):
		var offset := float(i) * HATCH_SPACING
		var from := Vector2(rect.position.x, rect.position.y + offset)
		var to := Vector2(rect.position.x + offset, rect.position.y)
		var clipped := _clip_segment(from, to, rect)
		if clipped.size() == 2:
			draw_line(clipped[0], clipped[1], color, HATCH_WIDTH)


## The part of the segment `from`-`to` that lies inside `rect`, as [start, end] or [] when none
## of it does. Godot has no 2D line/rect clip, and an unclipped hatch spills past the collider.
static func _clip_segment(from: Vector2, to: Vector2, rect: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var d := to - from
	var t0 := 0.0
	var t1 := 1.0
	var edges: Array[Vector4] = [
		Vector4(-d.x, from.x - rect.position.x, -d.y, from.y - rect.position.y),
		Vector4(d.x, rect.end.x - from.x, d.y, rect.end.y - from.y),
	]
	for e: Vector4 in edges:
		for pair: Array in [[e.x, e.y], [e.z, e.w]]:
			var p: float = pair[0]
			var q: float = pair[1]
			if is_zero_approx(p):
				if q < 0.0:
					return out
				continue
			var r := q / p
			if p < 0.0:
				t0 = maxf(t0, r)
			else:
				t1 = minf(t1, r)
	if t0 > t1:
		return out
	out.append(from + d * t0)
	out.append(from + d * t1)
	return out


func _dissolve() -> void:
	set_deferred(&"collision_layer", 0)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)


## The barrier's body colour: the theme's `danger`, pushed until it stands off the floor it is
## drawn over. `danger` rather than the ink colour, because this is a hazard, not a decal.
func _palette_color() -> Color:
	var pal := Desktop.palette
	if pal == null:
		return _color
	var body := pal.get_color(&"danger")
	return ThemePalette.separate(body, pal.get_color(&"floor"), FLOOR_CONTRAST)


## Edge and hatch colour: whichever of the theme's brightest ink and its outline stands further
## off the body, so the barrier keeps an edge on light themes as well as dark.
static func edge_color(body: Color) -> Color:
	var pal := Desktop.palette
	if pal == null:
		return Color.WHITE
	var bright := pal.get_color(&"text_bright")
	var dark := pal.outline_color()
	var pick := (
		bright
		if ThemePalette.contrast_ratio(bright, body) >= ThemePalette.contrast_ratio(dark, body)
		else dark
	)
	return ThemePalette.separate(pick, body, EDGE_CONTRAST)


func _on_palette_changed(_palette: ThemePalette) -> void:
	if _retint != null:
		_retint.kill()
	_retint = create_tween()
	_retint.tween_method(_set_color, _color, _palette_color(), RETINT_TIME)


func _set_color(c: Color) -> void:
	_color = c
	_edge = edge_color(c)
	queue_redraw()
