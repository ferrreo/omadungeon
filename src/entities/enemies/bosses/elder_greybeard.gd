## Floor 6 boss (greybeards). Three phases, everything telegraphed:
## 1 "Read The Manual" — lobbed tome volleys land in telegraphed circles, manpage hurlers join in.
## 2 "RTFM Beam" — a slow sweeping beam the player has to outrun, plus rows of kernel spikes that
##   rotate around the arena (the "rotating tiles" of docs §7.4).
## 3 "Beard Tentacles" — four tentacle hitboxes lash out on a rhythm, the beam speeds up and
##   beard wardens are summoned (their shields always face the player, see BeardWarden).
class_name ElderGreybeard
extends BossBase

## Display names of the three phases (index = phase - 1).
const PHASE_NAMES: Array[String] = ["Read The Manual", "RTFM Beam", "Beard Tentacles"]
const TENTACLE_COUNT := 4
const HAZARD_SPIKE := &"kernel_spike"
const ADDS_EARLY := &"manpage_hurler"
const ADDS_LATE := &"beard_warden"
const MELEE_TAGS: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
const BEAM_TAGS: Array[StringName] = [DamageInfo.TAG_ABILITY, DamageInfo.TAG_ARCANE]
const TOME_TAGS: Array[StringName] = [DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]

## True while the RTFM beam is live (phase 2+, after its warm-up).
var beam_active: bool = false
## World angle (radians) the beam currently points at.
var beam_angle: float = 0.0
## Sweep speed in radians/second (doubled-ish in phase 3).
var beam_speed: float = 0.0
## Rows of spikes emitted so far; drives the rotating pattern (tests/debug).
var spike_rows: int = 0
## Tome volleys thrown so far (tests/debug).
var volleys: int = 0
## Tentacle rhythms played so far (tests/debug).
var tentacle_strikes: int = 0
## The four tentacle hitboxes (children of the spinning tentacle root).
var tentacles: Array[Hitbox] = []

var _beam_pivot: Node2D
var _beam_hitbox: Hitbox
var _beam_visual: Line2D
var _tentacle_root: Node2D
var _summon_left: float = 0.0
var _spike_left: float = 0.0
var _tentacle_left: float = 0.0
var _tentacle_hold: float = 0.0


func _ready() -> void:
	super._ready()
	if def == null:
		return
	_build_beam()
	_build_tentacles()
	_reset_timers()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if def == null or state == State.DEAD or in_transition:
		return
	_update_beam(delta)
	_update_tentacles(delta)
	if not is_instance_valid(target):
		return
	_summon_left -= delta
	if _summon_left <= 0.0:
		_summon_left = def.param(&"summon_interval", 9.0)
		summon_wave()
	if phase >= 2:
		_spike_left -= delta
		if _spike_left <= 0.0:
			_spike_left = def.param(&"spike_interval", 3.2)
			spike_row()
	if phase >= 3:
		_tentacle_left -= delta
		if _tentacle_left <= 0.0:
			_tentacle_left = def.param(&"tentacle_interval", 2.8)
			tentacle_strike()


## Display name of a 1-based phase index.
func phase_name(index: int) -> String:
	return PHASE_NAMES[clampi(index - 1, 0, PHASE_NAMES.size() - 1)]


# --- phase 1: tome volley ---------------------------------------------------------------------


## The base state machine drives the volley: windup tell, then the tomes leave the lectern.
func _perform_attack() -> void:
	tome_volley()


## Lobs one volley of tomes. The first lands on the player's current tile, the rest spread
## around them; each impact is a danger-coloured circle for `volley_telegraph` seconds before
## its hitbox exists. Returns the impact points.
func tome_volley() -> Array[Vector2]:
	var spots: Array[Vector2] = []
	if def == null or state == State.DEAD or not is_instance_valid(target):
		return spots
	face(target.global_position)
	volleys += 1
	var count := def.param_int(&"volley_count", 3)
	var spread := def.param(&"volley_spread", 44.0)
	var radius := def.param(&"volley_radius", 18.0)
	var delay := def.param(&"volley_telegraph", 0.6)
	var damage := base_damage() * def.param(&"volley_damage_mult", 1.0)
	var knockback := def.param(&"volley_knockback", 140.0)
	var hit_time := def.param(&"volley_hit_time", 0.2)
	for i in range(count):
		var pos := target.global_position
		if i > 0:
			pos += Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
		pos = clamp_to_arena(pos)
		spots.append(pos)
		telegraph_arc(pos, radius, 0.0, TAU, delay, 2.0)
		var impact := Callable(self, &"_tome_impact").bind(pos, radius, damage, knockback, hit_time)
		_after(delay, impact)
	return spots


func _tome_impact(
	pos: Vector2, radius: float, damage: float, knockback: float, hit_time: float
) -> void:
	if state == State.DEAD:
		return
	var circle := CircleShape2D.new()
	circle.radius = radius
	var hitbox := _make_hitbox(circle, Vector2.ZERO, damage, knockback, TOME_TAGS)
	spawn_sibling(hitbox, pos)
	hitbox.activate(hit_time)
	EventBus.screen_shake.emit(2.0, 0.15)
	_after(hit_time + 0.25, Callable(hitbox, &"queue_free"))


# --- summons -----------------------------------------------------------------------------------


## Calls in the phase's adds (manpage hurlers, beard wardens from phase 3). Capped by
## `summon_cap`; the adds are cleaned up when the boss dies.
func summon_wave() -> Array[EnemyBase]:
	var defs := summon_pool()
	if defs.is_empty():
		return []
	return summon_adds(defs, def.param_int(&"summon_count", 2), def.param(&"summon_radius", 34.0))


## Defs the current phase summons from (falls back to every def listed in the .tres).
func summon_pool() -> Array[EnemyDef]:
	if def == null:
		return []
	var wanted := ADDS_LATE if phase >= 3 else ADDS_EARLY
	var out: Array[EnemyDef] = []
	for add_def: EnemyDef in def.summon_defs:
		if add_def != null and add_def.id == wanted:
			out.append(add_def)
	if out.is_empty():
		out.assign(def.summon_defs)
	return out


# --- phase 2: RTFM beam ------------------------------------------------------------------------


## Telegraphs the beam's starting line, then switches it on. No-op while it already burns.
func start_beam() -> void:
	if beam_active or def == null or state == State.DEAD:
		return
	beam_speed = def.param(&"beam_speed", 0.5)
	beam_angle = facing.angle()
	if is_instance_valid(target):
		beam_angle = (target.global_position - global_position).angle()
	_beam_pivot.rotation = beam_angle
	var warmup := def.param(&"beam_warmup", 0.8)
	var length := def.param(&"beam_length", 180.0)
	var tip := global_position + Vector2.from_angle(beam_angle) * length
	telegraph_line(global_position, tip, warmup, def.param(&"beam_width", 10.0))
	_after(warmup, Callable(self, &"_enable_beam"))


## Switches the beam off (phase transitions, death).
func stop_beam() -> void:
	beam_active = false
	if _beam_pivot != null:
		_beam_pivot.visible = false
	if _beam_hitbox != null:
		_beam_hitbox.deactivate()


func _enable_beam() -> void:
	if state == State.DEAD or in_transition or _beam_hitbox == null:
		return
	beam_active = true
	_beam_pivot.visible = true
	_beam_hitbox.team = team
	_beam_hitbox.collision_mask = Layers.hitbox_mask_for(team)
	_beam_hitbox.activate(0.0)


func _update_beam(delta: float) -> void:
	if not beam_active:
		return
	beam_angle = wrapf(beam_angle + beam_speed * delta, 0.0, TAU)
	_beam_pivot.rotation = beam_angle
	_beam_visual.default_color = danger_color()


func _build_beam() -> void:
	var length := def.param(&"beam_length", 180.0)
	var width := def.param(&"beam_width", 10.0)
	_beam_pivot = Node2D.new()
	_beam_pivot.name = "BeamPivot"
	_beam_pivot.visible = false
	add_child(_beam_pivot)
	_beam_visual = Line2D.new()
	_beam_visual.points = PackedVector2Array([Vector2(4.0, 0.0), Vector2(length, 0.0)])
	_beam_visual.width = width
	_beam_visual.default_color = danger_color()
	_beam_visual.z_index = -1
	_beam_pivot.add_child(_beam_visual)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, width)
	_beam_hitbox = _make_hitbox(
		rect,
		Vector2(length * 0.5, 0.0),
		base_damage() * def.param(&"beam_damage_mult", 0.7),
		def.param(&"beam_knockback", 90.0),
		BEAM_TAGS
	)
	_beam_hitbox.multi_hit_interval = def.param(&"beam_hit_interval", 0.6)
	_beam_pivot.add_child(_beam_hitbox)


# --- phase 2: rotating spike rows --------------------------------------------------------------


## Emits one row of kernel spikes across the arena; each call rotates the row by
## `spike_row_step` radians, so the floor pattern turns under the player. Returns the tiles.
func spike_row() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if def == null or state == State.DEAD:
		return positions
	var angle := float(spike_rows) * def.param(&"spike_row_step", PI / 4.0)
	var dir := Vector2.from_angle(angle)
	var count := def.param_int(&"spike_row_count", 7)
	var spacing := def.param(&"spike_row_spacing", float(Layers.TILE))
	var duration := def.param(&"spike_duration", 2.5)
	for i in range(count):
		var offset := float(i) - float(count - 1) * 0.5
		var pos := _snap_to_tile(clamp_to_arena(arena_center + dir * (offset * spacing)))
		positions.append(pos)
		EventBus.spawn_hazard.emit(HAZARD_SPIKE, pos, duration)
	spike_rows += 1
	return positions


func _snap_to_tile(pos: Vector2) -> Vector2:
	var tile := float(Layers.TILE)
	return (pos / tile).floor() * tile + Vector2.ONE * (tile * 0.5)


# --- phase 3: beard tentacles ------------------------------------------------------------------


## World angles of the four tentacles right now (tests/debug).
func tentacle_angles() -> Array[float]:
	var out: Array[float] = []
	if _tentacle_root == null:
		return out
	for i in range(TENTACLE_COUNT):
		out.append(_tentacle_root.rotation + TAU * float(i) / float(TENTACLE_COUNT))
	return out


## One beat of the tentacle rhythm: the ring turns a step, all four arms are telegraphed as
## danger-coloured lashes, then their hitboxes snap out together.
func tentacle_strike() -> Array[float]:
	if def == null or state == State.DEAD or _tentacle_root == null:
		return []
	_tentacle_root.rotation = wrapf(
		_tentacle_root.rotation + def.param(&"tentacle_step", PI / 6.0), 0.0, TAU
	)
	tentacle_strikes += 1
	var windup := def.param(&"tentacle_windup", 0.5)
	var reach := def.param(&"tentacle_reach", 56.0)
	var half_width := def.param(&"tentacle_width", 12.0) * 0.5
	var angles := tentacle_angles()
	for angle: float in angles:
		var dir := Vector2.from_angle(angle)
		var side := dir.orthogonal() * half_width
		var tip := global_position + dir * reach
		telegraph_polygon(
			PackedVector2Array(
				[global_position + side, tip + side, tip - side, global_position - side]
			),
			windup
		)
	_after(windup, Callable(self, &"_fire_tentacles"))
	return angles


func _fire_tentacles() -> void:
	if def == null or state == State.DEAD or in_transition:
		return
	var hit_time := def.param(&"tentacle_hit_time", 0.25)
	_tentacle_root.visible = true
	_tentacle_hold = hit_time
	for hitbox: Hitbox in tentacles:
		hitbox.team = team
		hitbox.collision_mask = Layers.hitbox_mask_for(team)
		hitbox.activate(hit_time)
	EventBus.screen_shake.emit(2.5, 0.2)


func _update_tentacles(delta: float) -> void:
	if _tentacle_root == null:
		return
	if _tentacle_hold > 0.0:
		_tentacle_hold -= delta
		if _tentacle_hold <= 0.0:
			_tentacle_root.visible = false
	elif phase >= 3:
		_tentacle_root.rotation = wrapf(
			_tentacle_root.rotation + def.param(&"tentacle_drift", 0.35) * delta, 0.0, TAU
		)


func _build_tentacles() -> void:
	_tentacle_root = Node2D.new()
	_tentacle_root.name = "Tentacles"
	_tentacle_root.visible = false
	add_child(_tentacle_root)
	var reach := def.param(&"tentacle_reach", 56.0)
	var width := def.param(&"tentacle_width", 12.0)
	var damage := base_damage() * def.param(&"tentacle_damage_mult", 0.9)
	var knockback := def.param(&"tentacle_knockback", 160.0)
	for i in range(TENTACLE_COUNT):
		var arm := Node2D.new()
		arm.name = "Tentacle%d" % i
		arm.rotation = TAU * float(i) / float(TENTACLE_COUNT)
		_tentacle_root.add_child(arm)
		var rect := RectangleShape2D.new()
		rect.size = Vector2(reach, width)
		var hitbox := _make_hitbox(rect, Vector2(reach * 0.5, 0.0), damage, knockback, MELEE_TAGS)
		arm.add_child(hitbox)
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2.ZERO, Vector2(reach, 0.0)])
		line.width = width * 0.7
		line.default_color = Color(0.85, 0.85, 0.85, 0.95)
		line.z_index = -1
		arm.add_child(line)
		tentacles.append(hitbox)


# --- phases / lifecycle ------------------------------------------------------------------------


func _on_transition_started(_next: int) -> void:
	stop_beam()
	_tentacle_hold = 0.0
	if _tentacle_root != null:
		_tentacle_root.visible = false
	for hitbox: Hitbox in tentacles:
		hitbox.deactivate()


func _on_phase_entered(new_phase: int) -> void:
	_reset_timers()
	EventBus.toast.emit("%s — %s" % [boss_name(), phase_name(new_phase)], 2.0)
	if new_phase >= 2:
		start_beam()
	if new_phase >= 3:
		beam_speed = def.param(&"beam_speed", 0.5) * def.param(&"beam_speed_mult", 1.8)
	summon_wave()


func _on_boss_death(_killer: Node2D) -> void:
	stop_beam()
	_tentacle_hold = 0.0
	if _tentacle_root != null:
		_tentacle_root.visible = false
	for hitbox: Hitbox in tentacles:
		hitbox.deactivate()


func _reset_timers() -> void:
	if def == null:
		return
	_summon_left = def.param(&"summon_interval", 9.0) * 0.35
	_spike_left = def.param(&"spike_interval", 3.2) * 0.5
	_tentacle_left = def.param(&"tentacle_interval", 2.8) * 0.5


# --- helpers -----------------------------------------------------------------------------------


## Hitbox owned by this boss: `shape` at `offset`, damage built through `make_damage()` so the
## boss' stats and crits apply. Inactive until `activate()`.
func _make_hitbox(
	shape: Shape2D, offset: Vector2, damage: float, knockback: float, tags: Array[StringName]
) -> Hitbox:
	var hitbox := Hitbox.new()
	hitbox.name = "BossHitbox"
	hitbox.team = team
	hitbox.source = self
	hitbox.damage = damage
	hitbox.knockback = knockback
	hitbox.tags = tags
	hitbox.damage_builder = Callable(self, &"_build_damage").bind(damage, knockback, tags)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = offset
	hitbox.add_child(col)
	return hitbox


func _build_damage(
	victim: Node2D, damage: float, knockback: float, tags: Array[StringName]
) -> DamageInfo:
	var dir := victim.global_position - global_position
	if dir.length_squared() < 0.01:
		dir = facing
	return make_damage(damage, tags, dir, knockback, rng)


## Runs `what` after `seconds` (one-shot scene timer; dies with the boss).
func _after(seconds: float, what: Callable) -> void:
	if not is_inside_tree():
		return
	get_tree().create_timer(maxf(0.01, seconds)).timeout.connect(what, CONNECT_ONE_SHOT)
