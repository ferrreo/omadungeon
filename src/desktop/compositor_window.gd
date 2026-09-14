## Asks the desktop's compositor whether **this game's own window** is fullscreen.
##
## Why it exists: on Wayland nothing in Godot's GDScript API can see a fullscreen the
## compositor made. Measured in the Omarchy VM (Hyprland 0.56.2, Godot's Wayland backend):
## tiled at 1896x1030 and then dispatched into a real fullscreen at 1920x1080, every engine
## observable was byte-identical - `Window.mode` and `DisplayServer.window_get_mode()` both
## `MODE_MAXIMIZED`, every position/size call unchanged. The backend never reports the
## compositor's configure back to the window, so there is nothing in-process to read.
##
## The compositor knows, though, and Omarchy's compositor answers questions about its own
## windows. `hyprctl clients -j` lists every window with the pid that owns it and its
## fullscreen state; sway answers the same through `swaymsg -t get_tree`. Matching on
## `OS.get_process_id()` is what makes this *this* window rather than whatever is focused -
## a game that has just lost focus to a launcher must still read its own state.
##
## Three rules it keeps:
## - **Never blocks.** The query runs on `WorkerThreadPool`; `poll()` starts one and collects
##   the previous one, so the main thread never waits on a process spawn.
## - **Never guesses.** `State.UNKNOWN` is a real answer - no compositor, no matching window,
##   a failed or unparseable query - and callers fall back to the engine's own reading.
## - **Never often.** One query per `CompositorProfile.poll_seconds`, and only while something
##   is actually asking (the Video page polls it; nothing else does).
class_name CompositorWindow
extends RefCounted

## Compositors that can answer. `NONE` also covers "we are headless", where there is no
## window for a compositor to describe.
enum Kind { NONE, HYPRLAND, SWAY }

## What the compositor said. `UNKNOWN` means *the question was not answered*, which is
## different from "not fullscreen" and must never be collapsed into it.
enum State { UNKNOWN, WINDOWED, FULLSCREEN }

const PROFILE_PATH := "res://data/desktop/compositor.tres"

## Hyprland reports `fullscreen` as a mode since 0.42 (0 none, 1 maximised, 2 fullscreen, and
## the two combined as 3); before that it was a JSON boolean. Testing the bit reads both of
## the modern values correctly, and the boolean is caught by its JSON type instead. Maximised
## is deliberately *not* fullscreen here, which is the same line `SettingsPanel` draws.
const HYPRLAND_FULLSCREEN_BIT := 2

## Where `timeout(1)` might be. Checked as files rather than with a `which` spawn - the point
## of the prefix is to make spawns safe, so it must not cost one of its own.
const TIMEOUT_PATHS: PackedStringArray = [
	"/usr/bin/timeout", "/bin/timeout", "/usr/local/bin/timeout"
]

## Which compositor answered `detect_kind()` at construction.
var kind: Kind = Kind.NONE

## The last answer collected. Written on the main thread by `poll()` only; tests set it
## directly to stand in for a compositor.
var state: State = State.UNKNOWN

## Turned off for test runs, where spawning `hyprctl` would make a headless gate depend on
## the developer's own desktop and a rendered capture depend on the harness's nested sway -
## neither of which is describing this game's window. Set it back to true to force a query.
var enabled: bool = true

var profile: CompositorProfile

var _pid: int = 0
var _wait: float = 0.0
var _task: int = -1
var _mutex := Mutex.new()
var _result: State = State.UNKNOWN


func _init(force_kind: int = -1, pid: int = 0) -> void:
	kind = detect_kind() if force_kind < 0 else (force_kind as Kind)
	enabled = not SaveManager.is_test_run()
	_pid = OS.get_process_id() if pid <= 0 else pid
	profile = load(PROFILE_PATH) as CompositorProfile
	if profile == null:
		profile = CompositorProfile.new()


## Which compositor this process is running under, from its own environment. A headless
## process is `NONE` on purpose: it has no surface, so no compositor has anything to say
## about it, and asking would report on some *other* window of the same session.
static func detect_kind() -> Kind:
	if DisplayServer.get_name() == "headless":
		return Kind.NONE
	if not OS.get_environment("HYPRLAND_INSTANCE_SIGNATURE").is_empty():
		return Kind.HYPRLAND
	if not OS.get_environment("SWAYSOCK").is_empty():
		return Kind.SWAY
	return Kind.NONE


## The command that asks `kind` about every window it manages, binary first. Empty for `NONE`.
static func query_argv(query_kind: Kind) -> PackedStringArray:
	match query_kind:
		Kind.HYPRLAND:
			return ["hyprctl", "clients", "-j"]
		Kind.SWAY:
			return ["swaymsg", "-t", "get_tree", "-r"]
		_:
			return []


## `timeout -k 1 <seconds>` when the system has the binary, empty otherwise. Without it a
## compositor that stops answering holds a pool thread until the process ends.
static func timeout_prefix(seconds: float) -> PackedStringArray:
	for path: String in TIMEOUT_PATHS:
		if FileAccess.file_exists(path):
			return [path, "-k", "1", "%.1f" % maxf(seconds, 0.1)]
	return []


## Reads one compositor's answer. `pid` is the process whose window we are asking about; a
## reply that names no window of that process is `UNKNOWN`, never `WINDOWED`, because "the
## compositor does not know about us" is not the same claim as "we are not fullscreen".
static func parse_state(query_kind: Kind, text: String, pid: int) -> State:
	match query_kind:
		Kind.HYPRLAND:
			return _hyprland_state(text, pid)
		Kind.SWAY:
			return _sway_state(text, pid)
		_:
			return State.UNKNOWN


static func _hyprland_state(text: String, pid: int) -> State:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		return State.UNKNOWN
	var seen := false
	for entry: Variant in parsed as Array:
		if not (entry is Dictionary):
			continue
		var client := entry as Dictionary
		if int(client.get("pid", -1)) != pid:
			continue
		seen = true
		if _hyprland_is_fullscreen(client.get("fullscreen")):
			return State.FULLSCREEN
	return State.WINDOWED if seen else State.UNKNOWN


static func _hyprland_is_fullscreen(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value as bool
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return (int(value) & HYPRLAND_FULLSCREEN_BIT) != 0
	return false


## Walks sway's window tree iteratively - `nodes` and `floating_nodes` both hold children, and
## only the leaves (views) carry a `pid`. `fullscreen_mode` is 0 none, 1 workspace-fullscreen,
## 2 global; anything above 0 fills the screen, which is the question being asked.
static func _sway_state(text: String, pid: int) -> State:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return State.UNKNOWN
	var stack: Array[Dictionary] = [parsed as Dictionary]
	var seen := false
	while not stack.is_empty():
		var node: Dictionary = stack.pop_back()
		if int(node.get("pid", -1)) == pid:
			seen = true
			if int(node.get("fullscreen_mode", 0)) > 0:
				return State.FULLSCREEN
		for key: String in ["nodes", "floating_nodes"]:
			var children: Variant = node.get(key)
			if not (children is Array):
				continue
			for child: Variant in children as Array:
				if child is Dictionary:
					stack.push_back(child as Dictionary)
	return State.WINDOWED if seen else State.UNKNOWN


## True when a query would actually go out.
func is_active() -> bool:
	return enabled and kind != Kind.NONE


## Collects a finished query and starts the next one when it is due. Call it once a frame
## from whatever is asking; it costs a float subtraction on every frame that is not due.
func poll(delta: float) -> void:
	if not is_active():
		return
	_collect()
	if _task >= 0:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = maxf(profile.poll_seconds, 0.05)
	_task = WorkerThreadPool.add_task(_query, false, "compositor window state")


## Drops the cached answer and makes the next query due immediately. Called when the *game*
## moves its own window: the cached answer describes the window as it was before the move, and
## believing it for another poll interval flips the Video row off and straight back on.
func invalidate() -> void:
	state = State.UNKNOWN
	_wait = 0.0


## Makes the engine's cached window mode agree with what the compositor actually did, and
## reports whether it had to. Godot's Wayland backend only ever sends the *difference* between
## the mode it believes it is in and the one being asked for, so a window the compositor
## fullscreened behind its back (engine still believes `MODE_MAXIMIZED`) never receives an
## `unset_fullscreen` when the player unticks the box - the engine has no fullscreen on record
## to unset. Writing reality in first gives it one. `engine_says_fullscreen` is the engine's
## own reading (`SettingsPanel.window_is_fullscreen`), kept out of here so this class never
## has to know how that question is asked.
func align_engine_mode(window: Window, engine_says_fullscreen: bool) -> bool:
	if window == null or state == State.UNKNOWN:
		return false
	var live := state == State.FULLSCREEN
	if live == engine_says_fullscreen:
		return false
	window.mode = Window.MODE_FULLSCREEN if live else Window.MODE_WINDOWED
	return true


## Waits for any query in flight. The task touches this object's mutex and fields, so it must
## never outlive the owner that is about to drop the last reference to it.
func shutdown() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1


func _collect() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_mutex.lock()
	state = _result
	_mutex.unlock()


## Runs on a worker thread: spawn, read, parse, hand back. Touches nothing but `_mutex` and
## `_result`, because everything else here belongs to the main thread.
func _query() -> void:
	var answer := run_query(kind, _pid, profile.query_timeout_seconds)
	_mutex.lock()
	_result = answer
	_mutex.unlock()


## One blocking query, start to finish. Static and public so a VM check can call it straight
## without standing up a poller. Any failure - missing binary, non-zero exit, empty or
## unparseable output - is `UNKNOWN`, which every caller reads as "ask the engine instead".
static func run_query(query_kind: Kind, pid: int, timeout_seconds: float) -> State:
	var argv := query_argv(query_kind)
	if argv.is_empty():
		return State.UNKNOWN
	var full := timeout_prefix(timeout_seconds)
	full.append_array(argv)
	var output: Array = []
	var code := OS.execute(full[0], full.slice(1), output, false)
	if code != 0 or output.is_empty():
		return State.UNKNOWN
	return parse_state(query_kind, "\n".join(PackedStringArray(output)), pid)
