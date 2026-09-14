## Playability guarantees that go beyond "the validator is happy": enemies must be able to
## leave their spawn tile, the walkable map must match the room graph, mask templates must
## stamp, and a hopeless generation must still hand back a floor the player can finish.
class_name FloorQualityTest
extends GdUnitTestSuite

const SPECIAL_TYPES: Array[int] = [
	FloorData.RoomType.ELITE, FloorData.RoomType.TRAP, FloorData.RoomType.TREASURE
]


func _generate(theme: String, seed_value: int, floor_index: int) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	return FloorGenerator.generate(params, RunRng.new(seed_value).floor_stream(&"gen", floor_index))


## Interior tiles of `room` reachable from one of its doors with props and pits solid.
func _reachable(data: FloorData, room: FloorData.Room) -> Dictionary:
	var solid: Dictionary = {}
	for p: Vector2i in room.prop_positions:
		solid[p] = true
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for door: Vector2i in room.door_tiles():
		for d: Vector2i in GenUtil.DIRS4:
			var p := door + d
			if not room.rect.has_point(p) or seen.has(p) or solid.has(p):
				continue
			if data.is_walkable(p.x, p.y):
				seen[p] = true
				queue.append(p)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for d: Vector2i in GenUtil.DIRS4:
			var n := cur + d
			if seen.has(n) or solid.has(n) or not room.rect.has_point(n):
				continue
			if not data.is_walkable(n.x, n.y):
				continue
			seen[n] = true
			queue.append(n)
	return seen


## Room ids that are walkably connected, derived from the carved corridor/door components.
func _walkable_adjacency(data: FloorData) -> Array[Dictionary]:
	var owner: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		for key: int in room.doors.keys():
			var door: Vector2i = room.doors[key]
			var ids: Array[int] = []
			if owner.has(door):
				ids = owner[door]
			if not (room.id in ids):
				ids.append(room.id)
			owner[door] = ids
	var adjacency: Array[Dictionary] = []
	for _room: FloorData.Room in data.rooms:
		adjacency.append({})
	var seen: Dictionary = {}
	for y in range(data.height):
		for x in range(data.width):
			var origin := Vector2i(x, y)
			if seen.has(origin) or not _is_link(data, origin):
				continue
			var members: Array[int] = []
			var queue: Array[Vector2i] = [origin]
			seen[origin] = true
			var head := 0
			while head < queue.size():
				var cur := queue[head]
				head += 1
				if owner.has(cur):
					for id: int in owner[cur] as Array[int]:
						if not (id in members):
							members.append(id)
				for d: Vector2i in GenUtil.DIRS4:
					var n := cur + d
					if seen.has(n) or not _is_link(data, n):
						continue
					seen[n] = true
					queue.append(n)
			for i in range(members.size()):
				for j in range(i + 1, members.size()):
					adjacency[members[i]][members[j]] = true
					adjacency[members[j]][members[i]] = true
	return adjacency


func _is_link(data: FloorData, p: Vector2i) -> bool:
	var t := data.get_tile(p.x, p.y)
	return t == FloorData.Tile.DOOR or t == FloorData.Tile.CORRIDOR


func _room_distances(data: FloorData, adjacency: Array[Dictionary]) -> Array[int]:
	var dist: Array[int] = []
	dist.resize(data.rooms.size())
	dist.fill(-1)
	dist[data.start_room] = 0
	var queue: Array[int] = [data.start_room]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for nb: int in adjacency[cur].keys():
			if dist[nb] < 0:
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	return dist


func test_every_special_room_type_shows_up_on_early_floors() -> void:
	# The crypt act (floors 0-2) used to contain no elite, gauntlet or treasure room at all.
	# The per-floor budget (docs 5.1 #4) keeps the very first floor free of elites and
	# gauntlets on purpose, so floor 0 is checked for the treasure room alone.
	for floor_index in range(3):
		var seen: Dictionary = {}
		for seed_value in range(60):
			var data := _generate("gruvbox", seed_value * 13 + floor_index, floor_index)
			for room: FloorData.Room in data.rooms:
				if room.type in SPECIAL_TYPES:
					seen[room.type] = true
		for type: int in SPECIAL_TYPES:
			if RoomBudget.max_count(floor_index, type as FloorData.RoomType) == 0:
				assert_bool(seen.has(type)).is_false()
				continue
			(
				assert_bool(seen.has(type))
				. override_failure_message(
					"room type %d never generated on floor %d" % [type, floor_index]
				)
				. is_true()
			)


func test_enemy_spawns_are_reachable_with_props_solid() -> void:
	var sealed: Array[String] = []
	for theme: String in GenParamsTest.THEMES:
		for seed_value in range(50):
			var floor_index := seed_value % 9
			var data := _generate(theme, seed_value * 7919 + 3, floor_index)
			for room: FloorData.Room in data.rooms:
				if room.enemy_spawns.is_empty():
					continue
				var reachable := _reachable(data, room)
				for p: Vector2i in room.enemy_spawns:
					if not reachable.has(p):
						sealed.append(
							"%s seed %d room %d spawn %s" % [theme, seed_value, room.id, p]
						)
	assert_array(sealed).override_failure_message("\n".join(sealed)).is_empty()


func test_walkable_topology_matches_the_room_graph() -> void:
	var problems: Array[String] = []
	for theme: String in GenParamsTest.THEMES:
		for seed_value in range(40):
			var floor_index := seed_value % 9
			var data := _generate(theme, seed_value * 31 + 5, floor_index)
			var adjacency := _walkable_adjacency(data)
			for room: FloorData.Room in data.rooms:
				for nb: int in adjacency[room.id].keys():
					if not (nb in room.neighbors):
						problems.append(
							(
								"%s seed %d: rooms %d-%d walkable but not neighbours"
								% [theme, seed_value, room.id, nb]
							)
						)
				for nb: int in room.neighbors:
					if not adjacency[room.id].has(nb):
						problems.append(
							(
								"%s seed %d: rooms %d-%d neighbours but not walkable"
								% [theme, seed_value, room.id, nb]
							)
						)
			var dist := _room_distances(data, adjacency)
			if dist[data.stairs_room] < FloorGraph.MIN_STAIRS_DISTANCE:
				problems.append(
					(
						"%s seed %d floor %d: stairs only %d rooms of walking away"
						% [theme, seed_value, floor_index, dist[data.stairs_room]]
					)
				)
			for i in range(dist.size()):
				if dist[i] < 0:
					problems.append("%s seed %d: room %d unreachable" % [theme, seed_value, i])
	assert_array(problems).override_failure_message("\n".join(problems.slice(0, 10))).is_empty()


func test_mask_template_stamps_walls_pits_and_props() -> void:
	var data := FloorData.new()
	data.width = 21
	data.height = 17
	data.tiles.resize(data.width * data.height)
	data.tiles.fill(FloorData.Tile.VOID)
	var room := FloorData.Room.new()
	room.id = 0
	room.type = FloorData.RoomType.COMBAT
	room.rect = Rect2i(3, 3, 13, 9)
	data.rooms.append(room)
	for p: Vector2i in GenUtil.rect_tiles(room.rect.grow(1)):
		data.set_tile(p.x, p.y, FloorData.Tile.WALL)
	for p: Vector2i in GenUtil.rect_tiles(room.rect):
		data.set_tile(p.x, p.y, FloorData.Tile.FLOOR)

	var template := RoomTemplate.new()
	template.id = &"mask_fixture"
	template.pattern = &"mask"
	template.min_size = Vector2i(5, 5)
	template.mask = "#####\n#~~~#\n#~o~#\n#~~~#\n#####"
	var biome := Biome.new()
	biome.id = &"crypt"
	biome.prop_kinds = []
	biome.trap_kinds = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var templates: Array[RoomTemplate] = [template]
	RoomFiller.fill_room(data, room, biome, GenParams.new(), rng, templates)

	assert_str(String(room.fill_template)).is_equal("mask_fixture")
	var walls := 0
	var pits := 0
	for p: Vector2i in GenUtil.rect_tiles(room.rect):
		if data.get_tile(p.x, p.y) == FloorData.Tile.WALL:
			walls += 1
		elif data.get_tile(p.x, p.y) == FloorData.Tile.PIT:
			pits += 1
	assert_int(walls).is_equal(16)
	assert_int(pits).is_equal(8)
	assert_array(room.prop_positions).contains([room.center()])
	assert_int(room.prop_kinds.size()).is_equal(room.prop_positions.size())


func test_shipped_mask_template_is_used_by_the_pipeline() -> void:
	var used := false
	for seed_value in range(60):
		var data := _generate("nord", seed_value, 4)
		for room: FloorData.Room in data.rooms:
			if room.fill_template == &"vault":
				used = true
	assert_bool(used).is_true()


func test_generate_falls_back_to_a_playable_floor() -> void:
	# No layout can ever hold 400 rooms, so every attempt fails and the fallback must kick in.
	var params := GenParams.from_profile(GenParamsTest.profile_for("gruvbox"), 3)
	params.room_count = 400
	var data := FloorGenerator.generate(params, RunRng.new(5).floor_stream(&"gen", 3))
	assert_bool(data.is_fallback).is_true()
	assert_int(data.rooms.size()).is_greater_equal(2)
	assert_int(data.width).is_between(1, FloorLayout.MAX_WIDTH)
	assert_int(data.height).is_between(1, FloorLayout.MAX_HEIGHT)
	assert_int(data.rooms[data.start_room].type).is_equal(FloorData.RoomType.START)
	assert_int(data.rooms[data.stairs_room].type).is_equal(FloorData.RoomType.STAIRS)
	var adjacency := _walkable_adjacency(data)
	assert_int(_room_distances(data, adjacency)[data.stairs_room]).is_greater_equal(1)


func test_boss_fallback_floor_has_a_boss_arena() -> void:
	var params := GenParams.from_profile(GenParamsTest.profile_for("nord"), 5)
	var data := FloorGenerator.fallback_floor(params)
	assert_bool(data.is_fallback).is_true()
	assert_int(data.boss_room).is_equal(data.stairs_room)
	assert_int(data.rooms[data.boss_room].type).is_equal(FloorData.RoomType.BOSS)
	assert_int(data.rooms[data.boss_room].enemy_spawns.size()).is_equal(1)


func test_normal_floors_are_never_flagged_as_fallback() -> void:
	for seed_value in range(20):
		assert_bool(_generate("catppuccin", seed_value, seed_value % 9).is_fallback).is_false()


## A wall trap has to face open floor, and it has to still face open floor when the floor is
## finished: `_wall_trap_slots` checks the muzzle once, before the same pass has rolled its
## pits, so a trap placed early could end up aimed into a hole opened later. This is the case
## that caught it - the front tile came back PIT instead of FLOOR.
func test_wall_traps_carry_an_inward_facing() -> void:
	var checked := 0
	for seed_value in range(60):
		var data := _generate("tokyo-night", seed_value, seed_value % 9)
		for room: FloorData.Room in data.rooms:
			for trap: Dictionary in room.trap_positions:
				var pos: Vector2i = trap["pos"]
				var dir: Vector2i = trap["dir"]
				if room.rect.has_point(pos):
					assert_bool(dir == Vector2i.ZERO).is_true()
					continue
				checked += 1
				assert_bool(dir == room.trap_facing(pos)).is_true()
				assert_bool(dir != Vector2i.ZERO).is_true()
				var front := pos + dir
				assert_int(data.get_tile(front.x, front.y)).is_equal(FloorData.Tile.FLOOR)
	assert_int(checked).is_greater(0)


func test_biome_prop_kinds_match_the_prop_atlas() -> void:
	for id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(id)
		var known: Array = Prop.KINDS[id]
		for kind: StringName in biome.prop_kinds:
			(
				assert_bool(kind in known)
				. override_failure_message("%s: prop kind %s not in Prop.KINDS" % [id, kind])
				. is_true()
			)


func test_biome_exposes_the_atlas_path_alias_the_rooms_module_reads() -> void:
	for id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(id)
		var alias: Variant = biome.get("atlas_path")
		assert_bool(alias is String).is_true()
		assert_str(alias as String).is_equal(biome.tileset_path)


## A dungeon has to look like a place worth being in. Prop density is derived from the theme's
## saturation (docs §3.3) and then multiplied by the music and subtracted from by the
## wallpaper, so a greyscale theme stacked down to 0.105 and its combat rooms came out as empty
## tiled halls with a coffin in them - and the per-room cap of eight gave a 30x25 hall the same
## furniture as a closet. The floor and the area-scaled cap are both measured here, on the
## theme that hits the bottom of every lever at once.
func test_a_greyscale_theme_still_gets_a_furnished_combat_room() -> void:
	# Sampled over 20 seeds, not 6. Which room types a floor gets and which sizes they roll are
	# both layout rolls, so six seeds handed this measurement three or four large combat rooms
	# depending on where the room-size lever happened to sit - the "enough rooms to measure"
	# guard then failed for a reason that had nothing to do with how furnished a room is.
	var rooms := 0
	var props := 0
	for offset in range(20):
		var data := _generate("white", 7000 + offset, 1)
		for room: FloorData.Room in data.rooms:
			if room.type != FloorData.RoomType.COMBAT or room.rect.get_area() < 200:
				continue
			rooms += 1
			props += room.prop_positions.size()
	assert_int(rooms).override_failure_message("no large combat room to measure").is_greater(8)
	(
		assert_float(float(props) / float(maxi(1, rooms)))
		. override_failure_message(
			"the white theme averages %.1f props in a large combat room" % (float(props) / rooms)
		)
		. is_greater(4.0)
	)


## The guard for what the cap is *for*: a small room may not be furnished into a maze, and no
## room of any size may end up with its doors blocked off by its own furniture.
func test_the_prop_cap_still_protects_a_small_room() -> void:
	assert_int(RoomFiller.prop_cap(40)).is_equal(RoomFiller.MAX_PROPS)
	assert_int(RoomFiller.prop_cap(150)).is_equal(RoomFiller.MAX_PROPS)
	assert_int(RoomFiller.prop_cap(100000)).is_equal(RoomFiller.MAX_PROPS_LARGE)
	for offset in range(4):
		var data := _generate("gruvbox", 4100 + offset, 4)
		for room: FloorData.Room in data.rooms:
			(
				assert_int(room.prop_positions.size())
				. override_failure_message(
					"a %s room holds %d props" % [room.rect, room.prop_positions.size()]
				)
				. is_less_equal(RoomFiller.prop_cap(room.rect.get_area()))
			)
			assert_int(_reachable(data, room).size()).is_greater(0)
