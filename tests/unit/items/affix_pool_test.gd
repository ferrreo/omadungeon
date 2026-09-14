## Every affix that can roll on an item has to do something on that item (playtest: a large
## slice of the pool was inert). These tests assert the *reader* exists, not just that the
## roll happened: a projectile affix only rolls where a projectile is spawned, an elemental
## damage affix only where that tag is dealt, and a resist only where that tag is taken.
class_name AffixPoolTest
extends GdUnitTestSuite

## Generations per check. Large enough that a 0.35-weight affix would show up many times.
const ROLLS := 2000

var _registry: ItemRegistry


func before() -> void:
	_registry = ItemRegistry.load_default()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A 20-damage trap hit carrying `tag`, from nobody.
static func _trap_hit(tag: StringName) -> DamageInfo:
	var tags: Array[StringName] = [DamageInfo.TAG_TRAP, tag]
	return DamageInfo.create(20.0, tags, null, Layers.Team.NEUTRAL)


## Every affix id rolled onto bases of `style` over ROLLS generations.
func _ids_rolled_on_style(style: WeaponBase.Style) -> Dictionary:
	var rng := _rng(777)
	var out: Dictionary = {}
	for i in range(ROLLS):
		var item := ItemGenerator.generate(
			_registry, i % 9, rng, 0.6, [ItemBase.Slot.WEAPON], i % 4
		)
		var weapon := item.base as WeaponBase
		if weapon == null or weapon.style != style:
			continue
		for entry: Dictionary in item.affixes:
			out[(entry["affix"] as Affix).id] = true
	return out


func test_projectile_affixes_never_roll_on_a_melee_weapon() -> void:
	var dead: Array[StringName] = [&"proj_count", &"proj_size", &"proj_speed", &"pierce"]
	for style: WeaponBase.Style in [WeaponBase.Style.MELEE_ARC, WeaponBase.Style.MELEE_THRUST]:
		var rolled := _ids_rolled_on_style(style)
		assert_bool(rolled.is_empty()).is_false()
		for id: StringName in dead:
			(
				assert_bool(rolled.has(id))
				. override_failure_message(
					"%s rolled on a melee weapon, where nothing reads it" % id
				)
				. is_false()
			)


func test_projectile_affixes_still_roll_on_the_weapons_that_read_them() -> void:
	var rolled: Dictionary = {}
	for style: WeaponBase.Style in [
		WeaponBase.Style.RANGED_BOW, WeaponBase.Style.RANGED_WAND, WeaponBase.Style.THROWN
	]:
		for id: StringName in _ids_rolled_on_style(style).keys():
			rolled[id] = true
	for id: StringName in [&"proj_count", &"proj_size", &"proj_speed", &"pierce"]:
		(
			assert_bool(rolled.has(id))
			. override_failure_message("%s can no longer roll anywhere" % id)
			. is_true()
		)


func test_tag_damage_affixes_only_roll_on_weapons_that_carry_the_tag() -> void:
	var rng := _rng(4242)
	for i in range(ROLLS):
		var item := ItemGenerator.generate(
			_registry, i % 9, rng, 0.6, [ItemBase.Slot.WEAPON], i % 4
		)
		var weapon := item.base as WeaponBase
		for entry: Dictionary in item.affixes:
			var affix: Affix = entry["affix"]
			for tag: StringName in affix.weapon_tags:
				(
					assert_bool(weapon.tags.has(tag))
					. override_failure_message(
						"%s (needs %s) rolled on %s" % [affix.id, tag, weapon.id]
					)
					. is_true()
				)


func test_a_melee_weapon_never_offers_ranged_damage() -> void:
	var melee := _ids_rolled_on_style(WeaponBase.Style.MELEE_ARC)
	assert_bool(melee.has(&"damage_ranged")).is_false()
	assert_bool(melee.has(&"damage_melee")).is_true()
	var bow := _ids_rolled_on_style(WeaponBase.Style.RANGED_BOW)
	assert_bool(bow.has(&"damage_melee")).is_false()
	assert_bool(bow.has(&"damage_ranged")).is_true()


func test_rings_and_trinkets_keep_the_whole_pool() -> void:
	# The style gate is a weapon rule: a ring does not know which weapon it will be worn with.
	var ring := _registry.find_base(&"ring_iron")
	var pool := _registry.affixes_for(ring.slot_name(), 3, ring)
	var ids: Array[StringName] = []
	for affix: Affix in pool:
		ids.append(affix.id)
	assert_array(ids).contains([&"damage_melee", &"damage_ranged"])


func test_every_shipped_resist_affix_has_a_damage_source_in_the_game() -> void:
	# Nothing in the shipped content deals frost, shock or poison damage *to the player*, so
	# those resists were removed. The two that remain are backed by live content, asserted
	# here against the real nodes rather than a list.
	var resists: Array[StringName] = []
	for affix: Affix in _registry.affixes:
		if String(affix.stat).begins_with("resist_"):
			resists.append(affix.stat)
	assert_array(resists).contains_exactly_in_any_order([&"resist_fire", &"resist_arcane"])

	var vent := auto_free(FireVent.new()) as FireVent
	assert_array(vent.tags).contains([DamageInfo.TAG_FIRE])
	assert_bool(vent.tags.has(DamageInfo.TAG_TRUE)).is_false()
	var laser := auto_free(LaserGrid.new()) as LaserGrid
	assert_array(laser.tags).contains([DamageInfo.TAG_ARCANE])
	assert_bool(laser.tags.has(DamageInfo.TAG_TRUE)).is_false()
	assert_array(RingmasterFireRing.TAGS).contains([DamageInfo.TAG_FIRE])


func test_resistance_actually_reduces_that_damage() -> void:
	# The affix is only real if the number moves: a fire resist has to cost the fire vent.
	var victim := auto_free(Entity.new()) as Entity
	add_child(victim)
	await get_tree().physics_frame
	var plain := victim.health.take_damage(_trap_hit(DamageInfo.TAG_FIRE))
	victim.stats.add_flat(&"resist_fire", &"test", 0.5)
	var resisted := victim.health.take_damage(_trap_hit(DamageInfo.TAG_FIRE))
	assert_float(resisted).is_less(plain)
	victim.stats.remove_owner(&"test")
	victim.stats.add_flat(&"resist_arcane", &"test", 0.5)
	var arcane := victim.health.take_damage(_trap_hit(DamageInfo.TAG_ARCANE))
	assert_float(arcane).is_less(plain)


func test_every_affix_in_the_registry_can_still_roll_somewhere() -> void:
	var rng := _rng(31337)
	var rolled: Dictionary = {}
	for i in range(4000):
		var item := ItemGenerator.generate(_registry, i % 9, rng, 0.5, [], i % 4)
		for entry: Dictionary in item.affixes:
			rolled[(entry["affix"] as Affix).id] = true
	for affix: Affix in _registry.affixes:
		(
			assert_bool(rolled.has(affix.id))
			. override_failure_message("affix %s never rolled" % affix.id)
			. is_true()
		)
