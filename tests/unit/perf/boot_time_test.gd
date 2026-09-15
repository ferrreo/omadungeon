## Time to the title screen, measured the only way it can honestly be measured: by booting a
## second headless engine and asking it when its title screen came up.
##
## `BootProbe` prints `BOOT_MS=<n>` (engine-relative, so it covers autoload construction,
## theme discovery, scene load and first layout); this suite also times the whole child
## process, which adds exec and dynamic linking. Both must fit `PerfBudget.boot_budget_seconds`.
class_name BootTimeTest
extends GdUnitTestSuite

const PROBE := "res://src/core/perf/boot_probe.gd"


func test_title_screen_is_up_inside_the_boot_budget() -> void:
	var budget := PerfBudget.load_default()
	var output: Array = []
	var project := ProjectSettings.globalize_path("res://")
	var started := Time.get_ticks_msec()
	var code := OS.execute(
		OS.get_executable_path(), ["--headless", "--path", project, "-s", PROBE], output, true
	)
	var wall_ms := Time.get_ticks_msec() - started
	var text: String = "\n".join(PackedStringArray(output))
	assert_int(code).override_failure_message("boot probe failed:\n%s" % text).is_equal(0)
	var reported := _parse_boot_ms(text)
	var allowed := PerfBudget.allowance(budget.boot_budget_seconds)
	prints(
		(
			"\nboot: probe reported %d ms to title, child process wall clock %d ms (budget %.0f ms)"
			% [reported, wall_ms, allowed * 1000.0]
		)
	)
	assert_int(reported).is_greater(0)
	assert_float(float(reported) / 1000.0).is_less(allowed)
	assert_float(float(wall_ms) / 1000.0).is_less(allowed)


## Pulls `<n>` out of the probe's `BOOT_MS=<n>` line; -1 when it never printed one.
static func _parse_boot_ms(text: String) -> int:
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("BOOT_MS="):
			return int(trimmed.substr("BOOT_MS=".length()))
	return -1
