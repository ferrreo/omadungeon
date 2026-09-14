## The reactivity levers as the player meets them, on a real run built by the RunManager
## autoload: the music energy decides how many enemies are actually spawned (and never two on
## one tile), and boss music starts on the threshold of the boss room, not on the boss floor.
## `manage_scenes` is off so the gdUnit runner stays the current scene.
class_name ReactiveRunTest
extends GdUnitTestSuite

const SEED := 5150
const CLASS_ID := &"fighter"


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## Every live enemy's tile, per room, on the current floor.
func _enemy_tiles(root: FloorRoot) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if root != null and not root.is_ancestor_of(enemy):
			continue
		out.append(Vector2i((enemy.global_position / Layers.TILE).floor()))
	return out


func test_no_two_enemies_are_spawned_on_the_same_tile() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var checked := 0
	for _floor in range(4):
		var root := RunManager.floor_root()
		assert_object(root).is_not_null()
		var tiles := _enemy_tiles(root)
		assert_int(tiles.size()).is_greater(0)
		var seen: Dictionary = {}
		for tile: Vector2i in tiles:
			(
				assert_bool(seen.has(tile))
				. override_failure_message(
					"floor %d spawned two enemies on tile %s" % [RunManager.floor_index, tile]
				)
				. is_false()
			)
			seen[tile] = true
		checked += tiles.size()
		EventBus.floor_exit_requested.emit()
		await _frames(4)
	assert_int(checked).is_greater(10)


func test_the_pack_never_exceeds_the_spawn_points_the_generator_scaled() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	var data := RunManager.floor_data
	var per_room: Dictionary = {}
	for tile: Vector2i in _enemy_tiles(root):
		var room := data.room_at(tile)
		if room == null:
			continue
		per_room[room.id] = int(per_room.get(room.id, 0)) + 1
	assert_int(per_room.size()).is_greater(0)
	for room_id: int in per_room:
		var room := data.room_by_id(room_id)
		if room.type == FloorData.RoomType.BOSS:
			continue
		(
			assert_int(int(per_room[room_id]))
			. override_failure_message(
				(
					"room %d holds %d enemies for %d spawn points"
					% [room_id, int(per_room[room_id]), room.enemy_spawns.size()]
				)
			)
			. is_less_equal(room.enemy_spawns.size())
		)


func test_boss_music_waits_for_the_boss_room() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	while RunManager.floor_index < 2:
		EventBus.floor_exit_requested.emit()
		await _frames(4)
	assert_int(RunManager.floor_index).is_equal(2)
	var data := RunManager.floor_data
	assert_int(data.boss_room).is_greater_equal(0)
	# Standing in the start room of a boss floor: the radio is still playing.
	(
		assert_int(Music.mode)
		. override_failure_message("boss music started with the floor instead of the boss room")
		. is_not_equal(MusicManager.Mode.BOSS)
	)
	EventBus.room_entered.emit(data.boss_room)
	await _frames(2)
	assert_int(Music.mode).is_equal(MusicManager.Mode.BOSS)
