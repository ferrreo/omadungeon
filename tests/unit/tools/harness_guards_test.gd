## The two guards the release gate's reproducibility rests on, both of them in shell.
##
## **The dead-sandbox sweep.** `tools/test.sh`, `tools/run-scenario.sh`, `tools/ui-gallery.sh`
## and `tools/check-scripts.sh` each rsync the project (or move `$XDG_DATA_HOME`) into
## `<copy root>/omadungeon-<kind>-<pid>`, and each sweeps the leftovers of runs that died before
## their EXIT trap could fire. That sweep used to ask whether the pid *in the directory name* was
## still in `/proc` — and that pid is the harness shell, which is only half of a run. Godot
## outlives a shell that is killed, and Godot is the half still reading the copy. Observed live:
## a `godot -s GdUnitCmdTool.gd` reparented to init with 2h36m of CPU whose cwd read
## `/var/tmp/omadungeon-test-2455577 (deleted)`, while four concurrent runs' directories were
## untouched — the next harness in had deleted exactly the one whose shell had died. A deletion
## that lands mid-run makes a healthy suite fail for reasons that read as project regressions,
## which is the worst kind of red gate: one that lies about why.
##
## So these cases drive `tools/sandbox-lib.sh` against real processes in the shapes that matter,
## including the shape the fix must *not* break: a sandbox that genuinely belongs to nobody is
## still removed, or the leftovers fill the copy root and the harness starts failing for want of
## disk instead.
##
## **The theme-fixture check.** `tools/run-scenario.sh floor no-such-theme` used to exit 0 and
## write `floor_no-such-theme.png` — a picture of whatever desktop theming the machine happened
## to be wearing, under a filename claiming a fixture it never read. That is the same failure the
## `theme_swap` refusal exists to prevent.
class_name HarnessGuardsTest
extends GdUnitTestSuite

const SaveManagerScript := preload("res://src/core/save_manager.gd")
const LIB := "res://tools/sandbox-lib.sh"
const RUN_SCENARIO := "res://tools/run-scenario.sh"
const UI_GALLERY := "res://tools/ui-gallery.sh"
## Fixture names docs/TESTING.md promises. The new refusal must not fire on any of them.
const FIXTURES: Array[String] = [
	"tokyo-night", "catppuccin", "catppuccin-latte", "gruvbox", "nord", "white"
]
## The scenario driver's exit code for "you named something that does not exist".
const REFUSED := 4

## The probe script, written per test run so concurrent runs never share it.
const PROBE_SOURCE := """#!/usr/bin/env bash
# Drives tools/sandbox-lib.sh against one of the sandbox shapes and prints the verdict.
# Usage: probe.sh <case> <lib> <workroot>
set -u
case_name="$1"
source "$2"
work="$3/$case_name"
rm -rf "$work"
mkdir -p "$work"
SANDBOX_SWEEP_ROOTS=("$work")

# A pid that cannot be running and cannot be recycled into one mid-test: one past the kernel's
# own maximum. A pid harvested from a process that has exited would do, until the machine wraps
# round onto it and turns this suite red for no reason anybody could reproduce.
dead_pid() {
	local max
	max=$(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304)
	echo $((max + 1))
}

verdict() {
	if [[ -d "$1" ]]; then echo "KEPT"; else echo "SWEPT"; fi
}

holder=""
case "$case_name" in
	locked)
		# The reported shape: the harness shell is gone, its Godot child is not, and the child
		# inherited the descriptor the lock lives on.
		dir="$work/omadungeon-test-$(dead_pid)"
		mkdir -p "$dir"
		holder=$(bash -c 'exec {fd}>"$1/.sandbox.lock"; flock -n "$fd" || exit 1;
			sleep 30 >/dev/null 2>&1 & echo $!' _ "$dir")
		[[ -d "/proc/$holder" ]] || { echo "PROBE-BROKEN no holder"; exit 1; }
		sandbox_sweep omadungeon-test-
		verdict "$dir"
		;;
	cwd)
		# The backstop, with no lock file at all: a sandbox made before this rule existed, or on
		# a machine with no flock(1). Somebody is working inside it.
		dir="$work/omadungeon-scenario-$(dead_pid)"
		mkdir -p "$dir"
		holder=$(cd "$dir" && bash -c 'sleep 30 >/dev/null 2>&1 & echo $!')
		[[ -d "/proc/$holder" ]] || { echo "PROBE-BROKEN no holder"; exit 1; }
		sandbox_sweep omadungeon-scenario-
		verdict "$dir"
		;;
	abandoned)
		# The property the two above must not cost: a sandbox nobody is using is still removed.
		dir="$work/omadungeon-test-$(dead_pid)"
		mkdir -p "$dir"
		printf 'x' >"$dir/payload"
		sandbox_sweep omadungeon-test-
		verdict "$dir"
		;;
	stderr)
		# `sandbox_claim` must leave the harness able to speak. It used to take the lock with
		# `exec {fd}>... 2>/dev/null`, and an `exec` with no command makes *both* redirections
		# permanent - so the first sandbox a harness claimed sent its own stderr to /dev/null
		# for the rest of the run, and every diagnostic after that point was written into
		# nothing.
		dir="$work/omadungeon-test-$$"
		mkdir -p "$dir"
		errors="$work/after-claim.err"
		(
			sandbox_claim "$dir"
			echo "after-claim" >&2
		) 2>"$errors"
		if grep -q after-claim "$errors"; then echo "KEPT"; else echo "LOST"; fi
		;;
	owner_alive)
		# The original rule, kept: the pid in the name is a live run.
		sleep 30 >/dev/null 2>&1 &
		holder=$!
		dir="$work/omadungeon-userdata-$holder"
		mkdir -p "$dir"
		sandbox_sweep omadungeon-userdata-
		verdict "$dir"
		;;
	*)
		echo "PROBE-BROKEN unknown case $case_name"
		exit 1
		;;
esac
[[ -n "$holder" ]] && kill "$holder" 2>/dev/null
rm -rf "$work"
exit 0
"""


func after_test() -> void:
	var work := _workdir()
	if DirAccess.dir_exists_absolute(work):
		OS.execute("rm", ["-rf", work])


## Scratch directory, inside *this process's* sandbox rather than at a fixed `user://` name: a
## fixed one is shared by every concurrent run and its teardown deletes the other run's fixture.
func _workdir() -> String:
	var sandbox := SaveManagerScript.resolved_path(SaveManagerScript.test_sandbox_dir())
	return sandbox.path_join("harness_guards")


## Runs one sandbox shape through `tools/sandbox-lib.sh` and returns the probe's verdict line.
func _sweep_verdict(case_name: String) -> String:
	var work := _workdir()
	DirAccess.make_dir_recursive_absolute(work)
	var probe := work.path_join("probe.sh")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(PROBE_SOURCE)
	file.close()
	OS.execute("chmod", ["+x", probe])
	var output: Array = []
	var code := OS.execute(
		"bash", [probe, case_name, ProjectSettings.globalize_path(LIB), work], output, true
	)
	var text := "\n".join(PackedStringArray(output)).strip_edges()
	assert_int(code).override_failure_message("probe failed: %s" % text).is_equal(0)
	return text.split("\n")[-1].strip_edges()


## The reported failure, in the shape it was reported in.
func test_a_sandbox_whose_godot_outlived_its_harness_is_not_swept() -> void:
	(
		assert_str(_sweep_verdict("locked"))
		. override_failure_message(
			(
				"the sweep deleted a project copy a live process was still holding - this is the"
				+ " 2h36m orphan with a `(deleted)` cwd, and the red gates around it"
			)
		)
		. is_equal("KEPT")
	)


## The same property through the second rule, so a sandbox created before the lock existed (or
## on a machine with no flock) is still safe.
func test_a_sandbox_that_is_a_live_processs_working_directory_is_not_swept() -> void:
	(
		assert_str(_sweep_verdict("cwd"))
		. override_failure_message("the sweep deleted the working directory of a live process")
		. is_equal("KEPT")
	)


## The property the fix must not destroy. Without it the copy root fills with 700 MB-1.1 GB
## leftovers and the harness fails for want of disk, which is where the sweep came from.
func test_a_sandbox_that_belongs_to_nobody_is_still_swept() -> void:
	(
		assert_str(_sweep_verdict("abandoned"))
		. override_failure_message(
			"an abandoned sandbox survived the sweep; leftovers will fill the copy root again"
		)
		. is_equal("SWEPT")
	)


## And the original rule still answers for a run that has not started a child yet.
func test_a_sandbox_whose_owning_shell_is_alive_is_not_swept() -> void:
	(
		assert_str(_sweep_verdict("owner_alive"))
		. override_failure_message("the sweep deleted a sandbox whose own harness is still running")
		. is_equal("KEPT")
	)


## A fixture name that does not exist is refused instead of silently producing a PNG of the
## developer's own desktop theme under a filename naming a fixture it never read.
## A harness that cannot print is a harness that fails silently, and this one did.
##
## `sandbox_claim` took its lock with `exec {fd}>"$dir/.sandbox.lock" 2>/dev/null`. An `exec`
## with no command applies *every* redirection on the line to the shell itself and keeps them,
## so the `2>/dev/null` was permanent: from the first sandbox a harness claimed - which is the
## first thing `tools/test.sh`, `tools/soak.sh`, `tools/run-scenario.sh` and
## `tools/ui-gallery.sh` all do - the whole run had no stderr. `test.sh`'s "the run wrote no
## gdUnit report - not a pass", its class-cache refusal, the soak's minima, every capture
## harness's failure line: written, exit codes set, nothing printed. Found while writing the
## soak minima, by a run that exited 1 and said nothing at all about why.
func test_a_claim_does_not_take_the_harnesss_stderr_with_it() -> void:
	(
		assert_str(_sweep_verdict("stderr"))
		. override_failure_message(
			(
				"sandbox_claim swallowed the shell's stderr. Scope the redirection to a group - "
				+ "`{ exec {fd}>...; } 2>/dev/null` - or every diagnostic the harness writes "
				+ "after its first claim goes to /dev/null with the exit code left to explain "
				+ "itself."
			)
		)
		. is_equal("KEPT")
	)


func test_the_capture_harnesses_refuse_a_theme_fixture_that_does_not_exist() -> void:
	# The fixture is the first bare word each script takes, and that is not the same argument in
	# both: run-scenario.sh takes the scenario first.
	var invocations := {
		RUN_SCENARIO: ["floor", "no-such-theme"],
		UI_GALLERY: ["no-such-theme"],
	}
	for script: String in invocations:
		var path := ProjectSettings.globalize_path(script)
		var args: Array = [path]
		args.append_array(invocations[script] as Array)
		var output: Array = []
		var code := OS.execute("bash", args, output, true)
		(
			assert_int(code)
			. override_failure_message(
				(
					"%s accepted the fixture 'no-such-theme' (exit %d): %s"
					% [script, code, "\n".join(PackedStringArray(output))]
				)
			)
			. is_equal(REFUSED)
		)


## The other half of that guard: it must not refuse a fixture that really ships, or every
## rendered check in docs/TESTING.md stops running.
func test_every_documented_theme_fixture_really_exists() -> void:
	for name: String in FIXTURES:
		var state := "res://tests/fixtures/omarchy/%s/state" % name
		(
			assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(state)))
			. override_failure_message(
				"docs/TESTING.md promises the '%s' fixture, but %s does not exist" % [name, state]
			)
			. is_true()
		)
