## Player camera: smooth pixel-snapped follow, floor limits, a subtle clamped look-ahead toward
## the aim direction, and the shake/punch offsets owned by `GameFeel` (which honours the
## `screen_shake` setting). Every position it writes is rounded, so the 480x270 render stays
## pixel-perfect no matter what the follow/shake maths produces.
class_name PlayerCamera
extends Camera2D

## Node to follow; assign or call `follow()`.
@export var target_path: NodePath
## Exponential follow rate (higher = tighter).
@export var follow_speed: float = 9.0
## Hard cap (px) on the shake offset this camera will apply.
@export var max_shake: float = 8.0
## Multiplier on `FeelProfile.look_ahead_px`; 0 switches look-ahead off for this camera.
@export var look_ahead_scale: float = 1.0

var target: Node2D
var _follow_pos: Vector2 = Vector2.ZERO
var _look: Vector2 = Vector2.ZERO
var _feel: GameFeel


func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = false
	_feel = GameFeel.instance(get_tree())
	# A camera is built at the start of a floor: nothing that happened before it should still
	# be rattling the view.
	if _feel != null:
		_feel.reset_shake()
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Node2D
	if target == null:
		var players := get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			target = players[0] as Node2D
	_follow_pos = target.global_position if target != null else global_position
	global_position = _follow_pos.round()


func follow(node: Node2D) -> void:
	target = node
	if node != null:
		snap_to(node.global_position)


## Jumps to `pos` without smoothing (floor start, respawn).
func snap_to(pos: Vector2) -> void:
	_follow_pos = pos
	_look = Vector2.ZERO
	global_position = pos.round()
	reset_smoothing()


## Clamps the view to a world-space rectangle (the floor bounds).
func set_limits(rect: Rect2) -> void:
	limit_left = int(floorf(rect.position.x))
	limit_top = int(floorf(rect.position.y))
	limit_right = int(ceilf(rect.end.x))
	limit_bottom = int(ceilf(rect.end.y))


func clear_limits() -> void:
	limit_left = -10000000
	limit_top = -10000000
	limit_right = 10000000
	limit_bottom = 10000000


## Adds screen shake (px amplitude, seconds) for callers holding the camera directly.
## `EventBus.screen_shake` is handled by `GameFeel` itself, so it is never counted twice.
func shake(strength: float, duration: float) -> void:
	if _feel == null:
		_feel = GameFeel.instance(get_tree())
	if _feel != null:
		_feel.shake(strength, duration)


func is_shaking() -> bool:
	return _feel != null and _feel.is_shaking()


## Current look-ahead offset in px (tests/debug).
func look_ahead() -> Vector2:
	return _look


## Where the camera wants to lead the player: `look_ahead_px` along their aim, and nowhere at
## all for a target that does not aim (a cutscene marker, a test dummy).
func _wanted_look() -> Vector2:
	if _feel == null or look_ahead_scale <= 0.0 or not is_instance_valid(target):
		return Vector2.ZERO
	if not target.has_method("aim_direction"):
		return Vector2.ZERO
	var aim: Vector2 = target.call("aim_direction")
	if aim.length_squared() < 0.0001:
		return Vector2.ZERO
	return aim.normalized() * (_feel.profile.look_ahead_px * look_ahead_scale)


func _physics_process(delta: float) -> void:
	if is_instance_valid(target):
		var t := 1.0 - exp(-follow_speed * delta)
		_follow_pos = _follow_pos.lerp(target.global_position, t)
	var look_t := 1.0 - exp(-_look_speed() * delta)
	_look = _look.lerp(_wanted_look(), look_t)
	global_position = (_follow_pos + _look).round()
	offset = _shake_and_punch()


func _look_speed() -> float:
	return _feel.profile.look_ahead_speed if _feel != null else 3.5


## Shake plus heavy-hit punch, capped by `max_shake` and snapped to whole pixels.
func _shake_and_punch() -> Vector2:
	if _feel == null:
		return Vector2.ZERO
	var total := _feel.shake_offset() + _feel.punch_offset()
	if total == Vector2.ZERO:
		return Vector2.ZERO
	return total.limit_length(max_shake).round()
