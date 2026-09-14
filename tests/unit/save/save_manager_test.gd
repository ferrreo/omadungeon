class_name SaveManagerTest
extends GdUnitTestSuite

const SaveManagerScript := preload("res://src/core/save_manager.gd")


## Stand-in for an enemy: exposes `def` like EnemyBase does.
class FakeEnemy:
	extends Node2D
	var def: EnemyDef


## Stand-in for a projectile/hitbox: carries its shooter in `source`.
class FakeProjectile:
	extends Node2D
	var source: Node2D


var _dir: String = ""
var _manager: Node
var _earned: Array = []
# The live autoload listens to the same global signals this suite emits, so it is redirected
# into the temp directory for the duration of each test: no test may touch the real save files.
var _autoload: Node
var _autoload_run: String = ""
var _autoload_profile: String = ""


func before_test() -> void:
	_dir = ProjectSettings.globalize_path(
		"res://tests/out/save_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	DirAccess.make_dir_recursive_absolute(_dir)
	_autoload = get_node_or_null(^"/root/SaveManager")
	if _autoload != null:
		_autoload_run = _autoload.run_path
		_autoload_profile = _autoload.profile_path
		_autoload.run_path = _dir.path_join("autoload_run.json")
		_autoload.profile_path = _dir.path_join("autoload_profile.json")
		_autoload.load_profile()
	_manager = SaveManagerScript.new()
	_manager.run_path = _dir.path_join("run.json")
	_manager.profile_path = _dir.path_join("profile.json")
	_earned = []
	EventBus.unlock_earned.connect(_on_unlock_earned)
	add_child(_manager)


func after_test() -> void:
	get_tree().paused = false
	EventBus.unlock_earned.disconnect(_on_unlock_earned)
	if _autoload != null:
		_autoload.cancel_autosave()
		_autoload.run_path = _autoload_run
		_autoload.profile_path = _autoload_profile
		_autoload.load_profile()
	# Free synchronously (runs _exit_tree, which may flush) before wiping the directory.
	if is_instance_valid(_manager):
		_manager.free()
	_manager = null
	var dir := DirAccess.open(_dir)
	if dir != null:
		for name: String in dir.get_files():
			dir.remove(name)
	DirAccess.remove_absolute(_dir)


func _on_unlock_earned(id: StringName, title: String) -> void:
	_earned.append([id, title])


func _files() -> PackedStringArray:
	var dir := DirAccess.open(_dir)
	return dir.get_files() if dir != null else PackedStringArray()


func _state(seed_value: int = 5, floor_index: int = 1) -> RunState:
	var state := RunState.new()
	state.run_seed = seed_value
	state.floor_index = floor_index
	state.class_id = &"ranger"
	state.cleared_room_ids = [0, 2]
	state.gold = 31
	return state


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _enemy(id: StringName) -> FakeEnemy:
	var enemy := auto_free(FakeEnemy.new()) as FakeEnemy
	enemy.def = EnemyDef.new()
	enemy.def.id = id
	return enemy


# --- run file ---------------------------------------------------------------------------------


func test_paths_resolve_to_absolute() -> void:
	assert_str(_manager.run_file_path()).starts_with("/")
	assert_str(_manager.run_file_path()).ends_with("run.json")
	assert_str(SaveManagerScript.resolved_path("user://run.json")).ends_with("/run.json")
	assert_bool(_manager.run_file_path().begins_with(_dir)).is_true()


func test_has_run_save_load_delete() -> void:
	assert_bool(_manager.has_run()).is_false()
	assert_object(_manager.load_run()).is_null()
	assert_bool(_manager.save_run(_state(1234, 2))).is_true()
	assert_bool(_manager.has_run()).is_true()
	var loaded: RunState = _manager.load_run()
	assert_object(loaded).is_not_null()
	assert_int(loaded.run_seed).is_equal(1234)
	assert_int(loaded.seed).is_equal(1234)
	assert_int(loaded.floor_index).is_equal(2)
	assert_str(String(loaded.class_id)).is_equal("ranger")
	assert_array(loaded.cleared_room_ids).contains_exactly([0, 2])
	assert_int(loaded.gold).is_equal(31)
	assert_int(int(loaded.player["gold"])).is_equal(31)
	_manager.delete_run()
	assert_bool(_manager.has_run()).is_false()
	assert_object(_manager.load_run()).is_null()
	assert_bool(FileAccess.file_exists(_manager.run_path)).is_false()


func test_test_runs_never_touch_the_real_save_files() -> void:
	# Guard for the whole project: the autoload redirects its default paths into a sandbox
	# while tests run, so no suite can write the player's real run.json / profile.json.
	assert_bool(SaveManagerScript.is_test_run()).is_true()
	if _autoload == null:
		return
	var real_run := SaveManagerScript.resolved_path("user://run.json")
	var real_profile := SaveManagerScript.resolved_path("user://profile.json")
	assert_str(_autoload_run).is_not_equal(real_run)
	assert_str(_autoload_run).is_not_equal("user://run.json")
	assert_str(_autoload_profile).is_not_equal(real_profile)
	assert_str(_autoload_profile).is_not_equal("user://profile.json")
	assert_str(_autoload_run).contains("/test/")
	assert_bool(FileAccess.file_exists(real_run)).is_false()


func test_rendered_scenario_runs_are_sandboxed_too() -> void:
	# tools/run-scenario.sh drives the real game, so a scenario capture used to overwrite the
	# developer's run.json/profile.json. The launch itself is the marker now.
	var scenario: PackedStringArray = [
		"/usr/bin/godot",
		"--path",
		"/home/dev/omadungeon",
		"--rendering-driver",
		"opengl3",
		"--test-scenario",
		"combat",
		"--screenshot-dir",
		"/home/dev/omadungeon/tests/out",
	]
	assert_bool(SaveManagerScript.args_request_sandbox(scenario)).is_true()
	var gdunit: PackedStringArray = ["godot", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"]
	assert_bool(SaveManagerScript.args_request_sandbox(gdunit)).is_true()
	# A real player's launch must keep writing the real files.
	var player_launch: PackedStringArray = ["/usr/bin/omadungeon", "--fullscreen"]
	assert_bool(SaveManagerScript.args_request_sandbox(player_launch)).is_false()
	assert_bool(SaveManagerScript.args_request_sandbox(PackedStringArray())).is_false()


func test_settings_are_written_into_the_same_sandbox() -> void:
	# GameState persists settings.json next to run.json; a suite that flips a setting must not
	# rewrite the developer's real one either (docs §12).
	var sandbox := SaveManagerScript.test_sandbox_dir()
	assert_str(sandbox).contains("/test/")
	assert_str(GameState.settings_path).is_equal(sandbox + "/settings.json")
	assert_str(GameState.settings_path).is_not_equal("user://settings.json")
	var real_settings := SaveManagerScript.resolved_path("user://settings.json")
	var stamp := (
		FileAccess.get_modified_time(real_settings) if FileAccess.file_exists(real_settings) else -1
	)
	GameState.save_settings()
	(
		assert_bool(
			FileAccess.file_exists(SaveManagerScript.resolved_path(GameState.settings_path))
		)
		. is_true()
	)
	var after := (
		FileAccess.get_modified_time(real_settings) if FileAccess.file_exists(real_settings) else -1
	)
	assert_int(int(after)).is_equal(int(stamp))


## A sandbox is removed in `_exit_tree()`, which is not a shutdown guarantee: a failed
## scenario calls `get_tree().quit(2)` and a wedged capture takes a KILL. 145 empty
## `user://test/<pid>` directories had piled up in the real data directory before anyone
## noticed, so the sweep at startup is what actually bounds the mess.
func test_dead_sandboxes_are_pruned_and_live_ones_are_left_alone() -> void:
	if not DirAccess.dir_exists_absolute("/proc"):
		return
	var root := SaveManagerScript.resolved_path(SaveManagerScript.TEST_DIR)
	var mine := SaveManagerScript.resolved_path(SaveManagerScript.test_sandbox_dir())
	DirAccess.make_dir_recursive_absolute(mine)
	# Above `pid_max` on every Linux, so these two can never be a running process.
	var dead := root.path_join("2147480000")
	var legacy := root.path_join("boot-2147480001")
	for path: String in [dead, legacy]:
		DirAccess.make_dir_recursive_absolute(path)
	_write_text(dead.path_join("profile.json"), "{}")
	_manager._prune_dead_sandboxes()
	(
		assert_bool(DirAccess.dir_exists_absolute(dead))
		. override_failure_message("a dead process's sandbox survived the sweep")
		. is_false()
	)
	(
		assert_bool(DirAccess.dir_exists_absolute(legacy))
		. override_failure_message("the older <scenario>-<pid> naming was not recognised")
		. is_false()
	)
	(
		assert_bool(DirAccess.dir_exists_absolute(mine))
		. override_failure_message("the sweep deleted this very process's sandbox")
		. is_true()
	)


## The sweep keys off the pid in the directory name, and a name it cannot read must be left
## alone rather than guessed at - `user://test` is inside the player's own data directory.
func test_sandbox_pid_reads_both_namings_and_refuses_the_rest() -> void:
	assert_int(SaveManagerScript.sandbox_pid("1807729")).is_equal(1807729)
	assert_int(SaveManagerScript.sandbox_pid("boot-1827501")).is_equal(1827501)
	assert_int(SaveManagerScript.sandbox_pid("unit-42")).is_equal(42)
	for name: String in ["", "-", "notes", "12ab", "boot-", "boot-x"]:
		(
			assert_int(SaveManagerScript.sandbox_pid(name))
			. override_failure_message('"%s" was read as a pid' % name)
			. is_equal(0)
		)


func test_has_run_cache_follows_file_changes() -> void:
	assert_bool(_manager.has_run()).is_false()
	_manager.save_run(_state(1, 1))
	assert_bool(_manager.has_run()).is_true()
	assert_bool(_manager.has_run()).is_true()
	# An external change (different size) is noticed without save_run/delete_run.
	_write_text(_manager.run_path, "[1, 2, 3, 4, 5, 6, 7, 8, 9]")
	assert_bool(_manager.has_run()).is_false()
	DirAccess.remove_absolute(_manager.run_path + ".corrupt")
	_write_text(_manager.run_path, JSON.stringify(_state(2, 2).to_dict()))
	assert_bool(_manager.has_run()).is_true()
	DirAccess.remove_absolute(_manager.run_path)
	assert_bool(_manager.has_run()).is_false()


func test_atomic_write_leaves_no_tmp() -> void:
	_manager.save_run(_state())
	_manager.save_run(_state(6, 3))
	var files := _files()
	assert_bool(files.has("run.json")).is_true()
	assert_bool(files.has("run.json.tmp")).is_false()
	assert_int(_manager.run_write_count).is_equal(2)
	assert_int(_manager.load_run().floor_index).is_equal(3)


func test_corrupt_run_file_is_recovered_from() -> void:
	_write_text(_manager.run_path, "{ this is not json")
	assert_bool(_manager.has_run()).is_false()
	assert_object(_manager.load_run()).is_null()
	assert_bool(FileAccess.file_exists(_manager.run_path)).is_false()
	assert_bool(FileAccess.file_exists(_manager.run_path + ".corrupt")).is_true()
	# Saving afterwards works normally and leaves a clean directory.
	assert_bool(_manager.save_run(_state(8, 4))).is_true()
	assert_bool(_manager.has_run()).is_true()
	assert_int(_manager.load_run().run_seed).is_equal(8)
	assert_bool(_files().has("run.json.tmp")).is_false()


func test_wrong_shape_json_is_not_a_run() -> void:
	_write_text(_manager.run_path, "[1, 2, 3]")
	assert_bool(_manager.has_run()).is_false()
	_write_text(_manager.run_path, '{"version": 1, "seed": "abc"}')
	assert_bool(_manager.has_run()).is_false()
	assert_object(_manager.load_run()).is_null()
	_write_text(_manager.run_path, '{"version": 1, "seed": "12", "run_stats": "x", "player": 3}')
	assert_bool(_manager.has_run()).is_false()
	assert_object(_manager.load_run()).is_null()


func test_has_run_does_not_repair_or_create_files() -> void:
	# Polling has_run() must be side-effect free: no .corrupt backups, no promoted .tmp.
	assert_bool(_manager.has_run()).is_false()
	assert_int(_files().size()).is_equal(0)
	_write_text(_manager.run_path, "{ not json")
	assert_bool(_manager.has_run()).is_false()
	assert_bool(_files().has("run.json.corrupt")).is_false()
	assert_bool(_files().has("run.json")).is_true()
	_write_text(_manager.run_path + ".tmp", JSON.stringify(_state(4, 1).to_dict()))
	assert_bool(_manager.has_run()).is_true()  # the .tmp would be promoted by load_run()
	assert_bool(_files().has("run.json.tmp")).is_true()
	assert_int(_manager.load_run().run_seed).is_equal(4)
	assert_bool(_files().has("run.json.tmp")).is_false()
	assert_bool(_files().has("run.json.corrupt")).is_true()


func test_newer_tmp_wins_over_a_stale_main_file() -> void:
	# Crash between close() and rename(): run.json still holds the previous save and the
	# newer .tmp holds the one that matters. The .tmp must win, not be deleted unread.
	_write_text(_manager.run_path, JSON.stringify(_state(1, 1).to_dict()))
	await get_tree().create_timer(1.1).timeout  # mtime has 1 s resolution
	_write_text(_manager.run_path + ".tmp", JSON.stringify(_state(2, 7).to_dict()))
	assert_bool(_manager.has_run()).is_true()
	var loaded: RunState = _manager.load_run()
	assert_int(loaded.run_seed).is_equal(2)
	assert_int(loaded.floor_index).is_equal(7)
	assert_bool(_files().has("run.json.tmp")).is_false()
	assert_int(_manager.load_run().run_seed).is_equal(2)


func test_older_tmp_loses_to_the_main_file() -> void:
	_write_text(_manager.run_path + ".tmp", JSON.stringify(_state(2, 7).to_dict()))
	await get_tree().create_timer(1.1).timeout
	_write_text(_manager.run_path, JSON.stringify(_state(1, 1).to_dict()))
	assert_int(_manager.load_run().run_seed).is_equal(1)
	assert_bool(_files().has("run.json.tmp")).is_false()


func test_unrecognizable_run_is_backed_up_not_destroyed() -> void:
	# A future version (downgraded game) must never be deleted by the next new_run().
	var future := '{"version": 99, "seed": "5", "future": true}'
	_write_text(_manager.run_path, future)
	assert_bool(_manager.has_run()).is_false()
	assert_object(_manager.load_run()).is_null()
	assert_bool(_files().has("run.json")).is_false()
	assert_bool(_files().has("run.json.corrupt")).is_true()
	var backup := FileAccess.open(_manager.run_path + ".corrupt", FileAccess.READ)
	assert_str(backup.get_as_text()).is_equal(future)
	backup.close()


func test_leftover_tmp_is_promoted_when_main_missing() -> void:
	var data := _state(99, 5).to_dict()
	_write_text(_manager.run_path + ".tmp", JSON.stringify(data))
	assert_bool(_manager.has_run()).is_true()
	assert_int(_manager.load_run().run_seed).is_equal(99)
	assert_bool(_files().has("run.json.tmp")).is_false()
	assert_bool(_files().has("run.json")).is_true()


func test_load_migrates_version_0_file() -> void:
	_write_text(_manager.run_path, '{"seed": 7, "class": "wizard", "floor": 1, "room": 2}')
	assert_bool(_manager.has_run()).is_true()
	var loaded: RunState = _manager.load_run()
	assert_object(loaded).is_not_null()
	assert_int(loaded.run_seed).is_equal(7)
	assert_str(String(loaded.class_id)).is_equal("wizard")
	assert_int(loaded.current_room_id).is_equal(2)


# --- autosave -----------------------------------------------------------------------------------


func test_debounce_collapses_requests_into_one_write() -> void:
	var calls := [0]
	_manager.state_provider = func() -> RunState:
		calls[0] += 1
		return _state(3, calls[0])
	for i: int in 5:
		_manager.request_autosave()
	assert_bool(_manager.has_pending_autosave()).is_true()
	assert_bool(_manager.has_pending_run_save()).is_true()
	assert_int(_manager.run_write_count).is_equal(0)
	await get_tree().create_timer(0.9).timeout
	assert_int(calls[0]).is_equal(1)
	assert_int(_manager.run_write_count).is_equal(1)
	assert_bool(_manager.has_pending_autosave()).is_false()
	assert_bool(_manager.has_pending_run_save()).is_false()
	assert_bool(_manager.has_run()).is_true()
	assert_bool(_files().has("run.json.tmp")).is_false()


func test_debounce_flushes_while_tree_is_paused() -> void:
	_manager.state_provider = func() -> RunState: return _state()
	get_tree().paused = true
	_manager.request_autosave()
	await get_tree().create_timer(0.8, true).timeout
	get_tree().paused = false
	assert_int(_manager.run_write_count).is_equal(1)
	assert_bool(_manager.has_pending_autosave()).is_false()


func test_event_bus_signals_schedule_autosave() -> void:
	_manager.state_provider = func() -> RunState: return _state()
	EventBus.room_cleared.emit(3)
	assert_bool(_manager.has_pending_autosave()).is_true()
	_manager.cancel_autosave()
	assert_bool(_manager.has_pending_autosave()).is_false()
	EventBus.floor_started.emit(1)
	assert_bool(_manager.has_pending_autosave()).is_true()
	_manager.flush_autosave()
	assert_int(_manager.run_write_count).is_equal(1)
	assert_bool(_manager.has_pending_autosave()).is_false()


func test_flush_without_provider_does_not_write() -> void:
	_manager.request_autosave()
	_manager.flush_autosave()
	assert_int(_manager.run_write_count).is_equal(0)
	assert_bool(_manager.has_run()).is_false()


func test_failed_write_keeps_the_snapshot_queued() -> void:
	# A directory in the way of run.json.tmp makes the atomic write fail.
	DirAccess.make_dir_absolute(_manager.run_path + ".tmp")
	_manager.state_provider = func() -> RunState: return _state(42, 2)
	_manager.request_autosave()
	_manager.flush_autosave()
	assert_int(_manager.run_write_count).is_equal(0)
	assert_bool(_manager.has_pending_run_save()).is_true()  # retried, not dropped
	assert_bool(_manager.has_pending_autosave()).is_true()
	DirAccess.remove_absolute(_manager.run_path + ".tmp")
	_manager.flush_autosave()
	assert_int(_manager.run_write_count).is_equal(1)
	assert_bool(_manager.has_pending_run_save()).is_false()
	assert_int(_manager.load_run().run_seed).is_equal(42)


func test_autosave_is_dropped_after_the_run_ended() -> void:
	var calls := [0]
	_manager.state_provider = func() -> RunState:
		calls[0] += 1
		return _state()
	EventBus.run_started.emit(1)
	EventBus.room_cleared.emit(1)
	assert_bool(_manager.has_pending_run_save()).is_true()
	_manager.flush_autosave()
	_manager.delete_run()
	EventBus.run_ended.emit(false)
	EventBus.room_cleared.emit(2)  # a late clear must not resurrect the finished run
	EventBus.floor_started.emit(1)
	_manager.request_autosave()
	assert_bool(_manager.has_pending_run_save()).is_false()
	await get_tree().create_timer(0.7).timeout
	assert_bool(_manager.has_run()).is_false()
	assert_int(calls[0]).is_equal(1)
	# The next run re-arms it.
	EventBus.run_started.emit(2)
	EventBus.room_cleared.emit(0)
	assert_bool(_manager.has_pending_run_save()).is_true()


func test_feeds_survive_a_reparent() -> void:
	_manager.state_provider = func() -> RunState: return _state()
	remove_child(_manager)
	add_child(_manager)
	EventBus.room_cleared.emit(1)
	assert_bool(_manager.has_pending_run_save()).is_true()
	_manager.cancel_autosave()
	EventBus.run_started.emit(1)
	EventBus.player_damaged.emit(3, _enemy(&"honker"))
	EventBus.player_died.emit()
	assert_int(int(_manager.profile.deaths_by_enemy.get("honker", 0))).is_equal(1)


func test_delete_run_cancels_pending_autosave() -> void:
	_manager.state_provider = func() -> RunState: return _state()
	_manager.request_autosave()
	_manager.delete_run()
	assert_bool(_manager.has_pending_autosave()).is_false()
	await get_tree().create_timer(0.7).timeout
	assert_bool(_manager.has_run()).is_false()


func test_profile_only_flush_never_resurrects_a_deleted_run() -> void:
	var calls := [0]
	_manager.state_provider = func() -> RunState:
		calls[0] += 1
		return _state()
	_manager.save_run(_state())
	_manager.delete_run()
	_manager.increment(&"kills")
	_manager.record_death(&"honker")
	assert_bool(_manager.has_pending_autosave()).is_true()
	assert_bool(_manager.has_pending_run_save()).is_false()
	await get_tree().create_timer(0.7).timeout
	assert_bool(_manager.has_run()).is_false()
	assert_int(_manager.run_write_count).is_equal(1)  # only the explicit save above
	assert_int(calls[0]).is_equal(0)
	assert_int(_manager.profile_write_count).is_equal(1)
	assert_bool(_manager.has_pending_autosave()).is_false()


func test_explicit_save_supersedes_queued_autosave() -> void:
	var calls := [0]
	_manager.state_provider = func() -> RunState:
		calls[0] += 1
		return _state(1, 9)
	EventBus.room_cleared.emit(2)
	assert_bool(_manager.save_run(_state(1, 4))).is_true()  # Save & Quit
	assert_bool(_manager.has_pending_autosave()).is_false()
	await get_tree().create_timer(0.7).timeout
	assert_int(calls[0]).is_equal(0)
	assert_int(_manager.run_write_count).is_equal(1)
	assert_int(_manager.load_run().floor_index).is_equal(4)


func test_dirty_run_and_profile_flush_together() -> void:
	_manager.state_provider = func() -> RunState: return _state()
	_manager.record_death(&"juggler")
	_manager.request_autosave()
	_manager.flush_autosave()
	assert_int(_manager.run_write_count).is_equal(1)
	assert_int(_manager.profile_write_count).is_equal(1)
	assert_bool(_manager.has_pending_autosave()).is_false()


func test_pending_autosave_is_flushed_on_exit_tree() -> void:
	_manager.state_provider = func() -> RunState: return _state(77, 6)
	_manager.record_death(&"honker")
	_manager.request_autosave()
	assert_int(_manager.run_write_count).is_equal(0)
	remove_child(_manager)
	assert_int(_manager.run_write_count).is_equal(1)
	assert_int(_manager.profile_write_count).is_equal(1)
	assert_bool(_manager.has_run()).is_true()
	assert_int(_manager.load_run().run_seed).is_equal(77)


func test_pending_autosave_is_flushed_on_close_request() -> void:
	_manager.state_provider = func() -> RunState: return _state(78, 6)
	_manager.request_autosave()
	_manager.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(_manager.run_write_count).is_equal(1)
	assert_bool(_manager.has_pending_autosave()).is_false()
	_manager.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_int(_manager.run_write_count).is_equal(1)


# --- profile / unlocks -----------------------------------------------------------------------


func test_profile_defaults_and_persistence() -> void:
	assert_object(_manager.profile).is_not_null()
	assert_bool(_manager.is_unlocked(&"fighter")).is_true()
	assert_bool(_manager.is_unlocked(&"bulwark")).is_true()
	assert_bool(_manager.is_unlocked(&"oligarch")).is_false()
	_manager.profile.runs = 4
	assert_bool(_manager.save_profile()).is_true()
	assert_bool(_files().has("profile.json")).is_true()
	assert_bool(_files().has("profile.json.tmp")).is_false()
	_manager.profile = Profile.new()
	var reloaded: Profile = _manager.load_profile()
	assert_int(reloaded.runs).is_equal(4)
	assert_object(_manager.profile).is_same(reloaded)


func test_corrupt_profile_yields_default() -> void:
	_write_text(_manager.profile_path, "garbage")
	var profile: Profile = _manager.load_profile()
	assert_int(profile.runs).is_equal(0)
	assert_bool(profile.is_unlocked(&"fighter")).is_true()
	assert_bool(profile.is_unlocked(&"wizard")).is_false()
	assert_bool(_files().has("profile.json.corrupt")).is_true()


func test_unknown_profile_version_is_backed_up_not_overwritten() -> void:
	var newer := '{"version": 99, "unlocks": ["oligarch"], "future_field": true}'
	_write_text(_manager.profile_path, newer)
	var profile: Profile = _manager.load_profile()
	assert_int(profile.runs).is_equal(0)
	assert_bool(profile.is_unlocked(&"oligarch")).is_false()
	assert_bool(_manager.save_profile()).is_true()
	assert_bool(_files().has("profile.json.corrupt")).is_true()
	var backup := FileAccess.open(_manager.profile_path + ".corrupt", FileAccess.READ)
	assert_str(backup.get_as_text()).is_equal(newer)
	backup.close()
	assert_int(_manager.load_profile().version).is_equal(Profile.VERSION)


func test_parseable_but_wrong_shape_profile_is_backed_up() -> void:
	# `{}` (a truncated write) or a foreign JSON object must not silently reset progression.
	_write_text(_manager.profile_path, "{}")
	var profile: Profile = _manager.load_profile()
	assert_int(profile.runs).is_equal(0)
	assert_bool(_files().has("profile.json.corrupt")).is_true()
	DirAccess.remove_absolute(_manager.profile_path + ".corrupt")
	_write_text(_manager.profile_path, '{"hello": "world"}')
	_manager.load_profile()
	assert_bool(_files().has("profile.json.corrupt")).is_true()
	assert_bool(_files().has("profile.json")).is_false()


func test_direct_unlock_emits_and_saves() -> void:
	assert_bool(_manager.unlock(&"oligarch")).is_true()
	assert_bool(_manager.unlock(&"oligarch")).is_false()
	assert_bool(_manager.unlock(&"fireball")).is_false()  # never gated
	assert_int(_earned.size()).is_equal(1)
	assert_str(String(_earned[0][0])).is_equal("oligarch")
	assert_str(str(_earned[0][1])).is_equal("The Oligarch")
	assert_int(_manager.profile_write_count).is_equal(1)
	assert_bool(_manager.load_profile().is_unlocked(&"oligarch")).is_true()


func test_increment_rule_unlocks_whirlwind_once() -> void:
	var earned: Array[StringName] = _manager.increment(&"clowns_killed", 49)
	assert_array(earned).is_empty()
	assert_bool(_manager.is_unlocked(&"whirlwind")).is_false()
	assert_int(_manager.profile_write_count).is_equal(0)
	earned = _manager.increment(&"clowns_killed")
	assert_array(earned).contains_exactly([&"whirlwind"])
	assert_bool(_manager.is_unlocked(&"whirlwind")).is_true()
	assert_int(_manager.profile_write_count).is_equal(1)
	assert_int(_earned.size()).is_equal(1)
	assert_str(str(_earned[0][1])).is_equal("Whirlwind")
	earned = _manager.increment(&"clowns_killed", 100)
	assert_array(earned).is_empty()
	assert_int(_earned.size()).is_equal(1)
	assert_int(_manager.profile.get_counter(&"clowns_killed")).is_equal(150)


func test_all_counter_rules() -> void:
	_manager.increment(&"greybeards_killed", 50)
	_manager.increment(&"tinkerers_killed", 50)
	_manager.increment(&"flawless_floors", 1)
	_manager.increment(&"gold_earned", 999)
	assert_bool(_manager.is_unlocked(&"lucky_coin")).is_false()
	_manager.increment(&"gold_earned", 1)
	for id: StringName in [&"reboot", &"rm_rf", &"tiling_wm", &"lucky_coin"]:
		assert_bool(_manager.is_unlocked(id)).override_failure_message(String(id)).is_true()
	assert_int(_earned.size()).is_equal(4)


## Every rule earns a gated id, and every gated id has a rule that earns it: a gate with no
## rule is content nobody can ever reach, and a rule for an ungated id is a toast for something
## the player already had.
func test_every_rule_targets_a_gated_id() -> void:
	var table: UnlockTable = _manager.rules()
	for def: UnlockDef in table.ordered():
		assert_bool(Profile.is_gated(def.id)).override_failure_message(String(def.id)).is_true()
		assert_str(def.description).override_failure_message(String(def.id)).is_not_empty()
		assert_int(def.threshold).override_failure_message(String(def.id)).is_greater(0)
	for id: StringName in Profile.GATED_UNLOCKS:
		(
			assert_object(table.find(id))
			. override_failure_message("%s is gated but no rule can earn it" % String(id))
			. is_not_null()
		)
	assert_bool(table.matches_profile_gates()).is_true()
	assert_int(table.ordered().size()).is_equal(Profile.GATED_UNLOCKS.size())


func test_record_run_end_floor_semantics() -> void:
	# Dying on floor 3 (index 2) clears two floors: the Ranger (1 floor), not the Oligarch (3).
	var earned: Array[StringName] = _manager.record_run_end(false, 2, &"fighter", "gruvbox")
	assert_array(earned).contains_exactly([&"ranger"])
	assert_bool(_manager.is_unlocked(&"ranger")).is_true()
	assert_bool(_manager.is_unlocked(&"oligarch")).is_false()
	assert_int(_manager.profile.best_floor(&"fighter")).is_equal(3)
	assert_int(_manager.profile.get_counter(&"best_floor")).is_equal(2)
	assert_int(_manager.profile_write_count).is_equal(1)
	# Dying on floor 4 (index 3) means floor 3 was beaten: Oligarch, one write.
	earned = _manager.record_run_end(false, 3, &"fighter", "gruvbox")
	assert_array(earned).contains_exactly([&"oligarch"])
	assert_bool(_manager.is_unlocked(&"oligarch")).is_true()
	assert_int(_manager.profile_write_count).is_equal(2)
	assert_int(_earned.size()).is_equal(2)
	# Winning on the last floor (index 8) counts all nine floors.
	_manager.record_run_end(true, 8, &"wizard", "nord")
	_manager.record_run_end(true, 8, &"fighter", "gruvbox")
	_manager.record_run_end(false, 0, &"fighter", "nord")
	var profile: Profile = _manager.load_profile()
	assert_int(profile.runs).is_equal(5)
	assert_int(profile.wins).is_equal(2)
	assert_int(profile.best_floor(&"fighter")).is_equal(9)
	assert_int(profile.best_floor(&"wizard")).is_equal(9)
	assert_int(profile.theme_wins("gruvbox")).is_equal(1)
	assert_int(profile.theme_wins("nord")).is_equal(1)
	assert_int(profile.get_counter(&"best_floor")).is_equal(9)
	assert_bool(profile.is_unlocked(&"oligarch")).is_true()


func test_record_run_end_victory_on_floor_3_unlocks_oligarch() -> void:
	var earned: Array[StringName] = _manager.record_run_end(true, 2, &"ranger", "nord")
	assert_array(earned).contains_exactly_in_any_order([&"ranger", &"oligarch"])
	assert_int(_manager.profile.get_counter(&"best_floor")).is_equal(3)


func test_record_death_is_flushed_by_autosave() -> void:
	_manager.record_death(&"honker")
	_manager.record_death(&"honker")
	assert_bool(_manager.has_pending_autosave()).is_true()
	assert_bool(_manager.has_pending_run_save()).is_false()
	_manager.flush_autosave()
	assert_int(_manager.profile_write_count).is_equal(1)
	assert_int(int(_manager.load_profile().deaths_by_enemy["honker"])).is_equal(2)


func test_second_death_needs_its_own_damage_source() -> void:
	EventBus.run_started.emit(1)
	EventBus.player_damaged.emit(3, _enemy(&"honker"))
	EventBus.player_died.emit()
	EventBus.player_died.emit()  # revive / double emission: not the honker's kill
	var deaths: Dictionary = _manager.profile.deaths_by_enemy
	assert_int(int(deaths.get("honker", 0))).is_equal(1)
	assert_int(int(deaths.get("unknown", 0))).is_equal(1)


func test_unlock_title_lookup() -> void:
	assert_str(_manager.unlock_title(&"rm_rf")).is_equal("rm -rf")
	assert_str(_manager.unlock_title(&"some_thing")).is_equal("Some Thing")


# --- EventBus counter feeds -------------------------------------------------------------------


func test_gold_earned_counts_positive_deltas_after_floor_start() -> void:
	EventBus.gold_changed.emit(10)  # class start gold, before run_started
	EventBus.run_started.emit(1)
	EventBus.gold_changed.emit(12)  # start loadout tweaks: still guarded
	EventBus.floor_started.emit(0)
	assert_int(_manager.profile.get_counter(&"gold_earned")).is_equal(0)
	EventBus.gold_changed.emit(32)  # +20 pickup
	EventBus.gold_changed.emit(27)  # spent 5: not earned
	EventBus.gold_changed.emit(1027)  # +1000
	assert_int(_manager.profile.get_counter(&"gold_earned")).is_equal(1020)
	assert_bool(_manager.is_unlocked(&"lucky_coin")).is_true()
	EventBus.run_ended.emit(false)
	EventBus.gold_changed.emit(5)  # next run's start gold: baseline only
	assert_int(_manager.profile.get_counter(&"gold_earned")).is_equal(1020)


func test_resume_does_not_count_restored_gold() -> void:
	_manager.save_run(_state(1, 2))  # gold 31
	var state: RunState = _manager.load_run()
	assert_int(state.gold).is_equal(31)
	EventBus.gold_changed.emit(10)  # apply_class start gold
	EventBus.gold_changed.emit(31)  # restore_from_dict
	EventBus.floor_started.emit(2)
	EventBus.gold_changed.emit(41)
	assert_int(_manager.profile.get_counter(&"gold_earned")).is_equal(10)


func test_flawless_floor_is_counted_from_floor_transitions() -> void:
	EventBus.run_started.emit(1)
	EventBus.floor_started.emit(0)
	EventBus.floor_started.emit(1)  # floor 0 cleared without damage
	assert_int(_manager.profile.get_counter(&"flawless_floors")).is_equal(1)
	assert_bool(_manager.is_unlocked(&"tiling_wm")).is_true()
	EventBus.player_damaged.emit(5, null)
	EventBus.floor_started.emit(2)  # floor 1 had damage
	assert_int(_manager.profile.get_counter(&"flawless_floors")).is_equal(1)
	EventBus.run_ended.emit(true)  # final floor cleared clean
	assert_int(_manager.profile.get_counter(&"flawless_floors")).is_equal(2)
	EventBus.run_started.emit(2)
	EventBus.floor_started.emit(0)
	EventBus.player_died.emit()
	EventBus.run_ended.emit(false)
	assert_int(_manager.profile.get_counter(&"flawless_floors")).is_equal(2)


func test_resumed_floor_is_never_flawless() -> void:
	_manager.save_run(_state(1, 2))
	_manager.load_run()
	EventBus.floor_started.emit(2)
	EventBus.floor_started.emit(3)  # history of floor 2 is unknown
	assert_int(_manager.profile.get_counter(&"flawless_floors")).is_equal(0)
	EventBus.floor_started.emit(4)
	assert_int(_manager.profile.get_counter(&"flawless_floors")).is_equal(1)


func test_death_is_attributed_to_last_damage_source() -> void:
	var honker := _enemy(&"honker")
	var shot := auto_free(FakeProjectile.new()) as FakeProjectile
	shot.source = _enemy(&"juggler")
	var trap := auto_free(Node2D.new()) as Node2D
	trap.name = "SpikeTrap3"
	EventBus.run_started.emit(1)
	EventBus.player_damaged.emit(3, honker)
	EventBus.player_damaged.emit(4, shot)
	EventBus.player_died.emit()
	EventBus.player_damaged.emit(4, trap)
	EventBus.player_died.emit()
	EventBus.run_started.emit(2)
	EventBus.player_died.emit()
	var deaths: Dictionary = _manager.profile.deaths_by_enemy
	assert_int(int(deaths.get("juggler", 0))).is_equal(1)
	assert_int(int(deaths.get("spike_trap", 0))).is_equal(1)
	assert_int(int(deaths.get("unknown", 0))).is_equal(1)
	assert_bool(deaths.has("honker")).is_false()
	assert_str(String(SaveManagerScript.attribution_id(null))).is_equal("unknown")
	assert_str(String(SaveManagerScript.attribution_id(honker))).is_equal("honker")
