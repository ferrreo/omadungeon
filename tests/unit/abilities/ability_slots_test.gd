class_name AbilitySlotsTest
extends GdUnitTestSuite

## Every EventBus handler this suite connects goes through the probe, which hands them all back
## in after_test: an autoload signal outlives the suite, so a leaked lambda silently changes
## the result of whatever runs next (see tests/unit/tools/test_isolation_test.gd).
var _probe := EventBusProbe.new()

var _player: DummyPlayer
var _slots: AbilitySlots


func before_test() -> void:
	_player = auto_free(AbilityTestHelpers.make_player())
	add_child(_player)
	_slots = AbilityTestHelpers.attach_slots(_player)


func after_test() -> void:
	_probe.release()


func test_add_fills_slots_by_kind_then_refuses() -> void:
	assert_bool(_slots.add(AbilityTestHelpers.active(&"fireball"))).is_true()
	assert_bool(_slots.add(AbilityTestHelpers.active(&"frost_nova"))).is_true()
	assert_bool(_slots.add(AbilityTestHelpers.active(&"whirlwind"))).is_false()
	assert_bool(_slots.is_full(Ability.Kind.ACTIVE)).is_true()
	assert_bool(_slots.is_full(Ability.Kind.PASSIVE)).is_false()
	assert_bool(_slots.add(AbilityTestHelpers.passive(&"thorns"))).is_true()
	assert_bool(_slots.add(AbilityTestHelpers.passive(&"vampiric"))).is_true()
	assert_bool(_slots.add(AbilityTestHelpers.passive(&"hotkey"))).is_false()
	assert_int(_slots.all().size()).is_equal(4)
	assert_object(_slots.get_ability(0)).is_not_null()
	assert_str(String(_slots.get_ability(2).id)).is_equal("thorns")


func test_duplicate_tiers_up_to_max() -> void:
	_slots.add(AbilityTestHelpers.active(&"fireball"))
	assert_int(_slots.tier_of(&"fireball")).is_equal(1)
	assert_bool(_slots.add(AbilityTestHelpers.active(&"fireball"))).is_true()
	assert_int(_slots.tier_of(&"fireball")).is_equal(2)
	_slots.add(AbilityTestHelpers.active(&"fireball"))
	_slots.add(AbilityTestHelpers.active(&"fireball"))
	assert_int(_slots.tier_of(&"fireball")).is_equal(3)
	assert_int(_slots.all().size()).is_equal(1)


func test_passive_tier_up_reapplies_stats() -> void:
	_slots.add(AbilityTestHelpers.passive(&"glass_cannon"))
	assert_float(_player.stats.get_value(&"damage_melee")).is_equal_approx(0.4, 0.001)
	_slots.add(AbilityTestHelpers.passive(&"glass_cannon"))
	assert_float(_player.stats.get_value(&"damage_melee")).is_equal_approx(0.5, 0.001)
	assert_float(_player.stats.get_value(&"max_hp")).is_equal_approx(75.0, 0.001)


func test_replace_swaps_and_uninstalls_previous() -> void:
	_slots.add(AbilityTestHelpers.passive(&"glass_cannon"))
	_slots.add(AbilityTestHelpers.passive(&"thorns"))
	var previous := _slots.replace(2, AbilityTestHelpers.passive(&"vampiric"))
	assert_str(String(previous.id)).is_equal("glass_cannon")
	assert_str(String(_slots.get_ability(2).id)).is_equal("vampiric")
	assert_float(_player.stats.get_value(&"damage_melee")).is_equal_approx(0.0, 0.001)
	assert_float(_player.stats.get_value(&"max_hp")).is_equal_approx(100.0, 0.001)
	# A passive may be addressed by its index inside `passives` (what ChestUI hands back)
	# or by the unified index; both land in the same slot.
	assert_str(String(_slots.replace(0, AbilityTestHelpers.passive(&"hotkey")).id)).is_equal(
		"vampiric"
	)
	assert_str(String(_slots.get_ability(2).id)).is_equal("hotkey")


func test_replace_refuses_kind_mismatch_and_out_of_range() -> void:
	_slots.add(AbilityTestHelpers.active(&"fireball"))
	_slots.add(AbilityTestHelpers.passive(&"thorns"))
	# An active cannot go into a passive slot index.
	assert_object(_slots.replace(2, AbilityTestHelpers.active(&"frost_nova"))).is_null()
	assert_object(_slots.replace(-1, AbilityTestHelpers.passive(&"vampiric"))).is_null()
	(
		assert_object(
			_slots.replace(AbilitySlots.SLOT_COUNT, AbilityTestHelpers.passive(&"vampiric"))
		)
		. is_null()
	)
	assert_object(_slots.replace(99, AbilityTestHelpers.active(&"frost_nova"))).is_null()
	assert_str(String(_slots.get_ability(0).id)).is_equal("fireball")
	assert_str(String(_slots.get_ability(2).id)).is_equal("thorns")
	assert_bool(_slots.has(&"vampiric")).is_false()


func test_replace_with_owned_id_tiers_up_instead_of_duplicating() -> void:
	_slots.add(AbilityTestHelpers.passive(&"thorns"))
	_slots.add(AbilityTestHelpers.passive(&"vampiric"))
	assert_object(_slots.replace(0, AbilityTestHelpers.passive(&"vampiric"))).is_null()
	assert_int(_slots.tier_of(&"vampiric")).is_equal(2)
	assert_str(String(_slots.get_ability(2).id)).is_equal("thorns")


func test_would_need_replace_matches_replace_indices() -> void:
	var thorns := AbilityTestHelpers.passive(&"thorns")
	assert_array(_slots.would_need_replace(thorns)).is_empty()
	assert_array(_slots.would_need_replace(null)).is_empty()
	_slots.add(thorns)
	_slots.add(AbilityTestHelpers.passive(&"vampiric"))
	# Already owned: a tier-up, not a replace.
	assert_array(_slots.would_need_replace(AbilityTestHelpers.passive(&"thorns"))).is_empty()
	var options := _slots.would_need_replace(AbilityTestHelpers.passive(&"hotkey"))
	assert_int(options.size()).is_equal(2)
	assert_str(String((options[0] as Ability).id)).is_equal("thorns")
	# The array index ChestUI returns is what `replace` expects.
	var displaced := _slots.replace(1, AbilityTestHelpers.passive(&"hotkey"))
	assert_str(String(displaced.id)).is_equal("vampiric")
	assert_str(String(_slots.get_ability(3).id)).is_equal("hotkey")
	_slots.add(AbilityTestHelpers.active(&"fireball"))
	assert_array(_slots.would_need_replace(AbilityTestHelpers.active(&"frost_nova"))).is_empty()
	_slots.add(AbilityTestHelpers.active(&"frost_nova"))
	var active_options := _slots.would_need_replace(AbilityTestHelpers.active(&"whirlwind"))
	assert_int(active_options.size()).is_equal(2)
	assert_str(String((active_options[0] as Ability).id)).is_equal("fireball")


func test_add_at_max_tier_reports_failure() -> void:
	_slots.add(AbilityTestHelpers.active(&"fireball"))
	_slots.add(AbilityTestHelpers.active(&"fireball"))
	assert_bool(_slots.add(AbilityTestHelpers.active(&"fireball"))).is_true()
	assert_int(_slots.tier_of(&"fireball")).is_equal(3)
	assert_bool(_slots.add(AbilityTestHelpers.active(&"fireball"))).is_false()
	assert_int(_slots.tier_of(&"fireball")).is_equal(3)


func test_innates_are_uncounted_applied_and_hooked() -> void:
	_slots.add_innate(AbilityTestHelpers.passive(&"second_wind"))
	assert_bool(_slots.is_full(Ability.Kind.PASSIVE)).is_false()
	assert_int(_slots.all().size()).is_equal(0)
	assert_int(_slots.all_passives().size()).is_equal(1)
	assert_bool(_slots.has(&"second_wind")).is_true()
	assert_int(_slots.tier_of(&"second_wind")).is_equal(1)
	assert_dict(_slots.owned_tiers()).contains_keys([&"second_wind"])
	# Both passive slots stay free.
	assert_bool(_slots.add(AbilityTestHelpers.passive(&"thorns"))).is_true()
	assert_bool(_slots.add(AbilityTestHelpers.passive(&"vampiric"))).is_true()
	# Innate hooks fire: Second Wind boosts damage below 40% HP.
	_player.health.setup(100.0, false)
	_player.health.hp = 20.0
	var info := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], _player, _player.team)
	assert_float(_slots.outgoing_damage_multiplier(null, info)).is_greater(1.0)
	# A duplicate innate tiers up instead of stacking.
	_slots.add_innate(AbilityTestHelpers.passive(&"second_wind"))
	assert_int(_slots.tier_of(&"second_wind")).is_equal(2)
	assert_int(_slots.all_passives().size()).is_equal(3)


func test_uncounted_uniques_install_and_uninstall() -> void:
	var unique := AbilityTestHelpers.passive(&"glass_cannon")
	_slots.add_uncounted(unique)
	assert_float(_player.stats.get_value(&"damage_melee")).is_equal_approx(0.4, 0.001)
	assert_bool(_slots.is_full(Ability.Kind.PASSIVE)).is_false()
	_slots.remove_uncounted(unique)
	assert_float(_player.stats.get_value(&"damage_melee")).is_equal_approx(0.0, 0.001)
	assert_bool(_slots.has(&"glass_cannon")).is_false()


func test_passives_added_before_the_tree_apply_on_ready() -> void:
	var player: DummyPlayer = auto_free(AbilityTestHelpers.make_player())
	var slots: AbilitySlots = auto_free(AbilitySlots.new())
	slots.name = "AbilitySlots"
	slots.add(AbilityTestHelpers.passive(&"glass_cannon"))
	player.add_child(slots)
	add_child(player)
	assert_float(player.stats.get_value(&"damage_melee")).is_equal_approx(0.4, 0.001)


func test_add_never_mutates_the_shared_registry_resource() -> void:
	var registry := AbilityTestHelpers.registry()
	var shared := registry.find(&"fireball")
	assert_int(shared.tier).is_equal(1)
	_slots.add(shared)
	_slots.add(registry.find(&"fireball"))
	assert_int(_slots.tier_of(&"fireball")).is_equal(2)
	assert_int(shared.tier).is_equal(1)
	assert_int(registry.find(&"fireball").tier).is_equal(1)
	_slots.replace(0, registry.find(&"frost_nova"))
	assert_int(registry.find(&"frost_nova").tier).is_equal(1)


func test_shipped_scene_instantiates_the_node() -> void:
	var scene := load("res://src/abilities/ability_slots.tscn") as PackedScene
	assert_object(scene).is_not_null()
	var slots := auto_free(scene.instantiate()) as AbilitySlots
	assert_object(slots).is_not_null()
	assert_str(slots.name).is_equal(AbilitySlots.NODE_NAME)


func test_attach_creates_the_node_once() -> void:
	var player: DummyPlayer = auto_free(AbilityTestHelpers.make_player())
	add_child(player)
	var stream := RandomNumberGenerator.new()
	var slots := AbilitySlots.attach(player, stream)
	assert_object(slots).is_not_null()
	assert_object(slots.rng).is_same(stream)
	assert_object(AbilitySlots.attach(player)).is_same(slots)
	assert_object(player.get_node_or_null("AbilitySlots")).is_same(slots)


func test_slot_changed_signal_and_remove() -> void:
	var seen: Array = []
	_probe.watch(
		EventBus.ability_slot_changed,
		func(index: int, ability: Resource) -> void: seen.append([index, ability])
	)
	_slots.add(AbilityTestHelpers.active(&"fireball"))
	_slots.remove(0)
	_probe.release()
	assert_int(seen.size()).is_equal(2)
	assert_int(seen[0][0]).is_equal(0)
	assert_object(seen[1][1]).is_null()
	assert_object(_slots.get_ability(0)).is_null()


func test_try_use_starts_cooldown_with_reduction() -> void:
	_player.stats.add_primary(&"arcana", 10)  # 15% CDR
	var nova := AbilityTestHelpers.active(&"frost_nova")
	_slots.add(nova)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	assert_float(nova.cooldown_left).is_equal_approx(nova.cooldown * 0.85, 0.01)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_false()
	_slots._process(1.0)
	assert_float(nova.cooldown_left).is_equal_approx(nova.cooldown * 0.85 - 1.0, 0.01)
	assert_bool(_slots.try_use(1, Vector2.RIGHT)).is_false()
	assert_bool(_slots.try_use(2, Vector2.RIGHT)).is_false()


func test_try_use_blocked_while_stunned() -> void:
	_slots.add(AbilityTestHelpers.active(&"frost_nova"))
	_player.status.apply(StatusEffect.make(StatusEffect.Kind.STUN, 1.0, 0.0))
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_false()


func test_free_cast_skips_cooldown_and_stamps_power() -> void:
	var nova := AbilityTestHelpers.active(&"frost_nova")
	_slots.add(nova)
	_slots.free_cast_next = true
	_slots.free_cast_power = 1.25
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	assert_float(nova.cooldown_left).is_equal(0.0)
	assert_bool(_slots.free_cast_next).is_false()
	assert_float(_slots.cast_power(nova)).is_equal_approx(1.25, 0.001)
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	assert_float(_slots.cast_power(nova)).is_equal(1.0)


func test_next_hit_crit_buff_consumed_once() -> void:
	_slots.queue_next_hit(AbilitySlots.BUFF_CRIT)
	var info := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], _player, _player.team)
	assert_float(_slots.outgoing_damage_multiplier(null, info)).is_equal_approx(1.5, 0.001)
	assert_bool(info.is_crit).is_true()
	assert_bool(_slots.has_next_hit(AbilitySlots.BUFF_CRIT)).is_false()
	var again := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], _player, _player.team)
	assert_float(_slots.outgoing_damage_multiplier(null, again)).is_equal(1.0)
	assert_bool(again.is_crit).is_false()


func test_flags_write_into_owner_dictionary() -> void:
	_slots.set_flag(&"projectile_bounces", 1)
	assert_int(_player.flags.get("projectile_bounces", 0)).is_equal(1)
	assert_int(_slots.get_flag(&"projectile_bounces", 0)).is_equal(1)
	assert_bool(_slots.flags.has(&"projectile_bounces")).is_false()
	_slots.clear_flag(&"projectile_bounces")
	assert_bool(_player.flags.has(&"projectile_bounces")).is_false()


func test_flags_fall_back_to_local_without_owner_property() -> void:
	var plain: Entity = auto_free(Entity.new())
	plain.team = Layers.Team.PLAYER
	add_child(plain)
	var slots := AbilityTestHelpers.attach_slots(plain)
	slots.set_flag(&"trap_immune_dodge", true)
	assert_bool(slots.flags.get(&"trap_immune_dodge", false)).is_true()
	assert_bool(slots.get_flag(&"trap_immune_dodge", false)).is_true()


func test_hooks_dispatch_to_passives() -> void:
	var fireball := AbilityTestHelpers.active(&"fireball")
	_slots.add(fireball)
	_slots.add(AbilityTestHelpers.passive(&"hotkey"))
	_slots.add(AbilityTestHelpers.passive(&"adrenaline"))
	var enemy: DummyEnemy = auto_free(AbilityTestHelpers.make_enemy(Vector2(30, 0)))
	add_child(enemy)
	fireball.cooldown_left = 5.0
	EventBus.enemy_died.emit(enemy, enemy)  # not our kill
	assert_float(fireball.cooldown_left).is_equal(5.0)
	EventBus.enemy_died.emit(enemy, _player)
	assert_float(fireball.cooldown_left).is_equal_approx(5.0 - fireball.cooldown * 0.2, 0.001)
	EventBus.player_dodged.emit(&"roll")
	assert_float(_player.stats.get_value(&"attack_speed")).is_equal_approx(1.3, 0.001)


func test_dict_round_trip() -> void:
	var fireball := AbilityTestHelpers.active(&"fireball")
	fireball.tier = 2
	_slots.add(fireball)
	fireball.cooldown_left = 2.5
	var thorns := AbilityTestHelpers.passive(&"thorns")
	_slots.add(thorns)
	_slots.add(thorns)  # tier 2
	_slots.add(AbilityTestHelpers.passive(&"glass_cannon"))
	_slots.queue_next_hit(AbilitySlots.BUFF_CRIT)
	var data := _slots.to_dict()
	assert_str(JSON.stringify(data)).is_not_empty()
	var other: DummyPlayer = auto_free(AbilityTestHelpers.make_player())
	add_child(other)
	var restored := AbilityTestHelpers.attach_slots(other)
	restored.from_dict(JSON.parse_string(JSON.stringify(data)), AbilityTestHelpers.registry())
	assert_str(String(restored.get_ability(0).id)).is_equal("fireball")
	assert_int(restored.get_ability(0).tier).is_equal(2)
	assert_float((restored.get_ability(0) as ActiveAbility).cooldown_left).is_equal_approx(
		2.5, 0.001
	)
	assert_object(restored.get_ability(1)).is_null()
	assert_int(restored.tier_of(&"thorns")).is_equal(2)
	assert_int(restored.tier_of(&"glass_cannon")).is_equal(1)
	assert_float(other.stats.get_value(&"max_hp")).is_equal_approx(70.0, 0.001)
	assert_bool(restored.has_next_hit(AbilitySlots.BUFF_CRIT)).is_true()
	assert_dict(restored.owned_tiers()).is_equal(_slots.owned_tiers())
	assert_dict(restored.owned()).is_equal(_slots.owned_tiers())


func test_dict_round_trip_keeps_innates_free_cast_power_and_passive_state() -> void:
	var overflow := AbilityTestHelpers.passive(&"overflow") as OverflowPassive
	_slots.add_innate(overflow)
	_slots.add(AbilityTestHelpers.active(&"frost_nova"))
	_slots.try_use(0, Vector2.RIGHT)
	assert_int(overflow.casts).is_equal(1)
	_slots.free_cast_next = true
	_slots.free_cast_power = 1.25
	var data: Dictionary = JSON.parse_string(JSON.stringify(_slots.to_dict()))
	var other: DummyPlayer = auto_free(AbilityTestHelpers.make_player())
	add_child(other)
	var restored := AbilityTestHelpers.attach_slots(other)
	restored.from_dict(data, AbilityTestHelpers.registry())
	assert_bool(restored.free_cast_next).is_true()
	assert_float(restored.free_cast_power).is_equal_approx(1.25, 0.001)
	assert_bool(restored.has(&"overflow")).is_true()
	assert_int(restored.all().size()).is_equal(1)
	var restored_overflow := restored.all_passives()[0] as OverflowPassive
	assert_int(restored_overflow.casts).is_equal(1)
