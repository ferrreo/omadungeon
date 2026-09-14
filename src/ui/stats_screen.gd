## Profile statistics table. `show_stats(profile)` renders scalar entries as rows and nested
## dictionaries (best floor per class, wins per theme) as titled sections.
##
## What it is handed is `Profile.to_dict()`, which is a *save file*, not a report: it carries a
## schema `version`, the full unlock id list and its statistics nested one level down under
## `stats`. Rendered as-is that came out, on a brand new profile, as "Version 2", the fourteen
## default unlock ids printed as one run-on array, an empty "Counters" heading and three rows
## reading "{ }". `normalise()` is the step that was missing: it turns a saved profile into the
## table a player reads, and leaves any other dictionary (the gallery fixture, a caller with its
## own summary) exactly as it is.
##
## The table is plain Labels, so nothing in it can take focus: without ui_up/ui_down driving
## the ScrollContainer directly, a profile taller than the panel would be unreachable on a
## controller. That is what `_unhandled_input` below is for.
class_name StatsScreen
extends Control

signal back_pressed

## Pixels one ui_up/ui_down step scrolls the table.
const SCROLL_STEP := 24
## Shown under the summary while nothing has been recorded yet.
const NO_HISTORY := "No runs yet. Go get lost."
## Printed for a number that does not exist yet (a win rate with no runs behind it).
const NO_VALUE := "-"
## Saved-profile keys that are bookkeeping rather than statistics.
const HIDDEN_KEYS: PackedStringArray = ["version"]
## Section and row captions that `_pretty()` cannot arrive at on its own.
const TITLES := {
	"best_floor_per_class": "Best Floor by Class",
	"per_theme_wins": "Wins by Theme",
	"deaths_by_enemy": "Deaths by Enemy",
	"counters": "Milestones",
	"win_rate": "Win Rate",
	"unlocks": "Unlocks",
}

@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List
@onready var _back: Button = %Back


func _ready() -> void:
	UiTheme.apply(self)
	# Left stick -> ui_up/ui_down for the table (see UiStickNav).
	UiStickNav.serve(self)
	_back.pressed.connect(func() -> void: back_pressed.emit())
	_back.grab_focus()


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		back_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down"):
		scroll_by(SCROLL_STEP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		scroll_by(-SCROLL_STEP)
		get_viewport().set_input_as_handled()


## Scrolls the table by `delta` pixels, clamped to its content. Returns the new offset.
func scroll_by(delta: int) -> int:
	var limit := maxi(0, int(_list.size.y - _scroll.size.y))
	_scroll.scroll_vertical = clampi(_scroll.scroll_vertical + delta, 0, limit)
	return _scroll.scroll_vertical


## Current vertical scroll offset of the table, in pixels.
func scroll_offset() -> int:
	return _scroll.scroll_vertical


## Renders a profile. Scalars become rows in the top grid, nested dictionaries become titled
## sections under it, and an empty section is left out entirely rather than drawn as a heading
## with nothing beneath it.
func show_stats(profile: Dictionary) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var data := normalise(profile)
	if data.is_empty():
		_list.add_child(_note(NO_HISTORY))
		return
	var grid := _grid()
	_list.add_child(grid)
	var sections: Array[String] = []
	for key: Variant in data.keys():
		var value: Variant = data[key]
		if value is Dictionary:
			sections.append(str(key))
		else:
			_add_row(grid, caption(str(key)), _format(value))
	if not has_history(data):
		_list.add_child(_note(NO_HISTORY))
	for key: String in sections:
		var sub: Dictionary = data[key]
		if sub.is_empty():
			continue
		var heading := Label.new()
		heading.theme_type_variation = &"Heading"
		heading.text = caption(key)
		_list.add_child(heading)
		var section_grid := _grid()
		_list.add_child(section_grid)
		for sub_key: Variant in section_order(sub):
			_add_row(section_grid, caption(str(sub_key)), _format(sub[sub_key]))


## Turns a saved profile (`Profile.to_dict()`) into the table a player reads: the schema
## version and the raw unlock id list go, `stats` is lifted to the top level so its numbers are
## rows rather than a nested section, the unlock list becomes "earned of gated", and the win
## rate is derived because the two numbers it is made of are already on screen.
##
## Any dictionary that is not a saved profile - the gallery fixture, a caller that has already
## built its own summary - is returned as it came in. This is the only thing that knows the
## save shape; the renderer above stays a renderer.
static func normalise(profile: Dictionary) -> Dictionary:
	if not is_saved_profile(profile):
		return profile
	var stats := profile["stats"] as Dictionary
	var runs := int(stats.get("runs", 0))
	var wins := int(stats.get("wins", 0))
	var out: Dictionary = {
		"runs": runs,
		"wins": wins,
		"win_rate": NO_VALUE if runs <= 0 else "%d%%" % int(round(100.0 * float(wins) / runs)),
		"unlocks": "%d / %d" % [earned_unlocks(profile), Profile.GATED_UNLOCKS.size()],
	}
	for key: Variant in stats.keys():
		if str(key) in ["runs", "wins"] or str(key) in HIDDEN_KEYS:
			continue
		out[str(key)] = stats[key]
	var counters: Variant = profile.get("counters")
	if counters is Dictionary:
		out["counters"] = counters
	return out


## True for the dictionary `Profile.to_dict()` writes: a `stats` sub-dictionary and the schema
## version beside it. Nothing else is unwrapped, so a caller's own summary is never rearranged.
static func is_saved_profile(profile: Dictionary) -> bool:
	return profile.get("stats") is Dictionary and profile.has("version")


## How many of the gated unlocks (`Profile.GATED_UNLOCKS`) a saved profile has earned. The
## ungated ids are in the list too and every profile has all of them, so counting the whole
## array would print the same number on every save file ever written.
static func earned_unlocks(profile: Dictionary) -> int:
	var raw: Variant = profile.get("unlocks")
	if not (raw is Array):
		return 0
	var count := 0
	for id: StringName in Profile.GATED_UNLOCKS:
		if (raw as Array).has(String(id)):
			count += 1
	return count


## False when the table holds nothing but zeroes and empty sections - a fresh profile, which
## gets the "no runs yet" line under its summary instead of a page of nought.
static func has_history(data: Dictionary) -> bool:
	for key: Variant in data.keys():
		var value: Variant = data[key]
		if value is Dictionary:
			if not (value as Dictionary).is_empty():
				return true
		elif value is int or value is float:
			if absf(float(value)) > 0.0:
				return true
	return false


## The order a section's rows are read in: biggest first for the numeric ones (a long history
## is a ranking, and alphabetical order buries the answer), alphabetical for everything else.
## Ties fall back to the key, so the same profile always renders the same table.
static func section_order(section: Dictionary) -> Array:
	var keys: Array = section.keys()
	keys.sort()
	if not _all_numeric(section):
		return keys
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			var left := float(section[a])
			var right := float(section[b])
			if left == right:
				return str(a) < str(b)
			return left > right
	)
	return keys


## Row/section caption for a key: the override in `TITLES`, else the key with its underscores
## opened out ("deaths_by_enemy" -> "Deaths by Enemy", "bit_rot" -> "Bit Rot").
static func caption(key: String) -> String:
	return str(TITLES.get(key, _pretty(key)))


func row_count() -> int:
	var count := 0
	for child in _list.get_children():
		if child is GridContainer:
			count += (child as GridContainer).get_child_count() / 2
	return count


static func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func _all_numeric(section: Dictionary) -> bool:
	for key: Variant in section.keys():
		var value: Variant = section[key]
		if not (value is int or value is float):
			return false
	return not section.is_empty()


static func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiTheme.GAP_SECTION)
	grid.add_theme_constant_override("v_separation", UiTheme.GAP_TIGHT)
	return grid


static func _pretty(key: String) -> String:
	return key.replace("_", " ").capitalize()


## One cell of the value column. Nothing here may fall through to `str()` on a container: that
## is what printed a fourteen-entry unlock array across the table and "{ }" under three
## headings on a profile that had simply never been played.
static func _format(value: Variant) -> String:
	if value is float:
		return "%.1f" % float(value)
	if value is bool:
		return "Yes" if bool(value) else "No"
	if value is Dictionary:
		var sub := value as Dictionary
		return NO_VALUE if sub.is_empty() else str(sub.size())
	if value is Array:
		var list := value as Array
		return NO_VALUE if list.is_empty() else str(list.size())
	return str(value)


static func _add_row(grid: GridContainer, label_text: String, value_text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	grid.add_child(label)
	var value := Label.new()
	value.theme_type_variation = &"Bright"
	value.text = value_text
	grid.add_child(value)
