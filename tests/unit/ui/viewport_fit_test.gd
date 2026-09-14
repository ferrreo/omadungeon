## Nothing a screen draws may fall outside the 480x270 frame, in a dark theme or a light one.
##
## `TextFitTest` asks whether a Label fits the box it was given; this asks whether the box is
## on screen at all. The end-of-run panel passed the first question and failed the second: it
## was a fixed 344x256 whose content asked for 273 px with the gallery fixture and 441 px with
## every gear and ability slot filled, so it grew symmetrically out through the top and bottom
## of the viewport and took the VICTORY headline and the REUSE SEED / NEW RUN / TITLE row with
## it. A capture harness cannot see that - the PNG lands, exit 0, and the payoff screen of a
## winning run is sheared in half.
##
## Content inside a ScrollContainer is exempt, and only there: the container itself is checked,
## its children are the thing it exists to clip.
class_name ViewportFitTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
## The game's internal resolution; every screen is laid out against it (docs §1).
const NATIVE := Vector2(480, 270)
## One dark fixture and one light one. The overflow is driven by content width, not by the
## palette, but the light themes are where it was first seen and where it reads worst.
const THEMES: PackedStringArray = ["tokyo-night", "catppuccin-latte"]
## Half a pixel of slack, so a container that lands on a sub-pixel boundary is not a failure.
const EPSILON := 0.5

const SCREENS: Array[Dictionary] = [
	{"name": "title", "path": "res://src/ui/title.tscn"},
	{"name": "class_select", "path": "res://src/ui/class_select.tscn"},
	{"name": "settings", "path": "res://src/ui/settings_panel.tscn"},
	{"name": "stats", "path": "res://src/ui/stats_screen.tscn"},
	{"name": "credits", "path": "res://src/ui/credits.tscn"},
	{"name": "pause", "path": "res://src/ui/pause_menu.tscn"},
	{"name": "chest", "path": "res://src/ui/chest_ui.tscn"},
	{"name": "hud", "path": "res://src/ui/hud.tscn"},
	{"name": "run_death", "path": "res://src/ui/run_summary.tscn"},
	# An abandoned run carries the longest headline the screen ever draws ("RUN ABANDONED"),
	# which is the one string on it nobody chose the width of.
	{"name": "run_abandoned", "path": "res://src/ui/run_summary.tscn"},
	{"name": "run_summary", "path": "res://src/ui/run_summary.tscn"},
	{"name": "run_summary_full", "path": "res://src/ui/run_summary.tscn"},
]

var _theme_name: String = "Tokyo Night"
var _saved_motion: Variant = null


func before_test() -> void:
	# The panel scales itself in on a tween; a rect sampled mid-tween is neither the start nor
	# the end state. Reduce-motion makes the finished layout the only layout there is.
	_saved_motion = GameState.settings.get(Accessibility.SETTING_REDUCE_MOTION, false)
	GameState.settings[Accessibility.SETTING_REDUCE_MOTION] = true


func after_test() -> void:
	GameState.settings[Accessibility.SETTING_REDUCE_MOTION] = _saved_motion
	UiTheme.rebuild(Desktop.palette)


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


## `Desktop.palette` is pinned to the tokyo-night fixture for the whole unit run, so
## `UiFakes.summary_data()` names that theme whatever palette the screen is being drawn with.
## The theme name is half of why this screen overflowed - it is the widest value in the left
## table - so a light-theme case that still says "Tokyo Night" is not the light-theme case.
func _dress(theme: String) -> void:
	UiTheme.rebuild(_palette(theme))
	# The display name, out of the fixture's own `theme.name`, is what `Desktop` reads and what
	# the screen prints - not the directory slug. "Catppuccin Latte" and "catppuccin-latte" are
	# different widths and different wrap points, and only the first one is ever on screen.
	var file := FileAccess.open(
		"%s/%s/state/current/theme.name" % [FIXTURES, theme], FileAccess.READ
	)
	(
		assert_object(file)
		. override_failure_message("no theme.name in the %s fixture" % theme)
		. is_not_null()
	)
	_theme_name = file.get_as_text().strip_edges()


func _summary(victory: bool) -> Dictionary:
	var data := UiFakes.summary_data(victory)
	data["theme"] = _theme_name
	return data


## Builds one screen at the native resolution with generous fake content and settles it.
func _screen(spec: Dictionary) -> Control:
	var node: Node = auto_free((load(str(spec["path"])) as PackedScene).instantiate())
	var host := node as Control
	if node is CanvasLayer:
		add_child(node)
		host = node.get_node("%Root") as Control
	else:
		add_child(node)
	host.size = NATIVE
	match str(spec["name"]):
		"class_select":
			(node as ClassSelect).select(1)
		"stats":
			(node as StatsScreen).show_stats(UiFakes.profile_stats())
		"run_summary":
			(node as RunSummary).show_summary(_summary(true))
		"run_death":
			(node as RunSummary).show_summary(_summary(false))
		"run_abandoned":
			var walked := _summary(false)
			walked["abandoned"] = true
			(node as RunSummary).show_summary(walked)
		"run_summary_full":
			(node as RunSummary).show_summary(UiFakes.summary_data_full())
		"pause":
			var pause := node as PauseMenu
			var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
			add_child(player)
			pause.bind(player)
			pause.open()
		"hud":
			var hud := node as Hud
			var hud_player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
			add_child(hud_player)
			hud.bind(hud_player)
			hud.set_floor(3, "Sunken Library")
			hud.set_minimap(UiFakes.minimap_rooms(), UiFakes.minimap_edges())
			hud.show_prompt("Open the enormous chest", true)
		"chest":
			var chest := node as ChestUi
			var player2: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
			add_child(player2)
			chest.show_offers(
				ChestUi.Kind.ITEM,
				UiFakes.make_offers(ChestUi.Kind.ITEM),
				UiFakes.chest_context(player2)
			)
	for _i in 5:
		await get_tree().process_frame
	return host


## Visible Controls whose rect leaves `host`'s own rect. A ScrollContainer's children are
## skipped: clipping them is what the container is for.
static func outside(host: Control, node: Node = null) -> PackedStringArray:
	var out: PackedStringArray = []
	_walk(host.get_global_rect().grow(EPSILON), host if node == null else node, out)
	return out


static func _walk(frame: Rect2, node: Node, out: PackedStringArray) -> void:
	for child: Node in node.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		var rect := control.get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and not frame.encloses(rect):
			out.append("%s %s outside %s" % [control.name, rect, frame])
		if control is ScrollContainer:
			continue
		_walk(frame, child, out)


func _assert_fits(theme: String, spec: Dictionary) -> void:
	var host := await _screen(spec)
	var problems := outside(host)
	(
		assert_array(problems)
		. override_failure_message("%s, %s: %s" % [theme, spec["name"], problems])
		. is_empty()
	)


func test_no_screen_leaves_the_frame_in_a_dark_theme() -> void:
	_dress("tokyo-night")
	for spec: Dictionary in SCREENS:
		await _assert_fits("tokyo-night", spec)


func test_no_screen_leaves_the_frame_in_a_light_theme() -> void:
	_dress("catppuccin-latte")
	for spec: Dictionary in SCREENS:
		await _assert_fits("catppuccin-latte", spec)


## The two things a player must always be able to reach on the end-of-run screen, named
## individually so a failure says which one went off the edge rather than "some Control did".
func test_the_headline_and_the_buttons_stay_on_screen_for_every_theme() -> void:
	for theme: String in THEMES:
		_dress(theme)
		for data: Dictionary in [UiFakes.summary_data_full(), _summary(false)]:
			var host := await _screen({"name": "blank", "path": "res://src/ui/run_summary.tscn"})
			var summary := host as RunSummary
			summary.show_summary(data)
			for _i in 4:
				await get_tree().process_frame
			var frame := host.get_global_rect().grow(EPSILON)
			for path: String in ["%Headline", "%Retry", "%NewRun", "%ToTitle"]:
				var control := summary.get_node(path) as Control
				(
					assert_bool(frame.encloses(control.get_global_rect()))
					. override_failure_message(
						(
							"%s: %s is at %s, frame is %s"
							% [theme, path, control.get_global_rect(), frame]
						)
					)
					. is_true()
				)


## The panel adapts *down* as well as up: a run that recorded no build must not be padded out
## to the full-frame box the capped one uses, or the cap has just become a fixed height under
## another name.
func test_the_panel_shrinks_to_a_summary_with_no_build() -> void:
	_dress("tokyo-night")
	var bare := await _screen({"name": "blank", "path": "res://src/ui/run_summary.tscn"})
	(bare as RunSummary).show_summary({"victory": false, "floor": 2, "kills": 3})
	for _i in 4:
		await get_tree().process_frame
	var bare_height := (bare.get_node("%Panel") as Control).size.y
	var full := await _screen({"name": "run_summary_full", "path": "res://src/ui/run_summary.tscn"})
	var full_height := (full.get_node("%Panel") as Control).size.y
	(
		assert_float(bare_height)
		. override_failure_message(
			"an empty summary is %.0f px tall, a full one %.0f" % [bare_height, full_height]
		)
		. is_less(full_height)
	)
	assert_array(outside(bare)).is_empty()


## A win with every slot filled has to show the whole thing: the gear, the abilities, *and*
## the two lines the screen exists for - what the run unlocked and what the radio did. Those
## two used to share the scroll region with the build and a finished build pushed them below
## the fold, so the screen that is meant to reward the player buried the reward.
func test_a_full_build_shows_the_reward_lines_without_scrolling() -> void:
	for theme: String in ["tokyo-night", "catppuccin-latte"]:
		_dress(theme)
		var host := await _screen(
			{"name": "run_summary_full", "path": "res://src/ui/run_summary.tscn"}
		)
		var summary := host as RunSummary
		# The per-floor music lines are the one block allowed under the fold (docs 10.2);
		# `fold_slack` is the scroll limit less that block, and it is what must be 0.
		(
			assert_int(summary.fold_slack())
			. override_failure_message(
				(
					"%s: %d px of a full build is below the fold (scroll %d, floors %d)"
					% [
						theme,
						summary.fold_slack(),
						summary.scroll_limit(),
						int(summary.floors_height())
					]
				)
			)
			. is_equal(0)
		)
		assert_str(summary.overflow_notice()).is_empty()
		var names: PackedStringArray = []
		_collect_text(summary.get_node("%Build"), names)
		for expected: String in [
			"Gruvboxen Greatsword of the Bear",
			"Glimmering Signet of the Archivist",
			"Cracked Terminal Fragment",
			"Vampiric Resonance II",
			"Innate: Buyout Negotiator",
		]:
			(
				assert_array(names)
				. override_failure_message("%s: the panel dropped %s" % [theme, expected])
				. contains([expected])
			)
		# The reward lines are on screen, not merely in the tree.
		var frame := host.get_global_rect().grow(EPSILON)
		for path: String in ["%StatLine", "%Tracks"]:
			var control := summary.get_node(path) as Control
			(
				assert_bool(frame.encloses(control.get_global_rect()))
				. override_failure_message(
					"%s: %s is at %s, frame is %s" % [theme, path, control.get_global_rect(), frame]
				)
				. is_true()
			)


## And when a build really is bigger than the frame can hold, the page is turned deliberately:
## the marker says there is more, every name is still reachable, and the reward lines below the
## list never move. A scroll region a player is not told about is content silently cut off.
func test_a_build_too_big_for_the_frame_is_paginated_and_says_so() -> void:
	_dress("catppuccin-latte")
	var host := await _screen({"name": "blank", "path": "res://src/ui/run_summary.tscn"})
	var summary := host as RunSummary
	var data := UiFakes.summary_data_full()
	var gear: Array = (data["equipment"] as Array).duplicate()
	for i in 8:
		gear.append(
			{"slot": "Spare %d" % i, "name": "Overgrown Relic of the Archivist", "role": ""}
		)
	data["equipment"] = gear
	summary.show_summary(data)
	for _i in 6:
		await get_tree().process_frame
	assert_int(summary.scroll_limit()).is_greater(0)
	(
		assert_str(summary.overflow_notice())
		. override_failure_message("the list scrolls and nothing on screen says so")
		. is_equal(RunSummary.MORE_HINT)
	)
	var frame := host.get_global_rect().grow(EPSILON)
	var tracks := summary.get_node("%Tracks") as Control
	var before := tracks.get_global_rect()
	var limit := summary.scroll_limit()
	assert_int(summary.scroll_by(limit * 2)).is_equal(limit)
	await get_tree().process_frame
	# Scrolling the build must not drag the pinned footer with it.
	assert_vector(tracks.get_global_rect().position).is_equal(before.position)
	assert_bool(frame.encloses(tracks.get_global_rect())).is_true()
	var names: PackedStringArray = []
	_collect_text(summary.get_node("%Build"), names)
	assert_array(names).contains(["Innate: Buyout Negotiator"])
	assert_int(summary.scroll_by(-limit * 2)).is_equal(0)


## The ordinary end-of-run screen - the one the gallery captures and a player actually sees -
## must need no scrolling at all, in either theme. The cap is the backstop for a maximal build,
## not the normal state: a victory whose stat line and playlist sit below a fold has moved the
## complaint inside the panel rather than answered it.
func test_an_ordinary_victory_needs_no_scrolling_in_either_theme() -> void:
	for theme: String in THEMES:
		_dress(theme)
		for victory: bool in [true, false]:
			var host := await _screen({"name": "blank", "path": "res://src/ui/run_summary.tscn"})
			var summary := host as RunSummary
			summary.show_summary(_summary(victory))
			for _i in 4:
				await get_tree().process_frame
			(
				assert_int(summary.fold_slack())
				. override_failure_message(
					(
						"%s, victory=%s: %d px of the summary is below the fold"
						% [theme, victory, summary.fold_slack()]
					)
				)
				. is_equal(0)
			)
			assert_str(summary.overflow_notice()).is_empty()


## ... and the cap is vertical only: the longest class and theme names must not push the
## panel out through the sides instead. Same bug, other axis.
func test_the_longest_names_do_not_widen_the_panel_past_the_frame() -> void:
	for theme: String in THEMES:
		_dress(theme)
		var host := await _screen({"name": "blank", "path": "res://src/ui/run_summary.tscn"})
		var data := UiFakes.summary_data_full()
		data["class"] = "Oligarch"
		data["theme"] = "Catppuccin Latte Extended"
		(host as RunSummary).show_summary(data)
		for _i in 4:
			await get_tree().process_frame
		var panel := host.get_node("%Panel") as Control
		var frame := host.get_global_rect().grow(EPSILON)
		(
			assert_bool(frame.encloses(panel.get_global_rect()))
			. override_failure_message(
				"%s: panel %s, frame %s" % [theme, panel.get_global_rect(), frame]
			)
			. is_true()
		)


static func _collect_text(node: Node, out: PackedStringArray) -> void:
	for child: Node in node.get_children():
		var label := child as Label
		if label != null:
			out.append(label.text)
		_collect_text(child, out)
