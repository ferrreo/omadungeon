## Duck-typed integration with the items (Equipment) and abilities (AbilitySlots) modules.
## Skips silently when those scripts are not present yet.
class_name PlayerIntegrationTest
extends GdUnitTestSuite

const EQUIPMENT_SCRIPT := "res://src/items/equipment.gd"
const SLOTS_SCRIPT := "res://src/abilities/ability_slots.gd"


func before_test() -> void:
	HitStop.set_enabled(get_tree(), false)


func after_test() -> void:
	HitStop.set_enabled(get_tree(), true)
	Engine.time_scale = 1.0


func test_equip_through_equipment_applies_stats_and_weapon() -> void:
	if not ResourceLoader.exists(EQUIPMENT_SCRIPT):
		return
	var player := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(player)
	player.apply_class(PlayerTestHelpers.load_class("ranger"))
	var script := load(EQUIPMENT_SCRIPT) as GDScript
	player.equipment = script.new() as RefCounted
	var bow := WeaponBase.new()
	bow.id = &"shortbow"
	bow.style = WeaponBase.Style.RANGED_BOW
	bow.implicit_flat = {&"precision": 2.0}
	var item := ItemInstance.new()
	item.uid = 7
	item.base = bow
	player.equip(item)
	assert_int(player.stats.primary(&"precision")).is_equal(7)
	assert_int(player.weapon_controller.style()).is_equal(WeaponBase.Style.RANGED_BOW)
	assert_object(player.weapon_controller.item).is_same(item)
	var data := player.to_dict()
	assert_bool((data["equipment"] as Dictionary).has("weapon")).is_true()


func test_ability_slots_child_is_picked_up_and_cast_on_active_press() -> void:
	if not ResourceLoader.exists(SLOTS_SCRIPT):
		return
	var player := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(player)
	player.apply_class(PlayerTestHelpers.load_class("wizard"))
	var slots := player.ability_slots
	assert_object(slots).is_same(player.get_node_or_null("AbilitySlots"))
	var snapshot := player.to_dict()
	assert_bool((snapshot["abilities"] as Dictionary).has("actives")).is_true()
	(
		assert_float(
			float(slots.call("outgoing_damage_multiplier", null, PlayerTestHelpers.enemy_hit(1.0)))
		)
		. is_equal_approx(1.0, 0.001)
	)


func test_scene_provides_ability_slots_and_equipment() -> void:
	var player := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(player)
	assert_object(player.ability_slots).is_not_null()
	assert_str(player.ability_slots.name).is_equal("AbilitySlots")
	if ResourceLoader.exists(EQUIPMENT_SCRIPT):
		assert_object(player.equipment).is_not_null()
		assert_bool(player.equipment.has_method("empty_slots")).is_true()


func test_rng_assignment_reaches_the_ability_slots_crit_roll() -> void:
	var player := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(player)
	var stream := RandomNumberGenerator.new()
	stream.seed = 4242
	player.rng = stream
	assert_object(player.ability_slots.get(&"rng")).is_same(stream)


func test_restore_with_equipment_and_passive_does_not_double_modifiers() -> void:
	if not ResourceLoader.exists(EQUIPMENT_SCRIPT) or not ResourceLoader.exists(SLOTS_SCRIPT):
		return
	var items := load("res://data/items/registry.tres") as ItemRegistry
	var abilities := AbilityRegistry.load_default()
	if items == null or abilities == null:
		return
	var base := items.find_base(&"longsword") as WeaponBase
	var passive := abilities.instance(&"sure_footed") as PassiveAbility
	if base == null or passive == null:
		return
	var player := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(player)
	player.apply_class(PlayerTestHelpers.load_class("ranger"))
	var item := ItemInstance.new()
	item.uid = 4242
	item.base = base
	player.equip(item)
	assert_bool(player.ability_slots.call("add", passive)).is_true()
	var might := player.stats.get_value(&"might")
	var move_speed := player.stats.get_value(&"move_speed")
	var data := player.to_dict()

	var other := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(other)
	other.apply_class(PlayerTestHelpers.load_class("ranger"))
	other.restore_from_dict(data, items, abilities)
	assert_float(other.stats.get_value(&"might")).is_equal_approx(might, 0.001)
	assert_float(other.stats.get_value(&"move_speed")).is_equal_approx(move_speed, 0.001)
	assert_int(other.weapon_controller.style()).is_equal(WeaponBase.Style.MELEE_ARC)
	assert_str(String(other.weapon_controller.weapon.id)).is_equal("longsword")
	assert_bool(other.ability_slots.call("has", &"sure_footed")).is_true()

	# And a second save/load cycle must stay flat too.
	var again := auto_free(PlayerTestHelpers.make_player()) as Player
	add_child(again)
	again.apply_class(PlayerTestHelpers.load_class("ranger"))
	again.restore_from_dict(other.to_dict(), items, abilities)
	assert_float(again.stats.get_value(&"move_speed")).is_equal_approx(move_speed, 0.001)
