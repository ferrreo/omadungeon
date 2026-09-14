## Central game-feel service: hit-stop, screen-shake trauma, camera punch, hit-flash strength
## and the brief slow that celebrates a room-ending blow (docs §6). One node under the tree
## root (process mode ALWAYS) so a freeze can never be stranded by a pause or a scene swap.
##
## Everything here honours the accessibility settings: `screen_shake` gates trauma and punch,
## `reduced_flash` scales every flash down. Numbers come from `FeelProfile` (data/feel/feel.tres).
##
## Hit-stop is counted in *rendered frames*, not seconds, so a stop is the same length whatever
## `Engine.time_scale` is doing, and requests are queued rather than summed: overlapping hits
## take the longest stop, capped by `hit_stop_max_frames`, and a refractory window after each
## stop drops further requests so a busy screen cannot chain freezes into a slideshow.
class_name GameFeel
extends Node

const NODE_NAME := "GameFeel"
## Physics ticks per second the frame-based timings assume (docs §1: physics at 60 Hz).
const FRAME_HZ := 60.0

## Set false (tests, accessibility) to make every effect a no-op.
var enabled: bool = true
## Set false to drop hit-stops and the room-clear slow while leaving shake and flashes alone
## (the `reduce_motion` setting and the test suites use this through `HitStop.set_enabled`).
var hit_stop_enabled: bool = true
var profile: FeelProfile

var _freeze_frames_left: int = 0
var _freeze_scale: float = 1.0
var _refractory_left: int = 0
var _trauma: float = 0.0
var _trauma_decay: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_phase: float = 0.0
var _punch: Vector2 = Vector2.ZERO
var _last_death_frame: int = -1000
## Physics frame the flash budget is currently counting, and how many claims it has seen.
var _flash_frame: int = -1
var _flash_claims: int = 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	profile = FeelProfile.load_default()
	_trauma_decay = profile.trauma_decay
	_rng.seed = 7


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.screen_shake.connect(shake)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.room_cleared.connect(_on_room_cleared)


## The shared service, created under the tree root on first use. Null only without a tree.
static func instance(tree: SceneTree) -> GameFeel:
	if tree == null or tree.root == null:
		return null
	var node := tree.root.get_node_or_null(NODE_NAME) as GameFeel
	if node == null:
		node = GameFeel.new()
		node.name = NODE_NAME
		tree.root.add_child(node)
	return node


## Convenience for any node already in the tree (null when it is not).
static func of(node: Node) -> GameFeel:
	if node == null or not node.is_inside_tree():
		return null
	return instance(node.get_tree())


# --- hit stop ---------------------------------------------------------------------------------


## Queues a `frames`-long freeze. Overlapping requests take the longest, never the sum, and are
## dropped entirely while the refractory window from the previous stop is running.
func request_hit_stop(frames: int, scale: float = -1.0) -> bool:
	if not enabled or not hit_stop_enabled or frames <= 0:
		return false
	if _refractory_left > 0:
		return false
	var wanted := mini(frames, profile.hit_stop_max_frames)
	var depth := scale if scale >= 0.0 else profile.hit_stop_scale
	_freeze(wanted, depth)
	return true


## Frames a hit of `amount` damage is worth, then queues it. `heavy` forces the heavy timing
## (crits, combo finishers, boss slams).
func hit_stop_for(amount: float, heavy: bool = false) -> bool:
	return request_hit_stop(profile.hit_stop_frames(amount, heavy))


## Seconds-based entry point kept for `HitStop.apply` and the ability FX helpers. Rounds to
## whole frames so every stop in the game shares one queue.
func hit_stop_seconds(seconds: float, scale: float = -1.0) -> bool:
	return request_hit_stop(int(roundf(maxf(0.0, seconds) * FRAME_HZ)), scale)


## Brief slow (not a freeze) used for the blow that empties a room. Bypasses the hit-stop
## refractory window: it is a deliberate, rare beat rather than per-hit feedback.
func slow_motion(scale: float, seconds: float) -> bool:
	if not enabled or not hit_stop_enabled or seconds <= 0.0:
		return false
	_freeze(int(roundf(seconds * FRAME_HZ)), clampf(scale, 0.01, 1.0))
	return true


func is_frozen() -> bool:
	return _freeze_frames_left > 0


func hit_stop_frames_left() -> int:
	return _freeze_frames_left


## Frames left before another hit-stop request will be accepted.
func refractory_frames_left() -> int:
	return _refractory_left


## Force-restores normal time (scene change, test teardown).
func restore_time() -> void:
	_freeze_frames_left = 0
	_freeze_scale = 1.0
	_refractory_left = 0
	Engine.time_scale = 1.0


func _freeze(frames: int, scale: float) -> void:
	if frames <= 0:
		return
	_freeze_frames_left = maxi(_freeze_frames_left, frames)
	# A deeper freeze wins, so a heavy hit landing during a light stop still reads as heavier.
	_freeze_scale = minf(_freeze_scale, scale) if is_frozen() else scale
	Engine.time_scale = _freeze_scale


# --- screen shake -----------------------------------------------------------------------------


## True when the player has screen shake switched on and the service is live.
func shake_allowed() -> bool:
	if not enabled or bool(GameState.settings.get("reduce_motion", false)):
		return false
	return bool(GameState.settings.get("screen_shake", true))


## Adds trauma (0..1, squared into the offset so small hits stay subtle). A positive `duration`
## makes the trauma decay at least fast enough to be gone by then.
func add_trauma(amount: float, duration: float = 0.0) -> void:
	if not shake_allowed() or amount <= 0.0:
		return
	var was_calm := _trauma <= 0.0
	var added := clampf(amount, 0.0, 1.0)
	_trauma = clampf(_trauma + added, 0.0, 1.0)
	var decay := profile.trauma_decay
	if duration > 0.0:
		decay = maxf(decay, added / duration)
	_trauma_decay = decay if was_calm else maxf(_trauma_decay, decay)


## Legacy `EventBus.screen_shake` adapter: px amplitude + seconds -> trauma.
func shake(strength: float, duration: float) -> void:
	if strength <= 0.0:
		return
	add_trauma(clampf(strength / maxf(1.0, profile.shake_max_offset), 0.0, 1.0), duration)


func trauma() -> float:
	return _trauma


func is_shaking() -> bool:
	return _trauma > 0.0


## Current shake offset in px (already pixel-snapped). Zero when shake is off.
func shake_offset() -> Vector2:
	return _shake_offset


## Kicks the camera `strength` px along `dir` (heavy hits). Honours the shake setting.
func punch(dir: Vector2, strength: float) -> void:
	if not shake_allowed() or dir.length_squared() < 0.0001 or strength <= 0.0:
		return
	var kick := dir.normalized() * strength
	# Take the stronger kick rather than summing, so a volley cannot walk the camera away.
	if kick.length() > _punch.length():
		_punch = kick


## Current camera punch offset in px (not yet snapped; the camera rounds the total).
func punch_offset() -> Vector2:
	return _punch


# --- flashes ----------------------------------------------------------------------------------


func reduced_flash() -> bool:
	return bool(GameState.settings.get("reduced_flash", false))


## Peak strength a hit flash should use, after the `reduced_flash` setting.
func flash_scale() -> float:
	if not enabled:
		return 0.0
	var scale := profile.flash_strength
	if reduced_flash():
		scale *= profile.reduced_flash_scale
	return scale


func flash_time() -> float:
	return profile.flash_time


## Strength a hit flash should actually use, after the per-frame crowd budget.
##
## The first `flash_budget_per_frame` claims in a physics frame get the full settings-aware
## strength; every further claim in that frame is scaled by `flash_crowd_scale`. Four enemies
## taking a cleave on the same frame used to blow four sprites to pure white at once, which
## welds them (and whatever is standing between them) into one silhouette-free mass - the
## opposite of docs §1 pillar 1. Capping the budget keeps the hit *readable as a hit* on every
## target while leaving only the loudest two able to bleach themselves.
func claim_flash(strength: float = 1.0) -> float:
	if not enabled:
		return 0.0
	var frame := Engine.get_physics_frames()
	if frame != _flash_frame:
		_flash_frame = frame
		_flash_claims = 0
	_flash_claims += 1
	var scaled := maxf(0.0, strength) * flash_scale()
	if _flash_claims > maxi(1, profile.flash_budget_per_frame):
		scaled *= clampf(profile.flash_crowd_scale, 0.0, 1.0)
	return scaled


## Flash claims made so far in the current physics frame (tests/debug).
func flash_claims_this_frame() -> int:
	return _flash_claims if Engine.get_physics_frames() == _flash_frame else 0


## `self_modulate` multiplier a flash of an already-claimed `strength` peaks at. Capped by
## `flash_peak_mul`: the old fixed 2.0 clipped all three channels, so the flash erased the
## sprite's own colours instead of brightening them.
func flash_peak(strength: float) -> float:
	return 1.0 + profile.flash_peak_mul * maxf(0.0, strength)


## Brief white flash on a sprite's `self_modulate`, at the settings-aware strength and through
## the per-frame crowd budget. Used by enemies and props so every hit flash in the game has
## the same shape.
func flash_modulate(item: CanvasItem, strength: float = 1.0) -> Tween:
	if item == null or not item.is_inside_tree():
		return null
	var peak := flash_peak(claim_flash(strength))
	item.self_modulate = Color(peak, peak, peak, item.self_modulate.a)
	var tween := item.create_tween()
	tween.tween_property(item, "self_modulate", Color.WHITE, flash_time())
	return tween


# --- room-ending blow -------------------------------------------------------------------------


func _on_enemy_died(_enemy: Node2D, _killer: Node2D) -> void:
	_last_death_frame = Engine.get_physics_frames()


## A room that unlocks in the same breath as its last death gets the celebratory slow; a room
## that was already empty when the player walked in does not.
func _on_room_cleared(_room_id: int) -> void:
	var age := Engine.get_physics_frames() - _last_death_frame
	if age < 0 or age > profile.room_clear_window_frames:
		return
	_last_death_frame = -1000
	slow_motion(profile.room_clear_slow_scale, profile.room_clear_slow_time)
	add_trauma(profile.trauma_death, profile.room_clear_slow_time)


## True when `room_cleared` right now would count as a room-ending blow (tests/debug).
func room_ending_blow_pending() -> bool:
	var age := Engine.get_physics_frames() - _last_death_frame
	return age >= 0 and age <= profile.room_clear_window_frames


# --- loop -------------------------------------------------------------------------------------


func _process(_delta: float) -> void:
	if _freeze_frames_left > 0:
		_freeze_frames_left -= 1
		if _freeze_frames_left <= 0:
			_freeze_scale = 1.0
			Engine.time_scale = 1.0
			_refractory_left = profile.hit_stop_refractory_frames
	elif _refractory_left > 0:
		_refractory_left -= 1


func _physics_process(delta: float) -> void:
	_decay_trauma(delta)
	if _punch.length_squared() > 0.0001:
		_punch = _punch.lerp(Vector2.ZERO, clampf(profile.punch_decay * delta, 0.0, 1.0))
		if _punch.length() < 0.05:
			_punch = Vector2.ZERO


func _decay_trauma(delta: float) -> void:
	if _trauma <= 0.0:
		_shake_offset = Vector2.ZERO
		return
	_trauma = maxf(0.0, _trauma - _trauma_decay * delta)
	if _trauma <= 0.0:
		_trauma_decay = profile.trauma_decay
		_shake_offset = Vector2.ZERO
		_shake_phase = 0.0
		return
	_shake_phase += delta * profile.shake_frequency
	if _shake_phase >= 1.0 or _shake_offset == Vector2.ZERO:
		_shake_phase = fmod(_shake_phase, 1.0)
		var amp := profile.shake_max_offset * _trauma * _trauma
		_shake_offset = Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp)).round()


## Clears the shake/punch state only (a new camera starts calm) without touching time scale.
func reset_shake() -> void:
	_trauma = 0.0
	_trauma_decay = profile.trauma_decay
	_shake_offset = Vector2.ZERO
	_shake_phase = 0.0
	_punch = Vector2.ZERO


## Clears every live effect (tests, scene swaps).
func reset() -> void:
	restore_time()
	reset_shake()
	_last_death_frame = -1000
	_flash_frame = -1
	_flash_claims = 0
