class_name PassivesTest
extends GdUnitTestSuite

var _world: Node2D
var _player: DummyPlayer
var _slots: AbilitySlots


func before_test() -> void:
	_world = auto_free(Node2D.new())
	add_child(_world)
	_player = AbilityTestHelpers.make_player()
	_world.add_child(_player)
	_slots = AbilityTestHelpers.attach_slots(_player)


func _enemy(pos: Vector2) -> DummyEnemy:
	var e := AbilityTestHelpers.make_enemy(pos)
	_world.add_child(e)
	return e


func _info(amount: float, tags: Array[StringName], source: Entity) -> DamageInfo:
	var info := DamageInfo.create(amount, tags, source, source.team)
	info.applied = amount
	return info


func _stat_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for stat: StringName in Stats.PRIMARY + Stats.SECONDARY:
		out[stat] = _player.stats.get_value(stat)
	return out


func test_every_passive_applies_and_removes_cleanly() -> void:
	var before := _stat_snapshot()
	for id: StringName in AbilityRegistry.ICON_ORDER:
		var ability := AbilityTestHelpers.registry().instance(id)
		if ability.is_active():
			continue
		var passive := ability as PassiveAbility
		assert_bool(_slots.add(passive)).override_failure_message("add %s" % id).is_true()
		assert_object(_slots.remove(_slots.index_of(id))).is_same(passive)
		assert_dict(_stat_snapshot()).override_failure_message("%s left stats dirty" % id).is_equal(
			before
		)
		(
			assert_bool(_player.flags.is_empty())
			. override_failure_message("%s left flags" % id)
			. is_true()
		)


func test_thorns_reflects_melee_only() -> void:
	var attacker := _enemy(Vector2(20, 0))
	_slots.add(AbilityTestHelpers.passive(&"thorns"))
	_player.hurtbox.receive(AbilityTestHelpers.melee_hit(attacker, 30.0))
	assert_float(_player.health.hp).is_equal(70.0)
	# 5% of the player's own 100 max HP + 20% of the 30 damage taken.
	assert_float(attacker.health.hp).is_equal(89.0)
	var ranged: Array[StringName] = [DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]
	_player.hurtbox.receive(DamageInfo.create(10.0, ranged, attacker, attacker.team))
	assert_float(attacker.health.hp).is_equal(89.0)


func test_thorns_scales_with_the_players_own_pool_not_the_enemys_damage() -> void:
	# Thorns used to reflect nothing but a share of the incoming hit, which made it dead
	# content: it got *weaker* the better the build's mitigation got, and against a floor-5
	# elite (328 HP, hitting for 30) it took some fifty-five unmitigated hits to kill anything.
	var thorns := AbilityTestHelpers.passive(&"thorns") as ThornsPassive
	var small := thorns.retaliation_damage(100.0, 30.0)
	var tanky := thorns.retaliation_damage(200.0, 30.0)
	(
		assert_float(tanky)
		. override_failure_message("doubling max HP did not change what Thorns hits for")
		. is_greater(small)
	)
	assert_float(tanky).is_equal_approx(200.0 * 0.05 + 30.0 * 0.2, 0.001)
	# A build that takes half the damage still retaliates for most of what it did before.
	assert_float(thorns.retaliation_damage(200.0, 15.0)).is_greater(tanky * 0.6)
	# Tiers move both halves.
	thorns.tier = 3
	assert_float(thorns.retaliation_damage(200.0, 30.0)).is_greater(tanky * 1.9)


func test_thorns_is_worth_taking_against_an_elite() -> void:
	# The playtest measure: a 200 HP build standing in front of a 328 HP floor-5 elite that
	# hits for 30. Under the old model that was ~55 hits of pure reflection; anything that
	# needs more than a fight's worth of hits is not a card, it is a decoration.
	var thorns := AbilityTestHelpers.passive(&"thorns") as ThornsPassive
	var per_hit := thorns.retaliation_damage(200.0, 30.0)
	assert_int(int(ceilf(328.0 / per_hit))).is_less_equal(25)


func test_glass_cannon_trades_hp_for_damage() -> void:
	_slots.add(AbilityTestHelpers.passive(&"glass_cannon"))
	assert_float(_player.stats.get_value(&"damage_ranged")).is_equal_approx(0.4, 0.001)
	assert_float(_player.stats.get_value(&"damage_ability")).is_equal_approx(0.4, 0.001)
	assert_float(_player.health.max_hp).is_equal_approx(70.0, 0.001)
	_slots.remove(2)
	assert_float(_player.health.max_hp).is_equal_approx(100.0, 0.001)


func test_vampiric_heals_on_hit_dealt() -> void:
	var enemy := _enemy(Vector2(20, 0))
	_player.health.hp = 50.0
	_slots.add(AbilityTestHelpers.passive(&"vampiric"))
	EventBus.player_hit_dealt.emit(enemy, _info(40.0, [DamageInfo.TAG_MELEE], _player))
	assert_float(_player.health.hp).is_equal_approx(51.2, 0.001)
	# Hits from someone else do not feed us.
	EventBus.player_hit_dealt.emit(_player, _info(40.0, [DamageInfo.TAG_MELEE], enemy))
	assert_float(_player.health.hp).is_equal_approx(51.2, 0.001)


func test_tiling_wm_needs_three_aligned() -> void:
	var tiling := AbilityTestHelpers.passive(&"tiling_wm")
	_slots.add(tiling)
	_enemy(Vector2(30, 4))
	_enemy(Vector2(60, -8))
	var info := _info(10.0, [DamageInfo.TAG_MELEE], _player)
	assert_float(_slots.outgoing_damage_multiplier(null, info)).is_equal(1.0)
	_enemy(Vector2(90, 12))
	# data/abilities/tiling_wm.tres: bonus 0.3 at tier 1 ("+30% damage" on the card).
	assert_float(_slots.outgoing_damage_multiplier(null, info)).is_equal_approx(1.30, 0.001)
	_slots.remove(2)
	_enemy(Vector2(0, 40))
	_enemy(Vector2(0, 80))
	_enemy(Vector2(0, 120))
	_enemy(Vector2(0, 160))
	assert_float(_slots.outgoing_damage_multiplier(null, info)).is_equal(1.0)


func test_dotfiles_raises_lowest_primary_per_item() -> void:
	_player.stats.add_primary(&"vitality", 5)
	var equipment := _player.equipment as DummyEquipment
	equipment.slots[&"weapon"] = "sword"
	equipment.slots[&"ring1"] = "ring"
	assert_int(DotfilesPassive.equipped_count(_player)).is_equal(2)
	_slots.add(AbilityTestHelpers.passive(&"dotfiles"))
	# All points land on the single lowest primary, they are not spread across several.
	assert_int(_player.stats.primary(&"might")).is_equal(2)
	assert_int(_player.stats.primary(&"precision")).is_equal(0)
	assert_int(_player.stats.primary(&"vitality")).is_equal(5)
	equipment.slots[&"armor"] = "vest"
	EventBus.item_equipped.emit(null, &"armor")
	assert_int(_player.stats.primary(&"might")).is_equal(3)
	_slots.remove(2)
	assert_int(_player.stats.primary(&"might")).is_equal(0)
	EventBus.item_equipped.emit(null, &"armor")
	assert_int(_player.stats.primary(&"might")).is_equal(0)


func test_dotfiles_counts_the_real_equipment_contract() -> void:
	var equipment := Equipment.new()
	var player: DummyPlayer = auto_free(AbilityTestHelpers.make_player())
	add_child(player)
	var slots := AbilityTestHelpers.attach_slots(player)
	player.equipment = equipment
	var registry := load("res://data/items/registry.tres") as ItemRegistry
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var item := ItemGenerator.generate(registry, 0, rng, 0.0)
	equipment.equip(item, null)
	assert_int(equipment.items().size()).is_equal(1)
	assert_int(DotfilesPassive.equipped_count(player)).is_equal(1)
	slots.add(AbilityTestHelpers.passive(&"dotfiles"))
	var total := 0
	for stat: StringName in Stats.PRIMARY:
		total += player.stats.primary(stat)
	assert_int(total).is_equal(1)


func test_lucky_coin_ricochet_and_buyout_set_flags_run_manager_reads() -> void:
	_slots.add(AbilityTestHelpers.passive(&"lucky_coin"))
	_slots.add(AbilityTestHelpers.passive(&"ricochet"))
	assert_bool(_player.flags[&"free_reroll_per_floor"]).is_true()
	assert_float(_player.stats.get_value(&"luck")).is_greater(0.0)
	assert_int(_player.flags[&"projectile_bounces"]).is_equal(1)
	_slots.replace(2, AbilityTestHelpers.passive(&"buyout"))
	assert_bool(_player.flags.has(&"free_reroll_per_floor")).is_false()
	assert_float(_player.stats.get_value(&"luck")).is_equal(0.0)
	assert_bool(_player.flags[&"chest_extra_option"]).is_true()
	assert_bool(_player.flags[&"chest_costs_gold"]).is_true()
	assert_float(_player.stats.get_value(&"gold_find")).is_equal_approx(0.5, 0.001)
	_slots.replace(3, AbilityTestHelpers.passive(&"thorns"))
	assert_bool(_player.flags.has(&"projectile_bounces")).is_false()


## "The gold in hand is itself damage" (docs §4.3) has to include the gold the Oligarch starts
## the run holding, and it did not. `_gold` is fed only by `EventBus.gold_changed`, and
## `Player.apply_class()` announces the 150 starting gold *before* the innate is granted - so the
## one class built around its purse spent the opening floor with that purse priced at nothing and
## only caught up on the first coin it picked up. The balance model has always assumed otherwise
## (`SimPlayer.create()` sets `gold` from `def.start_gold` before folding the effect), and the
## live calibration is what caught the two sides disagreeing. The grant order here is the one
## `RunManager._setup_player()` uses, because the order is the bug.
func test_buyout_prices_the_gold_the_player_is_already_holding() -> void:
	var live := auto_free(PlayerTestHelpers.make_player()) as Player
	_world.add_child(live)
	live.apply_class(PlayerTestHelpers.load_class("oligarch"))
	await get_tree().physics_frame
	assert_int(live.gold).is_greater(0)
	var slots := AbilityUtil.slots_of(live)
	assert_object(slots).is_not_null()
	var buyout := AbilityTestHelpers.passive(&"buyout") as BuyoutPassive
	slots.add_innate(buyout)
	(
		assert_float(buyout.wealth_bonus())
		. override_failure_message(
			(
				(
					"the Oligarch holds %d gold and Buyout prices it at nothing, so its innate pays"
					+ " out only after the first coin it picks up"
				)
				% live.gold
			)
		)
		. is_greater(0.0)
	)
	(
		assert_float(1.0 + buyout.wealth_bonus())
		. override_failure_message("the live purse and wealth_multiplier() disagree")
		. is_equal_approx(buyout.wealth_multiplier(live.gold), 0.0001)
	)


## The property that must not follow from it: a purse the player does not have is worth nothing.
## Reading gold at apply time is a read, not a gift - a class with no starting gold gets no
## damage from Buyout until it earns some, and removing the passive forgets the purse again.
func test_buyout_is_worth_nothing_to_a_player_carrying_no_gold() -> void:
	var live := auto_free(PlayerTestHelpers.make_player()) as Player
	_world.add_child(live)
	live.apply_class(PlayerTestHelpers.load_class("fighter"))
	await get_tree().physics_frame
	assert_int(live.gold).is_equal(0)
	var slots := AbilityUtil.slots_of(live)
	var buyout := AbilityTestHelpers.passive(&"buyout") as BuyoutPassive
	slots.add_innate(buyout)
	assert_float(buyout.wealth_bonus()).is_equal(0.0)
	live.add_gold(400)
	assert_float(buyout.wealth_bonus()).is_greater(0.0)
	buyout.remove(live)
	assert_float(buyout.wealth_bonus()).is_equal(0.0)


func test_heavy_hands_scales_melee_knockback_only() -> void:
	_slots.add(AbilityTestHelpers.passive(&"heavy_hands"))
	var melee := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], _player, _player.team)
	melee.with_knockback(Vector2.RIGHT, 50.0)
	assert_float(_slots.outgoing_damage_multiplier(null, melee)).is_equal(1.0)
	# data/abilities/heavy_hands.tres: multiplier 3.0 ("Melee knockback x3" on the card).
	assert_float(melee.knockback.x).is_equal_approx(150.0, 0.001)
	var ranged := DamageInfo.create(10.0, [DamageInfo.TAG_RANGED], _player, _player.team)
	ranged.with_knockback(Vector2.RIGHT, 50.0)
	_slots.outgoing_damage_multiplier(null, ranged)
	assert_float(ranged.knockback.x).is_equal_approx(50.0, 0.001)
	# Tier 2 scales it further.
	_slots.add(AbilityTestHelpers.passive(&"heavy_hands"))
	var tier2 := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], _player, _player.team)
	tier2.with_knockback(Vector2.RIGHT, 50.0)
	_slots.outgoing_damage_multiplier(null, tier2)
	# 3.0 + 0.75 per tier above 1.
	assert_float(tier2.knockback.x).is_equal_approx(187.5, 0.001)


func test_ricochet_flag_reaches_ability_projectiles() -> void:
	_slots.add(AbilityTestHelpers.passive(&"ricochet"))
	_slots.add(AbilityTestHelpers.active(&"volley"))
	_slots.try_use(0, Vector2.RIGHT)
	var found := false
	for child: Node in _world.get_children():
		if child is Projectile:
			found = true
			assert_int((child as Projectile).bounces).is_equal(1)
	assert_bool(found).is_true()


func test_adrenaline_surges_after_dodge_then_fades() -> void:
	var adrenaline := AbilityTestHelpers.passive(&"adrenaline") as AdrenalinePassive
	adrenaline.duration = 0.2
	_slots.add(adrenaline)
	assert_float(_player.stats.get_value(&"attack_speed")).is_equal_approx(1.0, 0.001)
	EventBus.player_dodged.emit(&"roll")
	assert_bool(adrenaline.is_surging()).is_true()
	assert_float(_player.stats.get_value(&"attack_speed")).is_equal_approx(1.3, 0.001)
	await await_millis(400)
	assert_bool(adrenaline.is_surging()).is_false()
	assert_float(_player.stats.get_value(&"attack_speed")).is_equal_approx(1.0, 0.001)


func test_hotkey_refunds_cooldowns_on_kill() -> void:
	var enemy := _enemy(Vector2(20, 0))
	var fireball := AbilityTestHelpers.active(&"fireball")
	var nova := AbilityTestHelpers.active(&"frost_nova")
	_slots.add(fireball)
	_slots.add(nova)
	_slots.add(AbilityTestHelpers.passive(&"hotkey"))
	fireball.cooldown_left = 6.0
	nova.cooldown_left = 1.0
	EventBus.enemy_died.emit(enemy, _player)
	assert_float(fireball.cooldown_left).is_equal_approx(6.0 - 6.0 * 0.2, 0.001)
	assert_float(nova.cooldown_left).is_equal(0.0)


func test_second_wind_only_below_threshold() -> void:
	_slots.add(AbilityTestHelpers.passive(&"second_wind"))
	var info := _info(10.0, [DamageInfo.TAG_MELEE], _player)
	assert_float(_slots.outgoing_damage_multiplier(null, info)).is_equal(1.0)
	_player.health.hp = 30.0
	assert_float(_slots.outgoing_damage_multiplier(null, info)).is_equal_approx(1.25, 0.001)


func test_sure_footed_speed_and_flag() -> void:
	var base := _player.stats.get_value(&"move_speed")
	_slots.add(AbilityTestHelpers.passive(&"sure_footed"))
	assert_float(_player.stats.get_value(&"move_speed")).is_equal_approx(base * 1.1, 0.01)
	assert_bool(_player.flags[&"trap_immune_dodge"]).is_true()
	_slots.remove(2)
	assert_float(_player.stats.get_value(&"move_speed")).is_equal_approx(base, 0.01)
	assert_bool(_player.flags.has(&"trap_immune_dodge")).is_false()


func test_overflow_makes_every_fourth_cast_free_and_stronger() -> void:
	var nova := AbilityTestHelpers.active(&"frost_nova")
	_slots.add(nova)
	_slots.add(AbilityTestHelpers.passive(&"overflow"))
	for i in range(3):
		nova.cooldown_left = 0.0
		assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
		assert_float(nova.cooldown_left).is_greater(0.0)
	assert_bool(_slots.free_cast_next).is_true()
	nova.cooldown_left = 0.0
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	assert_float(nova.cooldown_left).is_equal(0.0)
	assert_float(_slots.cast_power(nova)).is_equal_approx(1.25, 0.001)
	assert_bool(_slots.free_cast_next).is_false()
	assert_bool(_slots.try_use(0, Vector2.RIGHT)).is_true()
	assert_float(nova.cooldown_left).is_greater(0.0)
	assert_float(_slots.cast_power(nova)).is_equal(1.0)


func test_overflow_power_reaches_ability_damage() -> void:
	var nova := AbilityTestHelpers.active(&"frost_nova")
	_slots.add(nova)
	_slots.rng.seed = 1
	_slots.add(AbilityTestHelpers.passive(&"overflow"))
	_player.stats.set_base(&"crit_chance", 0.0)
	var tags: Array[StringName] = [DamageInfo.TAG_ABILITY]
	var plain := AbilityUtil.make_damage(_player, nova, tags, Vector2.RIGHT, 0.0)
	assert_float(plain.amount).is_equal_approx(nova.damage, 0.001)
	_slots.free_cast_next = true
	_slots.free_cast_power = 1.25
	_slots.try_use(0, Vector2.RIGHT)
	var boosted := AbilityUtil.make_damage(_player, nova, tags, Vector2.RIGHT, 0.0)
	assert_float(boosted.amount).is_equal_approx(nova.damage * 1.25, 0.001)
