## Autoload `SaveManager` (docs §12): run persistence, profile, unlocks and debounced autosave.
## Files: `user://run.json` (resumable run) and `user://profile.json` (meta progression);
## `resolved_path()` gives the absolute location. Every write is atomic (`.tmp` + rename).
## project.godot sets `use_custom_user_dir` + `custom_user_dir_name="omadungeon"`, so `user://`
## resolves to `$XDG_DATA_HOME/omadungeon/` as docs §12 requires.
## No `class_name` on purpose: a class named like an autoload shadows the singleton.
##
## Wiring for RunManager:
##   SaveManager.state_provider = Callable(self, "build_run_state")  # -> RunState
##   EventBus.room_cleared / floor_started already trigger `request_autosave()`;
##   call `flush_autosave()` on Save & Quit, `delete_run()` + `record_run_end(...)` on death/win/abandon.
## Run and profile writes are tracked separately: profile-only changes (kills, deaths, gold)
## never rewrite run.json, so a finished run cannot be resurrected by a late counter, and
## autosaves are ignored between `run_ended` and the next `run_started`.
##
## Under a gdUnit4 run, a `--test-scenario` capture, or with `OMADUNGEON_TEST_COPY=1` /
## `OMADUNGEON_SAVE_SANDBOX=1`, the default paths are redirected to a throwaway directory under
## `user://test/`, so neither a test suite nor the rendered-scenario harness can ever touch the
## player's real save files.
extends Node

## Emitted after run.json was written successfully (absolute path).
signal run_saved(path: String)
## Emitted after profile.json was written successfully (absolute path).
signal profile_saved(path: String)

const RUN_FILE := "user://run.json"
const PROFILE_FILE := "user://profile.json"
const TMP_SUFFIX := ".tmp"
const CORRUPT_SUFFIX := ".corrupt"
## Seconds of quiet after the last `request_autosave()` before the write happens.
const AUTOSAVE_DELAY := 0.5
## Attribution used for a death with no known damage source (pits, scripted damage).
const UNKNOWN_KILLER := &"unknown"
## Sandbox for headless test runs; see `test_sandbox_dir()`.
const TEST_DIR := "user://test"
## Where process liveness is read from when pruning stale sandboxes (Linux only).
const PROC_DIR := "/proc"
## Command-line fragments that identify a process which must never write the real save files:
## the gdUnit4 runner and the rendered-scenario driver (`tools/run-scenario.sh`).
const SANDBOX_ARG_MARKERS: Array[String] = ["gdUnit4", "--test-scenario", "--screenshot-dir"]
## Environment variables that force the sandbox on (test copies, scenario harness, CI).
const SANDBOX_ENV_VARS: Array[String] = ["OMADUNGEON_TEST_COPY", "OMADUNGEON_SAVE_SANDBOX"]
## `has_run()` cache sentinels: nothing cached yet / cached "there is no run file".
const STAMP_NONE := -1
const STAMP_MISSING := -2

## Achievement table (`data/progression/unlocks.tres`): when a `UnlockDef`'s `counter` reaches
## its `threshold`, its `id` is granted and `EventBus.unlock_earned(id, title)` fires. Counters
## are fed by `increment()`, `record_run_end()` (raises `best_floor` = floors fully cleared) and
## the EventBus feeds below (`gold_earned`, `flawless_floors`). Every id in the table must be in
## `Profile.GATED_UNLOCKS`, which `UnlockTable.matches_profile_gates()` checks.

# True once this process has swept stale sandboxes. Once per process, not per SaveManager: a
# suite that builds its own instance per test case would otherwise re-walk the directory
# dozens of times a run.
static var _swept_sandboxes: bool = false

## Override before `_ready()` (tests) to redirect the files. `user://` or absolute paths.
var run_path: String = RUN_FILE
var profile_path: String = PROFILE_FILE
## In-memory profile; always non-null after `_ready()`/`load_profile()`.
var profile: Profile = Profile.new()
## The achievement table; loaded on first use so tests can swap it before `_ready()`.
var unlock_table: UnlockTable = null
## Set by RunManager: `Callable() -> RunState`. Run autosaves are skipped while invalid.
var state_provider: Callable = Callable()
## Diagnostics: number of successful run.json / profile.json writes since startup.
var run_write_count: int = 0
var profile_write_count: int = 0

var _autosave_left: float = -1.0
var _run_dirty: bool = false
var _profile_dirty: bool = false
var _warned_no_provider: bool = false
# False between `run_ended` and the next `run_started`: autosaves are dropped so a late
# room_cleared cannot recreate run.json for a finished run. Unknown (= true) before any run.
var _run_live: bool = true
# has_run() cache: a stamp built from the run file's and temp file's modification times
# (STAMP_NONE = nothing cached, STAMP_MISSING = "no file", also cached so polling is free).
var _has_run_stamp: int = STAMP_NONE
var _has_run_cached: bool = false
# EventBus feeds for achievement counters (gold_earned, flawless_floors, deaths_by_enemy).
var _gold_total: int = -1
var _gold_guard: bool = true
var _floor_tracking: bool = false
var _floor_damage: int = 0
var _skip_next_floor: bool = false
var _last_killer: StringName = UNKNOWN_KILLER
# Non-empty while this process writes into a test sandbox (wiped on exit).
var _sandbox_dir: String = ""
# Ids unlocked since the current run started, and the counter values it started from, so the
# run summary can tell the player what the run earned instead of leaving meta progress
# invisible until they go looking for it.
var _run_unlocks: Array[StringName] = []
var _run_counters_at_start: Dictionary = {}


## Connecting here (not in `_ready()`) keeps the feeds alive when the node is removed from the
## tree and added back again; `_exit_tree()` takes them down.
func _enter_tree() -> void:
	_connect(EventBus.room_cleared, _on_room_cleared)
	_connect(EventBus.floor_started, _on_floor_started)
	_connect(EventBus.run_started, _on_run_started)
	_connect(EventBus.run_ended, _on_run_ended)
	_connect(EventBus.gold_changed, _on_gold_changed)
	_connect(EventBus.player_damaged, _on_player_damaged)
	_connect(EventBus.player_died, _on_player_died)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_redirect_paths_for_tests()
	rules()
	load_profile()


func _exit_tree() -> void:
	if has_pending_autosave():
		flush_autosave()
	_clear_sandbox()
	_disconnect(EventBus.room_cleared, _on_room_cleared)
	_disconnect(EventBus.floor_started, _on_floor_started)
	_disconnect(EventBus.run_started, _on_run_started)
	_disconnect(EventBus.run_ended, _on_run_ended)
	_disconnect(EventBus.gold_changed, _on_gold_changed)
	_disconnect(EventBus.player_damaged, _on_player_damaged)
	_disconnect(EventBus.player_died, _on_player_died)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and has_pending_autosave():
		flush_autosave()


func _process(delta: float) -> void:
	if _autosave_left < 0.0:
		return
	_autosave_left -= delta
	if _autosave_left < 0.0:
		_autosave_left = -1.0
		flush_autosave()


# --- paths -------------------------------------------------------------------------------


## Absolute filesystem path for a `user://` (or any) Godot path.
static func resolved_path(path: String) -> String:
	return ProjectSettings.globalize_path(path)


## True while this process must write into a save sandbox instead of the player's files: the
## gdUnit4 runner, a `--test-scenario` capture, or one of `SANDBOX_ENV_VARS` set to "1".
static func is_test_run() -> bool:
	for name: String in SANDBOX_ENV_VARS:
		if OS.get_environment(name) == "1":
			return true
	if args_request_sandbox(OS.get_cmdline_args()):
		return true
	return args_request_sandbox(OS.get_cmdline_user_args())


## True when a command line carries one of `SANDBOX_ARG_MARKERS`. Split out of `is_test_run()`
## so the rule is unit-testable without launching a second process.
static func args_request_sandbox(args: PackedStringArray) -> bool:
	for arg: String in args:
		for marker: String in SANDBOX_ARG_MARKERS:
			if arg.contains(marker):
				return true
	return false


## Per-process sandbox directory for test runs, e.g. `user://test/12345`. Static so anything
## else that persists into `user://` (GameState's settings.json) can share the same sandbox.
static func test_sandbox_dir() -> String:
	return "%s/%d" % [TEST_DIR, OS.get_process_id()]


## Redirects the *default* paths into the test sandbox during a test run so no suite can write
## the player's real run.json/profile.json. Paths overridden by the caller are left alone.
func _redirect_paths_for_tests() -> void:
	if not is_test_run():
		return
	var dir := test_sandbox_dir()
	DirAccess.make_dir_recursive_absolute(resolved_path(dir))
	_sandbox_dir = dir
	if not _swept_sandboxes:
		_swept_sandboxes = true
		_prune_dead_sandboxes()
	if run_path == RUN_FILE:
		run_path = dir + "/run.json"
	if profile_path == PROFILE_FILE:
		profile_path = dir + "/profile.json"


## Removes this process's test sandbox (files and directory) when the game shuts down.
func _clear_sandbox() -> void:
	if _sandbox_dir.is_empty():
		return
	var abs_dir := resolved_path(_sandbox_dir)
	_sandbox_dir = ""
	_remove_tree(abs_dir)


## Deletes sandboxes belonging to processes that are gone. `_exit_tree()` is not a shutdown
## guarantee — a scenario that fails calls `get_tree().quit(2)`, a wedged run gets a KILL —
## so without a sweep at startup the player's data directory collects one `user://test/<pid>`
## per crashed run and never gives the space back.
##
## Liveness comes from `/proc`, because `OS.is_process_running()` only answers for children
## this process spawned, and pruning by age would race a sibling suite that is still running.
## With no `/proc` (not Linux) nothing is pruned: leaking a directory is cheaper than deleting
## the sandbox out from under a live run.
func _prune_dead_sandboxes() -> void:
	if not DirAccess.dir_exists_absolute(PROC_DIR):
		return
	var root := resolved_path(TEST_DIR)
	var dir := DirAccess.open(root)
	if dir == null:
		return
	var mine := OS.get_process_id()
	for name: String in dir.get_directories():
		var pid := sandbox_pid(name)
		if pid <= 0 or pid == mine:
			continue
		if DirAccess.dir_exists_absolute("%s/%d" % [PROC_DIR, pid]):
			continue
		_remove_tree(root.path_join(name))


## Process id a sandbox directory belongs to, or 0 when the name is not one of ours. Handles
## both the current `<pid>` naming and the older `<scenario>-<pid>` one still on disk.
static func sandbox_pid(dir_name: String) -> int:
	var tail := dir_name.substr(dir_name.rfind("-") + 1)
	if tail.is_empty() or not tail.is_valid_int():
		return 0
	return maxi(0, tail.to_int())


## Recursively deletes `abs_dir`. Sandboxes are flat today; the recursion keeps a future
## nested one from turning this into a silent no-op.
static func _remove_tree(abs_dir: String) -> void:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	for name: String in dir.get_files():
		dir.remove(name)
	for name: String in dir.get_directories():
		_remove_tree(abs_dir.path_join(name))
	DirAccess.remove_absolute(abs_dir)


func run_file_path() -> String:
	return resolved_path(run_path)


func profile_file_path() -> String:
	return resolved_path(profile_path)


# --- run ---------------------------------------------------------------------------------


## True when a resumable run exists on disk (the file, or a newer leftover `.tmp`, must parse
## as a valid run). Cached against the files' modification times — including the "no file"
## answer — and free of side effects, so a UI may poll it every frame. Repairs (promoting a
## `.tmp`, backing up a corrupt file) happen in `load_run()`, never here.
func has_run() -> bool:
	var stamp := _run_stamp()
	if stamp == _has_run_stamp:
		return _has_run_cached
	var ok := _parses_as_run(run_file_path())
	if not ok:
		ok = _parses_as_run(run_file_path() + TMP_SUFFIX)
	_has_run_stamp = stamp
	_has_run_cached = ok
	return ok


## True when `abs_path` holds a resumable run. Read-only: nothing is renamed or removed.
func _parses_as_run(abs_path: String) -> bool:
	var data := _peek_json(abs_path)
	return not data.is_empty() and RunState.is_valid(RunState.migrate(data))


## Writes `state` atomically. An explicit save supersedes a queued run autosave.
## Returns false (and warns) on I/O failure.
func save_run(state: RunState) -> bool:
	if state == null:
		return false
	if not _write_json_atomic(run_path, state.to_dict()):
		return false
	_run_dirty = false
	_run_live = true
	if not _profile_dirty:
		_autosave_left = -1.0
	_invalidate_has_run()
	run_write_count += 1
	run_saved.emit(run_file_path())
	return true


## Loads and migrates run.json; null when absent, corrupt or unrecognizable.
## Also primes the counter feeds for a resume (restored gold is not "earned").
func load_run() -> RunState:
	var data := _read_json(run_path)
	_invalidate_has_run()  # _read_json may have promoted a .tmp or moved a corrupt file aside
	if data.is_empty():
		return null
	var state := RunState.from_dict(data)
	if state == null:
		# Parses, but is not a run we understand (a future version, a wrong shape). Keep it:
		# a downgrade or a half-bad file must never be destroyed by the next new_run().
		push_warning(
			(
				"SaveManager: %s is not a resumable run (version %s), backing it up as %s"
				% [run_file_path(), str(data.get("version", "?")), CORRUPT_SUFFIX]
			)
		)
		_move_aside(run_file_path())
		_invalidate_has_run()
		return null
	_gold_total = state.gold
	_gold_guard = true
	_floor_tracking = false
	_skip_next_floor = true
	_run_live = true
	return state


## Deletes run.json (and any stray temp file) and drops any queued run autosave. A dirty
## profile stays queued; profile-only flushes never write run.json.
func delete_run() -> void:
	cancel_autosave()
	_remove(run_path)
	_remove(run_path + TMP_SUFFIX)
	_invalidate_has_run()


# --- autosave ------------------------------------------------------------------------------


## Schedules a run save 0.5 s from now; repeated calls inside the window collapse into one write.
## Dropped once the run has ended (`EventBus.run_ended`) until the next `run_started`, so a late
## room_cleared cannot resurrect a finished run.
func request_autosave() -> void:
	if not _run_live:
		return
	_run_dirty = true
	_autosave_left = AUTOSAVE_DELAY


## Drops the queued run write. A dirty profile keeps its pending flush.
func cancel_autosave() -> void:
	_run_dirty = false
	if not _profile_dirty:
		_autosave_left = -1.0


## True while a debounced flush (run and/or profile) is queued.
func has_pending_autosave() -> bool:
	return _autosave_left >= 0.0


## True while a run snapshot is queued for writing.
func has_pending_run_save() -> bool:
	return _run_dirty


## Performs any pending work immediately: the run snapshot via `state_provider` (only when a
## run save was requested) and the profile when dirty. Safe to call at any time (Save & Quit,
## window close, tree exit).
func flush_autosave() -> void:
	_autosave_left = -1.0
	if _run_dirty:
		if state_provider.is_valid():
			var state: RunState = state_provider.call()
			# Keep the request queued when the write failed (disk full, rename error) so the
			# next window retries instead of silently dropping the snapshot.
			_run_dirty = state != null and not save_run(state)
			if _run_dirty:
				_autosave_left = AUTOSAVE_DELAY
		else:
			if not _warned_no_provider:
				_warned_no_provider = true
				push_warning("SaveManager: autosave requested but no state_provider is set")
			_run_dirty = false
	if _profile_dirty:
		save_profile()


# --- profile ---------------------------------------------------------------------------------


## Loads profile.json into `profile`. A missing file yields a fresh default; a corrupt or
## unrecognizable one (bad JSON, unknown future version, wrong shape) is moved aside as
## `.corrupt` first so it is never overwritten by the defaults.
func load_profile() -> Profile:
	var data := _read_json(profile_path)
	if data.is_empty():
		profile = Profile.new()
	elif Profile.is_valid(Profile.migrate(data)):
		profile = Profile.from_dict(data)
	else:
		push_warning(
			(
				"SaveManager: %s has an unknown shape (version %s), backing it up as %s"
				% [profile_file_path(), str(data.get("version", "?")), CORRUPT_SUFFIX]
			)
		)
		_move_aside(profile_file_path())
		profile = Profile.new()
	_profile_dirty = false
	return profile


func save_profile() -> bool:
	if not _write_json_atomic(profile_path, profile.to_dict()):
		return false
	_profile_dirty = false
	if not _run_dirty:
		_autosave_left = -1.0
	profile_write_count += 1
	profile_saved.emit(profile_file_path())
	return true


## Marks the profile for writing on the next autosave flush (cheap for hot paths like kills).
## Never schedules a run.json write on its own.
func mark_profile_dirty() -> void:
	_profile_dirty = true
	if not has_pending_autosave():
		_autosave_left = AUTOSAVE_DELAY


# --- unlocks / achievements ---------------------------------------------------------------------


## True for every ungated id and for gated ids once earned (see Profile.GATED_UNLOCKS).
func is_unlocked(id: StringName) -> bool:
	return profile.is_unlocked(id)


## Grants `id` directly (debug menu, scripted rewards). Emits `unlock_earned` and saves
## when it is new. Returns true only for a fresh unlock.
func unlock(id: StringName, title: String = "") -> bool:
	if not profile.unlock(id):
		return false
	EventBus.unlock_earned.emit(id, title if not title.is_empty() else unlock_title(id))
	save_profile()
	return true


## The achievement table, loaded on first use.
func rules() -> UnlockTable:
	if unlock_table == null:
		unlock_table = UnlockTable.load_default()
	return unlock_table


## Human title for an unlock id, from the table or a capitalized fallback.
func unlock_title(id: StringName) -> String:
	var def := rules().find(id)
	return def.title if def != null and not def.title.is_empty() else String(id).capitalize()


## What the player has to do to earn `id` ("Clear a floor."); "" for an id with no rule.
func unlock_description(id: StringName) -> String:
	var def := rules().find(id)
	return def.description if def != null else ""


## Adds to an achievement counter (e.g. &"clowns_killed"), evaluates the rule table and
## returns the ids newly unlocked. The profile is saved immediately on an unlock, otherwise
## lazily on the next autosave flush.
func increment(counter: StringName, amount: int = 1) -> Array[StringName]:
	profile.add_counter(counter, amount)
	var earned := _evaluate_rules()
	if earned.is_empty():
		mark_profile_dirty()
	else:
		save_profile()
	return earned


## Records the outcome of a finished run. `floor_index` is the 0-based floor the run ended on
## (RunManager.floor_index). Floors fully cleared = `floor_index` on a loss, `floor_index + 1`
## on a win; that count feeds the `best_floor` counter (docs §12: Oligarch after *beating*
## floor 3). `best_floor_per_class` stores the 1-based floor number reached for the stats page.
## Updates lifetime stats, evaluates unlocks and writes the profile exactly once.
func record_run_end(
	victory: bool, floor_index: int, class_id: StringName, theme_name: String
) -> Array[StringName]:
	var floor_number := maxi(0, floor_index) + 1
	var floors_cleared := floor_number if victory else maxi(0, floor_index)
	profile.runs += 1
	var class_key := String(class_id)
	profile.best_floor_per_class[class_key] = maxi(profile.best_floor(class_id), floor_number)
	if victory:
		profile.wins += 1
		if not theme_name.is_empty():
			profile.per_theme_wins[theme_name] = profile.theme_wins(theme_name) + 1
	profile.raise_counter(&"best_floor", floors_cleared)
	var earned := _evaluate_rules()
	save_profile()
	return earned


## Records which enemy killed the player (stats page). Called automatically from the
## `player_died` feed with the last damage source; call it directly to override.
func record_death(enemy_id: StringName) -> void:
	var key := String(enemy_id if enemy_id != &"" else UNKNOWN_KILLER)
	profile.deaths_by_enemy[key] = int(profile.deaths_by_enemy.get(key, 0)) + 1
	mark_profile_dirty()


## Stable id for whatever dealt damage: an enemy's `def.id`, following a projectile/hitbox
## `source` chain up to a few hops; otherwise the node name in snake_case without digits.
static func attribution_id(source: Node) -> StringName:
	var node := source
	for _hop in range(4):
		if node == null or not is_instance_valid(node):
			break
		var def: Variant = node.get(&"def")
		if def is Resource:
			var id: Variant = (def as Resource).get(&"id")
			if id is StringName and id != &"":
				return id
		var next: Variant = node.get(&"source")
		if next is Node and next != node:
			node = next
			continue
		break
	if source == null or not is_instance_valid(source):
		return UNKNOWN_KILLER
	var name := String(source.name).replace("@", "").to_snake_case().rstrip("0123456789_")
	return StringName(name) if not name.is_empty() else UNKNOWN_KILLER


## Evaluates the rule table, unlocking and announcing anything newly reached. Does not write;
## callers decide when to save.
func _evaluate_rules() -> Array[StringName]:
	var earned: Array[StringName] = []
	for def: UnlockDef in rules().ordered():
		if def == null or def.id == &"" or profile.is_unlocked(def.id):
			continue
		if profile.get_counter(def.counter) >= def.threshold:
			profile.unlock(def.id)
			earned.append(def.id)
			if not _run_unlocks.has(def.id):
				_run_unlocks.append(def.id)
			EventBus.unlock_earned.emit(def.id, def.title)
	return earned


# --- progress the player can see ------------------------------------------------------------


## Every gated unlock with the state the UI needs, board order with the locked ones the player
## is closest to first: `{id, title, description, kind, counter, value, threshold, fraction,
## progress, unlocked, earned_this_run}`.
##
## This is what "a place to see what you have unlocked and what is close" is built from
## (`ClassSelect`'s unlock board, `RunSummary`'s progress section). Nothing here is power: the
## kinds are classes and abilities only.
func progress_rows() -> Array[Dictionary]:
	var locked: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	for def: UnlockDef in rules().ordered():
		if def == null or def.id == &"":
			continue
		var value := profile.get_counter(def.counter)
		var unlocked := profile.is_unlocked(def.id)
		var row := {
			"id": def.id,
			"title": def.title,
			"description": def.description,
			"kind": "class" if def.grants_class() else "ability",
			"counter": def.counter,
			"value": mini(value, def.threshold) if not unlocked else def.threshold,
			"threshold": def.threshold,
			"fraction": 1.0 if unlocked else def.fraction(value),
			"progress": def.progress_text(def.threshold if unlocked else value),
			"unlocked": unlocked,
			"earned_this_run": _run_unlocks.has(def.id),
		}
		if unlocked:
			done.append(row)
		else:
			locked.append(row)
	locked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["fraction"]) > float(b["fraction"])
	)
	var out: Array[Dictionary] = []
	out.append_array(locked)
	out.append_array(done)
	return out


## The single locked unlock the player is closest to, or `{}` when everything is earned.
func next_unlock() -> Dictionary:
	for row: Dictionary in progress_rows():
		if not bool(row["unlocked"]):
			return row
	return {}


## Ids unlocked since the current run started (cleared by `run_started`). The run summary's
## "this run earned" list.
func unlocks_this_run() -> Array[StringName]:
	return _run_unlocks.duplicate()


## How far each achievement counter moved during the current run: counter name -> delta.
## Only counters that actually moved are listed.
func counter_gains_this_run() -> Dictionary:
	var out: Dictionary = {}
	for def: UnlockDef in rules().ordered():
		var key := String(def.counter)
		if out.has(key):
			continue
		var gain := profile.get_counter(def.counter) - int(_run_counters_at_start.get(key, 0))
		if gain > 0:
			out[key] = gain
	return out


# --- signal handlers ------------------------------------------------------------------------------


func _on_room_cleared(_room_id: int) -> void:
	request_autosave()


func _on_floor_started(_floor_index: int) -> void:
	request_autosave()
	_gold_guard = false
	# A floor entered without damage on the previous one was cleared flawlessly.
	if _floor_tracking and _floor_damage == 0:
		increment(&"flawless_floors")
	_floor_tracking = not _skip_next_floor  # a resumed floor has unknown history
	_skip_next_floor = false
	_floor_damage = 0


func _on_run_started(_run_seed: int) -> void:
	_run_live = true
	_run_unlocks = []
	_run_counters_at_start = {}
	for def: UnlockDef in rules().ordered():
		_run_counters_at_start[String(def.counter)] = profile.get_counter(def.counter)
	_gold_guard = true  # start gold / loadout emissions are not "earned"
	_floor_tracking = false
	_skip_next_floor = false
	_floor_damage = 0
	_last_killer = UNKNOWN_KILLER


func _on_run_ended(victory: bool) -> void:
	if victory and _floor_tracking and _floor_damage == 0:
		increment(&"flawless_floors")
	_run_live = false
	cancel_autosave()
	_floor_tracking = false
	_gold_total = -1
	_gold_guard = true


## `gold_changed` carries the new total; positive deltas count as earned once a floor is live.
func _on_gold_changed(total: int) -> void:
	if _gold_guard or _gold_total < 0:
		_gold_total = total
		return
	if total > _gold_total:
		increment(&"gold_earned", total - _gold_total)
	_gold_total = total


func _on_player_damaged(amount: int, source: Node2D) -> void:
	_floor_damage += maxi(0, amount)
	_last_killer = attribution_id(source)


func _on_player_died() -> void:
	_floor_tracking = false
	record_death(_last_killer)
	_last_killer = UNKNOWN_KILLER  # a second death needs its own damage source


# --- file helpers ---------------------------------------------------------------------------------


## Writes `data` as JSON to `path` atomically: temp file first, then rename over the target.
func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var abs_path := resolved_path(path)
	var dir := abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			push_warning("SaveManager: cannot create %s (%s)" % [dir, error_string(mk)])
			return false
	var tmp := abs_path + TMP_SUFFIX
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning(
			"SaveManager: cannot open %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	# A full disk or a quota fails here, not at open(): without this check the short temp file
	# is renamed over a good save and `save_run()` reports success over a truncated run.
	var wrote := file.get_error()
	file.close()
	if wrote != OK:
		push_warning("SaveManager: writing %s failed (%s)" % [tmp, error_string(wrote)])
		DirAccess.remove_absolute(tmp)
		return false
	var err := DirAccess.rename_absolute(tmp, abs_path)
	if err != OK:
		push_warning("SaveManager: rename %s failed (%s)" % [abs_path, error_string(err)])
		DirAccess.remove_absolute(tmp)
		return false
	return true


## Reads and parses `path`, repairing as needed. Returns {} when missing or corrupt.
## A leftover `.tmp` (crash between write and rename) that parses and is at least as new as
## the main file wins and is promoted over it; an older or unparsable one is removed.
## A corrupt main file is moved aside as `.corrupt`.
func _read_json(path: String) -> Dictionary:
	var abs_path := resolved_path(path)
	var tmp := abs_path + TMP_SUFFIX
	var main_data: Dictionary = {}
	if FileAccess.file_exists(abs_path):
		main_data = _parse_file(abs_path)
		if main_data.is_empty():
			push_warning("SaveManager: %s is corrupt, moving to %s" % [abs_path, CORRUPT_SUFFIX])
			_move_aside(abs_path)
	if FileAccess.file_exists(tmp):
		var recovered := _parse_file(tmp)
		var newer := main_data.is_empty() or _mtime(tmp) >= _mtime(abs_path)
		if not recovered.is_empty() and newer:
			if not main_data.is_empty():
				DirAccess.remove_absolute(abs_path)
			if DirAccess.rename_absolute(tmp, abs_path) == OK:
				return recovered
			return main_data if not main_data.is_empty() else recovered
		DirAccess.remove_absolute(tmp)
	return main_data


func _parse_file(abs_path: String) -> Dictionary:
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


## Renames `abs_path` to `<abs_path>.corrupt` (replacing an older backup).
func _move_aside(abs_path: String) -> void:
	var backup := abs_path + CORRUPT_SUFFIX
	DirAccess.remove_absolute(backup)
	var err := DirAccess.rename_absolute(abs_path, backup)
	if err != OK:
		push_warning("SaveManager: could not back up %s (%s)" % [abs_path, error_string(err)])
		DirAccess.remove_absolute(abs_path)


func _remove(path: String) -> void:
	var abs_path := resolved_path(path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


## Parses `abs_path` without touching the filesystem (used by `has_run()`).
func _peek_json(abs_path: String) -> Dictionary:
	if not FileAccess.file_exists(abs_path):
		return {}
	return _parse_file(abs_path)


## Cache key for `has_run()`: modification time and size of run.json and run.json.tmp, both
## read with cheap stat calls (no file is opened).
func _run_stamp() -> int:
	var abs_path := run_file_path()
	var tmp := abs_path + TMP_SUFFIX
	var main_time := _mtime(abs_path)
	var tmp_time := _mtime(tmp)
	if main_time < 0 and tmp_time < 0:
		return STAMP_MISSING
	var sizes := [_size(abs_path), _size(tmp)]
	return hash([main_time, tmp_time, sizes[0], sizes[1]])


func _invalidate_has_run() -> void:
	_has_run_stamp = STAMP_NONE
	_has_run_cached = false


## Modification time of `abs_path`, or -1 when it does not exist.
static func _mtime(abs_path: String) -> int:
	if not FileAccess.file_exists(abs_path):
		return -1
	return int(FileAccess.get_modified_time(abs_path))


## Size of `abs_path` in bytes, or -1 when it does not exist (stat only, no open).
static func _size(abs_path: String) -> int:
	if not FileAccess.file_exists(abs_path):
		return -1
	return int(FileAccess.get_size(abs_path))


static func _connect(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


static func _disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
