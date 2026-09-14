class_name EnemyInstantiateTest
extends GdUnitTestSuite

## Every EventBus handler this suite connects goes through the probe, which hands them all back
## in after_test: an autoload signal outlives the suite, so a leaked lambda silently changes
## the result of whatever runs next (see tests/unit/tools/test_isolation_test.gd).
var _probe := EventBusProbe.new()


func after_test() -> void:
	_probe.release()


func test_every_def_instantiates_with_scaled_hp() -> void:
	var registry := EnemyTestHelpers.registry()
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var spawned: Array[Node2D] = []
	_probe.watch(EventBus.enemy_spawned, func(e: Node2D) -> void: spawned.append(e))
	for def: EnemyDef in registry.regular_defs():
		var enemy := EnemySpawner.instantiate(def, 2, Vector2(40, 40), EnemyTestHelpers.seeded(1))
		root.add_child(enemy)
		(
			assert_object(enemy)
			. override_failure_message("%s is not an EnemyBase" % def.id)
			. is_not_null()
		)
		assert_float(enemy.health.max_hp).override_failure_message(def.id).is_equal_approx(
			def.scaled_hp(2), 0.01
		)
		assert_float(enemy.health.hp).is_equal_approx(def.scaled_hp(2), 0.01)
		assert_float(enemy.stats.get_value(&"move_speed")).is_equal_approx(def.move_speed, 0.01)
		assert_bool(enemy.is_in_group(&"enemy")).is_true()
		assert_that(enemy.team).is_equal(Layers.Team.ENEMY)
		assert_int(enemy.hurtbox.collision_layer).is_equal(Layers.ENEMY_HURTBOX)
		assert_bool(enemy.hp_bar.visible).is_equal(def.is_elite)
		assert_bool(enemy.sprite.sprite_frames.has_animation(&"death")).is_true()
		assert_int(enemy.sprite.sprite_frames.get_frame_count(&"idle")).is_equal(4)
	for _i in range(3):
		await get_tree().physics_frame
	_probe.release()
	assert_int(spawned.size()).is_equal(registry.regular_defs().size())
	for enemy: Node2D in spawned:
		assert_that((enemy as EnemyBase).state).is_equal(EnemyBase.State.IDLE)


func test_setup_after_ready_rescales() -> void:
	var def := EnemyTestHelpers.def(&"juggler")
	var enemy := auto_free(def.scene.instantiate()) as EnemyBase
	add_child(enemy)
	enemy.setup(def, 5)
	assert_float(enemy.health.max_hp).is_equal_approx(def.scaled_hp(5), 0.01)
	assert_float(enemy.health.hp).is_equal_approx(def.scaled_hp(5), 0.01)
	assert_float(enemy.base_damage()).is_equal_approx(def.scaled_damage(5), 0.01)
