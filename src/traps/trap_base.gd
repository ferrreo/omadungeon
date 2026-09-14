## Base for every trap and hazard (docs §9). Runs the telegraph -> active -> cooldown cycle,
## owns a neutral Hitbox that hits both teams (minus immunities), a frame-strip sprite from
## `assets/sprites/traps/<kind>.png` and a pulsing danger-coloured tell. Subclasses override the
## `_on_*` hooks and `_build_damage` for custom behaviour.
class_name TrapBase
extends Node2D

## Emitted when the tell starts.
signal telegraph_started(trap: TrapBase)
## Emitted when the trap becomes dangerous.
signal triggered(trap: TrapBase)
## Emitted when the active window ends.
signal deactivated(trap: TrapBase)
## Emitted whenever damage actually landed on a hurtbox.
signal hit_landed(trap: TrapBase, target: Node2D, info: DamageInfo)
signal state_changed(state: State)

enum State { IDLE, TELEGRAPH, ACTIVE, COOLDOWN }

const SPRITE_DIR := "res://assets/sprites/traps/"
const FRAME_IDLE := 0
const FRAME_TELEGRAPH := 1
const FRAME_ACTIVE := 2
const PALETTE_TWEEN := 0.6
const TELL_PULSE_HZ := 7.0
## Sprite frame flicker during the telegraph (kept well under photosensitivity range).
const TELL_FLICKER_HZ := 5.0
const GROUP_TRAP := &"trap"
## Group prefix shared by every trap configured with a `room_id` (see `room_group`).
const ROOM_GROUP_PREFIX := "room_%d_traps"

@export var kind: StringName = &"spike_floor"
@export var def: TrapDef
@export var damage: float = 15.0
@export var knockback: float = 40.0
@export var telegraph_time: float = 0.5
@export var active_time: float = 0.4
@export var cooldown_time: float = 2.0
## Enemy hurtboxes are never hit (Tinkerer traps).
@export var enemies_immune: bool = false
## Re-arm automatically after the cooldown (arrow walls, lasers, vents).
@export var auto_cycle: bool = false
## Trigger when a body on `trigger_mask` enters the tile.
@export var proximity_trigger: bool = false
@export_flags_2d_physics var trigger_mask: int = Layers.PLAYER | Layers.ENEMY
## When >= 0 the trap only cycles while the player is in this room (EventBus.room_entered).
@export var room_id: int = -1
## Hitbox tags; TAG_TRAP is always present.
@export var tags: Array[StringName] = [DamageInfo.TAG_TRAP, DamageInfo.TAG_PHYSICAL]
## 0 = hit each target once per activation; > 0 re-hits every N seconds (zones).
@export var multi_hit_interval: float = 0.0
@export var hitbox_size: Vector2 = Vector2(14.0, 14.0)
## Runtime hazards: seconds before the trap removes itself (0 = never).
@export var lifetime: float = 0.0
## Remove the node after the first full cycle (one-shot hazards).
@export var one_shot: bool = false
## Start the cycle as soon as the trap enters the tree (spawned hazards).
@export var trigger_on_spawn: bool = false
@export var enabled: bool = true
## Pressure plates may fire/toggle this trap through `on_plate_pressed`.
@export var plate_controlled: bool = true
## Status effects attached to every hit.
@export var statuses: Array[StatusEffect] = []

var state: State = State.IDLE
var hitbox: Hitbox
var sprite: Sprite2D
var tell: Polygon2D
var particles: CPUParticles2D
var trigger_area: Area2D
## Total time spent in the current state.
var state_time: float = 0.0
## Room-gated traps (room_id >= 0) only cycle once EventBus.room_entered names their room.
var _player_present: bool = true
var _danger: Color = Color(0.9, 0.3, 0.3)
var _age: float = 0.0
var _cycles: int = 0
var _pending_trigger: bool = false
var _def_applied: bool = false
## Single tween used for palette crossfades (restarted, never stacked).
var _tint_tween: Tween


func _ready() -> void:
	add_to_group(GROUP_TRAP)
	if def != null and not _def_applied:
		apply_def(def)
	_player_present = room_id < 0
	_danger = _palette_color(&"danger")
	_build_visuals()
	if _uses_hitbox():
		_build_hitbox()
	if proximity_trigger:
		_build_trigger_area()
	EventBus.palette_changed.connect(_on_palette_changed)
	EventBus.room_entered.connect(_on_room_entered)
	_on_setup()
	_set_state(State.IDLE)
	if auto_cycle or trigger_on_spawn:
		_pending_trigger = true


## Copies the numbers from a TrapDef onto this node.
func apply_def(trap_def: TrapDef) -> void:
	_def_applied = true
	def = trap_def
	kind = trap_def.id
	damage = trap_def.damage
	knockback = trap_def.knockback
	telegraph_time = trap_def.telegraph_time
	active_time = trap_def.active_time
	cooldown_time = trap_def.cooldown_time
	enemies_immune = trap_def.enemies_immune
	if trap_def.duration > 0.0 and lifetime <= 0.0:
		lifetime = trap_def.duration


## Applies spawn-time options (from TrapRegistry.instantiate `extra`). Subclasses extend.
func configure(extra: Dictionary) -> void:
	if extra.has("duration"):
		lifetime = float(extra["duration"])
	if extra.has("enemies_immune"):
		enemies_immune = bool(extra["enemies_immune"])
	if extra.has("room_id"):
		room_id = int(extra["room_id"])
		if room_id >= 0:
			add_to_group(room_group(room_id))
	if extra.has("damage"):
		damage = float(extra["damage"])
	if extra.has("enabled"):
		enabled = bool(extra["enabled"])
	if extra.has("proximity_trigger"):
		proximity_trigger = bool(extra["proximity_trigger"])
	if extra.has("plate_controlled"):
		plate_controlled = bool(extra["plate_controlled"])


## Group every trap of room `id` joins when configured with `room_id`; pressure plates without an
## explicit `linked_group` control this group.
static func room_group(id: int) -> StringName:
	return StringName(ROOM_GROUP_PREFIX % id)


## Starts the telegraph if the trap is idle and enabled. Returns true when it started.
func trigger() -> bool:
	if not enabled or state != State.IDLE:
		return false
	if not is_inside_tree():
		_pending_trigger = true
		return true
	_set_state(State.TELEGRAPH)
	return true


## Enables/disables the trap. Disabling mid-cycle ends it immediately (emitting `deactivated`
## when it was dangerous so FX listeners can stop looping effects).
func set_enabled(value: bool) -> void:
	enabled = value
	if not value and state != State.IDLE:
		var was_active := state == State.ACTIVE
		_deactivate_hitbox()
		_set_state(State.IDLE)
		if was_active:
			deactivated.emit(self)
	elif value and state == State.IDLE:
		if auto_cycle:
			_pending_trigger = true
		_rearm_if_occupied()


## Pressure-plate hook: cycling traps toggle, one-shot traps fire. Ignored when
## `plate_controlled` is false (pits, ice, plates, mimics).
func on_plate_pressed(_plate_id: StringName, pressed: bool) -> void:
	if not pressed or not plate_controlled:
		return
	if auto_cycle:
		set_enabled(not enabled)
	else:
		trigger()


## True while the trap can hurt something.
func is_dangerous() -> bool:
	return state == State.ACTIVE


func is_telegraphing() -> bool:
	return state == State.TELEGRAPH


func _physics_process(delta: float) -> void:
	_age += delta
	if lifetime > 0.0 and _age >= lifetime and state != State.ACTIVE:
		_expire()
		return
	if _pending_trigger and state == State.IDLE and enabled and _player_present:
		_pending_trigger = false
		_set_state(State.TELEGRAPH)
	state_time += delta
	match state:
		State.TELEGRAPH:
			_update_tell(delta)
			if state_time >= telegraph_time:
				_set_state(State.ACTIVE)
		State.ACTIVE:
			_on_active_process(delta)
			# A non-positive active window means "dangerous for one frame", never "forever".
			if active_time <= 0.0 or state_time >= active_time:
				_set_state(State.COOLDOWN)
		State.COOLDOWN:
			if state_time >= cooldown_time:
				_set_state(State.IDLE)
				if one_shot:
					_expire()
				elif auto_cycle:
					_pending_trigger = true
		_:
			_on_idle_process(delta)


func _set_state(new_state: State) -> void:
	var previous := state
	state = new_state
	state_time = 0.0
	match new_state:
		State.IDLE:
			_set_frame(FRAME_IDLE)
			_set_tell_alpha(0.0)
			_on_idle()
			_rearm_if_occupied()
		State.TELEGRAPH:
			_set_frame(FRAME_TELEGRAPH)
			_on_telegraph()
			telegraph_started.emit(self)
		State.ACTIVE:
			_set_frame(FRAME_ACTIVE)
			_set_tell_alpha(0.55)
			_cycles += 1
			_activate_hitbox()
			_punch_sprite()
			_on_trigger()
			triggered.emit(self)
			EventBus.trap_triggered.emit(self)
		State.COOLDOWN:
			_deactivate_hitbox()
			_set_frame(FRAME_IDLE)
			_set_tell_alpha(0.0)
			_on_cooldown()
			if previous == State.ACTIVE:
				deactivated.emit(self)
	state_changed.emit(new_state)


# --- hooks for subclasses -----------------------------------------------------------------


## Called at the end of _ready, after visuals/hitbox exist.
func _on_setup() -> void:
	pass


func _on_idle() -> void:
	pass


func _on_idle_process(_delta: float) -> void:
	pass


func _on_telegraph() -> void:
	pass


func _on_trigger() -> void:
	pass


func _on_active_process(_delta: float) -> void:
	pass


func _on_cooldown() -> void:
	pass


## Whether this trap deals damage through the shared Hitbox (pits/plates/ice do not).
func _uses_hitbox() -> bool:
	return true


## Colour of the tell overlay at pulse phase `t` (0..1).
func _tell_color(t: float) -> Color:
	var c := _danger
	c.a = lerpf(0.15, 0.5, t)
	return c


# --- damage ------------------------------------------------------------------------------


## Builds the DamageInfo for `target` (a Hurtbox or prop body). Zero damage = skipped.
func _build_damage(target: Node2D) -> DamageInfo:
	var entity := _entity_of(target)
	if entity != null and not can_hurt(entity):
		return DamageInfo.create(0.0, tags, self, Layers.Team.NEUTRAL)
	var all_tags: Array[StringName] = tags.duplicate()
	if not all_tags.has(DamageInfo.TAG_TRAP):
		all_tags.append(DamageInfo.TAG_TRAP)
	var info := DamageInfo.create(damage, all_tags, self, Layers.Team.NEUTRAL)
	var dir := target.global_position - global_position
	if dir.length_squared() < 0.001:
		dir = Vector2.DOWN
	info.with_knockback(dir, knockback)
	for s: StatusEffect in statuses:
		info.with_status(s)
	return info


## Immunity rules: `enemies_immune`, Tinkerer faction, and the player's `is_trap_immune()`
## (Ranger sure-footed dodge). Enemies never get blanket immunity from `is_trap_immune()`:
## EnemyBase uses that method for pit avoidance only, which `Pit._can_fall` handles itself.
func can_hurt(entity: Node) -> bool:
	var team_value: Variant = entity.get("team")
	var is_enemy := team_value is int and int(team_value) == Layers.Team.ENEMY
	if is_enemy:
		if enemies_immune:
			return false
		if _is_tinkerer(entity):
			return false
		return true
	if entity.has_method("is_trap_immune") and bool(entity.call("is_trap_immune")):
		return false
	return true


static func _is_tinkerer(entity: Node) -> bool:
	var faction: Variant = entity.get("faction")
	if faction is int and int(faction) == EnemyDef.Faction.TINKERERS:
		return true
	var enemy_def: Variant = entity.get("def")
	if enemy_def is EnemyDef and (enemy_def as EnemyDef).faction == EnemyDef.Faction.TINKERERS:
		return true
	return false


static func _entity_of(target: Node) -> Node:
	if target is Hurtbox:
		var hb := target as Hurtbox
		return hb.entity if hb.entity != null else hb.get_parent()
	return target


func _on_hit_dealt(target: Hurtbox, info: DamageInfo) -> void:
	hit_landed.emit(self, target, info)
	_spawn_hit_particles(target.global_position)


# --- construction ------------------------------------------------------------------------


func _build_hitbox() -> void:
	hitbox = get_node_or_null("Hitbox") as Hitbox
	if hitbox == null:
		hitbox = Hitbox.new()
		hitbox.name = "Hitbox"
		var shape := CollisionShape2D.new()
		shape.name = "Shape"
		var rect := RectangleShape2D.new()
		rect.size = hitbox_size
		shape.shape = rect
		hitbox.add_child(shape)
		add_child(hitbox)
	hitbox.team = Layers.Team.NEUTRAL
	hitbox.source = self
	hitbox.damage = damage
	hitbox.knockback = knockback
	hitbox.tags = tags
	hitbox.multi_hit_interval = multi_hit_interval
	hitbox.damage_builder = _build_damage
	hitbox.collision_mask = Layers.PLAYER_HURTBOX | Layers.ENEMY_HURTBOX
	hitbox.hit_dealt.connect(_on_hit_dealt)


func _activate_hitbox() -> void:
	if hitbox != null:
		hitbox.collision_mask = Layers.PLAYER_HURTBOX | Layers.ENEMY_HURTBOX
		hitbox.activate(active_time)


func _deactivate_hitbox() -> void:
	if hitbox != null:
		hitbox.deactivate()


func _build_trigger_area() -> void:
	trigger_area = Area2D.new()
	trigger_area.name = "Trigger"
	trigger_area.collision_layer = Layers.TRAP
	trigger_area.collision_mask = trigger_mask
	trigger_area.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = hitbox_size
	shape.shape = rect
	trigger_area.add_child(shape)
	add_child(trigger_area)
	trigger_area.body_entered.connect(_on_trigger_body_entered)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _can_trigger(body):
		trigger()


## Bodies the proximity trigger reacts to: anything the trap could actually hurt.
func _can_trigger(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var team_value: Variant = body.get("team")
	if team_value is int and int(team_value) == Layers.Team.ENEMY:
		if enemies_immune or _is_tinkerer(body):
			return false
	return true


## Proximity traps keep cycling while something stands on them: re-arm when a body is still
## overlapping after the cooldown (body_entered only fires once).
func _rearm_if_occupied() -> void:
	if not proximity_trigger or trigger_area == null or not enabled:
		return
	for body: Node2D in trigger_area.get_overlapping_bodies():
		if _can_trigger(body):
			_pending_trigger = true
			return


func _build_visuals() -> void:
	tell = Polygon2D.new()
	tell.name = "Tell"
	_rebuild_tell()
	tell.color = _tell_color(0.0)
	tell.color.a = 0.0
	# Added before the sprite so it draws under the trap art but above the floor tilemaps
	# (which share z 0); a negative z_index would hide it under the ground layer.
	add_child(tell)
	sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
	sprite.texture = load_sprite(kind)
	# A hazard keeps its own colours and its warning frame whatever the room's light: on
	# `TELL_MASK`, which no light - the lighting layer's darkness included - reaches (docs 10.2).
	sprite.light_mask = LightRig.TELL_MASK
	tell.light_mask = LightRig.TELL_MASK
	sprite.hframes = frame_count(sprite.texture)
	sprite.frame = FRAME_IDLE
	particles = CPUParticles2D.new()
	particles.name = "Particles"
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 10
	particles.lifetime = 0.35
	particles.direction = Vector2.UP
	particles.spread = 60.0
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 70.0
	particles.gravity = Vector2(0.0, 160.0)
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.0
	particles.color = _danger
	add_child(particles)


## Sizes the tell polygon from `hitbox_size`. Subclasses that change `hitbox_size` in
## `_on_setup` (oversized pits/ice regions) call this again afterwards.
func _rebuild_tell() -> void:
	if tell == null:
		return
	var half := hitbox_size * 0.5 + Vector2.ONE
	tell.polygon = PackedVector2Array(
		[Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]
	)


## Loads the frame strip for `sprite_kind`; falls back to a generated placeholder.
static func load_sprite(sprite_kind: StringName) -> Texture2D:
	var path := SPRITE_DIR + String(sprite_kind) + ".png"
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	var image := Image.create(48, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.55, 1.0))
	return ImageTexture.create_from_image(image)


## Frame strips are square frames laid out horizontally.
static func frame_count(texture: Texture2D) -> int:
	if texture == null or texture.get_height() <= 0:
		return 1
	return maxi(1, int(texture.get_width() / texture.get_height()))


func _set_frame(frame: int) -> void:
	if sprite != null:
		sprite.frame = clampi(frame, 0, maxi(0, sprite.hframes * sprite.vframes - 1))


func _set_tell_alpha(alpha: float) -> void:
	if tell != null:
		var c := _tell_color(1.0)
		c.a = alpha
		tell.color = c


func _update_tell(delta: float) -> void:
	if tell == null:
		return
	var t := 0.5 + 0.5 * sin(state_time * TAU * TELL_PULSE_HZ)
	# Pulse faster and brighter as the trigger approaches.
	var urgency := clampf(state_time / maxf(telegraph_time, 0.01), 0.0, 1.0)
	var c := _tell_color(lerpf(t, 1.0, urgency * 0.5))
	tell.color = c
	tell.scale = Vector2.ONE * (1.0 + 0.04 * t)
	if sprite != null and sprite.hframes > FRAME_TELEGRAPH:
		var flicker := int(state_time * TELL_FLICKER_HZ) % 2 == 0
		sprite.frame = FRAME_TELEGRAPH if flicker or urgency > 0.75 else FRAME_IDLE
	_on_telegraph_process(delta)


func _on_telegraph_process(_delta: float) -> void:
	pass


## Squash/stretch on trigger.
func _punch_sprite() -> void:
	if sprite == null or not is_inside_tree():
		return
	sprite.scale = Vector2(1.35, 0.7)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.18)
	if particles != null:
		particles.restart()
		particles.emitting = true


## Burst of particles toward `at` (the victim) so hits read as directional.
func _spawn_hit_particles(at: Vector2) -> void:
	if particles == null:
		return
	var dir := at - global_position
	particles.direction = dir.normalized() if dir.length_squared() > 1.0 else Vector2.UP
	particles.restart()
	particles.emitting = true


func _palette_color(role: StringName) -> Color:
	var palette: ThemePalette = Desktop.palette
	if palette == null:
		return _danger
	return palette.get_color(role)


func _on_palette_changed(palette: ThemePalette) -> void:
	var target := palette.get_color(&"danger")
	if not is_inside_tree():
		_danger = target
		return
	var tween := start_tint_tween()
	tween.tween_method(_set_danger, _danger, target, PALETTE_TWEEN)


## Kills the running palette crossfade and starts a fresh (parallel) one, so rapid theme
## changes never stack tweens fighting over the same colours. Subclasses add their own
## `tween_method` calls to the returned tween.
func start_tint_tween() -> Tween:
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	_tint_tween = create_tween()
	_tint_tween.set_parallel(true)
	return _tint_tween


func _set_danger(c: Color) -> void:
	_danger = c
	if particles != null:
		particles.color = c
	if state == State.ACTIVE:
		_set_tell_alpha(0.55)


func _on_room_entered(entered_room: int) -> void:
	if room_id < 0:
		return
	_player_present = entered_room == room_id
	if not _player_present and state == State.TELEGRAPH:
		_set_state(State.IDLE)
		_pending_trigger = auto_cycle


func _expire() -> void:
	_deactivate_hitbox()
	_on_expire()
	queue_free()


## Called just before a hazard removes itself.
func _on_expire() -> void:
	pass


## Number of completed activations (tests/telemetry).
func cycles() -> int:
	return _cycles
