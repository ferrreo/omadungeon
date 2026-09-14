class_name PlayerDecoyTest
extends GdUnitTestSuite


func test_decoy_taunts_enemies_in_radius_and_expires() -> void:
	var near := auto_free(PlayerTestHelpers.make_dummy(Vector2(30, 0))) as Entity
	var far := auto_free(PlayerTestHelpers.make_dummy(Vector2(200, 0))) as Entity
	add_child(near)
	add_child(far)
	await PlayerTestHelpers.physics_frames(get_tree(), 2)
	var decoy := auto_free(Decoy.new()) as Decoy
	add_child(decoy)
	await PlayerTestHelpers.physics_frames(get_tree(), 3)
	assert_bool(near.status.is_taunted()).is_true()
	assert_object(near.status.taunt_source()).is_same(decoy)
	assert_bool(far.status.is_taunted()).is_false()
	assert_int(decoy.taunted.size()).is_equal(1)
	assert_int(decoy.hurtbox.collision_layer).is_equal(Layers.PLAYER_HURTBOX)
	assert_float(decoy.time_left()).is_less(Decoy.LIFETIME)


func test_decoy_dies_to_one_hit() -> void:
	var decoy := auto_free(Decoy.new()) as Decoy
	add_child(decoy)
	await get_tree().physics_frame
	var expired := [false]
	decoy.expired.connect(func() -> void: expired[0] = true)
	decoy.hurtbox.receive(PlayerTestHelpers.enemy_hit(5.0))
	assert_bool(decoy.health.is_dead()).is_true()
	assert_bool(expired[0]).is_true()


func test_enemies_arriving_later_are_taunted_too() -> void:
	var decoy := auto_free(Decoy.new()) as Decoy
	add_child(decoy)
	decoy.global_position = Vector2.ZERO
	await PlayerTestHelpers.physics_frames(get_tree(), 2)
	assert_int(decoy.taunted.size()).is_equal(0)
	var late := auto_free(PlayerTestHelpers.make_dummy(Vector2(20, 0))) as Entity
	add_child(late)
	# The decoy rescans on an interval, so an enemy that walks in later is taunted as well.
	await get_tree().create_timer(Decoy.SCAN_INTERVAL * 1.5).timeout
	assert_int(decoy.taunted.size()).is_equal(1)
	assert_bool(late.status.is_taunted()).is_true()
