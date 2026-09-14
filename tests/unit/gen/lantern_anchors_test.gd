## The lighting system's hooks (docs 5.1 #8, `LanternAnchors`): every anchor is a wall tile
## facing open ground, none in or beside a doorway, the biome's spacing holds along a run,
## every room gets at least one, and the list is a function of the seed that survives a save.
class_name LanternAnchorsTest
extends GdUnitTestSuite

const SEEDS := 60


func _generate(theme: String, seed_value: int, floor_index: int) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
	return FloorGenerator.generate(params, rng)


func test_every_anchor_is_a_wall_tile_facing_walkable_ground() -> void:
	var checked := 0
	for i in range(SEEDS):
		var data := _generate("tokyo-night", 9000 + i, i % 9)
		assert_bool(data.lantern_anchors.is_empty()).is_false()
		var seen: Dictionary = {}
		for p: Vector2i in data.lantern_anchors:
			assert_int(data.get_tile(p.x, p.y)).is_equal(FloorData.Tile.WALL)
			var faces_ground := false
			for d: Vector2i in GenUtil.DIRS4:
				if data.is_walkable(p.x + d.x, p.y + d.y):
					faces_ground = true
			assert_bool(faces_ground).override_failure_message("%s faces nothing" % p).is_true()
			assert_bool(seen.has(p)).is_false()
			seen[p] = true
			checked += 1
	assert_int(checked).is_greater(SEEDS * 20)


## Same shape as `arena_spawns_test`: the two tests below measure against
## `LanternAnchors.DOOR_CLEARANCE` and `MIN_SPACING`, the constants the placer itself obeys, so
## neither can see the spacing being flattened. These are the literals those constants have to
## clear. A clearance of 2 keeps a lantern off the tile a door opens onto and its neighbour; a
## spacing of 3 is what stops a wall becoming a strip light, which is the whole point of
## spacing lanterns rather than filling the wall with them.
func test_the_spacing_guarantees_are_numbers_not_tautologies() -> void:
	(
		assert_int(LanternAnchors.DOOR_CLEARANCE)
		. override_failure_message("DOOR_CLEARANCE fell to %d; doorways stop being clear")
		. is_greater_equal(2)
	)
	(
		assert_int(LanternAnchors.MIN_SPACING)
		. override_failure_message("MIN_SPACING fell to %d; a wall becomes a strip light")
		. is_greater_equal(3)
	)
	(
		assert_int(LanternAnchors.MIN_APART)
		. override_failure_message("MIN_APART fell to %d; two lanterns may share a tile edge")
		. is_greater_equal(2)
	)


func test_no_anchor_in_or_beside_a_doorway() -> void:
	for i in range(SEEDS):
		var data := _generate("gruvbox", 9100 + i, i % 9)
		var doors: Array[Vector2i] = []
		for room: FloorData.Room in data.rooms:
			doors.append_array(room.door_tiles())
		for p: Vector2i in data.lantern_anchors:
			for door: Vector2i in doors:
				(
					assert_int(GenUtil.chebyshev(p, door))
					. override_failure_message("anchor %s sits beside door %s" % [p, door])
					. is_greater_equal(LanternAnchors.DOOR_CLEARANCE)
				)


func test_anchors_keep_the_biome_spacing_along_a_wall_and_never_touch() -> void:
	for i in range(SEEDS):
		var floor_index := i % 9
		var data := _generate("nord", 9200 + i, floor_index)
		var spacing := Biome.load_by_id(data.biome).lantern_spacing
		assert_int(spacing).is_greater_equal(LanternAnchors.MIN_SPACING)
		var anchors := data.lantern_anchors
		for a in range(anchors.size()):
			for b in range(a + 1, anchors.size()):
				assert_int(GenUtil.chebyshev(anchors[a], anchors[b])).is_greater_equal(
					LanternAnchors.MIN_APART
				)
		# Along one side of one room's ring, two anchors are never closer than the spacing.
		for room: FloorData.Room in data.rooms:
			for side: Array[Vector2i] in LanternAnchors.ring_sides(room):
				var on_side: Array[int] = []
				for k in range(side.size()):
					if side[k] in anchors:
						on_side.append(k)
				for k in range(1, on_side.size()):
					assert_int(on_side[k] - on_side[k - 1]).is_greater_equal(spacing)


func test_biomes_space_their_lanterns_differently() -> void:
	var spacings: Dictionary = {}
	for id: StringName in Biome.ALL_IDS:
		spacings[Biome.load_by_id(id).lantern_spacing] = true
	assert_int(spacings.size()).is_greater_equal(3)
	assert_int(Biome.load_by_id(&"void").lantern_spacing).is_greater(
		Biome.load_by_id(&"forge").lantern_spacing
	)


func test_every_room_with_a_free_wall_has_a_lantern() -> void:
	var rooms := 0
	var lit := 0
	for i in range(SEEDS):
		var data := _generate("catppuccin", 9300 + i, i % 9)
		var zone := LanternAnchors.door_zone(data)
		for room: FloorData.Room in data.rooms:
			var ring := room.ring()
			var candidates := 0
			for side: Array[Vector2i] in LanternAnchors.ring_sides(room):
				for p: Vector2i in side:
					if LanternAnchors.is_anchor_tile(data, p, zone):
						candidates += 1
			if candidates == 0:
				continue
			rooms += 1
			var count := 0
			for p: Vector2i in data.lantern_anchors:
				if ring.has_point(p) and not room.rect.has_point(p):
					count += 1
			if count >= 1:
				lit += 1
			(
				assert_int(count)
				. override_failure_message("room %d (%s) has no lantern" % [room.id, room.rect])
				. is_greater_equal(1)
			)
	assert_int(rooms).is_greater(SEEDS * 5)
	assert_int(lit).is_equal(rooms)


func test_anchors_are_deterministic_and_survive_the_save_block() -> void:
	for i in range(10):
		var floor_index := i % 9
		var params := GenParams.from_profile(GenParamsTest.profile_for("white"), floor_index)
		var a := FloorGenerator.generate(
			params, RunRng.new(41 + i).floor_stream(&"gen", floor_index)
		)
		var restored := FloorRestore.gen_params_for(
			floor_index, FloorRestore.gen_params_to_dict(params)
		)
		var b := FloorGenerator.generate(
			restored, RunRng.new(41 + i).floor_stream(&"gen", floor_index)
		)
		assert_array(a.lantern_anchors).is_equal(b.lantern_anchors)
		assert_int(a.layout_hash()).is_equal(b.layout_hash())
	# The hash sees the anchors: moving one changes it.
	var data := _generate("white", 41, 0)
	var before := data.layout_hash()
	data.lantern_anchors.append(Vector2i(1, 1))
	assert_int(data.layout_hash()).is_not_equal(before)


func test_placing_by_hand_honours_the_rules_on_a_fallback_floor() -> void:
	var params := GenParams.from_profile(GenParamsTest.profile_for("tokyo-night"), 2)
	var data := FloorGenerator.fallback_floor(params)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var anchors := LanternAnchors.place(data, 4, rng)
	assert_bool(anchors.is_empty()).is_false()
	var zone := LanternAnchors.door_zone(data)
	for p: Vector2i in anchors:
		assert_bool(LanternAnchors.is_anchor_tile(data, p, zone)).is_true()
		assert_bool(zone.has(p)).is_false()
