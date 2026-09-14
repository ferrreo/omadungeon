## A GDScript call on a freed instance is a **segmentation fault** - in the gate, not only in a
## shipped build - and this is the guard against writing one again.
##
## Re-measured on Godot 4.7.1 this round, inside gdUnit4 under `tools/test.sh`, because the
## explanation that used to sit here (a debugger-only ObjectDB check) is a Godot 3 story and is
## not what happens:
##
## * calling a **GDScript** method on a freed node - `room.pending_enemy_count()` - is a
##   **SIGSEGV**. The harness exits 134, there is no gdUnit report and the run has no answer at
##   all. Going through a `Variant` does not help; that crashes too.
## * calling an **engine** method on the same reference - `room.get_name()` - instead raises an
##   uncatchable script error ("Cannot call method 'get_name' on a previously freed instance"),
##   which gdUnit counts as an error and the harness reports as exit 100.
##
## Which of the two you get is not yours to choose, neither is catchable, and the crash carries
## the engine's own backtrace with the same two frames (`Variant::callp`,
## `GDScriptFunction::call`) that both of the controller-session core dumps carry. The gate's
## own `--remote-debug tcp://127.0.0.1:0` never connects (the engine refuses port 0), so the
## gate runs with no debugger attached and the behaviour above is the behaviour it has.
##
## Those cores died in exactly this shape: a scenario driver picked a `RoomNode` up before an
## `await`, the run ended underneath it - `RunManager._teardown_run()` ->
## `Game.unload_floor()` -> `FloorRoot.clear_floor()` frees every room - and the next line
## called a method on it. The GDScript stack in the core still held the room in local slot 0.
##
## So: **nothing may call a method on a node it picked up before an `await`.** Re-validate
## first. `TestScenarios.live_room()` is that re-validation for the scenario driver; these are
## its tests, plus a scan that fails when a scenario reaches for a room across an `await`
## without going through it again.
class_name FreedInstanceTest
extends GdUnitTestSuite

const DRIVER_PATH := "res://src/core/test_scenarios.gd"

## Source in the shape of the two core dumps: the local is fetched, awaited over, then read.
const _FETCHED_ACROSS_AWAIT := """
func _scenario_probe() -> void:
	var room := _busiest_room()
	await _frames(6)
	require(room.pending_enemy_count() > 0, "empty")
"""

## The shape the driver is really written in, and the one the scan used to be blind to: the
## local that is read after the await came out of `live_room()`, not out of `_busiest_room()`.
const _GUARDED_ACROSS_AWAIT := """
func _scenario_probe() -> void:
	var room := _busiest_room()
	await _frames(6)
	var cleared := live_room(room)
	cleared.force_clear(true)
	await _frames(4)
	cleared.chest.interact(RunManager.player())
"""

## The third shape, and the one the scan reported nothing about until this round: the local is
## not a room at all. A `Main`, a `Game`, a `Title` - every one of them is a node the run can
## take away across an await, and a method call on the freed one crashes exactly the same way.
const _NODE_ACROSS_AWAIT := """
func _scenario_probe() -> void:
	var main := _main()
	await _settle()
	require(main.current is Title, "the title screen is not up")
"""

## The shape the loot_drop collector was written in: a `for` variable *cast* after an await,
## which is not a member access and so slipped past the scan entirely.
const _CAST_ACROSS_AWAIT := """
func _collect_loot() -> void:
	for node: Node in _loose_loot():
		await _physics_frames(3)
		var drop := node as ItemPickup
		if drop == null:
			continue
"""

## The same two functions written correctly: every read after an await is preceded by a
## `live_room()` on the expression the local was validated with.
const _REVALIDATED := """
func _scenario_probe() -> void:
	var room := _busiest_room()
	await _frames(6)
	var here := live_room(room)
	require(here.pending_enemy_count() > 0, "empty")

func _scenario_other() -> void:
	var room := _busiest_room()
	await _frames(6)
	var cleared := live_room(room)
	cleared.force_clear(true)
	await _frames(4)
	if not require(live_room(room) != null, "gone"):
		return
	cleared.chest.interact(RunManager.player())

func _scenario_node() -> void:
	var main := _main()
	await _settle()
	var now := _main()
	require(now.current is Title, "the title screen is not up")
	if is_instance_valid(main):
		pass
"""


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func test_live_room_returns_a_room_that_is_still_standing() -> void:
	var room := RoomNode.new()
	add_child(room)
	assert_object(TestScenarios.live_room(room)).is_same(room)
	room.free()


func test_live_room_refuses_a_freed_room() -> void:
	var room := RoomNode.new()
	add_child(room)
	remove_child(room)
	room.free()
	# `is_instance_valid` is the only safe question left to ask about this reference; reading
	# any property of it would be the crash this suite exists to prevent. Note that the
	# argument reaches `live_room` at all only because that parameter is `Variant`: a typed
	# one is checked against the argument's class, and a freed instance has none.
	assert_bool(is_instance_valid(room)).is_false()
	assert_object(TestScenarios.live_room(room)).is_null()


func test_live_room_refuses_a_room_queued_for_deletion() -> void:
	var room := RoomNode.new()
	add_child(room)
	room.queue_free()
	assert_object(TestScenarios.live_room(room)).is_null()
	await _frames(2)


func test_live_room_refuses_a_room_that_has_left_the_tree() -> void:
	var room := RoomNode.new()
	add_child(room)
	remove_child(room)
	assert_object(TestScenarios.live_room(room)).is_null()
	room.free()


func test_live_room_refuses_null() -> void:
	assert_object(TestScenarios.live_room(null)).is_null()


## Why `!= null` is not the guard, locked down so the claim in docs/TESTING.md stays true.
##
## `FloorRoot.clear_floor()` takes a floor down with `queue_free()`, and a queue-freed node is
## `!= null`, is `is_instance_valid()`, and answers every method asked of it - for the rest of
## this frame. It is gone on the next one, which is the far side of the `await` a scenario is
## sitting on, and a GDScript method call on it there is a SIGSEGV. So a guard written as
## `if room != null` passes on exactly the frame it needed to fail, and only
## `is_queued_for_deletion()` separates the two.
##
## The crash itself cannot be asserted here - it would take the gate down rather than fail a
## case - so it is measured by hand and written up in docs/TESTING.md. Everything below is the
## part that can be checked without freeing the ground under the process.
func test_a_null_check_cannot_see_a_room_on_its_way_out() -> void:
	var room := RoomNode.new()
	add_child(room)
	room.queue_free()
	assert_bool(room != null).override_failure_message("a queue-freed room is not null").is_true()
	(
		assert_bool(is_instance_valid(room))
		. override_failure_message("a queue-freed room is still a valid instance")
		. is_true()
	)
	(
		assert_bool(room.is_queued_for_deletion())
		. override_failure_message("only is_queued_for_deletion() can tell")
		. is_true()
	)
	assert_object(TestScenarios.live_room(room)).is_null()
	await _frames(2)


## The other half: a node that has merely left the tree is not dying at all, and every null-ish
## check says so. `live_room()` still refuses it, because a room outside the tree is not a room
## anything can be photographed in.
func test_a_room_that_only_left_the_tree_is_not_a_freed_one() -> void:
	var room := RoomNode.new()
	add_child(room)
	remove_child(room)
	assert_bool(is_instance_valid(room)).is_true()
	assert_bool(room.is_queued_for_deletion()).is_false()
	assert_bool(room.is_inside_tree()).is_false()
	assert_object(TestScenarios.live_room(room)).is_null()
	room.free()


## The call-site half of the fix. A scenario picks its subject up - a room from `_busiest_room()`,
## the current scene from `_main()`, the game from `RunManager.game` - and then waits: for attack
## frames, for a palette poll, for a floor to be built, for a screen to settle. Every one of
## those waits is a chance for the run to end, the floor to be freed, or `Main.show_screen()` to
## free the screen the local is holding. This walks the driver's own source and fails when any
## local is read again after an `await` without being re-fetched or re-validated in between,
## which is the line the two core dumps died on.
func test_no_scenario_touches_a_node_across_an_await() -> void:
	var source := FileAccess.get_file_as_string(DRIVER_PATH)
	assert_str(source).override_failure_message("could not read %s" % DRIVER_PATH).is_not_empty()
	var offences := _locals_used_after_await(source)
	(
		assert_array(offences)
		. override_failure_message(
			(
				(
					"%s reaches for a node it picked up before an await:\n  %s\n"
					+ "A method call on a freed node is a SIGSEGV, not an error. Re-fetch it "
					+ "after the wait - live_room() for a room, _main() / RunManager.game for "
					+ "the screens - or guard the read with is_instance_valid()."
				)
				% [DRIVER_PATH, "\n  ".join(offences)]
			)
		)
		. is_empty()
	)


## The scan's own positive control. A test that only ever runs over healthy source cannot tell
## "nothing is wrong" from "nothing is being looked at" - which is what this scan was: it read
## the real driver, found nothing, and would have found nothing had the driver been written
## entirely out of the crashing shape. So it is also driven over source that *is* the bug.
func test_the_scan_catches_a_room_read_after_an_await() -> void:
	var offences := _locals_used_after_await(_FETCHED_ACROSS_AWAIT)
	(
		assert_array(offences)
		. override_failure_message(
			"the scan did not see a _busiest_room() local read after an await"
		)
		. is_not_empty()
	)
	var guarded := _locals_used_after_await(_GUARDED_ACROSS_AWAIT)
	(
		assert_array(guarded)
		. override_failure_message(
			(
				"the scan did not see a live_room() local read after an await. That is the "
				+ "shape src/core/test_scenarios.gd actually uses, so a scan blind to it is "
				+ "watching a shape nothing in the driver is written in."
			)
		)
		. is_not_empty()
	)


## The third positive control, and the hole a verifier found this round: the local is a `Main`,
## not a room. `Main.show_screen()` frees the screen it replaces and `_settle()` is an await, so
## `main.current` on the far side of one is the same call on a possibly-freed instance - and the
## scan reported five of those in the real driver while claiming to cover it.
func test_the_scan_catches_a_node_that_is_not_a_room() -> void:
	var offences := _locals_used_after_await(_NODE_ACROSS_AWAIT)
	(
		assert_array(offences)
		. override_failure_message(
			(
				"the scan did not see `main.current` read after an await. A Main, a Game and a "
				+ "Title are nodes too: the run can take any of them away across a wait, and "
				+ "the call on the freed one crashes exactly the way the room ones do."
			)
		)
		. is_not_empty()
	)


## The fourth positive control, and the one a real bug wrote. `node` here is a `for` variable,
## which the scan already tracked, but the use is a cast rather than a dotted read, which it did
## not. Nothing in the driver is written this way any more; if something is again, this fails.
func test_the_scan_catches_a_node_cast_after_an_await() -> void:
	var offences := _locals_used_after_await(_CAST_ACROSS_AWAIT)
	(
		assert_array(offences)
		. override_failure_message(
			(
				"the scan did not see `node as ItemPickup` after an await. A cast on a freed "
				+ "object is a runtime error that ends the function, so it is worse than the "
				+ "dotted reads the scan already catches, not lesser."
			)
		)
		. is_not_empty()
	)


## The scan's negative control: the same two functions with their re-validation put back must be
## clean, or the scan would simply fail everything and say nothing.
func test_the_scan_passes_source_that_re_validates_after_the_await() -> void:
	var offences := _locals_used_after_await(_REVALIDATED)
	(
		assert_array(offences)
		. override_failure_message(
			"the scan failed source that re-validates properly: %s" % offences
		)
		. is_empty()
	)


## Lines in `source` that read a member of a local after an `await` in the same function,
## without re-validating that local in between.
##
## It has been narrowed twice, and both times because a verifier found real lines it was blind
## to. It began by tracking only locals assigned straight from `_busiest_room()`, and the
## scenarios do not carry *that* local across their awaits: they carry the guarded one
## `live_room()` hands back - `var cleared := live_room(room)`, then
## `cleared.chest.interact(...)` three awaits later - so deleting the one
## `require(live_room(room) != null, ...)` line standing between `_scenario_chest` and the crash
## the two core dumps died on left the scan green. Then it tracked both room shapes and nothing
## else, and the driver held five reads that are not rooms at all:
##
##     test_scenarios.gd:211  require(main.current is ClassSelect, ...)
##     test_scenarios.gd:492  require(view.pause_menu.is_open(), ...)
##     test_scenarios.gd:646  var button := title.get_node_or_null(^"%NewRun") as Button
##     test_scenarios.gd:651  require(title.confirm_visible(), ...)
##     test_scenarios.gd:653  require(not (main.current is ClassSelect), ...)
##
## A `Main`, a `Game` and a `Title` are nodes, `Main.show_screen()` frees the screen it
## replaces, and `_settle()` is an await - so each of those is the same call on a
## possibly-freed instance as the room ones, and the scan named none of them. It tracks
## **every** local now (and every `for` binding), and reports every `name.member` read that
## happens after a wait.
##
## What counts as re-validating, on the line of the read or any line since the await:
## `live_room(<the expression the local was validated with>)`, `is_instance_valid(name)`, or
## assigning the name again - which is what "re-fetch it, do not carry it" looks like in
## source. A guard on the same line as the read counts, because `is_instance_valid(n) or n.x()`
## short-circuits and is correct.
##
## Deliberately narrow in both directions: only `name.member` counts as a read (a bare name
## passed on is not a call on it), and a local leaves the set the moment it is re-assigned.
func _locals_used_after_await(source: String) -> Array[String]:
	var offences: Array[String] = []
	# local name -> "an await has happened since it was validated". A local read on the line
	# after it was fetched or re-validated is fresh; the same read after a wait is the bug.
	var stale: Dictionary = {}
	# local name -> the expression `live_room()` was handed to validate it, so re-validating
	# that expression re-validates this local as well. Everything else guards itself.
	var source_of: Dictionary = {}
	var line_no := 0
	for raw: String in source.split("\n"):
		line_no += 1
		var line := raw.strip_edges()
		if raw.begins_with("func ") or raw.begins_with("static func "):
			stale.clear()
			source_of.clear()
			continue
		if line.begins_with("#"):
			continue
		# Every question below is asked of the *code* on the line, with string literals blanked
		# out. Without that the scan reads its own failure messages: the guard
		# `require(opened != null, "main.tscn went away ...")` mentions `main.` inside a message
		# about `main`, and the scan reported the line that fixes the bug as the bug.
		var code := _code_of(line)
		# Re-validation first, then the read, then the ageing: a line may do all three, and a
		# read guarded on its own line is not a read across a wait at all.
		for name: String in stale.keys():
			if _revalidates(code, name, str(source_of.get(name, name))):
				stale[name] = false
		for name: String in stale.keys():
			if not bool(stale[name]):
				continue
			if _reads_member_of(code, name) or _casts(code, name):
				offences.append("%s:%d  %s" % [DRIVER_PATH.get_file(), line_no, line])
				break
		var assigned := _assigned_local(code)
		if not assigned.is_empty():
			stale[assigned] = false
			source_of[assigned] = _guard_argument(code) if code.contains("live_room(") else assigned
		if "await" in code:
			for name: String in stale.keys():
				stale[name] = true
	return offences


## `line` with the contents of every string literal replaced by spaces, so a name that appears
## only inside a message is not read as source. Lengths are preserved, because the offence is
## reported with the original line and the column has to keep meaning something.
func _code_of(line: String) -> String:
	var out := ""
	var quote := ""
	var index := 0
	while index < line.length():
		var ch := line[index]
		if quote.is_empty():
			if ch == '"' or ch == "'":
				quote = ch
				out += " "
			else:
				out += ch
		else:
			if ch == "\\":
				out += "  "
				index += 1
			elif ch == quote:
				quote = ""
				out += " "
			else:
				out += " "
		index += 1
	return out


## True when `line` re-validates the local `name`, which was itself validated against
## `validated_with` (the expression handed to `live_room()`, or its own name).
func _revalidates(line: String, name: String, validated_with: String) -> bool:
	if line.contains("live_room(%s)" % name) or line.contains("live_room(%s)" % validated_with):
		return true
	return line.contains("is_instance_valid(%s)" % name)


## The local `line` assigns to, or "". Covers `var x := ...`, a plain re-assignment `x = ...`
## and a `for x: T in ...` binding, because all three hand the name a reference fetched *now*.
func _assigned_local(line: String) -> String:
	if line.begins_with("var "):
		var at := line.find(" := ")
		if at < 0:
			at = line.find(" = ")
		if at <= 0:
			return ""
		return line.substr(4, at - 4).strip_edges().split(":")[0].strip_edges()
	if line.begins_with("for "):
		var into := line.find(" in ")
		if into <= 0:
			return ""
		return line.substr(4, into - 4).strip_edges().split(":")[0].strip_edges()
	var equals := line.find(" = ")
	if equals > 0:
		var head := line.substr(0, equals).strip_edges()
		if head.is_valid_identifier():
			return head
	return ""


## The argument a `live_room(...)` call on `line` was handed, so the local it produced can be
## re-validated by a later `live_room()` on the same expression.
func _guard_argument(line: String) -> String:
	var at := line.find("live_room(")
	if at < 0:
		return ""
	var rest := line.substr(at + "live_room(".length())
	var close := rest.find(")")
	return rest.substr(0, close).strip_edges() if close > 0 else ""


## True when `line` reads a member of the local `name` (`name.something`), ignoring a longer
## identifier that merely ends in it (`fight_room.x` is not `room.x`).
## True when `line` casts `name` with `as`. A cast is not a member access, so the check above
## never saw one - and `node as ItemPickup` on a freed object is not merely null, it is a runtime
## error that ends the running function on the spot. That is how `_collect_loot` left every drop
## after the freed one lying on the floor: measured 2026-09-14, 1 run in 12 of
## `tools/run-scenario.sh loot_drop white` failed with "2 drops were still on the floor", the
## cast error the only clue in the log, while this suite sat green over the line that caused it.
## A freed node reached by `as` is exactly as dead as one reached by a dot.
func _casts(line: String, name: String) -> bool:
	var needle := name + " as "
	var from := 0
	while true:
		var at := line.find(needle, from)
		if at < 0:
			return false
		var before := line[at - 1] if at > 0 else " "
		if not (before.is_valid_identifier() or before == "_" or before.is_valid_int()):
			return true
		from = at + needle.length()
	return false


func _reads_member_of(line: String, name: String) -> bool:
	var needle := name + "."
	var from := 0
	while true:
		var at := line.find(needle, from)
		if at < 0:
			return false
		var before := line[at - 1] if at > 0 else " "
		if not (before.is_valid_identifier() or before == "_" or before.is_valid_int()):
			return true
		from = at + needle.length()
	return false
