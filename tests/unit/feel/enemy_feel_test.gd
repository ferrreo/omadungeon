class_name EnemyFeelTest
extends GdUnitTestSuite

var _feel: GameFeel
var _root: Node2D


func before_test() -> void:
	_feel = FeelTestHelpers.fresh(get_tree())
	_feel.hit_stop_enabled = false
	_root = auto_free(Node2D.new()) as Node2D
	add_child(_root)


func after_test() -> void:
	_feel.enabled = true
	_feel.hit_stop_enabled = true
	_feel.reset()
	GameState.settings["reduced_flash"] = false
	Engine.time_scale = 1.0


func _honker() -> EnemyBase:
	return EnemyTestHelpers.spawn(&"honker", _root, Vector2(100, 100))


func test_an_enemy_freezes_its_own_frames_for_the_profile_beat() -> void:
	var enemy := _honker()
	await get_tree().physics_frame
	assert_int(enemy.hit_freeze_frames(1.0)).is_equal(_feel.profile.hit_stop_light_frames)
	assert_int(enemy.hit_freeze_frames(_feel.profile.heavy_damage + 1.0)).is_equal(
		_feel.profile.hit_stop_heavy_frames
	)
	assert_int(enemy.hit_freeze_frames(1.0)).is_between(2, 4)


func test_being_hit_freezes_flashes_and_squashes_the_sprite() -> void:
	var enemy := _honker()
	await get_tree().physics_frame
	EnemyTestHelpers.hit(enemy, 6.0)
	assert_float(enemy.sprite.speed_scale).is_equal(0.0)
	assert_float(enemy.sprite.self_modulate.r).is_greater(1.0)
	assert_float(enemy.sprite.scale.x).is_greater(1.0)
	assert_float(enemy.sprite.scale.y).is_less(1.0)
	await FeelTestHelpers.physics_frames(get_tree(), 6)
	assert_float(enemy.sprite.speed_scale).is_equal(1.0)


func test_reduced_flash_dims_the_hit_flash_on_enemies_too() -> void:
	var enemy := _honker()
	await get_tree().physics_frame
	EnemyTestHelpers.hit(enemy, 6.0)
	var bright := enemy.sprite.self_modulate.r
	enemy.sprite.self_modulate = Color.WHITE
	GameState.settings["reduced_flash"] = true
	EnemyTestHelpers.hit(enemy, 6.0)
	var dim := enemy.sprite.self_modulate.r
	GameState.settings["reduced_flash"] = false
	assert_float(dim).is_less(bright)
	assert_float(dim).is_greater_equal(1.0)


func test_a_heavy_blow_squashes_harder_than_a_chip() -> void:
	var enemy := _honker()
	await get_tree().physics_frame
	EnemyTestHelpers.hit(enemy, 1.0)
	var light := enemy.sprite.scale.x
	await FeelTestHelpers.physics_frames(get_tree(), 20)
	EnemyTestHelpers.hit(enemy, _feel.profile.heavy_damage + 5.0)
	assert_float(enemy.sprite.scale.x).is_greater(light)


func test_the_death_burst_is_bigger_for_a_bigger_sprite() -> void:
	var small := _honker()
	await get_tree().physics_frame
	assert_int(small.death_burst_count()).is_equal(_feel.profile.death_burst_count)
	small.def = small.def.duplicate() as EnemyDef
	small.def.sprite_size = 32
	assert_int(small.death_burst_count()).is_greater(_feel.profile.death_burst_count)


func test_a_death_pops_a_pooled_burst_without_allocating_a_new_one() -> void:
	var pool := FxPool.instance(get_tree())
	pool.clear()
	pool.prewarm(pool.allocations() + 4)
	var before := pool.allocations()
	var enemy := _honker()
	await get_tree().physics_frame
	enemy.health.take_damage(
		DamageInfo.create(9999.0, [DamageInfo.TAG_TRUE], null, Layers.Team.PLAYER)
	)
	await get_tree().physics_frame
	assert_bool(enemy.death_burst.emitting).is_true()
	assert_int(pool.active_count()).is_greater(0)
	assert_int(pool.allocations()).is_equal(before)
	pool.clear()


func test_the_windup_tint_tracks_the_shared_tell_colour() -> void:
	var enemy := _honker()
	await get_tree().physics_frame
	enemy.set_physics_process(false)
	enemy.telegraph.flash(0.5, enemy.telegraph_radius())
	enemy.state = EnemyBase.State.WINDUP
	enemy.state_time = 0.4
	enemy._update_animation()
	var danger := DangerTell.color()
	# The body is pulled toward the danger colour, never past it.
	assert_float(enemy.sprite.modulate.r).is_between(minf(1.0, danger.r), maxf(1.0, danger.r))
	assert_bool(enemy.sprite.modulate.is_equal_approx(Color.WHITE)).is_false()
