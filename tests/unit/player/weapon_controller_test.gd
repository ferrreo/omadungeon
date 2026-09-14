class_name PlayerWeaponControllerTest
extends GdUnitTestSuite

var _player: Player
var _wc: WeaponController


func before_test() -> void:
	HitStop.set_enabled(get_tree(), false)
	_player = auto_free(PlayerTestHelpers.make_player())
	add_child(_player)
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.stats.set_base(&"crit_chance", 0.0)
	_player.input.enabled = false
	_wc = _player.weapon_controller
	await get_tree().physics_frame


func after_test() -> void:
	HitStop.set_enabled(get_tree(), true)
	Engine.time_scale = 1.0


func _bow() -> WeaponBase:
	var bow := WeaponBase.new()
	bow.id = &"shortbow"
	bow.style = WeaponBase.Style.RANGED_BOW
	bow.base_damage = 10.0
	bow.attacks_per_second = 1.5
	bow.projectile_speed = 200.0
	bow.range_px = 200.0
	bow.tags = [DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]
	return bow


## A thrust weapon with a `combo_length`-beat combo (dagger, stiletto, spear, glaive all have one).
func _thrust_weapon(combo_length: int) -> WeaponBase:
	var spear := WeaponBase.new()
	spear.id = &"spear"
	spear.style = WeaponBase.Style.MELEE_THRUST
	spear.base_damage = 10.0
	spear.attacks_per_second = 2.0
	spear.range_px = 32.0
	spear.knockback = 70.0
	spear.combo_length = combo_length
	return spear


## Drives `handle_input` for `seconds` of physics frames with the attack button held down,
## exactly the way `Player._physics_process` drives it. The Player's own physics is switched
## off for the duration so the disabled `PlayerInput` cannot post a conflicting "not held".
func _hold_attack(seconds: float) -> void:
	_player.set_physics_process(false)
	var frames := int(ceilf(seconds * float(Engine.physics_ticks_per_second)))
	for i in range(frames):
		_wc.handle_input(Vector2.RIGHT, true, i == 0, false, false)
		await get_tree().physics_frame
	_player.set_physics_process(true)


func test_default_weapon_is_fists() -> void:
	assert_str(String(_wc.weapon.id)).is_equal("fists")
	assert_int(_wc.weapon.style).is_equal(WeaponBase.Style.MELEE_ARC)
	assert_float(_wc.weapon.base_damage).is_equal_approx(6.0, 0.001)
	assert_float(_wc.weapon.attacks_per_second).is_equal_approx(2.5, 0.001)
	assert_bool(_wc.sprite.visible).is_false()


func test_attack_interval_scales_with_attack_speed() -> void:
	var base := _wc.attack_interval()
	_player.stats.add_percent(&"attack_speed", &"test", 1.0)
	assert_float(_wc.attack_interval()).is_equal_approx(base / 2.0, 0.001)
	_player.stats.remove_owner(&"test")


func test_melee_swing_damages_dummy_in_front() -> void:
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(14, 0))) as Entity
	add_child(dummy)
	await PlayerTestHelpers.physics_frames(get_tree(), 2)
	var hits: Array[Node2D] = []
	var handler := func(target: Node2D, _info: DamageInfo) -> void: hits.append(target)
	EventBus.player_hit_dealt.connect(handler)
	assert_bool(_wc.try_attack(Vector2.RIGHT)).is_true()
	assert_bool(_wc.try_attack(Vector2.RIGHT)).override_failure_message("rate limited").is_false()
	await PlayerTestHelpers.physics_frames(get_tree(), 4)
	EventBus.player_hit_dealt.disconnect(handler)
	# Fists 6 dmg x (1 + 0.04 * 6 might) = 7.44 -> rounded 7
	assert_float(dummy.health.hp).is_equal_approx(93.0, 0.001)
	assert_array(hits).contains([dummy])
	assert_int(_wc.combo_index).is_equal(1)


func test_melee_does_not_hit_behind() -> void:
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(-16, 0))) as Entity
	add_child(dummy)
	await PlayerTestHelpers.physics_frames(get_tree(), 2)
	_player.weapon_pivot.rotation = 0.0
	_wc.try_attack(Vector2.RIGHT)
	await PlayerTestHelpers.physics_frames(get_tree(), 4)
	assert_float(dummy.health.hp).is_equal_approx(100.0, 0.001)


func test_combo_finisher_doubles_knockback() -> void:
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(14, 0))) as Entity
	add_child(dummy)
	_wc.combo_index = 0
	var first := _wc._melee_damage(dummy, 1.0)
	_wc.combo_index = _wc.weapon.combo_length - 1
	var last := _wc._melee_damage(dummy, 2.0)
	assert_float(last.knockback.length()).is_equal_approx(first.knockback.length() * 2.0, 0.01)


func test_bow_charge_scales_damage_and_full_charge_pierces() -> void:
	_wc.set_weapon(_bow())
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(200, 0))) as Entity
	add_child(dummy)
	var fired: Array[Projectile] = []
	var handler := func(p: Projectile) -> void: fired.append(p)
	_wc.projectile_fired.connect(handler)
	_wc.begin_charge()
	assert_bool(_wc.is_charging).is_true()
	_wc.charge_time = 0.0
	_wc.release_charge(Vector2.RIGHT)
	await get_tree().physics_frame
	assert_int(fired.size()).is_equal(1)
	var tap := fired[0]
	var tap_damage := tap.hitbox.build_info(dummy).amount
	assert_int(tap.pierce).is_equal(0)
	_wc._cooldown = 0.0
	_wc.begin_charge()
	_wc.charge_time = _wc.full_charge_time()
	_wc.release_charge(Vector2.RIGHT)
	await get_tree().physics_frame
	assert_int(fired.size()).is_equal(2)
	var full := fired[1]
	var full_damage := full.hitbox.build_info(dummy).amount
	assert_int(full.pierce).is_equal(1)
	var tuning := ItemTuning.shared()
	assert_float(full_damage / tap_damage).is_equal_approx(
		tuning.bow_full_damage_mult / tuning.bow_tap_damage_mult, 0.01
	)
	# 10 base x the full-charge multiplier x (1 + 0.04 * 2 precision)
	assert_float(full_damage).is_equal_approx(10.0 * tuning.bow_full_damage_mult * 1.08, 0.01)
	assert_float(full.speed).is_greater(tap.speed)
	_wc.projectile_fired.disconnect(handler)
	for p: Projectile in fired:
		if is_instance_valid(p):
			p.queue_free()


func test_projectile_count_and_bounce_flags() -> void:
	_wc.set_weapon(_bow())
	_player.stats.add_flat(&"projectile_count", &"test", 2.0)
	_player.flags["projectile_bounces"] = 1
	var fired: Array[Projectile] = []
	var handler := func(p: Projectile) -> void: fired.append(p)
	_wc.projectile_fired.connect(handler)
	_wc.begin_charge()
	_wc.release_charge(Vector2.UP)
	await get_tree().physics_frame
	_wc.projectile_fired.disconnect(handler)
	assert_int(fired.size()).is_equal(3)
	assert_int(fired[0].bounces).is_equal(1)
	assert_float(fired[0].direction.angle_to(fired[2].direction)).is_not_equal(0.0)
	for p: Projectile in fired:
		if is_instance_valid(p):
			p.queue_free()
	_player.stats.remove_owner(&"test")


func test_wand_bolt_homes_on_nearest_enemy() -> void:
	var wand := WeaponBase.new()
	wand.id = &"staff"
	wand.style = WeaponBase.Style.RANGED_WAND
	wand.base_damage = 8.0
	wand.attacks_per_second = 2.0
	_wc.set_weapon(wand)
	var far := auto_free(PlayerTestHelpers.make_dummy(Vector2(120, 0))) as Entity
	var near := auto_free(PlayerTestHelpers.make_dummy(Vector2(0, 50))) as Entity
	add_child(far)
	add_child(near)
	near.add_to_group(&"enemies")
	far.add_to_group(&"enemies")
	await PlayerTestHelpers.physics_frames(get_tree(), 2)
	var fired: Array[Projectile] = []
	var handler := func(p: Projectile) -> void: fired.append(p)
	_wc.projectile_fired.connect(handler)
	assert_bool(_wc.try_attack(Vector2.RIGHT)).is_true()
	_wc.projectile_fired.disconnect(handler)
	assert_int(fired.size()).is_equal(1)
	assert_float(fired[0].homing_strength).is_equal_approx(WeaponController.WAND_HOMING, 0.001)
	assert_object(fired[0].homing_target).is_same(near)
	fired[0].queue_free()


## Every player ranged attack used to render as a featureless 6x3 white rectangle tinted with the
## theme accent, while `assets/sprites/projectiles.png` shipped 16 frames of hand-drawn art that
## only enemies drew from. The tint was outside the documented tinting scope as well: docs §10
## puts projectiles with enemies and items, keeping "their own authored colours so factions and
## threats stay readable under any theme". No shipped weapon sets `projectile_scene`, so this
## path is what a bow actually looks like in the player's hands.
func test_a_player_shot_is_drawn_from_the_projectile_sheet_and_keeps_its_own_colours() -> void:
	_wc.set_weapon(_bow())
	var fired: Array[Projectile] = []
	var handler := func(p: Projectile) -> void: fired.append(p)
	_wc.projectile_fired.connect(handler)
	_wc.begin_charge()
	_wc.release_charge(Vector2.RIGHT)
	await get_tree().physics_frame
	_wc.projectile_fired.disconnect(handler)
	assert_int(fired.size()).is_equal(1)
	var shot := fired[0]
	var atlas := shot.sprite_texture as AtlasTexture
	(
		assert_object(atlas)
		. override_failure_message(
			"the bow shot is not drawn from assets/sprites/projectiles.png at all"
		)
		. is_not_null()
	)
	assert_str(atlas.atlas.resource_path).is_equal(ProjectileSprites.SHEET_PATH)
	var frame_width := atlas.region.size.x
	(
		assert_float(atlas.region.position.x)
		. override_failure_message("the bow shot is not the arrow frame")
		. is_equal_approx(float(ProjectileSprites.ARROW) * frame_width, 0.01)
	)
	(
		assert_that(shot.modulate)
		. override_failure_message(
			"the shot is tinted with the theme accent; docs §10 keeps projectiles authored"
		)
		. is_equal(Color.WHITE)
	)
	shot.queue_free()


## The frame table itself: the weapon's damage tag decides first, its style second.
func test_the_projectile_frame_follows_the_damage_tag_then_the_weapon_style() -> void:
	var wand := WeaponBase.new()
	wand.id = &"staff"
	wand.style = WeaponBase.Style.RANGED_WAND
	wand.tags = [DamageInfo.TAG_RANGED, DamageInfo.TAG_ARCANE]
	_wc.set_weapon(wand)
	assert_int(_wc._projectile_frame()).is_equal(ProjectileSprites.BOLT)
	var knives := WeaponBase.new()
	knives.id = &"knives"
	knives.style = WeaponBase.Style.THROWN
	knives.tags = [DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]
	_wc.set_weapon(knives)
	assert_int(_wc._projectile_frame()).is_equal(ProjectileSprites.KNIFE)
	var flame_bow := _bow()
	flame_bow.tags = [DamageInfo.TAG_RANGED, DamageInfo.TAG_FIRE]
	_wc.set_weapon(flame_bow)
	(
		assert_int(_wc._projectile_frame())
		. override_failure_message("a fire-tagged bow should look like fire, not like an arrow")
		. is_equal(ProjectileSprites.FIREBALL)
	)


## The property the art change must not cost. A 16x16 sprite where a 6x3 rectangle used to be is
## five times the picture, and nothing about the shot's reach, its hit circle or the damage it
## carries may follow the art: the collision shape is `Projectile.HIT_RADIUS` whatever is drawn
## on top of it.
func test_the_projectile_art_does_not_change_what_the_shot_hits() -> void:
	_wc.set_weapon(_bow())
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(60, 0))) as Entity
	add_child(dummy)
	dummy.add_to_group(&"enemies")
	await PlayerTestHelpers.physics_frames(get_tree(), 2)
	var before := dummy.health.hp
	var fired: Array[Projectile] = []
	var handler := func(p: Projectile) -> void: fired.append(p)
	_wc.projectile_fired.connect(handler)
	_wc.begin_charge()
	_wc.release_charge(Vector2.RIGHT)
	await get_tree().physics_frame
	_wc.projectile_fired.disconnect(handler)
	assert_int(fired.size()).is_equal(1)
	var circle: CircleShape2D = null
	for child: Node in fired[0].hitbox.get_children():
		var shape := child as CollisionShape2D
		if shape != null:
			circle = shape.shape as CircleShape2D
	(
		assert_object(circle)
		. override_failure_message("the shot has no hit circle at all")
		. is_not_null()
	)
	(
		assert_float(circle.radius)
		. override_failure_message("the shot's hit circle followed its art")
		. is_equal_approx(Projectile.HIT_RADIUS, 0.001)
	)
	for _i in range(40):
		await get_tree().physics_frame
		if dummy.health.hp < before:
			break
	(
		assert_float(dummy.health.hp)
		. override_failure_message("the redrawn bow shot no longer damages what it hits")
		. is_less(before)
	)


func test_atlas_index_by_name_then_style() -> void:
	var cane := WeaponBase.new()
	cane.id = &"golden_cane"
	_wc.set_weapon(cane)
	assert_int(_wc._atlas_index()).is_equal(10)
	var unknown := WeaponBase.new()
	unknown.id = &"mystery"
	unknown.style = WeaponBase.Style.RANGED_BOW
	_wc.set_weapon(unknown)
	assert_int(_wc._atlas_index()).is_equal(5)
	assert_bool(_wc.sprite.visible).is_true()
	assert_bool(_wc.sprite.region_enabled).is_true()


func test_equip_weapon_item_switches_controller() -> void:
	var item := ItemInstance.new()
	item.uid = 42
	item.base = _bow()
	_player.equip(item)
	assert_int(_wc.style()).is_equal(WeaponBase.Style.RANGED_BOW)
	assert_object(_wc.item).is_same(item)


func test_skill_override_is_used_for_secondary() -> void:
	var shared := ActiveAbility.new()
	shared.id = &"shared_skill"
	var copy := ActiveAbility.new()
	copy.id = &"copy_skill"
	var bow := _bow()
	bow.skill = shared
	_wc.set_weapon(bow)
	assert_object(_wc.skill).is_same(shared)
	_wc.set_weapon(bow, null, copy)
	assert_object(_wc.skill).is_same(copy)


func _knives() -> WeaponBase:
	var knives := WeaponBase.new()
	knives.id = &"throwing_knives"
	knives.style = WeaponBase.Style.THROWN
	knives.base_damage = 7.0
	knives.attacks_per_second = 2.0
	knives.projectile_speed = 180.0
	knives.tags = [DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]
	return knives


func test_thrown_shots_arc_with_engine_gravity() -> void:
	_wc.set_weapon(_knives())
	_wc.projectile_parent = self
	var fired: Array[Projectile] = []
	_wc.projectile_fired.connect(func(p: Projectile) -> void: fired.append(p))
	assert_bool(_wc.try_attack(Vector2.RIGHT)).is_true()
	assert_int(fired.size()).is_greater(0)
	var proj := fired[0]
	assert_float(proj.arc_gravity).is_equal_approx(WeaponController.THROWN_GRAVITY, 0.001)
	assert_bool(proj.rotate_to_direction).is_false()
	for p: Projectile in fired:
		p.queue_free()


func test_nearest_enemy_matches_the_enemy_group() -> void:
	var enemy := auto_free(Node2D.new()) as Node2D
	enemy.add_to_group(&"enemy")
	add_child(enemy)
	enemy.global_position = _player.global_position + Vector2(60, 0)
	var found := _wc.nearest_enemy(_player.global_position, WeaponController.ENEMY_SEARCH_RADIUS)
	assert_object(found).is_same(enemy)


# ---------------------------------------------------------------- bow charge model


func test_holding_the_attack_button_with_a_bow_keeps_firing_full_charges() -> void:
	# The blocker: `attack_pressed` started a draw and nothing ever released it, so a Ranger
	# holding LMB - the documented control model, docs 4.1 "attack is held-to-repeat", and
	# the class's own starting weapon - produced no shots at all, forever.
	_wc.set_weapon(_bow())
	_wc.projectile_parent = self
	var shots: Array[int] = []
	var handler := func(p: Projectile) -> void:
		shots.append(p.pierce)
		p.queue_free()
	_wc.projectile_fired.connect(handler)
	await _hold_attack(2.0)
	_wc.projectile_fired.disconnect(handler)
	(
		assert_int(shots.size())
		. override_failure_message("holding attack for 2 s with a bow fired nothing")
		. is_greater_equal(2)
	)
	# ... and every one of them is a full charge: a held button is a stream of real shots,
	# not a stream of taps.
	for pierce: int in shots:
		assert_int(pierce).override_failure_message("held shot was not a full charge").is_equal(1)


func test_attack_speed_shortens_the_bow_draw() -> void:
	_wc.set_weapon(_bow())
	var base := _wc.full_charge_time()
	assert_float(base).is_equal_approx(ItemTuning.shared().bow_charge_seconds, 0.05)
	_player.stats.add_percent(&"attack_speed", &"test", 1.0)
	assert_float(_wc.full_charge_time()).is_equal_approx(base / 2.0, 0.001)
	_player.stats.remove_owner(&"test")


func test_attack_speed_buys_a_bow_user_more_shots() -> void:
	# Attack speed used to be worth exactly nothing on a bow: the cycle was pinned by a hard
	# 0.6 s charge constant that no stat touched, so Swiftness, Overclock, Adrenaline and the
	# attack_speed affix were all dead weight on the Ranger's own weapon.
	_wc.set_weapon(_bow())
	_wc.projectile_parent = self
	var shots: Array[Projectile] = []
	var handler := func(p: Projectile) -> void:
		shots.append(p)
		p.queue_free()
	_wc.projectile_fired.connect(handler)
	await _hold_attack(2.0)
	var slow := shots.size()
	shots.clear()
	_wc.interrupt_charge()
	_wc._cooldown = 0.0
	_player.stats.add_percent(&"attack_speed", &"test", 1.0)
	await _hold_attack(2.0)
	_wc.projectile_fired.disconnect(handler)
	_player.stats.remove_owner(&"test")
	var fast := shots.size()
	assert_int(slow).is_greater(0)
	(
		assert_int(fast)
		. override_failure_message("x2 attack speed fired %d shots against %d" % [fast, slow])
		. is_greater_equal(int(ceilf(float(slow) * 1.7)))
	)


func test_releasing_early_still_fires_a_weak_tap_shot() -> void:
	_wc.set_weapon(_bow())
	_wc.projectile_parent = self
	var fired: Array[Projectile] = []
	var handler := func(p: Projectile) -> void: fired.append(p)
	_wc.projectile_fired.connect(handler)
	_player.set_physics_process(false)
	_wc.handle_input(Vector2.RIGHT, true, true, false, false)
	await get_tree().physics_frame
	assert_bool(_wc.is_charging).is_true()
	_wc.handle_input(Vector2.RIGHT, false, false, true, false)
	await get_tree().physics_frame
	_player.set_physics_process(true)
	_wc.projectile_fired.disconnect(handler)
	assert_int(fired.size()).is_equal(1)
	assert_int(fired[0].pierce).override_failure_message("a tap should not pierce").is_equal(0)
	fired[0].queue_free()


# ---------------------------------------------------------------- thrust combo


func test_thrust_weapons_run_a_combo_that_ends_in_a_knockback_finisher() -> void:
	# `combo_length` was dead data on every MELEE_THRUST weapon: `_thrust` hard-coded combo
	# index 0 and knockback x1, so dagger, stiletto, spear and glaive were a flat repeated poke.
	_wc.set_weapon(_thrust_weapon(3))
	var dummy := auto_free(PlayerTestHelpers.make_dummy(Vector2(20, 0))) as Entity
	add_child(dummy)
	var beats: Array[int] = []
	var handler := func(_style: WeaponBase.Style, index: int) -> void: beats.append(index)
	_wc.attacked.connect(handler)
	var knockbacks: Array[float] = []
	for _i in range(3):
		_wc._cooldown = 0.0
		assert_bool(_wc.try_attack(Vector2.RIGHT)).is_true()
		var info: DamageInfo = _wc.hitbox.damage_builder.call(dummy)
		knockbacks.append(info.knockback.length())
	_wc.attacked.disconnect(handler)
	assert_array(beats).override_failure_message("thrust never advanced its combo").is_equal(
		[0, 1, 2]
	)
	assert_int(_wc.combo_index).override_failure_message("finisher did not reset").is_equal(0)
	assert_float(knockbacks[1]).is_equal_approx(knockbacks[0], 0.01)
	(
		assert_float(knockbacks[2])
		. override_failure_message("the finishing thrust had no extra knockback")
		. is_equal_approx(knockbacks[0] * 2.0, 0.01)
	)


func test_thrust_finisher_costs_extra_recovery() -> void:
	_wc.set_weapon(_thrust_weapon(2))
	_wc._cooldown = 0.0
	_wc.try_attack(Vector2.RIGHT)
	var poke_recovery := _wc._cooldown
	_wc._cooldown = 0.0
	_wc.try_attack(Vector2.RIGHT)
	assert_float(_wc._cooldown).is_greater(poke_recovery)
	assert_float(_wc._cooldown).is_equal_approx(
		poke_recovery * WeaponController.FINISHER_RECOVERY, 0.001
	)


# ---------------------------------------------------------------- advertised range


func test_ranged_shots_stop_at_the_range_the_card_advertises() -> void:
	# `range_px` is printed on every weapon card ("200 rng") but ranged shots used a flat 2 s
	# lifetime, so a longbow's longer reach was a number on a card and nothing else.
	var bow := _bow()
	bow.range_px = 200.0
	bow.projectile_speed = 200.0
	_wc.set_weapon(bow)
	_wc.projectile_parent = self
	var fired: Array[Projectile] = []
	var handler := func(p: Projectile) -> void: fired.append(p)
	_wc.projectile_fired.connect(handler)
	_wc.begin_charge()
	_wc.release_charge(Vector2.RIGHT)
	await get_tree().physics_frame
	_wc.projectile_fired.disconnect(handler)
	assert_int(fired.size()).is_equal(1)
	var travel := fired[0].lifetime * fired[0].speed
	assert_float(travel).is_equal_approx(bow.range_px, 1.0)
	fired[0].queue_free()


## Builds a closed room of real WALL tiles under `_root`, interior tiles (2,2)-(9,9), so a
## shot fired from the middle meets the same TileMapLayer collision the game builds.
func _walled_room(root: Node2D) -> void:
	var data := FloorData.new()
	data.seed_value = 20250912
	data.biome = &"crypt"
	data.width = 12
	data.height = 12
	data.tiles.resize(data.width * data.height)
	data.tiles.fill(FloorData.Tile.VOID)
	var room := FloorData.Room.new()
	room.id = 0
	room.type = FloorData.RoomType.COMBAT
	room.rect = Rect2i(2, 2, 8, 8)
	for y in range(2, 10):
		for x in range(2, 10):
			data.set_tile(x, y, FloorData.Tile.FLOOR)
	for y in range(1, 11):
		for x in range(1, 11):
			if data.get_tile(x, y) == FloorData.Tile.VOID:
				data.set_tile(x, y, FloorData.Tile.WALL)
	data.rooms.append(room)
	data.start_room = 0
	data.stairs_room = 0
	data.boss_room = -1
	FloorBuilder.new().build(
		data, FloorBuilder.load_atlas("res://assets/tiles/crypt.png"), root, ThemePalette.fallback()
	)


## Fires one full-charge bow shot straight down from the middle of a real room and reports
## where it ended up. `bounces` is the `projectile_bounces` flag the ricochet passive sets.
func _shoot_at_the_floor_wall(bounces: int) -> Projectile:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	_walled_room(root)
	_player.global_position = Vector2(104.0, 88.0)
	_wc.set_weapon(_bow())
	_player.flags["projectile_bounces"] = bounces
	var fired: Array[Projectile] = []
	var handler := func(p: Projectile) -> void: fired.append(p)
	_wc.projectile_fired.connect(handler)
	await get_tree().physics_frame
	_wc.begin_charge()
	_wc.release_charge(Vector2.DOWN)
	await get_tree().physics_frame
	_wc.projectile_fired.disconnect(handler)
	assert_int(fired.size()).is_equal(1)
	return fired[0]


func test_a_bow_shot_stops_at_a_real_wall() -> void:
	# The wall path never fired at all: shots left the room and expired in the void outside it.
	var shot := await _shoot_at_the_floor_wall(0)
	# A lambda captures by value, so the death position comes back through a container.
	var grave: Array[Vector2] = []
	shot.expired.connect(func(p: Projectile) -> void: grave.append(p.global_position))
	for _i in range(60):
		await get_tree().physics_frame
		if not is_instance_valid(shot) or shot.is_queued_for_deletion():
			break
	assert_int(grave.size()).is_equal(1)
	# 160 is the inside face of the bottom wall; the shot must not be beyond it.
	assert_float(grave[0].y).is_less(160.0)
	assert_float(grave[0].y).is_greater(144.0)


func test_the_ricochet_flag_really_bounces_a_bow_shot_off_a_wall() -> void:
	# `RicochetPassive` promises "player projectiles bounce off walls", and every test it
	# shipped with only ever asserted `Projectile.bounces == 1` - the setting, not the bounce.
	var shot := await _shoot_at_the_floor_wall(1)
	assert_int(shot.bounces).is_equal(1)
	for _i in range(40):
		await get_tree().physics_frame
		if not is_instance_valid(shot):
			break
	assert_bool(is_instance_valid(shot)).is_true()
	assert_float(shot.direction.y).is_less(0.0)
	assert_float(shot.global_position.y).is_less(160.0)
	if is_instance_valid(shot):
		shot.queue_free()
