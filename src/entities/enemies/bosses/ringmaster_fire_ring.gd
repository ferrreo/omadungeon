## Phase 2 hazard: a ring of fire around the arena edge that slowly rotates and leaves exactly
## one gap, so the safe spot keeps moving. Telegraphed in the theme `danger` colour before the
## flames become solid. Lives as a `top_level` child of the boss, so it dies with it.
class_name RingmasterFireRing
extends Node2D

const TAGS: Array[StringName] = [DamageInfo.TAG_RANGED, DamageInfo.TAG_FIRE]
const RETINT_TIME := 0.6
const FLAME_ALPHA := 0.85
const TELEGRAPH_ALPHA := 0.35

## Slots around the circle; `gap_slots` of them stay empty (the moving safe lane).
var segments: int = 16
var gap_slots: int = 3
## Rotation speed in radians per second.
var spin_speed: float = 0.45
## Seconds the ring is shown as a harmless telegraph before it burns.
var telegraph_time: float = 1.0
var flame_radius: float = 9.0
var damage: float = 10.0
var burn_duration: float = 2.5
## Seconds before the same target can be burned again by the ring.
var rehit_interval: float = 0.7

var boss: BossBase
var active: bool = false
var armed: bool = false

var _angle: float = 0.0
var _radius: float = 96.0
var _telegraph_left: float = 0.0
var _hitboxes: Array[Hitbox] = []
var _flames: Array[Polygon2D] = []
var _retint: Tween


func _ready() -> void:
	top_level = true
	z_index = 1
	set_physics_process(false)
	EventBus.palette_changed.connect(_on_palette_changed)


## Binds the ring to its boss (call before `start()`).
func setup(owner_boss: BossBase) -> void:
	boss = owner_boss


## Lights the ring around `center`/`radius`: telegraph first, flames after `telegraph_time`.
func start(center: Vector2, radius: float) -> void:
	if active or boss == null:
		return
	active = true
	armed = false
	_radius = maxf(24.0, radius)
	global_position = center
	_telegraph_left = telegraph_time
	_build_segments()
	_layout()
	boss.telegraph_arc(center, _radius, 0.0, TAU, telegraph_time, flame_radius)
	set_physics_process(true)


## Puts the fire out and frees its segments.
func stop() -> void:
	active = false
	armed = false
	set_physics_process(false)
	for hitbox: Hitbox in _hitboxes:
		if is_instance_valid(hitbox):
			hitbox.deactivate()
			hitbox.queue_free()
	for flame: Polygon2D in _flames:
		if is_instance_valid(flame):
			flame.queue_free()
	_hitboxes.clear()
	_flames.clear()


## Live fire segments (tests/debug).
func segment_count() -> int:
	return _hitboxes.size()


## World position of the centre of the current gap.
func gap_position() -> Vector2:
	var mid := _angle + TAU * (float(gap_slots) * 0.5 - 0.5) / float(segments)
	return global_position + Vector2.from_angle(mid) * _radius


func _build_segments() -> void:
	for slot in range(gap_slots, segments):
		var hitbox := Hitbox.new()
		hitbox.name = "Flame%d" % slot
		hitbox.team = boss.team
		hitbox.source = boss
		hitbox.multi_hit_interval = rehit_interval
		hitbox.damage_builder = Callable(self, "build_fire_damage")
		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = flame_radius
		col.shape = circle
		hitbox.add_child(col)
		add_child(hitbox)
		hitbox.collision_mask = Layers.hitbox_mask_for(boss.team)
		_hitboxes.append(hitbox)
		var flame := Polygon2D.new()
		flame.polygon = _flame_shape()
		flame.color = _flame_color()
		flame.modulate = Color(1.0, 1.0, 1.0, TELEGRAPH_ALPHA)
		add_child(flame)
		_flames.append(flame)


func _flame_shape() -> PackedVector2Array:
	var r := flame_radius
	return PackedVector2Array(
		[
			Vector2(0.0, -r * 1.6),
			Vector2(r * 0.7, -r * 0.2),
			Vector2(r * 0.45, r * 0.8),
			Vector2(-r * 0.45, r * 0.8),
			Vector2(-r * 0.7, -r * 0.2),
		]
	)


func _flame_color() -> Color:
	if Desktop.palette == null:
		return Color(1.0, 0.5, 0.15)
	return Desktop.palette.get_color(&"heat").lerp(Desktop.palette.get_color(&"danger"), 0.35)


func _layout() -> void:
	for i in range(_hitboxes.size()):
		var angle := _angle + TAU * float(i + gap_slots) / float(segments)
		var offset := Vector2.from_angle(angle) * _radius
		_hitboxes[i].position = offset
		_flames[i].position = offset


func _physics_process(delta: float) -> void:
	if not active:
		return
	if not armed:
		_telegraph_left -= delta
		if _telegraph_left <= 0.0:
			_arm()
	_angle = fmod(_angle + spin_speed * delta, TAU)
	_layout()
	if armed:
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
		for flame: Polygon2D in _flames:
			flame.modulate.a = FLAME_ALPHA * pulse


func _arm() -> void:
	armed = true
	for hitbox: Hitbox in _hitboxes:
		hitbox.activate(0.0)
	if has_node("/root/Audio"):
		Audio.play(&"trap_fire", global_position)


## Fire damage with a burn, built through the boss so its stats and crit apply.
func build_fire_damage(target: Node2D) -> DamageInfo:
	var dir := target.global_position - global_position
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	var info := boss.make_damage(damage, TAGS, dir.normalized(), 60.0, boss.rng)
	info.with_status(StatusEffect.make(StatusEffect.Kind.BURN, burn_duration, damage * 0.25, boss))
	return info


func _on_palette_changed(_palette: ThemePalette) -> void:
	if _flames.is_empty():
		return
	if _retint != null:
		_retint.kill()
	_retint = create_tween().set_parallel(true)
	for flame: Polygon2D in _flames:
		_retint.tween_property(flame, "color", _flame_color(), RETINT_TIME)
