## The small, in-place life of an enemy that has not noticed anything yet.
##
## An enemy at its post used to be exactly motionless: `EnemyBase._unaware_process` asked for a
## velocity and got zero unless something had dragged the enemy off its home tile, so a room of
## sleeping enemies read as a shelf of statues. The owner's report was "they either just stand
## still or only dash".
##
## The fix has to respect the rule that produced the stillness in the first place (decisions
## log, and `tests/unit/enemies/awareness_test.gd`: "enemies should only path to the user after
## spotting them"). So this is a *leash*, not a patrol: it picks a spot within `DRIFT_RADIUS`
## of the post, ambles there at about a third of walking speed, stands for a beat, and picks
## another. It is never told where the player is and cannot be - the only inputs are the
## enemy's own position and its post - so no drift can ever close distance on purpose.
##
## Deliberately a plain `RefCounted` with no node, no timer and no raycast of its own: the
## leash is the part worth testing, forty sleeping enemies cost forty floats rather than forty
## timers, and the caller keeps ownership of how the returned point is walked to.
class_name EnemyIdle
extends RefCounted

## Returned by `tick` when the enemy should stand still this frame.
const HOLD := Vector2.INF
## How far (px) from its post a drift may take an enemy: under a tile, so a sleeping pack never
## loses the formation the generator placed it in and never drifts through a doorway.
const DRIFT_RADIUS := 12.0
## Shortest drift worth taking: below this the step does not read as movement.
const MIN_STEP := 5.0
## Seconds a drift may take before the enemy gives up on reaching the spot - a wall, a pit edge
## or a neighbour leaning on it - and holds where it got to.
const STEP_SECONDS := 1.2
## Seconds spent standing between two drifts. The spread is what stops a pack stepping in time.
const HOLD_MIN := 0.7
const HOLD_MAX := 2.2
## Fraction of move speed a drift is walked at. A sleeping enemy must not move like a chasing
## one, so this sits well under `AwarenessProfile.return_speed_scale`.
const DRIFT_SPEED_SCALE := 0.34
## How close (px) to the spot counts as arrived.
const ARRIVE := 1.5

## Fraction of move speed the caller should walk the returned point at: a drift is a saunter, a
## walk back to an abandoned post is brisker.
var speed_scale: float = DRIFT_SPEED_SCALE

var _rng := RandomNumberGenerator.new()
var _spot: Vector2 = HOLD
var _hold_left: float = 0.0
var _step_left: float = 0.0
var _returning: bool = false
var _seeded: bool = false


## The point the enemy should be walking to this frame, or `HOLD` to stand still.
##
## `home` is the post. Once the enemy is further from it than a drift could have put it,
## something else moved it - knockback, a pit, a chase that just settled - and the answer is
## the post itself until it is properly home again, not merely back inside the leash.
func tick(delta: float, pos: Vector2, home: Vector2, profile: AwarenessProfile) -> Vector2:
	if not _seeded:
		_seeded = true
		# Seeded from the post: a pack placed by one floor seed idles identically on every
		# replay of that seed, and two enemies on neighbouring tiles still drift out of step.
		_rng.seed = hash(home)
		_hold_left = _rng.randf_range(0.0, HOLD_MAX)
	var leash := profile.home_tolerance if _returning else DRIFT_RADIUS + profile.home_tolerance
	if pos.distance_to(home) > leash:
		_returning = true
		speed_scale = profile.return_speed_scale
		_spot = HOLD
		_hold_left = 0.0
		_step_left = 0.0
		return home
	_returning = false
	speed_scale = DRIFT_SPEED_SCALE
	if _hold_left > 0.0:
		_hold_left -= delta
		return HOLD
	if _step_left > 0.0:
		_step_left -= delta
		if _step_left > 0.0 and pos.distance_to(_spot) > ARRIVE:
			return _spot
		_step_left = 0.0
		_hold_left = _rng.randf_range(HOLD_MIN, HOLD_MAX)
		return HOLD
	_spot = _pick_spot(home)
	_step_left = STEP_SECONDS
	return _spot


## A spot to amble to: anywhere in the ring between `MIN_STEP` and `DRIFT_RADIUS` of the post.
func _pick_spot(home: Vector2) -> Vector2:
	var angle := _rng.randf() * TAU
	return home + Vector2.RIGHT.rotated(angle) * _rng.randf_range(MIN_STEP, DRIFT_RADIUS)
