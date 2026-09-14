## Unit tests for the pieces of the headless balance simulation (`src/core/balance/**`):
## determinism, the class loadout it starts from, the floor mix it walks, the fight maths and
## the offer policy. The balance *targets* are asserted in `balance_targets_test.gd`.
class_name BalanceSimTest
extends GdUnitTestSuite

const SEED_A := 20260912
const SEED_B := 4242


func _simulator() -> RunSimulator:
	return RunSimulator.create()


func _class_def(id: StringName) -> ClassDef:
	return load("%s/%s.tres" % [BalanceSim.CLASS_DIR, id]) as ClassDef


func test_profile_resource_loads() -> void:
	var profile := BalanceProfile.load_default()
	assert_object(profile).is_not_null()
	assert_float(profile.weapon_uptime).is_greater(0.0)
	assert_float(profile.avoidance_base).is_between(0.0, 0.95)
	assert_int(profile.shop_base_price).is_greater(0)


func test_mirrored_economy_constants_match_run_manager() -> void:
	# The simulation must not reach for an autoload, so it keeps its own copy of the prices
	# RunManager charges. This is the alarm that fires when the two drift apart.
	var profile := BalanceProfile.load_default()
	assert_int(profile.shop_base_price).is_equal(RunManager.SHOP_BASE_PRICE)
	assert_int(profile.shop_price_per_floor).is_equal(RunManager.SHOP_PRICE_PER_FLOOR)
	assert_int(profile.buyout_base_price).is_equal(RunManager.BUYOUT_BASE_PRICE)
	assert_int(profile.buyout_price_per_floor).is_equal(RunManager.BUYOUT_PRICE_PER_FLOOR)
	assert_int(profile.skip_gold_base).is_equal(RunManager.SKIP_GOLD_BASE)
	assert_int(profile.skip_gold_per_floor).is_equal(RunManager.SKIP_GOLD_PER_FLOOR)
	assert_int(RunSimulator.FLOOR_COUNT).is_equal(RunManager.FLOOR_COUNT)
	assert_array(RunSimulator.BOSS_FLOORS).is_equal(RunManager.BOSS_FLOORS)
	assert_array(RunSimulator.BOSS_IDS).is_equal(RunManager.BOSS_IDS)


func test_same_seed_same_run() -> void:
	var sim := _simulator()
	var def := _class_def(&"fighter")
	var a := sim.simulate(def, SEED_A)
	var b := sim.simulate(def, SEED_A)
	assert_int(a.death_floor).is_equal(b.death_floor)
	assert_bool(a.victory).is_equal(b.victory)
	assert_float(a.total_damage_taken).is_equal_approx(b.total_damage_taken, 0.001)
	assert_float(a.total_seconds).is_equal_approx(b.total_seconds, 0.001)
	assert_int(a.total_gold).is_equal(b.total_gold)


func test_different_seeds_differ() -> void:
	var sim := _simulator()
	var def := _class_def(&"wizard")
	var a := sim.simulate(def, SEED_A)
	var b := sim.simulate(def, SEED_B)
	assert_float(a.total_damage_taken).is_not_equal(b.total_damage_taken)


func test_class_loadout_matches_class_def() -> void:
	var sim := _simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	for class_id: StringName in BalanceSim.CLASS_IDS:
		var def := _class_def(class_id)
		var player := SimPlayer.create(def, sim.items, sim.abilities, sim.profile, rng)
		assert_bool(player.abilities.has(def.innate_passive_id)).is_true()
		assert_bool(player.abilities.has(def.class_active_id)).is_true()
		assert_int(player.gold).is_equal(def.start_gold)
		assert_object(player.equipment.weapon()).is_not_null()
		assert_float(player.max_hp()).is_equal(100.0 + 5.0 * float(def.vitality))
		assert_float(player.hp).is_equal(player.max_hp())
		# The innate is uncounted, exactly as AbilitySlots.add_innate() has it.
		assert_int(player.counted(Ability.Kind.PASSIVE)).is_equal(0)


func test_ability_slots_respect_the_live_limits() -> void:
	var sim := _simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	var player := SimPlayer.create(
		_class_def(&"fighter"), sim.items, sim.abilities, sim.profile, rng
	)
	assert_bool(player.take_ability(sim.abilities.instance(&"fireball"))).is_true()
	assert_bool(player.take_ability(sim.abilities.instance(&"frost_nova"))).is_false()
	assert_int(player.counted(Ability.Kind.ACTIVE)).is_equal(AbilitySlots.ACTIVE_COUNT)
	assert_bool(player.take_ability(sim.abilities.instance(&"thorns"))).is_true()
	assert_bool(player.take_ability(sim.abilities.instance(&"vampiric"))).is_true()
	assert_bool(player.take_ability(sim.abilities.instance(&"glass_cannon"))).is_false()
	# A duplicate tiers up instead of consuming a slot.
	assert_bool(player.take_ability(sim.abilities.instance(&"thorns"))).is_true()
	assert_int((player.abilities[&"thorns"] as Ability).tier).is_equal(2)


func test_glass_cannon_trades_hp_for_damage_from_its_tres() -> void:
	var sim := _simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	var player := SimPlayer.create(
		_class_def(&"fighter"), sim.items, sim.abilities, sim.profile, rng
	)
	var hp_before := player.max_hp()
	var dps_before := player.dps()
	player.take_ability(sim.abilities.instance(&"glass_cannon"))
	assert_float(player.max_hp()).is_less(hp_before)
	assert_float(player.dps()).is_greater(dps_before)


func test_floor_plan_matches_the_generator_room_budget() -> void:
	var rng := RandomNumberGenerator.new()
	for floor_index in range(RunSimulator.FLOOR_COUNT):
		rng.seed = SEED_A + floor_index
		var plan := SimFloorPlan.build(floor_index, rng)
		# Every room but the start room, so one less than the generator's count.
		assert_int(plan.rooms.size()).is_equal(GenParams.room_count_for(floor_index) - 1)
		var fights := 0
		for room_type: int in plan.rooms:
			if SimFloorPlan.is_fight(room_type):
				fights += 1
		assert_int(fights).is_greater(0)
		assert_bool(plan.is_boss_floor).is_equal(GenParams.is_boss_floor_index(floor_index))
		if plan.is_boss_floor:
			assert_bool(plan.rooms.has(int(FloorData.RoomType.BOSS))).is_true()
		else:
			assert_bool(plan.rooms.has(int(FloorData.RoomType.STAIRS))).is_true()


func test_encounter_scales_with_the_floor() -> void:
	var sim := _simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	var player := SimPlayer.create(
		_class_def(&"fighter"), sim.items, sim.abilities, sim.profile, rng
	)
	var pack: Array[EnemyDef] = [sim.enemies.find(&"juggler"), sim.enemies.find(&"honker")]
	var noiseless := BalanceProfile.load_default()
	noiseless.room_noise = 0.0
	var early := SimEncounter.resolve(player, pack, 0, false, noiseless, rng)
	var late := SimEncounter.resolve(player, pack, 8, false, noiseless, rng)
	assert_float(late.seconds).is_greater(early.seconds)
	assert_float(late.damage_taken).is_greater(early.damage_taken)
	assert_float(early.damage_taken).is_greater(0.0)


func test_policy_prefers_the_stronger_card() -> void:
	var sim := _simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	var player := SimPlayer.create(
		_class_def(&"fighter"), sim.items, sim.abilities, sim.profile, rng
	)
	var weak := {"stat": &"arcana", "points": 1}
	var strong := {"stat": &"vitality", "points": 2}
	assert_float(SimOfferPolicy.score_of(strong, player, sim.profile)).is_greater(
		SimOfferPolicy.score_of(weak, player, sim.profile)
	)
	# Gold is worth something, but never as much as a real upgrade.
	assert_float(SimOfferPolicy.score_of(40, player, sim.profile)).is_greater(1.0)
	assert_float(SimOfferPolicy.score_of(40, player, sim.profile)).is_less(
		SimOfferPolicy.score_of(strong, player, sim.profile)
	)


# --- the instruments themselves -----------------------------------------------------------
#
# A green suite caught none of the balance findings, so the checks that are supposed to catch
# them are themselves tested here against hand-built reports carrying the exact numbers the
# playtest measured. A detector nobody has ever shown a fault to is not a detector.


## One finished run whose floors cost exactly `shares` of a constant health pool.
func _run_with_shares(shares: Array[float]) -> SimRunResult:
	var result := SimRunResult.new()
	result.class_id = &"fighter"
	for share: float in shares:
		result.add_floor(60.0, 0.5, share * 200.0, 100.0, 10, 200.0)
	return result


func test_the_smoothness_check_can_see_a_sawtooth() -> void:
	# The shipped curve, as the playtest measured it: floor 6 the hardest floor in the game and
	# floor 7 easier than it. The old check sampled floors 1/3/5/7/9 and was one-sided, so this
	# series passed clean.
	var measured: Array[float] = [0.19, 0.35, 0.74, 0.76, 0.88, 1.41, 1.27, 1.81, 2.07]
	var report := SimReport.of([_run_with_shares(measured)])
	assert_array(report.sawtooth_floors()).is_equal([6])
	assert_float(report.ramp_evenness()).is_equal(0.0)
	# The old checkpoints could not have seen it: they skip floor 6 entirely.
	var sampled: Array[float] = []
	for index: int in [0, 2, 4, 6, 8]:
		sampled.append(report.avg_damage_share(index))
	for i in range(1, sampled.size()):
		assert_float(sampled[i]).is_greater(sampled[i - 1])


func test_the_smoothness_check_can_see_a_flat_floor_and_a_wall() -> void:
	# Every step positive is not enough: this curve never goes backwards and is still a
	# staircase of non-events and walls.
	var lumpy: Array[float] = [0.2, 0.22, 0.24, 0.9, 0.92, 0.94, 1.7, 1.72, 1.74]
	var report := SimReport.of([_run_with_shares(lumpy)])
	assert_array(report.sawtooth_floors()).is_empty()
	assert_float(report.ramp_evenness()).is_greater(20.0)
	# A ramp of even steps is what passes.
	var even: Array[float] = [0.2, 0.4, 0.6, 0.82, 1.02, 1.24, 1.46, 1.7, 1.95]
	var smooth := SimReport.of([_run_with_shares(even)])
	assert_array(smooth.sawtooth_floors()).is_empty()
	assert_float(smooth.ramp_evenness()).is_less(2.0)


## A run whose floors cost `shares` of the pool, of which `boss_shares` (indexed like
## `RunSimulator.BOSS_FLOORS`) was charged by the floor's boss rather than by its rooms.
func _run_with_boss_shares(shares: Array[float], boss_shares: Array[float]) -> SimRunResult:
	var result := _run_with_shares(shares)
	for slot in range(boss_shares.size()):
		result.boss_damage[slot] = boss_shares[slot] * 200.0
		result.boss_kills[slot] = 1
	return result


func test_the_evenness_check_names_the_floor_that_is_a_wall() -> void:
	# The same staircase of non-events and walls, read the way the band actually asks about it:
	# per floor, as a multiple of a typical floor's climb. The old biggest-over-smallest ratio
	# was a single number that named neither end.
	var lumpy: Array[float] = [0.2, 0.22, 0.24, 0.9, 0.92, 0.94, 1.7, 1.72, 1.74]
	var report := SimReport.of([_run_with_shares(lumpy)])
	var ratios := report.room_ramp_ratios()
	var walls := 0
	var non_events := 0
	for ratio: float in ratios:
		if ratio > 2.0:
			walls += 1
		if ratio < 0.5:
			non_events += 1
	assert_int(walls).is_greater(0)
	assert_int(non_events).is_greater(0)
	# And an even ramp sits inside the band on every floor.
	var even: Array[float] = [0.2, 0.4, 0.6, 0.82, 1.02, 1.24, 1.46, 1.7, 1.95]
	for ratio: float in SimReport.of([_run_with_shares(even)]).room_ramp_ratios():
		assert_float(ratio).is_between(0.5, 2.0)


func test_retuning_a_boss_does_not_move_the_difficulty_ramp() -> void:
	# The decoupling the playtest asked for. Both runs walk exactly the same rooms; the second
	# fights a floor-6 boss three times as costly. The combined curve turns into a wall
	# followed by a lull, and the ramp the evenness band reads does not move at all.
	var shares: Array[float] = [0.2, 0.4, 0.7, 0.9, 1.1, 1.6, 1.8, 2.0, 2.3]
	var gentle: Array[float] = [0.1, 0.1, 0.1]
	var heavy: Array[float] = [0.1, 0.5, 0.1]
	var before := SimReport.of([_run_with_boss_shares(shares, gentle)])
	var after := SimReport.of(
		[_run_with_boss_shares([0.2, 0.4, 0.7, 0.9, 1.1, 2.0, 1.8, 2.0, 2.3], heavy)]
	)
	# The combined curve now reads as a wall into floor 6 and a drop out of it - a sawtooth
	# that is nothing but the boss.
	assert_array(after.sawtooth_floors()).is_equal([6])
	assert_array(before.sawtooth_floors()).is_empty()
	assert_float(after.boss_hp_share(1)).is_greater(before.boss_hp_share(1) * 2.0)
	var before_ratios := before.room_ramp_ratios()
	var after_ratios := after.room_ramp_ratios()
	assert_int(after_ratios.size()).is_equal(before_ratios.size())
	for i in range(before_ratios.size()):
		assert_float(after_ratios[i]).is_equal_approx(before_ratios[i], 0.001)


func test_the_boss_ladder_does_not_move_when_the_rooms_do() -> void:
	# The other direction: the same three bosses, in a run whose ordinary rooms got much more
	# expensive. A boss's share of the pool is what the runs that fought it paid out of their
	# own health, so it is untouched.
	var boss: Array[float] = [0.1, 0.15, 0.2]
	var easy := SimReport.of(
		[_run_with_boss_shares([0.2, 0.4, 0.7, 0.9, 1.1, 1.6, 1.8, 2.0, 2.3], boss)]
	)
	var hard := SimReport.of(
		[_run_with_boss_shares([0.5, 0.9, 1.4, 1.8, 2.2, 2.9, 3.3, 3.7, 4.2], boss)]
	)
	for slot in range(3):
		assert_float(hard.boss_hp_share(slot)).is_equal_approx(easy.boss_hp_share(slot), 0.0001)
	assert_array(easy.boss_threat_dips(1.1)).is_empty()
	# ... and a ladder whose last rung merely ties the one before it is an anticlimax the
	# margin can see, where a bare "did it rise at all" could not.
	var flat: Array[float] = [0.1, 0.2, 0.205]
	var tied := SimReport.of(
		[_run_with_boss_shares([0.2, 0.4, 0.7, 0.9, 1.1, 1.6, 1.8, 2.0, 2.3], flat)]
	)
	assert_array(tied.boss_threat_dips()).is_empty()
	assert_array(tied.boss_threat_dips(1.1)).is_equal([2])


## A report in which every id in `conversions` was offered in `offer` of the runs and taken in
## the matching share of those.
func _report_with_conversions(conversions: Dictionary, offer: float, runs: int) -> SimReport:
	var report := SimReport.new()
	report.runs = runs
	for id: StringName in conversions.keys():
		report.offered_runs[id] = int(round(offer * float(runs)))
		report.picked_runs[id] = int(round(offer * float(conversions[id]) * float(runs)))
	return report


func test_the_outlier_band_flags_the_options_the_old_one_missed() -> void:
	# The playtest's own numbers: a seven-fold spread between the best and worst option, which
	# the old rule (dominant above 60% pick rate, dead at exactly 0%) passed without a word.
	var measured := {
		&"vampiric": 0.69,
		&"whirlwind": 0.68,
		&"frost_nova": 0.66,
		&"adrenaline": 0.66,
		&"dotfiles": 0.63,
		&"ricochet": 0.63,
		&"hotkey": 0.62,
		&"tiling_wm": 0.63,
		&"fireball": 0.65,
		&"glass_cannon": 0.59,
		&"thorns": 0.56,
		&"heavy_hands": 0.56,
		&"turret": 0.59,
		&"lucky_coin": 0.53,
		&"shadowstep": 0.29,
		&"warcry": 0.24,
		&"reboot": 0.19,
		&"rm_rf": 0.1,
	}
	var ids: Array[StringName] = []
	for id: StringName in measured.keys():
		ids.append(id)
	var report := _report_with_conversions(measured, 0.85, 600)
	var flagged := report.outliers(ids)
	for id: StringName in [&"rm_rf", &"reboot", &"warcry", &"shadowstep"]:
		(
			assert_bool(flagged.has(id))
			. override_failure_message(
				"%s was taken a tenth as often as the pool median and is not flagged" % String(id)
			)
			. is_true()
		)
		assert_str(str((flagged[id] as Dictionary)["kind"])).is_equal("dead")
	# Nothing in that cluster was picked often enough to be called dominant by anyone, but the
	# rule still has to be able to say so when an option genuinely is.
	assert_bool(flagged.has(&"vampiric")).is_false()
	var runaway := measured.duplicate()
	runaway[&"vampiric"] = 1.0
	(
		assert_str(str((report.outliers(ids).get(&"rm_rf", {}) as Dictionary).get("kind", "")))
		. is_equal("dead")
	)
	var second := _report_with_conversions(runaway, 0.85, 600)
	assert_str(str((second.outliers(ids)[&"vampiric"] as Dictionary)["kind"])).is_equal("dominant")


func test_difficulty_curve_is_data_and_ramps() -> void:
	var curve := DifficultyCurve.shared()
	assert_int(curve.enemy_hp.size()).is_equal(RunSimulator.FLOOR_COUNT)
	assert_int(curve.enemy_damage.size()).is_equal(RunSimulator.FLOOR_COUNT)
	assert_int(curve.pack_budget.size()).is_equal(RunSimulator.FLOOR_COUNT)
	assert_int(curve.trap_damage.size()).is_equal(RunSimulator.FLOOR_COUNT)
	for index in range(1, RunSimulator.FLOOR_COUNT):
		(
			assert_float(curve.hp_multiplier(index))
			. override_failure_message(
				"floor %d enemies are no tougher than floor %d's" % [index + 1, index]
			)
			. is_greater(curve.hp_multiplier(index - 1))
		)
		assert_float(curve.damage_multiplier(index)).is_greater(curve.damage_multiplier(index - 1))
		assert_float(curve.trap_multiplier(index)).is_greater_equal(
			curve.trap_multiplier(index - 1)
		)
	# Boss floors carry a lighter pack: the boss is the event, not the corridor before it.
	for boss_floor: int in RunSimulator.BOSS_FLOORS:
		if boss_floor <= 0:
			continue
		(
			assert_float(curve.budget_for(boss_floor))
			. override_failure_message(
				"floor %d is a boss floor and still carries a full pack budget" % (boss_floor + 1)
			)
			. is_less(curve.budget_for(boss_floor - 1))
		)
	# A floor past the end of the table reads as the last one rather than crashing.
	assert_float(curve.hp_multiplier(99)).is_equal(
		curve.hp_multiplier(RunSimulator.FLOOR_COUNT - 1)
	)


func test_enemy_and_trap_scaling_read_the_shipped_curve() -> void:
	var curve := DifficultyCurve.shared()
	var sim := _simulator()
	var juggler := sim.enemies.find(&"juggler")
	assert_object(juggler).is_not_null()
	assert_float(juggler.scaled_hp(4)).is_equal_approx(
		juggler.max_hp * curve.hp_multiplier(4), 0.01
	)
	assert_float(juggler.scaled_damage(4)).is_equal_approx(
		juggler.damage * curve.damage_multiplier(4), 0.01
	)
	var spike := TrapRegistry.load_default().get_def(&"spike_floor")
	assert_float(spike.scaled_damage(8)).is_equal_approx(
		spike.damage * curve.trap_multiplier(8), 0.01
	)
	# A harmless trap stays harmless however deep the floor.
	assert_float(TrapRegistry.load_default().get_def(&"ice_slide").scaled_damage(8)).is_equal(0.0)


func test_boss_phase_pressure_rises_with_the_phase_steps() -> void:
	var sim := _simulator()
	for id: StringName in RunSimulator.BOSS_IDS:
		var def := sim.enemies.find(id)
		assert_object(def).is_not_null()
		(
			assert_float(SimEncounter.boss_phase_pressure(def))
			. override_failure_message("%s hits no harder in its later phases" % String(id))
			. is_greater(1.2)
		)
	# An ordinary enemy has no phases and is priced at face value.
	assert_float(SimEncounter.boss_phase_pressure(sim.enemies.find(&"juggler"))).is_equal(1.0)


func test_report_aggregates_every_floor() -> void:
	var sim := _simulator()
	var def := _class_def(&"ranger")
	var results: Array = []
	for i in range(8):
		results.append(sim.simulate(def, RunRng.hash_combine(SEED_B, i)))
	var report := SimReport.of(results)
	assert_int(report.runs).is_equal(8)
	assert_int(report.entered[0]).is_equal(8)
	assert_float(report.avg_seconds(0)).is_greater(0.0)
	assert_float(report.avg_damage_dealt(0)).is_greater(0.0)
	assert_float(report.clear_rate()).is_between(0.0, 1.0)


# --- the simulation reads the data it loads ------------------------------------------------


func _curse(id: StringName) -> Ability:
	var curse := load("res://data/abilities/%s.tres" % id) as Ability
	assert_object(curse).is_not_null()
	var copy := curse.duplicate_ability()
	copy.tier = 1
	return copy


func test_the_shrine_reads_the_curse_instead_of_assuming_it_is_bad() -> void:
	# The simulation used to cleanse unconditionally: carry a curse, pay the shrine\'s health
	# price, lose it, every single time. That is a belief about content rather than a reading of
	# it, and `data/abilities/curse_*.tres` are two-sided by design — Kernel Panic buys +40%
	# damage with 30% of the health pool. Whether that trade is worth undoing is a question
	# about the build, so the shrine now answers it the way it answers every other card: by
	# previewing it on a clone.
	var sim := _simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	var player := SimPlayer.create(
		_class_def(&"fighter"), sim.items, sim.abilities, sim.profile, rng
	)
	var before := player.power()
	player.take_ability(_curse(&"curse_1"))
	var after := player.power()
	# Whichever way it lands, the score is the plain power ratio and nothing else.
	(
		assert_float(sim.cleanse_score(player))
		. override_failure_message(
			(
				(
					"Kernel Panic moves a Fighter\'s power by %.1f%% and the shrine scores removing it"
					+ " at %.3f"
				)
				% [(after / before - 1.0) * 100.0, sim.cleanse_score(player)]
			)
		)
		. is_equal_approx(before / after, 0.001)
	)
	# On these class starters every shipped curse is a real loss, so the shrine still buys the
	# cleanse - the old behaviour was right here, but by assumption rather than by measurement.
	(
		assert_float(sim.cleanse_score(player))
		. override_failure_message("the shrine would not pay to remove a curse that costs power")
		. is_greater(1.0)
	)


func test_the_shrine_keeps_a_curse_that_is_worth_keeping() -> void:
	# The half of the behaviour the old code could never reach: a curse the build is better off
	# carrying is left alone and no health is spent on it.
	var sim := _simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	var player := SimPlayer.create(
		_class_def(&"fighter"), sim.items, sim.abilities, sim.profile, rng
	)
	var boon := StatPassive.new()
	boon.id = &"curse_test_boon"
	boon.kind = Ability.Kind.PASSIVE
	boon.max_tier = 1
	boon.tier = 1
	boon.flat_stats = [&"damage_melee"] as Array[StringName]
	boon.flat_values = PackedFloat32Array([0.6])
	var before := player.power()
	player.take_ability(boon)
	assert_float(player.power()).is_greater(before)
	(
		assert_float(sim.cleanse_score(player))
		. override_failure_message("the shrine would pay health to remove a net gain")
		. is_less(1.0)
	)


func test_cleansing_nothing_is_worth_nothing() -> void:
	var sim := _simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_A
	var player := SimPlayer.create(
		_class_def(&"wizard"), sim.items, sim.abilities, sim.profile, rng
	)
	assert_float(sim.cleanse_score(player)).is_equal(1.0)
	# A curse that is a straight loss for this build does score above 1.0, so the option is
	# still taken when it is worth taking.
	var loss := StatPassive.new()
	loss.id = &"curse_test_loss"
	loss.kind = Ability.Kind.PASSIVE
	loss.max_tier = 1
	loss.tier = 1
	loss.percent_stats = [&"max_hp"] as Array[StringName]
	loss.percent_values = PackedFloat32Array([-0.5])
	player.take_ability(loss)
	assert_float(sim.cleanse_score(player)).is_greater(1.05)
