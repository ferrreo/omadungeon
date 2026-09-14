## The "!" that pops over an enemy on the frame it notices the player.
##
## The wake-up is the one moment in the awareness model the player has to be able to read: an
## enemy that was standing still is now coming, and without a tell that reads as the AI
## stuttering. It is drawn rather than authored so it costs no sheet and follows the theme —
## the theme's brightest ink inside a one-pixel rim of the theme's darkest, which is the same
## pairing `SpriteOutline` uses to keep a silhouette off a floor of any colour.
##
## Deliberately *not* the `danger` colour: that is the attack-tell language (`Telegraph`,
## `DangerTell`, every armed trap), and "I have seen you" must not read as "this is about to
## hurt you".
class_name AlertMark
extends Node2D

## Seconds the pop takes to reach full size.
const POP_TIME := 0.16
## Seconds of fade at the end of the mark's life.
const FADE_TIME := 0.25
## Peak overshoot of the pop.
const POP_SCALE := 1.25
## How far (px) the mark rises over its life.
const RISE := 2.0
## Contrast the glyph is held at against its own rim, so it stays a mark and not a smudge.
const RIM_CONTRAST := 4.5

var _left: float = 0.0
var _duration: float = 0.0
var _ink: Color = Color(0, 0, 0, 0.85)
var _fg: Color = Color.WHITE
var _base_y: float = 0.0


func _ready() -> void:
	z_index = 6
	_base_y = position.y
	_read_palette()
	EventBus.palette_changed.connect(_on_palette_changed)
	visible = false
	set_process(false)


## Pops the mark for `duration` seconds. Calling it again restarts the pop.
func show_for(duration: float) -> void:
	_duration = maxf(0.1, duration)
	_left = _duration
	visible = true
	modulate.a = 1.0
	scale = Vector2.ONE if _reduce_motion() else Vector2.ONE * 0.4
	position.y = _base_y
	set_process(true)
	queue_redraw()


func is_showing() -> bool:
	return _left > 0.0


## Hides the mark immediately (death, or a wake-up that was cancelled).
func clear() -> void:
	_left = 0.0
	visible = false
	set_process(false)


## Where the mark sits above the body. Stored so the rise always starts from the same place.
func set_anchor(y: float) -> void:
	_base_y = y
	position.y = y


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		clear()
		return
	var elapsed := _duration - _left
	if _reduce_motion():
		scale = Vector2.ONE
	else:
		scale = Vector2.ONE * _pop_scale(elapsed)
		position.y = _base_y - RISE * clampf(elapsed / maxf(0.01, _duration), 0.0, 1.0)
	modulate.a = clampf(_left / FADE_TIME, 0.0, 1.0)


## Scale of the pop `elapsed` seconds in: overshoots `POP_SCALE` and settles at 1.
func _pop_scale(elapsed: float) -> float:
	if elapsed >= POP_TIME:
		return 1.0
	var t := clampf(elapsed / POP_TIME, 0.0, 1.0)
	if t < 0.6:
		return lerpf(0.4, POP_SCALE, t / 0.6)
	return lerpf(POP_SCALE, 1.0, (t - 0.6) / 0.4)


func _draw() -> void:
	# Rim first, then the glyph on top of it: two rects a pixel larger on every side.
	draw_rect(Rect2(-2.0, -9.0, 4.0, 7.0), _ink)
	draw_rect(Rect2(-2.0, -3.0, 4.0, 4.0), _ink)
	draw_rect(Rect2(-1.0, -8.0, 2.0, 5.0), _fg)
	draw_rect(Rect2(-1.0, -2.0, 2.0, 2.0), _fg)


## Rim colour: the theme's darkest ink, the same one enemy silhouettes use.
static func rim_color(palette: ThemePalette) -> Color:
	if palette == null:
		return Color(0, 0, 0, 0.85)
	var ink := palette.outline_color()
	ink.a = 0.85
	return ink


## Glyph colour: the theme's brightest text, pushed until it clears `RIM_CONTRAST` against
## the rim it is drawn inside. On a light theme that rim is a dark ink and the glyph stays
## bright; on `white` it is what stops a pale mark vanishing into its own outline.
static func glyph_color(palette: ThemePalette) -> Color:
	if palette == null:
		return Color.WHITE
	var rim := rim_color(palette)
	rim.a = 1.0
	return ThemePalette.ensure_contrast(palette.get_color(&"text_bright"), rim, RIM_CONTRAST)


func _read_palette() -> void:
	var palette := Desktop.palette if Desktop != null else null
	_ink = rim_color(palette)
	_fg = glyph_color(palette)


func _on_palette_changed(_palette: ThemePalette) -> void:
	_read_palette()
	queue_redraw()


func _reduce_motion() -> bool:
	return bool(GameState.settings.get("reduce_motion", false))
