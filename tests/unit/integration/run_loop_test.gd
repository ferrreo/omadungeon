## End-to-end integration: a real run built by the RunManager autoload. Starts a run,
## generates floor 1, spawns enemies, kills them, takes the chest reward the clear spawns and
## walks to the stairs to reach floor 2. `manage_scenes` is off so the SceneTree's
## `current_scene` (the gdUnit runner) is never swapped out.
class_name RunLoopIntegrationTest
extends GdUnitTestSuite

const SEED := 424242
const CLASS_ID := &"fighter"
## Longest a test waits for the death animation plus `RunManager.DEATH_DELAY` to produce a
## run summary; a real failure still fails the assertion right after, it just does not hang.
const SUMMARY_TIMEOUT := 8.0


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	# The docs §2 passive pick has its own suite; here it would sit on top of every chest.
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


func test_run_starts_and_builds_a_populated_first_floor() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	assert_int(RunManager.floor_index).is_equal(0)
	assert_object(RunManager.floor_data).is_not_null()
	var root := RunManager.floor_root()
	assert_object(root).is_not_null()
	assert_int(root.rooms.size()).is_greater(3)
	assert_int(_live_enemies(root)).is_greater(0)
	var live := RunManager.player()
	assert_object(live).is_not_null()
	assert_bool(live.is_in_group(&"player")).is_true()
	assert_object((live.equipment as Equipment).get_item(&"weapon")).is_not_null()
	assert_vector(live.global_position).is_equal(root.player_spawn_position())
	# The camera is clamped to the generated grid, not to the default unbounded limits.
	var view := RunManager.game as Game
	assert_int(view.camera.limit_right).is_equal(int(root.camera_limits().end.x))
	# The generator's trap_positions became live TrapBase nodes under the floor root.
	if _floor_trap_count() > 0:
		assert_int(view.hazard_spawner.floor_traps().size()).is_greater(0)
	# Shops are stocked at build time, before the player can ever reach them.
	for node: Node in root.get_shops():
		var shop := node as Shop
		assert_array(shop.offers).is_not_empty()
		assert_int(shop.prices.size()).is_equal(shop.offers.size())
		assert_int(shop.prices[0]).is_greater(0)


func test_reaching_the_last_floor_exit_ends_the_run_as_a_victory() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	RunManager.floor_index = RunManager.FLOOR_COUNT - 1
	EventBus.floor_exit_requested.emit()
	await _frames(4)
	assert_bool(RunManager.is_run_active()).is_false()
	assert_bool(bool(RunManager.pending_summary.get("victory", false))).is_true()
	assert_int(int(RunManager.pending_summary.get("floor", 0))).is_equal(RunManager.FLOOR_COUNT)
	assert_bool(SaveManager.has_run()).is_false()


func test_clearing_a_room_spawns_a_chest_whose_offer_can_be_taken() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	var room := _busiest_room(root)
	assert_object(room).is_not_null()
	var live := RunManager.player()
	live.global_position = room.center_world()
	await _physics_frames(6)
	assert_bool(room.is_locked()).is_true()
	_kill(room, live)
	await _frames(6)
	assert_int(room.state).is_equal(RoomNode.State.CLEARED)
	assert_object(room.chest).is_not_null()
	var gold_before := live.gold
	var stats_before := _primary_total(live)
	var abilities_before := _ability_count(live)
	room.chest.interact(live)
	await _frames(4)
	var view := RunManager.game as Game
	assert_bool(view.chest_ui.is_open()).is_true()
	assert_int(view.chest_ui.card_count()).is_greater(0)
	view.chest_ui.select(0)
	view.chest_ui.activate()
	await _frames(4)
	assert_bool(room.chest.is_opened).is_true()
	# Whatever the chest rolled, taking it changed gold, stats or the ability slots.
	var changed := (
		live.gold != gold_before
		or _primary_total(live) != stats_before
		or _ability_count(live) != abilities_before
		or (live.equipment as Equipment).get_item(&"weapon") != null
	)
	assert_bool(changed).is_true()


func test_stairs_advance_to_the_next_floor() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	assert_object(root.stairs).is_not_null()
	assert_bool(root.stairs.locked).is_false()
	var first_hash := RunManager.floor_data.layout_hash()
	var live := RunManager.player()
	live.global_position = root.stairs.global_position
	await _physics_frames(6)
	assert_bool(root.stairs.player_nearby()).is_true()
	assert_bool(Interactable.dispatch(live)).is_true()
	await _frames(4)
	# Floor 1 still has reward rooms the player never walked into, so the first Descend only
	# warns; the confirmation press goes down (docs §8, RunManager.DESCEND_CONFIRM_WINDOW).
	if RunManager.floor_index == 0:
		assert_bool(Interactable.dispatch(live)).is_true()
		await _frames(6)
	assert_int(RunManager.floor_index).is_equal(1)
	assert_int(GameState.floor_index).is_equal(1)
	var next_root := RunManager.floor_root()
	assert_object(next_root).is_not_null()
	assert_int(RunManager.floor_data.layout_hash()).is_not_equal(first_hash)
	assert_int(_live_enemies(next_root)).is_greater(0)
	assert_vector(live.global_position).is_equal(next_root.player_spawn_position())


func test_full_loop_kills_everything_then_reaches_floor_two() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	var live := RunManager.player()
	live.health.invulnerable = true
	var cleared := 0
	for room: RoomNode in root.rooms:
		if room.enemies.is_empty():
			continue
		live.global_position = room.center_world()
		await _physics_frames(4)
		_kill(room, live)
		await _frames(4)
		if room.state == RoomNode.State.CLEARED:
			cleared += 1
	assert_int(cleared).is_greater(0)
	assert_int(_live_enemies(root)).is_equal(0)
	assert_int(RunManager.build_run_state().cleared_room_ids.size()).is_equal(cleared)
	live.global_position = root.stairs.global_position
	await _physics_frames(6)
	root.stairs.interact(live)
	await _frames(4)
	if RunManager.floor_index == 0:
		root.stairs.interact(live)
		await _frames(6)
	assert_int(RunManager.floor_index).is_equal(1)
	# Cleared rooms belong to the floor that is gone.
	assert_array(RunManager.build_run_state().cleared_room_ids).is_empty()


func test_minimap_marker_follows_the_room_the_player_entered() -> void:
	# RunManager and FloorRoot both listen to `room_entered`; the autoload connected first, so
	# it used to refresh the minimap while FloorRoot still held the previous room and the
	# "you are here" marker stayed one room behind for the whole run.
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	var view := RunManager.game as Game
	var map := _minimap(view)
	assert_object(map).is_not_null()
	assert_int(map.current_room_id()).is_equal(RunManager.floor_data.start_room)
	var visited: Array[int] = []
	for room: RoomNode in root.rooms:
		if room.id == root.current_room_id:
			continue
		EventBus.room_entered.emit(room.id)
		await _frames(2)
		assert_int(root.current_room_id).is_equal(room.id)
		# Read back what the widget was actually fed, not what the model could produce now.
		assert_int(map.current_room_id()).is_equal(room.id)
		visited.append(room.id)
		if visited.size() >= 3:
			break
	assert_int(visited.size()).is_greater(0)


func test_the_marker_is_current_on_the_first_frame_of_every_floor() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var view := RunManager.game as Game
	await _descend_one_floor()
	assert_int(RunManager.floor_index).is_equal(1)
	var start := RunManager.floor_data.start_room
	assert_int(RunManager.floor_root().current_room_id).is_equal(start)
	assert_int(_minimap(view).current_room_id()).is_equal(start)
	# A snapshot taken before the player's body has confirmed the room still names it.
	assert_int(RunManager.build_run_state().current_room_id).is_equal(start)


func test_a_second_run_starts_from_a_clean_slate() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var root := RunManager.floor_root()
	var live := RunManager.player()
	live.health.invulnerable = true
	live.add_gold(250)
	var room := _busiest_room(root)
	assert_object(room).is_not_null()
	_kill(room, live)
	await _frames(6)
	EventBus.room_entered.emit(room.id)
	await _descend_one_floor()
	var dirty := RunManager.build_run_state()
	assert_int(dirty.gold_earned).is_greater(0)
	assert_int(dirty.kills).is_greater(0)
	assert_int(RunManager.floor_index).is_equal(1)

	assert_bool(RunManager.new_run(SEED + 1, &"wizard")).is_true()
	await _frames(6)
	var fresh := RunManager.build_run_state()
	assert_int(fresh.floor_index).is_equal(0)
	assert_int(fresh.kills).is_equal(0)
	assert_int(fresh.gold_earned).is_equal(0)
	assert_int(fresh.damage_taken).is_equal(0)
	assert_array(fresh.cleared_room_ids).is_empty()
	assert_str(String(fresh.class_id)).is_equal("wizard")
	assert_int(fresh.run_seed).is_equal(SEED + 1)
	assert_int(fresh.current_room_id).is_equal(RunManager.floor_data.start_room)
	# No card from the previous run's chest is still pending, and the widget is not stale.
	var view := RunManager.game as Game
	assert_bool(view.chest_ui.is_open()).is_false()
	assert_int(_minimap(view).current_room_id()).is_equal(RunManager.floor_data.start_room)


func test_a_death_that_lands_after_the_next_run_started_does_not_end_it() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	EventBus.player_died.emit()
	await _frames(2)
	assert_bool(RunManager.is_run_active()).is_false()
	# Restart inside RunManager.DEATH_DELAY, the way "Retry seed" can.
	assert_bool(RunManager.new_run(SEED + 7, CLASS_ID)).is_true()
	await _frames(4)
	await get_tree().create_timer(RunManager.DEATH_DELAY + 0.4).timeout
	await _frames(4)
	# The stale death handler must not have torn the new run down or written a summary.
	assert_bool(RunManager.is_run_active()).is_true()
	assert_dict(RunManager.pending_summary).is_empty()
	assert_object(RunManager.floor_root()).is_not_null()
	assert_int(RunManager.run_seed).is_equal(SEED + 7)


func test_a_full_lifecycle_leaves_nothing_behind_for_the_next_run() -> void:
	# Start, clear a room, descend, die, start again: the second run must share no counter,
	# no cleared-room set, no purse and no RNG position with the first.
	assert_bool(RunManager.new_run(SEED, &"oligarch")).is_true()
	await _frames(4)
	var live := RunManager.player()
	live.health.invulnerable = true
	var room := _busiest_room(RunManager.floor_root())
	assert_object(room).is_not_null()
	_kill(room, live)
	await _frames(6)
	await _descend_one_floor()
	assert_int(RunManager.floor_index).is_equal(1)
	live = RunManager.player()
	live.add_gold(90)
	live.health.invulnerable = false
	live.health.take_damage(
		DamageInfo.create(99999.0, [DamageInfo.TAG_TRUE], null, Layers.Team.ENEMY)
	)
	# The death animation runs before `player_died`, and RunManager.DEATH_DELAY before the
	# summary, so wait for the outcome rather than guessing a frame count.
	await _await_summary()
	assert_bool(RunManager.is_run_active()).is_false()
	assert_dict(RunManager.pending_summary).is_not_empty()
	assert_bool(SaveManager.has_run()).is_false()

	assert_bool(RunManager.new_run(SEED + 3, CLASS_ID)).is_true()
	await _frames(6)
	var fresh := RunManager.build_run_state()
	assert_int(fresh.floor_index).is_equal(0)
	assert_int(fresh.kills).is_equal(0)
	assert_int(fresh.gold_earned).is_equal(0)
	assert_int(fresh.damage_taken).is_equal(0)
	assert_array(fresh.cleared_room_ids).is_empty()
	assert_int(RunManager.player().gold).is_equal(0)
	assert_int(RunManager.rng.run_seed).is_equal(SEED + 3)
	assert_dict(RunManager.pending_summary).is_empty()
	assert_bool(RunManager.is_run_active()).is_true()


func test_a_class_purse_is_not_counted_as_gold_earned() -> void:
	# The Oligarch starts with 150g (data/classes/oligarch.tres). That is a loadout, not loot.
	assert_bool(RunManager.new_run(SEED, &"oligarch")).is_true()
	await _frames(4)
	var live := RunManager.player()
	assert_int(live.gold).is_greater(0)
	var state := RunManager.build_run_state()
	assert_int(state.gold_earned).is_equal(0)
	live.add_gold(40)
	await _frames(2)
	assert_int(RunManager.build_run_state().gold_earned).is_equal(40)


## The run summary reads "DAMAGE TAKEN 99999" for a 130 HP Fighter, because `Health` clamped
## the HP it removed but reported the raw figure. A player cannot take more damage than the
## health they had; the summary must never say otherwise.
func test_a_fatal_hit_does_not_record_more_damage_than_the_player_had_health() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var live := RunManager.player()
	var max_hp := live.health.max_hp
	live.health.invulnerable = false
	live.hurtbox.receive(DamageInfo.create(99999.0, [DamageInfo.TAG_TRUE], null, Layers.Team.ENEMY))
	await _frames(3)
	var taken := RunManager.build_run_state().damage_taken
	(
		assert_int(taken)
		. override_failure_message("summary reports %d damage against %d max HP" % [taken, max_hp])
		. is_less_equal(int(ceilf(max_hp)))
	)
	assert_int(taken).is_greater(0)


## ... and the ordinary case is untouched: a survivable hit still counts in full.
func test_a_survivable_hit_is_still_counted_in_full() -> void:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	await _frames(4)
	var live := RunManager.player()
	live.health.invulnerable = false
	live.hurtbox.receive(DamageInfo.create(10.0, [DamageInfo.TAG_TRUE], null, Layers.Team.ENEMY))
	await _frames(3)
	assert_int(RunManager.build_run_state().damage_taken).is_equal(10)


## Descends one floor. Docs §8: leaving reward rooms unexplored costs a confirmation press
## first (RunManager.DESCEND_CONFIRM_WINDOW), so a floor still holding an altar or a shop
## answers the first request with a warning toast and only the second one goes down.
func _descend_one_floor() -> void:
	var before := RunManager.floor_index
	EventBus.floor_exit_requested.emit()
	await _frames(3)
	if RunManager.floor_index == before and RunManager.is_run_active():
		EventBus.floor_exit_requested.emit()
		await _frames(6)


## Waits for the run summary the death path produces, up to `SUMMARY_TIMEOUT` seconds.
func _await_summary() -> void:
	var deadline := Time.get_ticks_msec() + int(SUMMARY_TIMEOUT * 1000.0)
	while RunManager.pending_summary.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## The live Minimap widget inside the HUD (its node is private to the HUD scene).
static func _minimap(view: Game) -> Minimap:
	return view.hud.find_child("Minimap", true, false) as Minimap


## Kills every enemy of `room` with a lethal true-damage hit credited to the player.
func _kill(room: RoomNode, killer: Node2D) -> void:
	for enemy: Node2D in room.enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		var entity := enemy as Entity
		if entity == null or entity.health == null:
			continue
		entity.health.take_damage(
			DamageInfo.create(99999.0, [DamageInfo.TAG_TRUE], killer, Layers.Team.PLAYER)
		)


static func _busiest_room(root: FloorRoot) -> RoomNode:
	var best: RoomNode = null
	for room: RoomNode in root.rooms:
		if room.enemies.is_empty():
			continue
		if best == null or room.enemies.size() > best.enemies.size():
			best = room
	return best


## Trap entries the generator placed on the live floor.
static func _floor_trap_count() -> int:
	var total := 0
	for room: FloorData.Room in RunManager.floor_data.rooms:
		total += room.trap_positions.size()
	return total


static func _live_enemies(root: FloorRoot) -> int:
	var total := 0
	for room: RoomNode in root.rooms:
		total += room.pending_enemy_count()
	return total


static func _primary_total(live: Player) -> int:
	var total := 0
	for stat: StringName in Stats.PRIMARY:
		total += live.stats.primary(stat)
	return total


static func _ability_count(live: Player) -> int:
	var slots := live.ability_slots as AbilitySlots
	if slots == null:
		return 0
	return slots.all().size()


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame
