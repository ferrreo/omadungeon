## The little health bar over an enemy: palette-tinted, compact, and shown only once the
## enemy has something to show.
##
## It used to be elites and bosses only, which left the player guessing at every ordinary
## fight — "is this one nearly dead or have I been hitting the air?". Every enemy carries one
## now, under two rules that keep forty of them off the screen at once:
##
## * an ordinary enemy's bar appears on the first hit it takes and fades out
##   `EnemyHpBarStyle.hide_delay` seconds after the last one, so an untouched pack is invisible
##   and the fight you are actually in is not;
## * an elite or a boss wears its bar for the whole fight, which is how the player has always
##   been able to tell one at a glance.
##
## Geometry and the contrast the colours are held to are data (`data/enemies/health_bars.tres`).
class_name EnemyHpBar
extends Node2D

const RETINT_TIME := 0.6

@export var width: float = 24.0
@export var height: float = 3.0

var fraction: float = 1.0
## True for elites and bosses: the bar is up from the first frame and never hides.
var always_visible: bool = false
var style: EnemyHpBarStyle = EnemyHpBarStyle.shared()
var _fill: Color = Color(0.9, 0.3, 0.3)
var _track: Color = Color(0.2, 0.2, 0.25)
var _backing: Color = Color(0, 0, 0, 0.6)
var _retint: Tween
## Seconds until an ordinary enemy's bar starts fading (0 when it is not counting down).
var _hide_left: float = 0.0


func _ready() -> void:
	z_index = 5
	_read_palette()
	EventBus.palette_changed.connect(_on_palette_changed)
	set_process(false)


## Sizes and places the bar for one enemy. `heavy` is elite-or-boss: a wider, taller bar that
## is always on show.
func configure(sprite_size: int, heavy: bool) -> void:
	if style == null:
		style = EnemyHpBarStyle.shared()
	always_visible = heavy
	width = style.width_for(sprite_size, heavy)
	height = style.height_for(heavy)
	position.y = style.anchor_for(sprite_size, heavy)
	visible = heavy
	modulate.a = 1.0
	_hide_left = 0.0
	set_process(false)
	queue_redraw()


## Sets how full the bar is. Anything below full reveals an ordinary enemy's bar and restarts
## its hide countdown, so the reveal is a consequence of being hurt rather than a separate
## call every caller has to remember.
func set_fraction(value: float) -> void:
	var previous := fraction
	fraction = clampf(value, 0.0, 1.0)
	if fraction < 1.0 and fraction != previous:
		reveal()
	queue_redraw()


## Shows the bar and restarts the countdown that hides it again.
func reveal() -> void:
	visible = true
	modulate.a = 1.0
	if always_visible:
		set_process(false)
		return
	_hide_left = maxf(0.0, style.hide_delay) + maxf(0.0, style.fade_time)
	set_process(true)


## Hides it now (death, or a pooled enemy being re-used).
func hide_now() -> void:
	visible = false
	_hide_left = 0.0
	set_process(false)


## Seconds left before the bar is gone (0 for a bar that is not counting down).
func hide_countdown() -> float:
	return _hide_left


func _process(delta: float) -> void:
	if always_visible:
		set_process(false)
		return
	_hide_left -= delta
	if _hide_left <= 0.0:
		hide_now()
		modulate.a = 1.0
		return
	modulate.a = clampf(_hide_left / maxf(0.01, style.fade_time), 0.0, 1.0)


func _draw() -> void:
	var x := -width * 0.5
	var b := style.border if style != null else 1.0
	draw_rect(Rect2(x - b, -b, width + b * 2.0, height + b * 2.0), _backing)
	draw_rect(Rect2(x, 0.0, width, height), _track)
	if fraction > 0.0:
		draw_rect(Rect2(x, 0.0, maxf(1.0, roundf(width * fraction)), height), _fill)


func _palette() -> ThemePalette:
	return Desktop.palette if Desktop != null else null


func _read_palette() -> void:
	var palette := _palette()
	if palette == null:
		return
	_fill = EnemyHpBarStyle.fill_for(palette, style)
	_track = EnemyHpBarStyle.track_for(palette, style)
	_backing = EnemyHpBarStyle.backing_for(palette, style)


func _on_palette_changed(_palette: ThemePalette) -> void:
	var palette := _palette()
	if palette == null:
		return
	if _retint != null:
		_retint.kill()
	_backing = EnemyHpBarStyle.backing_for(palette, style)
	_retint = create_tween().set_parallel(true)
	_retint.tween_method(_set_fill, _fill, EnemyHpBarStyle.fill_for(palette, style), RETINT_TIME)
	_retint.tween_method(_set_track, _track, EnemyHpBarStyle.track_for(palette, style), RETINT_TIME)


func _set_fill(c: Color) -> void:
	_fill = c
	queue_redraw()


func _set_track(c: Color) -> void:
	_track = c
	queue_redraw()
