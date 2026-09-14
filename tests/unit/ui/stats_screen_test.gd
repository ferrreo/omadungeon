## The profile statistics table, against the dictionary the game really hands it
## (`Profile.to_dict()`) rather than a hand-written fixture. Every case here is a state a
## player is in on a real machine: a profile that has never been played, one with a single run
## behind it, and one with a long history - the first of which rendered its schema version, its
## fourteen default unlock ids and three rows reading "{ }".
class_name StatsScreenTest
extends GdUnitTestSuite

const SCENE := "res://src/ui/stats_screen.tscn"


## The table's rows are freed with `queue_free()` on every rebuild.
func after_test() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _screen() -> StatsScreen:
	var screen: StatsScreen = auto_free((load(SCENE) as PackedScene).instantiate())
	add_child(screen)
	return screen


func test_a_profile_that_has_never_been_played_reads_as_a_summary() -> void:
	var screen := _screen()
	screen.show_stats(Profile.new().to_dict())
	var text := _table(screen)

	# Runs, wins, win rate, unlocks - and nothing else, because there is nothing else yet.
	assert_int(screen.row_count()).is_equal(4)
	assert_str(text).contains("Runs")
	assert_str(text).contains("Win Rate")
	assert_str(text).contains(StatsScreen.NO_VALUE)
	assert_str(text).contains("0 / %d" % Profile.GATED_UNLOCKS.size())
	assert_str(text).contains(StatsScreen.NO_HISTORY)

	# None of the save file's own plumbing reaches the screen: no schema version, no unlock id
	# list printed as one run-on array, and no container stringified into a value cell.
	assert_str(text).not_contains("Version")
	assert_str(text).not_contains("fireball")
	assert_str(text).not_contains("{")
	assert_str(text).not_contains("[")

	# An empty section is left out rather than drawn as a heading with nothing under it.
	assert_str(text).not_contains(StatsScreen.TITLES["counters"])
	assert_str(text).not_contains(StatsScreen.TITLES["deaths_by_enemy"])
	assert_str(text).not_contains(StatsScreen.TITLES["best_floor_per_class"])


func test_one_recorded_run_fills_the_summary_and_its_sections() -> void:
	var screen := _screen()
	var profile := Profile.new()
	profile.runs = 1
	profile.best_floor_per_class = {"fighter": 3}
	profile.deaths_by_enemy = {"bit_rot": 1}
	profile.add_counter(&"rooms_cleared", 12)
	screen.show_stats(profile.to_dict())
	var text := _table(screen)

	assert_int(screen.row_count()).is_equal(4 + 1 + 1 + 1)
	assert_str(text).not_contains(StatsScreen.NO_HISTORY)
	assert_str(text).contains("0%")
	assert_str(text).contains(StatsScreen.TITLES["best_floor_per_class"])
	assert_str(text).contains("Fighter")
	assert_str(text).contains(StatsScreen.TITLES["deaths_by_enemy"])
	assert_str(text).contains("Bit Rot")
	assert_str(text).contains(StatsScreen.TITLES["counters"])
	assert_str(text).contains("Rooms Cleared")


func test_a_won_run_states_the_win_rate_and_the_unlocks_it_earned() -> void:
	var screen := _screen()
	var profile := Profile.new()
	profile.runs = 4
	profile.wins = 1
	profile.per_theme_wins = {"Tokyo Night": 1}
	assert_bool(profile.unlock(&"ranger")).is_true()
	screen.show_stats(profile.to_dict())
	var text := _table(screen)
	assert_str(text).contains("25%")
	assert_str(text).contains("1 / %d" % Profile.GATED_UNLOCKS.size())
	assert_str(text).contains(StatsScreen.TITLES["per_theme_wins"])
	assert_str(text).contains("Tokyo Night")


func test_a_long_history_is_ranked_rather_than_alphabetical() -> void:
	var screen := _screen()
	var profile := Profile.new()
	profile.runs = 140
	profile.wins = 31
	for i in range(14):
		profile.deaths_by_enemy["enemy_%02d" % i] = i + 1
		profile.counters["milestone_%02d" % i] = i * 7
	profile.best_floor_per_class = {"fighter": 9, "ranger": 4, "wizard": 11, "oligarch": 2}
	screen.size = Vector2(320, 120)
	screen.show_stats(profile.to_dict())
	await await_idle_frame()

	# Nothing is dropped, and the biggest number of each section is at the top of it: an
	# alphabetical list of fourteen enemies buries the one the player keeps dying to.
	assert_int(screen.row_count()).is_equal(4 + 14 + 14 + 4)
	assert_array(StatsScreen.section_order(profile.deaths_by_enemy).slice(0, 2)).is_equal(
		["enemy_13", "enemy_12"]
	)
	assert_array(StatsScreen.section_order(profile.best_floor_per_class)).is_equal(
		["wizard", "fighter", "ranger", "oligarch"]
	)
	# The table is taller than the panel, which is what the ui_up/ui_down scrolling is for,
	# and it never scrolls past its own content.
	assert_int(screen.scroll_by(StatsScreen.SCROLL_STEP)).is_greater(0)
	assert_int(screen.scroll_by(-10_000)).is_equal(0)


## Ties are broken on the key, so the same profile always renders the same table.
func test_equal_counts_keep_a_stable_order() -> void:
	var section := {"zeta": 2, "alpha": 2, "mid": 5}
	assert_array(StatsScreen.section_order(section)).is_equal(["mid", "alpha", "zeta"])


## A dictionary that is not a saved profile is a summary somebody has already built: it is
## rendered as it came in, never rearranged.
func test_a_caller_built_summary_is_left_exactly_as_it_is() -> void:
	var fixture := UiFakes.profile_stats()
	assert_bool(StatsScreen.is_saved_profile(fixture)).is_false()
	assert_dict(StatsScreen.normalise(fixture)).is_equal(fixture)
	var screen := _screen()
	screen.show_stats(fixture)
	assert_int(screen.row_count()).is_equal(4 + 4 + 3)


func test_an_empty_dictionary_says_so() -> void:
	var screen := _screen()
	screen.show_stats({})
	assert_int(screen.row_count()).is_equal(0)
	assert_str(_table(screen)).is_equal(StatsScreen.NO_HISTORY)


## Every label the table draws, joined so a case can ask what is and is not on it.
static func _table(screen: StatsScreen) -> String:
	var parts := PackedStringArray()
	var list := screen.get_node("%List") as Control
	for node: Node in list.find_children("*", "Label", true, false):
		parts.append((node as Label).text)
	return "\n".join(parts)
