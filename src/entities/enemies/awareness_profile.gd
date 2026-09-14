## How enemies notice the player, as data (`data/enemies/awareness.tres`).
##
## Before this resource existed there was no noticing at all: every enemy on the floor picked
## the player as its target on the frame it spawned and walked at them through the walls, so a
## floor was one long chase and exploring bought nothing. The numbers below are the whole
## model — how far an enemy can see, how close you have to be before it hears you anyway, how
## far a wake-up travels through its pack, and how long it keeps coming after it loses you.
##
## They live here rather than in `EnemyBase` so pacing can be retuned without touching the
## state machine. A single enemy that should be keener or dozier than the rest overrides
## `EnemyDef.sight_range` instead of changing this file.
class_name AwarenessProfile
extends Resource

const PATH := "res://data/enemies/awareness.tres"

static var _cached: AwarenessProfile

## How far (px) an enemy can spot the player, with a clear line of sight. The internal
## viewport is 480x270, so this is deliberately well under half a screen: an enemy on the far
## side of a big room stays asleep until you commit to the room.
@export var sight_range: float = 160.0
## Distance (px) at which an enemy notices the player with no line of sight at all — you
## brushed past it. One and a half tiles plus a body.
@export var close_range: float = 28.0
## How far past `sight_range` an enemy keeps contact once it is already chasing, so stepping
## one pixel out of range does not switch it off.
@export var forget_slack: float = 1.25
## Radius (px) a fresh wake-up travels to sleeping allies.
@export var ally_wake_radius: float = 72.0
## Seconds an ally waits before it wakes in turn, so a pack notices you as a ripple the player
## can read rather than as one snap.
@export var ally_wake_delay: float = 0.3
## Seconds an alerted enemy keeps pressing after it has lost contact, before it settles.
@export var search_seconds: float = 3.5
## Seconds between two perception probes. Perception costs at most one cached raycast, and an
## enemy that notices you a tenth of a second late is not a bug the player can see.
@export var probe_interval: float = 0.15
## Seconds the "!" over a waking enemy is held.
@export var mark_seconds: float = 0.7
## Fraction of its move speed a settled enemy walks back to its post at.
@export var return_speed_scale: float = 0.55
## How close (px) to its post counts as home.
@export var home_tolerance: float = 6.0


## The shipped profile, loaded once. Falls back to a fresh default when the resource is
## missing, so a stripped export or a test with no data directory still runs.
static func shared() -> AwarenessProfile:
	if _cached != null:
		return _cached
	if ResourceLoader.exists(PATH):
		_cached = load(PATH) as AwarenessProfile
	if _cached == null:
		_cached = AwarenessProfile.new()
	return _cached


## Sight range for an enemy whose own reach is `attack_range`: never less than the attack it
## could already be making. A Manpage Hurler throws 150 px and must not sit asleep inside its
## own throwing range because the shared number is 160.
func sight_for(attack_range: float, override_range: float = 0.0) -> float:
	var base := override_range if override_range > 0.0 else sight_range
	return maxf(base, attack_range * 1.1)


## Distance at which contact is lost by an enemy already chasing.
func forget_range(sight: float) -> float:
	return sight * maxf(1.0, forget_slack)
