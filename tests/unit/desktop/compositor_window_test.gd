## `CompositorWindow`: the window manager asked whether *this* game window is fullscreen.
##
## The reading is the whole point, so this suite is mostly parsing against replies captured
## from a real compositor (`hyprctl clients -j` on Hyprland 0.56.2 in the Omarchy VM, and a
## sway `get_tree` shaped the way sway shapes one). What it pins hardest is the two ways the
## answer can be wrong in a way a player would never see: reading *another* window's state
## because it happened to be the fullscreen one, and turning "no answer" into "not fullscreen".
class_name CompositorWindowTest
extends GdUnitTestSuite

const OUR_PID := 1791
const OTHER_PID := 4242

## Captured verbatim from the VM, trimmed to the fields that are read. The game's window is
## tiled here (`fullscreen: 0`) and a second window of another process is fullscreen.
const HYPRLAND_TILED := (
	'[{"class":"Omadungeon","size":[1896,1030],"pid":1791,"fullscreen":0,"fullscreenClient":0},'
	+ '{"class":"Alacritty","size":[1920,1080],"pid":4242,"fullscreen":2,"fullscreenClient":2}]'
)

## The same reply after `SUPER+F`: the game's own window carries the fullscreen mode.
const HYPRLAND_FULLSCREEN := (
	'[{"class":"Omadungeon","size":[1920,1080],"pid":1791,"fullscreen":2,'
	+ '"fullscreenClient":2}]'
)

## Hyprland's `fullscreen` is a *mode*, and 1 of it is maximised - which this game does not
## call fullscreen anywhere else either.
const HYPRLAND_MAXIMIZED := '[{"class":"Omadungeon","pid":1791,"fullscreen":1}]'

## Before 0.42 the same field was a JSON boolean. An Omarchy machine will not serve this, but
## a player on an older Hyprland will, and a boolean read as a mode is silently always false.
const HYPRLAND_LEGACY_BOOL := '[{"class":"Omadungeon","pid":1791,"fullscreen":true}]'

## A reply that knows nothing about us: every window belongs to somebody else.
const HYPRLAND_NOT_OURS := '[{"class":"Alacritty","pid":4242,"fullscreen":2}]'

## sway nests: root -> output -> workspace -> con, with floating windows on a second list.
## Only the leaves carry `pid`, and `fullscreen_mode` is 0 none / 1 workspace / 2 global.
const SWAY_TILED := (
	'{"type":"root","nodes":[{"type":"output","name":"HEADLESS-1","nodes":['
	+ '{"type":"workspace","name":"1","nodes":['
	+ '{"type":"con","name":"Omadungeon","pid":1791,"fullscreen_mode":0}'
	+ '],"floating_nodes":[]}],"floating_nodes":[]}],"floating_nodes":[]}'
)

const SWAY_FULLSCREEN := (
	'{"type":"root","nodes":[{"type":"output","name":"HEADLESS-1","nodes":['
	+ '{"type":"workspace","name":"1","nodes":['
	+ '{"type":"con","name":"Omadungeon","pid":1791,"fullscreen_mode":1}'
	+ '],"floating_nodes":[]}],"floating_nodes":[]}],"floating_nodes":[]}'
)

## A floating window is reached through `floating_nodes`, which a walk of `nodes` alone
## misses entirely - and a floating game window is exactly the one a player fullscreens.
const SWAY_FLOATING_FULLSCREEN := (
	'{"type":"root","nodes":[{"type":"output","name":"HEADLESS-1","nodes":['
	+ '{"type":"workspace","name":"1","nodes":['
	+ '{"type":"con","name":"Alacritty","pid":4242,"fullscreen_mode":0}],"floating_nodes":['
	+ '{"type":"floating_con","name":"Omadungeon","pid":1791,"fullscreen_mode":2}'
	+ ']}],"floating_nodes":[]}],"floating_nodes":[]}'
)

const SWAY_NOT_OURS := (
	'{"type":"root","nodes":[{"type":"output","nodes":[{"type":"workspace","nodes":['
	+ '{"type":"con","pid":4242,"fullscreen_mode":1}]}]}]}'
)


func _hypr(text: String, pid: int = OUR_PID) -> CompositorWindow.State:
	return CompositorWindow.parse_state(CompositorWindow.Kind.HYPRLAND, text, pid)


func _sway(text: String, pid: int = OUR_PID) -> CompositorWindow.State:
	return CompositorWindow.parse_state(CompositorWindow.Kind.SWAY, text, pid)


func test_hyprland_reads_this_windows_fullscreen_mode() -> void:
	assert_int(_hypr(HYPRLAND_FULLSCREEN)).is_equal(CompositorWindow.State.FULLSCREEN)
	assert_int(_hypr(HYPRLAND_TILED)).is_equal(CompositorWindow.State.WINDOWED)


## The failure this whole class exists to avoid, in its subtler form: another window is
## fullscreen, ours is not, and a query that read the focused window - or just any window with
## the flag set - would report the game fullscreen while it sits tiled in a corner.
func test_hyprland_never_answers_with_another_windows_state() -> void:
	(
		assert_int(_hypr(HYPRLAND_TILED))
		. override_failure_message("another process's fullscreen window was read as ours")
		. is_equal(CompositorWindow.State.WINDOWED)
	)
	assert_int(_hypr(HYPRLAND_NOT_OURS)).is_equal(CompositorWindow.State.UNKNOWN)


## Maximised is not fullscreen - the same line `SettingsPanel.FULLSCREEN_MODES` draws. A
## window filling its tile is what an ordinary Hyprland window already looks like.
func test_hyprland_maximised_is_not_fullscreen() -> void:
	assert_int(_hypr(HYPRLAND_MAXIMIZED)).is_equal(CompositorWindow.State.WINDOWED)


func test_hyprland_still_reads_the_pre_0_42_boolean() -> void:
	assert_int(_hypr(HYPRLAND_LEGACY_BOOL)).is_equal(CompositorWindow.State.FULLSCREEN)


## "The compositor did not tell us" is a third answer, not a quiet "no". Collapsing it into
## WINDOWED is what would turn a failed query into the very lie owner report 12 is about.
func test_an_unanswerable_query_is_unknown_rather_than_windowed() -> void:
	assert_int(_hypr("")).is_equal(CompositorWindow.State.UNKNOWN)
	assert_int(_hypr("not json at all")).is_equal(CompositorWindow.State.UNKNOWN)
	assert_int(_hypr("{}")).is_equal(CompositorWindow.State.UNKNOWN)
	assert_int(_sway("[]")).is_equal(CompositorWindow.State.UNKNOWN)
	assert_int(_sway("")).is_equal(CompositorWindow.State.UNKNOWN)
	(
		assert_int(
			CompositorWindow.parse_state(CompositorWindow.Kind.NONE, HYPRLAND_FULLSCREEN, OUR_PID)
		)
		. is_equal(CompositorWindow.State.UNKNOWN)
	)


func test_sway_reads_this_windows_fullscreen_mode() -> void:
	assert_int(_sway(SWAY_FULLSCREEN)).is_equal(CompositorWindow.State.FULLSCREEN)
	assert_int(_sway(SWAY_TILED)).is_equal(CompositorWindow.State.WINDOWED)


## Floating windows hang off a second list on every container. A walk that only follows
## `nodes` sees a tree with the game missing from it and answers UNKNOWN forever.
func test_sway_finds_a_floating_window() -> void:
	assert_int(_sway(SWAY_FLOATING_FULLSCREEN)).is_equal(CompositorWindow.State.FULLSCREEN)


func test_sway_never_answers_with_another_windows_state() -> void:
	assert_int(_sway(SWAY_NOT_OURS)).is_equal(CompositorWindow.State.UNKNOWN)
	assert_int(_sway(SWAY_FULLSCREEN, OTHER_PID)).is_equal(CompositorWindow.State.UNKNOWN)


## A headless process has no surface, so no compositor has anything to say about it - and the
## session around a headless gate belongs to the developer, whose windows are not ours.
func test_headless_detects_no_compositor() -> void:
	assert_int(CompositorWindow.detect_kind()).is_equal(CompositorWindow.Kind.NONE)


func test_each_compositor_has_a_query_and_none_has_none() -> void:
	assert_array(CompositorWindow.query_argv(CompositorWindow.Kind.HYPRLAND)).is_equal(
		PackedStringArray(["hyprctl", "clients", "-j"])
	)
	assert_array(CompositorWindow.query_argv(CompositorWindow.Kind.SWAY)).is_equal(
		PackedStringArray(["swaymsg", "-t", "get_tree", "-r"])
	)
	assert_array(CompositorWindow.query_argv(CompositorWindow.Kind.NONE)).is_empty()


## Nothing may be spawned for a compositor that is not there.
func test_a_query_with_no_compositor_spawns_nothing_and_answers_unknown() -> void:
	assert_int(CompositorWindow.run_query(CompositorWindow.Kind.NONE, OUR_PID, 1.0)).is_equal(
		CompositorWindow.State.UNKNOWN
	)


## The deadline is a prefix, not a promise: a system without `timeout(1)` still gets queried.
func test_the_timeout_prefix_is_a_deadline_when_one_can_be_had() -> void:
	var prefix := CompositorWindow.timeout_prefix(2.0)
	if prefix.is_empty():
		return
	assert_str(prefix[0].get_file()).is_equal("timeout")
	assert_array(prefix).contains(["2.0"])


## The poll rate is data, not a literal, and it has to be slower than a frame.
func test_the_poll_rate_comes_from_the_profile_resource() -> void:
	var profile: CompositorProfile = load(CompositorWindow.PROFILE_PATH)
	assert_object(profile).is_not_null()
	assert_float(profile.poll_seconds).is_greater(0.1)
	assert_float(profile.query_timeout_seconds).is_greater(0.0)


## Under a test run the query is off, so a gate run inside the developer's own Hyprland session
## cannot read some other window and call it the game's.
func test_a_test_run_asks_no_compositor() -> void:
	var query := CompositorWindow.new()
	assert_bool(query.enabled).is_false()
	assert_bool(query.is_active()).is_false()
	query.state = CompositorWindow.State.FULLSCREEN
	query.poll(10.0)
	assert_int(query.state).is_equal(CompositorWindow.State.FULLSCREEN)


## The write half. Godot's Wayland backend only sends the difference between the mode it
## believes it is in and the one asked for, so a window the compositor fullscreened behind its
## back has no fullscreen on the engine's books to unset. Writing reality in first gives it one.
func test_aligning_the_engine_mode_writes_what_the_compositor_did() -> void:
	var window: Window = auto_free(Window.new())
	add_child(window)
	window.mode = Window.MODE_MAXIMIZED
	var query := CompositorWindow.new()

	query.state = CompositorWindow.State.FULLSCREEN
	(
		assert_bool(query.align_engine_mode(window, SettingsPanel.window_is_fullscreen(window)))
		. override_failure_message("the engine was left believing a fullscreen window is tiled")
		. is_true()
	)
	assert_int(int(window.mode)).is_equal(int(Window.MODE_FULLSCREEN))


func test_aligning_writes_nothing_when_the_two_already_agree_or_nobody_answered() -> void:
	var window: Window = auto_free(Window.new())
	add_child(window)
	window.mode = Window.MODE_FULLSCREEN
	var query := CompositorWindow.new()

	query.state = CompositorWindow.State.UNKNOWN
	assert_bool(query.align_engine_mode(window, true)).is_false()
	query.state = CompositorWindow.State.FULLSCREEN
	assert_bool(query.align_engine_mode(window, true)).is_false()
	assert_int(int(window.mode)).is_equal(int(Window.MODE_FULLSCREEN))
	assert_bool(query.align_engine_mode(null, false)).is_false()


## Invalidation is what keeps the row from flapping after the game moves its own window: the
## cached answer describes the window as it was, and it must stop being believed at once.
func test_invalidating_drops_the_cached_answer() -> void:
	var query := CompositorWindow.new()
	query.state = CompositorWindow.State.FULLSCREEN
	query.invalidate()
	assert_int(query.state).is_equal(CompositorWindow.State.UNKNOWN)
