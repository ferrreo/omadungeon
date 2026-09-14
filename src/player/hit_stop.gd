## Thin facade over `GameFeel`'s frame-based hit-stop queue, kept so ability FX, the weapon
## code and the settings panel can ask for a freeze in seconds without knowing about the feel
## service. Every request ends up in the same queue, so overlapping hits take the longest stop
## instead of compounding (see `src/core/feel/game_feel.gd`).
class_name HitStop
extends RefCounted

## Node the settings panel probes to see whether anything has already made the helper.
const NODE_NAME := GameFeel.NODE_NAME
const DEFAULT_DURATION := 0.04
const DEFAULT_SCALE := 0.05


## Freezes time for `duration` real seconds at `scale`, rounded to whole frames.
static func apply(
	tree: SceneTree, duration: float = DEFAULT_DURATION, scale: float = DEFAULT_SCALE
) -> void:
	var feel := GameFeel.instance(tree)
	if feel != null:
		feel.hit_stop_seconds(duration, scale)


## Queues a freeze measured in frames (docs §6 asks for 2-4 on a hit).
static func frames(tree: SceneTree, count: int) -> void:
	var feel := GameFeel.instance(tree)
	if feel != null:
		feel.request_hit_stop(count)


## Turns hit-stop (and the room-clear slow) on or off; off also restores normal time at once.
static func set_enabled(tree: SceneTree, on: bool) -> void:
	var feel := GameFeel.instance(tree)
	if feel == null:
		return
	feel.hit_stop_enabled = on
	if not on:
		feel.restore_time()


static func is_active(tree: SceneTree) -> bool:
	var feel := GameFeel.instance(tree)
	return feel != null and feel.is_frozen()
