## Behaviour tests for concrete traps: cycles, immunities, signals. Runs real physics frames.
class_name TrapBehaviourTest
extends GdUnitTestSuite

const POS := Vector2(200.0, 200.0)


## Player stand-in that is immune to floor traps (Ranger dodge).
class ImmunePlayer:
	extends Entity

	func is_trap_immune() -> bool:
		return true


## Player stand-in that reports whether it is mid-dodge.
class DodgingPlayer:
	extends Entity
	var dodging: bool = true

	func is_dodging() -> bool:
		return dodging


## Enemy stand-in exposing a faction (Tinkerer) like EnemyBase does.
class TinkererEnemy:
	extends Entity
	var faction: int = EnemyDef.Faction.TINKERERS


## Enemy stand-in that hovers over pits.
class FloatingEnemy:
	extends Entity
	var floats: bool = true


## Enemy stand-in whose `is_trap_immune()` is true (EnemyBase returns `ignores_pits()` there):
## it skips pits but must still be hurt by every other trap.
class PitAvoidingEnemy:
	extends Entity
	var floats: bool = true

	func is_trap_immune() -> bool:
		return true


## Body that records slippery toggles from ice.
class SlipperyBody:
	extends Entity
	var slippery_calls: Array[bool] = []

	func set_slippery(value: bool) -> void:
		slippery_calls.append(value)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func _make_entity(team: Layers.Team, at: Vector2, script_entity: Entity = null) -> Entity:
	var entity := script_entity if script_entity != null else Entity.new()
	entity.team = team
	entity.position = at
	# Entity only builds its hurtbox; give the body a shape so trigger areas can see it.
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10.0, 12.0)
	shape.shape = rect
	entity.add_child(shape)
	add_child(auto_free(entity))
	return entity


func _make_trap(kind: StringName, at: Vector2, extra: Dictionary = {}) -> TrapBase:
	var trap := TrapRegistry.instantiate(kind, at, extra)
	add_child(auto_free(trap))
	return trap


# --- spike floor ---------------------------------------------------------------------------


func test_spike_damages_after_telegraph_not_during() -> void:
	var spike := _make_trap(&"spike_floor", POS, {"proximity_trigger": false})
	var victim := _make_entity(Layers.Team.PLAYER, POS)
	await _frames(2)
	assert_bool(spike.trigger()).is_true()
	assert_bool(spike.is_telegraphing()).is_true()
	await _frames(15)
	assert_float(victim.health.hp).is_equal(100.0)
	assert_bool(spike.is_dangerous()).is_false()
	await _frames(25)
	assert_bool(spike.is_dangerous()).is_true()
	assert_float(victim.health.hp).is_equal(85.0)
	await _frames(30)
	assert_int(spike.state).is_equal(TrapBase.State.COOLDOWN)
	assert_float(victim.health.hp).is_equal(85.0)
	assert_int(spike.cycles()).is_equal(1)
	assert_bool(spike.trigger()).is_false()


func test_spike_is_proximity_triggered() -> void:
	var spike := _make_trap(&"spike_floor", POS)
	assert_int(spike.state).is_equal(TrapBase.State.IDLE)
	_make_entity(Layers.Team.PLAYER, POS)
	await _frames(4)
	assert_int(spike.state).is_equal(TrapBase.State.TELEGRAPH)


func test_spike_hits_enemies_unless_enemies_immune() -> void:
	var spike := _make_trap(&"spike_floor", POS)
	var enemy := _make_entity(Layers.Team.ENEMY, POS)
	await _frames(45)
	assert_float(enemy.health.hp).is_equal(85.0)
	var safe_spike := _make_trap(
		&"spike_floor", POS + Vector2(100, 0), {"enemies_immune": true, "proximity_trigger": false}
	)
	var enemy2 := _make_entity(Layers.Team.ENEMY, POS + Vector2(100, 0))
	await _frames(2)
	safe_spike.trigger()
	await _frames(45)
	assert_bool(safe_spike.cycles() >= 1).is_true()
	assert_float(enemy2.health.hp).is_equal(100.0)


func test_trap_immune_player_and_tinkerers_are_skipped() -> void:
	var spike := _make_trap(&"spike_floor", POS, {"proximity_trigger": false})
	var ranger := _make_entity(Layers.Team.PLAYER, POS, ImmunePlayer.new())
	var tinkerer := _make_entity(Layers.Team.ENEMY, POS, TinkererEnemy.new())
	await _frames(2)
	spike.trigger()
	await _frames(45)
	assert_bool(spike.cycles() >= 1).is_true()
	assert_float(ranger.health.hp).is_equal(100.0)
	assert_float(tinkerer.health.hp).is_equal(100.0)


func test_disabled_trap_does_not_fire() -> void:
	var spike := _make_trap(&"spike_floor", POS)
	spike.set_enabled(false)
	_make_entity(Layers.Team.PLAYER, POS)
	await _frames(10)
	assert_int(spike.state).is_equal(TrapBase.State.IDLE)


# --- arrow wall ---------------------------------------------------------------------------


func test_arrow_wall_cadence() -> void:
	var wall := _make_trap(&"arrow_wall", POS, {"direction": Vector2.RIGHT}) as ArrowWall
	# Only arrows fired by THIS wall: the group is process-global and other suites use it too.
	var fired: Array[Projectile] = []
	wall.arrow_fired.connect(func(p: Projectile) -> void: fired.append(p))
	await _frames(5)
	assert_int(fired.size()).is_equal(0)
	await _frames(30)  # 0.58 s: past the 0.4 s telegraph.
	assert_int(fired.size()).is_equal(1)
	var arrow := fired[0]
	assert_object(arrow).is_not_null()
	assert_bool(arrow.is_in_group(&"enemy_projectile")).is_true()
	assert_vector(arrow.direction).is_equal(Vector2.RIGHT)
	assert_int(arrow.hitbox.collision_mask).is_equal(Layers.PLAYER_HURTBOX | Layers.ENEMY_HURTBOX)
	assert_object(arrow.hitbox.source).is_same(wall)
	# Trigger-to-trigger period is active + cooldown + telegraph = 2.5 s (150 frames), so the
	# second arrow is due at ~frame 174. Assert well inside both halves of that window.
	await _frames(115)  # frame ~150 (2.5 s)
	assert_int(fired.size()).is_equal(1)
	await _frames(50)  # frame ~200 (3.3 s)
	assert_int(fired.size()).is_equal(2)
	assert_int(wall.projectiles_fired).is_equal(2)


func test_arrow_spawns_at_the_wall_under_a_translated_parent() -> void:
	var world := auto_free(Node2D.new()) as Node2D
	world.name = "OffsetWorld"
	world.position = Vector2(120.0, 80.0)
	add_child(world)
	var wall := (
		TrapRegistry.instantiate(&"arrow_wall", Vector2(16.0, 16.0), {"direction": Vector2.RIGHT})
		as ArrowWall
	)
	world.add_child(wall)
	await _frames(2)
	var arrow := wall.fire()
	assert_object(arrow).is_not_null()
	assert_vector(arrow.global_position).is_equal_approx(
		wall.global_position + Vector2(8.0, 0.0), Vector2(0.5, 0.5)
	)


func test_arrow_wall_pauses_when_player_leaves_room() -> void:
	var wall := _make_trap(&"arrow_wall", POS, {"room_id": 3}) as ArrowWall
	EventBus.room_entered.emit(7)
	await _frames(40)
	assert_int(wall.projectiles_fired).is_equal(0)
	EventBus.room_entered.emit(3)
	await _frames(40)
	assert_int(wall.projectiles_fired).is_equal(1)


# --- fire vent ---------------------------------------------------------------------------


func test_fire_vent_burns() -> void:
	var vent := _make_trap(&"fire_vent", POS) as FireVent
	var victim := _make_entity(Layers.Team.PLAYER, POS)
	await _frames(45)
	assert_bool(vent.is_dangerous()).is_true()
	assert_bool(victim.health.hp < 100.0).is_true()
	assert_bool(victim.status.has(StatusEffect.Kind.BURN)).is_true()


# --- pit ----------------------------------------------------------------------------------


func test_pit_emits_player_fell_and_damages() -> void:
	var fell: Array[Vector2] = []
	var handler := func(pos: Vector2) -> void: fell.append(pos)
	EventBus.player_fell.connect(handler)
	_make_trap(&"pit", POS)
	var player := _make_entity(Layers.Team.PLAYER, POS)
	await _frames(6)
	EventBus.player_fell.disconnect(handler)
	assert_int(fell.size()).is_equal(1)
	assert_vector(fell[0]).is_equal_approx(POS, Vector2(2.0, 2.0))
	assert_float(player.health.hp).is_equal(90.0)


func test_pit_ignores_dodging_player_and_floating_enemy() -> void:
	var fell: Array[Vector2] = []
	var handler := func(pos: Vector2) -> void: fell.append(pos)
	EventBus.player_fell.connect(handler)
	var pit := _make_trap(&"pit", POS) as Pit
	var dodger := _make_entity(Layers.Team.PLAYER, POS, DodgingPlayer.new()) as DodgingPlayer
	var floater := _make_entity(Layers.Team.ENEMY, POS, FloatingEnemy.new())
	await _frames(6)
	assert_int(fell.size()).is_equal(0)
	assert_float(dodger.health.hp).is_equal(100.0)
	assert_float(floater.health.hp).is_equal(100.0)
	dodger.dodging = false
	await _frames(3)
	EventBus.player_fell.disconnect(handler)
	assert_int(fell.size()).is_equal(1)
	assert_float(dodger.health.hp).is_equal(90.0)
	assert_object(pit).is_not_null()


func test_pit_shoves_grounded_enemy() -> void:
	_make_trap(&"pit", POS)
	var enemy := _make_entity(Layers.Team.ENEMY, POS + Vector2(3, 0))
	await _frames(6)
	assert_float(enemy.health.hp).is_equal(90.0)
	assert_bool(enemy.knockback_velocity.x > 0.0).is_true()


# --- pressure plate -----------------------------------------------------------------------


func test_plate_triggers_linked_spike_and_emits() -> void:
	var pressed_ids: Array[StringName] = []
	var handler := func(id: StringName) -> void: pressed_ids.append(id)
	EventBus.plate_pressed.connect(handler)
	var spike := _make_trap(&"spike_floor", POS + Vector2(64, 0), {"proximity_trigger": false})
	spike.add_to_group(&"link_a")
	var plate := (
		_make_trap(&"pressure_plate", POS, {"plate_id": "p1", "linked_group": "link_a"})
		as PressurePlate
	)
	assert_int(spike.state).is_equal(TrapBase.State.IDLE)
	_make_entity(Layers.Team.PLAYER, POS)
	await _frames(4)
	EventBus.plate_pressed.disconnect(handler)
	assert_bool(plate.pressed).is_true()
	assert_int(spike.state).is_equal(TrapBase.State.TELEGRAPH)
	assert_array(pressed_ids).contains_exactly([&"p1"])


func test_plate_toggles_cycling_trap() -> void:
	var laser := _make_trap(&"laser_grid", POS + Vector2(64, 0))
	laser.add_to_group(&"link_b")
	var plate := _make_trap(&"pressure_plate", POS, {"linked_group": "link_b"}) as PressurePlate
	await _frames(2)
	assert_bool(laser.enabled).is_true()
	plate.press()
	assert_bool(laser.enabled).is_false()
	assert_int(laser.state).is_equal(TrapBase.State.IDLE)


# --- ice ----------------------------------------------------------------------------------


func test_ice_slide_toggles_slippery() -> void:
	_make_trap(&"ice_slide", POS)
	var body := _make_entity(Layers.Team.PLAYER, POS, SlipperyBody.new()) as SlipperyBody
	await _frames(4)
	assert_array(body.slippery_calls).contains_exactly([true])
	body.position = POS + Vector2(100, 0)
	await _frames(4)
	assert_array(body.slippery_calls).contains_exactly([true, false])


func test_ice_field_keeps_sliding_across_the_seam() -> void:
	_make_trap(&"ice_slide", POS)
	_make_trap(&"ice_slide", POS + Vector2(16, 0))
	var body := _make_entity(Layers.Team.PLAYER, POS, SlipperyBody.new()) as SlipperyBody
	await _frames(4)
	assert_array(body.slippery_calls).contains_exactly([true])
	body.position = POS + Vector2(16, 0)
	await _frames(6)
	assert_array(body.slippery_calls).contains_exactly([true])
	body.position = POS + Vector2(200, 0)
	await _frames(6)
	assert_array(body.slippery_calls).contains_exactly([true, false])


# --- laser --------------------------------------------------------------------------------


func test_laser_timing_on_one_off_one_and_a_half() -> void:
	var laser := _make_trap(&"laser_grid", POS, {"to": POS + Vector2(48, 0)}) as LaserGrid
	assert_vector(laser.end_offset).is_equal(Vector2(48, 0))
	await _frames(5)
	assert_int(laser.state).is_equal(TrapBase.State.TELEGRAPH)
	await _frames(25)
	assert_bool(laser.is_dangerous()).is_true()
	await _frames(40)
	assert_bool(laser.is_dangerous()).is_true()
	await _frames(25)
	assert_int(laser.state).is_equal(TrapBase.State.COOLDOWN)
	assert_int(laser.cycles()).is_equal(1)
	await _frames(55)
	assert_int(laser.cycles()).is_equal(1)
	await _frames(30)
	assert_int(laser.cycles()).is_equal(2)


func test_laser_hits_entity_in_beam_hard() -> void:
	_make_trap(&"laser_grid", POS, {"to": POS + Vector2(48, 0)})
	var victim := _make_entity(Layers.Team.PLAYER, POS + Vector2(24, 0))
	await _frames(30)
	assert_float(victim.health.hp).is_equal(70.0)


# --- mimic --------------------------------------------------------------------------------


func test_mimic_requests_enemy_and_removes_itself() -> void:
	var requests: Array[Dictionary] = []
	var handler := func(id: StringName, pos: Vector2) -> void:
		requests.append({"id": id, "pos": pos})
	EventBus.spawn_enemy_requested.connect(handler)
	var mimic := TrapRegistry.instantiate(&"mimic_chest", POS) as MimicChest
	add_child(mimic)
	var expected_id := mimic.enemy_id
	await _frames(2)
	var interactable := mimic.get_node("Interactable") as TrapInteractable
	assert_object(interactable).is_not_null()
	assert_int(interactable.collision_layer).is_equal(Layers.INTERACTABLE)
	interactable.interact()
	await _frames(2)
	EventBus.spawn_enemy_requested.disconnect(handler)
	assert_int(requests.size()).is_equal(1)
	assert_str(String(requests[0]["id"])).is_equal(String(expected_id))
	assert_vector(requests[0]["pos"]).is_equal(POS)
	assert_bool(is_instance_valid(mimic)).is_false()


func test_mimic_enemy_id_exists_in_the_enemy_registry() -> void:
	var mimic := auto_free(TrapRegistry.instantiate(&"mimic_chest", POS)) as MimicChest
	var registry := load(MimicChest.ENEMY_REGISTRY_PATH) as EnemyRegistry
	assert_object(registry).is_not_null()
	(
		assert_object(registry.find(mimic.enemy_id))
		. override_failure_message("MimicChest.enemy_id '%s' has no EnemyDef" % mimic.enemy_id)
		. is_not_null()
	)
	assert_bool(mimic.spawn_is_servable()).is_true()


func test_mimic_with_unknown_enemy_id_stays_put() -> void:
	var mimic := (
		TrapRegistry.instantiate(&"mimic_chest", POS, {"enemy_id": "not_an_enemy"}) as MimicChest
	)
	add_child(auto_free(mimic))
	await _frames(2)
	var requests: Array[StringName] = []
	var handler := func(id: StringName, _pos: Vector2) -> void: requests.append(id)
	EventBus.spawn_enemy_requested.connect(handler)
	assert_bool(mimic.interact()).is_false()
	EventBus.spawn_enemy_requested.disconnect(handler)
	assert_int(requests.size()).is_equal(0)
	assert_bool(is_instance_valid(mimic)).is_true()


# --- hazards ------------------------------------------------------------------------------


func test_hazards_are_one_shot_and_enemy_safe() -> void:
	var spike := _make_trap(&"kernel_spike", POS, {"duration": 0.3})
	var player := _make_entity(Layers.Team.PLAYER, POS)
	var enemy := _make_entity(Layers.Team.ENEMY, POS)
	await _frames(45)
	assert_float(player.health.hp).is_equal(80.0)
	assert_float(enemy.health.hp).is_equal(100.0)
	await _frames(40)
	assert_bool(is_instance_valid(spike)).is_false()


func test_ricer_trap_becomes_spikes_after_one_second() -> void:
	var prop := _make_trap(&"ricer_trap", POS, {"duration": 1.0})
	var player := _make_entity(Layers.Team.PLAYER, POS)
	await _frames(50)
	assert_float(player.health.hp).is_equal(100.0)
	await _frames(20)
	assert_bool(prop.is_dangerous()).is_true()
	assert_float(player.health.hp).is_equal(88.0)


# --- regressions ---------------------------------------------------------------------------


func test_trap_hitbox_is_neutral_and_hits_both_hurtboxes() -> void:
	var spike := _make_trap(&"spike_floor", POS, {"proximity_trigger": false})
	await _frames(2)
	assert_int(spike.hitbox.collision_mask).is_equal(Layers.PLAYER_HURTBOX | Layers.ENEMY_HURTBOX)
	assert_int(spike.hitbox.team).is_equal(Layers.Team.NEUTRAL)
	assert_array(spike.tags).contains([DamageInfo.TAG_TRAP, DamageInfo.TAG_PHYSICAL])


func test_zero_active_window_does_not_lock_the_cycle() -> void:
	var spike := _make_trap(&"spike_floor", POS, {"proximity_trigger": false})
	spike.telegraph_time = 0.0
	spike.active_time = 0.0
	spike.cooldown_time = 0.05
	await _frames(2)
	assert_bool(spike.trigger()).is_true()
	await _frames(10)
	assert_int(spike.state).is_equal(TrapBase.State.IDLE)
	assert_int(spike.cycles()).is_equal(1)


func test_plate_does_not_stall_a_pit() -> void:
	var pit := _make_trap(&"pit", POS) as Pit
	await _frames(2)
	pit.on_plate_pressed(&"p", true)
	await _frames(2)
	assert_int(pit.state).is_equal(TrapBase.State.IDLE)
	var player := _make_entity(Layers.Team.PLAYER, POS)
	await _frames(8)
	assert_float(player.health.hp).is_equal(90.0)


func test_pit_grace_prevents_an_immediate_second_fall() -> void:
	_make_trap(&"pit", POS)
	var player := _make_entity(Layers.Team.PLAYER, POS)
	await _frames(8)
	assert_float(player.health.hp).is_equal(90.0)
	await _frames(20)  # still inside the 0.6 s re-fall grace
	assert_float(player.health.hp).is_equal(90.0)
	await _frames(30)  # grace over: the body is still in the hole
	assert_float(player.health.hp).is_equal(80.0)


func test_enemy_that_avoids_pits_still_takes_spike_damage() -> void:
	var pit := _make_trap(&"pit", POS + Vector2(128, 0)) as Pit
	var flyer := _make_entity(Layers.Team.ENEMY, POS + Vector2(128, 0), PitAvoidingEnemy.new())
	var spike := _make_trap(&"spike_floor", POS, {"proximity_trigger": false})
	var walker := _make_entity(Layers.Team.ENEMY, POS, PitAvoidingEnemy.new())
	await _frames(2)
	spike.trigger()
	await _frames(45)
	assert_object(pit).is_not_null()
	assert_float(flyer.health.hp).is_equal(100.0)  # is_trap_immune() only skips the hole
	assert_float(walker.health.hp).is_equal(85.0)


func test_reenabled_spike_rearms_under_a_standing_body() -> void:
	var spike := _make_trap(&"spike_floor", POS)
	spike.set_enabled(false)
	var victim := _make_entity(Layers.Team.PLAYER, POS)
	await _frames(10)
	assert_int(spike.state).is_equal(TrapBase.State.IDLE)
	assert_float(victim.health.hp).is_equal(100.0)
	spike.set_enabled(true)
	await _frames(45)
	assert_float(victim.health.hp).is_equal(85.0)


func test_plate_without_group_falls_back_to_its_room_trap_group() -> void:
	var spike := _make_trap(
		&"spike_floor", POS + Vector2(64, 0), {"proximity_trigger": false, "room_id": 5}
	)
	var plate := _make_trap(&"pressure_plate", POS, {"room_id": 5}) as PressurePlate
	await _frames(2)
	assert_str(String(plate.controlled_group())).is_equal(String(TrapBase.room_group(5)))
	assert_bool(spike.is_in_group(TrapBase.room_group(5))).is_true()
	plate.press()
	assert_int(spike.state).is_equal(TrapBase.State.TELEGRAPH)
