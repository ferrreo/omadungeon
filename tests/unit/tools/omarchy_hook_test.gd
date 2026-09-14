## `tools/omarchy-hook/theme-set` against the file `DesktopWatcher` actually polls.
##
## docs §3.5 offers this hook as the optional zero-latency path for a theme switch, and named it
## by path for a long time while the file was not in the repository - the watcher stats
## `$XDG_RUNTIME_DIR/omadungeon/theme-changed` (`HOOK_FILE`) on every tick and nothing could
## ever touch it. The script is three lines of POSIX sh, so what is worth testing is the pair of
## facts a reader of the doc is relying on: it lands on the path the watcher polls, and it does
## nothing at all rather than failing when the desktop it runs on has no runtime directory
## (Omarchy runs every hook in `theme-set.d/` after each switch, and a hook that exits non-zero
## there is the user's problem, not the theme's).
class_name OmarchyHookTest
extends GdUnitTestSuite

const SaveManagerScript := preload("res://src/core/save_manager.gd")
const HOOK_SCRIPT := "res://tools/omarchy-hook/theme-set"
## The path the watcher stats, relative to XDG_RUNTIME_DIR. Mirrored from
## `src/desktop/desktop_watcher.gd`, which is an autoload and has no `class_name` to read it
## from; if the two ever disagree the hook stops working and this test is what says so.
const HOOK_FILE := "omadungeon/theme-changed"

var _runtime_dir: String = ""


func before_test() -> void:
	var sandbox := SaveManagerScript.resolved_path(SaveManagerScript.test_sandbox_dir())
	_runtime_dir = sandbox.path_join("hook_runtime")
	DirAccess.make_dir_recursive_absolute(_runtime_dir)


func after_test() -> void:
	if not _runtime_dir.is_empty():
		OS.execute("rm", ["-rf", _runtime_dir])


func test_the_hook_ships_and_is_executable() -> void:
	var path := ProjectSettings.globalize_path(HOOK_SCRIPT)
	(
		assert_bool(FileAccess.file_exists(HOOK_SCRIPT))
		. override_failure_message("docs §3.5 names %s; it is not in the tree" % HOOK_SCRIPT)
		. is_true()
	)
	var output: Array = []
	assert_int(OS.execute("test", ["-x", path], output)).is_equal(0)


func test_the_hook_touches_the_file_the_watcher_polls() -> void:
	var stamped := _run_hook(_runtime_dir)
	assert_int(stamped).is_equal(0)
	var touched := _runtime_dir.path_join(HOOK_FILE)
	(
		assert_bool(FileAccess.file_exists(touched))
		. override_failure_message(
			"the hook did not touch %s, which is the only thing the watcher stats" % HOOK_FILE
		)
		. is_true()
	)


## A desktop with no runtime directory is not an error: the game retints from the symlink poll
## on its own, and the hook is documented as never required.
func test_the_hook_is_silent_when_there_is_no_runtime_directory() -> void:
	assert_int(_run_hook("")).is_equal(0)


## Runs the hook with `XDG_RUNTIME_DIR` set to `runtime` (unset when empty) and returns its exit
## code. `env` rather than `OS.set_environment`, which would change this process's own
## environment for every suite that runs afterwards.
func _run_hook(runtime: String) -> int:
	var path := ProjectSettings.globalize_path(HOOK_SCRIPT)
	var args := PackedStringArray()
	if runtime.is_empty():
		args.append("-u")
		args.append("XDG_RUNTIME_DIR")
	else:
		args.append("XDG_RUNTIME_DIR=%s" % runtime)
	args.append(path)
	var output: Array = []
	return OS.execute("env", args, output, true)
