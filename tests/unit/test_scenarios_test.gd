## The rendered-check driver's naming rules. The screenshots are produced by
## `tools/run-scenario.sh`, which cannot run inside a unit test; what is checked here is the
## part that decides where a capture lands.
class_name TestScenariosTest
extends GdUnitTestSuite


func _driver() -> TestScenarios:
	var driver := TestScenarios.new()
	driver.out_dir = "res://tests/out"
	return driver


func test_default_theme_keeps_the_bare_scenario_name() -> void:
	var driver := _driver()
	assert_str(driver.suffix).is_empty()
	assert_str(driver.screenshot_path("combat")).ends_with("/tests/out/combat.png")
	assert_str(driver.screenshot_path("theme_swap_before")).ends_with(
		"/tests/out/theme_swap_before.png"
	)
	driver.free()


func test_a_second_theme_lands_beside_the_first_instead_of_on_top_of_it() -> void:
	var dark := _driver()
	var light := _driver()
	light.suffix = "_white"
	assert_str(light.screenshot_path("combat")).ends_with("/tests/out/combat_white.png")
	assert_str(light.screenshot_path("combat")).is_not_equal(dark.screenshot_path("combat"))
	# The suffix belongs to the file name, never the directory.
	assert_str(light.screenshot_path("combat").get_base_dir()).is_equal(
		dark.screenshot_path("combat").get_base_dir()
	)
	dark.free()
	light.free()


func test_the_suffix_is_read_from_the_command_line() -> void:
	var had := GameState.cli_args.has("screenshot-suffix")
	var previous: Variant = GameState.cli_args.get("screenshot-suffix")
	assert_str(TestScenarios.suffix_from_cli()).is_empty()
	GameState.cli_args["screenshot-suffix"] = "_nord"
	var driver := _driver()
	driver.suffix = TestScenarios.suffix_from_cli()
	assert_str(driver.screenshot_path("floor")).ends_with("/tests/out/floor_nord.png")
	driver.free()
	if had:
		GameState.cli_args["screenshot-suffix"] = previous
	else:
		GameState.cli_args.erase("screenshot-suffix")


## The honesty rule: a capture is only allowed when the scenario actually reached its subject.
## `chest` used to screenshot a bare floor with no chest in it and still print "(OK)", which
## made a broken scenario indistinguishable from a passing one.
func test_a_scenario_that_missed_its_subject_may_not_capture() -> void:
	var driver := _driver()
	assert_bool(driver.may_capture()).is_true()
	assert_bool(driver.require(true, "still fine")).is_true()
	assert_bool(driver.may_capture()).is_true()
	await (
		assert_error(func() -> void: driver.require(false, "no chest"))
		. is_push_error("TestScenarios: boot: no chest")
	)
	(
		assert_bool(driver.may_capture())
		. override_failure_message("a scenario that missed its subject would still write a PNG")
		. is_false()
	)
	driver.free()


## ... and the other half of that property: a scenario whose checks all pass still captures.
## A guard that fails everything protects nothing.
func test_a_scenario_that_reached_its_subject_still_captures() -> void:
	var driver := _driver()
	for _i in range(5):
		assert_bool(driver.require(true, "unused")).is_true()
	assert_bool(driver.may_capture()).is_true()
	driver.free()


## Every scenario the harness offers has to declare what it exists to capture, so "this PNG is
## the right screen" is a written-down claim rather than an assumption.
func test_every_scenario_declares_the_state_it_captures() -> void:
	var names: Array[String] = [
		"boot",
		"class_select",
		"floor",
		"combat",
		"chest",
		"loot_drop",
		"pause",
		"theme_swap",
		"theme_swap_midfight",
		"summary",
		"new_run_confirm",
		"music_moods",
		"music_change",
		"music_within",
		"quit",
	]
	for name: String in names:
		(
			assert_str(TestScenarios.subject_of(name))
			. override_failure_message("scenario %s declares no subject" % name)
			. is_not_empty()
		)
	assert_str(TestScenarios.subject_of("not_a_scenario")).is_empty()
	assert_int(TestScenarios.SUBJECTS.size()).is_equal(names.size())


## A 2x2 image, enough to make a real PNG.
func _probe_image() -> Image:
	return Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)


## The other false-success the driver can produce, and the one nobody had a case for: the
## capture *ran*, `require()` was happy, and `save_png` failed. `_run` used to `quit(0)`
## regardless, so the harness reported success over the previous run's PNG - still on disk,
## still looking current. A failed write now fails the scenario like a missed subject does.
func test_a_screenshot_that_could_not_be_written_fails_the_scenario() -> void:
	var driver := _driver()
	var path := "/proc/omadungeon-not-a-directory/boot.png"
	assert_bool(driver.may_capture()).is_true()
	await (
		assert_error(func() -> void: driver.write_shot(_probe_image(), path))
		. is_push_error("TestScenarios: boot: could not write %s (File not found)" % path)
	)
	(
		assert_bool(driver.may_capture())
		. override_failure_message("a failed write would still be reported as a passing capture")
		. is_false()
	)
	assert_int(driver.shot_count()).is_equal(0)
	driver.free()


## The same when there is no frame to write at all (a headless viewport, a texture that came
## back null): `save_png` is never reached, so only the return value can catch it.
func test_a_capture_with_no_image_fails_the_scenario() -> void:
	var driver := _driver()
	var path := driver.screenshot_path("unit_no_image")
	await (
		assert_error(func() -> void: driver.write_shot(null, path))
		. is_push_error("TestScenarios: boot: could not write %s (Unavailable)" % path)
	)
	assert_bool(driver.may_capture()).is_false()
	assert_int(driver.shot_count()).is_equal(0)
	driver.free()


## ... and the half that protects: a capture that really landed is counted and does not fail
## the scenario. A write check that rejects everything protects nothing.
func test_a_screenshot_that_landed_counts_as_a_capture() -> void:
	var driver := _driver()
	driver.suffix = "_shoot_probe"
	var path := driver.screenshot_path("unit")
	(
		assert_bool(driver.write_shot(_probe_image(), path))
		. override_failure_message("could not write %s" % path)
		. is_true()
	)
	assert_bool(driver.may_capture()).is_true()
	assert_int(driver.shot_count()).is_equal(1)
	assert_int(TestScenarios.written_size(path)).is_greater(0)
	DirAccess.remove_absolute(path)
	driver.free()


## A stale PNG from an earlier run is indistinguishable from this run's result, so the target is
## removed before the write rather than left to be overwritten - or not overwritten at all.
func test_a_failed_capture_leaves_no_stale_png_behind() -> void:
	var driver := _driver()
	driver.suffix = "_stale_probe"
	var path := driver.screenshot_path("unit")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var stale := FileAccess.open(path, FileAccess.WRITE)
	assert_object(stale).is_not_null()
	stale.store_string("yesterday's picture")
	stale.close()
	assert_int(TestScenarios.written_size(path)).is_greater(0)
	await (
		assert_error(func() -> void: driver.write_shot(null, path))
		. is_push_error("TestScenarios: boot: could not write %s (Unavailable)" % path)
	)
	(
		assert_int(TestScenarios.written_size(path))
		. override_failure_message("yesterday's picture survived a failed capture")
		. is_equal(0)
	)
	driver.free()


func test_written_size_reports_zero_for_a_file_that_is_not_there() -> void:
	assert_int(TestScenarios.written_size("/proc/omadungeon-nope/boot.png")).is_equal(0)
