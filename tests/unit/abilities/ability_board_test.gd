## The shape of an ability board: three cards of one kind, and the kind is the one with a free
## slot.
##
## The fourth playtest round, verbatim: "An ability board that mixes an active with passives is
## not a decision while an active slot is open, because the active wins almost every time." It
## was not a taste judgement - `SimCardValue` measures every active's best gain at 0.25-0.75
## and every passive's at 0.04-0.19, so the weakest active on a board out-scores the best
## passive on it, and `SimOfferPolicy` softmaxes those two numbers against each other at a
## temperature of 0.06. Two of the three cards were scenery.
##
## The fix is upstream of the policy: a board is made of one kind, so the three cards on it are
## comparable and the choice between them is real. These are the assertions that keep it that
## way.
class_name AbilityBoardTest
extends GdUnitTestSuite

const SEED := 20260912
## Boards rolled per case. Enough that a board of the other kind would turn up.
const BOARDS := 40
const COUNT := 3


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## `BOARDS` ability boards rolled for `class_id`, with `prefer_kind` and `owned` as given.
func _boards(prefer_kind: int, owned: Dictionary = {}, class_id: StringName = &"fighter") -> Array:
	var registry := AbilityTestHelpers.registry()
	var out: Array = []
	for i in range(BOARDS):
		var rolled := ChestOffers.roll(
			Chest.Kind.ABILITY,
			COUNT,
			3,
			_rng(SEED + i),
			0.0,
			null,
			registry,
			null,
			class_id,
			owned,
			prefer_kind
		)
		out.append(rolled.offers)
	return out


## The kinds present on `offers`, as a sorted array of ints.
static func _kinds_on(offers: Array) -> Array[int]:
	var seen: Array[int] = []
	for ability: Ability in offers:
		if not seen.has(int(ability.kind)):
			seen.append(int(ability.kind))
	seen.sort()
	return seen


func test_a_board_never_mixes_actives_with_passives() -> void:
	for prefer_kind: int in [-1, int(Ability.Kind.ACTIVE), int(Ability.Kind.PASSIVE)]:
		for offers: Array in _boards(prefer_kind):
			assert_int(offers.size()).is_equal(COUNT)
			var kinds := _kinds_on(offers)
			(
				assert_int(kinds.size())
				. override_failure_message(
					(
						"a board rolled with prefer_kind %d shows %d kinds at once"
						% [prefer_kind, kinds.size()]
					)
				)
				. is_equal(1)
			)


func test_a_board_shows_the_kind_that_has_a_free_slot() -> void:
	# The slot rule that was already there, restated on a board that is now wholly one kind:
	# with the actives full, all three cards are passives the player can simply take.
	for kind: int in [int(Ability.Kind.ACTIVE), int(Ability.Kind.PASSIVE)]:
		for offers: Array in _boards(kind):
			for ability: Ability in offers:
				(
					assert_int(int(ability.kind))
					. override_failure_message(
						"%s is on a board asked for kind %d" % [String(ability.id), kind]
					)
					. is_equal(kind)
				)


func test_with_both_kinds_open_the_run_sees_both() -> void:
	# -1 means neither side is full, and a board is then one kind or the other by the roll. If
	# it were always the same kind the player would fill one pair of slots and never the other.
	var actives := 0
	var passives := 0
	for offers: Array in _boards(-1):
		if int((offers[0] as Ability).kind) == int(Ability.Kind.ACTIVE):
			actives += 1
		else:
			passives += 1
	(
		assert_int(actives)
		. override_failure_message("%d of %d open boards were actives" % [actives, BOARDS])
		. is_greater(BOARDS / 5)
	)
	(
		assert_int(passives)
		. override_failure_message("%d of %d open boards were passives" % [passives, BOARDS])
		. is_greater(BOARDS / 5)
	)


func test_a_short_board_is_topped_up_rather_than_left_short() -> void:
	# Deep in a run a kind's pool runs out - every passive owned or maxed. A two-card board is
	# worse than a mixed one, so the other kind fills the gap and the player still gets a row.
	var registry := AbilityTestHelpers.registry()
	var owned: Dictionary = {}
	for ability: Ability in registry.abilities:
		if ability != null and ability.kind == Ability.Kind.PASSIVE:
			owned[ability.id] = ability.max_tier
	for offers: Array in _boards(int(Ability.Kind.PASSIVE), owned):
		(
			assert_int(offers.size())
			. override_failure_message("a board with no passives left to show came back short")
			. is_equal(COUNT)
		)


func test_the_simulation_draws_the_same_board_shape_as_the_game() -> void:
	# `RunSimulator` rolls its own ability cards so it can control which ids count as unlocked.
	# It must still agree with `ChestOffers` about the shape of a board, or every number the
	# balance report gives about actives against passives is about a game nobody plays.
	var sim := RunSimulator.create()
	var def := load("res://data/classes/fighter.tres") as ClassDef
	var player := SimPlayer.create(def, sim.items, sim.abilities, sim.profile, _rng(SEED))
	# A fresh build has one active in and one free, and both passive slots free, so neither
	# kind is full: the roll decides, exactly as `prefer_kind_for` returning -1 does.
	assert_int(RunSimulator.prefer_kind_for(player)).is_equal(-1)
	player.take_ability(sim.abilities.instance(&"fireball"))
	(
		assert_int(RunSimulator.prefer_kind_for(player))
		. override_failure_message("both actives are in and the board is not steered to passives")
		. is_equal(int(Ability.Kind.PASSIVE))
	)
