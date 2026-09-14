## The Suit's arena control hazard. In SEIZE mode (phase 2 "Hostile Takeover") it owns a
## growing sector of the boss arena; in SHRINK mode (phase 3 "Exit Liquidity") it owns
## everything outside a shrinking safe circle. Both modes damage on a fixed tick through one
## `Hitbox` whose collision polygons follow the drawn region, and both spend `telegraph_time`
## seconds drawn-but-harmless first so nothing here is unavoidable damage.
class_name TheSuitZone
extends Node2D

## Emitted when the telegraph ended and the hazard started damaging.
signal armed

enum Mode { SEIZE, SHRINK }

## Convex pieces the region is decomposed into (fan triangles / ring quads).
const SEGMENTS := 18
## Seconds between two geometry rebuilds (the region grows slowly; 60 Hz is wasteful).
const REBUILD_INTERVAL := 0.2
## Sector width (radians) at progress 0 and 1.
const SEIZE_MIN_ARC := 0.7
const SEIZE_MAX_ARC := 2.5
## Safe radius at progress 0 (inset from the arena edge) and 1 (fraction of the arena).
const SHRINK_START_INSET := 6.0
const SHRINK_END_FRACTION := 0.55
## The outer edge reaches past the arena so nothing can hide behind the wall.
const OUTER_OVERSHOOT := 1.8
const FILL_ALPHA := 0.22
const TELEGRAPH_ALPHA := 0.1
const EDGE_ALPHA := 0.85
const FALLBACK_DANGER := Color(0.9, 0.3, 0.3)

var mode: Mode = Mode.SEIZE
var arena_center: Vector2 = Vector2.ZERO
var arena_radius: float = 104.0
## Damage per tick (already scaled by the boss).
var damage: float = 10.0
## Seconds between two damage ticks on the same target.
var tick: float = 0.75
## Seconds the region takes to grow from its starting size to its full size.
var duration: float = 24.0
## Angle (radians) the seized sector is centred on; the boss picks it from its own stream.
var sector_angle: float = 0.0
var hitbox: Hitbox

var _age: float = 0.0
var _telegraph_left: float = 0.0
var _rebuild_left: float = 0.0
var _live: bool = false
var _color: Color = FALLBACK_DANGER
var _pieces: Array[PackedVector2Array] = []


func _ready() -> void:
	z_index = -1
	_color = _danger_color()
	EventBus.palette_changed.connect(_on_palette_changed)
	set_physics_process(false)


## Pins the hazard to an arena and its numbers. Call before `arm()`.
func setup(
	center: Vector2, radius: float, tick_damage: float, tick_seconds: float, source: Node2D = null
) -> void:
	arena_center = center
	arena_radius = maxf(24.0, radius)
	damage = maxf(1.0, tick_damage)
	tick = maxf(0.1, tick_seconds)
	global_position = center
	if hitbox == null:
		hitbox = Hitbox.new()
		hitbox.name = "ZoneHitbox"
		hitbox.team = Layers.Team.ENEMY
		hitbox.tags = [DamageInfo.TAG_ABILITY, DamageInfo.TAG_PHYSICAL]
		hitbox.knockback = 0.0
		add_child(hitbox)
	hitbox.damage = damage
	hitbox.multi_hit_interval = tick
	hitbox.source = source


## Starts the telegraph; the hazard goes live (and `armed` fires) `telegraph_time` later.
func arm(new_mode: Mode, telegraph_time: float, grow_time: float = -1.0) -> void:
	mode = new_mode
	if grow_time > 0.0:
		duration = grow_time
	_age = 0.0
	_live = false
	_telegraph_left = maxf(0.05, telegraph_time)
	if hitbox != null:
		hitbox.deactivate()
	_rebuild()
	set_physics_process(true)
	queue_redraw()


## Switches modes without a new telegraph would be unfair: re-arms with a fresh tell instead.
func switch_mode(new_mode: Mode, telegraph_time: float, grow_time: float = -1.0) -> void:
	arm(new_mode, telegraph_time, grow_time)


## True once the telegraph elapsed and the hitbox is dealing damage.
func is_live() -> bool:
	return _live


## 0..1 growth of the region.
func progress() -> float:
	return clampf(_age / maxf(0.01, duration), 0.0, 1.0)


## Angular width (radians) of the seized sector at the current progress.
func sector_arc() -> float:
	return lerpf(SEIZE_MIN_ARC, SEIZE_MAX_ARC, progress())


## Radius (px) of the still-safe circle at the current progress (SHRINK mode).
func safe_radius() -> float:
	return lerpf(
		maxf(8.0, arena_radius - SHRINK_START_INSET), arena_radius * SHRINK_END_FRACTION, progress()
	)


## True when the world-space point is inside the dangerous region right now.
func contains_point(point: Vector2) -> bool:
	var offset := point - arena_center
	if mode == Mode.SHRINK:
		return offset.length() >= safe_radius()
	if offset.length() > arena_radius:
		return false
	return absf(angle_difference(offset.angle(), sector_angle)) <= sector_arc() * 0.5


## The convex pieces (local space) the region is currently built from.
func pieces() -> Array[PackedVector2Array]:
	return _pieces


func _physics_process(delta: float) -> void:
	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		queue_redraw()
		if _telegraph_left <= 0.0:
			_live = true
			if hitbox != null:
				hitbox.activate()
			armed.emit()
		return
	_age += delta
	_rebuild_left -= delta
	if _rebuild_left <= 0.0:
		_rebuild_left = REBUILD_INTERVAL
		_rebuild()
	queue_redraw()


func _rebuild() -> void:
	_pieces = _build_pieces()
	if hitbox == null:
		return
	var existing: Array[CollisionPolygon2D] = []
	for child: Node in hitbox.get_children():
		var poly := child as CollisionPolygon2D
		if poly != null:
			existing.append(poly)
	for i in range(_pieces.size()):
		var poly: CollisionPolygon2D
		if i < existing.size():
			poly = existing[i]
		else:
			poly = CollisionPolygon2D.new()
			hitbox.add_child(poly)
		poly.polygon = _pieces[i]
		poly.set_deferred(&"disabled", false)
	for i in range(_pieces.size(), existing.size()):
		existing[i].set_deferred(&"disabled", true)


func _build_pieces() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if mode == Mode.SHRINK:
		var inner := safe_radius()
		var outer := arena_radius * OUTER_OVERSHOOT
		for i in range(SEGMENTS):
			var a0 := TAU * float(i) / float(SEGMENTS)
			var a1 := TAU * float(i + 1) / float(SEGMENTS)
			(
				out
				. append(
					PackedVector2Array(
						[
							Vector2.from_angle(a0) * inner,
							Vector2.from_angle(a0) * outer,
							Vector2.from_angle(a1) * outer,
							Vector2.from_angle(a1) * inner,
						]
					)
				)
			)
		return out
	var arc := sector_arc()
	var steps := maxi(3, int(round(SEGMENTS * arc / TAU)) + 2)
	for i in range(steps):
		var a0 := sector_angle - arc * 0.5 + arc * float(i) / float(steps)
		var a1 := sector_angle - arc * 0.5 + arc * float(i + 1) / float(steps)
		(
			out
			. append(
				PackedVector2Array(
					[
						Vector2.ZERO,
						Vector2.from_angle(a0) * arena_radius,
						Vector2.from_angle(a1) * arena_radius,
					]
				)
			)
		)
	return out


func _draw() -> void:
	if _pieces.is_empty():
		return
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
	var fill := _color
	fill.a = FILL_ALPHA if _live else TELEGRAPH_ALPHA + 0.1 * pulse
	var edge := _color
	edge.a = EDGE_ALPHA if _live else 0.45 + 0.45 * pulse
	for piece: PackedVector2Array in _pieces:
		draw_colored_polygon(piece, fill)
	if mode == Mode.SHRINK:
		draw_arc(Vector2.ZERO, safe_radius(), 0.0, TAU, 48, edge, 1.5)
		return
	var arc := sector_arc()
	draw_arc(
		Vector2.ZERO,
		arena_radius,
		sector_angle - arc * 0.5,
		sector_angle + arc * 0.5,
		32,
		edge,
		1.5
	)
	for side: float in [-1.0, 1.0]:
		var a := sector_angle + side * arc * 0.5
		draw_line(Vector2.ZERO, Vector2.from_angle(a) * arena_radius, edge, 1.5)


func _danger_color() -> Color:
	if Desktop.palette == null:
		return FALLBACK_DANGER
	return Desktop.palette.get_color(&"danger")


func _on_palette_changed(_palette: ThemePalette) -> void:
	_color = _danger_color()
	queue_redraw()
