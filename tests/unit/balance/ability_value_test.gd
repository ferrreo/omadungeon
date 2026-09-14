## Is any option dead, and is any option dominant? Asked of the value function, not of the
## softmax that samples it.
##
## The playtest blocker, verbatim: "`test_no_ability_is_dominant_or_dead` — the project's only
## evidence that build variety is real — is structurally incapable of detecting a dead option,
## and its 'no dominant option' result is an artifact of one tuning constant." That was right.
## Thorns, Lucky Coin, Verbose Logging and Undervolt scored exactly 1.0000 on
## `SimOfferPolicy.score_of()` for all four classes — no measurable power change whatsoever —
## and still converted at 0.24-0.38, because at `pick_temperature = 0.06` a card worth nothing
## still wins a third of the boards it appears on. A pick rate is a softmax of a value; it can
## never fall below the floor the temperature puts under it, so it can never read zero.
##
## Every assertion here is on the value itself, and every one of them is shown to be able to
## fail by feeding it a card that is deliberately broken.
class_name AbilityValueTest
extends GdUnitTestSuite

const SEED := 20260912
## Build-to-build spread at which a card counts as one a build actually chooses: the best
## reference build wants it four times as much as the worst. Everything in the pool clears
## 1.5x just from diminishing returns - a plain +20% damage card measures 2.8x, because a
## build that already carries damage stats gains less from the next one - so 1.5 would count
## every card and measure nothing. Four is where "some builds want this" starts.
const BUILD_SENSITIVE_SPREAD := 4.0
## Passives the pool must hold that clear that bar, and actives. The shipped pool holds 11 and
## 7; the floors leave room for content edits without leaving room for the pool to flatten.
##
## Not "every card": a plain +armour or +lifesteal passive is worth close to the same to
## everybody and there is nothing wrong with that. What is wrong is a pool made entirely of
## them, which is the state the third playtest round measured - `rootkit`'s gain came back
## bit-identical on 27 of 37 reference builds because the model is a flat damage multiplier,
## and nothing in the suite would have noticed if every generic passive became one.
const MIN_BUILD_SENSITIVE_PASSIVES := 8
const MIN_BUILD_SENSITIVE_ACTIVES := 5

static var _measured: SimCardValue
static var _sim: RunSimulator


func simulator() -> RunSimulator:
	if _sim == null:
		_sim = RunSimulator.create()
	return _sim


## Every ability the offer pool can present, as resources.
func candidates() -> Array[Ability]:
	var out: Array[Ability] = []
	for ability: Ability in simulator().abilities.abilities:
		if ability == null or ability.weight <= 0.0:
			continue
		if AbilityRegistry.INNATE_IDS.has(ability.id):
			continue
		if String(ability.id).begins_with("curse_"):
			continue
		out.append(ability)
	return out


func candidate_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for ability: Ability in candidates():
		out.append(ability.id)
	return out


## The whole pool scored against builds real runs produced, shared by every test here.
func measured() -> SimCardValue:
	if _measured == null:
		var builds := SimCardValue.reference_builds(simulator(), SEED)
		_measured = SimCardValue.measure(
			simulator(), candidates(), builds, SimCardValue.reference_names(builds)
		)
	return _measured


func test_print_card_value_table() -> void:
	print("\n" + measured().to_text(candidate_ids()))
	print("builds: " + ", ".join(measured().build_names))
	for id: StringName in candidate_ids():
		if measured().best_share(id) < 0.4 or measured().top_share(id) > 0.3:
			print("  %-18s %s" % [String(id), str(measured().gains[id])])
	assert_int(measured().builds.size()).is_greater_equal(8)


func test_no_card_leaves_the_value_function_unmoved() -> void:
	# The assertion the old check could not make. A card that changes nothing measurable is not
	# "rarely taken", it is not an option at all - and no pick-rate table will ever say so.
	var inert := PackedStringArray()
	# A class's own starting active is never offered to anyone as a fresh card, so it has no
	# gain here at all; `test_every_class_starting_active_is_worth_its_slot` measures those
	# directly instead of letting them read as zero.
	var silent := measured().unmeasured(candidate_ids())
	for id: StringName in candidate_ids():
		if silent.has(id):
			continue
		if measured().best_gain(id) < SimCardValue.INERT_GAIN:
			inert.append("%s (%.4f)" % [String(id), measured().best_gain(id)])
	(
		assert_array(inert)
		. override_failure_message(
			"no build values these cards at anything at all: " + ", ".join(inert)
		)
		. is_empty()
	)


func test_the_cards_this_check_cannot_speak_for_are_named() -> void:
	# Honesty about the blind spot: a class's own starting active is carried by every build of
	# that class and shown to no other class, so no reference build is ever *offered* it and
	# nothing here can say whether it is dead. Rather than let it score as dead, it is listed —
	# and the list is asserted to contain only that, so a genuinely unreachable card cannot
	# hide in it.
	var starting: Array[StringName] = []
	for class_id: StringName in BalanceSim.CLASS_IDS:
		var def := load("%s/%s.tres" % [BalanceSim.CLASS_DIR, class_id]) as ClassDef
		starting.append(def.class_active_id)
		starting.append_array(def.extra_ability_ids)
	var silent := measured().unmeasured(candidate_ids())
	var unexplained := PackedStringArray()
	for id: StringName in silent:
		if not starting.has(id):
			unexplained.append(String(id))
	(
		assert_array(unexplained)
		. override_failure_message(
			(
				"no reference build can be offered these, and they are not class starting kit: "
				+ ", ".join(unexplained)
			)
		)
		. is_empty()
	)


func test_no_card_is_dead_or_dominant() -> void:
	var lines := PackedStringArray()
	var flagged := measured().outliers(candidate_ids())
	for id: StringName in flagged.keys():
		var entry := flagged[id] as Dictionary
		(
			lines
			. append(
				(
					(
						"%s %s (best build values it at %.2f of that build's best card of its kind, top"
						+ " pick for %.0f%% of builds, beating the runner-up by %.2fx)"
					)
					% [
						String(id),
						str(entry["kind"]),
						float(entry["share"]),
						float(entry["top"]) * 100.0,
						float(entry.get("margin", 1.0)),
					]
				)
			)
		)
	(
		assert_array(lines)
		. override_failure_message("card value out of band: " + ", ".join(lines))
		. is_empty()
	)


func test_the_pool_holds_cards_whose_worth_depends_on_the_build() -> void:
	# The half of "build variety" a dead-option check cannot state. Every card here can be
	# alive, every card can be non-dominant, and the pool can still pose no question at all if
	# each card is worth the same to every build - which is exactly what a flat damage
	# multiplier is under `power()`.
	var measurement := measured()
	var rows := PackedStringArray()
	for id: StringName in candidate_ids():
		if measurement.best_share(id) < 0.0:
			continue
		rows.append("%s %.2f" % [String(id), measurement.gain_spread(id)])
	print("card gain spread (best build / worst build): " + ", ".join(rows))
	var passives := measurement.build_sensitive(
		candidate_ids(), int(Ability.Kind.PASSIVE), BUILD_SENSITIVE_SPREAD
	)
	(
		assert_int(passives.size())
		. override_failure_message(
			(
				"only %d passives are worth more to one build than another (%s)"
				% [passives.size(), ", ".join(PackedStringArray(passives))]
			)
		)
		. is_greater_equal(MIN_BUILD_SENSITIVE_PASSIVES)
	)
	var actives := measurement.build_sensitive(
		candidate_ids(), int(Ability.Kind.ACTIVE), BUILD_SENSITIVE_SPREAD
	)
	(
		assert_int(actives.size())
		. override_failure_message(
			(
				"only %d actives are worth more to one build than another (%s)"
				% [actives.size(), ", ".join(PackedStringArray(actives))]
			)
		)
		. is_greater_equal(MIN_BUILD_SENSITIVE_ACTIVES)
	)


func test_the_check_can_see_a_pool_of_flat_multipliers() -> void:
	# Proof the assertion above can fail. A card whose whole payload is +20% to every damage
	# channel is worth roughly the same to every build - what little it varies by is the
	# diminishing return of stacking damage on damage - so it does not count towards the quota
	# however strong it is. A pool of these would be a pool with nothing to choose between.
	var flat := _synthetic(
		&"synthetic_flat", [&"damage_melee", &"damage_ranged", &"damage_ability"], [0.2, 0.2, 0.2]
	)
	var probe := _with_synthetic(flat)
	var ids: Array[StringName] = [&"synthetic_flat"]
	(
		assert_int(
			probe.build_sensitive(ids, int(Ability.Kind.PASSIVE), BUILD_SENSITIVE_SPREAD).size()
		)
		. override_failure_message(
			(
				"a flat damage card varied by %.2fx across builds, above the bar for a build choice"
				% probe.gain_spread(&"synthetic_flat")
			)
		)
		. is_equal(0)
	)


# --- the instrument, shown a fault ---------------------------------------------------------
#
# A detector nobody has ever shown a fault to is not a detector. Each of these builds a card
# with a known defect and asserts the check above would have caught it.


## A passive that grants `values` of `stats` at tier 1, or nothing at all when both are empty.
func _synthetic(id: StringName, stats: Array[StringName], values: Array[float]) -> StatPassive:
	var made := StatPassive.new()
	made.id = id
	made.display_name = String(id)
	made.kind = Ability.Kind.PASSIVE
	made.max_tier = 1
	made.weight = 1.0
	made.tier = 1
	made.flat_stats = stats
	made.flat_values = PackedFloat32Array(values)
	return made


func _with_synthetic(extra: StatPassive) -> SimCardValue:
	var pool := candidates()
	pool.append(extra)
	var builds := measured().builds
	return SimCardValue.measure(simulator(), pool, builds, SimCardValue.reference_names(builds))


func test_the_check_can_see_a_card_that_does_nothing() -> void:
	var empty: Array[StringName] = []
	var dud := _synthetic(&"synthetic_dud", empty, [])
	var probe := _with_synthetic(dud)
	assert_float(probe.best_gain(&"synthetic_dud")).is_less(SimCardValue.INERT_GAIN)
	var ids := candidate_ids()
	ids.append(&"synthetic_dud")
	var flagged := probe.outliers(ids)
	(
		assert_bool(flagged.has(&"synthetic_dud"))
		. override_failure_message("a card with no effect at all was not flagged")
		. is_true()
	)
	assert_str(str((flagged[&"synthetic_dud"] as Dictionary)["kind"])).is_equal("inert")


func test_the_check_can_see_a_card_that_is_merely_feeble() -> void:
	# Harder than the dud: this one does something, just far too little. The old pick-rate rule
	# could not see this either - at 0.06 temperature it still converts around a third.
	var dud := _synthetic(&"synthetic_crumb", [&"armor"], [2.0])
	var probe := _with_synthetic(dud)
	var ids := candidate_ids()
	ids.append(&"synthetic_crumb")
	var flagged := probe.outliers(ids)
	(
		assert_bool(flagged.has(&"synthetic_crumb"))
		. override_failure_message(
			(
				"+2 armour was worth %.2f of the best passive and was not called dead"
				% probe.best_share(&"synthetic_crumb")
			)
		)
		. is_true()
	)
	assert_str(str((flagged[&"synthetic_crumb"] as Dictionary)["kind"])).is_equal("dead")


func test_the_check_can_see_a_card_nobody_would_refuse() -> void:
	var monster := _synthetic(
		&"synthetic_monster",
		[&"damage_melee", &"damage_ranged", &"damage_ability"],
		[3.0, 3.0, 3.0]
	)
	var probe := _with_synthetic(monster)
	var ids := candidate_ids()
	ids.append(&"synthetic_monster")
	var flagged := probe.outliers(ids)
	(
		assert_bool(flagged.has(&"synthetic_monster"))
		. override_failure_message(
			(
				"+300%% damage was the top pick for %.0f%% of builds and was not called dominant"
				% (probe.top_share(&"synthetic_monster") * 100.0)
			)
		)
		. is_true()
	)
	assert_str(str((flagged[&"synthetic_monster"] as Dictionary)["kind"])).is_equal("dominant")


func test_the_value_function_sees_every_channel_a_card_can_pay_in() -> void:
	# The four blind spots the playtest found, one assertion each, on a build that is otherwise
	# identical. Without these the fixes above are invisible to the suite the moment someone
	# simplifies `power()`.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sim := simulator()
	var def := load("res://data/classes/fighter.tres") as ClassDef
	var player := SimPlayer.create(def, sim.items, sim.abilities, sim.profile, rng)
	player.floor_index = 4
	var channels := {
		&"reflect": _synthetic(&"probe_reflect", [], []),
		&"luck": _synthetic(&"probe_luck", [&"luck"], [1.0]),
		&"gold_find": _synthetic(&"probe_gold", [&"gold_find"], [1.0]),
		&"resist":
		_synthetic(
			&"probe_resist",
			[&"resist_fire", &"resist_frost", &"resist_shock", &"resist_poison", &"resist_arcane"],
			[0.9, 0.9, 0.9, 0.9, 0.9]
		),
		&"move_speed": _synthetic(&"probe_speed", [], []),
	}
	(channels[&"move_speed"] as StatPassive).percent_stats = [&"move_speed"] as Array[StringName]
	(channels[&"move_speed"] as StatPassive).percent_values = PackedFloat32Array([0.5])
	for channel: StringName in channels.keys():
		if channel == &"reflect":
			continue
		var score := SimOfferPolicy.score_of(channels[channel], player, sim.profile)
		(
			assert_float(score)
			. override_failure_message("%s is invisible to the offer policy" % String(channel))
			. is_greater(1.0)
		)
	# Reflect is not a `Stats` modifier, so it is checked through the real Thorns resource.
	var thorns := sim.abilities.instance(&"thorns")
	assert_object(thorns).is_not_null()
	(
		assert_float(SimOfferPolicy.score_of(thorns, player, sim.profile))
		. override_failure_message("SimEffect.reflect is written and never read")
		. is_greater(1.0)
	)


func test_a_crowd_control_active_is_worth_what_its_uptime_says() -> void:
	# Hostile Takeover holds a body for 10 s of its 12 s cooldown, which the model turns into
	# mitigation. This pins the chain from the .tres to the score, so "that card is dead" can be
	# answered with a number instead of a shrug.
	var sim := simulator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var def := load("res://data/classes/oligarch.tres") as ClassDef
	var player := SimPlayer.create(def, sim.items, sim.abilities, sim.profile, rng)
	var card := sim.abilities.instance(&"hostile_takeover")
	assert_object(card).is_not_null()
	var preview := player.clone()
	preview.drop_weakest(Ability.Kind.ACTIVE)
	var base_effect := preview.effect
	var after := preview.clone()
	after.take_ability(card)
	print(
		(
			(
				"[cc] base mitigation %.3f avoid %.3f dps %.2f ehp %.1f | after mitigation %.3f"
				+ " avoid %.3f dps %.2f ehp %.1f | power %.4f -> %.4f"
			)
			% [
				base_effect.mitigation,
				base_effect.avoid,
				preview.dps(),
				preview.ehp(),
				after.effect.mitigation,
				after.effect.avoid,
				after.dps(),
				after.ehp(),
				preview.power(),
				after.power(),
			]
		)
	)
	var cooldown := 12.0 * (1.0 - after.stats.get_value(&"cooldown_reduction"))
	var expected := (
		clampf(10.0 / cooldown, 0.0, 1.0) * BalanceProfile.load_default().cc_mitigation_share
	)
	(
		assert_float(after.effect.mitigation)
		. override_failure_message(
			(
				"the model turns a 10 s hold on a 12 s cooldown into %.3f mitigation, not %.3f"
				% [after.effect.mitigation, expected]
			)
		)
		. is_equal_approx(expected, 0.01)
	)


func test_every_class_starting_active_is_worth_its_slot() -> void:
	# The blind spot, closed rather than merely named: a class active is only ever a tier-up to
	# the class that starts with it and is shown to nobody else, so the offer-path check above
	# can say nothing about it. Here it is measured directly, against the generic actives the
	# same build could take instead.
	var sim := simulator()
	var weak := PackedStringArray()
	for class_id: StringName in BalanceSim.CLASS_IDS:
		var def := load("%s/%s.tres" % [BalanceSim.CLASS_DIR, class_id]) as ClassDef
		var rng := RandomNumberGenerator.new()
		rng.seed = RunRng.hash_combine(SEED, hash(class_id))
		var build := SimPlayer.create(def, sim.items, sim.abilities, sim.profile, rng)
		build.drop_weakest(Ability.Kind.ACTIVE)
		var card := sim.abilities.instance(def.class_active_id)
		(
			assert_object(card)
			. override_failure_message("%s has no class active" % class_id)
			. is_not_null()
		)
		var gain := SimOfferPolicy.score_of(card, build, sim.profile) - 1.0
		var best := 0.0
		for other: Ability in candidates():
			if other.kind != Ability.Kind.ACTIVE or other.id == def.class_active_id:
				continue
			if not sim.abilities.is_offerable(other, class_id, build.owned_tiers()):
				continue
			best = maxf(best, SimOfferPolicy.score_of(other, build, sim.profile) - 1.0)
		var share := gain / maxf(0.01, best)
		if gain < SimCardValue.INERT_GAIN or share < SimCardValue.DEAD_SHARE:
			weak.append(
				(
					"%s's %s gains %.3f, %.2f of the best generic active (%.3f)"
					% [String(class_id), String(def.class_active_id), gain, share, best]
				)
			)
	(
		assert_array(weak)
		. override_failure_message("class actives not worth their slot: " + ", ".join(weak))
		. is_empty()
	)
