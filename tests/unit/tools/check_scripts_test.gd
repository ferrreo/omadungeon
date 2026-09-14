## The compile gate's own unit test.
##
## `tools/check-scripts.sh` is what ARCHITECTURE.md calls "scripts must compile", and for a
## long time it did not compile anything: it ran `godot --headless --import` and grepped, and
## the importer does not re-parse a script whose cache it believes is current, so it printed
## "scripts ok" over a tree holding a hard parse error. The parse now comes from
## `ScriptCompileCheck`, and the two things that verdict rests on are pinned here: a broken
## script really does come back false, and a healthy one really does come back true.
##
## The broken file is written under `user://`, deliberately not into `res://`: anything under
## `res://tests` is part of the sweep this class performs, so a broken fixture there would fail
## the project's own compile gate for everybody. It goes in this process's
## `SaveManager.test_sandbox_dir()` rather than at a fixed `user://` name, because a fixed name
## is shared by every concurrent run and its teardown then deletes somebody else's fixture.
class_name CheckScriptsTest
extends GdUnitTestSuite

const SaveManagerScript := preload("res://src/core/save_manager.gd")
const BROKEN_SOURCE := """
extends RefCounted


func broken() -> int:
	return "not an int" +
"""
## The engine's own message for BROKEN_SOURCE, pinned so the expected error can be consumed.
## If a Godot upgrade rewords it this test fails loudly, which is the right way round.
const PARSE_ERROR := 'Parse Error: Expected expression after "+" operator.'
const HEALTHY_SOURCE := """
extends RefCounted


func fine() -> int:
	return 1
"""

## Set by the probes below, which have to be plain methods: `assert_error()` takes a Callable
## and the verdict has to survive the call.
var _verdict: bool = true
var _bad: PackedStringArray = PackedStringArray()
## Fixture paths, inside *this process's* `user://test/<pid>` sandbox rather than a fixed
## `user://` name. A fixed one is shared by every concurrent run - the rsync copy
## `OMADUNGEON_TEST_COPY=1` makes isolates `res://` and nothing else - so one run's
## `after_test()` deletes the other run's fixture between its write and its read.
var _broken_path: String = ""
var _healthy_path: String = ""


func before() -> void:
	var sandbox := SaveManagerScript.test_sandbox_dir()
	DirAccess.make_dir_recursive_absolute(SaveManagerScript.resolved_path(sandbox))
	_broken_path = sandbox.path_join("qa_check_scripts_broken.gd")
	_healthy_path = sandbox.path_join("qa_check_scripts_healthy.gd")


func after_test() -> void:
	for path: String in [_broken_path, _healthy_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write(path: String, source: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(source)
	file.close()


func _check_broken() -> void:
	_verdict = ScriptCompileCheck.compiles(_broken_path)


func _check_failures() -> void:
	_bad = ScriptCompileCheck.failures([_broken_path, "res://src/combat/hitbox.gd"])


## The engine prints the reason on the way past, which is the whole point - the wrapper greps
## for it - so the parse error is *expected* here and consumed with `is_runtime_error`, or
## gdUnit would count the gate's own evidence as a test error.
func test_a_script_that_does_not_parse_is_reported_as_broken() -> void:
	_write(_broken_path, BROKEN_SOURCE)
	_verdict = true
	await assert_error(_check_broken).is_runtime_error(PARSE_ERROR)
	(
		assert_bool(_verdict)
		. override_failure_message(
			(
				"a script with a parse error was reported as compiling - this is the exact "
				+ "false green the old --import check produced"
			)
		)
		. is_false()
	)


func test_a_script_that_parses_is_reported_as_compiling() -> void:
	_write(_healthy_path, HEALTHY_SOURCE)
	(
		assert_bool(ScriptCompileCheck.compiles(_healthy_path))
		. override_failure_message("a healthy script was reported as broken")
		. is_true()
	)


## The property the parse check could have destroyed: a real project file, with `class_name`
## and autoload references in it, still passes. A check that failed these would be useless
## noise, which is how a gate gets switched off.
func test_real_project_scripts_still_compile() -> void:
	for path: String in ["res://src/combat/hitbox.gd", "res://src/core/run_manager.gd"]:
		(
			assert_bool(ScriptCompileCheck.compiles(path))
			. override_failure_message("%s was reported as not compiling" % path)
			. is_true()
		)


func test_a_missing_file_is_not_a_pass() -> void:
	assert_bool(ScriptCompileCheck.compiles("res://src/does_not_exist.gd")).is_false()


func test_the_sweep_finds_the_tree_and_honours_the_skip() -> void:
	var files := ScriptCompileCheck.collect(["res://src/combat"])
	assert_int(files.size()).is_greater(5)
	assert_bool(files.has("res://src/combat/hitbox.gd")).is_true()
	var skipped := ScriptCompileCheck.collect(["res://src/combat"], "res://src/combat/hitbox.gd")
	assert_int(skipped.size()).is_equal(files.size() - 1)
	assert_bool(skipped.has("res://src/combat/hitbox.gd")).is_false()


## `failures()` names the broken file and nothing else.
func test_failures_names_only_the_broken_file() -> void:
	_write(_broken_path, BROKEN_SOURCE)
	_bad = PackedStringArray()
	await assert_error(_check_failures).is_runtime_error(PARSE_ERROR)
	assert_array(_bad).contains([_broken_path])
	assert_int(_bad.size()).is_equal(1)
