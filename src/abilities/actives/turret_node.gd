## Deployable turret that shoots player-credited projectiles at the nearest enemy until it
## expires. Drawn procedurally in theme colours (retints on palette change).
class_name TurretNode
extends Node2D

var owner_entity: Entity
var ability: ActiveAbility
var lifetime: float = 10.0
var fire_interval: float = 0.5
var range_px: float = 140.0
var projectile_speed: float = 220.0
var knockback: float = 40.0
var _time_left: float = 10.0
var _fire_left: float = 0.3
var _barrel_angle: float = 0.0
var _body_color: Color = Color.WHITE
var _accent_color: Color = Color.WHITE
var _retint: Callable


func setup(from: Entity, source_ability: ActiveAbility, duration: float) -> TurretNode:
	owner_entity = from
	ability = source_ability
	lifetime = duration
	_time_left = duration
	return self


func _ready() -> void:
	add_to_group(&"turret")
	_body_color = AbilityFx.color(&"wall_top")
	_accent_color = AbilityFx.color(&"accent")
	_retint = _on_palette_changed
	EventBus.palette_changed.connect(_retint)
	scale = Vector2(0.2, 0.2)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25)


func _exit_tree() -> void:
	if EventBus.palette_changed.is_connected(_retint):
		EventBus.palette_changed.disconnect(_retint)


func _on_palette_changed(palette: ThemePalette) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_method(
		_set_body_color, _body_color, palette.get_color(&"wall_top"), AbilityFx.RETINT_TIME
	)
	tween.tween_method(
		_set_accent_color, _accent_color, palette.get_color(&"accent"), AbilityFx.RETINT_TIME
	)


func _set_body_color(c: Color) -> void:
	_body_color = c
	queue_redraw()


func _set_accent_color(c: Color) -> void:
	_accent_color = c
	queue_redraw()


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		_expire()
		return
	var target := AbilityUtil.nearest_enemy(get_tree(), global_position, range_px)
	if target != null:
		var wanted := (target.global_position - global_position).angle()
		_barrel_angle = rotate_toward(_barrel_angle, wanted, 12.0 * delta)
	_fire_left -= delta
	if _fire_left <= 0.0:
		_fire_left = fire_interval
		if target != null and is_instance_valid(owner_entity):
			fire_at(target)
	queue_redraw()


## Fires one projectile toward `target`.
func fire_at(target: Node2D) -> void:
	var dir := (target.global_position - global_position).normalized()
	var projectile := AbilityUtil.spawn_projectile(
		owner_entity,
		ability,
		get_parent(),
		global_position + dir * 6.0,
		dir,
		projectile_speed,
		range_px / projectile_speed + 0.1,
		ability.tags,
		knockback
	)
	if projectile == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = AbilityFx.bar_texture(5, 2)
	AbilityFx.bind_palette(sprite, &"accent")
	projectile.add_child(sprite)
	AbilityFx.squash(self, 0.15, 0.12)


func _expire() -> void:
	AbilityFx.burst(get_parent(), global_position, &"wall_top", 12, 10.0)
	queue_free()


func _draw() -> void:
	var blink := 1.0 if _time_left > 2.0 or fmod(_time_left, 0.3) < 0.15 else 0.4
	draw_rect(Rect2(-5, -3, 10, 7), _body_color)
	draw_rect(Rect2(-6, 4, 12, 2), _body_color.darkened(0.3))
	var barrel := Vector2.from_angle(_barrel_angle) * 7.0
	draw_line(Vector2.ZERO, barrel, _accent_color * Color(1, 1, 1, blink), 2.0)
	draw_circle(Vector2.ZERO, 2.0, _accent_color * Color(1, 1, 1, blink))
