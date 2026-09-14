## Base for every regular enemy: state machine (IDLE → APPROACH → WINDUP → ATTACK → RECOVER),
## awareness, navigation/steering, hit feedback, telegraphs, death FX and loot. Concrete
## enemies override `_perform_attack()` (and optionally `_approach_process()`, `_on_death()`,
## `_modify_incoming()`).
##
## **Awareness gates the state machine.** An enemy that has not noticed the player stays at its
## post: it still picks a target (that is who it *would* chase) but it does not path anywhere,
## and IDLE → APPROACH is refused until `EnemyAwareness` says it is awake. It wakes when it
## sees the player, when the player walks into its room, when it is hit, or when a pack-mate
## passes the word; it settles back a few seconds after it loses contact and walks home. The
## rule itself lives in `EnemyAwareness`, the numbers in `data/enemies/awareness.tres`, and the
## "!" the player reads it by in `AlertMark`.
class_name EnemyBase
extends Entity

signal state_changed(previous: State, current: State)
signal attack_started
signal converted(new_team: Layers.Team)

enum State { IDLE, APPROACH, WINDUP, ATTACK, RECOVER, STUNNED, DEAD }

## Sheet rows in `EnemyDef.texture`: name -> [row, frame_count, fps, loops].
const ANIMS: Dictionary = {
	&"idle": [0, 4, 6.0, true],
	&"move": [1, 4, 10.0, true],
	&"windup": [2, 2, 8.0, true],
	&"attack": [3, 3, 12.0, false],
	&"hurt": [4, 1, 1.0, false],
	&"death": [5, 4, 8.0, false],
}
## Beyond this distance (px) steering always follows the navigation path.
const DIRECT_STEER_DISTANCE := 96.0
const SEPARATION_RADIUS := 12.0
const SEPARATION_STRENGTH := 45.0
const HEART_DROP_CHANCE := 0.08
const HEART_HEAL := 15
## Extra gold a floor is worth, per floor index.
const GOLD_PER_FLOOR := 0.1
## Docs §7: "Elites ... always drop a Rare+ item". Floor of the rarity rolled for that drop.
const ELITE_DROP_MIN_RARITY := ItemInstance.Rarity.RARE
const DEATH_FALLBACK_TIME := 1.5
const REPATH_DISTANCE := 8.0
## Minimum seconds between two NavigationServer2D path recomputes.
const REPATH_INTERVAL := 0.3
## Beyond this distance to the nearest target the AI idles (cheap off-screen cull).
const AI_CULL_DISTANCE := 640.0
## Minimum seconds between two "who am I chasing" scans. Retargeting is not a per-frame
## decision — forty enemies each walking the player group every frame is forty array
## allocations a frame for an answer that changes once a second at most. An invalid or dying
## target still forces an immediate rescan.
const RETARGET_INTERVAL := 0.2
## Seconds a line-of-sight answer is reused for, and how far the probed point may move before
## the cached answer is thrown away.
const LOS_CACHE_TIME := 0.1
const LOS_CACHE_TOLERANCE := 8.0
## Seconds between two "has the navigation map baked yet" probes. The answer latches once it
## is true: a map does not lose its regions while an enemy lives.
const NAV_READY_INTERVAL := 0.5
## attack_range at or below this counts as a melee reach for the windup tell.
const MELEE_TELEGRAPH_CAP := 32.0
## Gap (px) between the health bar and the "!" that pops above it, so a waking enemy that is
## also hurt shows two readable marks instead of one stack.
const MARK_GAP := 6.0
const DEFAULT_TELEGRAPH_RADIUS := 16.0

## Physics frame `_enemy_cache` was filled on.
static var _enemy_cache_frame: int = -1
## The "enemy" group as of that frame, shared by every instance. Separation, ally scans and
## converted-enemy targeting all walk this list; without the cache each of forty enemies
## allocated its own copy of the same array every frame.
static var _enemy_cache: Array[Node] = []

var def: EnemyDef
var floor_index: int = 0
## Deterministic stream for this enemy's rolls (loot, spread, summons). Set via `setup()`.
var rng: RandomNumberGenerator
var state: State = State.IDLE
var state_time: float = 0.0
var target: Node2D
## Has this enemy noticed the player yet, and for how much longer does it believe it.
var awareness := EnemyAwareness.new()
## The leashed in-place drift that keeps an enemy holding its post from reading as a statue.
var idle := EnemyIdle.new()
## Where it was posted. A settled enemy walks back here instead of stopping wherever the
## chase ended, so a floor does not slowly drain into its corridors.
var home_position: Vector2 = Vector2.ZERO
## Id of the room this enemy belongs to (-1 for one that belongs to no room): the player
## entering that room wakes it even with no line of sight.
var room_id: int = -1
var is_converted: bool = false
## The floor's music mood (docs §10.2, `GenParams.sight_scale/cadence_scale/loot_scale`):
## multipliers on the def's sight range, attack cooldown and gold. 1.0 until `FloorPopulator`
## says otherwise, so an enemy spawned outside a floor behaves exactly as its def says.
var mood_sight: float = 1.0
var mood_cadence: float = 1.0
var mood_loot: float = 1.0
## Hovers over PIT areas (queried by src/traps/pit.gd). Set from `def.ignores_pits`.
var floats: bool = false
## Velocity the current state wants this frame (before separation/knockback).
var desired_velocity: Vector2 = Vector2.ZERO
## Attack helper currently driving the ATTACK state (may be null for instant attacks).
var current_attack: EnemyAttack

## False until the first physics frame has confirmed where this enemy actually stands.
var _home_latched: bool = false
var _attack_cooldown_left: float = 0.0
var _hitstop_left: int = 0
var _convert_left: float = 0.0
var _hit_tween: Tween
var _def_applied: bool = false
var _death_freed: bool = false
var _repath_left: float = 0.0
var _retarget_left: float = 0.0
var _nav_ready_latched: bool = false
var _nav_check_left: float = 0.0
var _los_left: float = 0.0
var _los_point: Vector2 = Vector2.INF
var _los_value: bool = false
var _ray_query: PhysicsRayQueryParameters2D
var _feel: GameFeel
var _fx: FxPool
## Dark rim behind the sprite. Enemies pile on top of each other and on the player, and a
## flashed sprite has no edges of its own; the rim is what keeps the pack countable.
var _outline: SpriteOutline

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var nav_agent: NavigationAgent2D = $NavAgent
@onready var telegraph: Telegraph = $Telegraph
@onready var death_burst: CPUParticles2D = $DeathBurst
@onready var hp_bar: EnemyHpBar = $HpBar
@onready var alert_mark: AlertMark = $AlertMark
@onready var body_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	team = Layers.Team.ENEMY
	super._ready()
	add_to_group(&"enemy")
	_feel = GameFeel.instance(get_tree())
	_fx = FxPool.instance(get_tree())
	if rng == null:
		rng = _derive_rng(null, def, floor_index)
	if def != null and not _def_applied:
		_apply_def()
	_setup_outline()
	home_position = global_position
	room_id = _resolve_room_id()
	EventBus.room_entered.connect(_on_room_entered)
	health.damaged.connect(_on_damaged_fx)
	health.damaged.connect(_on_damaged_wake)
	health.hp_changed.connect(_on_hp_changed)
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	sprite.animation_finished.connect(_on_animation_finished)
	_enter_state(State.IDLE)
	EventBus.enemy_spawned.emit(self)


## Adds (or re-finds) the silhouette rim and tints it from the live palette.
func _setup_outline() -> void:
	_outline = get_node_or_null("Outline") as SpriteOutline
	if _outline == null:
		_outline = SpriteOutline.new()
		_outline.name = "Outline"
		add_child(_outline)
	_outline.source = sprite
	_outline.set_tint(outline_tint())
	# Draw order, not z: the rim sits at z 0 like the tile layers and gets behind the body by
	# being an earlier child than it.
	move_child(_outline, 0)
	EventBus.palette_changed.connect(_on_outline_palette_changed)


func _on_outline_palette_changed(_palette: ThemePalette) -> void:
	if _outline != null:
		_outline.set_tint(outline_tint())


## Rim colour: the palette's darkest ink at most of full alpha. Theme-derived, so a rim on
## gruvbox is gruvbox's ink rather than a hard-coded black bolted onto every theme (docs §3).
static func outline_tint() -> Color:
	var palette := Desktop.palette if Desktop != null else null
	var ink := palette.outline_color() if palette != null else Color.BLACK
	ink.a = 0.8
	return ink


## Dust colour for an impact puff. Pure white read as a flashbang over a dark crypt: a dozen
## blown-out dots at FX depth sat on top of every sprite in the scrum, which is most of what
## made the pile unreadable. The theme's dim text tone is already guarded against every
## surface, so it reads as dust on any floor and still changes with the theme.
static func impact_tint() -> Color:
	var palette := Desktop.palette if Desktop != null else null
	if palette == null:
		return Color(0.8, 0.8, 0.8, 0.9)
	var tint := palette.get_color(&"text_dim")
	tint.a = 0.9
	return tint


## Configures numbers from the def. Safe to call before or after entering the tree.
func setup(enemy_def: EnemyDef, floor_idx: int, stream: RandomNumberGenerator = null) -> void:
	def = enemy_def
	floor_index = floor_idx
	rng = _derive_rng(stream, enemy_def, floor_idx)
	_def_applied = false
	if is_node_ready():
		_apply_def()


## Per-enemy generator. Derived from the caller's stream when given (so the shared spawn
## stream is advanced exactly once per enemy), otherwise seeded from the def/floor/position so
## loot stays a pure function of the run seed even when a caller forgets to pass a stream.
func _derive_rng(
	stream: RandomNumberGenerator, enemy_def: EnemyDef, floor_idx: int
) -> RandomNumberGenerator:
	var derived := RandomNumberGenerator.new()
	if stream != null:
		derived.seed = stream.randi()
		return derived
	var id_text := String(enemy_def.id) if enemy_def != null else "enemy"
	derived.seed = hash([id_text, floor_idx, position.x, position.y])
	return derived


func _apply_def() -> void:
	_def_applied = true
	stats.set_base(&"max_hp", def.scaled_hp(floor_index))
	stats.set_base(&"move_speed", def.move_speed)
	stats.set_base(&"armor", def.armor)
	knockback_resistance = def.knockback_resistance
	floats = def.ignores_pits
	var circle := CircleShape2D.new()
	circle.radius = def.body_radius
	body_shape.shape = circle
	var hurt_shape := hurtbox.get_node_or_null("HurtShape") as CollisionShape2D
	if hurt_shape != null:
		var rect := RectangleShape2D.new()
		rect.size = def.hurtbox_size
		hurt_shape.shape = rect
	if def.texture != null:
		sprite.sprite_frames = build_frames(def.texture, def.sprite_size)
		sprite.offset = Vector2(0.0, -def.sprite_size * 0.5 + 4.0)
	var heavy := def.is_elite or def.is_boss
	hp_bar.configure(def.sprite_size, heavy)
	hp_bar.set_fraction(1.0)
	if alert_mark != null:
		alert_mark.set_anchor(hp_bar.position.y - MARK_GAP)
	_configure_awareness()
	death_burst.scale_amount_max = 2.5 if def.sprite_size >= 32 else 1.8
	death_burst.amount = death_burst_count()
	_play(&"idle")


## Builds SpriteFrames from a 4-column sheet whose rows follow `ANIMS`.
static func build_frames(texture: Texture2D, size: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var cols := maxi(1, texture.get_width() / size)
	var rows := maxi(1, texture.get_height() / size)
	for anim_name: StringName in ANIMS.keys():
		var spec: Array = ANIMS[anim_name]
		var row: int = mini(int(spec[0]), rows - 1)
		var count: int = mini(int(spec[1]), cols)
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, float(spec[2]))
		frames.set_animation_loop(anim_name, bool(spec[3]))
		for i in range(count):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * size, row * size, size, size)
			frames.add_frame(anim_name, atlas)
	return frames


## Base damage for this enemy at the current floor.
func base_damage() -> float:
	return def.scaled_damage(floor_index) if def != null else 8.0


func _physics_process(delta: float) -> void:
	if state == State.DEAD or def == null:
		return
	if not _home_latched:
		# Not in `_ready`: `PhysicsFlush.add_child_at` writes the world position *after* the
		# insertion, so a summon or a room pack reads its own origin as (0, 0) in `_ready` and
		# would walk to the corner of the floor the first time it settled.
		_home_latched = true
		home_position = global_position
	if _hitstop_left > 0:
		_hitstop_left -= 1
		if _hitstop_left == 0:
			sprite.speed_scale = 1.0
		return
	state_time += delta
	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left -= delta
	if _convert_left > 0.0:
		_convert_left -= delta
		if _convert_left <= 0.0:
			convert_team(Layers.Team.ENEMY, 0.0)
	if _repath_left > 0.0:
		_repath_left -= delta
	if _retarget_left > 0.0:
		_retarget_left -= delta
	if _nav_check_left > 0.0:
		_nav_check_left -= delta
	if _los_left > 0.0:
		_los_left -= delta
	_update_target()
	_update_awareness(delta)
	if not awareness.is_awake() and (state == State.IDLE or state == State.APPROACH):
		_unaware_process(delta)
		return
	if _is_dormant():
		desired_velocity = Vector2.ZERO
		_play(&"idle")
		_move(Vector2.ZERO, delta)
		return
	if status.is_stunned() and state != State.STUNNED:
		_enter_state(State.STUNNED)
	desired_velocity = Vector2.ZERO
	_state_process(delta)
	_apply_movement(delta)
	_update_animation()


# --- awareness -----------------------------------------------------------------------------


## Points `awareness` at the shared profile and this enemy's own sight range. Called from
## `_apply_def`, so a def swapped in after spawn re-arms it.
func _configure_awareness() -> void:
	var profile := AwarenessProfile.shared()
	var sight := profile.sight_range
	var always_awake := false
	if def != null:
		sight = profile.sight_for(def.attack_range, def.sight_range)
		# A boss is the room. It has nothing to notice and nowhere to settle back to.
		always_awake = def.is_boss
	# The music mood, never below the def's own reach: a ranged enemy does not sleep inside it.
	var own_reach := def.attack_range * 1.1 if def != null else 0.0
	sight = maxf(sight * mood_sight, own_reach)
	awareness.configure(profile, sight, always_awake)


## Sets the floor's music mood (see `mood_sight`); re-arms the awareness so it reaches sight.
func set_mood(sight_scale: float, cadence_scale: float, loot_scale: float) -> void:
	mood_sight = maxf(sight_scale, 0.1)
	mood_cadence = maxf(cadence_scale, 0.1)
	mood_loot = maxf(loot_scale, 0.0)
	if def != null:
		_configure_awareness()


## Seconds between this enemy's attacks: the def's cooldown under the floor's music mood.
func attack_cooldown() -> float:
	return def.attack_cooldown * mood_cadence if def != null else 0.0


## Ticks the awareness clocks and, when a probe is due, feeds it one distance and one
## (cached) line-of-sight answer. Probing on an interval rather than per frame is what keeps
## this cheaper than the chase it replaced: a sleeping enemy costs one raycast every
## `probe_interval`, and only while a target is within the AI cull distance at all.
func _update_awareness(delta: float) -> void:
	if awareness.tick(delta):
		_on_woken()
	if not awareness.due_for_probe(delta):
		return
	if not is_instance_valid(target):
		awareness.perceive(INF, false)
		return
	var dist := target.global_position.distance_to(global_position)
	if dist > AI_CULL_DISTANCE:
		awareness.perceive(dist, false)
		return
	# The raycast is only worth paying for inside the distance at which the answer could
	# change anything; `and` short-circuits, so an enemy with the player far across the floor
	# probes for free.
	var in_reach := dist <= awareness.profile.forget_range(awareness.sight)
	if awareness.perceive(dist, in_reach and has_line_of_sight(target.global_position)):
		_on_woken()


## Wakes this enemy outright: the player walked into its room, hit it, or a caller said so.
## Safe to call on an enemy that is already awake (it refreshes the chase instead).
func alert() -> void:
	if awareness.alert():
		_on_woken()


## True while this enemy is at its post and has noticed nothing.
func is_asleep() -> bool:
	return not awareness.is_awake()


## The moment it notices: it turns toward whoever it spotted, the "!" pops, and the word goes
## out to the pack. The turn matters as much as the mark — a 16 px figure that flips to face
## you is readable at a glance from across a room, where a two-pixel glyph is not.
func _on_woken() -> void:
	if is_instance_valid(target):
		face(target.global_position)
	_show_alert_mark()
	_wake_allies()


func _show_alert_mark() -> void:
	if alert_mark == null or state == State.DEAD:
		return
	alert_mark.show_for(awareness.profile.mark_seconds)


## Passes the wake-up to sleeping neighbours, which arrive a beat later so a pack turns as a
## ripple. `nudge_from_ally` refuses an enemy that is already awake or already nudged, so this
## cannot loop between two of them.
func _wake_allies() -> void:
	var radius := awareness.profile.ally_wake_radius
	if radius <= 0.0:
		return
	for ally: EnemyBase in nearby_allies(radius):
		ally.awareness.nudge_from_ally()


## Room this enemy belongs to: the id the populator tagged it with, else the room it was
## parented under. -1 for a summon dropped straight onto the floor.
func _resolve_room_id() -> int:
	if has_meta(&"pack_room"):
		return int(get_meta(&"pack_room"))
	var room := get_parent() as RoomNode
	return room.id if room != null else -1


func _on_room_entered(entered_room: int) -> void:
	if room_id < 0 or entered_room != room_id or state == State.DEAD:
		return
	alert()


## A hit always wakes the thing it hit, and is loud enough that the neighbours hear it too.
func _on_damaged_wake(_info: DamageInfo) -> void:
	if state == State.DEAD or health.is_dead():
		return
	alert()
	_wake_allies()


## What an unnoticed enemy does instead of chasing: it holds its post. `EnemyIdle` ambles it a
## few px around home and stands about, so a room reads as occupied rather than as statues, and
## walks it back if something dragged it off. The drift is leashed to the post and is never
## told where the player is, so this cannot become the pre-sighting chase the owner rejected.
func _unaware_process(delta: float) -> void:
	if state != State.IDLE:
		_enter_state(State.IDLE)
	var post := idle.tick(delta, global_position, home_position, awareness.profile)
	desired_velocity = Vector2.ZERO
	if post != EnemyIdle.HOLD:
		desired_velocity = steer_toward(post) * effective_speed() * idle.speed_scale
	if desired_velocity == Vector2.ZERO:
		_play(&"idle")
		_move(Vector2.ZERO, delta)
		return
	_apply_movement(delta)
	_update_animation()


# --- state machine -------------------------------------------------------------------------


func _enter_state(new_state: State) -> void:
	if state == State.DEAD:
		return
	var previous := state
	state = new_state
	state_time = 0.0
	match new_state:
		State.IDLE:
			_play(&"idle")
		State.APPROACH:
			_play(&"move")
		State.WINDUP:
			if is_instance_valid(target):
				face(target.global_position)
			telegraph.flash(def.windup_time, telegraph_radius())
			_play(&"windup")
		State.ATTACK:
			telegraph.cancel()
			_play(&"attack")
			attack_started.emit()
			_perform_attack()
		State.RECOVER:
			if current_attack != null and current_attack.running:
				current_attack.stop()
			current_attack = null
			_attack_cooldown_left = attack_cooldown()
			_play(&"idle")
		State.STUNNED:
			telegraph.cancel()
			if current_attack != null and current_attack.running:
				current_attack.stop()
			current_attack = null
			_play(&"hurt")
		State.DEAD:
			telegraph.cancel()
			if current_attack != null and current_attack.running:
				current_attack.stop()
			current_attack = null
	_on_state_entered(new_state, previous)
	state_changed.emit(previous, new_state)


func _state_process(delta: float) -> void:
	match state:
		State.IDLE:
			if is_instance_valid(target):
				_enter_state(State.APPROACH)
		State.APPROACH:
			if not is_instance_valid(target):
				_enter_state(State.IDLE)
			else:
				_approach_process(delta)
		State.WINDUP:
			desired_velocity = _windup_velocity(delta)
			if state_time >= def.windup_time:
				_enter_state(State.ATTACK)
		State.ATTACK:
			_attack_process(delta)
			if state_time >= def.attack_time and _attack_finished():
				_enter_state(State.RECOVER)
		State.RECOVER:
			desired_velocity = _recover_velocity(delta)
			if state_time >= def.recover_time:
				_enter_state(State.APPROACH if is_instance_valid(target) else State.IDLE)
		State.STUNNED:
			if not status.is_stunned():
				_enter_state(State.APPROACH if is_instance_valid(target) else State.IDLE)


## Radius (px) of the windup tell. `attack_range` is an aggro/commit distance, so ranged
## enemies get a small ring around the body instead of a misleading area-sized one.
func telegraph_radius() -> float:
	if def == null:
		return DEFAULT_TELEGRAPH_RADIUS
	if def.attack_range <= MELEE_TELEGRAPH_CAP:
		return maxf(def.attack_range, def.body_radius * 2.0)
	return maxf(def.body_radius * 2.5, 10.0)


## True when nothing worth chasing is close enough to justify running the AI this frame.
func _is_dormant() -> bool:
	if state != State.IDLE and state != State.APPROACH:
		return false
	if not is_instance_valid(target):
		return state == State.IDLE
	var cull := AI_CULL_DISTANCE * AI_CULL_DISTANCE
	return target.global_position.distance_squared_to(global_position) > cull


## Default chase/kite behaviour. Override for exotic movement (dashes, teleports).
func _approach_process(_delta: float) -> void:
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	if can_start_attack(dist):
		_enter_state(State.WINDUP)
		return
	var speed := effective_speed()
	if def.retreat_when_close and dist < def.preferred_range * 0.75:
		desired_velocity = -to_target.normalized() * speed
		face(target.global_position)
	elif def.preferred_range > 0.0 and dist <= def.preferred_range and dist <= def.attack_range:
		if has_line_of_sight(target.global_position):
			desired_velocity = Vector2.ZERO
			face(target.global_position)
		else:
			desired_velocity = steer_toward(target.global_position) * speed
	else:
		desired_velocity = steer_toward(target.global_position) * speed


## True when an attack may begin against a target `dist` px away.
func can_start_attack(dist: float) -> bool:
	if _attack_cooldown_left > 0.0 or not can_act():
		return false
	if dist > def.attack_range:
		return false
	return dist <= Layers.TILE * 1.5 or has_line_of_sight(target.global_position)


## Override: launch the attack. Use `run_attack()` with a helper or spawn things directly.
func _perform_attack() -> void:
	pass


## Called every frame in ATTACK. Default: let the running attack helper drive velocity.
func _attack_process(delta: float) -> void:
	if current_attack != null and current_attack.running:
		desired_velocity = current_attack.tick(delta)


## ATTACK ends once `def.attack_time` elapsed and this returns true.
func _attack_finished() -> bool:
	return current_attack == null or not current_attack.running


## Velocity during windup (default: stand still).
func _windup_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO


## Velocity during recovery (default: stand still).
func _recover_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO


## Hook for subclasses on every state change.
func _on_state_entered(_new_state: State, _previous: State) -> void:
	pass


## Starts an attack helper and makes it the current attack.
func run_attack(attack: EnemyAttack, target_pos: Vector2) -> void:
	current_attack = attack
	attack.start(target_pos)


## Registers an attack helper node under this enemy.
func add_attack(attack: EnemyAttack) -> EnemyAttack:
	attack.enemy = self
	add_child(attack)
	return attack


# --- targeting & movement -----------------------------------------------------------------


func _update_target() -> void:
	if status.is_taunted():
		var taunter := status.taunt_source()
		if is_instance_valid(taunter):
			target = taunter
			_retarget_left = 0.0
			# Being taunted is being noticed at: an enemy cannot be pulled onto a target and
			# then stand there because it has not spotted anybody yet.
			alert()
			return
	if _retarget_left > 0.0 and _target_still_good():
		return
	_retarget_left = RETARGET_INTERVAL
	if is_converted:
		target = _nearest_in_group(&"enemy", true)
	else:
		target = _nearest_in_group(&"player", false)


## True when the current target is still worth keeping until the next scheduled scan.
func _target_still_good() -> bool:
	if not is_instance_valid(target):
		return false
	var entity := target as Entity
	return entity == null or (not entity.is_dying and entity.team != team)


func _nearest_in_group(group: StringName, exclude_self: bool) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for node: Node in get_tree().get_nodes_in_group(group):
		var n := node as Node2D
		if n == null or (exclude_self and n == self) or not is_instance_valid(n):
			continue
		if n is Entity and ((n as Entity).is_dying or (n as Entity).team == team):
			continue
		var d := n.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## Unit direction toward `pos`: direct when close with line of sight, else along the nav path.
func steer_toward(pos: Vector2) -> Vector2:
	var direct := pos - global_position
	if direct.length_squared() < 1.0:
		return Vector2.ZERO
	if direct.length() <= DIRECT_STEER_DISTANCE and has_line_of_sight(pos):
		return direct.normalized()
	if _repath_left <= 0.0 and nav_agent.target_position.distance_to(pos) > REPATH_DISTANCE:
		nav_agent.target_position = pos
		_repath_left = REPATH_INTERVAL
	if nav_ready() and not nav_agent.is_navigation_finished():
		var next := nav_agent.get_next_path_position()
		var step := next - global_position
		if step.length_squared() > 0.25:
			return step.normalized()
	return direct.normalized()


## True when the navigation map this agent uses has regions and was synced at least once.
func nav_ready() -> bool:
	if _nav_ready_latched:
		return true
	var map := nav_agent.get_navigation_map()
	# Cheap and allocation-free, so it is asked every time: an enemy must start pathing on the
	# frame the region finishes baking, not half a second later.
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return false
	if _nav_check_left > 0.0:
		return false
	_nav_check_left = NAV_READY_INTERVAL
	# `map_get_regions` allocates an array. Latching means each enemy pays for it once instead
	# of twice a frame for its whole life (`steer_toward` and `_apply_movement` both ask).
	_nav_ready_latched = not NavigationServer2D.map_get_regions(map).is_empty()
	return _nav_ready_latched


## Raycast on WORLD from this enemy to `pos`. The answer is cached for `LOS_CACHE_TIME` while
## the probed point stays within `LOS_CACHE_TOLERANCE`, and the query object is built once per
## enemy: approach, attack-gating and steering all ask this question in the same frame.
func has_line_of_sight(pos: Vector2) -> bool:
	var tolerance := LOS_CACHE_TOLERANCE * LOS_CACHE_TOLERANCE
	if _los_left > 0.0 and _los_point.distance_squared_to(pos) <= tolerance:
		return _los_value
	var space := get_world_2d().direct_space_state
	if space == null:
		return true
	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters2D.create(
			global_position, pos, Layers.WORLD, [get_rid()]
		)
	else:
		_ray_query.from = global_position
		_ray_query.to = pos
	_los_point = pos
	_los_left = LOS_CACHE_TIME
	_los_value = space.intersect_ray(_ray_query).is_empty()
	return _los_value


## Nearest navigable point to `pos` (falls back to `pos` without a baked map).
func walkable_point(pos: Vector2) -> Vector2:
	if not nav_ready():
		return pos
	return NavigationServer2D.map_get_closest_point(nav_agent.get_navigation_map(), pos)


## The "enemy" group as of this physics frame, shared by every enemy instead of copied per
## instance. Entries may have been freed since the scan, so callers must validate.
static func enemies_this_frame(tree: SceneTree) -> Array[Node]:
	if tree == null:
		return []
	var frame := Engine.get_physics_frames()
	if frame != _enemy_cache_frame:
		_enemy_cache_frame = frame
		_enemy_cache = tree.get_nodes_in_group(&"enemy")
	return _enemy_cache


func _separation() -> Vector2:
	var push := Vector2.ZERO
	var radius_sq := SEPARATION_RADIUS * SEPARATION_RADIUS
	for node: Node in enemies_this_frame(get_tree()):
		# Validity before the cast, not after: the frame cache can outlive an entry (a scan
		# taken this frame, an enemy freed since, anything that asks between two physics
		# frames), and casting a freed object is itself an error.
		if not is_instance_valid(node):
			continue
		var other := node as Node2D
		if other == null or other == self:
			continue
		var away := global_position - other.global_position
		var d_sq := away.length_squared()
		if d_sq >= radius_sq and d_sq >= 0.0001:
			continue
		var d := sqrt(d_sq)
		if d < 0.01:
			# Deterministic per-instance nudge: the loot stream must not be spent on cosmetics.
			away = Vector2.RIGHT.rotated(float(get_instance_id() % 997) / 997.0 * TAU)
			d = 0.01
		push += away / d * (1.0 - d / SEPARATION_RADIUS)
	return push * SEPARATION_STRENGTH


func _apply_movement(delta: float) -> void:
	var v := desired_velocity
	var steering := state == State.APPROACH or state == State.IDLE or state == State.RECOVER
	if steering:
		v += _separation()
	if v.length_squared() > 1.0 and state != State.WINDUP:
		facing = v.normalized()
		sprite.flip_h = v.x < 0.0
	if steering and nav_ready() and nav_agent.avoidance_enabled:
		nav_agent.velocity = v
		return
	_move(v, delta)


func _move(v: Vector2, delta: float) -> void:
	velocity = v
	move_with_knockback(delta)
	if current_attack != null and current_attack.running:
		current_attack.after_move()


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if state == State.DEAD or _hitstop_left > 0:
		return
	_move(safe_velocity, get_physics_process_delta_time())


## Turns toward `pos` (sprite flip + facing vector).
func face(pos: Vector2) -> void:
	var d := pos - global_position
	if d.length_squared() > 0.01:
		facing = d.normalized()
		sprite.flip_h = d.x < 0.0


## Adds `node` next to this enemy in the tree at a world position (projectiles, walls, summons).
##
## The insertion is deferred while the physics server is flushing its queries, which is where
## every on-death effect runs: `Hitbox._on_area_signal` -> `Hurtbox.receive` ->
## `Health.take_damage` -> `Entity._on_died` -> `_die` -> `_on_death` is one synchronous call
## chain, and a collider inserted there has its `_ready` writes refused. Measured on one
## Dotfile Golem and one Balloon Clown killed through a real overlap: 39
## "Can't change this state while flushing queries" errors, and the clown's confetti came up
## `monitorable` where `Projectile._ready` had asked for the opposite. The golem's gremlins
## came out functionally the same either way - what the server refused for them was shape
## *flags* the node re-applies - so for that path the cost was the error storm and a collider
## built in a state nobody chose, not lost damage. Outside a flush the insertion stays
## synchronous, so a caller that reads the node straight back still can.
func spawn_sibling(node: Node2D, pos: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	# Anything an enemy spawns mid-fight is in that fight already: a golem's gremlins and a
	# clown car's clowns must not stand around waiting to notice the player who just split them.
	var spawned := node as EnemyBase
	if spawned != null:
		spawned.set_mood(mood_sight, mood_cadence, mood_loot)
		if awareness.is_awake():
			spawned.awareness.alert()
	PhysicsFlush.add_child_at(parent, node, pos)


## Enemies on the same team within `radius` px (self excluded).
func nearby_allies(radius: float) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	var radius_sq := radius * radius
	for node: Node in enemies_this_frame(get_tree()):
		if not is_instance_valid(node):
			continue
		var other := node as EnemyBase
		if other == null or other == self:
			continue
		if other.team != team or other.is_dying:
			continue
		if other.global_position.distance_squared_to(global_position) <= radius_sq:
			out.append(other)
	return out


## Floating enemies are not caught by pits (traps read the `floats` property, not this).
func ignores_pits() -> bool:
	return floats


# --- conversion (Hostile Takeover) ----------------------------------------------------------


## Hostile Takeover entry point: switches sides for `duration` seconds (0 = permanent).
## Pass Team.ENEMY to revert early. (Alias of `convert_team`; the bare name shadows a builtin.)
func convert(new_team: Layers.Team, duration: float) -> void:
	convert_team(new_team, duration)


## Switches sides for `duration` seconds (0 = permanent). Pass Team.ENEMY to revert.
func convert_team(new_team: Layers.Team, duration: float) -> void:
	is_converted = new_team != Layers.Team.ENEMY
	team = new_team
	collision_layer = Layers.PLAYER if new_team == Layers.Team.PLAYER else Layers.ENEMY
	hurtbox.team = new_team
	hurtbox.set_deferred(&"collision_layer", Layers.hurtbox_layer_for(new_team))
	if is_converted:
		remove_from_group(&"enemy")
		add_to_group(&"ally")
	else:
		remove_from_group(&"ally")
		add_to_group(&"enemy")
	_convert_left = duration if is_converted else 0.0
	target = null
	# A converted enemy is already in the fight: it has no post to hold and nothing to notice.
	awareness.never_sleeps = is_converted or (def != null and def.is_boss)
	awareness.alert()
	converted.emit(new_team)


# --- damage in ---------------------------------------------------------------------------------


## Called by EnemyHurtbox before Health applies `info`. Tinkerers ignore their own traps.
func modify_incoming(info: DamageInfo) -> void:
	if (
		info.has_tag(DamageInfo.TAG_TRAP)
		and def != null
		and def.faction == EnemyDef.Faction.TINKERERS
	):
		info.amount = 0.0
		return
	_modify_incoming(info)


## Override to reduce/redirect incoming damage (e.g. frontal shield).
func _modify_incoming(_info: DamageInfo) -> void:
	pass


## Direction from this enemy toward the attacker of `info` (falls back to knockback direction).
func incoming_direction(info: DamageInfo) -> Vector2:
	if is_instance_valid(info.source) and info.source != self:
		var d := info.source.global_position - global_position
		if d.length_squared() > 0.01:
			return d.normalized()
	if info.knockback.length_squared() > 0.01:
		return -info.knockback.normalized()
	return -facing


## Impact: the enemy's own frames freeze for a beat, the sprite flashes and squashes, and a
## pooled puff pops where it was hit. Frame count, flash strength (the `reduced_flash` setting)
## and the squash threshold all come from the shared `FeelProfile`.
func _on_damaged_fx(info: DamageInfo) -> void:
	if health.is_dead():
		return
	_hitstop_left = hit_freeze_frames(info.amount)
	sprite.speed_scale = 0.0
	if _hit_tween != null:
		_hit_tween.kill()
	var peak := _flash_peak()
	sprite.self_modulate = Color(peak, peak, peak, 1.0)
	# The rim is stamped only for the length of the flash: the sheet's own ink outline carries
	# the silhouette the rest of the time, and two rims made every enemy a black token.
	if _outline != null:
		_outline.flash_for(_flash_time())
	var squash := Vector2(1.3, 0.75) if info.amount < _heavy_damage() else Vector2(1.5, 0.6)
	sprite.scale = squash
	_hit_tween = create_tween().set_parallel(true)
	_hit_tween.tween_property(sprite, "self_modulate", Color.WHITE, _flash_time())
	(
		_hit_tween
		. tween_property(sprite, "scale", Vector2.ONE, 0.22)
		. set_trans(Tween.TRANS_ELASTIC)
		. set_ease(Tween.EASE_OUT)
	)
	if _fx != null:
		var light_hit := info.amount < _heavy_damage()
		var puff_count := _puff_count(light_hit)
		_fx.puff(global_position, impact_tint(), puff_count)


## Frames this enemy's own animation freezes for after a hit of `amount` (docs §6: 2-4).
func hit_freeze_frames(amount: float) -> int:
	if _feel == null:
		return 2
	return _feel.profile.hit_stop_frames(amount)


## Particles a death burst emits; big sprites get a bigger one.
func death_burst_count() -> int:
	var base := _feel.profile.death_burst_count if _feel != null else 16
	if def != null and def.sprite_size >= 32:
		return int(roundf(base * 1.5))
	return base


func _heavy_damage() -> float:
	return _feel.profile.heavy_damage if _feel != null else 25.0


func _flash_scale() -> float:
	return _feel.flash_scale() if _feel != null else 1.0


## Peak `self_modulate` multiplier for this hit's flash, claimed against the shared per-frame
## budget. Only the first couple of enemies hit on one frame bleach themselves; the rest still
## flash, quieter, so a cleave through a pack stays a pack instead of one white mass.
func _flash_peak() -> float:
	if _feel == null:
		return 2.3
	return _feel.flash_peak(_feel.claim_flash(1.0))


func _puff_count(light_hit: bool) -> int:
	if _feel == null:
		return 8 if light_hit else 11
	return _feel.profile.puff_count if light_hit else _feel.profile.puff_heavy_count


func _flash_time() -> float:
	return _feel.flash_time() if _feel != null else 0.12


## Every enemy carries a bar now, so the fraction is always kept current: the bar itself
## decides whether anyone can see it (`EnemyHpBar`, revealed by the first hit).
func _on_hp_changed(hp: float, max_hp: float) -> void:
	hp_bar.set_fraction(hp / max_hp if max_hp > 0.0 else 0.0)


# --- death ------------------------------------------------------------------------------------


func _die(killer: Node2D) -> void:
	_enter_state(State.DEAD)
	desired_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	hurtbox.set_deferred(&"monitorable", false)
	hurtbox.set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	nav_agent.avoidance_enabled = false
	hp_bar.hide_now()
	if alert_mark != null:
		alert_mark.clear()
	remove_from_group(&"enemy")
	remove_from_group(&"ally")
	if _hit_tween != null:
		_hit_tween.kill()
	sprite.speed_scale = 1.0
	sprite.self_modulate = Color.WHITE
	sprite.scale = Vector2.ONE
	_drop_loot()
	_on_death(killer)
	EventBus.enemy_died.emit(self, killer)
	# Anything may have happened inside that emission. A boss kill can end the run, and a room
	# clear can start the next floor; both reach `FloorRoot.clear_floor()`, which `remove_child`s
	# this enemy's whole branch *synchronously* before queueing it for deletion. This node is
	# then outside the tree with `get_tree()` null, so the death FX have nowhere to play and the
	# fallback timer below has no tree to be created in - `get_tree().create_timer(...)` on a
	# null tree was the crash. `Prop._break` makes the same check after its own emit; this is
	# that check, at the other end of the same signal.
	if not is_inside_tree():
		_finish_death()
		return
	death_burst.amount = death_burst_count()
	death_burst.restart()
	death_burst.emitting = true
	if _fx != null:
		_fx.puff(global_position, DangerTell.color(), death_burst_count(), 20.0)
	if _feel != null:
		_feel.add_trauma(_feel.profile.trauma_light * 0.5, 0.18)
	_play(&"death")
	_schedule_death_fallback()


## Frees the corpse `DEATH_FALLBACK_TIME` from now, for the sprite sheets whose death animation
## never reports finished. The timer belongs to the `SceneTree`, not to this node, so it is only
## ever created while there is a tree to create it in; the connection is dropped by the engine
## when this enemy is freed first, and `_finish_death` is idempotent either way.
func _schedule_death_fallback() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(DEATH_FALLBACK_TIME).timeout.connect(_finish_death, CONNECT_ONE_SHOT)


## Override for on-death effects (shrapnel, splitting). Runs before `enemy_died` is emitted.
func _on_death(_killer: Node2D) -> void:
	pass


func _drop_loot() -> void:
	if def == null:
		return
	var gold := rng.randi_range(def.gold_min, def.gold_max)
	gold = int(
		roundf(gold * (1.0 + GOLD_PER_FLOOR * floor_index) * gold_find_multiplier() * mood_loot)
	)
	if gold > 0:
		EventBus.spawn_pickup.emit(&"gold", global_position, gold)
	if rng.randf() < HEART_DROP_CHANCE:
		EventBus.spawn_pickup.emit(&"heart", global_position, HEART_HEAL)
	if def.is_elite:
		EventBus.spawn_pickup.emit(
			&"stat_orb", global_position, rng.randi_range(0, Stats.PRIMARY.size() - 1)
		)
		_drop_elite_item()


## Multiplier the player's `gold_find` secondary puts on a gold drop (docs §4.3: the
## Oligarch's Buyout is "+30% gold from enemies", and every `gold_find` affix rides the same
## stat). Applied here, at the drop site, so the roll itself is richer rather than the purse.
func gold_find_multiplier() -> float:
	var hero := _loot_owner()
	if hero == null or hero.stats == null:
		return 1.0
	return maxf(0.0, 1.0 + hero.stats.get_value(&"gold_find"))


## Nearest node in group "player" — the hero the drop is rolled for. Unlike
## `_nearest_in_group` this ignores teams, so a converted enemy still drops the player's loot.
func _loot_owner() -> Entity:
	if not is_inside_tree():
		return null
	var best: Entity = null
	var best_d := INF
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var hero := node as Entity
		if hero == null or not is_instance_valid(hero):
			continue
		var d := hero.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = hero
	return best


## Docs §7: an elite always drops a Rare-or-better item. The drop is an `ItemPickup`, which
## the player has to walk up to and interact with (it shows the comparison card first) — it
## never equips itself, because the guaranteed good item of the run must not be able to
## overwrite a build by being walked past.
##
## The rarity is still rolled (with the player's luck) but can never fall below Rare, and the
## slot is biased to the one the hero has empty or weakest, so the guaranteed drop is usually
## a slot they can actually use (the same rule item chests follow, docs §8).
func _drop_elite_item() -> void:
	var registry := ItemRegistry.load_default()
	var parent := get_parent()
	if registry == null or parent == null or not is_inside_tree():
		return
	var luck := 0.0
	var hero := _loot_owner()
	if hero != null and hero.stats != null:
		luck = hero.stats.get_value(&"luck")
	var rarity := maxi(
		int(ItemGenerator.roll_rarity(floor_index, rng, luck)), int(ELITE_DROP_MIN_RARITY)
	)
	var item := ItemGenerator.generate(
		registry, floor_index, rng, luck, elite_drop_slots(hero), rarity
	)
	if item != null:
		ItemPickup.drop(parent, item, global_position, rng)


## Slot filter for the elite drop: the hero's empty-or-weakest slot when they carry an
## Equipment, else no filter (any slot).
static func elite_drop_slots(hero: Entity) -> Array[int]:
	if hero == null:
		return []
	var gear := hero.get(&"equipment") as Equipment
	if gear == null:
		return []
	var out: Array[int] = [gear.weakest_slot()]
	return out


func _on_animation_finished() -> void:
	if state != State.DEAD or sprite.animation != &"death":
		return
	# `create_tween()` needs a tree. A floor torn down while the death animation was still
	# playing leaves this node outside one, and there is nothing left to fade out anyway.
	if not is_inside_tree():
		_finish_death()
		return
	var fade := create_tween()
	fade.tween_property(sprite, "modulate:a", 0.0, 0.2)
	fade.tween_callback(_finish_death)


func _finish_death() -> void:
	if _death_freed:
		return
	_death_freed = true
	queue_free()


# --- animation ---------------------------------------------------------------------------------


func _play(anim: StringName) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim):
		return
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)


func _update_animation() -> void:
	match state:
		State.WINDUP:
			# Same pulse rate and urgency ramp as the telegraph ring under it (and as every
			# trap tell), so "this will hurt" always looks and beats the same.
			var windup := def.windup_time if def != null else 0.4
			var pulse := DangerTell.pulse(state_time)
			var urgency := DangerTell.urgency(state_time, windup)
			sprite.modulate = Color.WHITE.lerp(
				telegraph.color, lerpf(0.25 + 0.45 * pulse, 0.85, urgency * 0.5)
			)
		State.APPROACH, State.IDLE, State.RECOVER:
			sprite.modulate = Color.WHITE
			_play(&"move" if desired_velocity.length_squared() > 4.0 else &"idle")
		_:
			sprite.modulate = Color.WHITE
