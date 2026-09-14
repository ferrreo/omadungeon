## The boss never stands in the doorway (docs 7.4, owner report #6): its spawn and the
## fallback pack's spots sit across the arena, clear of every door, on every boss floor and
## every fixture; ordinary packs keep their door clearance too; and corridor dressing never
## opens a shortcut the room graph does not know about.
class_name ArenaSpawnsTest
extends GdUnitTestSuite

const SEEDS := 100
const BOSS_FLOORS: Array[int] = [2, 5, 8]
## The owner's floor for ordinary rooms; the generator's own clearance is 3.
const MIN_PACK_CLEARANCE := 2


func _generate(theme: String, seed_value: int, floor_index: int) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
	return FloorGenerator.generate(params, rng)


## The bound the test below uses is `ArenaSpawns.DOOR_CLEARANCE`, which is also the number the
## placer filters on - so the two move together and that test alone cannot see the guarantee
## being weakened. Drop the constant from 8 to 2 and every spawn is still "far enough" by its
## own definition. This is the literal the constant has to clear, so a quiet loosening fails
## here instead of passing everywhere: 8 tiles is roughly two player-lengths of warning before
## a boss pack is on top of someone walking in, and anything under 6 is not a doorway that can
## be entered safely at all.
func test_the_door_clearance_guarantee_is_a_number_not_a_tautology() -> void:
	(
		assert_int(ArenaSpawns.DOOR_CLEARANCE)
		. override_failure_message(
			(
				(
					"ArenaSpawns.DOOR_CLEARANCE is %d; the arena-spawn test measures against this "
					+ "same constant, so lowering it silently lowers the guarantee too"
				)
				% ArenaSpawns.DOOR_CLEARANCE
			)
		)
		. is_greater_equal(6)
	)


func test_the_boss_spawns_far_from_every_door_over_a_hundred_seeds() -> void:
	var checked := 0
	for i in range(SEEDS):
		var floor_index: int = BOSS_FLOORS[i % BOSS_FLOORS.size()]
		var theme: String = GenParamsTest.THEMES[i % GenParamsTest.THEMES.size()]
		var data := _generate(theme, 8000 + i, floor_index)
		var boss := data.room_by_id(data.boss_room)
		assert_object(boss).is_not_null()
		assert_bool(boss.enemy_spawns.is_empty()).is_false()
		var doors := boss.door_tiles()
		assert_int(doors.size()).is_greater_equal(1)
		for p: Vector2i in boss.enemy_spawns:
			var clearance := ArenaSpawns.door_distance(doors, p)
			(
				assert_float(clearance)
				. override_failure_message(
					(
						"seed %d floor %d: arena spawn %s is %d from a door"
						% [8000 + i, floor_index, p, int(clearance)]
					)
				)
				. is_greater_equal(float(ArenaSpawns.DOOR_CLEARANCE))
			)
			assert_bool(boss.rect.grow(-ArenaSpawns.WALL_INSET).has_point(p)).is_true()
			checked += 1
	assert_int(checked).is_greater_equal(SEEDS)


func test_the_boss_stands_across_from_the_door_not_in_a_corner() -> void:
	for i in range(30):
		var data := _generate("tokyo-night", 8500 + i, BOSS_FLOORS[i % 3])
		var boss := data.room_by_id(data.boss_room)
		var door := boss.door_tiles()[0]
		var spot := boss.enemy_spawns[0]
		var c := boss.center()
		var horizontal_door := door.y < boss.rect.position.y or door.y >= boss.rect.end.y
		# The far side: past the centre away from the door, near the centre line.
		if horizontal_door:
			assert_bool(signi(spot.y - c.y) == signi(c.y - door.y) or spot.y == c.y).is_true()
			assert_int(absi(spot.x - c.x)).is_less_equal(3)
		else:
			assert_bool(signi(spot.x - c.x) == signi(c.x - door.x) or spot.x == c.x).is_true()
			assert_int(absi(spot.y - c.y)).is_less_equal(3)


func test_the_fallback_pack_has_spots_of_its_own_near_the_boss() -> void:
	for i in range(30):
		var data := _generate("gruvbox", 8600 + i, BOSS_FLOORS[i % 3])
		var boss := data.room_by_id(data.boss_room)
		assert_int(boss.enemy_spawns.size()).is_between(2, ArenaSpawns.PACK_SPOTS + 1)
		var seen: Dictionary = {}
		for p: Vector2i in boss.enemy_spawns:
			assert_bool(seen.has(p)).is_false()
			seen[p] = true
			assert_int(GenUtil.chebyshev(p, boss.enemy_spawns[0])).is_less_equal(6)


func test_ordinary_packs_never_spawn_within_two_tiles_of_a_door() -> void:
	var checked := 0
	for i in range(SEEDS):
		var data := _generate("catppuccin", 8700 + i, i % 9)
		for room: FloorData.Room in data.rooms:
			if room.type == FloorData.RoomType.BOSS:
				continue
			for p: Vector2i in room.enemy_spawns:
				for door: Vector2i in room.door_tiles():
					assert_int(GenUtil.chebyshev(door, p)).is_greater(MIN_PACK_CLEARANCE)
					checked += 1
	assert_int(checked).is_greater(500)


func test_the_validator_rejects_a_boss_in_the_doorway() -> void:
	var data := _generate("nord", 8800, 2)
	assert_array(FloorValidator.validate(data)).is_empty()
	var boss := data.room_by_id(data.boss_room)
	var door := boss.door_tiles()[0]
	boss.enemy_spawns = [door + boss.trap_facing(door) * 3]
	var violations := FloorValidator.validate(data)
	assert_bool(violations.is_empty()).is_false()
	var mentions_arena := false
	for v: String in violations:
		if v.begins_with("boss room"):
			mentions_arena = true
	assert_bool(mentions_arena).is_true()


func test_corridor_dressing_opens_tiles_without_shortcuts() -> void:
	var dressed := 0
	for i in range(40):
		var data := _generate("white", 8900 + i, i % 9)
		assert_array(FloorValidator.validate(data)).is_empty()
		var owner: Dictionary = {}
		for index in range(data.corridors.size()):
			var corridor := data.corridors[index]
			for p: Vector2i in corridor.path:
				owner[p] = index
			for room_id: int in [corridor.from_room, corridor.to_room]:
				var room := data.room_by_id(room_id)
				var other := (
					corridor.to_room if room_id == corridor.from_room else corridor.from_room
				)
				if room.doors.has(other):
					owner[room.doors[other]] = index
		for index in range(data.corridors.size()):
			for p: Vector2i in data.corridors[index].extra:
				dressed += 1
				assert_int(data.get_tile(p.x, p.y)).is_equal(FloorData.Tile.CORRIDOR)
				for d: Vector2i in GenUtil.DIRS4:
					var q := p + d
					if not data.is_walkable(q.x, q.y):
						continue
					if owner.has(q):
						assert_int(int(owner[q])).is_equal(index)
					else:
						# Only another dressed tile of the same corridor may be walkable here.
						assert_bool(q in data.corridors[index].extra).is_true()
	assert_int(dressed).is_greater(50)


func test_a_resumed_floor_carries_its_arena_spawns() -> void:
	var params := GenParams.from_profile(GenParamsTest.profile_for("tokyo-night"), 5)
	var saved := FloorRestore.gen_params_to_dict(params)
	var restored := FloorRestore.gen_params_for(5, saved)
	var a := FloorGenerator.generate(params, RunRng.new(31).floor_stream(&"gen", 5))
	var b := FloorGenerator.generate(restored, RunRng.new(31).floor_stream(&"gen", 5))
	assert_int(a.layout_hash()).is_equal(b.layout_hash())
	assert_array(a.rooms[a.boss_room].enemy_spawns).is_equal(b.rooms[b.boss_room].enemy_spawns)
	assert_str(String(a.archetype)).is_equal(String(b.archetype))
