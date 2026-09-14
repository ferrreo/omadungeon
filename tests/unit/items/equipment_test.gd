class_name EquipmentTest
extends GdUnitTestSuite

var _registry: ItemRegistry


func before() -> void:
	_registry = ItemRegistry.load_default()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _snapshot(stats: Stats) -> Dictionary:
	var out: Dictionary = {}
	for stat: StringName in Stats.PRIMARY + Stats.SECONDARY:
		out[stat] = stats.get_value(stat)
	return out


func _item(slot: ItemBase.Slot, seed_value: int, rarity: int = -1) -> ItemInstance:
	return ItemGenerator.generate(_registry, 4, _rng(seed_value), 0.0, [slot], rarity)


func test_apply_and_remove_leave_stats_unchanged() -> void:
	var stats := Stats.new()
	stats.add_primary(&"might", 6)
	var before := _snapshot(stats)
	var eq := Equipment.new()
	var items: Array[ItemInstance] = [
		_item(ItemBase.Slot.WEAPON, 1, 3),
		_item(ItemBase.Slot.ARMOR, 2, 2),
		_item(ItemBase.Slot.RING, 3, 1),
		_item(ItemBase.Slot.RING, 4, 3),
		_item(ItemBase.Slot.TRINKET, 5, 2),
	]
	for item: ItemInstance in items:
		assert_object(eq.equip(item, stats)).is_null()
	assert_int(eq.items().size()).is_equal(5)
	assert_int(eq.empty_slots().size()).is_equal(0)
	assert_dict(_snapshot(stats)).is_not_equal(before)
	eq.clear(stats)
	assert_int(eq.items().size()).is_equal(0)
	assert_dict(_snapshot(stats)).is_equal(before)
	assert_int(eq.empty_slots().size()).is_equal(4)


func test_equip_replaces_and_returns_old_item() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var first := _item(ItemBase.Slot.WEAPON, 10, 0)
	var second := _item(ItemBase.Slot.WEAPON, 11, 1)
	eq.equip(first, stats)
	var replaced := eq.equip(second, stats)
	assert_object(replaced).is_same(first)
	assert_object(eq.get_item(&"weapon")).is_same(second)
	assert_object(eq.weapon()).is_same(second.base)
	assert_object(eq.weapon_skill()).is_not_null()
	assert_object(eq.weapon_skill()).is_not_same((second.base as WeaponBase).skill)
	var removed := eq.unequip(&"weapon", stats)
	assert_object(removed).is_same(second)
	assert_object(eq.weapon_skill()).is_null()
	assert_dict(_snapshot(stats)).is_equal(_snapshot(Stats.new()))


func test_rings_fill_both_slots_then_replace_first() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var a := _item(ItemBase.Slot.RING, 20)
	var b := _item(ItemBase.Slot.RING, 21)
	var c := _item(ItemBase.Slot.RING, 22)
	eq.equip(a, stats)
	eq.equip(b, stats)
	assert_object(eq.get_item(&"ring1")).is_same(a)
	assert_object(eq.get_item(&"ring2")).is_same(b)
	assert_str(String(eq.target_slot(c))).is_equal("ring1")
	assert_object(eq.equip(c, stats)).is_same(a)
	assert_object(eq.equip(_item(ItemBase.Slot.RING, 23), stats, &"ring2")).is_same(b)
	assert_object(eq.equip(_item(ItemBase.Slot.WEAPON, 24), stats, &"ring2")).is_null()


func test_compare_reports_deltas() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var armor := _registry.find_base(&"leather_jerkin")
	var item := ItemGenerator.instance_of(armor, _rng(1))
	var deltas := eq.compare(item, stats)
	assert_float(float(deltas.get(&"armor", 0.0))).is_equal(4.0)
	assert_float(float(deltas.get(&"swiftness", 0.0))).is_equal(1.0)
	assert_bool(deltas.has(&"move_speed")).is_true()
	assert_bool(deltas.has(&"might")).is_false()
	assert_dict(_snapshot(stats)).is_equal(_snapshot(Stats.new()))
	eq.equip(item, stats)
	var heavy := ItemGenerator.instance_of(_registry.find_base(&"iron_plate"), _rng(2))
	var swap := eq.compare(heavy, stats)
	assert_float(float(swap.get(&"armor", 0.0))).is_equal(7.0)
	assert_float(float(swap.get(&"swiftness", 0.0))).is_equal(-1.0)
	assert_dict(eq.compare(item, stats)).is_empty()


func test_dict_round_trip() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	eq.equip(_item(ItemBase.Slot.WEAPON, 30, 3), stats)
	eq.equip(_item(ItemBase.Slot.ARMOR, 31, 2), stats)
	eq.equip(_item(ItemBase.Slot.RING, 32, 1), stats)
	eq.equip(_item(ItemBase.Slot.TRINKET, 33, 3), stats)
	var data := eq.to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(data))
	var restored_stats := Stats.new()
	var restored := Equipment.from_dict(json as Dictionary, _registry, restored_stats)
	assert_dict(restored.to_dict()).is_equal(data)
	assert_dict(_snapshot(restored_stats)).is_equal(_snapshot(stats))
	assert_object(restored.weapon_skill()).is_not_null()
	assert_bool(restored.has_item(&"ring1")).is_true()
	assert_bool(restored.has_item(&"ring2")).is_false()


func test_unique_effect_signals() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var added: Array[PassiveAbility] = []
	var removed: Array[PassiveAbility] = []
	eq.unique_added.connect(func(p: PassiveAbility) -> void: added.append(p))
	eq.unique_removed.connect(func(p: PassiveAbility) -> void: removed.append(p))
	var legendary := _item(ItemBase.Slot.TRINKET, 40, 3)
	assert_str(String(legendary.unique_effect)).is_not_empty()
	eq.equip(legendary, stats)
	assert_int(added.size()).is_equal(1)
	assert_str(String(added[0].id)).is_equal(String(legendary.unique_effect))
	eq.equip(_item(ItemBase.Slot.TRINKET, 41, 0), stats)
	assert_int(removed.size()).is_equal(1)
	assert_object(removed[0]).is_same(added[0])


func test_on_hit_statuses_collected_and_rolled() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var weapon := ItemGenerator.instance_of(_registry.find_base(&"dagger"), _rng(1))
	weapon.affixes.append({"affix": _registry.find_affix(&"onhit_burn"), "value": 1.0})
	weapon.affixes.append({"affix": _registry.find_affix(&"might_flat"), "value": 2.0})
	eq.equip(weapon, stats)
	var listed := eq.on_hit_statuses()
	assert_int(listed.size()).is_equal(1)
	assert_int(int(listed[0]["kind"])).is_equal(StatusEffect.Kind.BURN)
	var rolled := eq.roll_on_hit_statuses(_rng(1))
	assert_int(rolled.size()).is_equal(1)
	assert_int(rolled[0].kind).is_equal(StatusEffect.Kind.BURN)
	assert_float(stats.get_value(&"might")).is_equal(2.0)


func test_event_bus_signals_emitted() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var slots: Array[StringName] = []
	var handler := func(slot: StringName, _item: RefCounted) -> void: slots.append(slot)
	EventBus.equipment_changed.connect(handler)
	eq.equip(_item(ItemBase.Slot.ARMOR, 50), stats)
	eq.unequip(&"armor", stats)
	EventBus.equipment_changed.disconnect(handler)
	assert_array(slots).contains_exactly([&"armor", &"armor"])


func test_restore_onto_saved_stats_does_not_stack_modifiers() -> void:
	# Player.restore_from_dict replays stats.from_dict (which already carries the item:<uid>
	# entries) and then Equipment.from_dict on the same Stats; equipping must be idempotent.
	var stats := Stats.new()
	stats.add_primary(&"might", 4)
	var eq := Equipment.new()
	eq.equip(_item(ItemBase.Slot.WEAPON, 60, 3), stats)
	eq.equip(_item(ItemBase.Slot.ARMOR, 61, 2), stats)
	eq.equip(_item(ItemBase.Slot.RING, 62, 1), stats)
	var before := _snapshot(stats)
	var saved_stats := stats.to_dict()
	var saved_equipment := eq.to_dict()
	for _pass in range(3):
		var restored_stats := Stats.new()
		restored_stats.from_dict(saved_stats.duplicate(true))
		var restored := Equipment.from_dict(saved_equipment, _registry, restored_stats)
		assert_dict(_snapshot(restored_stats)).is_equal(before)
		assert_int(restored.items().size()).is_equal(3)
	# Re-equipping the same instance twice on a live Stats is idempotent too.
	var weapon := eq.get_item(&"weapon")
	eq.equip(weapon, stats, &"weapon")
	assert_dict(_snapshot(stats)).is_equal(before)


func test_slots_dictionary_is_public() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var armor := _item(ItemBase.Slot.ARMOR, 70)
	eq.equip(armor, stats)
	var exposed: Variant = (eq as Object).get("slots")
	assert_bool(exposed is Dictionary).is_true()
	var dict := exposed as Dictionary
	assert_int(dict.size()).is_equal(1)
	assert_object(dict[&"armor"]).is_same(armor)
	eq.unequip(&"armor", stats)
	assert_bool((eq as Object).get("slots").is_empty()).is_true()


func test_unique_effect_is_hosted_on_the_player_when_nobody_claims_it() -> void:
	var world := auto_free(Node2D.new()) as Node2D
	add_child(world)
	var player := Entity.new()
	player.team = Layers.Team.PLAYER
	world.add_child(player)
	await get_tree().physics_frame
	var eq := Equipment.new()
	eq.bind(player)
	var legendary := ItemGenerator.instance_of(
		_registry.find_base(&"rabbits_foot"), _rng(80), ItemInstance.Rarity.LEGENDARY
	)
	legendary.unique_effect = &"fork_bomb"
	eq.equip(legendary, player.stats)
	var host := ItemUniqueHost.of(player)
	assert_object(host).is_not_null()
	assert_int(host.passives.size()).is_equal(1)
	# apply() ran on the player.
	assert_bool(player.has_meta(&"fork_bomb")).is_true()
	# and the hook arrives through EventBus.
	var fork := host.passives[0] as UniqueForkBomb
	var target := auto_free(Node2D.new()) as Node2D
	world.add_child(target)
	target.global_position = Vector2(30.0, 0.0)
	var info := DamageInfo.create(20.0, [DamageInfo.TAG_RANGED], player, Layers.Team.PLAYER)
	info.with_knockback(Vector2.RIGHT, 10.0)
	EventBus.player_hit_dealt.emit(target, info)
	assert_int(fork.forks_spawned).is_equal(2)
	eq.unequip(&"trinket", player.stats)
	assert_int(host.passives.size()).is_equal(0)
	assert_bool(player.has_meta(&"fork_bomb")).is_false()
	for _i in range(45):
		await get_tree().physics_frame
	player.queue_free()


func test_hosted_sudo_multiplies_damage_through_equipment() -> void:
	var world := auto_free(Node2D.new()) as Node2D
	add_child(world)
	var player := Entity.new()
	player.team = Layers.Team.PLAYER
	world.add_child(player)
	await get_tree().physics_frame
	var eq := Equipment.new()
	eq.bind(player)
	var legendary := ItemGenerator.instance_of(
		_registry.find_base(&"ring_iron"), _rng(81), ItemInstance.Rarity.LEGENDARY
	)
	legendary.unique_effect = &"sudo"
	eq.equip(legendary, player.stats)
	var grunt := auto_free(Entity.new()) as Entity
	var boss := auto_free(Node2D.new()) as Node2D
	boss.set_script(load("res://tests/unit/items/elite_dummy.gd"))
	var info := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], player, Layers.Team.PLAYER)
	assert_float(eq.outgoing_damage_multiplier(grunt, info)).is_equal(1.0)
	assert_float(eq.outgoing_damage_multiplier(boss, info)).is_equal(1.25)
	eq.clear(player.stats)
	assert_float(eq.outgoing_damage_multiplier(boss, info)).is_equal(1.0)
	player.queue_free()


## An explicit owner - and only an explicit owner - takes the unique passives off Equipment.
func test_a_declared_external_host_takes_ownership_of_uniques() -> void:
	var world := auto_free(Node2D.new()) as Node2D
	add_child(world)
	var player := Entity.new()
	player.team = Layers.Team.PLAYER
	world.add_child(player)
	await get_tree().physics_frame
	var eq := Equipment.new()
	eq.bind(player)
	eq.set_unique_host(true)
	var taken: Array[PassiveAbility] = []
	eq.unique_added.connect(func(p: PassiveAbility) -> void: taken.append(p))
	var legendary := ItemGenerator.instance_of(
		_registry.find_base(&"whetstone"), _rng(82), ItemInstance.Rarity.LEGENDARY
	)
	legendary.unique_effect = &"yacht"
	eq.equip(legendary, player.stats)
	assert_int(taken.size()).is_equal(1)
	assert_bool(eq.hosts_uniques_externally()).is_true()
	assert_object(ItemUniqueHost.of(player)).is_null()
	player.queue_free()


## The regression the flag exists for. Ownership used to be inferred from
## `unique_added.get_connections().size()`, so a listener that only wanted to watch - a HUD, a
## telemetry probe, a test - silently took the passive and the legendary went inert. docs
## TESTING.md forbids exactly this: "gameplay must never branch on a global signal's connection
## count or on any other cross-suite state".
func test_an_observer_on_the_signal_does_not_change_what_the_item_does() -> void:
	var world := auto_free(Node2D.new()) as Node2D
	add_child(world)
	var player := Entity.new()
	player.team = Layers.Team.PLAYER
	world.add_child(player)
	await get_tree().physics_frame
	var eq := Equipment.new()
	eq.bind(player)
	var watched: Array[PassiveAbility] = []
	eq.unique_added.connect(func(p: PassiveAbility) -> void: watched.append(p))
	var legendary := ItemGenerator.instance_of(
		_registry.find_base(&"whetstone"), _rng(82), ItemInstance.Rarity.LEGENDARY
	)
	legendary.unique_effect = &"yacht"
	eq.equip(legendary, player.stats)
	assert_int(watched.size()).is_equal(1)
	assert_bool(eq.hosts_uniques_externally()).is_false()
	var host := ItemUniqueHost.of(player)
	(
		assert_object(host)
		. override_failure_message("watching the signal stopped the legendary being installed")
		. is_not_null()
	)
	assert_int(host.passives.size()).is_equal(1)
	player.queue_free()


func test_same_unique_is_not_installed_twice() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var added: Array[PassiveAbility] = []
	eq.unique_added.connect(func(p: PassiveAbility) -> void: added.append(p))
	for seed_value: int in [90, 91]:
		var ring := ItemGenerator.instance_of(
			_registry.find_base(&"ring_iron"), _rng(seed_value), ItemInstance.Rarity.LEGENDARY
		)
		ring.unique_effect = &"omakase"
		eq.equip(ring, stats)
	assert_int(eq.uniques().size()).is_equal(1)
	assert_int(added.size()).is_equal(1)


# --------------------- a full ring family is a choice (owner report 8, round 3)


## With both ring slots worn, a third ring has two things it could displace, and the trade view
## has to be handed both. `target_slot()` answers `ring1` and only `ring1`, which is what made
## taking a third ring destroy Ring 1 in silence however the player answered.
func test_a_full_ring_family_offers_both_rings_as_candidates() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var ring_one := _item(ItemBase.Slot.RING, 3, 1)
	var ring_two := _item(ItemBase.Slot.RING, 4, 2)
	var offered := _item(ItemBase.Slot.RING, 5, 3)
	eq.equip(ring_one, stats)
	# One ring worn: the offer fills the free slot, so there is nothing to ask about.
	assert_array(eq.occupied_slots_for(offered)).is_empty()
	assert_array(eq.occupied_items_for(offered)).is_empty()
	assert_object(eq.worn_for(offered)).is_null()
	eq.equip(ring_two, stats)
	assert_array(eq.occupied_slots_for(offered)).contains_exactly([&"ring1", &"ring2"])
	assert_array(eq.occupied_items_for(offered)).contains_exactly([ring_one, ring_two])


## Single-slot families keep answering with the one slot they have, and never open a choice
## that does not exist.
func test_a_single_slot_family_has_exactly_one_candidate() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var worn := _item(ItemBase.Slot.WEAPON, 1, 2)
	var offered := _item(ItemBase.Slot.WEAPON, 2, 3)
	assert_array(eq.occupied_slots_for(offered)).is_empty()
	eq.equip(worn, stats)
	assert_array(eq.occupied_items_for(offered)).contains_exactly([worn])
	assert_object(eq.worn_for(offered)).is_equal(worn)


## The answer the picker gives back names a slot, and the second ring is reachable through it.
## `&""` means "the slot this would take anyway", so a caller can keep its own equip path for
## everything the choice does not change.
func test_the_players_answer_picks_the_ring_that_goes() -> void:
	var stats := Stats.new()
	var eq := Equipment.new()
	var ring_one := _item(ItemBase.Slot.RING, 3, 1)
	var ring_two := _item(ItemBase.Slot.RING, 4, 2)
	var offered := _item(ItemBase.Slot.RING, 5, 3)
	eq.equip(ring_one, stats)
	eq.equip(ring_two, stats)
	assert_str(eq.chosen_slot(offered, -1)).is_equal("")
	assert_str(eq.chosen_slot(offered, 0)).is_equal("")
	assert_str(eq.chosen_slot(offered, 1)).is_equal("ring2")
	assert_str(eq.chosen_slot(offered, 7)).is_equal("")
	var replaced := eq.equip(offered, stats, eq.chosen_slot(offered, 1))
	(
		assert_object(replaced)
		. override_failure_message("answering 'Ring 2' still took Ring 1 off")
		. is_equal(ring_two)
	)
	assert_object(eq.get_item(&"ring1")).is_equal(ring_one)
	assert_object(eq.get_item(&"ring2")).is_equal(offered)
