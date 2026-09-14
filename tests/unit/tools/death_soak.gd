## Headless soak over the death, drop and teardown path.
##
## The gate never kills an enemy through a *live* overlap more than a handful of times, and no
## rendered scenario kills one at all, so everything downstream of a death - the loot roll, the
## deferred pickup insertion, the chest the clear spawns, the floor that is torn down on top of
## all of it - had no long-running exercise. This is that exercise: a real `RunManager` run,
## real floors, enemies killed through a real `Hitbox` overlap (so the physics query flush
## window is genuinely open when the loot spawns), drops collected, and the floor torn down and
## rebuilt underneath whatever is still in flight.
##
## It is a main scene rather than a gdUnit suite because it is a *soak*: it runs for minutes,
## it is driven by `tools/soak.sh` over many processes, and its answer is a crash rate, not an
## assertion. Nothing here may be load-bearing for the gate.
##
##     tools/soak.sh --runs 20 --floors 4
##     godot --headless --path . res://tests/unit/tools/death_soak.tscn -- --soak-runs 2
##
## Arguments (user args, after `--`):
##   `--soak-runs N`     whole runs to play (default 3)
##   `--soak-floors N`   floors per run (default 4)
##   `--soak-seed N`     first run seed; run i uses seed+i (default 20250913)
##   `--soak-mortal`     let the player die instead of making them invulnerable
##
## Exit code: 0 when every run finished *and* every minimum below was cleared, 1 when a run
## could not be started or a floor never came up, 1 with `SOAK below minimum:` lines when the
## run was too quiet to be evidence about the path it claims to cover (see `_check_minima`).
## A segmentation fault is the finding this scene exists to catch and needs no exit code of
## its own.
class_name DeathSoak
extends Node

## Classes cycled across runs, so class actives and passives all get their turn on the
## `on_kill` hooks that a death runs.
const CLASS_IDS: Array[StringName] = [&"fighter", &"ranger", &"wizard", &"oligarch"]
## Enough to kill anything on any floor through any armour roll.
const KILL_DAMAGE := 9999.0
## Reach of the soak's killing box, in pixels. Wide enough to take a clump at once, so a pack
## dies inside one flush window rather than one enemy per window.
const HIT_RADIUS := 40.0
## Physics frames a swing is held for. The overlap is reported by the server on the step
## *after* monitoring goes on, so a shorter pulse never opens `area_entered` at all.
const SWING_FRAMES := 6
## Physics frames waited after a swing for the deferred loot insertion and the death FX.
const SETTLE_FRAMES := 4
## Hard cap on swings per floor, so a floor whose enemies cannot be reached ends the leg
## instead of the process.
const MAX_SWINGS_PER_FLOOR := 120
## Frames given to a floor build before it is read.
const BUILD_FRAMES := 6
## Longest the soak waits for a killed player's run to finish tearing itself down
## (`RunManager.DEATH_DELAY` plus the death animation, with room to spare).
const DEATH_WAIT_MS := 8000
## Kills a floor has to produce, per floor built, before the soak will call itself a soak of
## the death path. Measured on the CI matrix (`--processes 2 --runs 2 --floors 3`): 60 and 53
## kills over 6 floors each, so 9-10 per floor, and the smallest floor the generator makes
## still holds a pack. Three is a floor that went badly and still died on; below that the
## deaths are not happening and the run is photographing an empty dungeon.
const MIN_KILLS_PER_FLOOR := 3
## Homing pickups (gold, hearts, stat orbs) a floor has to drop, per floor built. Every death
## rolls gold, so this is the number that says the *drop* half of the path ran at all - and
## unlike an item drop it does not depend on the generator having put an ELITE room on the
## floor. Counted off `EventBus.spawn_pickup` rather than by looking for them on the ground:
## the soak teleports the player onto the enemy it is about to kill, so a homing pickup is
## collected within a frame or two of spawning and a sweep of the floor finds nothing. That is
## what the first version of this minimum measured, and it reported `pickups_seen=0` beside
## `kills=55`.
const MIN_PICKUPS_PER_FLOOR := 1
## Physics frames a drop is given to become interactable before the soak counts it as one it
## could not take. `ItemPickup.SETTLE_TIME` is 0.4 s, which is 24 frames at 60 Hz; this is that
## with room for a loaded machine. The soak used to wait two frames and move on, which is why
## a process that saw an item drop could still report `items_taken=0`.
const DROP_SETTLE_FRAMES := 60
## Every run ends one of two ways on purpose (a death, an abandon), because they free the floor
## from different call stacks. A soak of more than one run has to have been through both.
const MIN_RUNS_FOR_BOTH_ENDINGS := 2

var runs: int = 3
var floors: int = 4
var first_seed: int = 20250913
var mortal: bool = false

var _kills: int = 0
var _items_taken: int = 0
## Instance ids of every item drop this process has walked up to, so a drop that is looked at
## on three passes before it is taken counts once rather than three times.
var _drops_seen: Dictionary = {}
## Item drops that were walked up to and never became interactable inside `DROP_SETTLE_FRAMES`.
var _drops_missed: int = 0
## Homing pickups (gold, heart, stat orb) the deaths rolled, counted as they are spawned.
var _pickups_dropped: int = 0
var _floors_built: int = 0
var _deaths: int = 0
var _abandons: int = 0
var _failures: int = 0
var _shortfalls: Array[String] = []


func _ready() -> void:
	_read_args()
	_soak()


func _read_args() -> void:
	var args := GameState.cli_args
	runs = maxi(1, int(str(args.get("soak-runs", runs))))
	floors = maxi(1, int(str(args.get("soak-floors", floors))))
	first_seed = int(str(args.get("soak-seed", first_seed)))
	mortal = bool(args.get("soak-mortal", false))


func _soak() -> void:
	# Never from a bare `_ready()`: the scene root is itself mid-insertion there, and every
	# `add_child()` the run makes underneath it is refused ("Parent node is busy setting up
	# children"), which produces a run with no player rather than a crash.
	await _frames(1)
	EventBus.spawn_pickup.connect(_on_pickup_spawned)
	RunManager.manage_scenes = false
	RunManager.offer_starting_passive = false
	for index in range(runs):
		await _one_run(index)
	EventBus.spawn_pickup.disconnect(_on_pickup_spawned)
	_check_minima()
	print(
		(
			(
				"SOAK done: runs=%d floors_built=%d kills=%d pickups=%d drops_seen=%d "
				+ "items_taken=%d drops_missed=%d deaths=%d abandons=%d failures=%d "
				+ "shortfalls=%d"
			)
			% [
				runs,
				_floors_built,
				_kills,
				_pickups_dropped,
				_drops_seen.size(),
				_items_taken,
				_drops_missed,
				_deaths,
				_abandons,
				_failures,
				_shortfalls.size()
			]
		)
	)
	get_tree().quit(1 if _failures > 0 or not _shortfalls.is_empty() else 0)


## The soak's own assertions. A soak reports a crash rate, but "no process crashed" is only
## evidence about the death, drop and teardown path if that path was walked, and nothing here
## used to say it was: a process that killed nothing, saw no drop and took no item printed the
## same `SOAK done` line and exited 0 as one that did all three. Every number below is a
## minimum the run has to clear, and a run under any of them exits 1 naming which.
func _check_minima() -> void:
	var want_kills := MIN_KILLS_PER_FLOOR * _floors_built
	if _floors_built < runs:
		_shortfalls.append(
			"floors_built=%d, wanted at least one per run (%d)" % [_floors_built, runs]
		)
	if _kills < want_kills:
		_shortfalls.append(
			(
				(
					"kills=%d over %d floor(s), wanted %d (%d per floor): the deaths this soak "
					+ "exists to cover did not happen"
				)
				% [_kills, _floors_built, want_kills, MIN_KILLS_PER_FLOOR]
			)
		)
	var want_pickups := MIN_PICKUPS_PER_FLOOR * _floors_built
	if _pickups_dropped < want_pickups:
		_shortfalls.append(
			(
				(
					"pickups=%d over %d floor(s), wanted %d: the deaths dropped nothing, so "
					+ "the loot roll and the deferred pickup insertion were never exercised"
				)
				% [_pickups_dropped, _floors_built, want_pickups]
			)
		)
	if _drops_missed > 0:
		_shortfalls.append(
			(
				(
					"drops_missed=%d of %d item drop(s): the soak walked up to a drop and never "
					+ "equipped it, so the pickup, equip and displaced-item path did not run"
				)
				% [_drops_missed, _drops_seen.size()]
			)
		)
	if runs >= MIN_RUNS_FOR_BOTH_ENDINGS and (_deaths < 1 or _abandons < 1):
		_shortfalls.append(
			(
				(
					"deaths=%d abandons=%d over %d run(s), wanted at least one of each: the two "
					+ "teardowns free the floor from different call stacks"
				)
				% [_deaths, _abandons, runs]
			)
		)
	for line: String in _shortfalls:
		push_error("SOAK below minimum: %s" % line)
		printerr("SOAK below minimum: %s" % line)


## One whole run: start it, clear and descend `floors` floors, then tear it down. The last
## floor is left mid-fight on purpose - `abandon_run()` frees the floor while deaths, drops and
## a chest are still in flight, which is the teardown ordering a real player produces by
## quitting into the pause menu the moment a pack goes down.
func _one_run(index: int) -> void:
	var class_id := CLASS_IDS[index % CLASS_IDS.size()]
	SaveManager.delete_run()
	if not RunManager.new_run(first_seed + index, class_id):
		push_error("SOAK: run %d (%s) refused to start" % [index, class_id])
		_failures += 1
		return
	await _frames(BUILD_FRAMES)
	var live := RunManager.player()
	if live == null:
		push_error("SOAK: run %d started with no player" % index)
		_failures += 1
		RunManager.abandon_run()
		return
	if not mortal:
		live.health.invulnerable = true
	for leg in range(floors):
		if not RunManager.is_run_active():
			break
		_floors_built += 1
		# Every other floor is descended *hot*: the stairs are taken on the frame the last
		# enemy dies, so the floor is torn down with the loot still in the message queue.
		await _clear_floor(live, leg % 2 == 1)
		if leg < floors - 1 and RunManager.is_run_active():
			EventBus.floor_exit_requested.emit()
			await _frames(BUILD_FRAMES)
	# The teardown that took the two controller sessions out: the run ends *during* a fight,
	# on the frame after a kill, while the loot is still in the message queue and everything
	# that picked a room up before its last `await` is still holding it. Alternated so both
	# endings are soaked - a death (RunManager._on_player_died, delayed by DEATH_DELAY) and an
	# abandon (immediate), because they free the floor from different call stacks.
	if RunManager.is_run_active():
		if index % 2 == 0:
			await _die_mid_fight(live)
			_deaths += 1
		else:
			RunManager.abandon_run()
			_abandons += 1
	await _frames(BUILD_FRAMES)
	if RunManager.is_run_active():
		RunManager.abandon_run()
		await _frames(BUILD_FRAMES)
	print(
		"SOAK run %d/%d (%s): kills=%d items=%d" % [index + 1, runs, class_id, _kills, _items_taken]
	)


## Kills everything on the current floor, collecting what the deaths drop. `hot` skips the
## settle after the last swing so the caller tears the floor down on top of it.
func _clear_floor(live: Player, hot: bool) -> void:
	var box := _make_box(live)
	var swings := 0
	while swings < MAX_SWINGS_PER_FLOOR:
		var root := RunManager.floor_root()
		if root == null or not is_instance_valid(root):
			break
		var enemy := _next_enemy(root)
		if enemy == null:
			break
		swings += 1
		var before := _live_enemy_count(root)
		live.global_position = enemy.global_position
		live.velocity = Vector2.ZERO
		box.activate(1.0)
		await _physics_frames(SWING_FRAMES)
		box.deactivate()
		if not hot or before > 1:
			await _physics_frames(SETTLE_FRAMES)
			await _take_item_drops(live)
		var after := _live_enemy_count(RunManager.floor_root())
		_kills += maxi(0, before - after)
		if after >= before:
			# Nothing died this swing (an out-of-reach enemy, a floating one over a pit):
			# step off it so the next pick is a different enemy.
			live.global_position += Vector2(HIT_RADIUS, 0.0)
	if is_instance_valid(box):
		box.queue_free()


## The soak's weapon: a player-team `Hitbox` carried by the player, so a kill is credited the
## way a real swing is and every `on_kill` passive hook fires.
func _make_box(live: Player) -> Hitbox:
	var box := Hitbox.new()
	box.name = "SoakBox"
	box.team = Layers.Team.PLAYER
	box.damage = KILL_DAMAGE
	box.source = live
	box.multi_hit_interval = 0.1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HIT_RADIUS
	shape.shape = circle
	box.add_child(shape)
	live.add_child(box)
	return box


## Walks onto every item drop lying on the floor and equips it, so the pickup path - the
## comparison card, the equip, the displaced item put back down - is exercised as often as the
## drop path is.
func _take_item_drops(live: Player) -> void:
	var root := RunManager.floor_root()
	if root == null or not is_instance_valid(root):
		return
	for node: Node in _item_pickups(root):
		var drop := node as ItemPickup
		if drop == null or not is_instance_valid(drop) or drop.is_queued_for_deletion():
			continue
		_drops_seen[drop.get_instance_id()] = true
		live.global_position = drop.global_position
		# `ItemPickup.SETTLE_TIME` holds a fresh drop shut so the keypress that equipped one
		# item cannot immediately re-equip what it displaced, so "walk on, press interact"
		# has to *wait* for the drop rather than ask once and give up.
		var waited := 0
		while waited < DROP_SETTLE_FRAMES:
			if not is_instance_valid(drop) or drop.is_queued_for_deletion():
				break
			if drop.can_interact():
				break
			live.global_position = drop.global_position
			live.velocity = Vector2.ZERO
			await _physics_frames(2)
			waited += 2
		if not is_instance_valid(drop) or drop.is_queued_for_deletion():
			continue
		if drop.can_interact():
			drop.interact(live)
			_items_taken += 1
			await _physics_frames(2)
		else:
			_drops_missed += 1


func _item_pickups(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in root.find_children("", "Area2D", true, false):
		if node is ItemPickup:
			out.append(node)
	return out


## Every gold, heart or stat orb a death rolls comes through here. Counted at the spawn rather
## than on the ground, because the soak stands on the enemy it kills and the pickup homes into
## the player immediately.
func _on_pickup_spawned(_kind: StringName, _pos: Vector2, _amount: int) -> void:
	_pickups_dropped += 1


## The live enemy nearest the player, or null. Read out of the tree rather than off a room, so
## a pack that wandered into a corridor still gets finished.
func _next_enemy(root: Node) -> Node2D:
	var live := RunManager.player()
	var best: Node2D = null
	var best_d := INF
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_inside_tree():
			continue
		if enemy.is_dying or not root.is_ancestor_of(enemy):
			continue
		var d := (
			enemy.global_position.distance_squared_to(live.global_position) if live != null else 0.0
		)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _live_enemy_count(root: Node) -> int:
	if root == null or not is_instance_valid(root):
		return 0
	var n := 0
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dying:
			if root.is_ancestor_of(enemy):
				n += 1
	return n


## Kills the player where they stand, so the run ends the way it ends for a real player: the
## floor is freed out from under whatever is still running. `DEATH_DELAY` plus the death
## animation is waited out, because the teardown is on the far side of it.
func _die_mid_fight(live: Player) -> void:
	if live == null or not is_instance_valid(live) or live.health == null:
		return
	live.health.invulnerable = false
	var info := DamageInfo.create(KILL_DAMAGE, [DamageInfo.TAG_TRUE], null, Layers.Team.ENEMY)
	live.health.take_damage(info)
	var deadline := Time.get_ticks_msec() + DEATH_WAIT_MS
	while RunManager.is_run_active() and Time.get_ticks_msec() < deadline:
		await _frames(2)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame
