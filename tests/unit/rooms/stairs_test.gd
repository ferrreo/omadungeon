class_name StairsTest
extends GdUnitTestSuite

var _exits: int = 0
var _cb: Callable


func before_test() -> void:
	_exits = 0
	_cb = func() -> void: _exits += 1
	EventBus.floor_exit_requested.connect(_cb)


func after_test() -> void:
	EventBus.floor_exit_requested.disconnect(_cb)


func _make(locked: bool) -> Stairs:
	var s: Stairs = auto_free(Stairs.new())
	s.setup(FloorBuilder.load_atlas(RoomsTestFixtures.ATLAS), null, locked)
	add_child(s)
	return s


func test_unlocked_stairs_request_exit() -> void:
	var s := _make(false)
	assert_bool(s.interact()).is_true()
	assert_int(_exits).is_equal(1)


func test_locked_until_boss_dies() -> void:
	var s := _make(true)
	assert_bool(s.interact()).is_false()
	assert_int(_exits).is_equal(0)
	assert_that(s.sprite.region_rect).is_equal(
		FloorBuilder.atlas_cell(FloorBuilder.SPECIAL_STAIRS_LOCKED, FloorBuilder.ROW_SPECIAL)
	)
	var grunt: Entity = auto_free(Entity.new())
	add_child(grunt)
	EventBus.enemy_died.emit(grunt, null)
	assert_bool(s.locked).is_true()
	var boss: Node2D = auto_free(Node2D.new())
	boss.set_meta(&"unused", true)
	var boss_script := GDScript.new()
	boss_script.source_code = "extends Node2D\nvar is_boss: bool = true\n"
	boss_script.reload()
	boss.set_script(boss_script)
	add_child(boss)
	EventBus.enemy_died.emit(boss, null)
	assert_bool(s.locked).is_false()
	assert_that(s.sprite.region_rect).is_equal(
		FloorBuilder.atlas_cell(FloorBuilder.SPECIAL_STAIRS, FloorBuilder.ROW_SPECIAL)
	)
	assert_bool(s.interact()).is_true()
	assert_int(_exits).is_equal(1)


func test_boss_detection_via_enemy_def() -> void:
	var def := EnemyDef.new()
	def.is_boss = true
	var holder: Node2D = auto_free(Node2D.new())
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar def: EnemyDef\n"
	script.reload()
	holder.set_script(script)
	holder.set("def", def)
	assert_bool(Stairs.is_boss_enemy(holder)).is_true()
	assert_bool(Stairs.is_boss_enemy(null)).is_false()


## Regression: `floor_exit_requested` builds the next floor synchronously inside the emission,
## while the old Stairs is only queue_freed and stays connected for the rest of the frame.
## Two interactions in one frame used to descend two floors and skip one floor's rewards.
func test_a_second_interact_in_the_same_frame_cannot_skip_a_floor() -> void:
	var s := _make(false)
	assert_bool(s.interact()).is_true()
	assert_bool(s.interact()).is_false()
	assert_int(_exits).is_equal(1)
	assert_bool(s.can_interact()).is_false()
	assert_bool(s.used).is_true()


func test_a_re_entrant_exit_request_cannot_descend_twice() -> void:
	var s := _make(false)
	var reenter := func() -> void: s.interact()
	EventBus.floor_exit_requested.connect(reenter)
	assert_bool(s.interact()).is_true()
	EventBus.floor_exit_requested.disconnect(reenter)
	assert_int(_exits).is_equal(1)
