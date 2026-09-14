## Guards the property that made the release gate flaky: a test must not leave a handler
## connected to an `EventBus` signal after it finishes.
##
## `EventBus` is an autoload and outlives every suite in the process, so a leaked handler keeps
## firing for the rest of the run. That is how `unique_effects_test.test_yacht_pays_gold_on_hits`
## came to pass alone and fail in the whole tree - two enemy suites had left anonymous lambdas
## on `EventBus.spawn_pickup`. A leak is undetectable from inside the suite that causes it and
## only shows up as somebody else's failure, hours later, in a different order, so it is checked
## here statically *and* dynamically:
##
## * `test_event_bus_holds_no_handler_owned_by_a_test` asks `EventBus` itself, at a point near
##   the end of the run, whether any of its signals still holds a callable owned by a test
##   suite or by an object that has been freed. That catches every shape of leak - a connection
##   made through a local `var s := EventBus.spawn_pickup`, a `Callable.bind` on a stored
##   `Signal`, a lambda in a branch - because it reads the live connection list instead of the
##   source text. It is the guarantee.
## * The two static scans below are the fast hint, not the proof, and they are honestly weak:
##   one `disconnect` anywhere in a file satisfies any number of `connect`s in it, and a
##   connection that never spells `EventBus.<name>.connect(` is invisible to them. They earn
##   their place by naming the offending file and line the moment someone writes the usual
##   shape of the bug, which the dynamic check cannot do (a leaked lambda knows its suite, not
##   the line it was made on).
class_name TestIsolationTest
extends GdUnitTestSuite

const TESTS_ROOT := "res://tests"
## This suite's own source quotes the pattern it looks for, so it cannot be its own subject.
const SELF_PATH := "res://tests/unit/tools/test_isolation_test.gd"


func test_no_test_leaves_a_handler_on_an_event_bus_signal() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for path: String in _gd_files(TESTS_ROOT):
		if path == SELF_PATH:
			continue
		scanned += 1
		var source := _read(path)
		if source.is_empty():
			continue
		var connects := _counted(source, "connect")
		var disconnects := _counted(source, "disconnect")
		for signal_name: String in connects:
			if int(disconnects.get(signal_name, 0)) > 0:
				continue
			offenders.append(
				(
					"%s: EventBus.%s connected %dx, never disconnected"
					% [path, signal_name, int(connects[signal_name])]
				)
			)
	assert_int(scanned).is_greater(50)
	(
		assert_array(offenders)
		. override_failure_message(
			(
				"These suites leak EventBus handlers into the rest of the run; "
				+ "disconnect them or use EventBusProbe:\n- "
				+ "\n- ".join(offenders)
			)
		)
		. is_empty()
	)


## EventBus signal name -> how many times `EventBus.<name>.<verb>(` appears in `source`.
## `disconnect` ends in "connect", so the verb is anchored on the dot in front of it.
func _counted(source: String, verb: String) -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.create_from_string("EventBus\\.([a-z_0-9]+)\\.%s\\(" % verb)
	for m: RegExMatch in re.search_all(source):
		var name := m.get_string(1)
		out[name] = int(out.get(name, 0)) + 1
	return out


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()


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


## The other half of the same rule: a suite that hands its connections to an `EventBusProbe`
## must also give them back. `watch()` without a `release()` leaks exactly as badly as a bare
## `connect()` did, and the check above cannot see it because the probe hides the `connect`.
func test_every_probe_in_a_test_is_released() -> void:
	var offenders: Array[String] = []
	for path: String in _gd_files(TESTS_ROOT):
		if path == SELF_PATH:
			continue
		var source := _read(path)
		if not source.contains(".watch(EventBus."):
			continue
		if source.contains(".release()"):
			continue
		offenders.append("%s: EventBusProbe.watch() with no release()" % path)
	(
		assert_array(offenders)
		. override_failure_message(
			(
				"These suites watch EventBus signals and never release them:\n- "
				+ "\n- ".join(offenders)
			)
		)
		. is_empty()
	)


# ------------------------------------------------------- the dynamic half


## Every EventBus signal, asked directly, must be free of handlers belonging to a test.
##
## This suite runs late in the tree (`res://tests/unit/tools/...`), so by the time it executes,
## every suite sorted before it has finished and had its `after()` run. Anything of theirs
## still hanging off an autoload signal is a leak by definition, and it is the leak that makes
## somebody else fail hours later in a different order.
##
## Two kinds are reported: a callable owned by an object whose script lives under `res://tests`
## (a suite, a helper, a lambda made inside one), and a callable whose object has been freed,
## which is the same leak one step further along.
func test_event_bus_holds_no_handler_owned_by_a_test() -> void:
	var offenders: Array[String] = []
	var signals_seen := 0
	for entry: Dictionary in EventBus.get_signal_list():
		var signal_name := str(entry.get("name", ""))
		if signal_name.is_empty():
			continue
		signals_seen += 1
		for connection: Dictionary in EventBus.get_signal_connection_list(signal_name):
			var reason := _leak_reason(connection.get("callable"))
			if not reason.is_empty():
				offenders.append("EventBus.%s: %s" % [signal_name, reason])
	assert_int(signals_seen).is_greater(5)
	(
		assert_array(offenders)
		. override_failure_message(
			(
				"EventBus still holds handlers left behind by tests that have already "
				+ "finished; they keep firing for the rest of the run:\n- "
				+ "\n- ".join(offenders)
			)
		)
		. is_empty()
	)


## Why `candidate` is a leak, or "" when it is a legitimate connection.
func _leak_reason(candidate: Variant) -> String:
	if not (candidate is Callable):
		return ""
	var callable: Callable = candidate
	var object := callable.get_object()
	if object == null or not is_instance_valid(object):
		return "a callable whose object has been freed (%s)" % callable.get_method()
	var script := object.get_script() as Script
	if script == null:
		return ""
	if not script.resource_path.begins_with(TESTS_ROOT):
		return ""
	return "%s still connected from %s" % [callable.get_method(), script.resource_path]
