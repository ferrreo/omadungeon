## Shared helpers for the game-feel suites (not a test suite).
class_name FeelTestHelpers
extends RefCounted


## A follow target that aims, so the camera's look-ahead has something to lead.
class AimTarget:
	extends Node2D

	var aim: Vector2 = Vector2.RIGHT

	func aim_direction() -> Vector2:
		return aim


## The live service, reset to a clean slate with every setting at its default.
static func fresh(tree: SceneTree) -> GameFeel:
	var feel := GameFeel.instance(tree)
	feel.enabled = true
	feel.hit_stop_enabled = true
	feel.reset()
	GameState.settings["screen_shake"] = true
	GameState.settings["reduced_flash"] = false
	GameState.settings["reduce_motion"] = false
	return feel


## Runs `count` rendered frames (hit-stop is counted in those, not in physics ticks).
static func process_frames(tree: SceneTree, count: int) -> void:
	for _i in range(maxi(1, count)):
		await tree.process_frame


static func physics_frames(tree: SceneTree, count: int) -> void:
	for _i in range(maxi(1, count)):
		await tree.physics_frame


## Waits (bounded) until the freeze the caller queued has ended.
static func wait_for_thaw(tree: SceneTree, feel: GameFeel, limit: int = 240) -> void:
	var guard := 0
	while feel.is_frozen() and guard < limit:
		guard += 1
		await tree.process_frame
