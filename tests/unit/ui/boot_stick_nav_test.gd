## The left stick on the screen the game actually starts on.
##
## Why this suite exists next to `controller_device_test`. That one proves the stick on every
## screen it loads - by adding the screen to the *test suite's* own node, which is a parent
## that is not in the middle of anything. Boot is not like that: the engine adds the main
## scene to the scene tree root, and while it is doing that the root refuses `add_child()`
## from anyone else ("Parent node is busy setting up children"). The stick service used to be
## installed lazily by the first screen that wanted it, from that screen's `_ready` - so at
## boot the insertion was refused, silently as far as the caller was concerned, and the stick
## was dead on the title and alive on every screen opened afterwards. Every suite in the tree
## loaded its screens the easy way and none of them could see it.
##
## The engine state itself cannot be staged from inside a running tree - the root blocks its
## children exactly once, while it propagates `_ready` over the autoloads and the main scene at
## startup, and that pass is over long before any test runs. (`tools/export.sh` plus a headless
## run of the packaged binary with an empty environment is what shows the refusal; it printed
## "Parent node is busy setting up children" before this change and does not after.) So the
## suite pins the two things that *are* observable and that the refusal turned on: the service
## is installed by an autoload rather than by whoever asks first, and asking for it inserts
## nothing - not even when it is missing, which is the call boot refused.
##
## `BootHost` then plays the rest back end to end: a parent that instantiates its screen from
## its own `_ready`, the way `Main` does, added to the live tree root.
class_name BootStickNavTest
extends GdUnitTestSuite

## Frames for a screen to settle: `Main` swaps its child in and `Title` focuses deferred.
const SETTLE_FRAMES := 4
## Frames a synthesised flick is given to travel `UiStickNav._process` and land on focus.
const FLICK_FRAMES := 3

var _device: int = 0
var _host: Node = null


## A parent that builds its screen from its own `_ready`, which is the shape boot has: while
## this node is being inserted, the node it is being inserted into is busy setting up children
## and will refuse an `add_child()` of its own. Any service a screen installs from `_ready`
## has to survive that, which is why the service is installed at startup instead.
class BootHost:
	extends Node

	## Scene to instantiate. Set before the host is added to the tree.
	var scene_path: String = ""
	## The instantiated screen, or null when the path did not load.
	var screen: Node = null

	func _ready() -> void:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			return
		screen = packed.instantiate()
		add_child(screen)


func before_test() -> void:
	_device = int(InputGlyphs.current_device())
	# `Main` opens the run summary instead of the title when a run is waiting to be reported.
	RunManager.pending_summary = {}


func after_test() -> void:
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
		_host = null
	await _centre_stick()
	InputGlyphs.set_device(_device as InputGlyphs.Device)
	EventBus.input_device_changed.emit(_device)
	await await_idle_frame()


# ------------------------------------------------------------------ device plumbing


static func _motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event


func _frames(count: int) -> void:
	for i in count:
		await await_idle_frame()


func _centre_stick() -> void:
	for axis: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		Input.parse_input_event(_motion(axis, 0.0))
	Input.flush_buffered_events()
	await _frames(FLICK_FRAMES)


## One physical flick of the left stick and back to centre, ramp included.
func _flick(axis: JoyAxis, sign_value: float) -> void:
	for step: float in [0.6, 0.8, 1.0]:
		Input.parse_input_event(_motion(axis, sign_value * step))
		Input.flush_buffered_events()
	await _frames(FLICK_FRAMES)
	await _centre_stick()


## Boots `scene_path` the way the engine boots the main scene: into the live tree root, from a
## parent that is adding children at the time.
func _boot(scene_path: String) -> BootHost:
	var host := BootHost.new()
	host.scene_path = scene_path
	_host = host
	get_tree().root.add_child(host)
	await _frames(SETTLE_FRAMES)
	return host


# ------------------------------------------------------------------ the service itself


func test_the_stick_service_is_up_before_any_screen_has_asked_for_it() -> void:
	var nav := UiStickNav.instance(get_tree())
	(
		assert_object(nav)
		. override_failure_message(
			"no stick service at rest: it is installed by the UiNav autoload, not by a screen"
		)
		. is_not_null()
	)
	assert_bool(nav.is_inside_tree()).is_true()
	(
		assert_int(int(nav.process_mode))
		. override_failure_message("the service stops ticking under a paused tree")
		. is_equal(int(Node.PROCESS_MODE_ALWAYS))
	)


func test_the_service_is_installed_by_an_autoload() -> void:
	# The fix, stated: `UiNav` brings the service up before the main scene exists. A screen
	# that installs it instead is a screen asking the tree root to adopt a node while the root
	# is still adopting the main scene, which the engine refuses.
	(
		assert_bool(ProjectSettings.has_setting("autoload/UiNav"))
		. override_failure_message("no UiNav autoload: the stick service is nobody's job again")
		. is_true()
	)
	var nav := UiStickNav.instance(get_tree())
	assert_object(nav).is_not_null()
	(
		assert_object(nav.get_parent())
		. override_failure_message("the stick service is not the UiNav autoload's child")
		. is_same(get_tree().root.get_node_or_null(NodePath("UiNav")))
	)


func test_asking_for_the_service_never_inserts_anything_even_when_it_is_missing() -> void:
	# The old lookup created the node on first use and handed it to `tree.root.add_child()`,
	# which is the call boot refuses. Taken out of the tree, the lookup must now come back
	# empty-handed rather than build a replacement: "absent" has to stay absent, because the
	# one moment it is absent is the moment the insertion cannot happen.
	var nav := UiStickNav.instance(get_tree())
	assert_object(nav).is_not_null()
	var host := nav.get_parent()
	var before := get_tree().root.get_child_count()
	host.remove_child(nav)
	var missing := UiStickNav.instance(get_tree())
	var after := get_tree().root.get_child_count()
	host.add_child(nav)
	nav.name = UiStickNav.NODE_NAME
	(
		assert_object(missing)
		. override_failure_message("asking for the stick service built one and inserted it")
		. is_null()
	)
	(
		assert_int(after)
		. override_failure_message("asking for the stick service added a node to the tree root")
		. is_equal(before)
	)
	assert_object(UiStickNav.instance(get_tree())).is_same(nav)


func test_there_is_exactly_one_service_under_the_tree_root() -> void:
	# Two of them turn one flick into two presses, which is what a deferred insertion produced:
	# absent for a frame, so the next screen to ask built a second one.
	var found: Array[Node] = []
	_collect_services(get_tree().root, found)
	(
		assert_int(found.size())
		. override_failure_message("%d stick services are running at once" % found.size())
		. is_equal(1)
	)


static func _collect_services(node: Node, out: Array[Node]) -> void:
	if node is UiStickNav:
		out.append(node)
	for child: Node in node.get_children():
		_collect_services(child, out)


# ------------------------------------------------------------------ the boot screen


func test_the_left_stick_moves_the_focus_on_the_screen_the_game_boots_into() -> void:
	var host := await _boot("res://src/main.tscn")
	var main := host.screen as Main
	assert_object(main).is_not_null()
	var title := main.current as Title
	(
		assert_object(title)
		. override_failure_message("booting main.tscn did not land on the title screen")
		. is_not_null()
	)
	var ring := title.focus_ring()
	assert_array(ring).is_not_empty()
	ring[0].grab_focus()
	await _flick(JOY_AXIS_LEFT_Y, 1.0)
	(
		assert_object(title.get_viewport().gui_get_focus_owner())
		. override_failure_message(
			"the left stick is dead on the boot screen: the service never installed itself"
		)
		. is_same(ring[1])
	)


func test_a_screen_booted_the_hard_way_still_registers_itself_as_a_board() -> void:
	# The chest picker draws its own selection and focuses no Control, so it only gets the
	# stick by registering with the service from `_ready` - the same `_ready` boot runs busy.
	var host := await _boot("res://src/ui/chest_ui.tscn")
	var chest := host.screen as ChestUi
	assert_object(chest).is_not_null()
	var nav := UiStickNav.instance(get_tree())
	assert_object(nav).is_not_null()
	chest.show_offers(ChestUi.Kind.STAT, [{"stat": &"might", "points": 1}], {})
	await _frames(2)
	(
		assert_bool(nav.is_live())
		. override_failure_message("a board opened at boot never reached the stick service")
		. is_true()
	)
	chest.close()
