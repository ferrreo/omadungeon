## Death is permanent (docs section 1). Two ways a run used to survive its own death: the
## save outliving the death delay, and a stat thief taking a stolen point to the grave when a
## floor is torn down. Both are regression-guarded here.
class_name PermadeathTest
extends GdUnitTestSuite

const DAMAGE_TAGS: Array[StringName] = [DamageInfo.TAG_TRUE]
## Frames to wait for the death animation before giving up on the run ending.
const DEATH_FRAMES := 400


## Spins frames until the run reports itself over. Returns false if it never does.
func _await_run_over() -> bool:
	for _i in range(DEATH_FRAMES):
		if not RunManager.is_run_active():
			return true
		await get_tree().process_frame
	return false


## A real gremlin from the registry: a bare ConfigGremlin.new() has no navigation child.
func _gremlin() -> ConfigGremlin:
	var def := RunManager.enemy_registry.find(&"config_gremlin")
	return def.scene.instantiate() as ConfigGremlin


func before_test() -> void:
	SaveManager.cancel_autosave()
	SaveManager.delete_run()


func after_test() -> void:
	SaveManager.cancel_autosave()
	SaveManager.delete_run()


func test_the_save_is_gone_before_the_death_delay_elapses() -> void:
	RunManager.new_run(4242, &"fighter")
	await get_tree().process_frame
	SaveManager.flush_autosave()
	(
		assert_bool(SaveManager.has_run())
		. override_failure_message("a live run should have a save")
		. is_true()
	)

	var player: Player = RunManager.game.player
	player.health.take_damage(DamageInfo.create(99999.0, DAMAGE_TAGS, null, Layers.Team.ENEMY))
	# The death animation plays before player_died fires; wait for the run to end, then assert
	# the save is already gone rather than surviving the delay before the summary.
	assert_bool(await _await_run_over()).is_true()
	(
		assert_bool(SaveManager.has_run())
		. override_failure_message(
			"closing the window inside the death delay would resurrect the run"
		)
		. is_false()
	)


func test_a_pending_autosave_cannot_rewrite_the_save_after_death() -> void:
	RunManager.new_run(99, &"fighter")
	await get_tree().process_frame
	var player: Player = RunManager.game.player
	SaveManager.request_autosave()
	player.health.take_damage(DamageInfo.create(99999.0, DAMAGE_TAGS, null, Layers.Team.ENEMY))
	assert_bool(await _await_run_over()).is_true()
	SaveManager.flush_autosave()
	assert_bool(SaveManager.has_run()).is_false()


func test_a_thief_repays_the_stolen_point_when_the_floor_is_torn_down() -> void:
	var paid: Array[StringName] = []
	var probe := func(kind: StringName, _pos: Vector2, _amount: int) -> void: paid.append(kind)
	EventBus.spawn_pickup.connect(probe)

	var gremlin := _gremlin()
	add_child(gremlin)
	gremlin.stolen_stat = &"might"
	await get_tree().process_frame
	gremlin.get_parent().remove_child(gremlin)
	gremlin.free()
	await get_tree().process_frame

	EventBus.spawn_pickup.disconnect(probe)
	(
		assert_array(paid)
		. override_failure_message("a despawned thief must pay the point back, not strand it")
		. contains([&"stat_orb"])
	)


func test_a_thief_that_stole_nothing_pays_nothing() -> void:
	var paid: Array[StringName] = []
	var probe := func(kind: StringName, _pos: Vector2, _amount: int) -> void: paid.append(kind)
	EventBus.spawn_pickup.connect(probe)

	var gremlin := _gremlin()
	add_child(gremlin)
	await get_tree().process_frame
	gremlin.get_parent().remove_child(gremlin)
	gremlin.free()
	await get_tree().process_frame

	EventBus.spawn_pickup.disconnect(probe)
	assert_array(paid).is_empty()


func test_the_debt_is_paid_once_not_twice() -> void:
	var paid: Array[StringName] = []
	var probe := func(kind: StringName, _pos: Vector2, _amount: int) -> void: paid.append(kind)
	EventBus.spawn_pickup.connect(probe)

	var gremlin := _gremlin()
	add_child(gremlin)
	gremlin.stolen_stat = &"fortune"
	await get_tree().process_frame
	gremlin._on_death(null)
	gremlin.get_parent().remove_child(gremlin)
	gremlin.free()
	await get_tree().process_frame

	EventBus.spawn_pickup.disconnect(probe)
	(
		assert_int(paid.size())
		. override_failure_message("the point must be repaid exactly once")
		. is_equal(1)
	)
