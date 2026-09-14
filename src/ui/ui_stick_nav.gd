## Turns the gamepad's left stick into discrete UI navigation presses.
##
## Why this exists. `InputEventJoypadMotion.action_match()` has no edge detection: it reports
## "pressed" for *every* motion event whose axis is past the deadzone, and a real stick sends a
## stream of them as it travels (0.6, 0.8, 1.0...). With the stick bound straight to `ui_right`
## - which is what Godot's built-in default does - one physical flick arrived as three or four
## presses, and the class select jumped from Fighter to Oligarch in a single push. That is the
## "the joystick doesn't allow easy selection of characters" half of the controller report.
##
## So the stick is unbound from the directional `ui_*` actions in `project.godot` and comes
## through here instead: one press per flick, hysteresis between the push and the release
## threshold so a stick resting near the edge cannot rattle, and a held direction that repeats
## after a delay the way a held d-pad would if the engine repeated it.
##
## One node, owned by the `UiNav` autoload (`PROCESS_MODE_ALWAYS`, so the pause menu and the
## offer boards - which both pause the tree - still navigate). It is installed at startup
## rather than by the first screen that asks for it, because a screen's `_ready` runs while
## the tree root is busy inserting the main scene and the engine refuses an `add_child()` on
## a busy parent: the service was silently never created on the boot screen, which is why the
## stick was dead on the title and alive everywhere else. See `src/ui/ui_nav_service.gd`.
##
## What it emits is a real
## `InputEventJoypadButton` for the matching d-pad direction, through `Input.parse_input_event`
## - not a synthesised `InputEventAction`. That is the point: the stick then travels *exactly*
## the path the d-pad travels, byte for byte, so there is no class of screen the d-pad reaches
## and the stick does not. An action event is a shortcut past the device layer, and a shortcut
## is a place for the two to diverge; a verifier found the stick dead on the title, the pause
## menu, the Settings list and the summary buttons while the d-pad worked on all four.
##
## It also means `InputGlyphs.observe` sees a pad event when the player pushes the stick, so
## the prompts switch to gamepad glyphs from the stick alone.
##
## It only runs while something is actually waiting for it: a `Control` holds focus, or a
## registered board is on screen. Boards (the class select, the chest/shop picker) draw their
## own selection and never focus a `Control`, so they register with `serve()`.
class_name UiStickNav
extends Node

## Name the `UiNav` autoload gives the service node.
const NODE_NAME := "UiStickNav"
## Where the service sits under the tree root: the autoload node, then the service itself.
const SERVICE_PATH := "UiNav/" + NODE_NAME

## Tunables (thresholds, repeat timings).
var profile: UiNavProfile

## Device index the synthesised d-pad events carry: the pad the stick reading came from.
var device: int = 0

var _axis: Vector2 = Vector2.ZERO
var _dir: Vector2i = Vector2i.ZERO
var _repeat_left: float = 0.0
var _boards: Array[Control] = []


func _init() -> void:
	profile = UiNavProfile.load_default()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_process(true)


## The shared service the `UiNav` autoload installed. A plain lookup: nothing is created
## here, so it is safe to call from a `_ready` that runs while the tree root is still busy.
## Null only without a tree, or in a process that has no `UiNav` autoload.
static func instance(tree: SceneTree) -> UiStickNav:
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(SERVICE_PATH)) as UiStickNav


## Called by a UI screen from `_ready`: for screens that navigate without ever focusing a
## `Control`, keeps the stick live while that screen is on screen. Safe to call from every
## screen - a screen that does focus something is served anyway.
static func serve(board: Control) -> UiStickNav:
	if board == null or not board.is_inside_tree():
		return null
	var nav := instance(board.get_tree())
	if nav != null:
		nav.register(board)
	return nav


## Adds `board` to the list of screens whose visibility keeps the stick live.
func register(board: Control) -> void:
	if board == null or _boards.has(board):
		return
	_boards.append(board)
	if not board.tree_exiting.is_connected(unregister):
		board.tree_exiting.connect(unregister.bind(board))


## Drops `board` again (automatic when it leaves the tree).
func unregister(board: Control) -> void:
	_boards.erase(board)


## The UI action a stick direction stands for; `&""` for no direction. Kept as the readable
## name of what a direction means; what actually goes into the input system is `button_for`.
static func action_for(dir: Vector2i) -> StringName:
	if dir.x < 0:
		return &"ui_left"
	if dir.x > 0:
		return &"ui_right"
	if dir.y < 0:
		return &"ui_up"
	if dir.y > 0:
		return &"ui_down"
	return &""


## The d-pad button a stick direction is sent as, or -1 for no direction. The stick is the
## d-pad as far as every screen is concerned.
static func button_for(dir: Vector2i) -> int:
	if dir.x < 0:
		return JOY_BUTTON_DPAD_LEFT
	if dir.x > 0:
		return JOY_BUTTON_DPAD_RIGHT
	if dir.y < 0:
		return JOY_BUTTON_DPAD_UP
	if dir.y > 0:
		return JOY_BUTTON_DPAD_DOWN
	return -1


## True while a stick flick would have somewhere to land: a focused control, or a registered
## board on screen. Public so a test can assert the gameplay case stays off.
func is_live() -> bool:
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_focus_owner() != null:
		return true
	for board: Control in _boards:
		if is_instance_valid(board) and board.is_inside_tree() and board.is_visible_in_tree():
			return true
	return false


## Direction the stick currently holds, or `Vector2i.ZERO`. The threshold is the push one
## while no direction is held and the (lower) release one while one is, which is the
## hysteresis: the stick has to come most of the way back before the next flick counts.
func direction() -> Vector2i:
	var threshold := profile.release_threshold if _dir != Vector2i.ZERO else profile.press_threshold
	var ax := absf(_axis.x)
	var ay := absf(_axis.y)
	if ax >= threshold and ax >= ay:
		return Vector2i(-1 if _axis.x < 0.0 else 1, 0)
	if ay >= threshold:
		return Vector2i(0, -1 if _axis.y < 0.0 else 1)
	return Vector2i.ZERO


## Feeds one axis reading in, as if it came from the device. Used by `_input` and by tests
## that want the state machine without a running frame loop.
func feed_axis(axis: JoyAxis, value: float) -> void:
	if axis == JOY_AXIS_LEFT_X:
		_axis.x = value
	elif axis == JOY_AXIS_LEFT_Y:
		_axis.y = value


func _input(event: InputEvent) -> void:
	var motion := event as InputEventJoypadMotion
	if motion == null:
		return
	device = motion.device
	feed_axis(motion.axis, motion.axis_value)


func _process(delta: float) -> void:
	step(delta)


## One tick of the state machine, split out so a test can drive it without waiting on frames.
func step(delta: float) -> void:
	if not is_live():
		_dir = Vector2i.ZERO
		return
	var dir := direction()
	if dir != _dir:
		_dir = dir
		_repeat_left = profile.repeat_delay
		if dir != Vector2i.ZERO:
			emit_direction(dir)
		return
	if dir == Vector2i.ZERO:
		return
	_repeat_left -= delta
	if _repeat_left <= 0.0:
		_repeat_left = profile.repeat_interval
		emit_direction(dir)


## Sends one press-and-release of the d-pad button `dir` stands for into the input system.
##
## The release matters as much as the press: without it `Input` keeps the button latched and
## the next flick is not a fresh press. Both go in through `Input.parse_input_event`, which is
## where a physical pad's events enter too.
func emit_direction(dir: Vector2i) -> void:
	var button := button_for(dir)
	if button < 0:
		return
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button as JoyButton
		event.pressed = pressed
		Input.parse_input_event(event)
