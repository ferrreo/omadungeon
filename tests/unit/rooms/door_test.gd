class_name DoorTest
extends GdUnitTestSuite


func test_open_close_toggles_world_collision() -> void:
	var door: Door = auto_free(Door.new())
	var atlas := FloorBuilder.load_atlas(RoomsTestFixtures.ATLAS)
	door.setup(atlas, null, true)
	add_child(door)
	assert_bool(door.is_open).is_true()
	assert_int(door.collision_layer).is_equal(0)
	var events: Array[String] = []
	door.closed.connect(func() -> void: events.append("closed"))
	door.opened.connect(func() -> void: events.append("opened"))
	door.close()
	assert_bool(door.is_open).is_false()
	assert_int(door.collision_layer).is_equal(Layers.WORLD)
	assert_that(door.sprite.region_rect).is_equal(
		FloorBuilder.atlas_cell(FloorBuilder.SPECIAL_DOOR_CLOSED, FloorBuilder.ROW_SPECIAL)
	)
	door.close()  # idempotent
	door.open()
	assert_bool(door.is_open).is_true()
	assert_int(door.collision_layer).is_equal(0)
	assert_that(door.sprite.region_rect).is_equal(
		FloorBuilder.atlas_cell(FloorBuilder.SPECIAL_DOOR_OPEN, FloorBuilder.ROW_SPECIAL)
	)
	assert_array(events).contains_exactly(["closed", "opened"])


func test_vertical_door_is_rotated() -> void:
	var door: Door = auto_free(Door.new())
	door.setup(FloorBuilder.load_atlas(RoomsTestFixtures.ATLAS), null, false)
	add_child(door)
	assert_float(door.sprite.rotation).is_equal_approx(PI / 2.0, 0.001)


func test_closed_door_blocks_player_body() -> void:
	var door: Door = auto_free(Door.new())
	door.setup(FloorBuilder.load_atlas(RoomsTestFixtures.ATLAS), null, true)
	door.position = Vector2(100, 100)
	add_child(door)
	door.close(false)
	var player: CharacterBody2D = auto_free(RoomsTestFixtures.make_player())
	player.position = Vector2(60, 100)
	add_child(player)
	await get_tree().physics_frame
	for _i in range(20):
		player.velocity = Vector2(300, 0)
		player.move_and_slide()
		await get_tree().physics_frame
	assert_float(player.position.x).is_less(100.0)
	door.open(false)
	for _i in range(20):
		player.velocity = Vector2(300, 0)
		player.move_and_slide()
		await get_tree().physics_frame
	assert_float(player.position.x).is_greater(110.0)
