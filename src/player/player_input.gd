## Reads the InputMap actions for the player (docs §4.1) and tracks the active device.
## Mouse aim when the last device was keyboard/mouse; right stick on gamepad, with auto-aim
## toward `auto_aim_target` when the stick is idle. Hides the cursor on gamepad input.
##
## Held actions (attack, secondary, map) are configurable: in HOLD mode they report the raw
## button state, in TOGGLE mode a press flips a latch that stays on until the next press, so
## a player who cannot hold a trigger down can still fire continuously. The mode comes from
## `GameState.settings["hold_mode"]` (per action), falling back to the legacy
## `hold_to_toggle` master switch.
##
## The latch is advanced once per physics tick in `_physics_process`, from the raw pressed
## state rather than from `Input.is_action_just_pressed` (which answers differently depending
## on whether the caller is in an idle or a physics frame). `LATCH_PRIORITY` puts this node
## ahead of the Player that reads it, so a press is never a tick late.
##
## A press that arrives while the player cannot act is swallowed until the button comes back
## up. `ui_accept` shares gamepad A and Space with `dodge`: the A that picks a card closes the
## board, the board hands input back in the same frame, and the Player polls `dodge` off that
## same still-fresh press. The rule lives here, where every hand-back arrives - `enabled`
## turning on (the offer boards, via `Player.input_enabled`) and the tree unpausing over the
## Player (the pause menu never touches `enabled`) - so no menu has to remember it.
class_name PlayerInput
extends Node

signal device_changed(device: Device)

enum Device { KBM, GAMEPAD }

const DEFAULT_MOVE_DEADZONE := 0.25
const DEFAULT_AIM_DEADZONE := 0.25

## Actions whose "held" reading can be latched instead of physically held.
const HOLD_ACTIONS: Array[StringName] = [&"attack", &"secondary", &"map"]
const MODE_HOLD := "hold"
const MODE_TOGGLE := "toggle"
const SETTING_HOLD_MODE := "hold_mode"
## Pre-per-action master switch: true turned every held action into a toggle.
const SETTING_LEGACY := "hold_to_toggle"
## Physics priority: low enough that the latches are fresh before the Player reads them.
const LATCH_PRIORITY := -100
## Every polled gameplay action the swallow rule covers.
const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"attack", &"secondary", &"dodge", &"interact", &"potion", &"active_1", &"active_2"
]

## When false every query returns idle (cutscenes, death, menus). Turning it back on swallows
## whatever is held at that moment (see `is_swallowed`).
var enabled: bool = true:
	set(value):
		if value and not enabled:
			_swallow_held()
		enabled = value
var last_device: Device = Device.KBM
## Optional node the aim snaps to on gamepad when the right stick is idle.
var auto_aim_target: Node2D
var _last_aim: Vector2 = Vector2.RIGHT
var _cursor_hidden: bool = false
## Latch state, advanced once per physics tick: action -> bool / action -> +1|-1 edge.
var _latched: Dictionary = {}
var _latch_edges: Dictionary = {}
var _down: Dictionary = {}
## Swallowed actions: action -> whether a tick has already seen the button up. An event parsed
## in one tick is an edge on the next, so an entry outlives the release until that edge has
## passed: neither the press nor its release ever reaches the Player.
var _swallowed: Dictionary = {}
## Whether last tick was one the player could not act in; the tick after such a tick is where
## the press that closed the menu first shows up as `just_pressed`.
var _was_blocked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = LATCH_PRIORITY
	set_process_input(true)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	_advance_swallowed()
	var blocked := _blocked()
	if blocked or _was_blocked:
		_swallow_held()
	_was_blocked = blocked
	_advance_latches()


## The cursor is a global: never leave it hidden for the menus that outlive the player.
func _exit_tree() -> void:
	_show_cursor(true)
	clear_latches()


## Configured mode of a held action: MODE_HOLD or MODE_TOGGLE.
static func hold_mode(action: StringName) -> String:
	var modes: Variant = GameState.settings.get(SETTING_HOLD_MODE, {})
	if modes is Dictionary:
		var stored: Variant = (modes as Dictionary).get(String(action))
		if stored != null:
			return MODE_TOGGLE if str(stored) == MODE_TOGGLE else MODE_HOLD
	return MODE_TOGGLE if bool(GameState.settings.get(SETTING_LEGACY, false)) else MODE_HOLD


## Drops every toggle latch (scene change, death, a menu taking over).
func clear_latches() -> void:
	_latched.clear()
	_latch_edges.clear()
	_down.clear()


## Whether `action` is currently latched on. Only meaningful in MODE_TOGGLE.
func is_latched(action: StringName) -> bool:
	return bool(_latched.get(action, false))


## Whether `action` is being ignored until its button comes back up: it was pressed while the
## player could not act (a board or menu up, input withdrawn), so the press that closed the
## menu never reaches the run. A fresh press after the release is honoured.
func is_swallowed(action: StringName) -> bool:
	return _swallowed.has(action)


## True while nothing the player presses can reach them: input withdrawn, or the tree paused
## over a pausable Player.
func _blocked() -> bool:
	if not enabled:
		return true
	var parent := get_parent()
	return parent != null and not parent.can_process()


## Marks every gameplay action that is down right now as swallowed. A tap already released
## still reads `just_pressed` on the tick after the menu closed, so it is swallowed too.
func _swallow_held() -> void:
	for action: StringName in GAMEPLAY_ACTIONS:
		if not InputMap.has_action(action) or _swallowed.has(action):
			continue
		if Input.is_action_pressed(action) or Input.is_action_just_pressed(action):
			_swallowed[action] = false


## One tick of swallow bookkeeping. An entry is kept while its button is down, through the
## first tick it reads up, and through the tick its release edge shows on; it is dropped once
## the button has been up with no edge pending - or the moment it is down again after having
## been seen up, which is a fresh press and belongs to the Player.
func _advance_swallowed() -> void:
	for action: StringName in _swallowed.keys():
		var pressed := Input.is_action_pressed(action)
		var edge := Input.is_action_just_pressed(action) or Input.is_action_just_released(action)
		if bool(_swallowed[action]):
			if pressed or not edge:
				_swallowed.erase(action)
		elif not pressed:
			_swallowed[action] = true


## One physics tick of latch bookkeeping: a rising edge on a TOGGLE action flips its latch,
## and an action put back into HOLD mode drops whatever latch it was holding.
func _advance_latches() -> void:
	_latch_edges.clear()
	for action: StringName in HOLD_ACTIONS:
		var down := InputMap.has_action(action) and Input.is_action_pressed(action)
		var was_down := bool(_down.get(action, false))
		_down[action] = down
		if hold_mode(action) != MODE_TOGGLE:
			if bool(_latched.get(action, false)):
				_latched[action] = false
				_latch_edges[action] = -1
			continue
		if not down or was_down or _swallowed.has(action):
			continue
		var on := not bool(_latched.get(action, false))
		_latched[action] = on
		_latch_edges[action] = 1 if on else -1


## True while `action` counts as held, honouring its hold/toggle mode.
func _held(action: StringName) -> bool:
	if hold_mode(action) == MODE_TOGGLE:
		return is_latched(action)
	return _raw_pressed(action)


## True on the tick `action` started counting as held (a press, or the latch turning on).
func _pressed_edge(action: StringName) -> bool:
	if hold_mode(action) == MODE_TOGGLE:
		return int(_latch_edges.get(action, 0)) > 0
	return _raw_just_pressed(action)


## True on the tick `action` stopped counting as held (a release, or the latch turning off).
func _released_edge(action: StringName) -> bool:
	if hold_mode(action) == MODE_TOGGLE:
		return int(_latch_edges.get(action, 0)) < 0
	return not _swallowed.has(action) and Input.is_action_just_released(action)


## The raw button state, minus anything swallowed.
func _raw_pressed(action: StringName) -> bool:
	return not _swallowed.has(action) and Input.is_action_pressed(action)


func _raw_just_pressed(action: StringName) -> bool:
	return not _swallowed.has(action) and Input.is_action_just_pressed(action)


## Which device is live is decided in one place, `InputGlyphs.observe`, so the prompts and the
## player agree. This used to decide for itself and flip to the keyboard on every mouse
## motion event, and it broadcast that on the same signal the glyphs listen to - so a nudged
## mouse turned every pad prompt into key-caps mid-fight.
func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)
	var pad := InputGlyphs.current_device() == InputGlyphs.Device.GAMEPAD
	_set_device(Device.GAMEPAD if pad else Device.KBM)
	if pad:
		_show_cursor(false)
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		_show_cursor(true)


## Follows the shared device. `InputGlyphs.observe` has already put the change on
## `EventBus.input_device_changed`; only the local signal is emitted here.
func _set_device(device: Device) -> void:
	if device == last_device:
		return
	last_device = device
	device_changed.emit(device)


func _show_cursor(show: bool) -> void:
	if show != _cursor_hidden:
		return
	_cursor_hidden = not show
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show else Input.MOUSE_MODE_HIDDEN


func is_gamepad() -> bool:
	return last_device == Device.GAMEPAD


## Settings: `move_deadzone` overrides the shared `deadzone` slider value.
func move_deadzone() -> float:
	var shared: float = float(GameState.settings.get("deadzone", DEFAULT_MOVE_DEADZONE))
	return clampf(float(GameState.settings.get("move_deadzone", shared)), 0.0, 0.9)


func aim_deadzone() -> float:
	var shared: float = float(GameState.settings.get("deadzone", DEFAULT_AIM_DEADZONE))
	return clampf(float(GameState.settings.get("aim_deadzone", shared)), 0.0, 0.9)


## Movement wish direction, length 0..1 (normalised beyond 1).
func move_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var v := Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down", move_deadzone()
	)
	if v.length_squared() > 1.0:
		v = v.normalized()
	return v


## Raw right-stick vector (deadzone applied), zero on keyboard/mouse.
func stick_aim() -> Vector2:
	return Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down", aim_deadzone())


## World position under the mouse cursor (respects the active camera).
func mouse_world_position() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()


## Unit aim direction from `player_pos`. `fallback` is used when nothing else aims (facing).
func aim_direction(player_pos: Vector2, fallback: Vector2 = Vector2.RIGHT) -> Vector2:
	var dir := Vector2.ZERO
	if last_device == Device.GAMEPAD:
		dir = stick_aim()
		if dir.length_squared() < 0.001 and is_instance_valid(auto_aim_target):
			dir = auto_aim_target.global_position - player_pos
	else:
		dir = mouse_world_position() - player_pos
	if dir.length_squared() < 0.001:
		dir = fallback if fallback.length_squared() > 0.001 else _last_aim
	_last_aim = dir.normalized()
	return _last_aim


func last_aim() -> Vector2:
	return _last_aim


func attack_held() -> bool:
	return enabled and _held(&"attack")


func attack_just_pressed() -> bool:
	return enabled and _pressed_edge(&"attack")


func attack_just_released() -> bool:
	return enabled and _released_edge(&"attack")


func secondary_just_pressed() -> bool:
	return enabled and _pressed_edge(&"secondary")


func secondary_held() -> bool:
	return enabled and _held(&"secondary")


func dodge_just_pressed() -> bool:
	return enabled and _raw_just_pressed(&"dodge")


## `index` 0 or 1 -> active_1 / active_2.
func active_just_pressed(index: int) -> bool:
	return enabled and _raw_just_pressed(&"active_1" if index == 0 else &"active_2")


func interact_just_pressed() -> bool:
	return enabled and _raw_just_pressed(&"interact")


func potion_just_pressed() -> bool:
	return enabled and _raw_just_pressed(&"potion")


func map_held() -> bool:
	return _held(&"map")


func pause_just_pressed() -> bool:
	return Input.is_action_just_pressed(&"pause")
