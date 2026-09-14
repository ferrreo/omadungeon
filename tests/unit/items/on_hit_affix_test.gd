## On-hit affixes have to keep pace with the run (playtest: "12 damage of burn is 40% of a
## floor-1 Juggler and 5% of the same Juggler on floor 9"). The magnitude now comes from the
## weapon that swung and the wearer's elemental damage stat, so these tests measure the HP a
## victim actually loses, not just the number the builder returned.
class_name OnHitAffixTest
extends GdUnitTestSuite

## Physics frames covering one StatusController DoT tick (0.5 s at 60 Hz) plus slack.
const TICK_FRAMES := 36

var _registry: ItemRegistry
var _tuning: ItemTuning


func before() -> void:
	_registry = ItemRegistry.load_default()
	_tuning = ItemTuning.load_default()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func _weapon(id: StringName) -> WeaponBase:
	return _registry.find_base(id) as WeaponBase


## A wearer holding `weapon_id` with an always-procing on-hit affix of `affix_id`.
func _wearer(weapon_id: StringName, affix_id: StringName) -> Entity:
	var hero := auto_free(Entity.new()) as Entity
	hero.team = Layers.Team.PLAYER
	add_child(hero)
	var gear := Equipment.new()
	var weapon := ItemGenerator.instance_of(_registry.find_base(weapon_id), _rng(7))
	weapon.affixes.append({"affix": _registry.find_affix(affix_id), "value": 1.0})
	gear.equip(weapon, hero.stats)
	hero.set_meta(&"gear", gear)
	return hero


func _gear_of(hero: Entity) -> Equipment:
	return hero.get_meta(&"gear") as Equipment


## HP lost by a fresh victim over one DoT tick of `effect`.
func _tick_damage(effect: StatusEffect) -> float:
	var victim := auto_free(Entity.new()) as Entity
	add_child(victim)
	await get_tree().physics_frame
	var before := victim.health.hp
	victim.status.apply(effect)
	await _frames(TICK_FRAMES)
	return before - victim.health.hp


func test_burn_scales_with_the_weapon_that_applied_it() -> void:
	var starter := Equipment.make_on_hit_status(
		StatusEffect.Kind.BURN, null, _weapon(&"rusty_sword"), null
	)
	var late := Equipment.make_on_hit_status(
		StatusEffect.Kind.BURN, null, _weapon(&"greatsword"), null
	)
	assert_float(starter.magnitude).is_greater(0.0)
	# The late-game weapon hits 3.5x as hard, so its burn has to follow it up the ladder.
	assert_float(late.magnitude / starter.magnitude).is_greater(3.0)
	var starter_damage := await _tick_damage(starter)
	var late_damage := await _tick_damage(late)
	assert_float(starter_damage).is_greater(0.0)
	assert_float(late_damage).is_greater(starter_damage * 2.5)


func test_fire_damage_multiplies_the_burn_it_causes() -> void:
	var hero := _wearer(&"rusty_sword", &"onhit_burn")
	await get_tree().physics_frame
	var plain := _gear_of(hero).roll_on_hit_statuses(_rng(1), hero)
	assert_int(plain.size()).is_equal(1)
	hero.stats.add_flat(&"damage_fire", &"test", 0.5)
	var boosted := _gear_of(hero).roll_on_hit_statuses(_rng(1), hero)
	assert_int(boosted.size()).is_equal(1)
	assert_float(boosted[0].magnitude / plain[0].magnitude).is_equal_approx(1.5, 0.01)
	# And the extra magnitude is HP the victim really loses.
	var plain_damage := await _tick_damage(plain[0])
	var boosted_damage := await _tick_damage(boosted[0])
	assert_float(boosted_damage).is_greater(plain_damage)


func test_poison_damage_finally_has_a_source_to_multiply() -> void:
	var hero := _wearer(&"dagger", &"onhit_poison")
	await get_tree().physics_frame
	var plain := _gear_of(hero).roll_on_hit_statuses(_rng(2), hero)
	hero.stats.add_flat(&"damage_poison", &"test", 1.0)
	var boosted := _gear_of(hero).roll_on_hit_statuses(_rng(2), hero)
	assert_int(plain[0].kind).is_equal(StatusEffect.Kind.POISON)
	assert_float(boosted[0].magnitude / plain[0].magnitude).is_equal_approx(2.0, 0.01)
	assert_float(await _tick_damage(boosted[0])).is_greater(await _tick_damage(plain[0]))


func test_an_on_hit_roll_rides_the_weapon_in_the_slot() -> void:
	var light := _wearer(&"rusty_sword", &"onhit_burn")
	var heavy := _wearer(&"executioner_axe", &"onhit_burn")
	await get_tree().physics_frame
	var small := _gear_of(light).roll_on_hit_statuses(_rng(3), light)
	var big := _gear_of(heavy).roll_on_hit_statuses(_rng(3), heavy)
	assert_float(big[0].magnitude).is_greater(small[0].magnitude * 3.0)


func test_an_unarmed_wearer_still_gets_a_usable_proc() -> void:
	var effect := Equipment.make_on_hit_status(StatusEffect.Kind.BURN)
	assert_float(effect.magnitude).is_equal_approx(
		_tuning.unarmed_hit_damage * _tuning.burn_dps_per_hit, 0.001
	)
	assert_float(effect.duration).is_equal(_tuning.burn_duration)


func test_the_shock_proc_staggers_instead_of_doing_nothing() -> void:
	# StatusController has no behaviour for SHOCK, so the affix applies a short stun, which
	# it does have: an enemy that is hit by it visibly stops acting.
	var affix := _registry.find_affix(&"onhit_shock")
	assert_int(int(affix.status_kind)).is_equal(int(StatusEffect.Kind.STUN))
	assert_str(ItemGenerator.describe_affix(affix, 0.1)).is_equal("10% chance to stun on hit")
	var victim := auto_free(Entity.new()) as Entity
	add_child(victim)
	await get_tree().physics_frame
	assert_bool(victim.can_act()).is_true()
	victim.status.apply(Equipment.make_on_hit_status(StatusEffect.Kind.STUN))
	assert_bool(victim.can_act()).is_false()
	await _frames(int(_tuning.stun_duration * 60.0) + 6)
	assert_bool(victim.can_act()).is_true()


func test_the_frost_proc_still_slows_and_freezes() -> void:
	var victim := auto_free(Entity.new()) as Entity
	add_child(victim)
	await get_tree().physics_frame
	var full := victim.effective_speed()
	for _i in range(2):
		victim.status.apply(Equipment.make_on_hit_status(StatusEffect.Kind.FROST))
	assert_float(victim.effective_speed()).is_less(full)
	victim.status.apply(Equipment.make_on_hit_status(StatusEffect.Kind.FROST))
	assert_bool(victim.status.is_stunned()).is_true()
