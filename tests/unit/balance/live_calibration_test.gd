## Does the model describe the game it is supposed to be measuring?
##
## The playtest's charge: "the whole difficulty curve is validated only against a model with
## roughly ten free fudge constants and no calibration against the real game", and it was
## right — nothing in the tree compared a number the simulation predicts with a number the
## real scene tree produces. These tests do, in a real run, with real enemies, on floor 1 and
## floor 5.
##
## What is measurable headlessly and what is not, stated plainly rather than pretended away:
##
## * **Outgoing damage** is measurable. A real player holding the attack button on a real
##   dummy produces a damage-per-second the model must predict. This pins
##   `WeaponBase.effective_dps()`, the damage tags and the crit maths against the live hit
##   pipeline. It caught nothing about the old model only because nobody looked: the old model
##   ignored the bow charge entirely and priced the shortbow 1.25x off. All four classes are
##   measured, the Oligarch included: gold-in-hand as a damage multiplier exists in exactly two
##   places, `BuyoutPassive.wealth_bonus()` and `SimEffect.damage_per_gold`, and until the
##   Oligarch joined the loop nothing compared them.
## * **Incoming damage** is measurable per enemy: a real enemy attacking a real player lands a
##   damage-per-second that `EnemyDef.scaled_damage()` over `SimEncounter.attack_cycle()` must
##   predict.
## * **Avoidance and weapon uptime are not.** They describe how well a *person* plays, and a
##   headless test has no person in it. So they are not asserted as truths here; what is
##   asserted is that they are the only difference left between the model and the measurement,
##   and that their combined effect stays inside a stated band.
class_name LiveCalibrationTest
extends GdUnitTestSuite

const SEED := 90210
## The classes the outgoing measurement covers. It used to be three: the Oligarch was left out
## with no reason given, and it is the one class whose damage carries a term that exists nowhere
## but the passive-and-model pair below - gold in hand, priced by `BuyoutPassive.wealth_bonus()`
## on the game side and by `SimEffect.damage_per_gold` on the model side. "The model is
## calibrated" read as a claim about four classes while covering three.
const CALIBRATED_CLASSES: Array[StringName] = [&"fighter", &"ranger", &"wizard", &"oligarch"]
## Gold the purse is pinned to before an outgoing measurement. Fixed rather than "whatever the
## run start left", so both sides are asked about the same number and the wealth term is not
## trivially zero; the Oligarch's own 150 starting gold is the natural value.
const PURSE := 150
## How far the model may sit from the measurement before the build fails, either way.
const TOLERANCE := 0.3
## Seconds of held attack per outgoing sample. Long enough that crit variance averages out.
const ATTACK_SECONDS := 6.0
## Seconds of standing still under one enemy per incoming sample.
const EXPOSURE_SECONDS := 9.0
const PHYSICS_HZ := 60.0
## An ordinary melee enemy that exists on every floor, and the floors we calibrate on.
const MOOK_ID := &"honker"
const FLOORS: Array[int] = [0, 4]
## Floors the pacing measurement walks: the first, one in the middle and the last.
const PACING_FLOORS: Array[int] = [0, 4, 8]
## How many times the shortest possible walk `seconds_per_room` may be before it has stopped
## describing "walking to, entering and leaving a room" on this game's floors.
const PACING_SLACK := 3.0
## HP given to a dummy or to the player under test, so nothing dies mid-measurement.
const UNKILLABLE_HP := 200000.0


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	Input.action_release(&"attack")
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


# ---------------------------------------------------------------- outgoing


func test_the_model_predicts_the_damage_a_real_player_actually_deals() -> void:
	for class_id: StringName in CALIBRATED_CLASSES:
		var live := await _start(class_id)
		_set_purse(live)
		# The purse has to be visible to the passive before the measurement starts. `_gold` is fed
		# by `EventBus.gold_changed`, so a class that carries gold but whose Buyout never heard
		# about it would be measured *without* the wealth term while the model applied it - the
		# comparison would then be between two different games and would prove nothing.
		var purse := _buyout_of(live) as BuyoutPassive
		if purse != null:
			(
				assert_float(purse.wealth_bonus())
				. override_failure_message(
					"%s carries %d gold and Buyout prices it at nothing" % [class_id, live.gold]
				)
				. is_greater(0.0)
			)
		var dummy := await _dummy(live)
		var predicted := _model_dps(live)
		var measured := await _measure_outgoing(live, dummy)
		print(
			(
				"[calibration] %s model %.1f DPS vs game %.1f (%.0f%% out)"
				% [
					String(class_id),
					predicted,
					measured,
					absf(predicted / maxf(0.01, measured) - 1.0) * 100.0,
				]
			)
		)
		(
			assert_float(measured)
			. override_failure_message(
				"%s dealt no damage at all in %.0f s" % [class_id, ATTACK_SECONDS]
			)
			. is_greater(0.0)
		)
		(
			assert_float(predicted / measured)
			. override_failure_message(
				(
					"%s: the model says %.1f DPS, the game delivers %.1f (%.0f%% out)"
					% [
						String(class_id),
						predicted,
						measured,
						absf(predicted / measured - 1.0) * 100.0,
					]
				)
			)
			. is_between(1.0 - TOLERANCE, 1.0 + TOLERANCE)
		)
		dummy.queue_free()
		RunManager.abandon_run()
		await _frames(2)


# ---------------------------------------------------------------- incoming


func test_the_model_predicts_the_damage_a_real_enemy_actually_lands() -> void:
	var registry := RunManager.enemy_registry
	var def := registry.find(MOOK_ID)
	assert_object(def).is_not_null()
	for floor_index: int in FLOORS:
		var live := await _start(&"fighter")
		var measured := await _measure_incoming(live, def, floor_index)
		var predicted := def.scaled_damage(floor_index) / SimEncounter.attack_cycle(def)
		(
			assert_float(measured)
			. override_failure_message(
				(
					"floor %d: a real %s standing next to the player landed nothing"
					% [floor_index + 1, MOOK_ID]
				)
			)
			. is_greater(0.0)
		)
		(
			assert_float(predicted / measured)
			. override_failure_message(
				(
					"floor %d: the model says one %s deals %.1f DPS, it really deals %.1f"
					% [floor_index + 1, MOOK_ID, predicted, measured]
				)
			)
			. is_between(1.0 - TOLERANCE, 1.0 + TOLERANCE)
		)
		RunManager.abandon_run()
		await _frames(2)


# ---------------------------------------------------------------- the gap that is left


func test_the_behavioural_constants_are_the_only_gap_and_they_are_stated() -> void:
	# The simulation's floor-1 pack damage is the raw pressure above times a chain of terms
	# that describe a *person*: how much of a fight the pack spends alive, how much of its
	# output a moving player never eats, armour. This asserts the chain is what it claims to
	# be — so a future change to any of those constants shows up as a changed claim about the
	# player rather than as a silent change to "how hard floor 1 is".
	var profile := BalanceProfile.load_default()
	var sim := RunSimulator.create(profile)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var player := SimPlayer.create(_fighter(), sim.items, sim.abilities, profile, rng)
	var pack: Array[EnemyDef] = [sim.enemies.find(MOOK_ID), sim.enemies.find(MOOK_ID)]
	var quiet := BalanceProfile.load_default()
	quiet.room_noise = 0.0
	var fight := SimEncounter.resolve(player, pack, 0, false, quiet, rng)
	var raw := 0.0
	for entry: EnemyDef in pack:
		raw += entry.scaled_damage(0) / SimEncounter.attack_cycle(entry)
	raw *= fight.seconds
	var survived := fight.damage_taken / maxf(0.01, raw)
	var expected := (
		quiet.pack_alive_fraction
		* (1.0 - SimEncounter.avoidance_of(player, 0, false, quiet))
		* Stats.armor_multiplier(player.stats.get_value(&"armor"))
	)
	(
		assert_float(survived)
		. override_failure_message(
			(
				"the model keeps %.1f%% of a floor-1 pack's raw output; its stated terms give %.1f%%"
				% [survived * 100.0, expected * 100.0]
			)
		)
		. is_equal_approx(expected, 0.01)
	)
	# And the claim that chain makes about the player is a strong one, so it is written down as
	# a number a reader can argue with rather than left implicit in five multiplied constants.
	(
		assert_float(survived)
		. override_failure_message(
			"the scripted player eats %.0f%% of what floor 1 throws" % (survived * 100.0)
		)
		. is_between(0.08, 0.25)
	)


func test_the_hazard_share_the_offer_policy_uses_matches_what_runs_measure() -> void:
	# `hazard_damage_share` decides what a resistance card is worth. It is the one calibration
	# constant this module added, so it is pinned to the split the simulation itself produces
	# rather than left to drift.
	var profile := BalanceProfile.load_default()
	var sim := RunSimulator.create(profile)
	var hazard := 0.0
	var total := 0.0
	for i in range(24):
		var probe := HazardProbe.new()
		probe.simulator = sim
		probe.run(_fighter(), RunRng.hash_combine(SEED, i))
		hazard += probe.hazard
		total += probe.total
	var measured := hazard / maxf(1.0, total)
	(
		assert_float(profile.hazard_damage_share)
		. override_failure_message(
			(
				"the profile says %.0f%% of damage taken is hazard damage; runs measure %.0f%%"
				% [profile.hazard_damage_share * 100.0, measured * 100.0]
			)
		)
		. is_equal_approx(measured, 0.06)
	)


# ---------------------------------------------------------------- pacing


func test_the_seconds_per_room_constant_is_pinned_to_a_real_floors_geometry() -> void:
	# The headline design number - docs §2, "target total run time 20-35 min" - is asserted in
	# `balance_targets_test.test_run_length_matches_the_design_target()`, and almost half of the
	# minutes it sums come from three `@export`s in the Pacing group that nothing calibrated.
	# This is the one of the three a headless run *can* measure: `seconds_per_room` is time
	# spent walking, and a real generated floor knows exactly how far there is to walk.
	#
	# The measurement is the shortest honest walk: every corridor once and one crossing of every
	# room, at the real player's real `move_speed`. It is a floor, not a value - nobody walks a
	# perfect route, nobody skips the backtrack to a leaf room, and it counts none of the
	# hesitating, the door-reading or the looting. So the constant must sit above it, and not
	# more than `PACING_SLACK` times above it, which is the claim about the player this number
	# has always been making silently.
	var live := await _start(&"fighter")
	var speed := live.effective_speed()
	(
		assert_float(speed)
		. override_failure_message("the player has no move speed to measure against")
		. is_greater(0.0)
	)
	var profile := BalanceProfile.load_default()
	var walked_px := 0.0
	var rooms := 0
	var described := PackedStringArray()
	for index: int in PACING_FLOORS:
		var params := GenParams.from_profile(Desktop.profile, index)
		var data := FloorGenerator.generate(params, RunRng.new(SEED).floor_stream(&"gen", index))
		var floor_px := _walk_px(data)
		walked_px += floor_px
		rooms += data.rooms.size()
		described.append(
			(
				"F%d %d rooms %.0f px (%.1f s)"
				% [index + 1, data.rooms.size(), floor_px, floor_px / speed]
			)
		)
	assert_int(rooms).is_greater(0)
	var optimal := walked_px / float(rooms) / speed
	print(
		(
			"[calibration] pacing: %s -> %.1f s/room walked at %.0f px/s; profile says %.1f s"
			% [", ".join(described), optimal, speed, profile.seconds_per_room]
		)
	)
	(
		assert_float(profile.seconds_per_room)
		. override_failure_message(
			(
				(
					"seconds_per_room is %.1f s, but the shortest walk across a real floor is"
					+ " already %.1f s per room at %.0f px/s (%s). The pacing target cannot be"
					+ " met by a player who has to cover that ground."
				)
				% [profile.seconds_per_room, optimal, speed, ", ".join(described)]
			)
		)
		. is_greater_equal(optimal)
	)
	(
		assert_float(profile.seconds_per_room / optimal)
		. override_failure_message(
			(
				(
					"seconds_per_room is %.1fx the shortest walk (%.1f s vs %.1f s). Above %.1fx"
					+ " it is no longer a claim about walking this floor."
				)
				% [
					profile.seconds_per_room / optimal,
					profile.seconds_per_room,
					optimal,
					PACING_SLACK,
				]
			)
		)
		. is_less_equal(PACING_SLACK)
	)


func test_the_other_two_pacing_constants_are_stated_as_claims_about_the_player() -> void:
	# `seconds_per_chest` and `boss_overhead_seconds` are not measurable here for the same
	# reason `weapon_uptime` is not: they describe a person reading three cards and a person
	# circling an arena, and a headless run has no person in it. What can be done is what is
	# done for `survived` above - write the claim down as a number a reader can argue with,
	# instead of leaving it implicit in an `@export` nobody ever revisits.
	var profile := BalanceProfile.load_default()
	(
		assert_float(profile.seconds_per_chest)
		. override_failure_message(
			(
				"seconds_per_chest says a player reads a three-card offer and picks in %.1f s"
				% profile.seconds_per_chest
			)
		)
		. is_between(2.0, 10.0)
	)
	(
		assert_float(profile.boss_overhead_seconds)
		. override_failure_message(
			(
				(
					"boss_overhead_seconds says a boss arena costs %.1f s on top of the time its"
					+ " HP pool takes"
				)
				% profile.boss_overhead_seconds
			)
		)
		. is_between(5.0, 25.0)
	)


## The shortest honest walk across one generated floor, in pixels: every corridor traversed
## once, plus one crossing of every room. A route that actually visits every room walks most
## corridors twice, so this is a lower bound and is used as one.
func _walk_px(data: FloorData) -> float:
	var tiles := 0.0
	for corridor: FloorData.Corridor in data.corridors:
		tiles += float(corridor.path.size())
	for room: FloorData.Room in data.rooms:
		tiles += float(room.rect.size.x + room.rect.size.y) * 0.5
	return tiles * float(Layers.TILE)


# ---------------------------------------------------------------- helpers


## Damage per second the model predicts for the build `live` is actually carrying, with the
## behavioural uptime term divided back out (the measurement below holds the button down).
func _model_dps(live: Player) -> float:
	var profile := BalanceProfile.load_default()
	var gear := live.equipment as Equipment
	var worn := gear.get_item(&"weapon")
	var model := SimPlayer.bare(worn, profile)
	model.stats.from_dict(live.stats.to_dict())
	# The purse. A bare model carries no abilities, so for three of the four classes there is
	# nothing to add and this does nothing. For the Oligarch it is the whole point: the wealth
	# multiplier is the one damage term the simulation prices in a place of its own, and a
	# comparison that left it out of the model while the game applied it would either pass by
	# luck (the term is small at 150 gold) or fail for a reason that is not a mismatch. The live
	# build's own Buyout instance is handed over, so the two sides read the same `.tres`.
	var purse := _buyout_of(live)
	if purse != null:
		model.abilities[purse.id] = purse
		model.gold = live.gold
	model.recompute()
	return model.dps() / maxf(0.01, profile.weapon_uptime)


## The live build's Buyout passive, or null for a class that has none.
func _buyout_of(live: Player) -> PassiveAbility:
	var slots := AbilityUtil.slots_of(live)
	if slots == null:
		return null
	for passive: PassiveAbility in slots.all_passives():
		if passive is BuyoutPassive:
			return passive
	return null


## Pins the player's purse to `PURSE` through the real gold API, so `EventBus.gold_changed`
## fires and `BuyoutPassive` is looking at the same number the model is given.
func _set_purse(live: Player) -> void:
	live.add_gold(PURSE - live.gold)


## Holds the attack button on `dummy` and returns the damage per second that landed.
func _measure_outgoing(live: Player, dummy: EnemyBase) -> float:
	live.health.invulnerable = true
	live.facing = Vector2.RIGHT
	# A keyboard-and-mouse player aims at the cursor, and a headless run has the cursor parked
	# in the corner of a viewport nobody is looking at: the first version of this test swung
	# twelve times into empty floor and measured 0.0 DPS. Aiming the way a pad does - at the
	# nearest enemy - is the behaviour the model describes anyway.
	live.input.last_device = PlayerInput.Device.GAMEPAD
	live.input.auto_aim_target = dummy
	var swings: Array[int] = [0]
	var count := func(_style: WeaponBase.Style, _combo: int) -> void: swings[0] += 1
	live.weapon_controller.attacked.connect(count)
	var before := dummy.health.hp
	var home := dummy.global_position
	Input.action_press(&"attack")
	for tick in range(int(ATTACK_SECONDS * PHYSICS_HZ)):
		# A hurtbox that never moves is never *entered*, and an Area2D whose `monitoring` has
		# just been switched back on reports no overlaps until the next physics step. Nudging
		# the dummy a quarter of a pixel each tick keeps the rig honest without giving the
		# player anything to chase.
		dummy.global_position = home + Vector2(0.0, 0.25 if tick % 2 == 0 else -0.25)
		live.input.auto_aim_target = dummy
		await get_tree().physics_frame
	Input.action_release(&"attack")
	await _physics_frames(30)
	live.weapon_controller.attacked.disconnect(count)
	var dealt := before - dummy.health.hp
	print(
		(
			"[calibration] %s: %d attacks, %.0f damage in %.0f s -> %.1f DPS"
			% [
				String(live.class_id),
				swings[0],
				dealt,
				ATTACK_SECONDS,
				dealt / ATTACK_SECONDS,
			]
		)
	)
	(
		assert_int(swings[0])
		. override_failure_message("the attack button produced no attacks at all")
		. is_greater(0)
	)
	return dealt / ATTACK_SECONDS


## Stands still next to one live enemy and returns the damage per second it lands, before
## armour (which the model applies separately).
func _measure_incoming(live: Player, def: EnemyDef, floor_index: int) -> float:
	live.input.enabled = false
	live.health.setup(UNKILLABLE_HP)
	live.health.invulnerable = false
	live.stats.add_flat(&"armor", &"calibration", -live.stats.get_value(&"armor"))
	live.stats.add_flat(&"dodge_chance", &"calibration", -1.0)
	live.health.armor = 0.0
	live.health.dodge_chance = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var spot := live.global_position + Vector2(maxf(12.0, def.attack_range - 4.0), 0.0)
	var enemy := EnemySpawner.instantiate(def, floor_index, spot, rng)
	RunManager.floor_root().add_child(enemy)
	enemy.global_position = spot
	enemy.knockback_resistance = 1.0
	await _frames(2)
	var hits: Array[int] = [0]
	var amounts := PackedFloat32Array()
	var tally := func(info: DamageInfo) -> void:
		hits[0] += 1
		amounts.append(info.applied)
	live.health.damaged.connect(tally)
	var before := live.health.hp
	await _physics_frames(int(EXPOSURE_SECONDS * PHYSICS_HZ))
	live.health.damaged.disconnect(tally)
	var taken := before - live.health.hp
	print(
		(
			(
				"[calibration] %s F%d: %d hits, %.0f damage in %.0f s -> %.1f DPS (model %.1f,"
				+ " cycle %.2f s, per-attack %.1f)"
			)
			% [
				String(def.id),
				floor_index + 1,
				hits[0],
				taken,
				EXPOSURE_SECONDS,
				taken / EXPOSURE_SECONDS,
				def.scaled_damage(floor_index) / SimEncounter.attack_cycle(def),
				SimEncounter.attack_cycle(def),
				def.scaled_damage(floor_index),
			]
		)
	)
	print("[calibration]   per hit: %s" % str(amounts))
	enemy.queue_free()
	await _frames(2)
	return taken / EXPOSURE_SECONDS


## A frozen enemy with a bottomless health bar: a target that neither moves nor hits back, so
## what the measurement sees is the player's weapon and nothing else.
func _dummy(live: Player) -> EnemyBase:
	var registry := RunManager.enemy_registry
	var def := registry.find(MOOK_ID)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var spot := live.global_position + Vector2(14.0, 0.0)
	var enemy := EnemySpawner.instantiate(def, 0, spot, rng)
	RunManager.floor_root().add_child(enemy)
	enemy.global_position = spot
	await _frames(2)
	# Stats first: `Entity` re-syncs `Health` from `Stats` whenever a stat changes, so a health
	# bar widened before an armour change is quietly narrowed back to the def's own value.
	enemy.stats.add_flat(&"armor", &"calibration", -enemy.stats.get_value(&"armor"))
	enemy.stats.add_flat(&"max_hp", &"calibration", UNKILLABLE_HP)
	enemy.health.setup(UNKILLABLE_HP)
	enemy.health.armor = 0.0
	enemy.set_physics_process(false)
	enemy.set_process(false)
	await _frames(1)
	return enemy


## The Fighter `ClassDef`, loaded once.
func _fighter() -> ClassDef:
	return load("res://data/classes/fighter.tres") as ClassDef


## Starts a real run and clears the floor of everything the generator put on it, so what the
## measurement sees is the one enemy it spawned and not whichever pack wandered over. The first
## version of this test measured a honker at 13.3 DPS on floor 1 and 0.0 on floor 5 because the
## floor's own enemies were joining in and then not joining in.
func _start(class_id: StringName) -> Player:
	assert_bool(RunManager.new_run(SEED, class_id)).is_true()
	await _frames(4)
	var live := RunManager.player()
	assert_object(live).is_not_null()
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		node.queue_free()
	await _frames(2)
	return live


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## One headless run, recording how much of the damage it took came from hazards rather than
## from fights. `RunSimulator` reports the two separately only if somebody adds them up.
class HazardProbe:
	extends RefCounted
	var simulator: RunSimulator
	var hazard: float = 0.0
	var total: float = 0.0

	func run(def: ClassDef, seed_value: int) -> void:
		var result := simulator.simulate(def, seed_value)
		for value: float in result.floor_damage_taken:
			total += value
		hazard = simulator.hazard_damage
