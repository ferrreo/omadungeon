## End-to-end integration for the drop site and the Ranger dodge (docs §4.3, §7): gold-find
## applied to dropped gold, the elite's guaranteed Rare+ item pickup, and the caltrop patch
## the dash leaves behind. `manage_scenes` is off so the gdUnit runner's scene survives.
class_name DropsAndDodgeIntegrationTest
extends GdUnitTestSuite

const SEED := 616161
## An ordinary (non-elite) enemy with a gold range, and an elite one.
const MOOK_ID := &"honker"
const ELITE_ID := &"kernel_panic"


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
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


# ---------------------------------------------------------------- gold find (docs §4.3)


func test_gold_find_multiplies_dropped_gold() -> void:
	var live := await _start(&"fighter")
	var def := RunManager.enemy_registry.find(MOOK_ID)
	assert_object(def).is_not_null()
	assert_int(def.gold_max).is_greater(0)

	var plain := await _drop_gold(def, live, 0.0)
	var rich := await _drop_gold(def, live, 1.0)
	assert_int(plain.gold).is_greater(0)
	# +100% gold find has to be visible in the coins that actually hit the floor.
	assert_int(rich.gold).is_greater(plain.gold)
	assert_float(rich.multiplier - plain.multiplier).is_equal_approx(1.0, 0.001)
	assert_float(rich.gold / float(plain.gold)).is_greater(1.8)


func test_oligarch_buyout_feeds_the_same_gold_find_stat() -> void:
	var live := await _start(&"oligarch")
	# Docs §4.3 "Enemies drop +30% gold": the innate rides `gold_find`, which the drop reads.
	assert_float(live.stats.get_value(&"gold_find")).is_greater(0.29)
	var def := RunManager.enemy_registry.find(MOOK_ID)
	var enemy := await _spawn(def, 0)
	assert_float(enemy.gold_find_multiplier()).is_greater(1.29)


# ---------------------------------------------------------------- elite drop (docs §7)


func test_elite_drops_a_rare_or_better_item_the_player_chooses_to_take() -> void:
	var live := await _start(&"fighter")
	var def := RunManager.enemy_registry.find(ELITE_ID)
	assert_object(def).is_not_null()
	assert_bool(def.is_elite).is_true()
	var enemy := await _spawn(def, 4, Vector2(600, 0))
	enemy.call(&"_drop_loot")
	await _frames(2)

	var pickups := _item_pickups()
	assert_int(pickups.size()).is_equal(1)
	var drop := pickups[0]
	assert_object(drop.item).is_not_null()
	assert_int(drop.item.rarity).is_greater_equal(int(ItemInstance.Rarity.RARE))

	var gear := live.equipment as Equipment
	var offered := drop.item
	var slot_name := gear.target_slot(offered)
	var before := gear.get_item(slot_name)
	# Standing on it changes nothing: an item never equips itself (playtest blocker).
	await _physics_frames(30)
	assert_bool(is_instance_valid(drop)).is_true()
	drop.global_position = live.global_position
	await _physics_frames(20)
	assert_bool(is_instance_valid(drop)).is_true()
	assert_object(gear.get_item(slot_name)).is_same(before)

	# Interacting with it is what equips it, and nothing worn is destroyed by the swap.
	assert_bool(Interactable.dispatch(live)).is_true()
	await _frames(2)
	var after := gear.get_item(slot_name)
	assert_object(after).is_not_equal(before)
	assert_int(after.uid).is_equal(offered.uid)
	if before != null:
		var left := _item_pickups()
		assert_int(left.size()).is_equal(1)
		assert_int(left[0].item.uid).is_equal(before.uid)


func test_ordinary_enemies_drop_no_item() -> void:
	await _start(&"fighter")
	var enemy := await _spawn(RunManager.enemy_registry.find(MOOK_ID), 4)
	enemy.call(&"_drop_loot")
	await _frames(2)
	assert_array(_item_pickups()).is_empty()


# ---------------------------------------------------------------- caltrops (docs §4.3)


func test_ranger_dash_leaves_a_caltrop_patch() -> void:
	var live := await _start(&"ranger")
	assert_int(live.dodge_style).is_equal(int(ClassDef.DodgeStyle.DASH))
	assert_int(_caltrops(live).size()).is_equal(0)
	assert_bool(live.try_dodge(Vector2.RIGHT)).is_true()
	await _frames(2)
	var pads := _caltrops(live)
	assert_int(pads.size()).is_equal(Player.CALTROP_COUNT)
	for pad: Hitbox in pads:
		# Player-team hazards: they cannot touch the Ranger who dropped them.
		assert_int(pad.team).is_equal(int(Layers.Team.PLAYER))
		assert_bool(pad.tags.has(DamageInfo.TAG_TRAP)).is_true()
	# The patch trails along the dash line, not in a single spot.
	assert_float(pads[0].global_position.distance_to(pads[-1].global_position)).is_greater(8.0)


func test_caltrops_damage_an_enemy_that_walks_over_them() -> void:
	var live := await _start(&"ranger")
	var pads := live.drop_caltrops(Player.DASH_DISTANCE)
	assert_int(pads.size()).is_equal(Player.CALTROP_COUNT)
	await _frames(2)
	var dummy := Entity.new()
	dummy.team = Layers.Team.ENEMY
	live.get_parent().add_child(dummy)
	dummy.global_position = pads[0].global_position
	await _physics_frames(1)
	var full := dummy.health.hp
	await _physics_frames(8)
	assert_float(dummy.health.hp).is_less(full)
	dummy.queue_free()


func test_other_classes_leave_no_caltrops() -> void:
	var live := await _start(&"fighter")
	assert_bool(live.try_dodge(Vector2.RIGHT)).is_true()
	await _frames(2)
	assert_int(_caltrops(live).size()).is_equal(0)


# ---------------------------------------------------------------- sustain (docs §4.2)


func test_lifesteal_returns_a_fraction_of_the_damage_dealt() -> void:
	var live := await _start(&"fighter")
	live.health.hp = live.health.max_hp * 0.5
	var hurt := live.health.hp
	var info := DamageInfo.create(40.0, [DamageInfo.TAG_MELEE], live, Layers.Team.PLAYER)
	info.applied = 40.0
	# Nothing rolled the stat yet, so the same hit heals nothing.
	EventBus.player_hit_dealt.emit(live, info)
	assert_float(live.health.hp).is_equal_approx(hurt, 0.01)
	live.stats.add_flat(&"lifesteal", &"test", 0.5)
	EventBus.player_hit_dealt.emit(live, info)
	assert_float(live.health.hp).is_equal_approx(hurt + 20.0, 0.01)


func test_life_on_kill_heals_only_the_player_who_landed_the_kill() -> void:
	var live := await _start(&"fighter")
	live.health.hp = live.health.max_hp * 0.5
	live.stats.add_flat(&"life_on_kill", &"test", 12.0)
	var hurt := live.health.hp
	var victim := await _spawn(RunManager.enemy_registry.find(MOOK_ID), 0, Vector2(400, 0))
	victim.health.take_damage(
		DamageInfo.create(99999.0, [DamageInfo.TAG_TRUE], live, Layers.Team.PLAYER)
	)
	await _frames(4)
	assert_float(live.health.hp).is_equal_approx(hurt + 12.0, 0.01)

	var healed := live.health.hp
	var other := await _spawn(RunManager.enemy_registry.find(MOOK_ID), 0, Vector2(-400, 0))
	other.health.take_damage(
		DamageInfo.create(99999.0, [DamageInfo.TAG_TRUE], null, Layers.Team.NEUTRAL)
	)
	await _frames(4)
	assert_float(live.health.hp).is_equal_approx(healed, 0.01)


# ---------------------------------------------------------------- helpers


func _start(class_id: StringName) -> Player:
	assert_bool(RunManager.new_run(SEED, class_id)).is_true()
	await _frames(4)
	var live := RunManager.player()
	assert_object(live).is_not_null()
	live.health.invulnerable = true
	return live


func _spawn(def: EnemyDef, floor_index: int, offset := Vector2.ZERO) -> EnemyBase:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var live := RunManager.player()
	var pos := live.global_position + offset
	var enemy := EnemySpawner.instantiate(def, floor_index, pos, rng)
	assert_object(enemy).is_not_null()
	RunManager.floor_root().add_child(enemy)
	enemy.global_position = pos
	await _frames(2)
	return enemy


## Kills `def`'s loot roll once with the player's `gold_find` set to `bonus`, returning the
## gold that actually reached the floor plus the multiplier the drop site used.
func _drop_gold(def: EnemyDef, live: Player, bonus: float) -> DropSample:
	live.stats.remove_owner(&"test")
	if bonus > 0.0:
		live.stats.add_flat(&"gold_find", &"test", bonus)
	var enemy := await _spawn(def, 0)
	var sample := DropSample.new()
	sample.multiplier = enemy.gold_find_multiplier()
	var total: Array[int] = [0]
	var tally := func(kind: StringName, _pos: Vector2, amount: int) -> void:
		if kind == &"gold":
			total[0] += amount
	EventBus.spawn_pickup.connect(tally)
	enemy.call(&"_drop_loot")
	EventBus.spawn_pickup.disconnect(tally)
	sample.gold = total[0]
	enemy.queue_free()
	await _frames(2)
	return sample


func _item_pickups() -> Array[ItemPickup]:
	var out: Array[ItemPickup] = []
	var root := RunManager.floor_root()
	if root == null:
		return out
	for child: Node in root.get_children():
		if child is ItemPickup and not child.is_queued_for_deletion():
			out.append(child as ItemPickup)
	return out


func _caltrops(_live: Player) -> Array[Hitbox]:
	var out: Array[Hitbox] = []
	for node: Node in get_tree().get_nodes_in_group(Player.CALTROP_GROUP):
		if node is Hitbox and not node.is_queued_for_deletion():
			out.append(node as Hitbox)
	return out


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## One `_drop_gold` measurement.
class DropSample:
	extends RefCounted
	var gold: int = 0
	var multiplier: float = 1.0
