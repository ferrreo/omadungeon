## Headless load benchmark for the design target in docs §13.4: the CPU/simulation cost of
## `PerfBudget.projectile_count` projectiles and `PerfBudget.enemy_count` enemies alive at
## once, which has to fit inside a sixty-frames-per-second frame.
##
## **Rendering is not in this measurement.** The run is headless: no frame is ever rasterised,
## so nothing here can support a claim about frames per second on any particular GPU. What it
## bounds is the script time the game spends per frame under the target load - a necessary
## condition for 60 fps and not a sufficient one.
##
## It drives the *real* game — `RunManager.new_run()` with `manage_scenes = false`, a real
## floor, real navigation, real enemies — then tops that floor up to the target load and holds
## it there for the whole measurement window.
##
## "frame" is the wall-clock cost of one simulated frame: the `_physics_process` phase plus
## the `_process` phase, each bracketed by a pair of marker nodes whose priorities put them
## outside every other node (-10000 / +10000). The engine's own `Performance.TIME_PROCESS` and
## `TIME_PHYSICS_PROCESS` monitors are NOT used: they are one-second averages (verified: the
## value only changes about once a second), so they can report neither a percentile nor a
## worst frame, and under a test runner they also count the harness. What the bracket cannot
## see is the physics *server* step, which no script can measure and no gameplay code owns.
##
##     var bench := PerfBench.new()
##     add_child(bench)
##     var report := await bench.run_load()
##     print(PerfBench.format_report(report))
class_name PerfBench
extends Node2D

## Seed every benchmark run uses, so two runs build the same floor.
const SEED := 90210
const CLASS_ID := &"fighter"
## Projectile speed/lifetime for the synthetic load: slow enough to stay in the room, short
## enough that the population churns instead of sitting still for the whole window.
const SHOT_SPEED := 90.0
const SHOT_LIFETIME := 1.5
## Radius (px) the synthetic shots are seeded in around the player.
const SHOT_SPREAD := 72.0
## Ring the topped-up enemies are placed in, around the player.
const ENEMY_RING_MIN := 48.0
const ENEMY_RING_MAX := 160.0
## Physics priorities of the bracket markers. Far outside anything the game uses, so every
## other node's `_physics_process` runs between them.
const MARK_FIRST := -10000
const MARK_LAST := 10000


## Records `Time.get_ticks_usec()` at the start of both phases. Two of them, one at either
## priority extreme, bracket every other node in the tree.
class FrameMark:
	extends Node
	var physics_usec: int = 0
	var idle_usec: int = 0

	func _init(priority: int) -> void:
		process_physics_priority = priority
		process_priority = priority

	func _process(_delta: float) -> void:
		idle_usec = Time.get_ticks_usec()

	func _physics_process(_delta: float) -> void:
		physics_usec = Time.get_ticks_usec()


var budget: PerfBudget = PerfBudget.load_default()
## Set false to measure the same load without the projectile pool (A/B comparison).
var pool_projectiles: bool = true
## Filled while `run_load()` samples; public so a caller can watch it live.
var sampler: FrameSampler = FrameSampler.new()

var _rng := RandomNumberGenerator.new()
var _shots: Array[Projectile] = []
var _restore_manage_scenes: bool = true
var _restore_offers: bool = true
var _arena: Node2D
var _mark_first: FrameMark
var _mark_last: FrameMark
var _hold_load: bool = false


func _init() -> void:
	_rng.seed = SEED


func _ready() -> void:
	_mark_first = FrameMark.new(MARK_FIRST)
	_mark_last = FrameMark.new(MARK_LAST)
	add_child(_mark_first)
	add_child(_mark_last)
	process_physics_priority = MARK_LAST - 1


## Keeps the population at the target for as long as the benchmark is holding load. Runs just
## before the closing marker, so its own cost is inside the measured step like everything else.
func _physics_process(_delta: float) -> void:
	if _hold_load:
		_top_up_shots()


## Builds the target load, measures it and tears it down. Returns the report dictionary.
func run_load() -> Dictionary:
	var tree := get_tree()
	# Warm up first: the very first run of a process builds the things that are *supposed* to
	# outlive a floor (the tree-level FX pool, audio player pools, registries). Counting those
	# against the baseline would report the opposite of a leak.
	await start_run()
	await teardown()
	var before := NodeCensus.take(tree)
	await start_run()
	await spawn_load()
	await _frames(budget.warmup_frames)
	sampler = FrameSampler.new(budget.measure_frames + 8)
	var physics_sampler := FrameSampler.new(budget.measure_frames + 8)
	var idle_sampler := FrameSampler.new(budget.measure_frames + 8)
	for i in range(budget.measure_frames):
		await tree.physics_frame
		var physics_s := float(_mark_last.physics_usec - _mark_first.physics_usec) / 1_000_000.0
		var idle_s := float(_mark_last.idle_usec - _mark_first.idle_usec) / 1_000_000.0
		physics_sampler.feed(physics_s)
		idle_sampler.feed(idle_s)
		sampler.feed(physics_s + idle_s)
	var peak := NodeCensus.take(tree)
	var report := {
		"frames": sampler.to_dict(),
		"physics_phase": physics_sampler.to_dict(),
		"idle_phase": idle_sampler.to_dict(),
		"projectiles": live_projectiles(),
		"enemies": NodeCensus.group_size(tree, &"enemy"),
		"nodes": int(peak["nodes"]),
		"orphans": int(peak["orphans"]),
		"pool_reused": Projectile.pool().reused,
		"pool_created": Projectile.pool().created,
		"budget_ms": budget.frame_budget_ms(),
		"over_budget_frames": sampler.over_budget(budget.frame_budget_ms()),
	}
	await teardown()
	# Node delta, not "leak": a tree-level pool (the FX emitters, the audio players) keeps its
	# high-water mark past a run end on purpose. `run_floor_cycles()` is the leak check.
	report["node_delta"] = int(NodeCensus.take(tree)["nodes"]) - int(before["nodes"])
	return report


## Starts the benchmark run without touching the current scene. The hero is made invulnerable
## and passive: a benchmark measures a steady load, and a dead or fighting player is neither.
func start_run() -> void:
	_restore_manage_scenes = RunManager.manage_scenes
	_restore_offers = RunManager.offer_starting_passive
	RunManager.manage_scenes = false
	RunManager.offer_starting_passive = false
	RunManager.new_run(SEED, CLASS_ID)
	await _frames(4)
	_arena = RunManager.floor_root()
	var live := RunManager.player()
	if live != null:
		live.input_enabled = false
		live.health.invulnerable = true


## Tops the live floor up to `budget.enemy_count` enemies and `budget.projectile_count` shots,
## then keeps it there until `teardown()`.
func spawn_load() -> void:
	_top_up_enemies()
	_top_up_shots()
	_hold_load = true
	await _frames(2)


## Builds and tears down `budget.floor_cycles` floors in a row, returning the census before,
## after and the diff between them plus how long each build took.
func run_floor_cycles() -> Dictionary:
	var tree := get_tree()
	await _frames(2)
	var before := NodeCensus.take(tree)
	await start_run()
	var build_sampler := FrameSampler.new(budget.floor_cycles + 2)
	for i in range(budget.floor_cycles - 1):
		var t0 := Time.get_ticks_usec()
		EventBus.floor_exit_requested.emit()
		build_sampler.feed(float(Time.get_ticks_usec() - t0) / 1_000_000.0)
		await _frames(4)
	await teardown()
	var after := NodeCensus.take(tree)
	return {
		"cycles": budget.floor_cycles,
		"before": before,
		"after": after,
		"diff": NodeCensus.diff(before, after),
		"build_ms": build_sampler.to_dict(),
	}


## Live projectiles the benchmark is keeping in the air.
func live_projectiles() -> int:
	var n := 0
	for shot: Projectile in _shots:
		if is_instance_valid(shot) and shot.is_inside_tree():
			n += 1
	return n


## Ends the run, frees the synthetic load and empties the pool.
func teardown() -> void:
	_hold_load = false
	for shot: Projectile in _shots:
		if is_instance_valid(shot):
			if shot.expired.is_connected(_on_shot_expired):
				shot.expired.disconnect(_on_shot_expired)
			shot.queue_free()
	_shots.clear()
	_arena = null
	if RunManager.is_run_active():
		RunManager.abandon_run()
	await _frames(4)
	Projectile.clear_pool()
	RunManager.manage_scenes = _restore_manage_scenes
	RunManager.offer_starting_passive = _restore_offers


## Report as text, ready to paste into a perf note.
static func format_report(report: Dictionary) -> String:
	var frames: Dictionary = report.get("frames", {})
	var physics: Dictionary = report.get("physics_phase", {})
	var idle: Dictionary = report.get("idle_phase", {})
	var lines: PackedStringArray = PackedStringArray()
	(
		lines
		. append(
			(
				"load: %d projectiles, %d enemies, %d nodes, %d orphans"
				% [
					report.get("projectiles", 0),
					report.get("enemies", 0),
					report.get("nodes", 0),
					report.get("orphans", 0),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"frame: avg %.2f ms  p95 %.2f ms  worst %.2f ms  (%.0f fps, %d/%d over %.2f ms)"
				% [
					frames.get("average_ms", 0.0),
					frames.get("p95_ms", 0.0),
					frames.get("worst_ms", 0.0),
					frames.get("average_fps", 0.0),
					report.get("over_budget_frames", 0),
					frames.get("frames", 0),
					report.get("budget_ms", 0.0),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"  physics phase avg %.2f ms p95 %.2f ms | idle phase avg %.2f ms p95 %.2f ms"
				% [
					physics.get("average_ms", 0.0),
					physics.get("p95_ms", 0.0),
					idle.get("average_ms", 0.0),
					idle.get("p95_ms", 0.0),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"pool: %d reused, %d created; node delta after teardown: %+d (tree pools keep theirs)"
				% [
					report.get("pool_reused", 0),
					report.get("pool_created", 0),
					report.get("node_delta", 0),
				]
			)
		)
	)
	return "\n".join(lines)


func _top_up_enemies() -> void:
	var tree := get_tree()
	var registry := RunManager.enemy_registry
	if registry == null or _arena == null or not is_instance_valid(_arena):
		return
	var defs := registry.candidates(0, false)
	if defs.is_empty():
		return
	var live := RunManager.player()
	var origin := live.global_position if live != null else Vector2.ZERO
	var guard := budget.enemy_count * 2
	while NodeCensus.group_size(tree, &"enemy") < budget.enemy_count and guard > 0:
		guard -= 1
		var def := defs[_rng.randi() % defs.size()]
		var away := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var pos := origin + away * _rng.randf_range(ENEMY_RING_MIN, ENEMY_RING_MAX)
		var enemy := EnemySpawner.instantiate(def, 0, pos, _rng)
		if enemy == null:
			return
		_arena.add_child(enemy)
		enemy.global_position = pos


func _top_up_shots() -> void:
	var i := 0
	while i < _shots.size():
		var shot := _shots[i]
		if is_instance_valid(shot) and shot.is_inside_tree():
			i += 1
		else:
			_shots.remove_at(i)
	while _shots.size() < budget.projectile_count:
		if not _spawn_shot():
			return


func _spawn_shot() -> bool:
	if _arena == null or not is_instance_valid(_arena):
		return false
	var live := RunManager.player()
	var origin := live.global_position if live != null else Vector2.ZERO
	var shot := Projectile.acquire() if pool_projectiles else Projectile.new()
	var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
	# NEUTRAL + zero damage: the shot still monitors, overlaps and resolves hits every frame,
	# but the population it flies through stays exactly `enemy_count` for the whole window.
	shot.setup(live, Layers.Team.NEUTRAL, dir, _build_damage, SHOT_SPEED, SHOT_LIFETIME)
	_arena.add_child(shot)
	shot.global_position = origin + dir * _rng.randf_range(8.0, SHOT_SPREAD)
	if not shot.expired.is_connected(_on_shot_expired):
		shot.expired.connect(_on_shot_expired)
	_shots.append(shot)
	return true


## A pooled shot parks itself; the benchmark only has to stop tracking it so the next
## `_top_up_shots()` puts a replacement in the air.
func _on_shot_expired(shot: Projectile) -> void:
	_shots.erase(shot)


func _build_damage(_target: Node2D) -> DamageInfo:
	return DamageInfo.create(0.0, [DamageInfo.TAG_PHYSICAL], self, Layers.Team.NEUTRAL)


func _frames(count: int) -> void:
	var tree := get_tree()
	for i in range(count):
		await tree.physics_frame
