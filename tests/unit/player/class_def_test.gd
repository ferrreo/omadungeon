## What `data/classes/*.tres` actually ships - and, since the doc drifted off the data once
## already, that docs/GAME_DESIGN.md 4.2 and 4.3 still describe the classes this file loads.
## The data is the source of truth in both directions: the doc is checked against it, never
## the other way round.
class_name PlayerClassDefTest
extends GdUnitTestSuite

## Every playable class, in class-select order.
const CLASS_IDS: Array[String] = ["fighter", "ranger", "wizard", "oligarch"]
## Characters a class card's clipped description box shows before it trims with an ellipsis.
const BLURB_BUDGET := 80


func test_fighter_ships_its_documented_loadout() -> void:
	var def := PlayerTestHelpers.load_class("fighter")
	assert_object(def).is_not_null()
	assert_str(String(def.id)).is_equal("fighter")
	assert_int(def.vitality).is_equal(6)
	assert_int(def.might).is_equal(6)
	assert_int(def.precision).is_equal(2)
	assert_int(def.arcana).is_equal(1)
	assert_int(def.swiftness).is_equal(3)
	assert_int(def.fortune).is_equal(2)
	assert_str(String(def.start_weapon_id)).is_equal("rusty_sword")
	assert_str(String(def.innate_passive_id)).is_equal("second_wind")
	assert_str(String(def.class_active_id)).is_equal("bulwark")
	assert_int(def.dodge_style).is_equal(ClassDef.DodgeStyle.ROLL)
	assert_str(String(def.dodge_style_name())).is_equal("roll")


func test_all_classes_load_with_loadouts() -> void:
	var expected := {
		"ranger": ["shortbow", "sure_footed", "volley", ClassDef.DodgeStyle.DASH],
		"wizard": ["staff", "overflow", "chain_lightning", ClassDef.DodgeStyle.BLINK],
		"oligarch": ["golden_cane", "buyout", "contract", ClassDef.DodgeStyle.DELEGATE],
	}
	for id: String in expected.keys():
		var def := PlayerTestHelpers.load_class(id)
		assert_object(def).override_failure_message("missing class %s" % id).is_not_null()
		var row: Array = expected[id]
		assert_str(String(def.start_weapon_id)).is_equal(row[0])
		assert_str(String(def.innate_passive_id)).is_equal(row[1])
		assert_str(String(def.class_active_id)).is_equal(row[2])
		assert_int(def.dodge_style).is_equal(row[3])
		assert_bool(ResourceLoader.exists(def.sprite_sheet_path())).is_true()
		assert_bool(ResourceLoader.exists(def.portrait_path())).is_true()


func test_stat_tables() -> void:
	var ranger := PlayerTestHelpers.load_class("ranger")
	(
		assert_array(
			[
				ranger.vitality,
				ranger.might,
				ranger.precision,
				ranger.arcana,
				ranger.swiftness,
				ranger.fortune
			]
		)
		. is_equal([4, 2, 5, 2, 5, 2])
	)
	var wizard := PlayerTestHelpers.load_class("wizard")
	(
		assert_array(
			[
				wizard.vitality,
				wizard.might,
				wizard.precision,
				wizard.arcana,
				wizard.swiftness,
				wizard.fortune
			]
		)
		. is_equal([4, 0, 2, 7, 4, 3])
	)
	var oligarch := PlayerTestHelpers.load_class("oligarch")
	(
		assert_array(
			[
				oligarch.vitality,
				oligarch.might,
				oligarch.precision,
				oligarch.arcana,
				oligarch.swiftness,
				oligarch.fortune
			]
		)
		. is_equal([4, 3, 3, 2, 2, 6])
	)
	assert_int(oligarch.start_gold).is_equal(150)
	assert_int(ranger.start_gold).is_equal(0)


func test_no_class_starts_with_a_second_active_prefilled() -> void:
	# The Oligarch used to be granted Contract on top of Hostile Takeover, which filled both
	# of its active slots before floor 1 and left it one build decision short of every other
	# class for the whole run. `extra_ability_ids` is the hole that let that happen.
	for id: String in CLASS_IDS:
		var def := PlayerTestHelpers.load_class(id)
		(
			assert_int(def.extra_ability_ids.size())
			. override_failure_message(
				"%s starts with %s pre-slotted" % [id, def.extra_ability_ids]
			)
			. is_equal(0)
		)


func test_every_class_card_says_what_the_class_does() -> void:
	for id: String in CLASS_IDS:
		var def := PlayerTestHelpers.load_class(id)
		assert_str(def.description).override_failure_message("%s has no blurb" % id).is_not_empty()
		assert_str(def.display_name).is_not_empty()
	# The Oligarch's whole run is shaped by one mechanic the card has to name outright.
	var oligarch := PlayerTestHelpers.load_class("oligarch")
	(
		assert_str(oligarch.description.to_lower())
		. override_failure_message("the Oligarch card never says chests cost gold")
		. contains("chests cost gold")
	)


func test_no_class_blurb_is_longer_than_its_card_can_show() -> void:
	# `ClassSelect` clips the blurb to a fixed-height box with OVERRUN_TRIM_ELLIPSIS, so an
	# over-long description is not "more information", it is a sentence cut off mid-word: the
	# Ranger card used to end on "long dash that..." and the Oligarch on "decoy...".
	for id: String in CLASS_IDS:
		var def := PlayerTestHelpers.load_class(id)
		(
			assert_int(def.description.length())
			. override_failure_message(
				"%s's blurb is %d chars; the card trims it" % [id, def.description.length()]
			)
			. is_less_equal(BLURB_BUDGET)
		)


func test_base_stats_dictionary_keys_match_stats_primary() -> void:
	var def := PlayerTestHelpers.load_class("wizard")
	var base := def.base_stats()
	for stat: StringName in Stats.PRIMARY:
		assert_bool(base.has(stat)).is_true()
	assert_int(int(base[&"arcana"])).is_equal(7)


## The §4.2 table in docs/GAME_DESIGN.md and `data/classes/*.tres` have to agree, and for two
## classes they did not: the doc said Ranger 3/2/6/2/5/2 and Wizard 2/1/2/7/4/4 where the
## shipped ones are 4/2/5/2/5/2 and 4/0/2/7/4/3. A reader treats that table as authoritative -
## it is the only place a build is described in numbers - so the drift is not cosmetic.
func test_the_design_doc_stat_table_matches_the_shipped_classes() -> void:
	var text := FileAccess.get_file_as_string("res://docs/GAME_DESIGN.md")
	assert_str(text).override_failure_message("docs/GAME_DESIGN.md is unreadable").is_not_empty()
	for id: String in CLASS_IDS:
		var def := PlayerTestHelpers.load_class(id)
		var row := (
			"| %s | %d | %d | %d | %d | %d | %d |"
			% [
				id.capitalize(),
				def.vitality,
				def.might,
				def.precision,
				def.arcana,
				def.swiftness,
				def.fortune
			]
		)
		(
			assert_bool(text.contains(row))
			. override_failure_message("docs/GAME_DESIGN.md 4.2 has no row `%s`" % row)
			. is_true()
		)


## ...and the same for the class active each class actually starts its pool with. The doc
## credited the Oligarch with *Hostile Takeover*; `class_active_id` is `contract`, and Hostile
## Takeover is a separate class-only card it may or may not be offered.
func test_the_design_doc_names_the_class_active_each_class_ships_with() -> void:
	var text := FileAccess.get_file_as_string("res://docs/GAME_DESIGN.md")
	var registry := AbilityRegistry.load_default()
	for id: String in CLASS_IDS:
		var def := PlayerTestHelpers.load_class(id)
		var ability := registry.find(def.class_active_id)
		assert_object(ability).override_failure_message("%s has no class active" % id).is_not_null()
		(
			assert_bool(text.contains("Class active: *%s*" % ability.display_name))
			. override_failure_message(
				(
					"docs/GAME_DESIGN.md 4.3 does not name %s's class active (%s)"
					% [id, ability.display_name]
				)
			)
			. is_true()
		)
