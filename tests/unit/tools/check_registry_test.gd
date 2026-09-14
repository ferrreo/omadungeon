## The gate's guard against its own blind spot: **a check nobody runs**.
##
## For five rounds the release gate was `OMADUNGEON_TEST_COPY=1 tools/test.sh -c` and nothing
## else, and it reported green the whole time while `tests/unit/rooms/prop_frame_capture` was
## exiting 2 on the default theme. That scene is not a picture-taker - it reads its own PNG back
## and fails when a prop is under `Prop.READABLE_CONTRAST` or has lost its interior ladder - but
## the only way to run it was to retype the `tools/headless-sway.sh godot --path . ...` line out
## of its doc comment by hand, and nothing in the repository did. Four more capture scenes, the
## 32-screen UI gallery, ten of the eleven rendered scenarios, the weapon pose sheets and the
## death soak were in the same position. A check nobody runs is worse than no check, because it
## reads as coverage: every claim that rests on "the gate is green" rests on the gate seeing
## everything the repository owns.
##
## `tools/checks.json` is the register that ended that, `tools/run-checks.sh` is what runs a tier
## of it, and this suite is the half that lives *inside* the gate. It fails when
##
## * a file under `tools/` or a capture scene under `tests/` is not declared,
## * a declared check names a command that is not on disk,
## * a tier holding CI checks is not run by `.github/workflows/ci.yml`,
## * a check is marked `runs: manual` without saying what runs it instead,
## * a check declares a status of its own rather than leaving that to the ledger,
## * a pinned list (the scenario subjects, the gallery screens) has drifted from the code,
## * or **a check the register says CI runs has no recent passing record**.
##
## That last one is the point of this round. The register's first version recorded *claims*:
## a `known_failing` string a person typed, which was free text, unverifiable and stale within
## the hour of being written, and a "this check exists" line that nothing ever compared against
## a run. Redness is now a recorded exit code. `tools/run-checks.sh` writes one
## `reports/checks/<id>.json` per check it runs - identity, the exact invocations the register
## asked for, the exit code the process returned, and the clock either side of it - and
## `test_every_check_outside_the_gate_has_a_recent_passing_result` reads that ledger. There is
## no field in the register, and no field in a record, that a person can set to make a red
## check read green: the exit code came from the process, and a record whose plan no longer
## matches the register is not evidence about the check as it stands today.
##
## The numbers that could be used to widen the gate are bounded here, in code: a
## `result_max_age_hours` over `MAX_RESULT_AGE_CEILING_HOURS` fails this suite rather than
## buying anybody a longer window.
class_name CheckRegistryTest
extends GdUnitTestSuite

const SaveManagerScript := preload("res://src/core/save_manager.gd")
const REGISTER := "res://tools/checks.json"
const WORKFLOW := "res://.github/workflows/ci.yml"
const TOOLS_DIR := "res://tools"
const TESTS_DIR := "res://tests"
## Directories under `tools/` that hold no files of ours: build droppings, not checks.
const SKIPPED_DIRS: Array[String] = ["__pycache__"]
## Fields every check entry must carry.
const REQUIRED_FIELDS: Array[String] = ["id", "title", "tier", "command", "runs", "asserts"]
## The tier this suite is *in*. A check here cannot be required to have finished before the
## gate that is running it starts, so it is the one tier the ledger rule leaves out - and
## `test_only_the_gate_lives_in_the_gates_own_tier` stops anything else being parked in it.
const GATE_TIER := "unit"
## The longest `policy.result_max_age_hours` may be. The register holds the number, because it
## is a tunable; the ceiling is here, because a tunable that can be set to a year is not a
## limit. A week is already generous: a rendered check that last passed six days ago has seen
## none of this week's work.
const MAX_RESULT_AGE_CEILING_HOURS := 168.0
## And the shortest, so nobody can make the window so narrow that it is easier to delete the
## rule than to satisfy it.
const MIN_RESULT_AGE_FLOOR_HOURS := 1.0
## Fields a check may not carry. Each one is a person's claim about how a run went, which is
## exactly what the ledger exists to replace. `known_failing` was the first of them.
const FORBIDDEN_STATUS_FIELDS: Array[String] = [
	"known_failing", "passing", "green", "red", "status", "last_result", "skip", "expected_fail"
]
## Where a record lands when the register does not say (and what `tools/checks.py` defaults to).
const DEFAULT_RESULTS_DIR := "reports/checks"


## The parsed register. Read through the real filesystem rather than `res://` so the suite works
## the same in a copy-mode run, where `res://` is an rsync of the project.
static func register() -> Dictionary:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(REGISTER))
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


## Every check entry in declaration order.
static func check_entries() -> Array:
	return register().get("checks", []) as Array


## Every file under `res://<relative>`, as project-relative paths, recursively.
static func files_under(
	relative: String, out: PackedStringArray = PackedStringArray()
) -> PackedStringArray:
	var dir := DirAccess.open("res://" + relative)
	if dir == null:
		return out
	for file: String in dir.get_files():
		out.append("%s/%s" % [relative, file])
	for sub: String in dir.get_directories():
		if sub.begins_with(".") or SKIPPED_DIRS.has(sub):
			continue
		files_under("%s/%s" % [relative, sub], out)
	return out


func test_the_register_parses_and_every_check_is_complete() -> void:
	var data := register()
	assert_dict(data).override_failure_message("%s did not parse as JSON" % REGISTER).is_not_empty()
	var seen: Dictionary = {}
	var problems: Array[String] = []
	for entry: Variant in data.get("checks", []):
		var check := entry as Dictionary
		if check == null:
			problems.append("a checks[] entry is not an object")
			continue
		for field: String in REQUIRED_FIELDS:
			if not check.has(field):
				problems.append('%s: no "%s" field' % [check.get("id", "<unnamed>"), field])
		var id := str(check.get("id", ""))
		if seen.has(id):
			problems.append("%s: declared twice" % id)
		seen[id] = true
		if not ["ci", "manual"].has(str(check.get("runs", ""))):
			problems.append(
				"%s: runs must be 'ci' or 'manual', not \"%s\"" % [id, str(check.get("runs"))]
			)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_every_check_names_a_command_that_exists() -> void:
	var missing: Array[String] = []
	for entry: Variant in check_entries():
		var check := entry as Dictionary
		var argv := check.get("command", []) as Array
		if argv.is_empty():
			missing.append("%s: empty command" % check.get("id"))
			continue
		var path := "res://" + str(argv[0])
		if not FileAccess.file_exists(path):
			missing.append("%s: %s is not on disk" % [check.get("id"), argv[0]])
	(
		assert_array(missing)
		. override_failure_message(
			"tools/checks.json names commands that do not exist:\n  %s" % "\n  ".join(missing)
		)
		. is_empty()
	)


func test_every_ci_tier_is_run_by_the_workflow() -> void:
	var workflow := FileAccess.get_file_as_string(ProjectSettings.globalize_path(WORKFLOW))
	assert_str(workflow).override_failure_message("could not read %s" % WORKFLOW).is_not_empty()
	var wanted: Array[String] = []
	for entry: Variant in check_entries():
		var check := entry as Dictionary
		var tier := str(check.get("tier", ""))
		if str(check.get("runs", "")) == "ci" and not wanted.has(tier):
			wanted.append(tier)
	var unrun: Array[String] = []
	for tier: String in wanted:
		if not workflow.contains("run-checks.sh %s" % tier):
			unrun.append(tier)
	(
		assert_array(unrun)
		. override_failure_message(
			(
				(
					"tiers holding CI checks that %s never runs: %s\n"
					+ "Add a step that calls `tools/run-checks.sh <tier>`, or move the checks "
					+ "in them to runs: manual with a why_manual saying what runs them instead."
				)
				% [WORKFLOW, ", ".join(unrun)]
			)
		)
		. is_empty()
	)


func test_every_manual_check_says_what_runs_it_instead() -> void:
	var silent: Array[String] = []
	for entry: Variant in check_entries():
		var check := entry as Dictionary
		if str(check.get("runs", "")) != "manual":
			continue
		if _lines(check.get("why_manual", "")).strip_edges().is_empty():
			silent.append(str(check.get("id")))
	(
		assert_array(silent)
		. override_failure_message(
			(
				(
					"manual checks with no why_manual: %s\n"
					+ "A check that CI cannot run has to say why, and what runs it instead - "
					+ "otherwise 'manual' is just where checks go to stop being run."
				)
				% ", ".join(silent)
			)
		)
		. is_empty()
	)


## No check may carry its own verdict. `known_failing` was free text: a person typed why a
## check was red, the gate failed on the presence of the string, and clearing the string - not
## fixing the check - turned the gate green. It was also stale inside an hour, because nothing
## re-derived it from a run. Every field in `FORBIDDEN_STATUS_FIELDS` is a way of writing it
## again under another name.
func test_no_check_declares_a_status_of_its_own() -> void:
	var claims: Array[String] = []
	for entry: Variant in check_entries():
		var check := entry as Dictionary
		for field: String in FORBIDDEN_STATUS_FIELDS:
			if check.has(field):
				claims.append('%s: "%s"' % [check.get("id"), field])
	(
		assert_array(claims)
		. override_failure_message(
			(
				(
					"tools/checks.json carries a hand-written verdict: %s\n"
					+ "How a check went is recorded by tools/run-checks.sh in %s/<id>.json out "
					+ "of the exit code the process returned. A field here is a claim, and a "
					+ "claim is what this register exists to stop standing in for a result."
				)
				% [", ".join(claims), DEFAULT_RESULTS_DIR]
			)
		)
		. is_empty()
	)


## `tools/run-checks.sh` takes a tier *or* a check id, so that a check which just went red can
## be re-run on its own rather than through the other forty invocations of its tier. That only
## works while the two namespaces are disjoint: an id that is also a tier name would silently
## run the tier instead, and the record written would be for a check nobody asked for.
func test_no_check_id_collides_with_a_tier_name() -> void:
	var tiers: Dictionary = {}
	for entry: Variant in check_entries():
		tiers[str((entry as Dictionary).get("tier", ""))] = true
	var clashes: Array[String] = []
	for entry: Variant in check_entries():
		var id := str((entry as Dictionary).get("id", ""))
		if tiers.has(id) or ["all", "list", "results", "verify"].has(id):
			clashes.append(id)
	(
		assert_array(clashes)
		. override_failure_message(
			(
				(
					"check ids that are also a tier or a run-checks.sh subcommand: %s\n"
					+ "Rename the check: `tools/run-checks.sh <that name>` would run the tier, "
					+ "or print the register, instead of the check."
				)
				% ", ".join(clashes)
			)
		)
		. is_empty()
	)


## The gate's own tier holds the gate and nothing else, so "the ledger rule skips tier `unit`"
## cannot become a hiding place: a check moved in here would be exempt from having to have run.
func test_only_the_gate_lives_in_the_gates_own_tier() -> void:
	var parked: Array[String] = []
	for entry: Variant in check_entries():
		var check := entry as Dictionary
		if str(check.get("tier", "")) != GATE_TIER:
			continue
		var argv := check.get("command", []) as Array
		if argv.is_empty() or not str(argv[0]).begins_with("tools/test.sh"):
			parked.append("%s (%s)" % [check.get("id"), _joined(argv)])
	(
		assert_array(parked)
		. override_failure_message(
			(
				(
					"checks in tier '%s' that are not the gate itself: %s\n"
					+ "That tier is exempt from the recent-result rule because the gate cannot "
					+ "require its own result to exist before it runs. Anything else in here is "
					+ "a check nobody has to have run - give it a tier of its own."
				)
				% [GATE_TIER, ", ".join(parked)]
			)
		)
		. is_empty()
	)


## The two numbers that could be used to widen this gate live in the register, and their bounds
## live here. Setting `result_max_age_hours` to a year does not buy a year: it fails this.
func test_the_result_policy_is_inside_the_bounds_the_gate_sets() -> void:
	var hours := max_result_age_hours()
	(
		assert_float(hours)
		. override_failure_message(
			(
				(
					"policy.result_max_age_hours is %.1f; this suite allows %.1f to %.1f. A "
					+ "window wide enough to cover any run at all is not a freshness rule."
				)
				% [hours, MIN_RESULT_AGE_FLOOR_HOURS, MAX_RESULT_AGE_CEILING_HOURS]
			)
		)
		. is_between(MIN_RESULT_AGE_FLOOR_HOURS, MAX_RESULT_AGE_CEILING_HOURS)
	)


## **This is the case that makes the gate's colour mean something outside tier 1.**
##
## Every check the register says CI runs - today 47 invocations of captures, soaks and
## packaging steps against the gate's one - has to have a record in the ledger that says it ran,
## recently, against the plan the register describes today, and passed. A missing record is a
## check nobody ran; a record with a non-zero exit is a red check under a gate that would
## otherwise be green; a record whose plan no longer matches is evidence about a check that no
## longer exists in that shape.
##
## Nothing in this case reads a claim. The exit code is the one the process returned, the
## timestamps are the clock either side of it, and both were written by `tools/run-checks.sh`.
func test_every_check_outside_the_gate_has_a_recent_passing_result() -> void:
	var dir := results_dir()
	var now := Time.get_unix_time_from_system()
	var problems: Array[String] = []
	for entry: Variant in check_entries():
		var check := entry as Dictionary
		if str(check.get("runs", "")) != "ci" or str(check.get("tier", "")) == GATE_TIER:
			continue
		var why := _result_problem(check, dir, now)
		if not why.is_empty():
			problems.append("%s (tier %s): %s" % [check.get("id"), check.get("tier"), why])
	(
		assert_array(problems)
		. override_failure_message(
			(
				(
					"%d check(s) the register says CI runs have no usable result in %s:\n  %s\n"
					+ "Run them and the record appears: tools/run-checks.sh <tier>, or "
					+ "tools/run-checks.sh verify to see this list from a shell. A failing "
					+ "record clears by fixing the check - there is nothing here to edit."
				)
				% [problems.size(), dir, "\n  ".join(problems)]
			)
		)
		. is_empty()
	)


## **The reader's own controls.** The case above walks the real ledger, and a reader that
## answered "" to everything would pass it every time - which is the shape of the failure this
## whole register exists to end: a check that cannot tell "nothing is wrong" from "nothing is
## being looked at". So the four verdicts are driven over records written on purpose: a record
## that says the check failed, one that is older than the window, one recorded against a
## different plan, and one that is current and passing.
func test_the_result_reader_tells_the_four_verdicts_apart() -> void:
	var dir := _scratch_results_dir()
	var check: Dictionary = {
		"id": "fixture-check",
		"tier": "rendered",
		"command": ["tools/run-scenario.sh"],
		"matrix": [["boot", "tokyo-night"]],
		"runs": "ci"
	}
	var now := Time.get_unix_time_from_system()
	var plan := _plan_lines(check)
	(
		assert_str(_result_problem(check, dir, now))
		. override_failure_message("a check with no record at all was accepted")
		. contains("never run here")
	)
	_write_record(dir, "fixture-check", {"exit": 0, "finished": now - 60.0, "plan": plan})
	(
		assert_str(_result_problem(check, dir, now))
		. override_failure_message("a fresh passing record was refused")
		. is_empty()
	)
	_write_record(dir, "fixture-check", {"exit": 2, "finished": now - 60.0, "plan": plan})
	(
		assert_str(_result_problem(check, dir, now))
		. override_failure_message("a record saying the check exited 2 was read as a pass")
		. contains("exited 2")
	)
	var stale := now - (max_result_age_hours() + 1.0) * 3600.0
	_write_record(dir, "fixture-check", {"exit": 0, "finished": stale, "plan": plan})
	(
		assert_str(_result_problem(check, dir, now))
		. override_failure_message("a record older than the window was read as evidence")
		. contains("last passed")
	)
	_write_record(
		dir,
		"fixture-check",
		{"exit": 0, "finished": now - 60.0, "plan": ["tools/run-scenario.sh boot white"]}
	)
	(
		assert_str(_result_problem(check, dir, now))
		. override_failure_message(
			(
				"a record made against a different plan was counted. A matrix row added or a "
				+ "theme dropped changes what the check is; the old record is not evidence "
				+ "about the new one."
			)
		)
		. contains("different plan")
	)
	DirAccess.remove_absolute("%s/fixture-check.json" % dir)


## A scratch ledger for the controls above, inside *this process's* sandbox rather than at a
## fixed `user://` name: a fixed one is shared by every concurrent run and its teardown deletes
## the other run's fixture (docs/TESTING.md, tier 1).
func _scratch_results_dir() -> String:
	var sandbox := SaveManagerScript.resolved_path(SaveManagerScript.test_sandbox_dir())
	var dir := sandbox.path_join("check_results")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Writes one record the way `tools/run-checks.sh` would.
func _write_record(dir: String, id: String, fields: Dictionary) -> void:
	var file := FileAccess.open("%s/%s.json" % [dir, id], FileAccess.WRITE)
	assert_object(file).override_failure_message("could not write a fixture record").is_not_null()
	file.store_string(JSON.stringify(fields))
	file.close()


## Every file under `tools/`, one inventory entry each.
##
## The rule used to be satisfiable by a *directory*: an entry of `tools/vm/` covered all
## seventeen files under it, and `tools/art/` all sixteen under that, so a new check dropped
## into either arrived declared - by a line written before it existed, saying nothing about it.
## Thirty-three of the fifty-odd files under `tools/` were exempt from the completeness rule by
## construction, including the one directory holding a whole tier. Claims are per file now, and
## `test_no_inventory_entry_claims_a_whole_directory` keeps it that way.
func test_every_file_under_tools_is_declared() -> void:
	var claims: Dictionary = {}
	for entry: Variant in register().get("inventory", []):
		claims[str((entry as Dictionary).get("path", ""))] = true
	var undeclared: Array[String] = []
	for path: String in files_under("tools"):
		if not claims.has(path):
			undeclared.append(path)
	(
		assert_array(undeclared)
		. override_failure_message(
			(
				(
					"files under tools/ that tools/checks.json does not declare:\n  %s\n"
					+ "Add one inventory entry per file saying what it is (harness, library, "
					+ "generator, packaging, fixer, config, data, doc), and a checks[] entry "
					+ "with a runner if it is a check. One entry per file, not per directory: "
					+ "a directory claim declares files nobody has looked at."
				)
				% "\n  ".join(undeclared)
			)
		)
		. is_empty()
	)


func test_every_inventory_entry_is_really_there() -> void:
	var gone: Array[String] = []
	for entry: Variant in register().get("inventory", []):
		var path := str((entry as Dictionary).get("path", ""))
		if not FileAccess.file_exists("res://" + path):
			gone.append(path)
	(
		assert_array(gone)
		. override_failure_message(
			"tools/checks.json declares paths that no longer exist:\n  %s" % "\n  ".join(gone)
		)
		. is_empty()
	)


## A directory claim is a blank cheque: it declares every file that is in the directory now and
## every file anyone puts there later, which is the opposite of what the inventory is for.
func test_no_inventory_entry_claims_a_whole_directory() -> void:
	var blanket: Array[String] = []
	for entry: Variant in register().get("inventory", []):
		var path := str((entry as Dictionary).get("path", ""))
		if path.ends_with("/") or DirAccess.dir_exists_absolute("res://" + path):
			blanket.append(path)
	(
		assert_array(blanket)
		. override_failure_message(
			(
				(
					"inventory entries that claim a whole directory: %s\n"
					+ "Name the files. A directory entry declares whatever is dropped into it "
					+ "next, which is how a check arrives already accounted for and with "
					+ "nothing running it."
				)
				% ", ".join(blanket)
			)
		)
		. is_empty()
	)


func test_every_capture_scene_is_declared_and_has_a_runner() -> void:
	var declared: Dictionary = {}
	var ids: Dictionary = {}
	for entry: Variant in register().get("capture_scenes", []):
		var scene := entry as Dictionary
		declared[str(scene.get("path", ""))] = str(scene.get("check", ""))
		ids[str(scene.get("check", ""))] = str(scene.get("id", ""))
	var known: Dictionary = {}
	for entry: Variant in check_entries():
		known[str((entry as Dictionary).get("id", ""))] = true
	var problems: Array[String] = []
	for path: String in files_under("tests"):
		if not path.ends_with(".tscn"):
			continue
		var res := "res://" + path
		if not declared.has(res):
			problems.append("%s: a main-scene check with no entry in capture_scenes" % res)
		elif not known.has(declared[res]):
			problems.append(
				'%s: names check "%s", which is not in checks[]' % [res, str(declared[res])]
			)
	for res: String in declared:
		if not FileAccess.file_exists(res):
			problems.append("%s: declared in capture_scenes, not on disk" % res)
	(
		assert_array(problems)
		. override_failure_message(
			(
				(
					"%s\n"
					+ "A .tscn under tests/ is a check that runs as its own main scene, so it "
					+ "is invisible to the gdUnit selector. Every one of them needs a check "
					+ "entry naming the command that runs it."
				)
				% "\n  ".join(problems)
			)
		)
		. is_empty()
	)


## The prop frame capture rebuilds the floor once per `Biome.ALL_IDS` entry and writes one PNG
## each, and `tools/capture-scene.sh` deletes exactly those names first and demands them back.
## A biome added to the game and not to the register would leave that guard checking four of
## five frames, which is the quiet half of the same disease.
func test_the_prop_frame_outputs_cover_every_biome() -> void:
	var outputs: Array = []
	for entry: Variant in check_entries():
		var check := entry as Dictionary
		if str(check.get("id", "")) == "prop-frame":
			outputs = check.get("outputs", []) as Array
	var want: Array[String] = []
	for biome: StringName in Biome.ALL_IDS:
		want.append("prop_frame_%s%%s.png" % biome)
	var have: Array[String] = []
	for name: Variant in outputs:
		have.append(str(name))
	have.sort()
	want.sort()
	(
		assert_array(have)
		. override_failure_message(
			"prop-frame outputs %s do not match Biome.ALL_IDS %s" % [have, want]
		)
		. is_equal(want)
	)


## The scenario list, pinned in both directions.
##
## `TestScenarios.SUBJECTS` is the list of states this game can be photographed in, and the
## register's `scenarios` matrix is what actually gets shot. Nothing compared them: a scenario
## deleted from `SUBJECTS` and from the matrix in the same edit was a capture the repository
## silently stopped taking, and one added to `SUBJECTS` alone was a state nobody photographs.
## This is the prop-frame rule - assert the register's own outputs against the real source
## list - applied to the collection that can shrink without a word.
func test_the_scenario_subjects_are_pinned_to_the_driver() -> void:
	var declared := _string_list(_check_named("scenarios").get("subjects", []))
	var real: Array[String] = []
	for name: Variant in TestScenarios.SUBJECTS.keys():
		real.append(str(name))
	declared.sort()
	real.sort()
	(
		assert_array(declared)
		. override_failure_message(
			(
				(
					"tools/checks.json declares %d scenario subject(s) and "
					+ "TestScenarios.SUBJECTS holds %d:\n  register: %s\n  driver:   %s\n"
					+ "A scenario that leaves one list and not the other is either a capture "
					+ "nobody takes any more or a subject nobody declared."
				)
				% [declared.size(), real.size(), declared, real]
			)
		)
		. is_equal(real)
	)


## ... and every one of them has to be in the matrix that runs, or it is declared and unshot.
## `theme_swap` and `theme_swap_midfight` take no theme argument (they pin their own pair), so
## they are matched on the scenario name alone; every other subject is required in a dark
## fixture and a light one, which is the rule docs/TESTING.md states and nothing enforced.
func test_every_scenario_subject_is_in_the_matrix() -> void:
	var check := _check_named("scenarios")
	var rows := check.get("matrix", []) as Array
	var shot: Dictionary = {}
	for row: Variant in rows:
		var argv := _string_list(row)
		if argv.is_empty():
			continue
		var themes := shot.get(argv[0], []) as Array
		themes.append(argv[1] if argv.size() > 1 else "")
		shot[argv[0]] = themes
	var problems: Array[String] = []
	for name: Variant in TestScenarios.SUBJECTS.keys():
		var subject := str(name)
		if not shot.has(subject):
			problems.append("%s: declared in SUBJECTS, in no matrix row" % subject)
			continue
		if subject.begins_with("theme_swap"):
			continue
		var themes := shot[subject] as Array
		if themes.size() < 2:
			problems.append(
				(
					"%s: %d matrix row(s); every subject is shot dark and light"
					% [subject, themes.size()]
				)
			)
	(
		assert_array(problems)
		. override_failure_message(
			(
				(
					"the scenarios check does not shoot every subject:\n  %s\n"
					+ "Add the row to tools/checks.json; a subject with no row is a state the "
					+ "register claims coverage of and nothing photographs."
				)
				% "\n  ".join(problems)
			)
		)
		. is_empty()
	)


## The gallery's screen list, pinned the same way. `tools/ui-gallery.sh` deletes the PNGs it
## expects and demands them back, but it reads that list out of `UiGallery.SCREENS` itself - so
## a screen dropped from `SCREENS` took its own guard with it and the harness still reported
## "captured" over one picture fewer.
func test_the_gallery_screens_are_pinned_to_the_gallery() -> void:
	var declared := _string_list(_check_named("ui-gallery").get("screens", []))
	var real: Array[String] = []
	for name: String in UiGallery.SCREENS:
		real.append(name)
	(
		assert_array(declared)
		. override_failure_message(
			(
				(
					"tools/checks.json declares %d gallery screen(s) and UiGallery.SCREENS "
					+ "holds %d:\n  register: %s\n  gallery:  %s\n"
					+ "Order matters here as well as membership: the three *_glyphs screens and "
					+ "the four pad screens are last on purpose, because each pins state that "
					+ "outlives the capture."
				)
				% [declared.size(), real.size(), declared, real]
			)
		)
		. is_equal(real)
	)


## Where the ledger lives. `tools/test.sh` exports `OMADUNGEON_CHECK_RESULTS_DIR` pointing at
## the real checkout, because copy mode rsyncs `res://` without `reports/`: a gate running
## inside a copy would otherwise find no ledger at all and report that nothing has ever run.
static func results_dir() -> String:
	var from_env := OS.get_environment("OMADUNGEON_CHECK_RESULTS_DIR")
	if not from_env.is_empty():
		return from_env
	var relative := str(register().get("policy", {}).get("results_dir", DEFAULT_RESULTS_DIR))
	return ProjectSettings.globalize_path("res://" + relative)


## How old a record may be before it stops counting, bounded by this suite's own ceiling.
static func max_result_age_hours() -> float:
	var policy := register().get("policy", {}) as Dictionary
	return float(policy.get("result_max_age_hours", 48.0))


## The check with this id, or an empty dictionary.
static func _check_named(id: String) -> Dictionary:
	for entry: Variant in check_entries():
		var check := entry as Dictionary
		if str(check.get("id", "")) == id:
			return check
	return {}


## A register list as `Array[String]`, whatever the JSON parser handed back.
static func _string_list(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value as Array:
			out.append(str(item))
	return out


## Every invocation a check makes, one line each, exactly as `tools/run-checks.sh` types it and
## as `tools/checks.py plan_lines` records it. A record is pinned to this, so a matrix row
## added or a theme dropped makes the old record stop being evidence about today's check.
static func _plan_lines(check: Dictionary) -> Array[String]:
	var env := check.get("env", {}) as Dictionary
	var keys: Array = env.keys()
	keys.sort()
	var prefix := PackedStringArray()
	for key: Variant in keys:
		prefix.append("%s=%s" % [str(key), str(env[key])])
	var rows := check.get("matrix", [[]]) as Array
	if rows.is_empty():
		rows = [[]]
	var out: Array[String] = []
	for row: Variant in rows:
		var argv := PackedStringArray(prefix)
		for part: Variant in check.get("command", []) as Array:
			argv.append(str(part))
		for part: Variant in _string_list(row):
			argv.append(part)
		out.append(" ".join(argv).strip_edges())
	return out


## "" when the ledger says this check ran here, recently, in the shape the register describes,
## and passed - or the reason it says nothing of the kind.
static func _result_problem(check: Dictionary, dir: String, now: float) -> String:
	var path := "%s/%s.json" % [dir, str(check.get("id", ""))]
	if not FileAccess.file_exists(path):
		return "never run here - no %s" % path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var record := parsed as Dictionary
	if record == null:
		return "%s is not a record this runner wrote" % path
	var recorded := _string_list(record.get("plan", []))
	var wanted := _plan_lines(check)
	if recorded != wanted:
		return (
			(
				"recorded against a different plan (%d invocation(s), the register now asks "
				+ "for %d) - re-run it"
			)
			% [recorded.size(), wanted.size()]
		)
	var age := (now - float(record.get("finished", 0.0))) / 3600.0
	var code := int(record.get("exit", -1))
	if code != 0:
		return "last run exited %d, %.1f h ago" % [code, age]
	if age > max_result_age_hours():
		return "last passed %.1f h ago; the register allows %.1f h" % [age, max_result_age_hours()]
	return ""


## A register field that may be a string or a list of lines, as one string.
static func _lines(value: Variant) -> String:
	if value is Array:
		var out := PackedStringArray()
		for line: Variant in value as Array:
			out.append(str(line))
		return "\n".join(out)
	return str(value)


## An argv array printed the way it would be typed.
static func _joined(argv: Variant) -> String:
	var out := PackedStringArray()
	for part: Variant in argv as Array:
		out.append(str(part))
	return " ".join(out)
