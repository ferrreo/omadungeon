## The player character (docs §4, §6): twin-stick movement with acceleration/friction, class
## dodge styles, weapon controller, potion, gold, stat orbs, shield, hurt feedback and death.
## Scene: `res://src/player/player.tscn`, which also carries the AbilitySlots child. RunManager
## sets `rng` and calls `apply_class`; `equipment` and `ability_slots` provision themselves.
class_name Player
extends Entity

## Local mirrors of the EventBus signals for nodes that already hold a Player reference.
signal interact_pressed
signal active_pressed(index: int, aim: Vector2)
signal dodge_started(style: ClassDef.DodgeStyle)
signal dodge_finished
## HP actually restored by a potion. The HUD floats it over the player: without that, the
## only feedback for spending the run's single heal was the HP bar moving.
signal potion_used(amount: float)
signal potions_changed(count: int, max_count: int)
signal shield_changed(amount: float)
signal gold_changed(total: int, delta: int)
signal weapon_hit(target: Node2D, info: DamageInfo)
signal class_applied(def: ClassDef)

enum State { NORMAL, DODGE_STARTUP, DODGING, DEAD }

const ACCELERATION := 1100.0
const FRICTION := 1300.0
const SLIPPERY_FACTOR := 0.12
const DODGE_COOLDOWN := 0.6
const HIT_INVULN_TIME := 0.5
const POTION_HEAL_FRACTION := 0.4
const ROLL_TIME := 0.25
const ROLL_DISTANCE := 40.0
const DASH_TIME := 0.3
const DASH_DISTANCE := 84.0
const BLINK_STARTUP := 0.15
const BLINK_DISTANCE := 3.0 * Layers.TILE
const BLINK_IFRAMES := 0.2
const BLINK_LANDING := 0.06
const HOP_TIME := 0.18
const HOP_DISTANCE := 32.0
## Ranger dash caltrops (docs §4.3: "long dash, no i-frames but leaves a caltrop patch").
## Caltrops are player-team Hitboxes dropped along the dash path; enemies that stand on one
## are re-hit every CALTROP_REHIT seconds until it expires.
const CALTROP_COUNT := 3
const CALTROP_DAMAGE := 7.0
const CALTROP_RADIUS := 6.0
const CALTROP_LIFETIME := 5.0
const CALTROP_REHIT := 0.7
const CALTROP_KNOCKBACK := 20.0
## Fraction of the dash length the patch starts at, so caltrops land behind the player.
const CALTROP_START := 0.15
## Group every dropped caltrop joins, so the floor (and tests) can find the live patch.
const CALTROP_GROUP := &"caltrop"
const CALTROP_SHEET := "res://assets/sprites/projectiles.png"
## Column of the caltrop cell in the 16x16 projectile sheet.
const CALTROP_FRAME := 11
const HURT_ANIM_TIME := 0.2
const DEATH_ANIM_TIME := 0.75
const FRAME := 16
const SHEET_COLS := 6
## Row layout of the class sheet: name, frame count, fps, loops.
const SHEET_ROWS: Array[Array] = [
	[&"idle", 4, 6.0, true],
	[&"run", 6, 12.0, true],
	[&"dodge", 4, 16.0, false],
	[&"hurt", 2, 10.0, false],
	[&"death", 6, 8.0, false],
]
const FLASH_SHADER := "res://src/player/flash.gdshader"
## Ceiling on the hurt flash. The shader mixes the sprite toward `flash_color`, and at 1.0 the
## player became a flat silhouette of that colour - which, in a scrum where every enemy is
## also flashing, is exactly the frame in which a tester cannot find themselves. Low enough
## that the class colours still dominate: the flash tints the player rather than replacing
## them, and does not read as one more of the danger-coloured telegraphs on the floor.
const FLASH_MAX := 0.35
## Alpha of the dark rim stamped around the player sprite.
const OUTLINE_ALPHA := 0.85
const DECOY_SCRIPT := "res://src/player/decoy.gd"
## Optional sibling modules, loaded by path so the player module keeps no hard dependency.
const ABILITY_SLOTS_SCRIPT := "res://src/abilities/ability_slots.gd"
const EQUIPMENT_SCRIPT := "res://src/items/equipment.gd"
## Seconds between gamepad auto-aim target refreshes (one physics query each).
const AUTO_AIM_INTERVAL := 0.1
## Step used when walking a blink destination back out of geometry.
const BLINK_STEP_BACK := 4.0

## Optional: class applied automatically on ready (RunManager normally calls `apply_class`).
@export var class_def: ClassDef

var class_id: StringName = &""
var dodge_style: ClassDef.DodgeStyle = ClassDef.DodgeStyle.ROLL
var gold: int = 0
var potions: int = 1
var max_potions: int = 1
## Free-form behaviour flags set by passives/items (projectile_bounces, chest_extra_option,
## gold_drop_bonus, trap_immune_dodge, chest_costs_gold, free_reroll_per_floor, ...).
var flags: Dictionary = {}
## Combat RNG stream (RunManager assigns `RunRng.stream(&"combat")`). Seeded by default.
## Assigning it also seeds the Health dodge roll and the AbilitySlots crit roll.
var rng: RandomNumberGenerator = RandomNumberGenerator.new():
	set(value):
		rng = value if value != null else RandomNumberGenerator.new()
		_propagate_rng()
## Items module's Equipment (duck-typed: `equip(item)`, `to_dict()`, `from_dict(...)`).
## Created automatically when the items module is present, so callers can rely on it.
var equipment: RefCounted
## Abilities module's AbilitySlots node (the child named AbilitySlots, created if missing).
var ability_slots: Node
var input: PlayerInput
var weapon_pivot: Node2D
var weapon_controller: WeaponController
var sprite: AnimatedSprite2D
## "You are here": the ground ring, and the rim that keeps the player's edge through a flash.
var marker: PlayerMarker
var outline: SpriteOutline
var light: PointLight2D
var dodge_dust: CPUParticles2D
## Which way the character is turned, and whether the weapon draws in front of them or behind.
## Read it (`carry.flipped`, `carry.behind`); `refresh_carry` is what writes it.
var carry := WeaponCarry.new()
var state: State = State.NORMAL
var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if input != null:
			input.enabled = value

var _aim: Vector2 = Vector2.RIGHT
var _dodge_dir: Vector2 = Vector2.RIGHT
var _dodge_velocity: Vector2 = Vector2.ZERO
var _dodge_time_left: float = 0.0
var _dodge_cooldown_left: float = 0.0
var _iframes_left: float = 0.0
var _hit_invuln_left: float = 0.0
var _hurt_anim_left: float = 0.0
var _slippery: bool = false
var _shield_expire_left: float = 0.0
var _flash_material: ShaderMaterial
var _flash_tween: Tween
var _squash_tween: Tween
var _light_tween: Tween
var _pending_class: ClassDef
var _auto_aim_timer: float = 0.0
var _feel: GameFeel
var _fx: FxPool


func _init() -> void:
	team = Layers.Team.PLAYER
	rng.seed = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func _ready() -> void:
	super._ready()
	add_to_group(&"player")
	_feel = GameFeel.instance(get_tree())
	_fx = FxPool.instance(get_tree())
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_setup_children()
	health.damaged.connect(_on_player_damaged)
	health.healed.connect(
		func(amount: float) -> void: EventBus.player_healed.emit(int(roundf(amount)))
	)
	var ph := health as PlayerHealth
	if ph != null:
		ph.shield_absorbed.connect(_on_shield_absorbed)
		ph.shield_changed.connect(func(amount: float) -> void: shield_changed.emit(amount))
	EventBus.palette_changed.connect(_on_palette_changed)
	EventBus.player_hit_dealt.connect(_on_hit_dealt)
	EventBus.enemy_died.connect(_on_enemy_died)
	_retint(Desktop.palette, false)
	if _pending_class != null:
		apply_class(_pending_class)
	elif class_def != null:
		apply_class(class_def)
	elif sprite.sprite_frames == null:
		_build_frames(null)
	_update_invulnerable()


func _setup_children() -> void:
	input = get_node_or_null("Input") as PlayerInput
	if input == null:
		input = PlayerInput.new()
		input.name = "Input"
		add_child(input)
	input.enabled = input_enabled
	sprite = get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null:
		sprite = AnimatedSprite2D.new()
		sprite.name = "Sprite"
		sprite.position = Vector2(0, -2)
		add_child(sprite)
	_flash_material = sprite.material as ShaderMaterial
	if _flash_material == null:
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = load(FLASH_SHADER) as Shader
		sprite.material = _flash_material
	marker = get_node_or_null("Marker") as PlayerMarker
	if marker == null:
		marker = PlayerMarker.new()
		marker.name = "Marker"
		add_child(marker)
	outline = get_node_or_null("Outline") as SpriteOutline
	if outline == null:
		outline = SpriteOutline.new()
		outline.name = "Outline"
		add_child(outline)
	outline.source = sprite
	outline.position = sprite.position
	# Draw order, not z: both sit at z 0 (the tile layers are opaque at z 0) and rely on being
	# earlier children than the sprite. Ring first, then the rim, then the body.
	move_child(marker, 0)
	move_child(outline, 1)
	weapon_pivot = get_node_or_null("WeaponPivot") as Node2D
	if weapon_pivot == null:
		weapon_pivot = Node2D.new()
		weapon_pivot.name = "WeaponPivot"
		add_child(weapon_pivot)
	weapon_controller = weapon_pivot.get_node_or_null("WeaponController") as WeaponController
	if weapon_controller == null:
		weapon_controller = WeaponController.new()
		weapon_controller.name = "WeaponController"
		weapon_controller.player = self
		weapon_pivot.add_child(weapon_controller)
	weapon_controller.player = self
	light = get_node_or_null("Light") as PointLight2D
	if light == null:
		light = PointLight2D.new()
		light.name = "Light"
		light.energy = 0.7
		light.texture_scale = 1.5
		add_child(light)
	if light.texture == null:
		light.texture = _make_light_texture()
	light.shadow_enabled = false
	dodge_dust = get_node_or_null("DodgeDust") as CPUParticles2D
	if dodge_dust == null:
		dodge_dust = CPUParticles2D.new()
		dodge_dust.name = "DodgeDust"
		add_child(dodge_dust)
	dodge_dust.emitting = false
	dodge_dust.one_shot = true
	dodge_dust.explosiveness = 1.0
	dodge_dust.amount = 8
	dodge_dust.lifetime = 0.35
	dodge_dust.spread = 35.0
	dodge_dust.gravity = Vector2.ZERO
	dodge_dust.initial_velocity_min = 18.0
	dodge_dust.initial_velocity_max = 40.0
	dodge_dust.scale_amount_min = 1.0
	dodge_dust.scale_amount_max = 2.0
	dodge_dust.position = Vector2(0, 4)
	ability_slots = get_node_or_null("AbilitySlots")
	if ability_slots == null:
		ability_slots = _make_ability_slots()
		if ability_slots != null:
			ability_slots.name = "AbilitySlots"
			add_child(ability_slots)
	if equipment == null:
		equipment = _make_equipment()
	_propagate_rng()


## Instantiates the abilities module's AbilitySlots when that module is present. RunManager
## and the HUD rely on `ability_slots` being non-null for every player.
static func _make_ability_slots() -> Node:
	if not ResourceLoader.exists(ABILITY_SLOTS_SCRIPT):
		return null
	var script := load(ABILITY_SLOTS_SCRIPT) as GDScript
	if script == null:
		return null
	return script.new() as Node


## Instantiates (and binds) the items module's Equipment when that module is present.
func _make_equipment() -> RefCounted:
	if not ResourceLoader.exists(EQUIPMENT_SCRIPT):
		return null
	var script := load(EQUIPMENT_SCRIPT) as GDScript
	if script == null:
		return null
	var eq := script.new() as RefCounted
	if eq != null and eq.has_method("bind"):
		eq.call("bind", self)
	return eq


## Shares the combat stream with the sub-systems that roll dice of their own, so a fixed run
## seed produces a fixed fight (docs §1).
func _propagate_rng() -> void:
	var ph := health as PlayerHealth
	if ph != null:
		ph.set_rng(rng)
	if ability_slots != null and ability_slots.get(&"rng") is RandomNumberGenerator:
		ability_slots.set(&"rng", rng)


## The player's pool, from the same builder every other light on the floor uses
## (`DungeonLight.make_texture`), so its falloff is the one `DungeonLight.FALLOFF_POWER`
## shapes. It was a second copy of a linear ramp written out here, which meant the player
## carried the old halo around a dungeon whose lanterns had stopped throwing one.
static func _make_light_texture() -> Texture2D:
	return DungeonLight.make_texture(64)


# ---------------------------------------------------------------- class & sheet


## Applies base stats, dodge style, start gold and the class sprite sheet. Full heal.
func apply_class(def: ClassDef) -> void:
	if def == null:
		return
	if not is_node_ready():
		_pending_class = def
		class_def = def
		return
	_pending_class = null
	class_def = def
	class_id = def.id
	dodge_style = def.dodge_style
	var base := def.base_stats()
	for stat: StringName in Stats.PRIMARY:
		stats.set_base(stat, float(base[stat]))
	_sync_health_from_stats(false)
	health.setup(stats.get_value(&"max_hp"), false)
	gold = def.start_gold
	_build_frames(load_class_sheet(def.sprite_sheet_path()))
	for stat: StringName in Stats.PRIMARY:
		EventBus.stat_changed.emit(stat, stats.primary(stat))
	EventBus.gold_changed.emit(gold)
	gold_changed.emit(gold, gold)
	class_applied.emit(def)


## Builds SpriteFrames from a 6-column, 5-row sheet of 16x16 frames (placeholder when null).
func _build_frames(sheet: Texture2D) -> void:
	var texture := sheet if sheet != null else _placeholder_sheet()
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for row in range(SHEET_ROWS.size()):
		var anim: StringName = SHEET_ROWS[row][0]
		var count: int = SHEET_ROWS[row][1]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(SHEET_ROWS[row][2]))
		frames.set_animation_loop(anim, bool(SHEET_ROWS[row][3]))
		for col in range(count):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * FRAME, row * FRAME, FRAME, FRAME)
			frames.add_frame(anim, atlas)
	sprite.sprite_frames = frames
	sprite.play(&"idle")


## Loads a class sheet, or null when it cannot be read. `ResourceLoader` misses a texture
## whose `.import` has not been written yet (a freshly copied project, a half-finished import),
## so a miss is retried straight off disk before giving up - that race is what once put a
## blank rectangle on screen instead of the Fighter. A genuine miss is loud: it is a missing
## asset, not a cosmetic detail.
static func load_class_sheet(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path) as Texture2D
		if res != null:
			return res
	var global := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(global):
		var image := Image.load_from_file(global)
		if image != null:
			return ImageTexture.create_from_image(image)
	push_error("Player: class sprite sheet missing, drawing the placeholder instead: %s" % path)
	return null


## Stand-in sheet used when the class sheet cannot be loaded: a small figure (head, torso,
## legs, two eyes) in the theme's `accent` with an outline in the theme's ink, guarded to
## 4.5:1 against the floor. The old placeholder was a featureless white block, which on a
## light theme is invisible against the floor - the player could not see their character.
static func _placeholder_sheet() -> Texture2D:
	var img := Image.create(
		SHEET_COLS * FRAME, SHEET_ROWS.size() * FRAME, false, Image.FORMAT_RGBA8
	)
	img.fill(Color(0, 0, 0, 0))
	var body := placeholder_body_color()
	var ink := placeholder_ink_color()
	for row in range(SHEET_ROWS.size()):
		for col in range(SHEET_COLS):
			_draw_placeholder_figure(img, col * FRAME, row * FRAME, body, ink)
	return ImageTexture.create_from_image(img)


## Fill colour of the placeholder figure: `accent` pushed to 4.5:1 against the dungeon floor.
static func placeholder_body_color() -> Color:
	var palette := Desktop.palette if Desktop != null else null
	if palette == null:
		return Color(0.85, 0.35, 0.25)
	return ThemePalette.ensure_contrast(
		palette.get_color(&"accent"), palette.get_color(&"floor"), ThemePalette.MIN_CONTRAST
	)


## Outline colour of the placeholder figure: the palette's darkest ink, so the silhouette
## still reads where the body colour happens to match what is behind it.
static func placeholder_ink_color() -> Color:
	var palette := Desktop.palette if Desktop != null else null
	if palette == null:
		return Color(0.05, 0.05, 0.08)
	return palette.outline_color()


static func _draw_placeholder_figure(img: Image, x: int, y: int, body: Color, ink: Color) -> void:
	var parts: Array[Rect2i] = [
		Rect2i(x + 5, y + 2, 6, 5),
		Rect2i(x + 4, y + 7, 8, 5),
		Rect2i(x + 4, y + 12, 3, 3),
		Rect2i(x + 9, y + 12, 3, 3),
	]
	for part: Rect2i in parts:
		img.fill_rect(part.grow(1), ink)
	for part: Rect2i in parts:
		img.fill_rect(part, body)
	img.fill_rect(Rect2i(x + 6, y + 4, 1, 2), ink)
	img.fill_rect(Rect2i(x + 9, y + 4, 1, 2), ink)


## Frame texture used by the decoy (idle frame 0).
func idle_frame_texture() -> Texture2D:
	if (
		sprite == null
		or sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(&"idle")
	):
		return null
	return sprite.sprite_frames.get_frame_texture(&"idle", 0)


# ---------------------------------------------------------------- loop


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if state == State.DEAD:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		move_with_knockback(delta)
		return
	var move := input.move_vector() if can_act() else Vector2.ZERO
	_tick_auto_aim(delta)
	_aim = input.aim_direction(global_position, facing)
	# Before handle_input: the melee hitbox hangs off the pivot and samples overlaps the frame
	# an attack starts, so it must already point at this frame's aim.
	weapon_pivot.rotation = _aim.angle()
	match state:
		State.NORMAL:
			_apply_movement(delta, move)
			if input.dodge_just_pressed():
				try_dodge(move if move.length_squared() > 0.01 else facing)
			if state == State.NORMAL:
				weapon_controller.handle_input(
					_aim,
					input.attack_held(),
					input.attack_just_pressed(),
					input.attack_just_released(),
					input.secondary_just_pressed()
				)
				_handle_misc_input()
		State.DODGE_STARTUP:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		State.DODGING:
			velocity = _dodge_velocity
	move_with_knockback(delta)
	_update_facing(move)
	_update_animation()


func _tick_timers(delta: float) -> void:
	if _dodge_cooldown_left > 0.0:
		_dodge_cooldown_left -= delta
	if _hurt_anim_left > 0.0:
		_hurt_anim_left -= delta
	if _shield_expire_left > 0.0:
		_shield_expire_left -= delta
		if _shield_expire_left <= 0.0:
			set_shield(0.0)
	var invuln_changed := false
	if _iframes_left > 0.0:
		_iframes_left -= delta
		invuln_changed = true
	if _hit_invuln_left > 0.0:
		_hit_invuln_left -= delta
		invuln_changed = true
	if state == State.DODGE_STARTUP or state == State.DODGING:
		_dodge_time_left -= delta
		if _dodge_time_left <= 0.0:
			_advance_dodge()
			invuln_changed = true
	if invuln_changed:
		_update_invulnerable()


func _apply_movement(delta: float, move: Vector2) -> void:
	var factor := SLIPPERY_FACTOR if _slippery else 1.0
	if move.length_squared() > 0.001:
		var wanted := move * effective_speed()
		velocity = velocity.move_toward(wanted, ACCELERATION * factor * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * factor * delta)


## Gamepad aim assist (docs §4.1): with the right stick idle the aim snaps to the nearest
## enemy. Refreshed on an interval because it costs one physics query.
func _tick_auto_aim(delta: float) -> void:
	if input == null:
		return
	if not input.is_gamepad():
		input.auto_aim_target = null
		return
	_auto_aim_timer -= delta
	if _auto_aim_timer > 0.0:
		return
	_auto_aim_timer = AUTO_AIM_INTERVAL
	input.auto_aim_target = weapon_controller.nearest_enemy(
		global_position, WeaponController.ENEMY_SEARCH_RADIUS
	)


func _handle_misc_input() -> void:
	if input.potion_just_pressed():
		use_potion()
	if input.interact_just_pressed():
		interact_pressed.emit()
	for i in range(2):
		if input.active_just_pressed(i):
			active_pressed.emit(i, _aim)
			if ability_slots != null and ability_slots.has_method("try_use"):
				ability_slots.call("try_use", i, _aim)


func _update_facing(move: Vector2) -> void:
	if state == State.DODGING or state == State.DODGE_STARTUP:
		facing = _dodge_dir
	elif _aim.length_squared() > 0.001:
		facing = _aim
	elif move.length_squared() > 0.001:
		facing = move.normalized()
	refresh_carry(facing)


## Settles how the character carries their weapon for a direction (`WeaponCarry`): the body
## mirror, which side of the body the hand is on, whether the weapon draws in front of the body
## or behind it, and whether it is tucked in for a dodge. Public because the pose gallery drives
## it directly - "the weapon looks held" is a claim only a picture can make.
func refresh_carry(dir: Vector2) -> void:
	carry.update(dir)
	if sprite != null:
		sprite.flip_h = carry.flipped
	if weapon_pivot != null:
		# Not z_index: z 0 is the ground layer, so a negative z hides the weapon under the floor.
		weapon_pivot.show_behind_parent = carry.behind
	if weapon_controller != null:
		weapon_controller.set_mirrored(carry.flipped)
		weapon_controller.set_tucked(state == State.DODGING or state == State.DODGE_STARTUP)


func _update_animation() -> void:
	var anim := &"idle"
	if state == State.DEAD:
		anim = &"death"
	elif state == State.DODGING or state == State.DODGE_STARTUP:
		anim = &"dodge"
	elif _hurt_anim_left > 0.0:
		anim = &"hurt"
	elif velocity.length_squared() > 25.0:
		anim = &"run"
	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(anim)
		and sprite.animation != anim
	):
		sprite.play(anim)


# ---------------------------------------------------------------- dodge


func is_dodging() -> bool:
	return state == State.DODGING or state == State.DODGE_STARTUP


func is_invulnerable() -> bool:
	return health.invulnerable


func dodge_ready() -> bool:
	return _dodge_cooldown_left <= 0.0 and state == State.NORMAL


## True while dodging for classes whose passive grants it (Ranger's Sure-footed).
func is_trap_immune() -> bool:
	return is_dodging() and bool(flags.get("trap_immune_dodge", false))


## Ice floors: sluggish acceleration and friction.
func set_slippery(on: bool) -> void:
	_slippery = on


func aim_direction() -> Vector2:
	return _aim


## Starts the class dodge toward `dir`. Returns false when on cooldown or unable to act.
func try_dodge(dir: Vector2) -> bool:
	if not dodge_ready() or not can_act():
		return false
	_dodge_dir = dir.normalized() if dir.length_squared() > 0.001 else facing
	_dodge_cooldown_left = DODGE_COOLDOWN
	weapon_controller.cancel()
	var distance_mult := maxf(0.2, stats.get_value(&"dodge_distance"))
	match dodge_style:
		ClassDef.DodgeStyle.ROLL:
			_begin_dash(ROLL_DISTANCE * distance_mult, ROLL_TIME)
			_iframes_left = ROLL_TIME
		ClassDef.DodgeStyle.DASH:
			var dash_distance := DASH_DISTANCE * distance_mult
			_begin_dash(dash_distance, DASH_TIME)
			drop_caltrops(dash_distance)
		ClassDef.DodgeStyle.BLINK:
			state = State.DODGE_STARTUP
			_dodge_time_left = BLINK_STARTUP
			_dodge_velocity = Vector2.ZERO
			velocity = Vector2.ZERO
			_squash(Vector2(0.7, 1.3), BLINK_STARTUP)
			sprite.modulate.a = 0.6
		ClassDef.DodgeStyle.DELEGATE:
			spawn_decoy()
			_begin_dash(HOP_DISTANCE * distance_mult, HOP_TIME)
	_update_invulnerable()
	_puff_dust(-_dodge_dir)
	dodge_started.emit(dodge_style)
	EventBus.player_dodged.emit(ClassDef.DODGE_STYLE_NAMES[dodge_style])
	return true


func _begin_dash(distance: float, duration: float) -> void:
	state = State.DODGING
	_dodge_time_left = duration
	_dodge_velocity = _dodge_dir * (distance / duration)
	velocity = _dodge_velocity
	_squash(Vector2(1.3, 0.7), duration)


func _advance_dodge() -> void:
	if state == State.DODGE_STARTUP:
		var distance_mult := maxf(0.2, stats.get_value(&"dodge_distance"))
		_blink_to(_dodge_dir, BLINK_DISTANCE * distance_mult)
		sprite.modulate.a = 1.0
		_iframes_left = BLINK_IFRAMES
		state = State.DODGING
		_dodge_time_left = BLINK_LANDING
		_dodge_velocity = Vector2.ZERO
		_squash(Vector2(1.3, 0.7), 0.15)
		_puff_dust(_dodge_dir)
		return
	state = State.NORMAL
	_dodge_velocity = Vector2.ZERO
	velocity = velocity.limit_length(effective_speed())
	dodge_finished.emit()


## Teleports up to `distance` along `dir`, stopping short of walls/props. The raycast only
## tests the centre line, so the landing spot is then walked back until the body's own capsule
## actually fits (a diagonal blink through a doorway corner must not end inside geometry).
func _blink_to(dir: Vector2, distance: float) -> Vector2:
	var from := global_position
	var travel := distance
	var space := get_world_2d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters2D.create(
			from, from + dir * distance, Layers.WORLD | Layers.PROP
		)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			travel = maxf(0.0, from.distance_to(hit["position"] as Vector2) - 6.0)
	while travel >= BLINK_STEP_BACK and test_move(global_transform, dir * travel):
		travel -= BLINK_STEP_BACK
	if travel < BLINK_STEP_BACK:
		return from
	global_position = from + dir * travel
	return global_position


## Ranger dodge (docs §4.3): leaves a small patch of caltrops along the dash path. Each one
## is a player-team Hitbox that damages enemies walking over it (re-hitting every
## CALTROP_REHIT seconds) and vanishes after CALTROP_LIFETIME. Returns the spawned hitboxes.
## Damage goes through `make_damage`, so the Ranger's stats and crits apply.
func drop_caltrops(distance: float) -> Array[Hitbox]:
	var out: Array[Hitbox] = []
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return out
	var origin := global_position
	var texture := _caltrop_texture()
	for i in range(CALTROP_COUNT):
		var t := CALTROP_START + (1.0 - CALTROP_START) * (float(i) / float(CALTROP_COUNT))
		out.append(_spawn_caltrop(parent, origin + _dodge_dir * distance * t, texture))
	return out


func _spawn_caltrop(parent: Node, pos: Vector2, texture: Texture2D) -> Hitbox:
	var caltrop := Hitbox.new()
	caltrop.name = "Caltrop"
	caltrop.add_to_group(CALTROP_GROUP)
	caltrop.team = team
	caltrop.damage = CALTROP_DAMAGE
	caltrop.tags = [DamageInfo.TAG_PHYSICAL, DamageInfo.TAG_TRAP]
	caltrop.knockback = CALTROP_KNOCKBACK
	caltrop.multi_hit_interval = CALTROP_REHIT
	caltrop.source = self
	caltrop.damage_builder = _build_caltrop_damage.bind(caltrop)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = CALTROP_RADIUS
	shape.shape = circle
	caltrop.add_child(shape)
	if texture != null:
		var art := Sprite2D.new()
		art.texture = texture
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		caltrop.add_child(art)
	parent.add_child(caltrop)
	caltrop.global_position = pos
	caltrop.activate(CALTROP_LIFETIME)
	var t := caltrop.create_tween()
	t.tween_interval(CALTROP_LIFETIME * 0.7)
	t.tween_property(caltrop, "modulate:a", 0.0, CALTROP_LIFETIME * 0.3)
	t.tween_callback(caltrop.queue_free)
	return caltrop


## `Hitbox.damage_builder` for one caltrop. Knockback pushes away from the caltrop, not from
## the Ranger, who is long gone by the time an enemy steps on it.
func _build_caltrop_damage(target: Node2D, caltrop: Node2D) -> DamageInfo:
	var dir := Vector2.ZERO
	if target != null and is_instance_valid(target) and is_instance_valid(caltrop):
		dir = target.global_position - caltrop.global_position
	return make_damage(
		CALTROP_DAMAGE, [DamageInfo.TAG_PHYSICAL, DamageInfo.TAG_TRAP], dir, CALTROP_KNOCKBACK, rng
	)


## The caltrop cell of the shared projectile sheet, or null when the sheet is missing.
func _caltrop_texture() -> Texture2D:
	if not ResourceLoader.exists(CALTROP_SHEET):
		return null
	var sheet := load(CALTROP_SHEET) as Texture2D
	if sheet == null:
		return null
	var region := AtlasTexture.new()
	region.atlas = sheet
	region.region = Rect2(CALTROP_FRAME * FRAME, 0, FRAME, FRAME)
	return region


## Spawns a Decoy at the current position (Oligarch dodge; also usable by abilities).
func spawn_decoy() -> Decoy:
	var decoy := (load(DECOY_SCRIPT) as GDScript).new() as Decoy
	decoy.setup(idle_frame_texture(), sprite.flip_h)
	var parent := get_parent() if get_parent() != null else self
	parent.add_child(decoy)
	decoy.global_position = global_position
	return decoy


func _puff_dust(direction: Vector2) -> void:
	if dodge_dust == null:
		return
	dodge_dust.direction = direction
	dodge_dust.restart()
	dodge_dust.emitting = true


func _squash(to_scale: Vector2, duration: float) -> void:
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	sprite.scale = to_scale
	_squash_tween = create_tween()
	(
		_squash_tween
		. tween_property(sprite, "scale", Vector2.ONE, maxf(0.05, duration))
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


# ---------------------------------------------------------------- damage & death


func _update_invulnerable() -> void:
	health.invulnerable = _iframes_left > 0.0 or _hit_invuln_left > 0.0 or state == State.DEAD


func _is_dot(info: DamageInfo) -> bool:
	return info.team == Layers.Team.NEUTRAL and info.has_tag(DamageInfo.TAG_TRUE)


func _on_player_damaged(info: DamageInfo) -> void:
	if info.applied <= 0.0:
		return
	EventBus.player_damaged.emit(int(roundf(info.applied)), info.source)
	_flash(1.0)
	if _is_dot(info):
		return
	_hit_invuln_left = HIT_INVULN_TIME
	_update_invulnerable()
	_hurt_anim_left = HURT_ANIM_TIME
	_squash(Vector2(0.75, 1.25), 0.18)
	# Drop the combo and any held charge, but leave a live hitbox alone: losing a swing the
	# player already committed to reads as an unfair whiff.
	weapon_controller.interrupt_charge()
	if state == State.NORMAL and _feel != null:
		_feel.hit_stop_for(info.applied)
	EventBus.screen_shake.emit(clampf(2.0 + info.applied * 0.1, 2.0, 6.0), 0.2)
	_punch_camera(_hit_direction(info), info.applied)
	_impact_puff(global_position, _danger_color())


func _on_shield_absorbed(amount: float, _info: DamageInfo) -> void:
	_flash(0.5)
	EventBus.screen_shake.emit(clampf(1.0 + amount * 0.05, 1.0, 3.0), 0.12)


## Hit flash on the sprite shader. Strength and fade time come from the feel profile, so the
## `reduced_flash` accessibility setting dims every flash in the game from one place.
func _flash(strength: float) -> void:
	if _flash_material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var claimed := _feel.claim_flash(strength) if _feel != null else strength
	var peak := clampf(claimed, 0.0, FLASH_MAX)
	var fade := _feel.flash_time() * 1.5 if _feel != null else 0.18
	_flash_material.set_shader_parameter(&"flash", peak)
	if peak <= 0.0:
		return
	# The flash bleaches the sheet's own ink rim along with everything else, which is the one
	# moment the stamped rim is needed; it is not drawn outside it (see `SpriteOutline`).
	if outline != null:
		outline.flash_for(fade)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "shader_parameter/flash", 0.0, fade)


## Docs §4.2 secondary `lifesteal`: every point of damage the player deals gives back that
## fraction as health. Hooked to EventBus.player_hit_dealt so weapon swings, weapon skills and
## abilities all count, and driven by `info.applied` so soaked or resisted damage heals less.
func _on_hit_dealt(_target: Node2D, info: DamageInfo) -> void:
	var fraction := stats.get_value(&"lifesteal")
	if fraction <= 0.0 or info == null or info.applied <= 0.0:
		return
	health.heal(info.applied * fraction)


## Docs §4.2 secondary `life_on_kill`: a flat heal each time the player finishes something off.
func _on_enemy_died(_enemy: Node2D, killer: Node2D) -> void:
	if killer != self:
		return
	var amount := stats.get_value(&"life_on_kill")
	if amount > 0.0:
		health.heal(amount)


## Called by the WeaponController when a weapon hit lands.
## Called by the WeaponController when a weapon hit lands: the impact half of the attack's
## anticipation/impact/recovery beat. Hit-stop is queued through `GameFeel`, so a flurry into a
## pack takes the longest stop rather than the sum of them.
func on_weapon_hit(target: Node2D, info: DamageInfo) -> void:
	weapon_hit.emit(target, info)
	EventBus.player_hit_dealt.emit(target, info)
	var heavy := info.is_crit or info.amount >= _heavy_damage()
	if _feel != null:
		# Crits and heavy blows only: freezing on every swing of a 2.5 aps weapon would stall
		# the whole game (audio, tweens, AI) several times a second.
		if heavy:
			_feel.hit_stop_for(info.amount, true)
		_feel.add_trauma(_feel.profile.hit_trauma(info.amount, info.is_crit) * 0.5, 0.18)
	var at := target.global_position if is_instance_valid(target) else global_position
	_impact_puff(at, Color.WHITE, 12 if heavy else 6)
	if heavy and is_instance_valid(target):
		_punch_camera((at - global_position).normalized(), info.amount)


func _die(_killer: Node2D) -> void:
	var was_dodging := is_dodging()
	state = State.DEAD
	input_enabled = false
	sprite.modulate.a = 1.0  # a BLINK startup dims the sprite; _advance_dodge never runs now
	if was_dodging:
		dodge_finished.emit()
	weapon_controller.cancel()
	_update_invulnerable()
	hurtbox.set_deferred("monitorable", false)
	velocity = Vector2.ZERO
	_flash(1.0)
	EventBus.screen_shake.emit(6.0, 0.4)
	_impact_puff(global_position, _danger_color(), 24, 22.0)
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"death"):
		sprite.play(&"death")
	await get_tree().create_timer(DEATH_ANIM_TIME).timeout
	EventBus.player_died.emit()


## Direction the hit came from (used to kick the camera away from the attacker).
func _hit_direction(info: DamageInfo) -> Vector2:
	if info != null and is_instance_valid(info.source):
		var d := global_position - info.source.global_position
		if d.length_squared() > 0.01:
			return d.normalized()
	if info != null and info.knockback.length_squared() > 0.01:
		return info.knockback.normalized()
	return Vector2.ZERO


## Small directional camera kick on a heavy blow. Honours the screen-shake setting via GameFeel.
func _punch_camera(dir: Vector2, amount: float) -> void:
	if _feel == null or dir.length_squared() < 0.0001:
		return
	if amount < _heavy_damage():
		return
	_feel.punch(dir, _feel.profile.punch_px)


func _heavy_damage() -> float:
	return _feel.profile.heavy_damage if _feel != null else 25.0


## Pooled impact puff (no allocation on a busy screen).
func _impact_puff(pos: Vector2, tint: Color, count: int = -1, radius: float = 14.0) -> void:
	if _fx == null:
		_fx = FxPool.of(self)
	if _fx != null:
		_fx.puff(pos, tint, count, radius)


func _danger_color() -> Color:
	return DangerTell.color()


# ---------------------------------------------------------------- resources


## Heals 40% of max HP and consumes the potion. Returns false when none left.
func use_potion() -> bool:
	if potions <= 0 or health.is_dead():
		return false
	potions -= 1
	var amount := health.heal(health.max_hp * POTION_HEAL_FRACTION)
	potion_used.emit(amount)
	potions_changed.emit(potions, max_potions)
	_flash(0.4)
	return true


func add_potion(count: int = 1) -> void:
	potions = clampi(potions + count, 0, max_potions)
	potions_changed.emit(potions, max_potions)


func shield() -> float:
	var ph := health as PlayerHealth
	return ph.shield if ph != null else 0.0


## Absorb pool that soaks damage before HP (Bulwark). Not additive; `duration` > 0 makes it
## expire on its own.
func set_shield(amount: float, duration: float = 0.0) -> void:
	var ph := health as PlayerHealth
	if ph != null:
		ph.set_shield(amount)
	_shield_expire_left = duration if amount > 0.0 else 0.0


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(0, gold + amount)
	gold_changed.emit(gold, amount)
	EventBus.gold_changed.emit(gold)


## Returns false (and changes nothing) when the player cannot afford it.
func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold, -amount)
	EventBus.gold_changed.emit(gold)
	return true


## Stat orbs: adds primary points and broadcasts the new value.
func add_stat(stat: StringName, points: int = 1) -> void:
	if not Stats.PRIMARY.has(stat):
		return
	stats.add_primary(stat, points)
	EventBus.stat_changed.emit(stat, stats.primary(stat))


## Config gremlin: removes one point of `stat` if any. Returns whether something was stolen.
func steal_stat(stat: StringName) -> bool:
	if not Stats.PRIMARY.has(stat) or stats.primary(stat) <= 0:
		return false
	stats.add_primary(stat, -1)
	EventBus.stat_changed.emit(stat, stats.primary(stat))
	return true


## Equips an item: delegates to `equipment.equip(item)` when the items module provided one
## (else applies the item's stats directly) and swaps the weapon controller for weapons.
func equip(item: ItemInstance) -> void:
	if item == null or item.base == null:
		return
	if equipment != null and equipment.has_method("equip"):
		equipment.call("equip", item, stats)
		# Equipment rejects slot mismatches; re-read the slot instead of assuming it took.
		if item.is_weapon():
			_sync_weapon_from_equipment()
		return
	item.apply_to(stats)
	EventBus.item_equipped.emit(item.base, item.base.slot_name())
	if item.is_weapon():
		weapon_controller.set_weapon(item.base as WeaponBase, item, null)


## Per-equip weapon skill copy from the Equipment (own cooldown state), else null.
func _equipment_weapon_skill() -> ActiveAbility:
	if equipment != null and equipment.has_method("weapon_skill"):
		return equipment.call("weapon_skill") as ActiveAbility
	return null


## Outgoing weapon damage: stats/crit via `make_damage`, then passive multipliers and queued
## one-hit buffs from AbilitySlots, then equipment on-hit statuses.
func make_weapon_damage(
	target: Node2D, base: float, tags: Array[StringName], dir: Vector2, knockback: float
) -> DamageInfo:
	var info := make_damage(base, tags, dir, knockback, rng)
	if ability_slots != null and ability_slots.has_method("outgoing_damage_multiplier"):
		info.amount *= float(ability_slots.call("outgoing_damage_multiplier", target, info))
	if equipment != null and equipment.has_method("roll_on_hit_statuses"):
		var rolled: Variant = equipment.call("roll_on_hit_statuses", rng, self)
		if rolled is Array:
			for status_effect: Variant in rolled as Array:
				if status_effect is StatusEffect:
					info.with_status(status_effect as StatusEffect)
	return info


# ---------------------------------------------------------------- save/restore


## Snapshot for RunState.player.
func to_dict() -> Dictionary:
	var equipment_data: Dictionary = {}
	if equipment != null and equipment.has_method("to_dict"):
		equipment_data = equipment.call("to_dict")
	var abilities_data: Dictionary = {}
	if ability_slots != null and ability_slots.has_method("to_dict"):
		abilities_data = ability_slots.call("to_dict")
	return {
		"hp_fraction": health.fraction(),
		"gold": gold,
		"potion": potions,
		"max_potions": max_potions,
		"stats": stats.to_dict(),
		"equipment": equipment_data,
		"abilities": abilities_data,
		"flags": flags.duplicate(true),
		"shield": shield(),
	}


## Restores a `to_dict` snapshot. Equipment is rebuilt through the items module's static
## `Equipment.from_dict(data, registry, stats)` (called on the current instance) and abilities
## through `AbilitySlots.from_dict(data, registry)` when those modules are present.
func restore_from_dict(
	data: Dictionary, item_registry: Resource = null, ability_registry: Resource = null
) -> void:
	if data.has("stats") and data["stats"] is Dictionary:
		stats.from_dict(data["stats"])
		_strip_layered_owners(data["stats"] as Dictionary)
		_sync_health_from_stats(false)
	gold = int(data.get("gold", gold))
	max_potions = maxi(1, int(data.get("max_potions", max_potions)))
	potions = clampi(int(data.get("potion", potions)), 0, max_potions)
	if data.get("flags", null) is Dictionary:
		flags = (data["flags"] as Dictionary).duplicate(true)
	var equipment_data: Dictionary = {}
	if data.get("equipment", null) is Dictionary:
		equipment_data = data["equipment"] as Dictionary
	if equipment != null and equipment.has_method("from_dict"):
		var restored: Variant = equipment.call("from_dict", equipment_data, item_registry, stats)
		if restored is RefCounted:
			equipment = restored
			if equipment.has_method("bind"):
				equipment.call("bind", self)
		_sync_weapon_from_equipment()
	elif not equipment_data.is_empty():
		push_warning("Player.restore_from_dict: saved equipment dropped (no Equipment instance)")
	if ability_slots != null and ability_slots.has_method("from_dict"):
		ability_slots.call("from_dict", data.get("abilities", {}), ability_registry)
	elif not (data.get("abilities", {}) as Dictionary).is_empty():
		push_warning("Player.restore_from_dict: saved abilities dropped (no AbilitySlots)")
	set_shield(float(data.get("shield", 0.0)))
	var fraction := clampf(float(data.get("hp_fraction", 1.0)), 0.01, 1.0)
	health.hp = clampf(health.max_hp * fraction, 1.0, health.max_hp)
	health.hp_changed.emit(health.hp, health.max_hp)
	EventBus.gold_changed.emit(gold)
	gold_changed.emit(gold, 0)
	potions_changed.emit(potions, max_potions)
	for stat: StringName in Stats.PRIMARY:
		EventBus.stat_changed.emit(stat, stats.primary(stat))


## `Stats.to_dict()` serialises the layered `item:<uid>` / `passive:<id>` modifier tables, and
## rebuilding Equipment and AbilitySlots re-applies exactly those modifiers. Drop them after the
## snapshot is replayed so gear and passive bonuses are not counted twice per resume.
func _strip_layered_owners(stats_data: Dictionary) -> void:
	var owners: Dictionary = {}
	for table_key: String in ["flat", "percent"]:
		if not (stats_data.get(table_key, null) is Dictionary):
			continue
		var table: Dictionary = stats_data[table_key]
		for stat_key: Variant in table.keys():
			if not (table[stat_key] is Dictionary):
				continue
			for owner_key: Variant in (table[stat_key] as Dictionary).keys():
				var owner := String(owner_key)
				if owner.begins_with("item:") or owner.begins_with("passive:"):
					owners[owner] = true
	for owner: String in owners.keys():
		stats.remove_owner(StringName(owner))


## Points the weapon controller at whatever the Equipment currently holds in the weapon slot.
func _sync_weapon_from_equipment() -> void:
	if equipment == null or not equipment.has_method("get_item"):
		return
	var item := equipment.call("get_item", &"weapon") as ItemInstance
	if item != null and item.is_weapon():
		weapon_controller.set_weapon(item.base as WeaponBase, item, _equipment_weapon_skill())
	else:
		weapon_controller.set_weapon(null)


# ---------------------------------------------------------------- theme


func _on_palette_changed(palette: ThemePalette) -> void:
	_retint(palette, true)


func _retint(palette: ThemePalette, animate: bool) -> void:
	if palette == null:
		return
	var accent := palette.get_color(&"accent")
	var dust := palette.get_color(&"text_dim")
	dust.a = 0.8
	if marker != null:
		marker.retint(palette)
	if outline != null:
		var ink := palette.outline_color()
		ink.a = OUTLINE_ALPHA
		outline.set_tint(ink)
	if _flash_material != null:
		# Not white. Every enemy flashes white, so a white player flash is the one frame in
		# which the player is indistinguishable from the thing that just hit them; the theme's
		# own danger colour says "that was me" and keeps the six themes apart while it does.
		_flash_material.set_shader_parameter(&"flash_color", _danger_color())
	if not animate:
		light.color = accent
		dodge_dust.color = dust
		return
	if _light_tween != null and _light_tween.is_valid():
		_light_tween.kill()
	_light_tween = create_tween().set_parallel(true)
	_light_tween.tween_property(light, "color", accent, 0.6)
	_light_tween.tween_property(dodge_dust, "color", dust, 0.6)
