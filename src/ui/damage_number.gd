## Pooled floating damage number: it clears the body it is describing, rises, then fades.
## Crits are bigger and punchier. Spawned by the HUD from `EventBus.damage_number`; call
## `pop` to (re)start.
##
## Three things here are readability rules rather than taste (docs §1 pillar 1, "readable
## chaos"). The rise is a *total distance* over the lifetime, not a damped velocity: the old
## `RISE * delta * (1 - t)` form integrated to about 7 px of travel - under half a tile - so a
## single hit parked its number on the fight underneath it. That rise is deliberately linear
## rather than eased: every number climbs at the same speed, so two numbers the HUD put in
## different lanes when they popped stay that far apart for their whole lives. An ease-out let
## a late number sprint up into the tail of an early one and the two collided in mid-air. And
## the glyphs carry a full one-pixel outline rather than a one-pixel drop shadow, because a
## shadow leaves three of the four sides touching the sprite behind them.
##
## All the numbers come from `FeelProfile` (`data/feel/feel.tres`); the HUD owns where a
## number starts and which lane it lands in.
class_name DamageNumber
extends Node2D

signal finished(number: DamageNumber)

## Outline thickness in px. One frame all the way round, at any font size.
const OUTLINE := 1
## Contrast the outline must clear against the glyph colour before it is worth drawing.
const OUTLINE_CONTRAST := 3.0
## The light mask the lighting layer neither lights nor darkens (`LightRig.TELL_MASK`, bit 4;
## the literal so this widget does not depend on the lighting module).
const LIGHT_MASK := 8

var _text: String = ""
var _color: Color = Color.WHITE
var _outline: Color = Color(0, 0, 0, 0.85)
var _is_crit: bool = false
var _age: float = 0.0
var _drift: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _scale_punch: float = 1.0
var _profile: FeelProfile = FeelProfile.load_default()
## Own RNG (seeded from the pool slot) so gallery/scenario screenshots are reproducible.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_process(false)
	visible = false
	_rng.seed = hash(get_index())
	# The pool lives on the HUD's CanvasLayer, but a number is a world-space mark and must keep
	# its authored colour wherever it is drawn. The lighting layer darkens every item on its
	# light mask; a mask nothing lights or darkens (`LIGHT_MASK`) is the exemption. A material
	# is not: the compatibility renderer modulates unshaded items too.
	light_mask = LIGHT_MASK


## Seconds a number lives, from the shipped feel profile.
func lifetime() -> float:
	return maxf(0.05, _profile.number_lifetime)


## Total px this number travels upward over its life.
func total_rise() -> float:
	return _profile.number_rise_px


## Px of glyph this number occupies *above* its position, scale punch included. The HUD packs
## lanes with it, because a crit in the heading font is half as tall again as a body number
## and a fixed lane step let its ascenders print straight through the lane above.
func height() -> float:
	return _measure(_is_crit, _punch_for(_profile, _is_crit))


## `height()` for a number that has not popped yet.
static func height_for(is_crit: bool) -> float:
	return _measure(is_crit, _punch_for(FeelProfile.load_default(), is_crit))


static func _punch_for(profile: FeelProfile, is_crit: bool) -> float:
	return profile.number_crit_punch if is_crit else profile.number_punch


static func _measure(is_crit: bool, punch: float) -> float:
	var font := UiTheme.heading_font() if is_crit else UiTheme.body_font()
	var size := UiTheme.SIZE_M if is_crit else UiTheme.SIZE_S
	return font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, size).y * (1.0 + punch)


## Where this number was spawned (canvas space). The HUD stacks lanes against live positions,
## but a test wants the anchor the pop was asked for.
func origin() -> Vector2:
	return _origin


## Starts the animation at `screen_pos` (in the HUD's canvas space).
func pop(screen_pos: Vector2, amount: float, is_crit: bool, color: Color) -> void:
	var text := str(int(roundf(amount))) if amount >= 1.0 else "%.1f" % amount
	if is_crit:
		text += "!"
	pop_text(screen_pos, text, is_crit, color)


## Same float with arbitrary text, for feedback that is not a damage figure ("-1 VIT").
func pop_text(screen_pos: Vector2, text: String, is_crit: bool, color: Color) -> void:
	_origin = screen_pos.floor()
	position = _origin
	_text = text
	_color = color
	_outline = outline_for(color)
	_is_crit = is_crit
	_age = 0.0
	var drift := _profile.number_drift_px
	_drift = Accessibility.motion(_rng.randf_range(-drift, drift))
	_scale_punch = 1.0 + Accessibility.motion(_punch_for(_profile, is_crit))
	visible = true
	modulate.a = 1.0
	set_process(true)
	queue_redraw()


## Ink for the outline around `color`: the palette's own outline colour when that is far
## enough from the glyph, otherwise plain black or white - whichever the glyph is not. A
## light theme pushes damage colours dark, and a dark outline under a dark glyph is mush.
static func outline_for(color: Color) -> Color:
	var palette := Desktop.palette if Desktop != null else null
	var ink := palette.outline_color() if palette != null else Color.BLACK
	if ThemePalette.contrast_ratio(ink, color) < OUTLINE_CONTRAST:
		ink = Color.WHITE if ThemePalette.relative_luminance(color) < 0.4 else Color.BLACK
	ink.a = 0.85
	return ink


func _process(delta: float) -> void:
	_age += delta
	var life := lifetime()
	var t := clampf(_age / life, 0.0, 1.0)
	# Constant speed, and the whole distance at once when motion is reduced: either way every
	# live number moves in lockstep, which is what keeps the HUD's lanes from collapsing.
	var travelled := 1.0 if not Accessibility.animates() else t
	position = (
		Vector2(_origin.x + _drift * t, _origin.y - _profile.number_rise_px * travelled).floor()
	)
	_scale_punch = lerpf(_scale_punch, 1.0, minf(1.0, delta * 14.0))
	modulate.a = 1.0 if t < 0.55 else 1.0 - (t - 0.55) / 0.45
	if _age >= life:
		visible = false
		set_process(false)
		finished.emit(self)
	queue_redraw()


func _draw() -> void:
	var font := UiTheme.heading_font() if _is_crit else UiTheme.body_font()
	var size := UiTheme.SIZE_M if _is_crit else UiTheme.SIZE_S
	var text_size := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	var origin_px := Vector2(-text_size.x * 0.5, text_size.y * 0.3).floor()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _scale_punch)
	draw_string_outline(
		font, origin_px, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, OUTLINE, _outline
	)
	draw_string(font, origin_px, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _color)
