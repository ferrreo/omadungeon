## Whether one enemy has noticed the player yet, and how long it keeps believing it.
##
## Deliberately a plain `RefCounted` with no node, no tree and no raycasts of its own: the
## rule ("can it see you, is it close enough to hear you, has it lost you long enough to give
## up") is the part worth testing, and `EnemyBase` feeds it the two measurements — distance and
## line of sight — that only a live scene can produce.
##
## Three stances, and the difference between the last two is what stops a chase being a hunt:
##
## * `ASLEEP` — at its post. It does not path anywhere; it probes for the player on an
##   interval and walks home if something dragged it off.
## * `ALERT` — it has contact and chases normally.
## * `SEARCHING` — it had contact and lost it. It keeps pressing for `search_seconds`, which
##   is what stops a player breaking line of sight for one frame from switching a fight off,
##   and then settles back to `ASLEEP`.
class_name EnemyAwareness
extends RefCounted

enum Stance { ASLEEP, ALERT, SEARCHING }

var profile: AwarenessProfile = AwarenessProfile.shared()
var stance: Stance = Stance.ASLEEP
## Bosses, converted allies and mid-fight summons: already in the fight, never settle.
var never_sleeps: bool = false
## This enemy's own spotting distance (px), from `AwarenessProfile.sight_for`.
var sight: float = 160.0

var _probe_left: float = 0.0
var _search_left: float = 0.0
var _ally_delay_left: float = 0.0


## Wires the profile, this enemy's sight range and whether it is allowed to sleep at all.
func configure(new_profile: AwarenessProfile, sight_range: float, always_awake: bool) -> void:
	if new_profile != null:
		profile = new_profile
	sight = maxf(0.0, sight_range)
	never_sleeps = always_awake
	if never_sleeps:
		stance = Stance.ALERT


func is_awake() -> bool:
	return never_sleeps or stance != Stance.ASLEEP


## True when the enemy is chasing something it can currently account for.
func has_contact() -> bool:
	return stance == Stance.ALERT


## Seconds of chase left before a searching enemy gives up (0 when it is not searching).
func search_left() -> float:
	return _search_left if stance == Stance.SEARCHING else 0.0


## Ticks the perception clock. True on the frame a probe is due — the caller pays for the
## distance and the raycast only then, not every frame.
func due_for_probe(delta: float) -> bool:
	_probe_left -= delta
	if _probe_left > 0.0:
		return false
	_probe_left = maxf(0.016, profile.probe_interval)
	return true


## Ticks the timers that do not need a probe: a pack-mate's wake-up arriving, and the countdown
## of a search. Returns true when this tick is the moment the enemy woke (a delayed ally
## wake landing), so the caller can show the tell.
func tick(delta: float) -> bool:
	if _ally_delay_left > 0.0:
		_ally_delay_left -= delta
		if _ally_delay_left <= 0.0:
			_ally_delay_left = 0.0
			return alert()
	if stance == Stance.SEARCHING:
		_search_left -= delta
		if _search_left <= 0.0:
			settle()
	return false


## One perception probe. `distance` and `has_los` are measured against the enemy's target.
## Returns true when this probe is what woke a sleeping enemy (the caller shows the "!" and
## passes the word to its neighbours).
func perceive(distance: float, has_los: bool) -> bool:
	if _in_contact(distance, has_los):
		var was_asleep := stance == Stance.ASLEEP and not never_sleeps
		_search_left = profile.search_seconds
		stance = Stance.ALERT
		_ally_delay_left = 0.0
		return was_asleep
	# Something that never sleeps has nothing to search for: it stays ALERT, so its stance
	# never reads as a state it cannot leave and its search clock never runs off into the
	# negatives one frame at a time.
	if stance == Stance.ALERT and not never_sleeps:
		stance = Stance.SEARCHING
		_search_left = profile.search_seconds
	return false


## Wakes the enemy outright — the player walked into its room, hit it, or a script said so.
## Returns true when it was asleep (so only a real wake-up raises a tell).
func alert() -> bool:
	var was_asleep := stance == Stance.ASLEEP and not never_sleeps
	stance = Stance.ALERT
	_search_left = profile.search_seconds
	_ally_delay_left = 0.0
	return was_asleep


## A neighbour noticed the player. The wake lands `ally_wake_delay` later so a pack turns
## around as a ripple instead of all at once. False when it is already awake or already
## nudged, which is what stops two enemies waking each other forever.
func nudge_from_ally() -> bool:
	if is_awake() or _ally_delay_left > 0.0:
		return false
	_ally_delay_left = maxf(0.0, profile.ally_wake_delay)
	if _ally_delay_left <= 0.0:
		return alert()
	return true


## True while a neighbour's wake-up is on its way but has not landed yet.
func is_waking() -> bool:
	return _ally_delay_left > 0.0


## Back to the post. A no-op for anything that never sleeps.
func settle() -> void:
	if never_sleeps:
		return
	stance = Stance.ASLEEP
	_search_left = 0.0
	_ally_delay_left = 0.0


func _in_contact(distance: float, has_los: bool) -> bool:
	if distance <= profile.close_range:
		return true
	if not has_los:
		return false
	var reach := profile.forget_range(sight) if is_awake() else sight
	return distance <= reach
