## The weapon power ladder (playtest: "weapon bases do not ladder, so a later base can be
## strictly worse than the starting one"). Every assertion is about what the player can be
## handed on a given floor, not about a function returning.
class_name WeaponLadderTest
extends GdUnitTestSuite

## Floors a run visits (docs §2: nine floors, three biomes).
const FLOOR_COUNT := 9
## Weapons the four classes start with; they sit at the bottom of tier 0 on purpose.
const START_WEAPONS: Array[StringName] = [&"rusty_sword", &"shortbow", &"staff", &"golden_cane"]

var _registry: ItemRegistry
var _tuning: ItemTuning


func before() -> void:
	_registry = ItemRegistry.load_default()
	_tuning = ItemTuning.load_default()


## Every weapon base the registry could hand out on `floor_index`.
func _weapons_on(floor_index: int) -> Array[WeaponBase]:
	var out: Array[WeaponBase] = []
	for base: ItemBase in _registry.bases_for([ItemBase.Slot.WEAPON], floor_index):
		var weapon := base as WeaponBase
		if weapon != null:
			out.append(weapon)
	return out


func _best_dps(floor_index: int) -> float:
	var best := 0.0
	for weapon: WeaponBase in _weapons_on(floor_index):
		best = maxf(best, weapon.raw_dps())
	return best


func _worst_dps(floor_index: int) -> float:
	var worst := INF
	for weapon: WeaponBase in _weapons_on(floor_index):
		worst = minf(worst, weapon.raw_dps())
	return worst


func test_tuning_resource_ships_a_three_step_ladder() -> void:
	assert_object(_tuning).is_not_null()
	assert_int(_tuning.tier_count()).is_greater_equal(3)
	for tier in range(1, _tuning.tier_count()):
		assert_float(_tuning.dps_for_tier(tier)).is_greater(_tuning.dps_for_tier(tier - 1))
		assert_int(_tuning.min_floor_for_tier(tier)).is_greater(
			_tuning.min_floor_for_tier(tier - 1)
		)
	# Roughly 1.5x per biome, as the ladder is meant to read.
	assert_float(_tuning.dps_for_tier(1) / _tuning.dps_for_tier(0)).is_between(1.35, 1.65)
	assert_float(_tuning.dps_for_tier(2) / _tuning.dps_for_tier(1)).is_between(1.35, 1.65)


func test_every_weapon_base_sits_in_its_tier_band() -> void:
	for base: ItemBase in _registry.bases:
		var weapon := base as WeaponBase
		if weapon == null:
			continue
		var target := _tuning.dps_for_tier(weapon.tier)
		var lo := target * (1.0 - _tuning.weapon_tier_tolerance)
		var hi := target * (1.0 + _tuning.weapon_tier_tolerance)
		(
			assert_float(weapon.raw_dps())
			. override_failure_message(
				(
					"%s is tier %d (%.0f DPS) but its band is %.0f-%.0f"
					% [weapon.id, weapon.tier, weapon.raw_dps(), lo, hi]
				)
			)
			. is_between(lo, hi)
		)
		(
			assert_int(weapon.min_floor)
			. override_failure_message("%s drops before its tier does" % weapon.id)
			. is_greater_equal(_tuning.min_floor_for_tier(weapon.tier))
		)


func test_every_tier_and_style_is_represented() -> void:
	var by_tier: Dictionary = {}
	var by_style: Dictionary = {}
	for base: ItemBase in _registry.bases:
		var weapon := base as WeaponBase
		if weapon == null:
			continue
		by_tier[weapon.tier] = int(by_tier.get(weapon.tier, 0)) + 1
		by_style[weapon.style] = int(by_style.get(weapon.style, 0)) + 1
	for tier in range(_tuning.tier_count()):
		(
			assert_int(int(by_tier.get(tier, 0)))
			. override_failure_message("no weapon base at tier %d" % tier)
			. is_greater_equal(2)
		)
	for style: int in WeaponBase.Style.values():
		(
			assert_int(int(by_style.get(style, 0)))
			. override_failure_message("no weapon base of style %d" % style)
			. is_greater(0)
		)


func test_the_floor_you_are_on_decides_how_strong_a_weapon_can_drop() -> void:
	var previous_best := 0.0
	var previous_worst := 0.0
	for index in range(FLOOR_COUNT):
		var best := _best_dps(index)
		var worst := _worst_dps(index)
		assert_bool(_weapons_on(index).size() >= 4).is_true()
		(
			assert_float(best)
			. override_failure_message(
				"floor %d can drop weaker gear than floor %d" % [index, index - 1]
			)
			. is_greater_equal(previous_best)
		)
		assert_float(worst).is_greater_equal(previous_worst)
		previous_best = best
		previous_worst = worst
	# The headline promise: by the last biome even the *worst* weapon that can drop beats
	# everything the first biome could ever have given you.
	assert_float(_worst_dps(FLOOR_COUNT - 1)).is_greater(_best_dps(0))
	assert_float(_best_dps(FLOOR_COUNT - 1) / _best_dps(0)).is_greater(1.8)


func test_starting_weapons_are_the_floor_of_the_ladder() -> void:
	var best_start := 0.0
	for id: StringName in START_WEAPONS:
		var weapon := _registry.find_base(id) as WeaponBase
		assert_object(weapon).override_failure_message("missing %s" % id).is_not_null()
		assert_int(weapon.tier).is_equal(0)
		best_start = maxf(best_start, weapon.raw_dps())
	# Something the dungeon can hand you on floor 1 already beats every class starter.
	assert_float(_best_dps(0)).is_greater(best_start)


func test_obsolete_tiers_stop_dropping() -> void:
	var late := _weapons_on(FLOOR_COUNT - 1)
	for weapon: WeaponBase in late:
		(
			assert_int(weapon.tier)
			. override_failure_message("%s (tier 0) still drops on the last floor" % weapon.id)
			. is_greater_equal(1)
		)
	var early := _weapons_on(0)
	for weapon: WeaponBase in early:
		assert_int(weapon.tier).is_equal(0)


func test_generated_weapons_respect_the_ladder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in range(600):
		var index := i % FLOOR_COUNT
		var item := ItemGenerator.generate(
			_registry, index, rng, 0.2, [ItemBase.Slot.WEAPON], i % 4
		)
		var weapon := item.base as WeaponBase
		assert_object(weapon).is_not_null()
		assert_int(weapon.min_floor).is_less_equal(index)
		var floor_tier := _tuning.tier_for_floor(index)
		(
			assert_int(weapon.tier)
			. override_failure_message(
				"floor %d dropped tier-%d %s" % [index, weapon.tier, weapon.id]
			)
			. is_greater_equal(floor_tier - ItemRegistry.OBSOLETE_TIER_GAP)
		)


func test_the_ladder_measures_a_bow_by_what_a_held_button_produces() -> void:
	# A bow's cycle is its draw, not its attack interval, and holding the button sustains the
	# full-charge multiplier. Measuring it as `base_damage * attacks_per_second` let the real
	# shortbow ship at 25.7 DPS against a tier-0 band of 15-25 and the real longbow at 58.3
	# against a tier-2 band of 33.75-56.25: both escaped their own ladder upward.
	var bows := 0
	for base: ItemBase in _registry.bases:
		var weapon := base as WeaponBase
		if weapon == null or weapon.style != WeaponBase.Style.RANGED_BOW:
			continue
		bows += 1
		var authored := weapon.base_damage * weapon.attacks_per_second
		var target := _tuning.dps_for_tier(weapon.tier)
		var hi := target * (1.0 + _tuning.weapon_tier_tolerance)
		(
			assert_float(weapon.effective_dps(1.0))
			. override_failure_message(
				(
					"%s really does %.1f DPS (authored %.1f), band tops out at %.1f"
					% [weapon.id, weapon.effective_dps(1.0), authored, hi]
				)
			)
			. is_between(target * (1.0 - _tuning.weapon_tier_tolerance), hi)
		)
	assert_int(bows).override_failure_message("no bow bases to check").is_greater_equal(3)


func test_attack_speed_is_worth_the_same_dps_on_every_weapon_style() -> void:
	# The whole point of the effective-DPS model: a stat that both balance authorities price
	# as linear has to *be* linear, on a charged bow exactly as on a sword.
	for base: ItemBase in _registry.bases:
		var weapon := base as WeaponBase
		if weapon == null:
			continue
		var single := weapon.effective_dps(1.0)
		for speed: float in [1.25, 1.5, 2.0]:
			(
				assert_float(weapon.effective_dps(speed))
				. override_failure_message(
					(
						"%.2fx attack speed moves %s from %.2f to %.2f DPS"
						% [speed, weapon.id, single, weapon.effective_dps(speed)]
					)
				)
				. is_equal_approx(single * speed, 0.01)
			)


func test_a_bow_sustains_its_full_charge_not_its_tap() -> void:
	var shortbow := _registry.find_base(&"shortbow") as WeaponBase
	var tuning := _tuning
	var cycle := tuning.bow_cycle_seconds(shortbow.attacks_per_second, 1.0)
	assert_float(cycle).is_equal_approx(
		maxf(tuning.bow_charge_seconds, 1.0 / shortbow.attacks_per_second), 0.001
	)
	assert_float(shortbow.effective_dps(1.0)).is_equal_approx(
		shortbow.base_damage * tuning.bow_full_damage_mult / cycle, 0.01
	)
	# A tap is the weak, fast option it is advertised as, never the sustained one.
	assert_float(tuning.bow_tap_damage_mult).is_less(tuning.bow_full_damage_mult)
