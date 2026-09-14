## Every class must reach floor 1 with the same number of build decisions in front of it.
##
## The Oligarch used to start with both active slots full (Hostile Takeover from
## `class_active_id`, Contract from `extra_ability_ids`), so for the whole run every active it
## was offered was a forced downgrade of a class-defining ability, and it made two free ability
## picks against everyone else's three. This suite builds the real starting loadout through the
## real `AbilityRegistry` + `AbilitySlots` and counts the empty sockets.
##
## The grant sequence mirrors `RunManager._setup_player()`: innate passive, class active, then
## `starting_actives_for(def)`. If that order ever changes, change it here too.
class_name PlayerClassLoadoutTest
extends GdUnitTestSuite

const CLASS_IDS: Array[String] = ["fighter", "ranger", "wizard", "oligarch"]


## Builds `id`'s run-start loadout and returns it as `{actives_free, passives_free, innates}`.
func _starting_loadout(id: String) -> Dictionary:
	var registry := AbilityRegistry.load_default()
	var def := PlayerTestHelpers.load_class(id)
	var player := auto_free(AbilityTestHelpers.make_player()) as DummyPlayer
	add_child(player)
	var slots := AbilityTestHelpers.attach_slots(player)
	var innate := registry.innate_for(def)
	if innate != null:
		slots.add_innate(innate)
	var active := registry.instance(def.class_active_id)
	if active != null:
		slots.add(active)
	for starting: ActiveAbility in registry.starting_actives_for(def):
		slots.add(starting)
	var actives_free := 0
	for i in range(AbilitySlots.ACTIVE_COUNT):
		if slots.get_ability(i) == null:
			actives_free += 1
	var passives_free := 0
	for i in range(AbilitySlots.PASSIVE_COUNT):
		if slots.get_ability(i + AbilitySlots.ACTIVE_COUNT) == null:
			passives_free += 1
	return {
		"actives_free": actives_free,
		"passives_free": passives_free,
		"innates": slots.innates.size(),
	}


func test_every_class_starts_with_the_same_number_of_free_ability_slots() -> void:
	var first := _starting_loadout(CLASS_IDS[0])
	for id: String in CLASS_IDS:
		var loadout := _starting_loadout(id)
		(
			assert_int(int(loadout["actives_free"]))
			. override_failure_message(
				(
					"%s starts with %d free active slots, %s with %d"
					% [id, loadout["actives_free"], CLASS_IDS[0], first["actives_free"]]
				)
			)
			. is_equal(int(first["actives_free"]))
		)
		(
			assert_int(int(loadout["passives_free"]))
			. override_failure_message("%s has a different number of free passive slots" % id)
			. is_equal(int(first["passives_free"]))
		)


func test_a_run_starts_with_one_active_and_both_passive_slots_open() -> void:
	for id: String in CLASS_IDS:
		var loadout := _starting_loadout(id)
		# One class active in, one socket free: the first active a chest offers is a choice,
		# never a trade against the ability that defines the class.
		assert_int(int(loadout["actives_free"])).is_equal(AbilitySlots.ACTIVE_COUNT - 1)
		assert_int(int(loadout["passives_free"])).is_equal(AbilitySlots.PASSIVE_COUNT)
		# The innate passive is uncounted, so it never eats one of those two sockets.
		(
			assert_int(int(loadout["innates"]))
			. override_failure_message("%s lost its innate" % id)
			. is_equal(1)
		)


func test_every_class_active_is_class_only_and_never_reoffered() -> void:
	var registry := AbilityRegistry.load_default()
	for id: String in CLASS_IDS:
		var def := PlayerTestHelpers.load_class(id)
		var active := registry.instance(def.class_active_id)
		assert_object(active).override_failure_message("%s has no class active" % id).is_not_null()
		(
			assert_str(String(active.class_only))
			. override_failure_message("%s's class active is offered to everyone" % id)
			. is_equal(id)
		)
