## The achievement table as data (`data/progression/unlocks.tres`) and the progress rows the
## screens read off it.
##
## The table decides what a new player has to do to earn the rest of the game, so the things
## that would quietly break it get their own cases: a gate with no rule (content nobody can
## reach), a rule for an ungated id (a toast for something the player already had), a counter
## nothing in the game ever increments, and an unlock that hands out power rather than options.
class_name UnlockTableTest
extends GdUnitTestSuite

const SaveManagerScript := preload("res://src/core/save_manager.gd")

## Counters something in the project actually feeds. `kills`, `best_floor`, `gold_earned` and
## `flawless_floors` come from `SaveManager`/`RunManager`; the faction counters come from
## `RunManager._faction_counter`.
const FED_COUNTERS: Array[StringName] = [
	&"kills",
	&"best_floor",
	&"gold_earned",
	&"flawless_floors",
	&"clowns_killed",
	&"greybeards_killed",
	&"tinkerers_killed",
]
## Ids that are classes, not abilities.
const CLASS_IDS: Array[StringName] = [&"fighter", &"ranger", &"wizard", &"oligarch"]


func _table() -> UnlockTable:
	return UnlockTable.load_default()


func test_the_shipped_table_is_the_one_on_disk_not_the_fallback() -> void:
	assert_bool(ResourceLoader.exists(UnlockTable.PATH)).is_true()
	var table := _table()
	assert_int(table.entries.size()).is_equal(UnlockTable.FALLBACK.size())
	var fallback := UnlockTable.from_fallback()
	for def: UnlockDef in fallback.ordered():
		var shipped := table.find(def.id)
		assert_object(shipped).override_failure_message(String(def.id)).is_not_null()
		assert_str(shipped.title).override_failure_message(String(def.id)).is_equal(def.title)
		assert_int(shipped.threshold).override_failure_message(String(def.id)).is_equal(
			def.threshold
		)
		assert_that(shipped.counter).override_failure_message(String(def.id)).is_equal(def.counter)


func test_the_table_and_the_profile_gate_list_agree() -> void:
	assert_bool(_table().matches_profile_gates()).is_true()


## A threshold on a counter nothing increments is an unlock nobody can ever earn.
func test_every_rule_watches_a_counter_the_game_actually_feeds() -> void:
	for def: UnlockDef in _table().ordered():
		(
			assert_bool(FED_COUNTERS.has(def.counter))
			. override_failure_message(
				"%s waits on '%s', which nothing increments" % [String(def.id), String(def.counter)]
			)
			. is_true()
		)


## Docs §12: unlocks are content and options, never stat boosts. Everything the table grants
## has to be a class or an ability, so the check is that it is one of those and nothing else.
func test_unlocks_are_only_classes_and_abilities() -> void:
	var registry := AbilityRegistry.load_default()
	for def: UnlockDef in _table().ordered():
		if def.grants_class():
			(
				assert_bool(CLASS_IDS.has(def.id))
				. override_failure_message("%s is marked a class but is not one" % String(def.id))
				. is_true()
			)
			continue
		(
			assert_object(registry.find(def.id))
			. override_failure_message("%s is neither a class nor an ability" % String(def.id))
			. is_not_null()
		)


## The ladder a new player climbs: three classes, cheapest first, and the first one reachable
## inside the first run or two.
func test_the_class_ladder_is_ordered_and_starts_cheap() -> void:
	var classes := _table().class_entries()
	assert_int(classes.size()).is_equal(3)
	assert_that(classes[0].id).is_equal(&"ranger")
	assert_that(classes[2].id).is_equal(&"oligarch")
	assert_int(classes[0].threshold).is_less_equal(1)
	for def: UnlockDef in classes:
		(
			assert_bool(Profile.new().is_unlocked(def.id))
			. override_failure_message(String(def.id))
			. is_false()
		)


func test_progress_text_and_fraction_clamp() -> void:
	var def := UnlockDef.new()
	def.threshold = 50
	assert_str(def.progress_text(0)).is_equal("0 / 50")
	assert_str(def.progress_text(12)).is_equal("12 / 50")
	assert_str(def.progress_text(80)).is_equal("50 / 50")
	assert_str(def.progress_text(-3)).is_equal("0 / 50")
	assert_float(def.fraction(25)).is_equal_approx(0.5, 0.001)
	assert_float(def.fraction(999)).is_equal(1.0)


## The rows the unlock board and the run summary read: locked ones first, closest first, with
## the earned ones after them.
func test_progress_rows_put_the_closest_locked_unlock_first() -> void:
	var manager: Node = auto_free(SaveManagerScript.new())
	manager.run_path = SaveManager.test_sandbox_dir() + "/unlock_rows_run.json"
	manager.profile_path = SaveManager.test_sandbox_dir() + "/unlock_rows_profile.json"
	add_child(manager)
	manager.profile = Profile.new()
	manager.profile.add_counter(&"kills", 119)  # one short of the Wizard
	manager.profile.add_counter(&"clowns_killed", 2)
	var rows: Array[Dictionary] = manager.progress_rows()
	assert_int(rows.size()).is_equal(Profile.GATED_UNLOCKS.size())
	assert_that(StringName(str(rows[0]["id"]))).is_equal(&"wizard")
	assert_str(str(rows[0]["progress"])).is_equal("119 / 120")
	assert_bool(bool(rows[0]["unlocked"])).is_false()
	var next: Dictionary = manager.next_unlock()
	assert_that(StringName(str(next["id"]))).is_equal(&"wizard")
	# One more kill and it is earned, announced, and reported as this run's doing.
	var earned: Array[StringName] = manager.increment(&"kills")
	assert_array(earned).contains_exactly([&"wizard"])
	assert_array(manager.unlocks_this_run()).contains([&"wizard"])
	rows = manager.progress_rows()
	var wizard_row: Dictionary = {}
	for row: Dictionary in rows:
		if str(row["id"]) == "wizard":
			wizard_row = row
	assert_bool(bool(wizard_row["unlocked"])).is_true()
	assert_bool(bool(wizard_row["earned_this_run"])).is_true()
	assert_str(str(wizard_row["progress"])).is_equal("120 / 120")


## What the run moved, for the summary's "This run: +N kills" line.
func test_counter_gains_are_measured_from_the_start_of_the_run() -> void:
	var manager: Node = auto_free(SaveManagerScript.new())
	manager.run_path = SaveManager.test_sandbox_dir() + "/gains_run.json"
	manager.profile_path = SaveManager.test_sandbox_dir() + "/gains_profile.json"
	add_child(manager)
	manager.profile = Profile.new()
	manager.profile.add_counter(&"kills", 40)
	EventBus.run_started.emit(99)
	assert_dict(manager.counter_gains_this_run()).is_empty()
	manager.increment(&"kills", 17)
	manager.increment(&"clowns_killed", 3)
	var gains: Dictionary = manager.counter_gains_this_run()
	assert_int(int(gains.get("kills", 0))).is_equal(17)
	assert_int(int(gains.get("clowns_killed", 0))).is_equal(3)
	assert_bool(gains.has("gold_earned")).is_false()
	EventBus.run_ended.emit(false)
