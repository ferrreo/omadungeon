## Redirects the save autoloads into a throwaway directory, so a tool that drives the real
## game from a `-s` main loop can never overwrite the player's run.json, profile.json or
## settings.json.
##
## `SaveManager` sandboxes itself only for launches it recognises — the gdUnit runner, a
## `--test-scenario` capture, or `OMADUNGEON_TEST_COPY` / `OMADUNGEON_SAVE_SANDBOX` set to "1"
## (see `SaveManager.is_test_run()`). A main-loop script started with `-s` is none of those, so
## it has to say so itself, before it starts a run. Every entry point in `src/core/perf/` that
## touches `RunManager` calls `apply()` first.
##
## Everything is reached through `get_node_or_null` + `set()` on purpose: a `-s` script is
## compiled before the autoloads become global identifiers, so naming `SaveManager` here would
## stop this file from compiling at boot.
class_name PerfSandbox
extends RefCounted

const ROOT := "user://test"


## Points the save autoloads at `user://test/<label>-<pid>/` and returns that directory.
## Returns an empty string when the autoloads are absent (nothing to protect).
static func apply(tree: SceneTree, label: String) -> String:
	if tree == null or tree.root == null:
		return ""
	var dir := "%s/%s-%d" % [ROOT, label, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var touched := false
	var save := tree.root.get_node_or_null(^"SaveManager")
	if save != null:
		save.set(&"run_path", dir + "/run.json")
		save.set(&"profile_path", dir + "/profile.json")
		touched = true
	var state := tree.root.get_node_or_null(^"GameState")
	if state != null:
		state.set(&"settings_path", dir + "/settings.json")
		touched = true
	return dir if touched else ""


## True when the save autoloads write inside `ROOT` (either because `apply()` ran or because
## the launch was already recognised as a test run). Entry points assert this before the first
## `RunManager.new_run()`.
static func is_safe(tree: SceneTree) -> bool:
	if tree == null or tree.root == null:
		return true
	var save := tree.root.get_node_or_null(^"SaveManager")
	if save == null:
		return true
	var run_path := str(save.get(&"run_path"))
	return run_path.begins_with(ROOT + "/")
