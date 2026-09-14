## The release gate's own isolation, checked from inside the run.
##
## `OMADUNGEON_TEST_COPY=1` rsyncs the project, which isolates `res://` and nothing else.
## `user://` is `$XDG_DATA_HOME/omadungeon` (`project.godot` sets `use_custom_user_dir`), so
## every copy of the project resolved it to the *same* absolute directory: two gate runs at
## once shared gdUnit4's `user://tmp` scratch, every fixture any suite writes at a fixed
## `user://` name, and the player's own `profile.json`. One run's teardown then deleted the
## other's fixture mid-test and the gate went red naming suites that were perfectly healthy.
## That is worse than a flaky gate — it is a gate that lies about why it failed, and three
## reviews in a row wrote "N consecutive clean runs" on top of it.
##
## `tools/test.sh` now gives every run its own `$XDG_DATA_HOME`. This suite is the guard on
## that: it fails the run if the isolation is not actually in force, so the export cannot be
## dropped again and go unnoticed. It also pins the property the isolation could plausibly
## have destroyed — that `user://` is still a *working* directory and saving still round-trips
## through it — because a redirect that broke saving would pass every isolation check here.
class_name UserDirIsolationTest
extends GdUnitTestSuite

const SaveManagerScript := preload("res://src/core/save_manager.gd")
## Exported by `tools/test.sh` alongside `XDG_DATA_HOME`; the directory `user://` must live in.
const MARKER_ENV := "OMADUNGEON_TEST_USER_DIR"
const TESTS_ROOT := "res://tests"
## This suite's own source names the call it forbids, so it cannot be its own subject.
const SELF_PATH := "res://tests/unit/tools/user_dir_isolation_test.gd"


## The run has a `user://` of its own, not the one every other run on this machine is using.
##
## Deliberately a hard failure rather than a quiet skip when the marker is missing: a guard
## that passes when the thing it guards is switched off is the exact shape of false green this
## project keeps paying for. `tools/test.sh` is how tests are run (ARCHITECTURE §1); if you are
## looking at this failure, you ran gdUnit4 some other way.
func test_the_harness_gave_this_run_its_own_user_directory() -> void:
	var marker := OS.get_environment(MARKER_ENV)
	(
		assert_str(marker)
		. override_failure_message(
			(
				(
					"%s is not set, so this run shares user:// with every other run on the box. "
					+ "Run the suite through tools/test.sh, which exports it with XDG_DATA_HOME."
				)
				% MARKER_ENV
			)
		)
		. is_not_empty()
	)
	var user_dir := OS.get_user_data_dir()
	(
		assert_str(user_dir)
		. override_failure_message(
			(
				(
					"user:// resolved to %s, outside this run's private data directory %s. "
					+ "Two concurrent gate runs would write each other's files."
				)
				% [user_dir, marker]
			)
		)
		. starts_with(marker)
	)


## And it is not the player's real data directory, which harness runs used to litter with
## `music_test/`, `otter-test-config/` and a `profile.json.test-polluted.bak`.
func test_the_run_is_not_writing_the_real_data_directory() -> void:
	var home := OS.get_environment("HOME")
	if home.is_empty():
		return
	var real_dir := home.path_join(".local/share/omadungeon")
	(
		assert_str(OS.get_user_data_dir())
		. override_failure_message(
			"this run writes the player's real data directory (%s)" % real_dir
		)
		. is_not_equal(real_dir)
	)


## The property the redirect could have destroyed: `user://` still works. A harness that moved
## `XDG_DATA_HOME` somewhere unwritable would satisfy every isolation assertion above and
## silently break every suite that saves anything, so the round trip is pinned here.
func test_the_isolated_user_directory_is_a_working_user_directory() -> void:
	var path := SaveManagerScript.test_sandbox_dir().path_join("user_dir_isolation_probe.txt")
	DirAccess.make_dir_recursive_absolute(
		SaveManagerScript.resolved_path(SaveManagerScript.test_sandbox_dir())
	)
	var writer := FileAccess.open(path, FileAccess.WRITE)
	(
		assert_object(writer)
		. override_failure_message("user:// is not writable at %s" % path)
		. is_not_null()
	)
	writer.store_string("round trip")
	writer.close()
	var reader := FileAccess.open(path, FileAccess.READ)
	assert_object(reader).is_not_null()
	assert_str(reader.get_as_text()).is_equal("round trip")
	reader.close()
	DirAccess.remove_absolute(SaveManagerScript.resolved_path(path))


## Saving still round-trips: `SaveManager` writes and reads a profile through the isolated
## `user://`, and the file really does land inside this run's private directory.
func test_saving_still_round_trips_through_the_isolated_directory() -> void:
	var manager: Node = SaveManagerScript.new()
	var profile_path := SaveManagerScript.test_sandbox_dir().path_join("isolation_profile.json")
	manager.profile_path = profile_path
	add_child(manager)
	# A *gated* id, or `Profile.unlock()` reports "already unlocked" and writes nothing:
	# everything outside `Profile.GATED_UNLOCKS` is unlocked by default.
	assert_bool(manager.unlock(&"lucky_coin")).is_true()
	(
		assert_bool(FileAccess.file_exists(profile_path))
		. override_failure_message("saving wrote nothing to %s" % profile_path)
		. is_true()
	)
	var marker := OS.get_environment(MARKER_ENV)
	if not marker.is_empty():
		assert_str(SaveManagerScript.resolved_path(profile_path)).starts_with(marker)
	var reloaded: Profile = manager.load_profile()
	(
		assert_bool(reloaded.is_unlocked(&"lucky_coin"))
		. override_failure_message("the profile did not survive a round trip through user://")
		. is_true()
	)
	# Freed synchronously so `_exit_tree()` flushes before the file goes away.
	manager.free()
	DirAccess.remove_absolute(SaveManagerScript.resolved_path(profile_path))


## The second half of the rule, inside one process: the live `SaveManager` autoload writes into
## `user://test/<pid>`, not at the top of `user://`, so even without the harness's redirect a
## suite cannot stamp on the player's `run.json`.
func test_the_live_save_paths_stay_inside_this_processes_sandbox() -> void:
	var sandbox := SaveManagerScript.test_sandbox_dir()
	assert_str(sandbox).is_equal("user://test/%d" % OS.get_process_id())
	assert_str(str(SaveManager.get(&"run_path"))).starts_with(sandbox)
	assert_str(str(SaveManager.get(&"profile_path"))).starts_with(sandbox)
	assert_str(str(GameState.settings_path)).starts_with(sandbox)


## No test may reach past the sandbox to the process-wide user directory.
##
## `OS.get_user_data_dir()` is the one call that does it unconditionally: it ignores
## `SaveManager.test_sandbox_dir()`, and a directory named from it is shared by every run of
## every copy of the project. `tests/unit/tools/godot_import_test.gd` built its scratch
## directory that way, and its `after_test()` deleted it out from under whoever else was
## running — which failed exactly the two of its four cases that assert exit 0, because a
## `GODOT_BIN` that has vanished exits 3.
func test_no_test_reaches_past_the_sandbox_to_the_real_user_directory() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for path: String in _gd_files(TESTS_ROOT):
		if path == SELF_PATH:
			continue
		scanned += 1
		var lines := _code_lines(path)
		for i in lines.size():
			if lines[i].contains("OS.get_user_data_dir("):
				offenders.append("%s:%d" % [path, i + 1])
	assert_int(scanned).is_greater(50)
	(
		assert_array(offenders)
		. override_failure_message(
			(
				"These tests build paths from the process-wide user directory, which every "
				+ "concurrent run shares. Use SaveManager.test_sandbox_dir() instead:\n- "
				+ "\n- ".join(offenders)
			)
		)
		. is_empty()
	)


## Source lines of `path` with whole-line `#` comments dropped, so a rule quoted in a doc
## comment is not mistaken for the code it describes.
func _code_lines(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	for line: String in file.get_as_text().split("\n"):
		out.append("" if line.strip_edges().begins_with("#") else line)
	return out


func _gd_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for name: String in dir.get_files():
		if name.ends_with(".gd"):
			out.append(root.path_join(name))
	for name: String in dir.get_directories():
		out.append_array(_gd_files(root.path_join(name)))
	return out
