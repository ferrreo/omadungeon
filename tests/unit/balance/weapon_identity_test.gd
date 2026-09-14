## The mechanism behind "the class you pick is still the class you are on floor 9": the chest's
## weapon-family bias (`ChestOffers._roll_one_item`) and the damage-tag structure that makes a
## class's own family its best one (`data/items/*.tres`).
##
## `balance_targets_test` asserts the *outcome* over 1200 simulated runs. This suite asserts the
## two parts that produce it, directly and cheaply, so a failure there says which half broke.
class_name WeaponIdentityTest
extends GdUnitTestSuite

const SEED := 20260912
## Boards rolled per measurement. Large enough that a family share moves by a point.
const BOARDS := 400
const FLOOR := 4
## Every family must contain a base a run can actually be offered, or the bias has nothing to
## pull towards and the identity assertions in `balance_targets_test` are unfalsifiable.
const MIN_BASES_PER_FAMILY := 2

var _items: ItemRegistry
var _abilities: AbilityRegistry
## `ItemTuning.shared()` is one resource for the whole process, so a case that turns the bias
## off to prove the check has teeth must put it back however it ends. Restoring it inside the
## case is not enough: a failed assertion there would leave every suite that runs afterwards
## measuring an unbiased pool (docs/TESTING.md, "a test must leave the process as it found it").
var _kept_bias: float = -1.0


func before() -> void:
	_items = ItemRegistry.load_default()
	_abilities = AbilityRegistry.load_default()


func after_test() -> void:
	if _kept_bias >= 0.0:
		ItemTuning.shared().weapon_family_bias = _kept_bias
		_kept_bias = -1.0


func _rng(extra: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + extra
	return rng


## A one-item `Equipment` holding base `id`, which is what a chest reads to know what the
## player is fighting with.
func _wearing(id: StringName) -> Equipment:
	var gear := Equipment.new()
	var rng := _rng()
	var base := _items.find_base(id)
	assert_object(base).override_failure_message("no such base: %s" % String(id)).is_not_null()
	gear.slots[&"weapon"] = ItemGenerator.instance_of(base, rng)
	return gear


## Share of the weapon cards a run of item chests offers that belong to each family, for a
## player wearing `id`: [melee, projectile, arcane].
func _offered_family_share(id: StringName, class_id: StringName = &"") -> Array[float]:
	var gear := _wearing(id)
	var rng := _rng(7)
	var counts: Array[int] = [0, 0, 0]
	var total := 0
	for i in range(BOARDS):
		var board := ChestOffers.roll(
			Chest.Kind.ITEM, 3, FLOOR, rng, 0.0, _items, _abilities, gear, class_id, {}
		)
		for offer: Variant in board.offers:
			var weapon := (offer as ItemInstance).base as WeaponBase
			if weapon == null:
				continue
			counts[int(weapon.family())] += 1
			total += 1
	var out: Array[float] = []
	for count: int in counts:
		out.append(float(count) / float(maxi(1, total)))
	return out


func test_every_weapon_family_has_something_to_offer() -> void:
	var counts: Array[int] = [0, 0, 0]
	for base: ItemBase in _items.bases:
		var weapon := base as WeaponBase
		if weapon != null:
			counts[int(weapon.family())] += 1
	for index in range(counts.size()):
		(
			assert_int(counts[index])
			. override_failure_message(
				(
					"the %s family ships %d bases"
					% [String(WeaponBase.family_name(index as WeaponBase.Family)), counts[index]]
				)
			)
			. is_greater_equal(MIN_BASES_PER_FAMILY)
		)


func test_a_chest_offers_the_family_the_player_is_already_fighting_with() -> void:
	# The round-3 verdict this exists to prevent: item chests biased by empty slot only, so a
	# Ranger was handed swords until the Ranger was a swordsman. The bias is a *preference* -
	# `ItemTuning.weapon_family_bias` leaves a real share of off-family cards on the board - so
	# this is a majority, not a monopoly.
	var bias := ItemTuning.shared().weapon_family_bias
	for entry: Array in [
		[&"rusty_sword", WeaponBase.Family.MELEE],
		[&"shortbow", WeaponBase.Family.PROJECTILE],
		[&"staff", WeaponBase.Family.ARCANE],
	]:
		var share := _offered_family_share(entry[0] as StringName)
		var own := int(entry[1])
		(
			assert_float(share[own])
			. override_failure_message(
				(
					"wearing %s the board offers %.0f%% %s weapons"
					% [
						String(entry[0] as StringName),
						share[own] * 100.0,
						String(WeaponBase.family_name(own as WeaponBase.Family)),
					]
				)
			)
			. is_greater(bias * 0.9)
		)
		# ... and never all of them: a run must still be able to be offered something else.
		(
			assert_float(share[own])
			. override_failure_message("the weapon slot is a cage: %.2f own-family" % share[own])
			. is_less(0.99)
		)


func test_turning_the_bias_off_lets_the_families_converge() -> void:
	# Proof the assertion above has teeth rather than restating how many bases each family has.
	# With the bias at zero every family's share is whatever the base pool happens to be, which
	# is the state the playtest measured.
	var tuning := ItemTuning.shared()
	_kept_bias = tuning.weapon_family_bias
	tuning.weapon_family_bias = 0.0
	var bow_share := _offered_family_share(&"shortbow")
	tuning.weapon_family_bias = _kept_bias
	var biased := _offered_family_share(&"shortbow")
	(
		assert_float(bow_share[int(WeaponBase.Family.PROJECTILE)])
		. override_failure_message(
			"an unbiased board already offers %.2f projectile weapons" % bow_share[1]
		)
		. is_less(biased[int(WeaponBase.Family.PROJECTILE)] - 0.2)
	)


func test_a_chest_keeps_offering_a_class_its_own_family_after_it_switches() -> void:
	# Biasing only towards the weapon in hand is a ratchet: one good sword out of a shop and a
	# Ranger's chests reinforce the sword for the rest of the run, and the class the player
	# picked stops being offered its own weapons at all. Measured on a Ranger holding a
	# longsword, both doors have to stay open.
	var share := _offered_family_share(&"longsword", &"ranger")
	(
		assert_float(share[int(WeaponBase.Family.PROJECTILE)])
		. override_failure_message(
			(
				"a Ranger who picked up a sword is offered bows %.0f%% of the time"
				% [share[int(WeaponBase.Family.PROJECTILE)] * 100.0]
			)
		)
		. is_greater(0.3)
	)
	(
		assert_float(share[int(WeaponBase.Family.MELEE)])
		. override_failure_message(
			(
				"...and the sword it actually holds only %.0f%%"
				% [share[int(WeaponBase.Family.MELEE)] * 100.0]
			)
		)
		. is_greater(0.3)
	)


## Damage multiplier a weapon's tags earn on `stats`, which is exactly what `SimPlayer.dps()`
## and the live `Entity.damage_multiplier()` both apply.
static func _tag_multiplier(weapon: WeaponBase, stats: Stats) -> float:
	var mult := 1.0
	for tag: StringName in weapon.tags:
		mult *= 1.0 + stats.get_value(StringName("damage_" + String(tag)))
	return mult


func test_each_class_scales_best_with_its_own_weapon_family() -> void:
	# The other half of identity, and the half a chest bias cannot supply: a class has to *want*
	# its own family. Every family scales off exactly one primary (docs §4.2) - melee off Might,
	# projectile off Precision, arcane off Arcana - so the class's own stat spread decides.
	# Staves used to carry `ranged` as well as `arcane`/`ability` and so collected Precision and
	# Arcana both, which is why the same runed staff was the most likely final weapon for all
	# four classes.
	var exemplars: Dictionary = {
		int(WeaponBase.Family.MELEE): &"longsword",
		int(WeaponBase.Family.PROJECTILE): &"crossbow",
		int(WeaponBase.Family.ARCANE): &"runed_staff",
	}
	var lines := PackedStringArray()
	for class_id: StringName in BalanceSim.CLASS_IDS:
		var def := load("%s/%s.tres" % [BalanceSim.CLASS_DIR, class_id]) as ClassDef
		var stats := Stats.new()
		for stat: StringName in Stats.PRIMARY:
			stats.add_primary(stat, int(def.base_stats().get(stat, 0)))
		var own := (_items.find_base(def.start_weapon_id) as WeaponBase).family()
		var own_mult := _tag_multiplier(_items.find_base(exemplars[int(own)]) as WeaponBase, stats)
		var row := "%s (%s) %.3f" % [String(class_id), String(def.start_weapon_id), own_mult]
		for family: int in exemplars.keys():
			if family == int(own):
				continue
			var other := _items.find_base(exemplars[family]) as WeaponBase
			var other_mult := _tag_multiplier(other, stats)
			row += " vs %s %.3f" % [String(other.id), other_mult]
			(
				assert_float(own_mult)
				. override_failure_message(
					(
						"%s scales %.3f with its own family and %.3f with %s"
						% [String(class_id), own_mult, other_mult, String(other.id)]
					)
				)
				. is_greater_equal(other_mult)
			)
		lines.append(row)
	print("weapon-family scaling per class: " + "; ".join(lines))
