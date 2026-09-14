## Shared base for the three floor bosses. Adds to `EnemyBase`: health-gated phases with an
## invulnerable scream/shake transition between them, an `EventBus.boss_health_changed` feed
## for the HUD bar, arena bounds (set by RunManager or derived from the room), a capped summon
## helper that cleans its adds up on death, and telegraph shapes drawn in the theme `danger`
## colour before a hitbox goes live.
class_name BossBase
extends EnemyBase

## Emitted after a phase transition finished (1-based phase index).
signal phase_changed(phase: int)

## HP fractions at or below which the boss enters the next phase (100-66-33 by default).
const DEFAULT_THRESHOLDS: Array[float] = [0.66, 0.33]
## Fraction of its damage a boss gains per phase past the first (`phase_damage_step` in the
## def's `params`). A boss is meant to be a climax, not a long fight: the HP pools are small
## enough to die in twenty-odd seconds and every phase hits appreciably harder than the last.
const DEFAULT_PHASE_DAMAGE_STEP := 0.35
## Fraction by which the gap between attacks shrinks per phase past the first
## (`phase_speed_step`). Phase 3 of a three-phase boss attacks about twice as often as phase 1.
const DEFAULT_PHASE_SPEED_STEP := 0.25
const TRANSITION_TIME := 1.5
const TRANSITION_SHAKE := 7.0
const TRANSITION_TINT_ALPHA := 0.4
const DEFAULT_ARENA_RADIUS := 104.0
const DEFAULT_SUMMON_CAP := 4
const FALLBACK_DANGER := Color(0.9, 0.3, 0.3)
const TELEGRAPH_ARC_STEPS := 48

## 1-based phase index; 1 until the first threshold is crossed.
var phase: int = 1
var phase_thresholds: Array[float] = DEFAULT_THRESHOLDS.duplicate()
## True while the boss is mid-transition (invulnerable, no AI, no attacks).
var in_transition: bool = false
## True from `sleep_until_engaged()` until `engage()`: the boss idles at its spot across the
## arena and neither moves nor attacks. `BossArena` engages it when the player is well inside
## (docs 7.4); a hit engages it too, so it can never be sniped from the doorway for free.
var dormant: bool = false
var transition_time: float = TRANSITION_TIME
## Arena centre/radius in world px. `set_arena()` overrides the room-derived values.
var arena_center: Vector2 = Vector2.ZERO
var arena_radius: float = DEFAULT_ARENA_RADIUS
## Maximum adds alive at once (summons over the cap are dropped).
var summon_cap: int = DEFAULT_SUMMON_CAP
## Per-phase escalation, read from the def's `params` in `_ready()`.
var phase_damage_step: float = DEFAULT_PHASE_DAMAGE_STEP
var phase_speed_step: float = DEFAULT_PHASE_SPEED_STEP

var _summons: Array[EnemyBase] = []
var _transition_left: float = 0.0
var _next_phase: int = 1
var _arena_set: bool = false
var _telegraph_root: Node2D


func _ready() -> void:
	_telegraph_root = Node2D.new()
	_telegraph_root.name = "Telegraphs"
	_telegraph_root.top_level = true
	_telegraph_root.z_index = 1
	add_child(_telegraph_root)
	super._ready()
	if def != null:
		summon_cap = def.param_int(&"summon_cap", DEFAULT_SUMMON_CAP)
		phase_damage_step = def.param(&"phase_damage_step", DEFAULT_PHASE_DAMAGE_STEP)
		phase_speed_step = def.param(&"phase_speed_step", DEFAULT_PHASE_SPEED_STEP)
	if not _arena_set:
		_derive_arena()
	health.hp_changed.connect(_on_boss_hp_changed)
	_emit_health()


## Name shown on the boss health bar.
func boss_name() -> String:
	return def.display_name if def != null else "Boss"


## Number of phases this boss has (thresholds + 1).
func phase_count() -> int:
	return phase_thresholds.size() + 1


## Damage multiplier of `for_phase` (defaults to the phase the boss is in now): every phase
## past the first adds `phase_damage_step`.
func phase_damage_multiplier(for_phase: int = -1) -> float:
	var index := (phase if for_phase < 0 else for_phase) - 1
	return 1.0 + phase_damage_step * float(maxi(0, index))


## Multiplier on how *often* the boss attacks in `for_phase`: the recovery cooldown is divided
## by this, so phase 3 crowds the player instead of pausing politely between swings.
func phase_rate_multiplier(for_phase: int = -1) -> float:
	var index := (phase if for_phase < 0 else for_phase) - 1
	return 1.0 + phase_speed_step * float(maxi(0, index))


## Base damage including the current phase's escalation. Every hitbox a boss builds goes
## through `EnemyBase.base_damage()`, so overriding it here escalates the whole moveset.
func base_damage() -> float:
	return super.base_damage() * phase_damage_multiplier()


## Phase the given HP fraction belongs to (1-based).
func phase_for_fraction(value: float) -> int:
	var result := 1
	for threshold: float in phase_thresholds:
		if value <= threshold:
			result += 1
	return result


## Holds the boss still until `engage()`: no AI, no attacks, no phase changes.
func sleep_until_engaged() -> void:
	dormant = true


## Starts the fight. Safe to call on a boss that is already awake.
func engage() -> void:
	if not dormant:
		return
	dormant = false
	_on_engaged()


## Override: runs once when the arena wakes the boss (an opening move, a taunt).
func _on_engaged() -> void:
	pass


## RunManager (or a test) pins the arena the boss fights in.
func set_arena(center: Vector2, radius: float) -> void:
	arena_center = center
	arena_radius = maxf(24.0, radius)
	_arena_set = true


## Keeps `pos` inside the arena circle.
func clamp_to_arena(pos: Vector2) -> Vector2:
	var offset := pos - arena_center
	if offset.length() <= arena_radius:
		return pos
	return arena_center + offset.normalized() * arena_radius


func _derive_arena() -> void:
	arena_center = global_position
	arena_radius = def.param(&"arena_radius", DEFAULT_ARENA_RADIUS) if def != null else 0.0
	if arena_radius <= 0.0:
		arena_radius = DEFAULT_ARENA_RADIUS
	var room := get_parent() as RoomNode
	if room == null or room.data == null:
		return
	arena_center = room.data.center_world()
	var size := Vector2(room.data.rect.size) * float(Layers.TILE)
	arena_radius = maxf(32.0, minf(size.x, size.y) * 0.5 - float(Layers.TILE))


# --- phases -------------------------------------------------------------------------------


## Shortens the post-attack cooldown by the current phase's rate multiplier. Everything else
## about the state machine is `EnemyBase`'s.
func _enter_state(new_state: State) -> void:
	super._enter_state(new_state)
	if new_state == State.RECOVER:
		_attack_cooldown_left /= maxf(0.1, phase_rate_multiplier())


func _physics_process(delta: float) -> void:
	if dormant:
		velocity = Vector2.ZERO
		_play(&"idle")
		return
	if in_transition:
		_transition_left -= delta
		velocity = Vector2.ZERO
		move_with_knockback(delta)
		if _transition_left <= 0.0:
			_finish_transition()
		return
	super._physics_process(delta)


func _on_boss_hp_changed(hp: float, max_hp: float) -> void:
	engage()
	_emit_health()
	if state == State.DEAD or in_transition or hp <= 0.0 or max_hp <= 0.0:
		return
	var wanted := phase_for_fraction(hp / max_hp)
	if wanted > phase:
		_begin_transition(wanted)


func _emit_health() -> void:
	var fraction := health.fraction() if health != null else 1.0
	EventBus.boss_health_changed.emit(boss_name(), fraction, phase)


func _begin_transition(next_phase: int) -> void:
	in_transition = true
	_next_phase = mini(next_phase, phase_count())
	_transition_left = transition_time
	health.invulnerable = true
	telegraph.cancel()
	if current_attack != null and current_attack.running:
		current_attack.stop()
	current_attack = null
	_enter_state(State.IDLE)
	_scream()
	_on_transition_started(_next_phase)


## Scream + shake + palette-danger flash that sells the phase change.
func _scream() -> void:
	if has_node("/root/Audio"):
		Audio.play(&"boss_roar", global_position)
	EventBus.screen_shake.emit(TRANSITION_SHAKE, transition_time * 0.5)
	var tint := danger_color()
	tint.a = TRANSITION_TINT_ALPHA
	EventBus.screen_tint.emit(tint, transition_time * 0.6)
	var body := def.body_radius if def != null else 8.0
	telegraph.show_area(transition_time, maxf(24.0, body * 3.0))
	var flash := create_tween()
	flash.tween_property(sprite, "self_modulate", danger_color(), transition_time * 0.35)
	flash.tween_property(sprite, "self_modulate", Color.WHITE, transition_time * 0.35)


func _finish_transition() -> void:
	in_transition = false
	_transition_left = 0.0
	health.invulnerable = false
	phase = _next_phase
	_emit_health()
	_on_phase_entered(phase)
	phase_changed.emit(phase)


## Override: react to a new phase (new attacks, hazards, summon pool).
func _on_phase_entered(_new_phase: int) -> void:
	pass


## Override: runs when the transition starts (before the boss is invulnerable-idle).
func _on_transition_started(_next: int) -> void:
	pass


func can_act() -> bool:
	return super.can_act() and not in_transition and not dormant


# --- summons ------------------------------------------------------------------------------


## Adds alive right now (freed/dead ones are pruned).
func live_summons() -> Array[EnemyBase]:
	var alive: Array[EnemyBase] = []
	for add: EnemyBase in _summons:
		if is_instance_valid(add) and not add.is_dying:
			alive.append(add)
	_summons = alive
	return alive


## Spawns up to `count` adds from `defs` in a ring, never exceeding `summon_cap` alive.
## Positions are clamped to the arena and snapped to the navigation mesh. Returns the new adds.
func summon_adds(defs: Array[EnemyDef], count: int, ring_radius: float = 28.0) -> Array[EnemyBase]:
	var spawned: Array[EnemyBase] = []
	if defs.is_empty() or state == State.DEAD:
		return spawned
	var allowed := mini(count, summon_cap - live_summons().size())
	if allowed <= 0:
		return spawned
	var start_angle := rng.randf() * TAU
	for i in range(allowed):
		var add_def: EnemyDef = defs[rng.randi_range(0, defs.size() - 1)]
		var angle := start_angle + TAU * float(i) / float(allowed)
		var wanted := global_position + Vector2.from_angle(angle) * ring_radius
		var pos := walkable_point(clamp_to_arena(wanted))
		var add := EnemySpawner.instantiate(add_def, floor_index, pos, rng)
		if add == null:
			continue
		spawn_sibling(add, pos)
		add.knockback_velocity = Vector2.from_angle(angle) * 70.0
		_summons.append(add)
		spawned.append(add)
	return spawned


## Removes every add still alive (called when the boss dies so the arena empties with it).
func clear_summons() -> void:
	for add: EnemyBase in live_summons():
		add.queue_free()
	_summons.clear()


func _on_death(killer: Node2D) -> void:
	clear_summons()
	_clear_telegraphs()
	_emit_health()
	_on_boss_death(killer)


## Override instead of `_on_death` so summon cleanup always runs.
func _on_boss_death(_killer: Node2D) -> void:
	pass


# --- telegraphs ---------------------------------------------------------------------------


## Current theme danger colour (with a fallback before Desktop loaded a palette).
func danger_color() -> Color:
	if Desktop.palette == null:
		return FALLBACK_DANGER
	return Desktop.palette.get_color(&"danger")


## Draws a danger-coloured line in world space for `duration` seconds, then frees it.
func telegraph_line(from: Vector2, to: Vector2, duration: float, width: float = 3.0) -> Line2D:
	return telegraph_path(PackedVector2Array([from, to]), duration, width)


## Draws a danger-coloured arc (world space) of `arc` radians starting at `from_angle`.
func telegraph_arc(
	center: Vector2,
	radius: float,
	from_angle: float,
	arc: float,
	duration: float,
	width: float = 3.0
) -> Line2D:
	var points := PackedVector2Array()
	var steps := maxi(4, int(round(TELEGRAPH_ARC_STEPS * absf(arc) / TAU)))
	for i in range(steps + 1):
		var angle := from_angle + arc * float(i) / float(steps)
		points.append(center + Vector2.from_angle(angle) * radius)
	return telegraph_path(points, duration, width)


## Draws a danger-coloured polyline (world space) that fades and frees itself.
func telegraph_path(points: PackedVector2Array, duration: float, width: float = 3.0) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = danger_color()
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_add_telegraph(line, duration)
	return line


## Draws a filled danger-coloured polygon (world space) that fades and frees itself.
func telegraph_polygon(points: PackedVector2Array, duration: float) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = danger_color()
	_add_telegraph(poly, duration)
	return poly


func _add_telegraph(node: CanvasItem, duration: float) -> void:
	# The root is freed with the boss, and a telegraph raised after that has nowhere to go: the
	# `add_child` below would be a call on a freed instance, which is a segfault rather than an
	# error (`tests/unit/freed_instance_test.gd`). There was no check here at all.
	if not is_instance_valid(_telegraph_root):
		node.free()
		return
	node.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_telegraph_root.add_child(node)
	var half := maxf(0.05, duration * 0.5)
	var pulse := node.create_tween()
	pulse.tween_property(node, "modulate:a", 0.3, half).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(node, "modulate:a", 0.95, half).set_trans(Tween.TRANS_SINE)
	pulse.tween_callback(node.queue_free)


func _clear_telegraphs() -> void:
	if not is_instance_valid(_telegraph_root):
		return
	for child: Node in _telegraph_root.get_children():
		child.queue_free()
