## The running totals a finished run is reported with: kills, damage taken, gold earned, wall
## time, and what hit the player last.
##
## `RunManager` owns one per run and feeds it from the EventBus. It lives apart from the
## manager because the death screen, the autosave snapshot and the resume path all want the
## same numbers, and because "what killed me" is a fact about the run rather than about the
## scene machinery.
class_name RunTally
extends RefCounted

var kills: int = 0
var damage_taken: int = 0
var gold_earned: int = 0
## Display name of whatever last damaged the player, and how hard it hit. `player_died`
## carries no source, so the death screen's "Killed by" is reconstructed from this.
var last_hit_name: String = ""
var last_hit_amount: int = 0

var _gold_seen: int = 0
## True while the starting loadout is being applied: the `gold_changed` emissions from
## `apply_class` (the Oligarch starts with 150g) and from `restore_from_dict` only prime
## `_gold_seen`. Counting them would report a run's starting purse as gold earned, and would
## count it again on every resume.
var _gold_guard: bool = true
var _started_msec: int = 0


## Starts a fresh run at zero.
func begin() -> void:
	kills = 0
	damage_taken = 0
	gold_earned = 0
	last_hit_name = ""
	last_hit_amount = 0
	_gold_seen = 0
	_gold_guard = true
	_started_msec = Time.get_ticks_msec()


## Restores the totals of a resumed run, rebasing the clock so `elapsed()` keeps counting.
func restore(state: RunState) -> void:
	begin()
	if state == null:
		return
	kills = state.kills
	damage_taken = state.damage_taken
	gold_earned = state.gold_earned
	_started_msec = Time.get_ticks_msec() - int(state.time_played * 1000.0)


## Ends the start-of-run gold guard once `live`'s loadout is in place, priming the baseline
## with the purse it starts on.
func prime_gold(live: Player) -> void:
	_gold_seen = live.gold if live != null else 0
	_gold_guard = false


func record_kill() -> void:
	kills += 1


## `source` is the node that dealt the hit; a named one becomes the run's "killed by".
func record_damage(amount: int, source: Node2D) -> void:
	damage_taken += amount
	var name := RunBuild.source_name(source)
	if not name.is_empty():
		last_hit_name = name
		last_hit_amount = amount


## `gold_changed` carries the new total; only positive deltas count as earned.
func record_gold(total: int) -> void:
	if _gold_guard:
		_gold_seen = total
		return
	if total > _gold_seen:
		gold_earned += total - _gold_seen
	_gold_seen = total


func elapsed() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


## The run-summary payload: these totals plus the run's `identity` (seed, class, theme,
## floor) as the caller spells it. The build is merged in on top by `RunBuild.snapshot`.
func to_summary(victory: bool, identity: Dictionary = {}) -> Dictionary:
	var out := {
		"victory": victory,
		"kills": kills,
		"gold": gold_earned,
		"damage_taken": damage_taken,
		"time": elapsed(),
		"killer": "" if victory else last_hit_name,
		"last_hit": 0 if victory else last_hit_amount,
	}
	out.merge(identity, true)
	return out
