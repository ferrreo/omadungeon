class_name AbilityRegistryTest
extends GdUnitTestSuite

const ALL_IDS: Array[StringName] = AbilityRegistry.ICON_ORDER
## Cursed-chest pacts: max tier 1, weight 0, one shared script, never offered.
const CURSE_IDS: Array[StringName] = [&"curse_1", &"curse_2", &"curse_3"]
## Abilities that are nothing but `Stats` modifiers and so share `stat_passive.gd` rather than
## carrying a script of their own. Their whole behaviour is in the `.tres`, which is the point:
## a passive that is a number on a stat sheet should not cost a file.
const SHARED_SCRIPT := "res://src/abilities/passives/stat_passive.gd"


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_registry_loads_every_ability_with_script_and_icon() -> void:
	var registry := AbilityTestHelpers.registry()
	assert_object(registry).is_not_null()
	assert_int(registry.abilities.size()).is_equal(ALL_IDS.size())
	for id: StringName in ALL_IDS:
		var a := registry.find(id)
		assert_object(a).override_failure_message("missing %s" % id).is_not_null()
		assert_str(a.display_name).is_not_empty()
		assert_object(a.icon).override_failure_message("no icon for %s" % id).is_not_null()
		var script := a.get_script() as Script
		if CURSE_IDS.has(id):
			assert_int(a.max_tier).is_equal(1)
			assert_float(a.weight).is_equal(0.0)
			assert_str(script.resource_path).is_equal("res://src/abilities/passives/curse.gd")
		else:
			assert_int(a.max_tier).is_equal(3)
			if script.resource_path != SHARED_SCRIPT:
				(
					assert_str(script.resource_path)
					. override_failure_message(
						(
							"%s runs %s, which is neither its own script nor the shared stat passive"
							% [String(id), script.resource_path]
						)
					)
					. contains(String(id))
				)
	assert_object(registry.find(&"nope")).is_null()


func test_instance_returns_fresh_copy() -> void:
	var registry := AbilityTestHelpers.registry()
	var a := registry.instance(&"fireball")
	var b := registry.instance(&"fireball")
	assert_object(a).is_not_same(b)
	a.tier = 3
	assert_int(b.tier).is_equal(1)
	assert_int(registry.find(&"fireball").tier).is_equal(1)


func test_innates_and_starting_actives_per_class() -> void:
	var registry := AbilityTestHelpers.registry()
	assert_str(String(registry.innate_for(&"fighter").id)).is_equal("second_wind")
	assert_str(String(registry.innate_for(&"ranger").id)).is_equal("sure_footed")
	assert_str(String(registry.innate_for(&"wizard").id)).is_equal("overflow")
	assert_str(String(registry.innate_for(&"oligarch").id)).is_equal("buyout")
	assert_object(registry.innate_for(&"bard")).is_null()
	# No class is granted an extra active on top of its class active: that is what made the
	# Oligarch start with both slots full and one build decision fewer than everybody else.
	for id: StringName in [&"fighter", &"ranger", &"wizard", &"oligarch"]:
		(
			assert_int(registry.starting_actives_for(id).size())
			. override_failure_message("%s is granted a bonus starting active" % id)
			. is_equal(0)
		)


func test_innates_and_starting_actives_come_from_class_data() -> void:
	var registry := AbilityTestHelpers.registry()
	var oligarch := load("res://data/classes/oligarch.tres") as ClassDef
	assert_str(String(registry.innate_for(oligarch).id)).is_equal("buyout")
	assert_int(registry.starting_actives_for(oligarch).size()).is_equal(0)
	var fighter := load("res://data/classes/fighter.tres") as ClassDef
	assert_str(String(registry.innate_for(fighter).id)).is_equal("second_wind")
	assert_int(registry.starting_actives_for(fighter).size()).is_equal(0)
	# docs §4.3: the Oligarch "starts with ... a Contract", and its unique class active is
	# Hostile Takeover, "available in its pool". Both halves ship, and they cost one active
	# slot between them rather than two: Contract is `class_active_id`, so it is granted, and
	# Hostile Takeover is the class-only card the Oligarch alone can be offered for the slot
	# that is still open. The Oligarch used to be handed both, which filled every active slot
	# it had before floor 1 and turned every active it was ever offered into a forced downgrade.
	assert_str(String(oligarch.class_active_id)).is_equal("contract")
	var contract := registry.find(&"contract")
	assert_object(contract).is_not_null()
	assert_str(String(contract.class_only)).is_equal("oligarch")
	var takeover := registry.find(&"hostile_takeover")
	assert_object(takeover).is_not_null()
	assert_str(String(takeover.class_only)).is_equal("oligarch")
	(
		assert_bool(registry.is_offerable(takeover, &"oligarch", {}))
		. override_failure_message("the Oligarch can never be offered Hostile Takeover")
		. is_true()
	)
	assert_bool(registry.is_offerable(takeover, &"fighter", {})).is_false()
	assert_bool(registry.is_offerable(contract, &"fighter", {})).is_false()


func test_curses_resolve_but_are_never_offered() -> void:
	var registry := AbilityTestHelpers.registry()
	for id: StringName in CURSE_IDS:
		var curse := registry.find(id)
		assert_object(curse).override_failure_message("missing %s" % id).is_not_null()
		assert_bool(registry.is_offerable(curse, &"fighter", {})).is_false()
	for seed_value in range(30):
		for a: Ability in registry.offer(_rng(seed_value), 3, &"fighter", {}):
			assert_bool(CURSE_IDS.has(a.id)).is_false()


func test_curse_applies_its_pact_to_the_player() -> void:
	# A curse is the price of a cursed chest's Legendary, so it is pure downside - and every
	# one of the three has to actually land, and has to come off cleanly when a Shrine
	# cleanses it. Each expectation below is the curse's own shipped description. curse_3 has
	# no `Stats` factor to list: its dodge half is an outright removal (checked below) and its
	# damage half is a multiplier on the outgoing hit, measured in its own test.
	var expected := {
		&"curse_1": {&"max_hp": 0.7},
		&"curse_2": {&"attack_speed": 0.7, &"move_speed": 0.85},
		&"curse_3": {},
	}
	for id: StringName in expected.keys():
		var player: DummyPlayer = auto_free(AbilityTestHelpers.make_player())
		add_child(player)
		var curse := AbilityTestHelpers.registry().instance(id) as CursePassive
		assert_object(curse).override_failure_message("missing %s" % id).is_not_null()
		var before: Dictionary = {}
		var factors: Dictionary = expected[id]
		for stat: StringName in factors:
			before[stat] = player.stats.get_value(stat)
		curse.apply(player)
		for stat: StringName in factors:
			var factor := float(factors[stat])
			var want := (
				float(before[stat]) * factor if factor > 0.0 else float(before[stat]) + factor
			)
			(
				assert_float(player.stats.get_value(stat))
				. override_failure_message("%s did not change %s" % [id, stat])
				. is_equal_approx(want, 0.001)
			)
		curse.remove(player)
		for stat: StringName in factors:
			(
				assert_float(player.stats.get_value(stat))
				. override_failure_message("cleansing %s did not restore %s" % [id, stat])
				. is_equal_approx(float(before[stat]), 0.001)
			)
	# Root Access takes dodge away outright rather than shaving it.
	var dodge_player: DummyPlayer = auto_free(AbilityTestHelpers.make_player())
	add_child(dodge_player)
	dodge_player.stats.add_flat(&"dodge_chance", &"test", 0.2)
	var root := AbilityTestHelpers.registry().instance(&"curse_3") as CursePassive
	root.apply(dodge_player)
	assert_float(dodge_player.stats.get_value(&"dodge_chance")).is_less_equal(0.0)


## Root Access's card promises "-20% damage dealt". It used to subtract 0.2 from
## `damage_melee`/`damage_ranged`/`damage_ability`, which are additive *bonus* stats consumed
## as `1.0 + value`: that cut a Might-6 Fighter by 16%, a Might-25 build by 10%, and a Wizard
## below its own baseline. The pact got cheaper exactly as the build it prices got stronger,
## which is backwards for the price of a cursed chest's Legendary. So: measure the real cut,
## at several Might levels, on every damage tag.
func test_root_access_costs_a_flat_fifth_of_damage_at_every_might() -> void:
	var might_levels: Array[int] = [1, 6, 25]
	for might: int in might_levels:
		var player: DummyPlayer = auto_free(AbilityTestHelpers.make_player())
		add_child(player)
		var slots := AbilityTestHelpers.attach_slots(player)
		player.stats.add_primary(&"might", might)
		player.stats.add_primary(&"precision", might)
		player.stats.add_primary(&"arcana", might)
		for tag: StringName in [
			DamageInfo.TAG_MELEE, DamageInfo.TAG_RANGED, DamageInfo.TAG_ABILITY
		]:
			var tags: Array[StringName] = [tag]
			var before := player.damage_multiplier(tags)
			var curse := AbilityTestHelpers.registry().instance(&"curse_3") as CursePassive
			assert_bool(slots.add(curse)).is_true()
			var info := DamageInfo.create(10.0, tags, player, player.team)
			var after := (
				player.damage_multiplier(tags) * slots.outgoing_damage_multiplier(null, info)
			)
			(
				assert_float(after / before)
				. override_failure_message(
					(
						"curse_3 cuts %s by %.1f%% at might %d"
						% [tag, 100.0 - 100.0 * after / before, might]
					)
				)
				. is_equal_approx(0.8, 0.0001)
			)
			slots.remove(slots.index_of(&"curse_3"))
			(
				assert_float(player.damage_multiplier(tags))
				. override_failure_message("cleansing curse_3 did not restore %s" % tag)
				. is_equal_approx(before, 0.0001)
			)


func test_offer_respects_class_only_innates_and_maxed() -> void:
	var registry := AbilityTestHelpers.registry()
	var owned := {&"fireball": 3, &"thorns": 2}
	for seed_value in range(20):
		var offer := registry.offer(_rng(seed_value), 3, &"ranger", owned)
		assert_int(offer.size()).is_equal(3)
		var ids: Array[StringName] = []
		for a: Ability in offer:
			assert_bool(ids.has(a.id)).override_failure_message("duplicate %s" % a.id).is_false()
			ids.append(a.id)
			assert_bool(AbilityRegistry.INNATE_IDS.has(a.id)).is_false()
			assert_bool(a.class_only == &"" or a.class_only == &"ranger").is_true()
			assert_str(String(a.id)).is_not_equal("fireball")
			assert_str(String(a.id)).is_not_equal("bulwark")
			assert_str(String(a.id)).is_not_equal("chain_lightning")
			if a.id == &"thorns":
				assert_int(a.tier).is_equal(3)
			else:
				assert_int(a.tier).is_equal(1)


func test_offer_is_deterministic_and_seed_sensitive() -> void:
	var registry := AbilityTestHelpers.registry()
	var a := registry.offer(_rng(42), 3, &"wizard", {})
	var b := registry.offer(_rng(42), 3, &"wizard", {})
	for i in range(3):
		assert_str(String(a[i].id)).is_equal(String(b[i].id))
	var differs := false
	for seed_value in range(1, 30):
		var c := registry.offer(_rng(seed_value), 3, &"wizard", {})
		if c[0].id != a[0].id:
			differs = true
			break
	assert_bool(differs).is_true()


func test_offer_prefers_kind_then_tops_up() -> void:
	var registry := AbilityTestHelpers.registry()
	var offer := registry.offer(_rng(3), 3, &"fighter", {}, Ability.Kind.PASSIVE)
	for a: Ability in offer:
		assert_bool(a.is_active()).is_false()
	# Only two non-innate passives left unowned-but-not-maxed -> third slot is an active.
	var owned: Dictionary = {}
	for id: StringName in ALL_IDS:
		var ability := registry.find(id)
		if not ability.is_active() and id != &"thorns" and id != &"vampiric":
			owned[id] = 3
	var mixed := registry.offer(_rng(5), 3, &"fighter", owned, Ability.Kind.PASSIVE)
	assert_int(mixed.size()).is_equal(3)
	assert_bool(mixed[0].is_active()).is_false()
	assert_bool(mixed[1].is_active()).is_false()
	assert_bool(mixed[2].is_active()).is_true()


func test_weights_bias_offers() -> void:
	var registry := AbilityTestHelpers.registry()
	var hits := 0
	for seed_value in range(200):
		var offer := registry.offer(_rng(seed_value), 1, &"fighter", {}, Ability.Kind.ACTIVE)
		if offer[0].id == &"bulwark":
			hits += 1
	# bulwark weighs 1.5 among 9 offerable actives (8 x 1.0 + 1.5): expect roughly 15%.
	assert_int(hits).is_between(10, 60)


func test_icon_regions_follow_sheet_layout() -> void:
	var icon := AbilityRegistry.icon_for(&"thorns")
	assert_object(icon).is_not_null()
	var columns := maxi(1, int(icon.atlas.get_width()) / AbilityRegistry.ICON_SIZE)
	var index := AbilityRegistry.icon_index(&"thorns")
	assert_int(index).is_equal(13)
	assert_float(icon.region.position.x).is_equal(float((index % columns) * 16))
	assert_float(icon.region.position.y).is_equal(float((index / columns) * 16))
	assert_float(icon.region.size.x).is_equal(16.0)
	assert_object(AbilityRegistry.icon_for(&"nope")).is_null()
