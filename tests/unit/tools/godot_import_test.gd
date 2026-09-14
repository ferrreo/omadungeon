## `tools/godot-import.sh` is the one thing standing between a crashed asset import and a wall
## of meaningless test failures (or a screenshot of the wrong screen printed as "(OK)"). Both
## harnesses used to run it as `godot --import || true` and carry on against a half-imported
## project, so the property tested here is that a failed import fails *loudly* - and, just as
## importantly, that a perfectly ordinary import is not mistaken for a broken one.
class_name GodotImportHarnessTest
extends GdUnitTestSuite

const SaveManagerScript := preload("res://src/core/save_manager.gd")
const HELPER := "res://tools/godot-import.sh"
## What a *successful* `godot --import` prints on its way out every single time. Treating this
## as a failure would turn every green run red, which is the opposite mistake.
const BENIGN_EXIT_NOISE := "ERROR: 1 resources still in use at exit"


func after_test() -> void:
	var dir := DirAccess.open(_workdir())
	if dir == null:
		return
	for name: String in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(_workdir())


## Scratch directory for the fake Godot binaries, inside *this process's* sandbox.
##
## It used to be `OS.get_user_data_dir().path_join("godot_import_test")`, which is the same
## absolute directory for every concurrent run - `user://` is `$XDG_DATA_HOME/omadungeon` and
## the rsync copy `OMADUNGEON_TEST_COPY=1` makes isolates `res://` only. `after_test()` then
## deleted the fake binary out from under the other run, which failed exactly the two cases
## that assert exit 0 and left the two that assert non-zero passing: a missing `GODOT_BIN`
## exits 3. That is a red gate blaming a healthy suite, and it is why this is pid-scoped.
## `tools/test.sh` now also gives each run its own `$XDG_DATA_HOME`; this is the belt to that
## pair of braces, and the one that still holds if someone runs gdUnit without the harness.
func _workdir() -> String:
	var sandbox := SaveManagerScript.resolved_path(SaveManagerScript.test_sandbox_dir())
	return sandbox.path_join("godot_import_test")


## Runs the helper with a stand-in for Godot whose shell body is `fake_body`, and returns its
## exit code. One attempt, so a test does not pay for the retry.
func _run_with_fake_godot(fake_body: String) -> int:
	var work := _workdir()
	DirAccess.make_dir_recursive_absolute(work)
	var fake := work.path_join("fake-godot.sh")
	var file := FileAccess.open(fake, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string("#!/usr/bin/env bash\n%s\n" % fake_body)
	file.close()
	OS.execute("chmod", ["+x", fake])
	var helper := ProjectSettings.globalize_path(HELPER)
	assert_bool(FileAccess.file_exists(helper)).is_true()
	var command := "GODOT_BIN='%s' IMPORT_ATTEMPTS=1 '%s' '%s' '%s'" % [fake, helper, work, work]
	var output: Array = []
	return OS.execute("bash", ["-c", command], output, true)


## Runs the helper with the real two-attempt budget and a stand-in for Godot that aborts once
## and then succeeds, and reports the exit code, everything the helper printed, and what it left
## in the log directory.
func _run_flaky_import() -> Dictionary:
	var work := _workdir()
	DirAccess.make_dir_recursive_absolute(work)
	var fake := work.path_join("fake-godot.sh")
	var file := FileAccess.open(fake, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(
		(
			(
				"#!/usr/bin/env bash\n"
				+ 'counter="$(dirname "$0")/attempts"\n'
				+ 'n=$(cat "$counter" 2>/dev/null || echo 0)\n'
				+ 'n=$((n + 1)); echo "$n" >"$counter"\n'
				+ "if ((n == 1)); then echo 'importing glyphs.png'; kill -ABRT $$; fi\n"
				+ "echo '%s'; exit 0\n"
			)
			% BENIGN_EXIT_NOISE
		)
	)
	file.close()
	OS.execute("chmod", ["+x", fake])
	var helper := ProjectSettings.globalize_path(HELPER)
	var command := "GODOT_BIN='%s' '%s' '%s' '%s' 2>&1" % [fake, helper, work, work]
	var output: Array = []
	var code := OS.execute("bash", ["-c", command], output, true)
	var kept := PackedStringArray()
	var dir := DirAccess.open(work)
	if dir != null:
		for name: String in dir.get_files():
			if name.begins_with("import-"):
				kept.append(name)
	return {"code": code, "output": "\n".join(PackedStringArray(output)), "logs": kept}


## The reported failure: the import segfaulted, the harness swallowed it, and the run that
## followed reported 174 errors that a re-run made vanish.
func test_a_crashed_import_fails_the_harness() -> void:
	var code := _run_with_fake_godot("kill -SEGV $$")
	(
		assert_int(code)
		. override_failure_message("a crashed import was swallowed; the run would report noise")
		. is_not_equal(0)
	)


## The other shape of the same failure: the import exits 0 but left the project half-imported,
## which is what produced `Unable to open file: res://.godot/imported/glyphs.png-*.ctex` x246
## behind a screenshot of a chestless floor.
func test_a_half_imported_project_fails_the_harness() -> void:
	var code := _run_with_fake_godot(
		"echo 'Failed loading resource: res://assets/sprites/enemies/juggler.png'; exit 0"
	)
	assert_int(code).is_not_equal(0)


## And the property the two above must not destroy: an ordinary, successful import - exit
## noise and all - still passes, or the guard would fail every run instead of the broken ones.
func test_an_ordinary_import_still_passes() -> void:
	var code := _run_with_fake_godot("echo '%s'; exit 0" % BENIGN_EXIT_NOISE)
	assert_int(code).override_failure_message("a clean import was reported as a failure").is_equal(
		0
	)


## A script that does not compile is a broken script, not a broken import: `check-scripts.sh`
## reports those, and a bad `.gd` fails its own tests legibly rather than as a wall of noise.
## Failing the import on it would also mean one person mid-edit aborts everybody's harness.
func test_a_script_error_is_not_treated_as_an_import_failure() -> void:
	var code := _run_with_fake_godot(
		"echo 'SCRIPT ERROR: Parse Error: whatever'; echo '   at: (res://src/rooms/prop.gd:180)'"
	)
	(
		assert_int(code)
		. override_failure_message("a mid-edit script error aborted the harness")
		. is_equal(0)
	)


## The import aborts now and then - a `ui-gallery.sh` run printed `godot --import exited 134`
## (SIGABRT) on attempt 1, succeeded on attempt 2 and reported 24 screens - and the built-in
## retry then threw away the only evidence of why. Whether that is load-related or a real import
## bug is a question the next person has to be able to answer from the logs instead of by
## reproducing a race. So a failed attempt's log survives a successful retry, and the retry is
## said out loud rather than swallowed.
func test_a_retried_import_keeps_the_failed_attempts_log_and_says_it_retried() -> void:
	var result := _run_flaky_import()
	(
		assert_int(result["code"] as int)
		. override_failure_message("the retry did not recover the import: %s" % result["output"])
		. is_equal(0)
	)
	var logs := result["logs"] as PackedStringArray
	var kept := PackedStringArray()
	for name: String in logs:
		if name.contains("failed"):
			kept.append(name)
	(
		assert_int(kept.size())
		. override_failure_message(
			"the failed attempt's log was discarded on the successful retry; kept: %s" % str(logs)
		)
		. is_equal(1)
	)
	(
		assert_str(result["output"] as String)
		. override_failure_message("a silent retry reads exactly like a clean first-try import")
		. contains("attempt 2/2")
	)


## The property that must survive it: an import that needed no retry leaves no log behind at
## all, or the screenshot directory fills with "failed" files from runs that never failed.
func test_a_first_try_import_still_leaves_no_log_behind() -> void:
	var work := _workdir()
	assert_int(_run_with_fake_godot("echo '%s'; exit 0" % BENIGN_EXIT_NOISE)).is_equal(0)
	var dir := DirAccess.open(work)
	assert_object(dir).is_not_null()
	for name: String in dir.get_files():
		(
			assert_bool(name.begins_with("import-"))
			. override_failure_message("a clean import left %s behind" % name)
			. is_false()
		)
