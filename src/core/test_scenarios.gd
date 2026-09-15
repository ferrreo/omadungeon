## Rendered-check driver. `godot -- --test-scenario <name> --screenshot-dir <dir>
## [--screenshot-suffix <suffix>]` makes `RunManager` add one of these under the tree root; it
## then drives the game with real input events (`Input.parse_input_event`), waits for the frame
## it wants, writes `<dir>/<name><suffix>.png` and quits. `tools/run-scenario.sh` passes the
## theme fixture as the suffix whenever it is not the default one, so captures of the same
## scenario under two themes no longer overwrite each other.
##
## Every scenario runs on a fixed seed and a fixed class, and every asynchronous thing a
## capture depends on is *awaited* rather than slept past. **Every scenario also asserts that
## the state it claims to capture is really on screen**, through `require()`: a scenario that
## missed its subject exits non-zero and writes no PNG at all, instead of screenshotting
## whatever happened to be there. That is not theoretical - `summary` used to shoot a live
## floor and report success, and `chest` used to shoot a bare floor with no chest in it and
## print "(OK)". A broken scenario that looks like a passing one is worse than no scenario.
##
## **Not every capture is byte-identical, and the difference matters when you diff PNGs.**
## The *simulation* is deterministic — same seed, same floor, same loot. The *frame* is only
## deterministic when nothing on screen is still moving: `boot`, `class_select`, `pause` and
## `summary` are. `combat` is not, and cannot be made so cheaply: physics catch-up is a
## function of real elapsed time, so the number of 60 Hz steps between two awaits varies with
## machine load, and the floor scenarios carry animated props. `combat` is driven on physics
## frames and freezes the tree before the shot, which removes the process/physics interleave
## (two runs used to differ by a whole extra enemy hit); what is left is the frame it lands
## on. Judge those captures by eye, not by md5.
##
## Scenarios: boot, class_select, floor, combat, chest, loot_drop, pause, theme_swap,
## theme_swap_midfight, summary, new_run_confirm. `--scenario-floor N` makes the `floor`
## scenario descend to floor N before capturing.
class_name TestScenarios
extends Node

## Seed every scenario runs with, so two runs of the same scenario produce the same floor.
const SEED := 20250912
const CLASS_ID := &"fighter"
## Frames waited after a scene swap before anything is measured or captured.
const SETTLE_FRAMES := 12
## Hard cap so a broken scenario still exits instead of hanging the harness.
const TIMEOUT_SECONDS := 75.0
## Longest the summary scenario waits for the radio before giving up on a deterministic
## "Tracks played" section.
const MUSIC_WAIT_SECONDS := 6.0
## Longest the summary scenario keeps hitting the player before calling the kill impossible.
const DEATH_WAIT_SECONDS := 5.0
## Longest it then waits for the RunSummary screen to replace the floor.
const SUMMARY_WAIT_SECONDS := 15.0
## `loot_drop`: enough damage to kill anything on the opening floor through any armour roll.
const SLAY_DAMAGE := 9999.0
## Reach of the `loot_drop` killing box, in pixels - wide enough to take a clump at once.
const SLAY_RADIUS := 40.0
## Physics frames one swing is held for. The server reports the overlap on the step *after*
## monitoring goes on, so a shorter pulse never opens `area_entered` and nothing dies.
const SLAY_SWING_FRAMES := 8
## Swings `loot_drop` gives a room before it calls the pack unreachable.
const SLAY_SWINGS := 24
## Sweeps `loot_drop` makes over the floor picking drops up.
## A drop refuses collection until it is `PickupBase.settle_time` old (0.25 s, fifteen physics
## ticks) and each drop gets three, so four passes was enough here and not on a runner: "5 drops
## were still on the floor after walking over every one". Passes are cheap.
const COLLECT_PASSES := 10

## What each scenario exists to capture. A scenario with no entry here is one nobody can say
## is broken, so `_run` refuses to shoot it.
const SUBJECTS := {
	"boot": "the title screen",
	"class_select": "the class select screen",
	"floor": "a built floor with a live player on it",
	"combat": "a live fight",
	"chest": "an open chest offer",
	"loot_drop": "a killed pack's loot on the floor, then that floor torn down and rebuilt",
	"pause": "the pause menu over a live floor",
	"theme_swap": "the same floor before and after a theme change",
	"theme_swap_midfight": "the same live fight before and after a theme change",
	"summary": "the run summary screen",
	"new_run_confirm": "the title screen asking before it deletes a saved run",
	"music_moods": "the same room under the calmest, loudest and two mid-energy tracks",
	"music_change": "the same room across a track change, six frames over six seconds",
	"music_within": "the same room at the quiet, typical and loud passages of one track",
	"quit": "a floor with its lights and music running, then the process exiting on request",
}
## Seconds the `quit` scenario gives the floor to settle (music playing, lights lit) before it
## asks the tree to quit. `tools/check-quit.sh` times what happens after the request.
const QUIT_SETTLE_SECONDS := 1.5
## Seconds a mood capture waits after a track starts: the crossfade plus a margin.
const MOOD_SETTLE := 6.0
## Seed the adjacent-track pair is drawn with, so the same two tracks are photographed every
## run and a capture can be compared with the one before it.
const ADJACENT_SEED := 20260914
## Seconds after the switch each frame of the track-change strip is taken at.
const CHANGE_FRAMES: PackedFloat32Array = [0.0, 1.0, 2.0, 3.0, 4.0, 6.0]

var scenario: String = "boot"
var out_dir: String = "tests/out"
## Appended to every screenshot name (before ".png"). Empty for the default theme, so the
## historical `<scenario>.png` file names keep working.
var suffix: String = ""

var _shots: int = 0
## The music scenarios' running records, kept on the driver rather than in locals because
## every capture sits on an await (see `tests/unit/freed_instance_test.gd`'s scan).
var _music_lines: PackedStringArray = []
var _music_frames: Array[Image] = []
var _music_luminances: PackedFloat32Array = []
var _music_file: String = ""
## Set by `require()`: the scenario never reached the state it exists to capture, so the run
## exits non-zero with no screenshot rather than passing off the wrong screen as the right one.
var _failed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if suffix.is_empty():
		suffix = suffix_from_cli()
	_guard_timeout()
	_run()


## Adds the driver under the tree root when the game was launched with `--test-scenario`, and
## returns it; null when it was not. Lives here rather than in `RunManager` because everything
## it reads is this class's own command line. It also turns the docs §2 starting-passive picker
## off: a modal on the first frame of every run would cover the floor, combat, chest and pause
## captures. `--starting-passive` turns it back on, to capture the pick itself.
static func start_if_requested(tree: SceneTree) -> TestScenarios:
	var requested := str(GameState.cli_args.get("test-scenario", ""))
	if requested.is_empty():
		return null
	RunManager.offer_starting_passive = bool(GameState.cli_args.get("starting-passive", false))
	# `--scenario-archetype hub` lays every floor of the capture to one plan (docs 5.1 #1), so
	# the five archetypes can be shot one by one; the game itself never sets this.
	FloorArchetype.forced = StringName(str(GameState.cli_args.get("scenario-archetype", "")))
	var driver := TestScenarios.new()
	driver.scenario = requested
	driver.out_dir = str(GameState.cli_args.get("screenshot-dir", "tests/out"))
	tree.root.add_child.call_deferred(driver)
	return driver


## The screenshot suffix the game was launched with (`--screenshot-suffix _white`), empty when
## the run used the default theme. `tools/run-scenario.sh` derives it from the theme fixture.
static func suffix_from_cli() -> String:
	return str(GameState.cli_args.get("screenshot-suffix", ""))


## Fails loudly instead of hanging if a scenario never reaches its screenshot.
func _guard_timeout() -> void:
	await get_tree().create_timer(TIMEOUT_SECONDS).timeout
	push_error("TestScenarios: %s timed out" % scenario)
	QuitGuard.request(get_tree(), 2)


func _run() -> void:
	await _frames(SETTLE_FRAMES)
	match scenario:
		"boot":
			await _scenario_boot()
		"class_select":
			await _scenario_class_select()
		"floor":
			await _scenario_floor()
		"combat":
			await _scenario_combat()
		"chest":
			await _scenario_chest()
		"loot_drop":
			await _scenario_loot_drop()
		"pause":
			await _scenario_pause()
		"theme_swap":
			await _scenario_theme_swap()
		"theme_swap_midfight":
			await _scenario_theme_swap_midfight()
		"summary":
			await _scenario_summary()
		"new_run_confirm":
			await _scenario_new_run_confirm()
		"music_moods":
			await _scenario_music_moods()
		"music_change":
			await _scenario_music_change()
		"music_within":
			await MusicWithinScenario.run(self)
		"quit":
			await _scenario_quit()
			return
		_:
			push_error("TestScenarios: unknown scenario %s" % scenario)
			QuitGuard.request(get_tree(), 2)
			return
	if not may_capture():
		push_error(
			(
				"TestScenarios: %s never reached %s; no screenshot written"
				% [scenario, subject_of(scenario)]
			)
		)
		QuitGuard.request(get_tree(), 2)
		return
	if not await _shoot(scenario):
		QuitGuard.request(get_tree(), 2)
		return
	await QuitGuard.request(get_tree(), 0)


## Asserts that the scenario reached part of what it exists to capture, and returns
## `condition` so a caller can `if not require(...): return`. A false condition is the whole
## difference between "this PNG is a chest offer" and "this PNG is whatever was on screen":
## the run then exits 2 with no capture at all, rather than printing "(OK)" over the wrong
## screen.
func require(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("TestScenarios: %s: %s" % [scenario, message])
	return condition


## False once a scenario has missed its subject; `_run` then quits non-zero without shooting.
func may_capture() -> bool:
	return not _failed


## The state `name` exists to capture, or "" for a scenario nobody declared one for.
static func subject_of(name: String) -> String:
	return str(SUBJECTS.get(name, ""))


# ---------------------------------------------------------------- scenarios


## Title screen as the player first sees it.
func _scenario_boot() -> void:
	await _settle()
	var main := _main()
	require(main != null and main.current is Title, "the title screen is not up")


## Title -> Class Select by pressing the real "New Run" button on the title screen.
func _scenario_class_select() -> void:
	var main := _main()
	if not require(main != null, "main.tscn is not the current scene"):
		return
	var button := main.current.get_node_or_null(^"%NewRun") as Button
	if button != null:
		button.pressed.emit()
	else:
		main.show_screen(Main.Screen.CLASS_SELECT)
	await _settle()
	# Re-fetched rather than carried: `Main` is a node like any other, and a scenario that
	# reads one it picked up before a wait is one `queue_free()` away from the SIGSEGV
	# `live_room()` exists to prevent for rooms (docs/TESTING.md, "A freed instance is a
	# crash"). `tests/unit/freed_instance_test.gd` scans this file for the shape.
	var opened := _main()
	if not require(opened != null, "main.tscn went away while the class select opened"):
		return
	require(opened.current is ClassSelect, "New Run did not open the class select")


## A generated floor with the player standing in the start room. `--scenario-floor N`
## descends to floor N first, so a rendered check can look at a Forge/Frost/Library/Void
## floor and not only the opening Crypt; `--scenario-arena entry|engaged` then walks into the
## boss arena (`ArenaCapture`).
func _scenario_floor() -> void:
	if not await _start_run():
		return
	var target := clampi(int(GameState.cli_args.get("scenario-floor", 0)), 0, GenParams.LAST_FLOOR)
	await _descend_to(target)
	await _settle()
	require(
		RunManager.floor_index == target,
		"asked for floor %d, stopped on %d" % [target + 1, RunManager.floor_index + 1]
	)
	if not _require_live_floor():
		return
	await ArenaCapture.run(self, str(GameState.cli_args.get("scenario-arena", "")))


## The exit itself, measured: a built floor with the radio playing and the lights up, one
## frame of it on disk where a display exists, then the exit - and `tools/check-quit.sh`
## fails the check when the process is still alive `QUIT_BUDGET` seconds after the marker
## line below. The shutdown used to hang under load (a capture that had written its PNG sat
## for 235 s until the harness killed it), and nothing measured the half of a run that ends it.
##
## `--quit-by` picks which exit is measured. `request` (the default) asks `QuitGuard` straight.
## `self-close` hands the root the `NOTIFICATION_WM_CLOSE_REQUEST` the engine delivers when a
## window manager asks the window to close, so the game's own answer to that request is what
## is timed; it works headless, where there is no window manager to ask. `wm-close` prints the
## marker and waits for a real one, which `tools/check-quit.sh close` sends through sway.
## The last two exist because that request used to reach nobody once a run had started: `Main`
## answered it and `RunManager.new_run()` frees `Main`, so the window would not close at all
## during a run (measured 2026-09-14: still alive 30 s after `swaymsg kill`). The answer lives
## in the `Quit` autoload now, `src/core/quit_service.gd`.
func _scenario_quit() -> void:
	if not await _start_run():
		QuitGuard.request(get_tree(), 2)
		return
	await get_tree().create_timer(QUIT_SETTLE_SECONDS).timeout
	await _frames(2)
	var root := RunManager.floor_root()
	var lit := root != null and not root.torch_lights().is_empty()
	print(
		(
			"Scenario quit: floor %d, music %s, lights %s"
			% [RunManager.floor_index + 1, "playing" if Music.is_playing() else "silent", lit]
		)
	)
	if DisplayServer.get_name() != "headless":
		if not await _shoot(scenario):
			QuitGuard.request(get_tree(), 2)
			return
	print("Scenario quit: exiting at %d ms" % Time.get_ticks_msec())
	match str(GameState.cli_args.get("quit-by", "request")):
		"self-close":
			# Fetched into its own local rather than written as `get_tree().root.…`: this
			# function already has a `root` (the floor's), and the freed-instance scan in
			# `tests/unit/freed_instance_test.gd` reads `root.` after an await as that local
			# being touched across the wait. It is right to: a name it cannot tell apart is a
			# name the next person cannot either.
			var root_window := get_tree().root
			root_window.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		"wm-close":
			pass
		_:
			QuitGuard.request(get_tree(), 0)


## Takes the stairs until the run is on `floor_index` (clamped to the real floor range).
func _descend_to(floor_index: int) -> void:
	var target := clampi(floor_index, 0, GenParams.LAST_FLOOR)
	var guard := 0
	while RunManager.floor_index < target and guard < GenParams.LAST_FLOOR + 1:
		guard += 1
		EventBus.floor_exit_requested.emit()
		await _frames(SETTLE_FRAMES)


## Walks the player into the nearest populated room and simulates a few attack frames.
##
## Everything here is counted in *physics* frames and the world is frozen before the capture.
## Enemy AI, hitboxes and damage all run on physics; waiting on process frames (or on a
## wall-clock `_settle()`) let the interleave drift with machine load, and two runs of this
## scenario used to capture different HP and different stat drains. This narrows the drift to
## the frame the capture lands on; it does not make the PNG byte-identical (see the class
## docstring), because physics catch-up itself is a function of real elapsed time.
func _scenario_combat() -> void:
	if not await _start_run():
		return
	var room := _busiest_room()
	if not require(room != null, "the floor has no room with enemies in it to fight"):
		return
	_teleport_player(room.center_world())
	await _physics_frames(6)
	await _hold_action(&"attack", 12)
	await _physics_frames(10)
	await _hold_action(&"attack", 12)
	await _physics_frames(SETTLE_FRAMES)
	get_tree().paused = true
	await _frames(2)
	if not _require_live_floor():
		return
	var fight := live_room(room)
	if not require(fight != null, "the run ended mid-fight and took the floor with it"):
		return
	require(fight.pending_enemy_count() > 0, "every enemy died; the capture is an empty room")


## Clears one room programmatically so a real chest spawns, then opens its offer UI.
func _scenario_chest() -> void:
	if not await _start_run():
		return
	var room := _busiest_room()
	if not require(room != null, "the floor has no clearable room, so no chest can spawn"):
		return
	_teleport_player(room.center_world())
	await _frames(6)
	var cleared := live_room(room)
	if not require(cleared != null, "the run ended before the room could be cleared"):
		return
	cleared.force_clear(true)
	await _frames(SETTLE_FRAMES)
	if not require(live_room(room) != null, "the floor was torn down before the chest spawned"):
		return
	if not require(cleared.chest != null, "clearing the room spawned no chest"):
		return
	cleared.chest.interact(RunManager.player())
	await _settle()
	var view := RunManager.game as Game
	if not require(view != null, "the game scene went away"):
		return
	require(
		view.chest_ui.is_open(),
		"the chest offer never opened; the capture would be an ordinary floor"
	)


## The death, drop and pickup path, photographed. **No other scenario kills an enemy**: the
## combat capture needs its pack alive to be a picture of a fight, so everything downstream of
## a death - the loot roll, the deferred pickup insertion the physics flush rule exists for,
## the reward chest, the floor torn down on top of it all - had no rendered coverage at all,
## and two controller sessions died in that path without a single check noticing.
##
## The pack is killed through a real `Hitbox` overlap rather than through `hurtbox.receive()`,
## because that is the only way the physics query flush window is genuinely open while the loot
## spawns (see `PhysicsFlush`). Two pictures:
##
## * `loot_drop_before.png` - the pack down, the drops lying where they fell, before anything
##   is collected. This is the frame nobody had.
## * `loot_drop.png` - the next floor, after the drops have been walked over and the old floor
##   has been torn down, so "a drop never follows the player down the stairs" is a picture too.
func _scenario_loot_drop() -> void:
	if not await _start_run():
		return
	var room := _busiest_room()
	if not require(room != null, "the floor has no room with enemies in it to kill"):
		return
	var pack := room.pending_enemy_count()
	_teleport_player(room.center_world())
	await _physics_frames(6)
	await _slay(room)
	var cleared := live_room(room)
	if not require(cleared != null, "the run ended mid-fight and took the floor with it"):
		return
	if not require(
		cleared.pending_enemy_count() == 0,
		(
			"%d of %d enemies survived; this is not a death capture"
			% [cleared.pending_enemy_count(), pack]
		)
	):
		return
	var dropped := _loose_loot().size()
	if not require(dropped > 0, "the pack died and dropped nothing at all"):
		return
	get_tree().paused = true
	await _frames(2)
	if not await _shoot("loot_drop_before"):
		return
	get_tree().paused = false
	await _collect_loot()
	if not require(
		_loose_loot().is_empty(),
		(
			"%d drops were still on the floor after walking over every one: %s"
			% [_loose_loot().size(), ScenarioLoot.names(_loose_loot())]
		)
	):
		return
	var standing := live_room(room)
	if not require(standing != null, "the floor went away while the loot was collected"):
		return
	if not require(standing.chest != null, "clearing the room spawned no reward chest"):
		return
	var floor_before := RunManager.floor_index
	EventBus.floor_exit_requested.emit()
	await _settle()
	if not require(
		RunManager.floor_index == floor_before + 1, "the stairs did not build the next floor"
	):
		return
	if not _require_live_floor():
		return
	require(live_room(room) == null, "the torn-down floor's rooms are still in the tree")
	require(_loose_loot().is_empty(), "a drop followed the player down the stairs")
	get_tree().paused = true
	await _frames(2)


## Kills everything in `room` through a live player-team `Hitbox`, the way a real swing does,
## so every death runs inside a physics query flush. Gives up at `SLAY_SWINGS` swings rather
## than looping for ever on an enemy that cannot be reached.
func _slay(room: RoomNode) -> void:
	var live := RunManager.player()
	if live == null:
		return
	var box := _killing_box(live)
	for _swing in range(SLAY_SWINGS):
		# Everything is re-fetched every swing rather than carried across the `await` below.
		# `RunManager.player()` already answers null once the run is over, and `live_room()`
		# answers null once the floor is gone; a reference carried instead would be dangling.
		live = RunManager.player()
		var here := live_room(room)
		if live == null or here == null or here.pending_enemy_count() == 0:
			break
		var victim := _nearest_enemy(here)
		if victim == null or not is_instance_valid(box):
			break
		live.global_position = victim.global_position
		live.velocity = Vector2.ZERO
		box.activate(1.0)
		await _physics_frames(SLAY_SWING_FRAMES)
		if not is_instance_valid(box):
			break
		box.deactivate()
		await _physics_frames(2)
	if is_instance_valid(box):
		box.queue_free()
	await _physics_frames(SETTLE_FRAMES)


## The scenario's weapon: a player-team box carried by the player, so a kill is credited the
## way a real swing is and every on-kill hook fires.
func _killing_box(live: Node2D) -> Hitbox:
	var box := Hitbox.new()
	box.name = "ScenarioKillBox"
	box.team = Layers.Team.PLAYER
	box.damage = SLAY_DAMAGE
	box.source = live
	box.multi_hit_interval = 0.1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SLAY_RADIUS
	shape.shape = circle
	box.add_child(shape)
	live.add_child(box)
	return box


func _nearest_enemy(room: RoomNode) -> Node2D:
	var live := RunManager.player()
	var best: Node2D = null
	var best_d := INF
	for node: Node2D in room.enemies:
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var enemy := node as EnemyBase
		if enemy != null and enemy.is_dying:
			continue
		var d := (
			node.global_position.distance_squared_to(live.global_position) if live != null else 0.0
		)
		if d < best_d:
			best_d = d
			best = node
	return best


func _loose_loot() -> Array[Node]:
	return ScenarioLoot.loose(RunManager.game as Game)


## Walks the player onto every drop until the floor is clean. Homing pickups collect on
## contact; an item drop is an `Interactable` and has to be asked for.
func _collect_loot() -> void:
	for _pass in range(COLLECT_PASSES):
		var loot := _loose_loot()
		if loot.is_empty():
			break
		# Let whatever is still settling reach `settle_time` before walking the floor again.
		if _pass > 0:
			await _physics_frames(SETTLE_FRAMES)
		for node: Node in loot:
			# Both ends are re-checked after every wait: the drop may have been collected or
			# the floor torn down since the list was taken.
			# A player can be absent for a frame while a room hands over, so a null is waited
			# out once rather than taken as "give up". The wait happens here, before this
			# iteration touches `node`, and `live` is read *after* it: holding either across an
			# await is what `freed_instance_test` fails and what a SIGSEGV would punish.
			var live := RunManager.player()
			if live == null:
				await _physics_frames(2)
				live = RunManager.player()
			if live == null:
				require(false, "the player went away while the loot was being collected")
				return
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			live.global_position = (node as Node2D).global_position
			live.velocity = Vector2.ZERO
			await _physics_frames(3)
			# Re-checked *before* the cast, not after it. Walking onto a drop is how it gets
			# collected, so the wait above frees this node on purpose - and `as` on a freed
			# object is an error that ends this function, leaving every later drop where it
			# lay: "2 drops were still on the floor", 1 run in 12. The test used to sit one
			# line further down, guarding a cast that had already happened.
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			var drop := node as ItemPickup
			if drop == null or not drop.can_interact():
				continue
			# Re-read without waiting: `drop` is live right now and must stay that way until
			# `interact`, so nothing may await between the two.
			live = RunManager.player()
			if live == null:
				require(false, "the player went away while the loot was being collected")
				return
			drop.interact(live)
			await _physics_frames(2)
	await _physics_frames(SETTLE_FRAMES)


## Pause menu over a live floor.
func _scenario_pause() -> void:
	if not await _start_run():
		return
	var view := RunManager.game as Game
	if not require(view != null, "the game scene went away"):
		return
	view.pause_menu.open()
	await _settle()
	# The same rule as the rooms: `RunManager.game` is asked again on this side of the wait,
	# because the run can end during it and take the scene with it.
	var paused := RunManager.game as Game
	if not require(paused != null, "the game scene went away while the pause menu opened"):
		return
	require(paused.pause_menu.is_open(), "the pause menu did not open")
	_require_live_floor()


## Proves the live retint: screenshots the floor, flips the Omarchy state symlink to the
## `white` fixture, waits for the poll + crossfade, then screenshots again.
func _scenario_theme_swap() -> void:
	if not await _start_run():
		return
	var state_dir := _make_swap_state("tokyo-night")
	if not require(not state_dir.is_empty(), "could not build the theme-swap state dir"):
		return
	Desktop.omarchy = OmarchyState.new(state_dir)
	Desktop.reload(false)
	await _settle()
	if not _require_live_floor():
		return
	var before := _palette_name()
	if not await _shoot("theme_swap_before"):
		return
	if not require(_link_theme(state_dir, "white"), "could not point the state dir at `white`"):
		return
	# Desktop polls every 0.3 s and debounces 0.15 s; the retint tween takes 0.6 s.
	await get_tree().create_timer(1.6).timeout
	await _settle()
	# The whole point of the pair is that the second picture is a *different* theme. Without
	# this the scenario happily shoots the same floor twice and calls it a live retint.
	require(
		_palette_name() != before,
		"the palette never changed (still %s); the pair proves nothing" % before
	)


## The retint *during a fight* - docs GAME_DESIGN §3.5 names this check by name and it did not
## exist. `theme_swap` swaps on an idle floor, and an idle floor is the one place none of the
## live-retint subscribers that matter are on screen: `EnemyBase`, `Telegraph`, `EnemyHpBar`,
## `Decoy`, `MimeWall`, `TrapBase` and the boss zones all listen to `palette_changed`, and a
## theme change that crashed or failed to reach them would pass every existing rendered check.
##
## Same before/after pair as `theme_swap`, but taken over a room with live enemies in it, and
## the fight is asserted to still be a fight on both sides of the swap - an enemy that died to
## the flip would otherwise read as a clean capture.
func _scenario_theme_swap_midfight() -> void:
	if not await _start_run():
		return
	var room := _busiest_room()
	if not require(room != null, "the floor has no room with enemies in it to fight"):
		return
	_teleport_player(room.center_world())
	await _physics_frames(6)
	await _hold_action(&"attack", 10)
	await _physics_frames(SETTLE_FRAMES)
	var fight := live_room(room)
	if not require(fight != null, "the run ended mid-fight and took the floor with it"):
		return
	if not require(fight.pending_enemy_count() > 0, "every enemy died before the swap"):
		return
	var state_dir := _make_swap_state("tokyo-night")
	if not require(not state_dir.is_empty(), "could not build the theme-swap state dir"):
		return
	Desktop.omarchy = OmarchyState.new(state_dir)
	Desktop.reload(false)
	await _settle()
	if not _require_live_floor():
		return
	var before := _palette_name()
	if not await _shoot("theme_swap_midfight_before"):
		return
	if not require(_link_theme(state_dir, "white"), "could not point the state dir at `white`"):
		return
	# Desktop polls every 0.3 s and debounces 0.15 s; the retint tween takes 0.6 s.
	await get_tree().create_timer(1.6).timeout
	await _settle()
	if not require(_palette_name() != before, "the palette never changed (still %s)" % before):
		return
	if not _require_live_floor():
		return
	if not require(live_room(room) != null, "the swap took the floor down with it"):
		return
	if not require(
		fight.pending_enemy_count() > 0, "the swap emptied the room; this is not a fight"
	):
		return
	# Frozen last, like `combat`: the pair has to differ by the theme and nothing else.
	get_tree().paused = true
	await _frames(2)


## Death -> run summary screen. Waits for the radio first: the summary lists the tracks played,
## and killing the player before the first track registers would make the capture vary run to run.
## Then it waits for the summary screen to actually exist, because one run in four used to
## capture a live floor and still report success.
func _scenario_summary() -> void:
	if not await _start_run():
		return
	await _await_first_track()
	var live := RunManager.player()
	if not require(live != null, "no player to kill"):
		return
	if not await _kill_player(live):
		return
	if not await _await_summary():
		return
	await _settle()


## Kills the player outright for the death capture. One killing blow is not enough: a hit
## landing inside post-hit i-frames is dropped by `Health.take_damage`, which is how the
## summary scenario sometimes screenshotted a live floor. Retries until the health node
## reports dead. Returns false (and fails the scenario) when it never does.
func _kill_player(live: Player) -> bool:
	var deadline := Time.get_ticks_msec() + int(DEATH_WAIT_SECONDS * 1000.0)
	while not live.health.is_dead() and Time.get_ticks_msec() < deadline:
		live.health.invulnerable = false
		live.health.take_damage(
			DamageInfo.create(99999.0, [DamageInfo.TAG_TRUE], null, Layers.Team.ENEMY)
		)
		await get_tree().process_frame
	if not live.health.is_dead():
		require(false, "the player never died")
		return false
	return true


## Waits for `main.tscn` to be showing the RunSummary screen (death animation plus
## `RunManager.DEATH_DELAY` plus the scene swap). Returns false when it never appears.
func _await_summary() -> bool:
	var deadline := Time.get_ticks_msec() + int(SUMMARY_WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var main := _main()
		if main != null and main.current is RunSummary:
			return true
		await get_tree().process_frame
	require(false, "the run summary never appeared (the capture would show a live floor)")
	return false


## The title screen refusing to throw a saved run away without asking. Writes a run to the
## save sandbox, reopens the title so its Continue button sees it, then presses New Run and
## checks that the confirm panel - not the class select - is what came up.
func _scenario_new_run_confirm() -> void:
	var main := _main()
	if not require(main != null, "main.tscn is not the current scene"):
		return
	var state := RunState.new()
	state.run_seed = SEED
	state.class_id = CLASS_ID
	state.floor_index = 2
	if not require(SaveManager.save_run(state), "could not write a run to the save sandbox"):
		return
	var title := main.show_screen(Main.Screen.TITLE) as Title
	if not require(title != null, "the title screen did not come back up"):
		return
	await _settle()
	# `Main.show_screen()` frees the screen it replaces, so a `Title` held across a wait is a
	# reference to a node that may already be gone: every read below re-fetches through the
	# current scene rather than through the local the line above produced.
	var shown := _title_of(_main())
	if not require(shown != null, "the title screen went away before New Run was pressed"):
		return
	var button := shown.get_node_or_null(^"%NewRun") as Button
	if not require(button != null, "the title screen has no New Run button"):
		return
	button.pressed.emit()
	await _settle()
	var asked := _title_of(_main())
	if not require(asked != null, "the title screen went away while it was asking"):
		return
	require(asked.confirm_visible(), "New Run did not ask before deleting the saved run")
	require(SaveManager.has_run(), "the saved run was already deleted")
	var now := _main()
	if not require(now != null, "main.tscn went away"):
		return
	require(not (now.current is ClassSelect), "New Run walked straight into the class select")


## The same floor, same seed, same room, under the calmest and the loudest bundled tracks and
## under **two tracks the playlist actually plays back to back** - the evidence for docs 10.2's
## "you can see which track is playing". Each capture is measured around the player and the
## numbers go to `music_moods<suffix>.txt`, so the claim is a luminance and a hue, not an
## impression. The middle pair used to be two mid-energy tracks picked for the furthest-apart
## hue seeds, which measured the mapping at its most flattering; one track following another is
## what a player hears twenty times a run. `music_within` is the other half of the answer: the
## same room at three passages of *one* track.
func _scenario_music_moods() -> void:
	if not await _start_run():
		return
	var calm := MusicMood.extreme_file(false)
	var loud := MusicMood.extreme_file(true)
	var pair := _adjacent_pair()
	if not require(not calm.is_empty() and pair.size() == 2, "the mood table has no tracks"):
		return
	_reset_music_records()
	var picks := {"calm": calm, "next_a": pair[0], "next_b": pair[1], "loud": loud}
	for label: String in picks:
		_music_file = str(picks[label])
		if not require(Music.play_track_file(_music_file), "cannot play %s" % _music_file):
			return
		await get_tree().create_timer(MOOD_SETTLE).timeout
		await _settle()
		if not await _shoot("music_moods_%s" % label):
			return
		_record_mood_line(label)
	_write_lines("music_moods", _music_lines)


## The same room across one track change, calmest to loudest: a frame at the switch and at
## 1, 2, 3, 4 and 6 s after it, each measured, and a strip of the six side by side
## (`music_change_strip<suffix>.png`). The luminance around the player must rise monotonically
## across the frames - a crossfade, not a flash - or the scenario fails.
func _scenario_music_change() -> void:
	if not await _start_run():
		return
	_music_file = MusicMood.extreme_file(false)
	if not require(Music.play_track_file(_music_file), "cannot play %s" % _music_file):
		return
	await get_tree().create_timer(MOOD_SETTLE).timeout
	await _settle()
	_music_file = MusicMood.extreme_file(true)
	if not require(Music.play_track_file(_music_file), "cannot play %s" % _music_file):
		return
	_reset_music_records()
	var clock := 0.0
	for at: float in CHANGE_FRAMES:
		if at > clock:
			await get_tree().create_timer(at - clock).timeout
			clock = at
		if not await _shoot("music_change_t%d" % int(at)):
			return
		_record_change_frame("t%d" % int(at))
	_require_monotonic_luminance()
	_write_lines("music_change", _music_lines)
	_write_strip(_music_frames)


func _reset_music_records() -> void:
	_music_frames = []
	_music_lines = []
	_music_luminances = []


func _record_mood_line(label: String) -> void:
	_music_lines.append(_measure_line(label, _music_file))


## Fails the scenario when the series is not what a track change looks like; the rule and the
## reasoning live in `ScenarioMusicRules`.
func _require_monotonic_luminance() -> void:
	var fault := ScenarioMusicRules.fault_in_change(
		_music_luminances, CHANGE_FRAMES, MusicMoodLevers.shared().crossfade_seconds
	)
	require(fault.is_empty(), fault)


## One frame of the track-change series: the PNG just written read back for the strip, its
## measurement line, and the luminance the monotonic check runs over.
func _record_change_frame(label: String) -> void:
	var img := Image.load_from_file(screenshot_path("music_change_%s" % label))
	if img != null:
		_music_frames.append(img)
	_music_lines.append(_measure_line(label, _music_file))
	_music_luminances.append(_room_luminance())


## The first two tracks of a played order: shuffled then spread by mood the way a run does it
## (`MusicManager._build_queue`), from a fixed seed so the pair is the same every run.
func _adjacent_pair() -> PackedStringArray:
	var playlist := Music.playlist
	if playlist == null:
		return PackedStringArray()
	var rng := RunRng.new(ADJACENT_SEED).stream(&"music")
	var order := RadioPlaylist.spread(playlist.available(), rng)
	if order.size() < 2:
		return PackedStringArray()
	return [order[0].file, order[1].file]


## Mean luminance and hue of the room around the player, on the live viewport.
func _measure_line(label: String, file: String) -> String:
	var stats := _room_stats()
	var mood := Music.mood()
	return (
		"%s file=%s energy=%.2f hue_seed=%.2f words=%s luminance=%.4f hue=%.1f"
		% [
			label,
			file,
			mood.energy,
			mood.hue_seed,
			mood.words_line().replace(" ", "_"),
			stats.x,
			stats.y
		]
	)


func _room_luminance() -> float:
	return _room_stats().x


## (mean luminance, mean hue in degrees) over a 120x80 viewport-pixel box around the player,
## less the 24x24 the player and its ring occupy, read straight off the viewport texture.
func _room_stats() -> Vector2:
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var live := RunManager.player()
	if image == null or live == null or not is_instance_valid(live):
		return Vector2.ZERO
	var view := get_viewport().get_visible_rect().size
	var scale := Vector2(image.get_size()) / view
	var centre := live.get_global_transform_with_canvas().origin * scale
	var half := Vector2(60, 40) * scale
	var hole := Vector2(12, 12) * scale
	var lum := 0.0
	var sx := 0.0
	var sy := 0.0
	var count := 0
	for y in range(int(centre.y - half.y), int(centre.y + half.y)):
		for x in range(int(centre.x - half.x), int(centre.x + half.x)):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if absf(x - centre.x) < hole.x and absf(y - centre.y) < hole.y:
				continue
			var c := image.get_pixel(x, y)
			lum += c.get_luminance()
			sx += cos(c.h * TAU) * c.s
			sy += sin(c.h * TAU) * c.s
			count += 1
	if count == 0:
		return Vector2.ZERO
	return Vector2(lum / float(count), fposmod(rad_to_deg(atan2(sy, sx)), 360.0))


func _write_lines(name: String, lines: PackedStringArray) -> void:
	var path := screenshot_path(name).get_basename() + ".txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		require(false, "could not write %s" % path)
		return
	for line: String in lines:
		f.store_line(line)
		print("Scenario %s: %s" % [scenario, line])


## Six frames side by side at a third of their size: the strip a reviewer reads at a glance.
func _write_strip(frames: Array[Image], name: String = "music_change_strip") -> void:
	var strip := ScenarioStrip.build(frames)
	if strip != null:
		write_shot(strip, screenshot_path(name))


# ---------------------------------------------------------------- helpers


func _main() -> Main:
	return get_tree().current_scene as Main


## The `Title` the current scene is showing, or null. Used instead of a `Title` local carried
## across an `await`: `Main.show_screen()` frees the screen it replaces, so the local can be a
## freed instance by the time the wait is over, and calling a method on one of those is a
## segmentation fault rather than an error a scenario could report.
func _title_of(main: Main) -> Title:
	if main == null or not is_instance_valid(main):
		return null
	return main.current as Title


## Starts the scenario run. Returns false - and fails the scenario - when the run did not
## start, because every capture downstream of it would then be of the title screen.
func _start_run() -> bool:
	if not require(RunManager.new_run(SEED, CLASS_ID), "the run refused to start"):
		return false
	await _frames(SETTLE_FRAMES)
	return _require_live_floor()


## Asserts the thing every in-run capture is made of: a built floor with rooms, and a player
## alive on it. Returns false when it is missing.
func _require_live_floor() -> bool:
	var root := RunManager.floor_root()
	if not require(root != null and not root.rooms.is_empty(), "no floor was built"):
		return false
	var live := RunManager.player()
	if not require(live != null and not live.health.is_dead(), "no live player on the floor"):
		return false
	return true


## The live palette's name, or "" before Desktop has one. The theme-swap scenario compares it
## either side of the swap.
func _palette_name() -> String:
	return Desktop.palette.name if Desktop.palette != null else ""


## `room` if that room is still standing, null once its floor has been torn down.
##
## **Never call a method on a node a scenario picked up before an `await`.** A RoomNode (or a
## chest, or an enemy) is freed the moment the run ends under it -
## `RunManager._teardown_run()` -> `Game.unload_floor()` -> `FloorRoot.clear_floor()` - and a
## scenario that dies mid-fight, descends, or is abandoned reaches its next line holding a
## dangling reference. In a shipped Godot build that is not an error: `Variant::callp` only
## consults the ObjectDB when a script debugger is attached (`EngineDebugger::is_active()`),
## so with no debugger the call goes straight through the freed object's vtable and the process
## dies on SIGSEGV. Two cores on this machine died exactly that way, both inside
## `RoomNode.pending_enemy_count()` on a room whose floor was already gone. A scenario that
## loses its subject must fail with a message; it must not take the process out.
## The parameter is `Variant` on purpose, and it is the one place in this project where that
## is the right type: GDScript checks a *typed* parameter against the argument's class, and a
## freed instance has no class left, so `live_room(room: RoomNode)` answers a freed room with
## "Invalid type in function" and never runs its own guard. The whole point of this function is
## to be callable with the reference you are not sure about.
static func live_room(room: Variant) -> RoomNode:
	# `is_instance_valid` first and on the raw Variant: even *casting* a freed reference is a
	# runtime error ("Trying to cast a freed object"), so nothing else may touch it first.
	if not is_instance_valid(room):
		return null
	var node := room as RoomNode
	if node == null or node.is_queued_for_deletion() or not node.is_inside_tree():
		return null
	return node


## The live room with the most enemies (the one worth screenshotting).
func _busiest_room() -> RoomNode:
	var root := RunManager.floor_root()
	if root == null:
		return null
	var best: RoomNode = null
	for room: RoomNode in root.rooms:
		if room.enemies.is_empty():
			continue
		if best == null or room.enemies.size() > best.enemies.size():
			best = room
	return best


func _teleport_player(pos: Vector2) -> void:
	var live := RunManager.player()
	var view := RunManager.game as Game
	if live == null:
		return
	live.global_position = pos
	live.velocity = Vector2.ZERO
	if view != null:
		view.camera.snap_to(pos)


## Presses an action, holds it for `frames` frames and releases it.
func _hold_action(action: StringName, frames: int) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	press.strength = 1.0
	Input.parse_input_event(press)
	await _physics_frames(frames)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await _physics_frames(2)


## Waits until the radio has registered its first track, or `MUSIC_WAIT_SECONDS` elapse.
## Keeps the run summary's "Tracks played" section identical between runs of the same scenario.
func _await_first_track() -> void:
	var deadline := Time.get_ticks_msec() + int(MUSIC_WAIT_SECONDS * 1000.0)
	while Music.tracks_played().is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if Music.tracks_played().is_empty():
		push_warning("TestScenarios: radio never started; summary capture omits the track list")


func _frames(count: int) -> void:
	for _i in range(maxi(1, count)):
		await get_tree().process_frame


## Like `_frames`, but counted on the physics clock. Anything a capture of a live fight
## depends on — enemy AI, hitbox overlaps, damage — runs there, so waiting on process frames
## makes the number of simulated physics steps a function of the machine's frame rate.
func _physics_frames(count: int) -> void:
	for _i in range(maxi(1, count)):
		await get_tree().physics_frame


func _settle() -> void:
	await _frames(SETTLE_FRAMES)
	await get_tree().create_timer(0.4).timeout
	await _frames(2)


## Absolute file a capture called `name` lands in. The theme suffix goes on the file name,
## never the directory, so `tests/out/<scenario>.png` keeps working for the default theme and a
## second theme lands beside it instead of on top of it.
func screenshot_path(name: String) -> String:
	return ProjectSettings.globalize_path(out_dir).path_join("%s%s.png" % [name, suffix])


## Writes `<out_dir>/<name><suffix>.png` from the live viewport. Returns false - and fails the
## scenario, so the process exits non-zero - when nothing landed on disk.
func _shoot(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	return write_shot(texture.get_image() if texture != null else null, screenshot_path(name))


## Writes `image` to `path` and says whether it really landed. Split out of `_shoot` so the
## honesty rule is unit-testable without a compositor; `_shoot` only supplies the frame.
##
## The target is removed *before* the write. Without that, a failed `save_png` left the
## previous run's PNG sitting there with its old mtime, and the harness reported success over a
## picture of a different build - the same "a broken scenario that looks like a passing one"
## defect the `require()` gate exists to prevent, one step further down. The result is then
## verified by reading the file back, because a missing image or a short write can still
## return OK.
func write_shot(image: Image, path: String) -> bool:
	var err := save_png_verified(image, path)
	var size := written_size(path)
	print("Scenario %s: screenshot %s (%s, %d bytes)" % [scenario, path, error_string(err), size])
	if err != OK or size <= 0:
		require(false, "could not write %s (%s)" % [path, error_string(err)])
		return false
	_shots += 1
	return true


## Writes `image` to `path` with both honesty guards and returns the resulting error.
##
## Static and free of scenario state so any capture harness can use it, not just this driver:
## `src/ui/ui_gallery.gd` still trusts `image.save_png()`'s own return code, which a missing
## image or a short write can pass, and this is the call that fixes it.
##
## The guards, in order: the target is removed first (a stale PNG left in place by a failed
## write reads as this run's result), and the outcome is judged by reading the file back
## (`written_size`) rather than by the return code alone - `ERR_FILE_CANT_WRITE` is reported
## here as `ERR_FILE_CANT_WRITE`, but a zero-byte file that "saved OK" is reported too.
static func save_png_verified(image: Image, path: String) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# A stale PNG is worse than no PNG: it reads as this run's result.
	DirAccess.remove_absolute(path)
	if image == null:
		return ERR_UNAVAILABLE
	var err := image.save_png(path)
	if err == OK and written_size(path) <= 0:
		return ERR_FILE_CANT_WRITE
	return err


## Size of `path` on disk, or 0 when it is missing or unreadable. The screenshot check reads
## the file back rather than trusting the return code, and `require()` turns a 0 into an exit 2.
static func written_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return int(size)


## Number of screenshots written so far (tests).
func shot_count() -> int:
	return _shots


## Builds a writable Omarchy state directory whose `current/theme` is a symlink into the
## fixture tree, so the scenario can flip it mid-floor. Returns "" on failure.
func _make_swap_state(theme: String) -> String:
	# Under the project's own disposable tests/out, so an isolated copy run takes it with it
	# and nothing leaks into user://.
	var dir := ProjectSettings.globalize_path("res://tests/out/theme_swap_state")
	var current := dir.path_join("current")
	DirAccess.make_dir_recursive_absolute(current)
	var name_file := FileAccess.open(current.path_join("theme.name"), FileAccess.WRITE)
	if name_file == null:
		return ""
	name_file.store_string(theme)
	name_file.close()
	if not _link_theme(dir, theme):
		return ""
	return dir


## Points `<state_dir>/current/theme` at the fixture theme directory of `theme`.
func _link_theme(state_dir: String, theme: String) -> bool:
	var target := ProjectSettings.globalize_path(
		"res://tests/fixtures/omarchy/%s/state/current/theme" % theme
	)
	if not DirAccess.dir_exists_absolute(target):
		push_error("TestScenarios: no theme fixture at %s" % target)
		return false
	var link := state_dir.path_join("current/theme")
	var output: Array = []
	var code := OS.execute("ln", ["-sfn", target, link], output, true)
	var name_file := FileAccess.open(state_dir.path_join("current/theme.name"), FileAccess.WRITE)
	if name_file != null:
		name_file.store_string(theme)
		name_file.close()
	return code == 0
