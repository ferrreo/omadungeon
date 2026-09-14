## Greybeard that closes in hjkl steps: it walks the dominant cardinal at its own `move_speed`
## and punctuates the approach with a fast dash along that same axis. Never diagonal - and,
## since the owner's report "they either just stand still or only dash", never still either.
## The dead pause that used to sit between two dashes is now the walk, so what a player sees is
## a thing coming at them that lunges, rather than a thing hopping a body-length and freezing.
class_name VimZealot
extends EnemyBase

## Shortest burst worth firing: below this the lunge does not read as one.
const MIN_DASH := 12.0
## How squarely a contact normal must oppose travel before it counts as being blocked. A wall
## being slid along reads about 0 here; something walked into head-on reads -1.
const BLOCK_DOT := -0.5

var _stab: MeleeLunge
var _dash_dir: Vector2 = Vector2.ZERO
## Px of the current burst still to travel (0 while walking).
var _dash_left: float = 0.0
## Seconds of walking left before the next burst fires (0 while dashing).
var _walk_left: float = 0.0
## Seconds left of preferring the *minor* axis, after the dominant one ran into something.
var _flip_left: float = 0.0


func _ready() -> void:
	super._ready()
	_stab = add_attack(MeleeLunge.new()) as MeleeLunge


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != State.APPROACH or not _blocked_ahead():
		return
	# Blocked along the axis it chose. Cut the segment short and take the other axis for a
	# beat: that is how a cardinal-only walker turns a corner instead of grinding into it.
	_dash_left = 0.0
	_walk_left = 0.0
	_flip_left = _walk_time()


## True when one of this frame's slide contacts actually opposes travel.
##
## This used to be `get_slide_collision_count() > 0`, and that is the bug the owner reported as
## "they never dashed even when I walked up and hit them". An enemy body masks WORLD | PROP
## (`enemy_base.tscn`, 4097) and props became solid colliders this round, so anywhere cramped a
## zealot touches something on nearly every frame - and every dash died on the frame it
## started, over and over, with the pause restarting each time. A wall it is *sliding along*
## and a prop it brushes past are contacts that cost it nothing, so only a normal pointing back
## into the direction of travel may stop it.
func _blocked_ahead() -> bool:
	for i in range(get_slide_collision_count()):
		if get_slide_collision(i).get_normal().dot(_dash_dir) < BLOCK_DOT:
			return true
	return false


func _approach_process(delta: float) -> void:
	var to_target := target.global_position - global_position
	if can_start_attack(to_target.length()):
		_dash_left = 0.0
		_walk_left = 0.0
		_enter_state(State.WINDUP)
		return
	_flip_left = maxf(0.0, _flip_left - delta)
	if _dash_left <= 0.0 and _walk_left <= 0.0:
		_dash_dir = _cardinal(to_target)
		_walk_left = _walk_time()
	if _dash_dir.length_squared() < 0.5:
		return
	if _walk_left > 0.0:
		_walk_left -= delta
		desired_velocity = _dash_dir * effective_speed()
		if _walk_left <= 0.0:
			_dash_left = _dash_span(to_target)
		return
	var dash_speed := def.param(&"dash_speed", 240.0) * status.speed_multiplier()
	_dash_left -= dash_speed * delta
	desired_velocity = _dash_dir * dash_speed


## Seconds of walking between two bursts.
func _walk_time() -> float:
	return def.param(&"walk_time", 0.85)


## The axis to travel this segment: the one with more ground left to cover, or the other one
## while `_flip_left` runs, which is what unsticks a zealot pressed into a wall. The flip is
## refused when the minor axis has nothing to travel along, so it never returns a zero step.
func _cardinal(to_target: Vector2) -> Vector2:
	var horizontal := absf(to_target.x) > absf(to_target.y)
	if _flip_left > 0.0 and minf(absf(to_target.x), absf(to_target.y)) > 1.0:
		horizontal = not horizontal
	if horizontal:
		return Vector2(signf(to_target.x), 0.0)
	return Vector2(0.0, signf(to_target.y))


## How far the next burst travels: what is left along the chosen axis once the attack's own
## reach is discounted, capped at `dash_length` and never shorter than `MIN_DASH`.
func _dash_span(to_target: Vector2) -> float:
	var along := absf(to_target.x) if _dash_dir.x != 0.0 else absf(to_target.y)
	return clampf(along - def.attack_range * 0.5, MIN_DASH, def.param(&"dash_length", 44.0))


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_stab.damage = base_damage()
	_stab.reach = 16.0
	_stab.width = 10.0
	_stab.lunge_speed = 200.0
	_stab.knockback = 80.0
	run_attack(_stab, target.global_position)
