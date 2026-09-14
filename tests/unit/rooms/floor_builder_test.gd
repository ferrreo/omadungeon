class_name FloorBuilderTest
extends GdUnitTestSuite

var _data: FloorData
var _parent: Node2D
var _result: FloorBuilder.Result


func before_test() -> void:
	_data = RoomsTestFixtures.three_rooms()
	_parent = auto_free(Node2D.new())
	add_child(_parent)
	var atlas := FloorBuilder.load_atlas(RoomsTestFixtures.ATLAS)
	_result = FloorBuilder.new().build(_data, atlas, _parent, ThemePalette.fallback())


func _used(layer: TileMapLayer) -> int:
	return layer.get_used_cells().size()


func test_tile_counts_match_data() -> void:
	var walkable: Array[FloorData.Tile] = [
		FloorData.Tile.FLOOR, FloorData.Tile.CORRIDOR, FloorData.Tile.DOOR
	]
	var expected_ground := RoomsTestFixtures.count_tiles(_data, walkable)
	var expected_walls := RoomsTestFixtures.count_tiles(_data, [FloorData.Tile.WALL])
	assert_int(_result.ground_count).is_equal(expected_ground)
	assert_int(_result.wall_count).is_equal(expected_walls)
	assert_int(_result.pit_count).is_equal(2)
	# Room 1 has a variant, so its tiles live on a separate layer pair.
	assert_bool(_result.room_layers.has(1)).is_true()
	var pair: Dictionary = _result.room_layers[1]
	var ground_total := _used(_result.ground) + _used(pair["ground"])
	var wall_total := _used(_result.walls) + _used(pair["walls"])
	assert_int(ground_total).is_equal(expected_ground)
	assert_int(wall_total).is_equal(expected_walls)
	# The pits sit in the variant room, so they live on that room's own pits layer.
	assert_int(_used(_result.pits)).is_equal(0)
	assert_int(_used(pair["pits"])).is_equal(2)
	# Room 1 interior (5x4 minus the 2 pits) is entirely on its own ground layer.
	assert_int(_used(pair["ground"])).is_equal(5 * 4 - 2 + 2)  # + 2 door tiles on its ring


func test_layer_names_and_physics() -> void:
	assert_object(_parent.get_node_or_null("Ground")).is_not_null()
	assert_object(_parent.get_node_or_null("Walls")).is_not_null()
	assert_object(_parent.get_node_or_null("Pits")).is_not_null()
	assert_object(_parent.get_node_or_null("Ground_r1")).is_not_null()
	assert_object(_parent.get_node_or_null("Walls_r1")).is_not_null()
	assert_object(_parent.get_node_or_null("Pits_r1")).is_not_null()
	assert_bool(_result.walls.collision_enabled).is_true()
	assert_bool(_result.ground.collision_enabled).is_false()
	assert_int(_result.tileset.get_physics_layers_count()).is_equal(1)
	assert_int(_result.tileset.get_physics_layer_collision_layer(0)).is_equal(Layers.WORLD)
	var source := _result.tileset.get_source(FloorBuilder.SOURCE_ID) as TileSetAtlasSource
	var wall_td := source.get_tile_data(Vector2i(6, FloorBuilder.ROW_WALL), 0)
	assert_int(wall_td.get_collision_polygons_count(0)).is_equal(1)
	var floor_td := source.get_tile_data(Vector2i(0, FloorBuilder.ROW_FLOOR), 0)
	assert_int(floor_td.get_collision_polygons_count(0)).is_equal(0)


func test_autotile_masks() -> void:
	# Room 0 ring: top-left corner sees walls E and S.
	assert_int(FloorBuilder.wall_mask(_data, 1, 1)).is_equal(
		FloorBuilder.MASK_E | FloorBuilder.MASK_S
	)
	# Top edge sees E and W.
	assert_int(FloorBuilder.wall_mask(_data, 3, 1)).is_equal(
		FloorBuilder.MASK_E | FloorBuilder.MASK_W
	)
	# Wall above the east door: N wall, S door (counts as wall), E corridor wall, W floor.
	assert_int(FloorBuilder.wall_mask(_data, 7, 2)).is_equal(
		FloorBuilder.MASK_N | FloorBuilder.MASK_S | FloorBuilder.MASK_E
	)
	# Bottom-right corner sees N and W.
	assert_int(FloorBuilder.wall_mask(_data, 7, 6)).is_equal(
		FloorBuilder.MASK_N | FloorBuilder.MASK_W
	)
	# Placed atlas coords use the mask as the column in the wall row.
	var coords := _result.walls.get_cell_atlas_coords(Vector2i(3, 1))
	assert_that(coords).is_equal(
		Vector2i(FloorBuilder.MASK_E | FloorBuilder.MASK_W, FloorBuilder.ROW_WALL)
	)
	assert_int(int(_result.wall_masks[Vector2i(1, 1)])).is_equal(6)
	# Pits: the two pit tiles see each other horizontally.
	assert_int(FloorBuilder.pit_mask(_data, 15, 5)).is_equal(FloorBuilder.MASK_E)
	assert_int(FloorBuilder.pit_mask(_data, 16, 5)).is_equal(FloorBuilder.MASK_W)
	var pit_layer: TileMapLayer = (_result.room_layers[1] as Dictionary)["pits"]
	assert_that(pit_layer.get_cell_atlas_coords(Vector2i(15, 5))).is_equal(
		Vector2i(FloorBuilder.MASK_E, FloorBuilder.ROW_PIT)
	)
	assert_object(pit_layer.material).is_same(
		(_result.room_layers[1] as Dictionary)["ground"].material
	)


func test_floor_variants_are_deterministic_and_in_range() -> void:
	var a := FloorBuilder.floor_coords(4242, 3, 3, true)
	var b := FloorBuilder.floor_coords(4242, 3, 3, true)
	assert_that(a).is_equal(b)
	var decorated := 0
	for y in range(40):
		for x in range(40):
			var c := FloorBuilder.floor_coords(4242, x, y, true)
			assert_int(c.y).is_equal(FloorBuilder.ROW_FLOOR)
			assert_bool(c.x >= 0 and c.x < 8).is_true()
			if c.x >= 4:
				decorated += 1
			var plain := FloorBuilder.floor_coords(4242, x, y, false)
			assert_bool(plain.x < 4).is_true()
	assert_int(decorated).is_between(80, 320)


func test_pit_areas() -> void:
	assert_int(_result.pit_areas.size()).is_equal(1)
	var pit := _result.pit_areas[0]
	assert_int(pit.tiles.size()).is_equal(2)
	assert_int(pit.room_id).is_equal(1)
	assert_int(pit.collision_layer).is_equal(Layers.PIT)
	assert_int(pit.get_child_count()).is_equal(2)


func test_materials_and_retint() -> void:
	assert_int(_result.materials.size()).is_equal(2)
	assert_object(_result.ground.material).is_same(_result.walls.material)
	var mat := _result.ground.material as ShaderMaterial
	assert_object(mat).is_not_null()
	_result.retint(ThemePalette.fallback(), _parent)
	assert_float(float(mat.get_shader_parameter(&"blend"))).is_equal(0.0)


func test_placeholder_atlas_when_missing() -> void:
	var tex := FloorBuilder.load_atlas("res://assets/tiles/does_not_exist.png")
	assert_object(tex).is_not_null()
	assert_int(int(tex.get_width())).is_equal(256)
	assert_int(int(tex.get_height())).is_equal(80)
