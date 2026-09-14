## The death screen as a post-mortem: what killed you, how much it cost you, and what you
## built. The old screen listed six numbers and a playlist, and threw away the one
## death-relevant figure the run already tracked.
class_name RunReportTest
extends GdUnitTestSuite

const SUMMARY_SCENE := "res://src/ui/run_summary.tscn"


func _summary(data: Dictionary) -> RunSummary:
	var node: RunSummary = auto_free((load(SUMMARY_SCENE) as PackedScene).instantiate())
	add_child(node)
	node.show_summary(data)
	return node


## Every Label on the screen, so an assertion can ask "does the player see this string?"
## instead of trusting an internal structure.
func _texts(node: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for child: Node in node.get_children():
		var label := child as Label
		if label != null and label.visible:
			out.append(label.text)
		out.append_array(_texts(child))
	return out


func test_the_death_screen_names_the_killer_and_the_floor() -> void:
	var node := _summary(UiFakes.summary_data(false))
	assert_str(node.headline_text()).is_equal("YOU DIED")
	assert_str(node.subline_text_shown()).is_equal("Killed by Config Gremlin on floor 4")


func test_a_victory_keeps_the_class_and_theme_subline() -> void:
	var node := _summary(UiFakes.summary_data(true))
	assert_str(node.subline_text_shown()).contains("Fighter in the Dungeon of")


## `damage_taken` was tracked all run and rendered nowhere.
func test_damage_taken_is_on_the_summary() -> void:
	var node := _summary(UiFakes.summary_data(false))
	var texts := _texts(node)
	assert_array(texts).contains(["Damage taken"])
	assert_array(texts).contains(["418"])


## In a build rogue-like the death screen is where you look at what you made.
func test_the_summary_shows_the_build_it_ended_with() -> void:
	var node := _summary(UiFakes.summary_data(false))
	var texts := _texts(node)
	for expected: String in [
		"Weapon",
		"Sharp Rusty Sword",
		"Skill",
		"Lunge",
		"Active 1",
		"Fireball II",
		"Passive 2",
		"Vampiric II",
		"Innate: Second Wind",
	]:
		(
			assert_array(texts)
			. override_failure_message("summary does not show %s" % expected)
			. contains([expected])
		)
	assert_array(texts).contains(["VIT 9   MGT 11   PRE 3   ARC 1   SWI 5   FOR 4"])


## A run that recorded no build (an abandoned run, an old save) must still render.
func test_a_summary_without_a_build_still_renders() -> void:
	var node := _summary({"victory": false, "floor": 2, "kills": 3})
	assert_str(node.headline_text()).is_equal("YOU DIED")
	assert_array(_texts(node)).contains(["Damage taken"])


# --------------------- an abandoned run is not a death (owner report 11, round 4)


## Abandon Run and dying ended down the same path, so a player who walked away from a live run
## was shown a death screen - and blamed for it by name: the run tally keeps the last thing
## that hit the player whatever the run ended of, so "Killed by Config Gremlin on floor 4" was
## printed over a run nothing had killed.
func test_an_abandoned_run_is_not_reported_as_a_death() -> void:
	var data := UiFakes.summary_data(false)
	data["abandoned"] = true
	var node := _summary(data)
	assert_str(node.headline_text()).is_equal("RUN ABANDONED")
	assert_str(node.subline_text_shown()).not_contains("Killed by")
	assert_str(node.subline_text_shown()).contains("Fighter in the Dungeon of")
	# Everything the run did still counts: it is the same post-mortem, minus the death.
	var texts := _texts(node)
	assert_array(texts).contains(["Damage taken"])
	assert_array(texts).contains(["418"])
	assert_array(texts).contains(["Kills"])
	# "RUN ABANDONED" is the longest headline this screen can carry, and it is drawn in the
	# title font at the top of a panel the 480x270 frame has to hold whole.
	var headline := node.get_node("%Headline") as Label
	assert_float(headline.get_combined_minimum_size().x).is_less_equal(
		(node.get_node("%Panel") as Control).size.x
	)


## ... and the same data without the flag is still a death, so the flag is what decides it.
func test_the_same_run_without_the_flag_is_still_a_death() -> void:
	var node := _summary(UiFakes.summary_data(false))
	assert_str(node.headline_text()).is_equal("YOU DIED")
	assert_str(node.subline_text_shown()).contains("Killed by Config Gremlin")


## A win is a win however the dictionary is marked: `abandoned` only ever qualifies a loss.
func test_a_victory_is_never_reported_as_abandoned() -> void:
	var data := UiFakes.summary_data(true)
	data["abandoned"] = true
	assert_bool(RunSummary.is_abandoned(data)).is_false()
	assert_str(_summary(data).headline_text()).is_equal("VICTORY")


## `RunBuild` is what turns the live player into those rows; a dead run has none to read.
func test_run_build_snapshot_is_empty_without_a_player() -> void:
	assert_bool(RunBuild.snapshot(null).is_empty()).is_true()


func test_run_build_labels_an_ability_with_its_tier() -> void:
	var ability := UiFakes.make_active("fireball", "Fireball", 6.0)
	ability.tier = 2
	assert_str(RunBuild.label(ability)).is_equal("Fireball II")
	assert_str(RunBuild.label(null)).is_empty()


## `EventBus.player_died` carries no source, so the killer is the last thing that hit.
func test_the_tally_remembers_what_hit_last() -> void:
	var tally := RunTally.new()
	tally.begin()
	var gremlin: Node2D = auto_free(Node2D.new())
	gremlin.name = "config_gremlin"
	add_child(gremlin)
	tally.record_damage(5, null)
	tally.record_damage(11, gremlin)
	assert_int(tally.damage_taken).is_equal(16)
	assert_str(tally.last_hit_name).is_equal("Config Gremlin")
	var summary := tally.to_summary(false)
	assert_str(str(summary["killer"])).is_equal("Config Gremlin")
	assert_int(int(summary["damage_taken"])).is_equal(16)
	assert_str(str(tally.to_summary(true)["killer"])).is_empty()


## An anonymous killing blow (the scenario driver's synthetic hit) leaves the last hit alone
## rather than overwriting it with a node name nobody would recognise.
func test_an_anonymous_hit_does_not_replace_the_killer() -> void:
	var tally := RunTally.new()
	tally.begin()
	var gremlin: Node2D = auto_free(Node2D.new())
	gremlin.name = "honker"
	add_child(gremlin)
	tally.record_damage(4, gremlin)
	tally.record_damage(999, null)
	assert_str(tally.last_hit_name).is_equal("Honker")


## The build column runs at separation 0 so a heading sits tight against the grid it labels.
## That also jammed "Abilities" straight onto the "Skill  Lunge" row above it, with the same
## leading as two rows of the same table: three testers read it as a collision. Measured on
## the laid-out rects, because the bug is geometry - the strings were always right.
func test_the_abilities_heading_starts_a_new_section() -> void:
	var node := _summary(UiFakes.summary_data(false))
	await get_tree().process_frame
	await get_tree().process_frame
	var column := node.get_node("%Build") as Control
	var labels := _build_labels(node)
	var row_gap := INF
	var section_gap := INF
	for i in range(1, labels.size()):
		var gap := _gap_between(column, labels[i - 1], labels[i])
		if labels[i].text == "Abilities":
			section_gap = gap
		elif labels[i].text == "Armor":
			row_gap = gap
	(
		assert_bool(is_finite(row_gap) and is_finite(section_gap))
		. override_failure_message("the build panel did not render both sections")
		. is_true()
	)
	assert_float(row_gap).override_failure_message("gear rows overlap").is_greater_equal(0.0)
	(
		assert_float(section_gap)
		. override_failure_message(
			(
				'"Abilities" is %.1f px below the row above it; a gear row is %.1f px'
				% [section_gap, row_gap]
			)
		)
		. is_greater(row_gap)
	)


## ... and the headings still own the grids under them: a heading that drifted away from its
## own rows would pass the test above and label nothing.
func test_each_build_heading_stays_attached_to_its_own_rows() -> void:
	var node := _summary(UiFakes.summary_data(false))
	await get_tree().process_frame
	await get_tree().process_frame
	var column := node.get_node("%Build") as Control
	var labels := _build_labels(node)
	for i in range(1, labels.size()):
		if labels[i - 1].text != "Gear" and labels[i - 1].text != "Abilities":
			continue
		(
			assert_float(_gap_between(column, labels[i - 1], labels[i]))
			. override_failure_message(
				'"%s" floats away from "%s"' % [labels[i - 1].text, labels[i].text]
			)
			. is_less_equal(1.0)
		)


## Vertical space between the bottom of `above` and the top of `below`, in `column`'s own
## coordinates. Not `get_global_rect()`: the panel tweens its *scale* on the way in, and a
## global rect pairs a scaled position with an unscaled size, so the arithmetic goes silently
## negative for however many frames the animation is still running.
static func _gap_between(column: Control, above: Label, below: Label) -> float:
	return _offset_in(column, below) - (_offset_in(column, above) + above.size.y)


## `control`'s y position measured from `column`, summing the local offsets in between.
static func _offset_in(column: Control, control: Control) -> float:
	var y := 0.0
	var node: Node = control
	while node != null and node != column:
		var as_control := node as Control
		if as_control != null:
			y += as_control.position.y
		node = node.get_parent()
	return y


## Every Label under the build panel, in draw order.
func _build_labels(node: RunSummary) -> Array[Label]:
	var out: Array[Label] = []
	_collect_labels(node.get_node("%Build"), out)
	return out


static func _collect_labels(node: Node, out: Array[Label]) -> void:
	for child: Node in node.get_children():
		var label := child as Label
		if label != null:
			out.append(label)
		_collect_labels(child, out)


## The panel whose whole job is to show the build the run spent 25 minutes assembling was
## eliding it: the ARMOR row read "VITAL LEATHER JERK...". `label.text` still held the full
## name, which is why a green suite never saw it - so this asserts what is *rendered*.
func test_no_part_of_the_build_is_trimmed_away_on_the_death_screen() -> void:
	var node := _summary(UiFakes.summary_data(false))
	await get_tree().process_frame
	await get_tree().process_frame
	var checked := 0
	for label: Label in _build_labels(node):
		if label.text.is_empty() or label.text == "-":
			continue
		checked += 1
		(
			assert_int(label.text_overrun_behavior)
			. override_failure_message('the summary elides "%s"' % label.text)
			. is_not_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
		)
		(
			assert_int(label.get_visible_line_count())
			. override_failure_message(
				(
					'"%s" shows %d of its %d lines'
					% [label.text, label.get_visible_line_count(), label.get_line_count()]
				)
			)
			. is_greater_equal(label.get_line_count())
		)
	# The fake build has five named gear rows, four abilities, two headings and the innate.
	assert_int(checked).is_greater_equal(10)


## The longest gear name in the fixture does not fit the column on one line, so "not elided"
## has to mean "wrapped onto a second line", not "the column silently got wider".
func test_a_long_gear_name_wraps_instead_of_being_cut() -> void:
	var node := _summary(UiFakes.summary_data(false))
	await get_tree().process_frame
	await get_tree().process_frame
	var found: Label = null
	for label: Label in _build_labels(node):
		if label.text == "Vital Leather Jerkin":
			found = label
	assert_object(found).is_not_null()
	assert_int(found.autowrap_mode).is_not_equal(TextServer.AUTOWRAP_OFF)
	assert_int(found.get_visible_line_count()).is_greater_equal(found.get_line_count())
	# Every character of the name is on screen somewhere.
	assert_int(found.get_total_character_count()).is_equal("Vital Leather Jerkin".length())


# ------------------------------------------------------------- the music line (owner report 7)


## The results screen carried a debug readout: "F2 frantic +12% foes". It is the only screen
## the player is guaranteed to read to the end, and it was talking to the person who wrote the
## generator. What it says now has to be a sentence, and it still has to carry the real number.
func test_the_music_line_is_a_sentence_and_not_a_debug_readout() -> void:
	var node := _summary(UiFakes.summary_data(true))
	await get_tree().process_frame
	var text := "\n".join(_texts(node.get_node("%Tracks")))
	assert_str(text).contains("Calm on floor 1")
	assert_str(text).contains("frantic on floor 3")
	assert_str(text).contains("fewer enemies")
	assert_str(text).contains("26% more.")
	for shorthand: String in ["foes", "F1 ", "F2 ", "F3 ", "+0%"]:
		(
			assert_str(text)
			. override_failure_message('the results screen still says "%s": %s' % [shorthand, text])
			. not_contains(shorthand)
		)


## The number in that sentence is the generator's own enemy-count scale (`MusicLevers`), not a
## flavour figure, so a silent floor changed nothing and a loud one really did add foes.
func test_the_music_sentence_quotes_the_generator_s_own_number() -> void:
	var levers := MusicLevers.shared()
	var loud := int(round((levers.foes_loud - 1.0) * 100.0))
	var calm := int(round((levers.foes_calm - 1.0) * 100.0))
	assert_int(loud).is_greater(0)
	assert_int(calm).is_less(0)
	assert_int(RunSummary.foes_percent({"floor": 1, "energy": 1.0, "playing": true})).is_equal(loud)
	assert_int(RunSummary.foes_percent({"floor": 1, "energy": 0.0, "playing": true})).is_equal(calm)
	assert_int(RunSummary.foes_percent({"floor": 1, "energy": 0.9, "playing": false})).is_equal(0)
	assert_str(RunSummary.mood_word({"energy": 0.1, "playing": true})).is_equal("calm")
	assert_str(RunSummary.mood_word({"energy": 0.95, "playing": true})).is_equal("frantic")
	assert_str(RunSummary.mood_word({"energy": 0.95, "playing": false})).is_equal("silent")


## A run whose radio never changed mood says so in one clause rather than naming the same
## floor twice, and a run with no floor log at all says nothing instead of an empty sentence.
## One line per floor, in floor order, naming the track and what it did (owner: "make the
## music matter"). A floor built in silence says so; nothing is shorthand.
func test_the_summary_carries_a_line_per_floor_naming_the_track_and_its_effect() -> void:
	var node := _summary(UiFakes.summary_data(true))
	await get_tree().process_frame
	var floors := node.find_child("Floors", true, false)
	assert_object(floors).is_not_null()
	var text := "\n".join(_texts(floors))
	assert_str(text).contains("Floors")
	assert_str(text).contains("Floor 1 - Neon Corridors: sparse")
	assert_str(text).contains("fewer enemies, more traps")
	assert_str(text).contains(
		"Floor 3 - Rm -rf: dense, fast and bright, 26% more enemies, fewer traps"
	)
	for shorthand: String in ["foes", "F1 ", "F2 ", "F3 ", "+0%"]:
		assert_str(text).not_contains(shorthand)
	var lines := (
		RunSummary
		. floor_lines(
			[
				{"floor": 2, "title": "B", "energy": 0.5, "tempo": 0.0, "playing": true},
				{"floor": 1, "playing": false},
			]
		)
	)
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[0]).is_equal("Floor 1 - silence: the usual floor")
	assert_str(lines[1]).starts_with("Floor 2 - B: steady and lit, ")
	assert_bool(RunSummary.floor_lines([]).is_empty()).is_true()


func test_one_mood_all_run_reads_as_one_clause_and_no_log_says_nothing() -> void:
	var one: Array = [{"floor": 1, "energy": 0.5, "playing": true}]
	var text := RunSummary.music_summary(one)
	assert_str(text).starts_with("Driving all run")
	assert_str(text).ends_with(".")
	assert_str(RunSummary.music_summary([])).is_empty()
	assert_str(RunSummary.music_summary([{"floor": 1, "playing": false}])).is_empty()
