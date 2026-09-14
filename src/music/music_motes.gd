## Ambient motes over the dungeon - dust in a crypt, embers in a forge, snow in the frost -
## whose *number* follows the music's mood (`MusicMoodState.particles`) and whose motion
## follows nothing but a slow drift. Drawn by hand rather than with a particle node so the
## density can move continuously: every mote has a permanent slot and a target alpha (on or
## off, by whether its index is under the current count), and eases toward it over
## `FADE_SECONDS`, so a change of density is a slow reveal and never a pop. Nothing here reads
## the beat, the spectrum or the energy; the count arrives from a state that has already been
## through the mood crossfade.
class_name MusicMotes
extends Control

enum Kind { DUST, EMBER, SNOW, MOTE }

## Seconds a mote takes to fade in or out when the density changes.
const FADE_SECONDS := 2.5
## World size of one mote, in the layer's own pixels (the viewport is 480x270).
const MOTE_SIZE := 2.0
## The lit core of a mote, and the fainter halo that stops its edge being a border.
const MOTE_CORE_RADIUS := MOTE_SIZE * 0.5
const MOTE_HALO_RADIUS := MOTE_SIZE
## Share of a mote's alpha the halo carries.
const HALO_ALPHA := 0.35
## Slowest and fastest drift, pixels per second, before the kind's own scale.
const DRIFT_MIN := 3.0
const DRIFT_MAX := 9.0
## Most alpha a fully shown mote may have.
const ALPHA_MAX := 0.55

## Which biomes draw which kind; anything unlisted is dust.
const KIND_BY_BIOME := {
	&"forge": Kind.EMBER,
	&"frost": Kind.SNOW,
	&"void": Kind.MOTE,
}

var kind: Kind = Kind.DUST
var color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Whether the motes may move at all; false under reduce-motion (they still fade, slowly).
var drifting: bool = true

var _capacity: int = 0
var _shown: int = 0
var _positions: PackedVector2Array = PackedVector2Array()
var _velocities: PackedVector2Array = PackedVector2Array()
var _alphas: PackedFloat32Array = PackedFloat32Array()
var _phases: PackedFloat32Array = PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 0x6d6f7465


## Allocates `count` slots. Deterministic per call order, so a capture of the same state twice
## draws the motes in the same places.
func set_capacity(count: int) -> void:
	_capacity = maxi(count, 0)
	_positions.resize(_capacity)
	_velocities.resize(_capacity)
	_alphas.resize(_capacity)
	_phases.resize(_capacity)
	var area := _area()
	for i in _capacity:
		_positions[i] = Vector2(_rng.randf() * area.x, _rng.randf() * area.y)
		_velocities[i] = _drift_for(i)
		_alphas[i] = 0.0
		_phases[i] = _rng.randf() * TAU
	_shown = mini(_shown, _capacity)


## How many motes should be visible. Slots past `count` fade out, slots under it fade in.
func set_shown(count: int) -> void:
	_shown = clampi(count, 0, _capacity)


func shown() -> int:
	return _shown


func capacity() -> int:
	return _capacity


## The biome decides the kind: embers rise, snow falls, dust and void motes wander.
func set_biome(biome: StringName) -> void:
	var next: Kind = KIND_BY_BIOME.get(biome, Kind.DUST)
	if next == kind:
		return
	kind = next
	for i in _capacity:
		_velocities[i] = _drift_for(i)


## One frame: alphas ease toward their target, positions drift and wrap.
func step(delta: float) -> void:
	_time += delta
	var k := clampf(delta / FADE_SECONDS, 0.0, 1.0)
	var area := _area()
	for i in _capacity:
		var target := ALPHA_MAX if i < _shown else 0.0
		_alphas[i] += (target - _alphas[i]) * k
		if not drifting or _alphas[i] <= 0.001:
			continue
		var p := _positions[i] + _velocities[i] * delta
		# A gentle sideways sway, slow enough (one cycle every 6-10 s) to read as air, not beat.
		p.x += sin(_time * 0.8 + _phases[i]) * 4.0 * delta
		p.x = fposmod(p.x, maxf(area.x, 1.0))
		p.y = fposmod(p.y, maxf(area.y, 1.0))
		_positions[i] = p
	queue_redraw()


## Mean alpha over every slot: the density the tests measure, which must move smoothly.
func density() -> float:
	if _capacity == 0:
		return 0.0
	var total := 0.0
	for a in _alphas:
		total += a
	return total / (float(_capacity) * ALPHA_MAX)


## A mote is a speck of dust caught in the light, not a tile. It used to draw as a hard
## `MOTE_SIZE` square, which at this scale reads as a floating block over the dungeon - the
## owner's words were "weird floating squares". It is drawn as a soft point now: a small core
## at the mote's own alpha and a wider, much fainter halo around it, so the edge falls off
## instead of ending. Two circles rather than a texture keeps the density continuous, which is
## the whole reason these are drawn by hand (see the note at the top of this file).
func _draw() -> void:
	for i in _capacity:
		var a := _alphas[i]
		if a <= 0.002:
			continue
		var at := _positions[i].floor() + Vector2(MOTE_SIZE, MOTE_SIZE) * 0.5
		draw_circle(at, MOTE_HALO_RADIUS, Color(color.r, color.g, color.b, a * HALO_ALPHA))
		draw_circle(at, MOTE_CORE_RADIUS, Color(color.r, color.g, color.b, a))


func _area() -> Vector2:
	var s := size
	if s.x < 1.0 or s.y < 1.0:
		s = get_viewport_rect().size if is_inside_tree() else Vector2(480, 270)
	return s


## Where a mote of this kind goes: embers up, snow down, dust every way, slowly.
func _drift_for(index: int) -> Vector2:
	var speed := _rng.randf_range(DRIFT_MIN, DRIFT_MAX)
	match kind:
		Kind.EMBER:
			return Vector2(_rng.randf_range(-0.3, 0.3), -1.0).normalized() * speed
		Kind.SNOW:
			return Vector2(_rng.randf_range(-0.4, 0.4), 1.0).normalized() * speed * 1.2
		_:
			var angle := _rng.randf() * TAU + float(index) * 0.01
			return Vector2(cos(angle), sin(angle)) * speed * 0.6
