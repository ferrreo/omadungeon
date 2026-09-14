class_name PlayerCoreTest
extends GdUnitTestSuite

var _player: Player


func before_test() -> void:
	HitStop.set_enabled(get_tree(), false)
	_player = auto_free(PlayerTestHelpers.make_player())
	add_child(_player)
	await get_tree().physics_frame


func after_test() -> void:
	HitStop.set_enabled(get_tree(), true)
	Engine.time_scale = 1.0


func test_scene_wiring_and_group() -> void:
	assert_bool(_player.is_in_group(&"player")).is_true()
	assert_int(_player.team).is_equal(Layers.Team.PLAYER)
	assert_object(_player.input).is_not_null()
	assert_object(_player.weapon_controller).is_not_null()
	assert_object(_player.health as PlayerHealth).is_not_null()
	assert_object(_player.hurtbox).is_not_null()
	assert_int(_player.hurtbox.collision_layer).is_equal(Layers.PLAYER_HURTBOX)
	assert_object(_player.weapon_controller.weapon).is_not_null()
	assert_str(String(_player.weapon_controller.weapon.id)).is_equal("fists")
	assert_object(_player.sprite.sprite_frames).is_not_null()


func test_apply_class_sets_docs_stats_and_hp() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	assert_int(_player.stats.primary(&"vitality")).is_equal(6)
	assert_int(_player.stats.primary(&"might")).is_equal(6)
	assert_int(_player.stats.primary(&"swiftness")).is_equal(3)
	assert_float(_player.health.max_hp).is_equal_approx(130.0, 0.001)
	assert_float(_player.health.hp).is_equal_approx(130.0, 0.001)
	assert_int(_player.dodge_style).is_equal(ClassDef.DodgeStyle.ROLL)
	assert_bool(_player.sprite.sprite_frames.has_animation(&"run")).is_true()
	assert_int(_player.sprite.sprite_frames.get_frame_count(&"run")).is_equal(6)
	assert_int(_player.sprite.sprite_frames.get_frame_count(&"death")).is_equal(6)
	_player.apply_class(PlayerTestHelpers.load_class("oligarch"))
	assert_int(_player.gold).is_equal(150)
	assert_float(_player.health.max_hp).is_equal_approx(120.0, 0.001)


func test_roll_dodge_grants_iframes_that_block_damage() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.health.dodge_chance = 0.0  # fortune dodge is random; keep the test deterministic
	var dodged: Array[StringName] = []
	var handler := func(style: StringName) -> void: dodged.append(style)
	EventBus.player_dodged.connect(handler)
	assert_bool(_player.try_dodge(Vector2.RIGHT)).is_true()
	EventBus.player_dodged.disconnect(handler)
	assert_array(dodged).contains([&"roll"])
	assert_bool(_player.is_dodging()).is_true()
	assert_bool(_player.is_invulnerable()).is_true()
	var hp_before := _player.health.hp
	var dealt := _player.hurtbox.receive(PlayerTestHelpers.enemy_hit(20.0))
	assert_float(dealt).is_equal(0.0)
	assert_float(_player.health.hp).is_equal_approx(hp_before, 0.001)
	(
		assert_bool(_player.try_dodge(Vector2.RIGHT))
		. override_failure_message("dodge on cooldown")
		. is_false()
	)
	await PlayerTestHelpers.physics_frames(get_tree(), 20)
	assert_bool(_player.is_dodging()).is_false()
	assert_bool(_player.is_invulnerable()).is_false()
	assert_float(_player.position.x).is_greater(20.0)
	dealt = _player.hurtbox.receive(PlayerTestHelpers.enemy_hit(20.0))
	assert_float(dealt).is_greater(0.0)


func test_dash_has_no_iframes_and_trap_immunity_follows_flag() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("ranger"))
	_player.try_dodge(Vector2.DOWN)
	assert_bool(_player.is_dodging()).is_true()
	assert_bool(_player.is_invulnerable()).is_false()
	assert_bool(_player.is_trap_immune()).is_false()
	_player.flags["trap_immune_dodge"] = true
	assert_bool(_player.is_trap_immune()).is_true()


func test_blink_teleports_three_tiles_and_stops_at_walls() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("wizard"))
	_player.try_dodge(Vector2.RIGHT)
	assert_int(_player.state).is_equal(Player.State.DODGE_STARTUP)
	await PlayerTestHelpers.physics_frames(get_tree(), 14)
	assert_float(_player.position.x).is_equal_approx(48.0, 2.0)
	await PlayerTestHelpers.physics_frames(get_tree(), 40)
	var wall := auto_free(PlayerTestHelpers.wall(Vector2(80, 0), Vector2(8, 64))) as StaticBody2D
	add_child(wall)
	await PlayerTestHelpers.physics_frames(get_tree(), 2)
	_player.position = Vector2(48, 0)
	_player.try_dodge(Vector2.RIGHT)
	await PlayerTestHelpers.physics_frames(get_tree(), 14)
	assert_float(_player.position.x).is_less(76.0)
	assert_float(_player.position.x).is_greater(48.0)


func test_delegate_dodge_spawns_decoy() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("oligarch"))
	_player.try_dodge(Vector2.LEFT)
	var decoys := get_tree().get_nodes_in_group(&"decoys")
	assert_int(decoys.size()).is_equal(1)
	var decoy := decoys[0] as Decoy
	assert_object(decoy).is_not_null()
	assert_vector(decoy.global_position).is_equal_approx(Vector2.ZERO, Vector2(1, 1))
	decoy.queue_free()


func test_potion_heals_forty_percent_once() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.health.hp = 10.0
	var healed: Array[int] = []
	var handler := func(amount: int) -> void: healed.append(amount)
	EventBus.player_healed.connect(handler)
	assert_bool(_player.use_potion()).is_true()
	EventBus.player_healed.disconnect(handler)
	assert_float(_player.health.hp).is_equal_approx(10.0 + 130.0 * 0.4, 0.01)
	assert_int(_player.potions).is_equal(0)
	assert_array(healed).is_equal([52])
	assert_bool(_player.use_potion()).is_false()
	_player.add_potion()
	assert_int(_player.potions).is_equal(1)


func test_shield_absorbs_before_hp() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.health.dodge_chance = 0.0  # fortune dodge is random; keep the test deterministic
	_player.set_shield(15.0)
	assert_float(_player.shield()).is_equal_approx(15.0, 0.001)
	var dealt := _player.hurtbox.receive(PlayerTestHelpers.enemy_hit(10.0))
	assert_float(dealt).is_equal(0.0)
	assert_float(_player.health.hp).is_equal_approx(130.0, 0.001)
	assert_float(_player.shield()).is_equal_approx(5.0, 0.001)
	_player._hit_invuln_left = 0.0
	_player._update_invulnerable()
	dealt = _player.hurtbox.receive(PlayerTestHelpers.enemy_hit(10.0))
	assert_float(dealt).is_equal_approx(5.0, 0.001)
	assert_float(_player.health.hp).is_equal_approx(125.0, 0.001)
	assert_float(_player.shield()).is_equal(0.0)


func test_timed_shield_expires() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.set_shield(20.0, 0.1)
	assert_float(_player.shield()).is_equal_approx(20.0, 0.001)
	await PlayerTestHelpers.physics_frames(get_tree(), 10)
	assert_float(_player.shield()).is_equal(0.0)


func test_hit_gives_post_hit_invulnerability_and_signals() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.health.dodge_chance = 0.0  # fortune dodge is random; keep the test deterministic
	var damaged: Array[int] = []
	var handler := func(amount: int, _source: Node2D) -> void: damaged.append(amount)
	EventBus.player_damaged.connect(handler)
	var shakes: Array[float] = []
	var shake_handler := func(strength: float, _duration: float) -> void: shakes.append(strength)
	EventBus.screen_shake.connect(shake_handler)
	_player.hurtbox.receive(PlayerTestHelpers.enemy_hit(12.0))
	EventBus.player_damaged.disconnect(handler)
	EventBus.screen_shake.disconnect(shake_handler)
	assert_array(damaged).is_equal([12])
	assert_int(shakes.size()).is_greater_equal(1)
	assert_bool(_player.is_invulnerable()).is_true()
	assert_float(_player.hurtbox.receive(PlayerTestHelpers.enemy_hit(12.0))).is_equal(0.0)
	await PlayerTestHelpers.physics_frames(get_tree(), 36)
	assert_bool(_player.is_invulnerable()).is_false()


func test_gold_and_stat_signals() -> void:
	var gold_seen: Array[int] = []
	var gold_handler := func(amount: int) -> void: gold_seen.append(amount)
	EventBus.gold_changed.connect(gold_handler)
	var stat_seen: Array = []
	var stat_handler := func(stat: StringName, value: int) -> void: stat_seen.append([stat, value])
	EventBus.stat_changed.connect(stat_handler)
	_player.add_gold(30)
	assert_bool(_player.spend_gold(50)).is_false()
	assert_bool(_player.spend_gold(10)).is_true()
	assert_int(_player.gold).is_equal(20)
	_player.add_stat(&"might", 2)
	assert_int(_player.stats.primary(&"might")).is_equal(2)
	assert_bool(_player.steal_stat(&"might")).is_true()
	assert_bool(_player.steal_stat(&"arcana")).is_false()
	EventBus.gold_changed.disconnect(gold_handler)
	EventBus.stat_changed.disconnect(stat_handler)
	assert_array(gold_seen).is_equal([30, 20])
	assert_array(stat_seen).is_equal([[&"might", 2], [&"might", 1]])


func test_movement_accelerates_and_slippery_is_slower_to_start() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.input.enabled = false
	_player._apply_movement(1.0 / 60.0, Vector2.RIGHT)
	var normal_speed := _player.velocity.x
	assert_float(normal_speed).is_greater(0.0)
	_player.velocity = Vector2.ZERO
	_player.set_slippery(true)
	_player._apply_movement(1.0 / 60.0, Vector2.RIGHT)
	assert_float(_player.velocity.x).is_less(normal_speed)
	assert_float(_player.velocity.x).is_greater(0.0)


func test_death_plays_out_then_emits_player_died() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("wizard"))
	_player.health.dodge_chance = 0.0  # fortune dodge is random; keep the test deterministic
	var died := [false]
	var handler := func() -> void: died[0] = true
	EventBus.player_died.connect(handler)
	_player.hurtbox.receive(PlayerTestHelpers.enemy_hit(9999.0))
	assert_int(_player.state).is_equal(Player.State.DEAD)
	assert_bool(_player.health.is_dead()).is_true()
	assert_bool(died[0]).is_false()
	await get_tree().create_timer(1.0).timeout
	EventBus.player_died.disconnect(handler)
	assert_bool(died[0]).is_true()
	assert_bool(is_instance_valid(_player)).is_true()


func test_save_roundtrip() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("oligarch"))
	_player.add_stat(&"fortune", 3)
	_player.health.hp = 60.0
	_player.set_shield(7.0)
	_player.flags["chest_extra_option"] = true
	var data := _player.to_dict()
	var other := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(other)
	other.apply_class(PlayerTestHelpers.load_class("oligarch"))
	other.restore_from_dict(data)
	assert_int(other.gold).is_equal(150)
	assert_int(other.stats.primary(&"fortune")).is_equal(9)
	assert_float(other.health.max_hp).is_equal_approx(_player.health.max_hp, 0.001)
	assert_float(other.health.hp).is_equal_approx(60.0, 0.5)
	assert_float(other.shield()).is_equal_approx(7.0, 0.001)
	assert_bool(bool(other.flags.get("chest_extra_option", false))).is_true()


func test_max_potions_survives_the_save_roundtrip() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.max_potions = 3
	_player.add_potion(2)
	assert_int(_player.potions).is_equal(3)
	var other := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(other)
	other.apply_class(PlayerTestHelpers.load_class("fighter"))
	other.restore_from_dict(_player.to_dict())
	assert_int(other.max_potions).is_equal(3)
	assert_int(other.potions).is_equal(3)


func test_gamepad_auto_aim_locks_on_the_nearest_enemy() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("ranger"))
	var enemy := auto_free(Node2D.new()) as Node2D
	enemy.add_to_group(WeaponController.ENEMY_GROUP)
	add_child(enemy)
	enemy.global_position = _player.global_position + Vector2(48, 0)
	_player.input.last_device = PlayerInput.Device.GAMEPAD
	_player._tick_auto_aim(1.0)
	assert_object(_player.input.auto_aim_target).is_same(enemy)
	_player.input.last_device = PlayerInput.Device.KBM
	_player._tick_auto_aim(1.0)
	assert_object(_player.input.auto_aim_target).is_null()


func test_blink_never_lands_inside_geometry() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("wizard"))
	_player.global_position = Vector2.ZERO
	var wall := auto_free(PlayerTestHelpers.wall(Vector2(40, 0), Vector2(16, 200))) as StaticBody2D
	add_child(wall)
	await PlayerTestHelpers.physics_frames(get_tree(), 3)
	_player._blink_to(Vector2.RIGHT, Player.BLINK_DISTANCE)
	# Wall spans x 32..48 and the body capsule is 4 px wide: the landing spot must clear both.
	assert_float(_player.global_position.x).is_greater(0.0)
	assert_float(_player.global_position.x).is_less(28.0)


func test_chip_damage_mid_swing_keeps_the_active_hitbox() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.health.dodge_chance = 0.0
	_player.weapon_controller.try_attack(Vector2.RIGHT)
	# `is_live()`, not `monitoring`: the physics flag is applied deferred (Hitbox has to be
	# safe to toggle from inside an overlap callback), so it trails `activate()` by one flush.
	assert_bool(_player.weapon_controller.hitbox.is_live()).is_true()
	_player.hurtbox.receive(PlayerTestHelpers.enemy_hit(3.0))
	assert_bool(_player.weapon_controller.hitbox.is_live()).is_true()
	assert_int(_player.weapon_controller.combo_index).is_equal(0)
	# ... and the flag really does catch up, on the swing that took the chip damage.
	await PlayerTestHelpers.physics_frames(get_tree(), 1)
	assert_bool(_player.weapon_controller.hitbox.monitoring).is_true()


func test_death_during_a_blink_startup_restores_the_sprite() -> void:
	_player.apply_class(PlayerTestHelpers.load_class("wizard"))
	_player.health.dodge_chance = 0.0
	assert_bool(_player.try_dodge(Vector2.RIGHT)).is_true()
	assert_int(_player.state).is_equal(Player.State.DODGE_STARTUP)
	assert_float(_player.sprite.modulate.a).is_less(1.0)
	_player.health.invulnerable = false
	_player.hurtbox.receive(PlayerTestHelpers.enemy_hit(9999.0))
	assert_int(_player.state).is_equal(Player.State.DEAD)
	assert_float(_player.sprite.modulate.a).is_equal_approx(1.0, 0.001)


## The fallback sheet fired once in a real capture and rendered the hero as a blank white
## block that a light theme swallows whole. It has to stay a readable figure: two colours,
## a body that clears 4.5:1 against the floor, and a silhouette, not a filled rectangle.
func test_placeholder_sheet_is_a_readable_figure_not_a_white_block() -> void:
	var image := Player._placeholder_sheet().get_image()
	var palette := Desktop.palette
	var floor_c := palette.get_color(&"floor")
	var body := Player.placeholder_body_color()
	var ink := Player.placeholder_ink_color()
	(
		assert_float(ThemePalette.contrast_ratio(body, floor_c))
		. override_failure_message("the placeholder body is not readable on the dungeon floor")
		. is_greater_equal(ThemePalette.MIN_CONTRAST)
	)
	assert_float(ThemePalette.contrast_ratio(body, ink)).is_greater(1.5)
	var seen: Dictionary = {}
	var transparent := 0
	for y in range(16):
		for x in range(16):
			var c := image.get_pixel(x, y)
			if c.a <= 0.01:
				transparent += 1
				continue
			seen[c.to_html(false)] = true
	(
		assert_int(seen.size())
		. override_failure_message("the placeholder is one flat colour")
		. is_greater(1)
	)
	(
		assert_int(transparent)
		. override_failure_message("the placeholder fills the whole cell, so it has no silhouette")
		. is_greater(16)
	)
	assert_bool(seen.has(Color.WHITE.to_html(false))).is_false()


func test_a_missing_class_sheet_is_loud_and_still_draws_something() -> void:
	var missing := "res://assets/sprites/player/not_a_class.png"
	var expected := (
		"Player: class sprite sheet missing, drawing the placeholder instead: %s" % missing
	)
	await (assert_error(func() -> void: Player.load_class_sheet(missing)).is_push_error(expected))
	assert_object(Player.load_class_sheet("res://assets/sprites/player/fighter.png")).is_not_null()
