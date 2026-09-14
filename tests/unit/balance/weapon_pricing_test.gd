## One authority on what a weapon is worth.
##
## The playtest found two, disagreeing by up to 1.8x inside a single tier: the ladder in
## `data/items/tuning.tres` counted a weapon's implicit second projectile at full value (which
## is what put on-tier chakrams exactly on the tier-2 target), while the simulation priced that
## same shot at 45% and then multiplied every weapon by a hand-set per-style table the ladder
## knew nothing about. On-tier chakrams therefore scored 69% of their tier target to the offer
## policy and an on-tier longbow 125% of it, so the policy refused a whole weapon family the
## ladder called on-tier — and nothing in the tree compared the two numbers.
##
## `SimPlayer.dps()` now reads `WeaponBase.effective_dps()`, the ladder's own function. These
## assertions are what stops the two drifting apart again.
class_name WeaponPricingTest
extends GdUnitTestSuite

## How far the simulation's opinion of a weapon may sit from the ladder's, as a ratio.
const AGREEMENT_TOLERANCE := 0.001
## How much wider the simulation's within-tier spread may be than the ladder's own.
##
## Not 1.0, because a base's implicit stats are a real per-weapon difference the ladder does
## not price: an archmage staff carries +3 arcana, which multiplies its own `arcane` tag, and a
## stiletto carries +10% crit. That is the *weapon* being better, not the model preferring it.
## What is no longer allowed is the 1.81x the model used to invent inside tier 2 alone (an
## on-tier longbow at 56.3 DPS against on-tier chakrams at 31.0) out of a per-style table the
## ladder had never heard of.
const MAX_EXTRA_SPREAD := 1.15

var _registry: ItemRegistry
var _tuning: ItemTuning
var _profile: BalanceProfile


func before() -> void:
	_registry = ItemRegistry.load_default()
	_tuning = ItemTuning.load_default()
	_profile = BalanceProfile.load_default()


func _weapons() -> Array[WeaponBase]:
	var out: Array[WeaponBase] = []
	for base: ItemBase in _registry.bases:
		var weapon := base as WeaponBase
		if weapon != null:
			out.append(weapon)
	return out


## The offer policy's opinion of `weapon`, on a build that is nothing but the weapon.
func _sim_dps(weapon: WeaponBase) -> float:
	return _bare(weapon).dps()


func _bare(weapon: WeaponBase) -> SimPlayer:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	return SimPlayer.bare(ItemGenerator.instance_of(weapon, rng), _profile)


## Everything the simulation is allowed to scale a weapon by beyond the ladder number: the
## scripted player's weapon uptime, its crit, and the wearer's damage stats for the weapon's own
## tags. All three are properties of the *build*, not a per-weapon table.
func _allowed_multiplier(weapon: WeaponBase, player: SimPlayer) -> float:
	var tags := 1.0
	for tag: StringName in weapon.tags:
		tags *= 1.0 + player.stats.get_value(StringName("damage_" + String(tag)))
	var crit := (
		1.0 + player.stats.get_value(&"crit_chance") * (player.stats.get_value(&"crit_mult") - 1.0)
	)
	return tags * crit * _profile.weapon_uptime


func test_the_simulation_prices_every_weapon_exactly_as_the_ladder_does() -> void:
	var weapons := _weapons()
	assert_int(weapons.size()).is_greater_equal(12)
	for weapon: WeaponBase in weapons:
		var player := _bare(weapon)
		var ladder := weapon.effective_dps(player.stats.get_value(&"attack_speed"))
		(
			assert_float(ladder)
			. override_failure_message("%s prices at nothing" % weapon.id)
			. is_greater(0.0)
		)
		var explained := ladder * _allowed_multiplier(weapon, player)
		(
			assert_float(player.dps() / explained)
			. override_failure_message(
				(
					"the sim values %s at %.2f DPS; the ladder plus the build's own stats explain %.2f"
					% [weapon.id, player.dps(), explained]
				)
			)
			. is_equal_approx(1.0, AGREEMENT_TOLERANCE)
		)


func test_print_weapon_pricing_table() -> void:
	# The table a balance pass reads: what the ladder says a base is worth and what the offer
	# policy does with it. Before the two were reconciled these columns disagreed by up to 1.8x
	# inside one tier, and nothing printed them side by side.
	var lines := PackedStringArray()
	lines.append("Weapon           tier  ladder DPS  policy DPS  policy/ladder")
	for weapon: WeaponBase in _weapons():
		(
			lines
			. append(
				(
					"%-16s %4d %11.2f %11.2f %14.3f"
					% [
						String(weapon.id),
						weapon.tier,
						weapon.effective_dps(1.0),
						_sim_dps(weapon),
						_sim_dps(weapon) / maxf(0.01, weapon.effective_dps(1.0)),
					]
				)
			)
		)
	for tier in range(_tuning.tier_count()):
		var ladder_lo := INF
		var ladder_hi := 0.0
		var sim_lo := INF
		var sim_hi := 0.0
		for weapon: WeaponBase in _weapons():
			if weapon.tier != tier:
				continue
			ladder_lo = minf(ladder_lo, weapon.effective_dps(1.0))
			ladder_hi = maxf(ladder_hi, weapon.effective_dps(1.0))
			sim_lo = minf(sim_lo, _sim_dps(weapon))
			sim_hi = maxf(sim_hi, _sim_dps(weapon))
		if ladder_hi <= 0.0:
			continue
		lines.append(
			(
				"tier %d spread: ladder %.2fx, offer policy %.2fx"
				% [tier, ladder_hi / ladder_lo, sim_hi / sim_lo]
			)
		)
	print("\n" + "\n".join(lines))
	assert_int(_weapons().size()).is_greater_equal(12)


func test_two_weapons_of_one_tier_are_worth_the_same_to_the_offer_policy() -> void:
	# The ladder already keeps a tier's bases inside one band. The point here is that the
	# simulation adds no spread of its own on top: whatever the ladder says a tier is worth is
	# what the offer policy sees, weapon by weapon.
	for tier in range(_tuning.tier_count()):
		var ladder_lo := INF
		var ladder_hi := 0.0
		var sim_lo := INF
		var sim_hi := 0.0
		var count := 0
		for weapon: WeaponBase in _weapons():
			if weapon.tier != tier:
				continue
			count += 1
			ladder_lo = minf(ladder_lo, weapon.effective_dps(1.0))
			ladder_hi = maxf(ladder_hi, weapon.effective_dps(1.0))
			sim_lo = minf(sim_lo, _sim_dps(weapon))
			sim_hi = maxf(sim_hi, _sim_dps(weapon))
		if count < 2:
			continue
		var ladder_spread := ladder_hi / maxf(0.01, ladder_lo)
		var sim_spread := sim_hi / maxf(0.01, sim_lo)
		(
			assert_float(sim_spread)
			. override_failure_message(
				(
					"tier %d: the ladder spans %.2fx and the offer policy %.2fx"
					% [tier, ladder_spread, sim_spread]
				)
			)
			. is_less_equal(ladder_spread * MAX_EXTRA_SPREAD)
		)
		# And whatever spread is left is the one the ladder's own tolerance already allows, so
		# "same tier" still means something to the player choosing between two of them.
		(
			assert_float(sim_spread)
			. override_failure_message(
				"tier %d weapons are %.2fx apart to the offer policy" % [tier, sim_spread]
			)
			. is_less(1.0 + 2.0 * _tuning.weapon_tier_tolerance)
		)


func test_the_check_would_catch_a_per_style_fudge() -> void:
	# Proof this suite can fail: re-introduce the per-style multiplier the simulation used to
	# carry and the agreement above collapses. Without this, "the two authorities agree" is just
	# a restatement of one function calling another.
	var old_table: Array[float] = [1.15, 1.0, 1.25, 1.1, 0.95]
	var worst := 0.0
	for weapon: WeaponBase in _weapons():
		var player := _bare(weapon)
		var explained := (
			weapon.effective_dps(player.stats.get_value(&"attack_speed"))
			* _allowed_multiplier(weapon, player)
		)
		var honest := player.dps() / explained
		var fudged := honest * old_table[int(weapon.style)]
		assert_float(honest).is_equal_approx(1.0, AGREEMENT_TOLERANCE)
		worst = maxf(worst, absf(fudged - 1.0))
	(
		assert_float(worst)
		. override_failure_message("the old style table would not have shown up at all")
		. is_greater(AGREEMENT_TOLERANCE * 50.0)
	)


func test_an_affix_projectile_is_priced_below_the_weapons_own() -> void:
	# The one place the simulation is still allowed to discount a shot: projectiles the *build*
	# added. A wider fan overlaps on one body, so the fourth arrow is not worth the first — but
	# the weapon's own implicit fan is inside the ladder number and is never discounted twice.
	var fan: WeaponBase = null
	for weapon: WeaponBase in _weapons():
		if weapon.implicit_shots() > 1.0:
			fan = weapon
			break
	assert_object(fan).override_failure_message("no weapon base fires a fan").is_not_null()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var player := SimPlayer.bare(ItemGenerator.instance_of(fan, rng), _profile)
	var before := player.dps()
	assert_float(before / fan.effective_dps(1.0)).is_equal_approx(
		_allowed_multiplier(fan, player), AGREEMENT_TOLERANCE
	)
	player.stats.add_flat(&"projectile_count", &"test", 1.0)
	player.recompute()
	var per_implicit_shot := before / fan.implicit_shots()
	var added := player.dps() - before
	(
		assert_float(added / per_implicit_shot)
		. override_failure_message(
			(
				"an affix shot is worth %.2f of one of the weapon's own, not %.2f"
				% [added / per_implicit_shot, _profile.extra_projectile_value]
			)
		)
		. is_equal_approx(_profile.extra_projectile_value, 0.01)
	)
