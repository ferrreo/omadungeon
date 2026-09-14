## Bodyguard hireling summoned by Contract: a PLAYER-team Entity that shadows its leader and
## melee-attacks the nearest enemy, expiring after `lifetime` seconds. Drawn procedurally in
## theme colours and retinted on palette change.
class_name Hireling
extends Entity

var leader: Entity
var attack_damage: float = 8.0
var lifetime: float = 20.0
var move_speed: float = 95.0
var follow_distance: float = 22.0
var aggro_range: float = 110.0
var attack_range: float = 18.0
var attack_interval: float = 0.8
var attack_knockback: float = 60.0
## Combat RNG for crit rolls; ContractAbility assigns the AbilitySlots stream so a fixed run
## seed produces a fixed fight (docs §1).
var rng := RandomNumberGenerator.new()
var _time_left: float = 20.0
var _attack_left: float = 0.4
var _hitbox: Hitbox
var _max_hp: float = 40.0
var _body_color: Color = Color.WHITE
var _accent_color: Color = Color.WHITE
var _retint: Callable


func _init() -> void:
	team = Layers.Team.PLAYER
	hurtbox_size = Vector2(10, 12)


func setup(from: Entity, hp: float, dmg: float, seconds: float) -> Hireling:
	leader = from
	_max_hp = maxf(1.0, hp)
	attack_damage = dmg
	lifetime = seconds
	_time_left = seconds
	return self


func _ready() -> void:
	stats.set_base(&"max_hp", _max_hp)
	stats.set_base(&"move_speed", move_speed)
	super()
	add_to_group(&"hireling")
	var body := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 10)
	body.shape = rect
	add_child(body)
	_hitbox = Hitbox.new()
	_hitbox.name = "Hitbox"
	_hitbox.team = team
	_hitbox.source = self
	_hitbox.tags = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
	_hitbox.knockback = attack_knockback
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = attack_range
	shape.shape = circle
	_hitbox.add_child(shape)
	# Hireling hits are player hits: credit the leader so Vampiric/Hotkey/on_kill fire.
	_hitbox.hit_dealt.connect(AbilityUtil.report_hit)
	_hitbox.damage_builder = func(target: Node2D) -> DamageInfo:
		return make_damage(
			attack_damage,
			_hitbox.tags,
			target.global_position - global_position,
			attack_knockback,
			rng
		)
	add_child(_hitbox)
	_body_color = AbilityFx.color(&"accent")
	_accent_color = AbilityFx.color(&"loot")
	_retint = _on_palette_changed
	EventBus.palette_changed.connect(_retint)
	# Vector2.ONE is the resting scale: a squash during the spawn-in tween must return there.
	set_meta(AbilityFx.META_BASE_SCALE, Vector2.ONE)
	scale = Vector2(0.3, 0.3)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25)


func _exit_tree() -> void:
	if EventBus.palette_changed.is_connected(_retint):
		EventBus.palette_changed.disconnect(_retint)


func time_left() -> float:
	return _time_left


func _on_palette_changed(palette: ThemePalette) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_method(
		_set_body_color, _body_color, palette.get_color(&"accent"), AbilityFx.RETINT_TIME
	)
	tween.tween_method(
		_set_accent_color, _accent_color, palette.get_color(&"loot"), AbilityFx.RETINT_TIME
	)


func _set_body_color(c: Color) -> void:
	_body_color = c
	queue_redraw()


func _set_accent_color(c: Color) -> void:
	_accent_color = c
	queue_redraw()


func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		_expire()
		return
	if not can_act():
		velocity = Vector2.ZERO
		move_with_knockback(delta)
		return
	_attack_left -= delta
	var desired := Vector2.ZERO
	var target := AbilityUtil.nearest_enemy(get_tree(), global_position, aggro_range)
	if target != null:
		var to := target.global_position - global_position
		var dist := to.length()
		if dist > 0.01:
			facing = to / dist
		if dist > attack_range * 0.8:
			desired = facing
		if dist <= attack_range + 4.0 and _attack_left <= 0.0:
			_attack()
	elif is_instance_valid(leader):
		var to := leader.global_position - global_position
		if to.length() > follow_distance:
			facing = to.normalized()
			desired = facing
	velocity = desired * effective_speed()
	move_with_knockback(delta)
	queue_redraw()


func _attack() -> void:
	_attack_left = attack_interval
	_hitbox.position = facing * 6.0
	_hitbox.activate(0.15)
	AbilityFx.squash(self, 0.25, 0.15)


func _die(_killer: Node2D) -> void:
	if is_inside_tree():
		AbilityFx.burst(AbilityUtil.world_of(self), global_position, &"accent", 14, 12.0)
	queue_free()


func _expire() -> void:
	if is_dying:
		return
	is_dying = true
	if is_inside_tree():
		AbilityFx.burst(AbilityUtil.world_of(self), global_position, &"text_dim", 10, 10.0)
	queue_free()


func _draw() -> void:
	var blink := 1.0 if _time_left > 3.0 or fmod(_time_left, 0.4) < 0.2 else 0.5
	var col := _body_color * Color(1, 1, 1, blink)
	draw_rect(Rect2(-4, -2, 8, 8), col)
	draw_rect(Rect2(-3, -7, 6, 5), col.lightened(0.35))
	draw_rect(Rect2(-1, -1, 2, 5), _accent_color * Color(1, 1, 1, blink))
	var eye := Vector2(1.0 if facing.x >= 0.0 else -2.0, -5.0)
	draw_rect(Rect2(eye, Vector2(1, 1)), col.darkened(0.6))
