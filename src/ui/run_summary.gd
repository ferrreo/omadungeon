## End-of-run summary (victory, death, or a run the player walked away from): what happened,
## what killed you, and what you built.
##
## `show_summary(data)` keys: victory, abandoned, floor, kills, gold, damage_taken, time (seconds), seed,
## theme, class, tracks (Array of "Title - Artist"), killer (String), equipment
## (Array of {slot, name, role}), abilities (Array of {slot, name}), innate (String),
## stats (Dictionary primary -> int). Every build key is optional; a run that recorded none
## of them renders exactly the rows it has.
##
## Two more things it now reports, because a run that shows neither is a run with no reason to
## start another one:
##
## * **Progress** - what this run earned towards the next unlock, and anything it unlocked.
##   Read from the `SaveManager` autoload (`unlocks_this_run`, `counter_gains_this_run`,
##   `progress_rows`), or from `data` keys of the same names when a caller supplies them.
## * **Music** - what the radio was doing on each floor as it was generated, and what that did
##   to the floor. The playlist used to be a flat list of song titles with no connection to
##   anything the player saw, which is most of why the music levers read as doing nothing.
##   One sentence of it (the calmest and loudest floor) is chrome; the line per floor
##   ("Floor 3 - Rm -rf: dense and bright, 26% more enemies") is a "Floors" section of the
##   scrolled body, full width under the two columns, and it is the one thing on this screen
##   that is allowed to sit below the fold. Full width because a floor's line only fits on
##   one row there (under the stat table it wrapped to three per floor); below the fold
##   because nine rows of it cannot share a 270 px screen with the build. `_fit_to_frame`
##   therefore sizes the body for everything *but* the floors, so the build and the reward
##   lines still show whole without scrolling (`fold_slack()` is what the fit tests assert on
##   now, not `scroll_limit()`), and the chrome's music sentence says the floors are below.
##
## Both of those live **below** the scroll region, not in it. The gear and ability list is the
## one block that grows without bound, and while it shared a ScrollContainer with them a
## finished build pushed the unlock progress and the music line off the bottom of the panel:
## the screen that exists to reward the player was burying the reward. Only the build scrolls
## now, and it says so when it does (`%MoreHint`).
class_name RunSummary
extends Control

signal retry_seed_pressed
signal new_run_pressed
signal title_pressed

## Tracks named on the one playlist line before it becomes "+N more". The build panels want
## the height far more than the playlist does - a death screen that had room for four songs
## and none for the gear was the complaint, not the other way round.
const MAX_TRACKS := 2
## The seed button. It starts a *new run* with this run's seed and class; it does not replay
## the run. It is also the only place this screen mentions the seed at all - the table used to
## carry a "Seed 20240911" row, which is a number a player can neither act on nor remember,
## printed between "Time" and "Theme" as though it were a score.
##
## Generation also folds in the desktop theme, the wallpaper and the track playing
## when each floor is built, and the music levers are sampled live (GAME_DESIGN §5.1), so a
## button labelled "Retry seed" promised a replay the generator cannot deliver.
const RETRY_LABEL := "Reuse seed"
const RETRY_TOOLTIP := (
	"Starts a new run with this seed and class.\n"
	+ "The dungeon itself will differ: the theme, the wallpaper and the music playing\n"
	+ "shape every floor as it is built."
)
## Blank leading above a build-panel heading that is not the first one. The Build column runs
## at separation 0 so a heading sits tight against the grid it labels; without this the
## "Abilities" heading landed on the last gear row and read as a collision rather than a new
## section. Kept small on purpose: the body it lives in is capped at the frame height, so any
## leading it takes is leading the gear rows have to scroll for.
const SECTION_GAP_PX := 4
## Breathing room kept between the panel and the top and bottom of the frame. Four pixels, not
## eight: at 270 px tall, sixteen pixels of dead frame while the panel below it scrolls is the
## screen spending its height on nothing. Four still reads as a margin - it is wider than the
## HUD plates' own inset - and is what an ordinary end-of-run screen needs to fit whole. The panel used
## to be a fixed 344x256 in a 480x270 viewport, which is 7 px of slack the content was free to
## spend: a finished build asks for 273 px with the fixture data and 441 px with every slot
## filled, so the panel grew out through both edges and took the headline and the button row
## with it. Nothing above this line may depend on the content fitting.
const SAFE_MARGIN_PX := 4.0
## The stat/build body never collapses below this, however little room the frame leaves.
const MIN_BODY_PX := 48.0
## Layout passes the fit is re-run over after the content changes. A Label does not announce
## that autowrapping it at its new width changed how tall it is - it simply answers differently
## the next time it is asked - so the only way to see the settled height is to ask again on a
## later frame. Three passes is measure, correct, confirm; `_fit_to_frame` is idempotent, so a
## pass that has nothing to do costs a comparison.
const FIT_PASSES := 3
## Pixels one ui_up/ui_down step scrolls the body, matching `StatsScreen.SCROLL_STEP`.
## Nothing inside the body can take focus, so without this a build taller than the panel
## would be unreachable on a controller.
const SCROLL_STEP := 16
## Widest the panel may grow, and the gutter it keeps at either side of the frame. The panel
## used to be a fixed 344 px in a 480 px frame: 68 px of empty gutter on each side while the
## Gear column beside the table was narrow enough to wrap every single item name onto three
## lines. The table has vertical slack and the build column has none, so the width goes to the
## build column and a finished run's gear reads on one line each.
const PANEL_MAX_WIDTH := 440.0
const PANEL_SIDE_MARGIN := 16.0
## Narrowest the panel may be squeezed to on a frame smaller than the design resolution.
const PANEL_MIN_WIDTH := 280.0
## What the screen says when the build is taller than the room left for it. A scroll region a
## player cannot see the edge of is a page with content silently cut off it; this is the line
## that turns that into a page they know to turn.
const MORE_HINT := "More below - {ui_down} to scroll"
## Widest a wrapping table value may ask for before it folds onto a second line instead. Wide
## enough for the longest theme name a stock Omarchy ships; a longer one still wraps rather
## than pushing the build column back into three-line item names.
const WRAP_VALUE_MAX := 104.0
## How the energy that shaped a floor is described, low to high.
const ENERGY_WORDS: Array[String] = ["calm", "steady", "driving", "frantic"]
## Counters worth naming in the one-line "this run earned" summary, and what to call them.
const GAIN_LABELS: Dictionary = {
	"kills": "kills",
	"gold_earned": "gold",
	"best_floor": "best floor",
	"flawless_floors": "flawless floors",
	"clowns_killed": "clowns",
	"greybeards_killed": "greybeards",
	"tinkerers_killed": "tinkerers",
}
## Short names for the one-line final stat spread.
const STAT_SHORT: Dictionary = {
	&"vitality": "VIT",
	&"might": "MGT",
	&"precision": "PRE",
	&"arcana": "ARC",
	&"swiftness": "SWI",
	&"fortune": "FOR",
}

var data: Dictionary = {}

var _fit_passes: int = 0

@onready var _panel: PanelContainer = %Panel
@onready var _headline: Label = %Headline
@onready var _subline: Label = %Subline
@onready var _grid: GridContainer = %Grid
@onready var _body: ScrollContainer = %Body
@onready var _body_wrap: Control = %BodyWrap
@onready var _content: VBoxContainer = %Content
@onready var _build: VBoxContainer = %Build
@onready var _stat_line: Label = %StatLine
@onready var _tracks: VBoxContainer = %Tracks
## The per-floor music lines, built in code below `%Columns` inside the scrolled body.
@onready var _floors: VBoxContainer = _make_floors()
@onready var _more_hint: UiPrompt = %MoreHint
@onready var _more_plate: PanelContainer = %MorePlate

@onready var _retry: Button = %Retry
@onready var _new_run: Button = %NewRun
@onready var _title: Button = %ToTitle


func _ready() -> void:
	UiTheme.apply(self)
	# Left stick -> menu navigation (see UiStickNav).
	UiStickNav.serve(self)
	_retry.text = RETRY_LABEL
	_retry.tooltip_text = RETRY_TOOLTIP
	_retry.pressed.connect(func() -> void: retry_seed_pressed.emit())
	_new_run.pressed.connect(func() -> void: new_run_pressed.emit())
	_title.pressed.connect(func() -> void: title_pressed.emit())
	resized.connect(_queue_fit)
	# An autowrapped gear name only knows how tall it is once it has been given its width, so
	# the first measurement is an over-estimate and the body opens at its cap. Re-fitting as
	# the content settles walks that back; `_fit_to_frame` is idempotent, which is what stops
	# the fit and the resize it causes from chasing each other frame after frame.
	_content.resized.connect(_queue_fit)
	_content.minimum_size_changed.connect(_queue_fit)
	if data.is_empty():
		show_summary({"victory": false})


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)


func _unhandled_input(event: InputEvent) -> void:
	# Only while the body actually overflows: with content that fits, up/down must keep doing
	# whatever focus navigation does with them.
	if scroll_limit() <= 0:
		return
	if event.is_action_pressed(&"ui_down"):
		scroll_by(SCROLL_STEP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		scroll_by(-SCROLL_STEP)
		get_viewport().set_input_as_handled()


## How far the stat/build body can still be scrolled, in pixels; 0 when it all fits.
func scroll_limit() -> int:
	if _body == null or _content == null:
		return 0
	return maxi(0, int(ceilf(_content.size.y - _body.size.y)))


## How much of the body other than the floors section is below the fold, in pixels: 0 when
## the build and the stat table show whole. The floors are allowed under the fold; nothing
## else is, and this is the number that says so.
func fold_slack() -> int:
	return maxi(0, scroll_limit() - int(ceilf(floors_height())))


## Height the floors section asks for, plus the row gap it costs, or 0 while it is hidden.
func floors_height() -> float:
	if _floors == null or not _floors.visible:
		return 0.0
	return _floors.get_combined_minimum_size().y + float(_content.get_theme_constant("separation"))


## Scrolls the body by `delta` pixels, clamped to its content. Returns the new offset.
func scroll_by(delta: int) -> int:
	_body.scroll_vertical = clampi(_body.scroll_vertical + delta, 0, scroll_limit())
	return _body.scroll_vertical


## Current vertical scroll offset of the body, in pixels.
func scroll_offset() -> int:
	return 0 if _body == null else _body.scroll_vertical


## The marker shown over the build list when part of it is below the fold, or "" when the
## whole screen fits. Tests read this rather than the node path: "did the player get told"
## is the behaviour, and a scroll region nobody is told about is the bug.
func overflow_notice() -> String:
	if _more_plate == null or not _more_plate.visible:
		return ""
	return _more_hint.text


func _queue_fit() -> void:
	_fit_passes = FIT_PASSES
	set_process(true)


func _process(_delta: float) -> void:
	_fit_to_frame()
	_fit_passes -= 1
	if _fit_passes <= 0:
		set_process(false)


## Sizes the body so the whole panel fits the frame with `SAFE_MARGIN_PX` to spare, top and
## bottom. The panel is centred and takes its height from its own minimum size, so capping
## the one part that grows without bound - the scrolled body - is what caps the panel. Below
## the cap the panel still shrinks to its content; above it, the body scrolls.
func _fit_to_frame() -> void:
	if _body_wrap == null or _content == null or size.y <= 0.0:
		return
	_fit_width()
	# The panel's minimum is the sum of its rows', so taking the scrolled block's own minimum
	# back out leaves the chrome: the headline, the subline, the stat and music lines and the
	# button row, none of which may ever be the thing that overflows. `BodyWrap` is a plain
	# Control, which does not propagate its children's minimum size, so the height this
	# function last gave it *is* its minimum and the subtraction is exact.
	var chrome := _panel.get_combined_minimum_size().y - _body_wrap.custom_minimum_size.y
	# The "more below" marker is chrome only while it is showing, and whether it shows is
	# decided *here*. Measuring the chrome with it in would make its own height the reason the
	# body overflows - a marker that, once shown, could never go away again.
	var marker := _marker_height()
	if _more_plate != null and _more_plate.visible:
		chrome -= marker
	# The floors section is not part of what has to fit: it is the one block that may sit
	# below the fold, so the body is sized for the columns alone and the floors scroll in.
	var wanted := _content.get_combined_minimum_size().y - floors_height()
	var free_room := maxf(size.y - SAFE_MARGIN_PX * 2.0 - chrome, MIN_BODY_PX)
	var overflowing := wanted > free_room
	var room := maxf(free_room - (marker if overflowing else 0.0), MIN_BODY_PX)
	var target := ceilf(minf(wanted, room))
	if not is_equal_approx(target, _body_wrap.custom_minimum_size.y):
		_body_wrap.custom_minimum_size.y = target
	_refresh_more_hint(overflowing)


## Height the marker asks for, showing or not.
func _marker_height() -> float:
	if _more_plate == null:
		return 0.0
	return _more_plate.get_combined_minimum_size().y


## Widens the panel to the frame it is drawn in, less a gutter. The build column is the one
## block on this screen that has too little room, and it is the last child of the row, so every
## pixel the panel gains is a pixel of item name that does not have to wrap.
func _fit_width() -> void:
	if _panel == null or size.x <= 0.0:
		return
	var width := clampf(size.x - PANEL_SIDE_MARGIN * 2.0, PANEL_MIN_WIDTH, PANEL_MAX_WIDTH)
	var half := floorf(width * 0.5)
	if is_equal_approx(half, _panel.offset_right):
		return
	_panel.offset_left = -half
	_panel.offset_right = half


## Says so when the build is taller than the room left for it, so a page that has been turned
## under is a page the player knows about. `overflowing` is `_fit_to_frame`'s decision, not a
## reading of the scroll: the marker's own height is part of what the fit is deciding.
func _refresh_more_hint(overflowing: bool) -> void:
	if _more_hint == null:
		return
	_more_hint.text = MORE_HINT
	# The marker sits in the gutter under the list, not over it. It used to float on the
	# bottom-right corner of the scrolled body, where it covered the end of whatever line
	# happened to be there - "PASSIVE 1 HEAVY HANDS" with the last two words under the badge -
	# so the notice that content was hidden was itself hiding content. Showing it costs the
	# body a row, which can only ever keep an already-overflowing body overflowing: the fit
	# converges rather than flickering, and a summary that fits pays nothing for the marker.
	if _more_plate == null:
		return
	_more_plate.visible = overflowing
	if overflowing:
		_more_plate.add_theme_stylebox_override(&"panel", _plate_style())


## Opaque background for the "more below" marker, in the live theme's own colours.
static func _plate_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.color(&"floor_alt")
	style.border_color = UiTheme.color(&"text_dim")
	style.set_border_width_all(1)
	style.set_content_margin_all(2)
	return style


func show_summary(new_data: Dictionary) -> void:
	data = new_data
	var victory := bool(data.get("victory", false))
	var abandoned := is_abandoned(data)
	_headline.text = headline_for(victory, abandoned)
	_headline.add_theme_color_override(
		"font_color", UiTheme.text_color(headline_role(victory, abandoned))
	)
	# RunManager passes "class"; "class_name" is accepted as an alias for older callers.
	var class_name_text := str(data.get("class", data.get("class_name", ""))).capitalize()
	var theme_name := str(
		data.get("theme", Desktop.palette.name if Desktop.palette != null else "")
	)
	_subline.text = subline_text(data, class_name_text, theme_name)
	_subline.theme_type_variation = (
		&"Danger"
		if not victory and not abandoned and not str(data.get("killer", "")).is_empty()
		else &"Dim"
	)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var floor_text := "%d" % int(data.get("floor", 0))
	if victory:
		floor_text += " (cleared)"
	_add_row("Floor reached", floor_text)
	_add_row("Kills", str(int(data.get("kills", 0))))
	_add_row("Gold", str(int(data.get("gold", 0))))
	_add_row("Damage taken", str(int(data.get("damage_taken", 0))))
	_add_row("Time", format_time(float(data.get("time", 0.0))))
	# The theme name is the one value in this table nobody chose the length of - it is whatever
	# the player's desktop is called - and the table is the left half of a 344 px panel. Left to
	# widen the column, "Catppuccin Latte" took 26 px off the Gear column, wrapped three item
	# names and pushed the panel out through the top and bottom of the frame. It wraps instead.
	_add_row("Theme", theme_name, true)
	_fill_build()
	_fill_floors()
	_fill_stat_line()
	_fill_music()
	_body.scroll_vertical = 0
	_fit_to_frame()
	_queue_fit()
	_animate_in()
	# "New run" holds the focus, not "Reuse seed": the ordinary answer to a finished run is
	# another run, and a seed is a power-user handle that should not be the default action.
	_new_run.grab_focus()


## "The Ranger, Tiling WM" - what this run earned, for the table's Unlocked row.
static func earned_line(rows: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for row: Dictionary in rows:
		parts.append(str(row.get("title", "")))
	return ", ".join(parts)


## "Next: The Wizard - Defeat 120 enemies. 64 / 120"
static func next_line(row: Dictionary) -> String:
	var text := "Next: %s" % str(row.get("title", ""))
	var description := str(row.get("description", ""))
	if not description.is_empty():
		text += " - %s" % description
	var progress := str(row.get("progress", ""))
	if not progress.is_empty():
		text += " %s" % progress
	return text


## "+142 kills, +230 gold" - "" when the run moved nothing.
static func gains_line(gains: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: Variant in GAIN_LABELS.keys():
		var name := str(key)
		if not gains.has(name):
			continue
		var amount := int(gains[name])
		if amount <= 0:
			continue
		parts.append("+%d %s" % [amount, str(GAIN_LABELS[name])])
	if parts.is_empty():
		return ""
	return ", ".join(parts)


## What the radio did to the run, as a sentence: the calmest floor and the most frantic one,
## each named with the mood it ran at and the difference that made to how many enemies were
## waiting. "F2 frantic +12% foes" is a debug readout, not something a player would say, and
## it was on the screen that is supposed to be the reward for finishing a run.
##
## A flat list of song titles - which is all this screen used to carry before that - connects
## the music to nothing the player saw, and is most of why the levers read as doing nothing.
static func music_summary(floors: Array) -> String:
	var played: Array[Dictionary] = []
	for entry: Variant in floors:
		if entry is Dictionary and bool((entry as Dictionary).get("playing", true)):
			played.append(entry as Dictionary)
	if played.is_empty():
		return ""
	var calmest := played[0]
	var loudest := played[0]
	for entry: Dictionary in played:
		if float(entry.get("energy", 0.5)) < float(calmest.get("energy", 0.5)):
			calmest = entry
		if float(entry.get("energy", 0.5)) > float(loudest.get("energy", 0.5)):
			loudest = entry
	if calmest == loudest:
		return (
			"%s all run, which meant %s."
			% [mood_word(calmest).capitalize(), foes_phrase(calmest, true)]
		)
	return (
		"%s on floor %d meant %s; %s on floor %d meant %s."
		% [
			mood_word(calmest).capitalize(),
			int(calmest.get("floor", 0)),
			foes_phrase(calmest, true),
			mood_word(loudest),
			int(loudest.get("floor", 0)),
			foes_phrase(loudest, false)
		]
	)


## The mood a floor was generated in: "calm", "steady", "driving", "frantic". A floor built in
## silence had no mood, and says so rather than borrowing the middle one.
static func mood_word(entry: Dictionary) -> String:
	if not bool(entry.get("playing", true)):
		return "silent"
	var energy := clampf(float(entry.get("energy", 0.5)), 0.0, 1.0)
	return ENERGY_WORDS[clampi(
		int(energy * float(ENERGY_WORDS.size())), 0, ENERGY_WORDS.size() - 1
	)]


## What that did to the floor, in the words a player would use: "12% more enemies". The
## percentage is `GenParams`' own enemy-count scale (0.85 + 0.3 x energy), so it is the real
## number, not a flavour figure. `name_them` is false for the second half of a sentence that
## has already said what is being counted, so the line stays on one row of the panel.
static func foes_phrase(entry: Dictionary, name_them: bool = true) -> String:
	var percent := foes_percent(entry)
	var noun := " enemies" if name_them else ""
	if percent == 0:
		return "the usual number of enemies" if name_them else "no change"
	if percent > 0:
		return "%d%% more%s" % [percent, noun]
	return "%d%% fewer%s" % [-percent, noun]


## The enemy-count change a floor's music bought, as a signed whole percentage: `MusicLevers`'
## own number, the one the generator used.
static func foes_percent(entry: Dictionary) -> int:
	if not bool(entry.get("playing", true)):
		return 0
	var energy := clampf(float(entry.get("energy", 0.5)), 0.0, 1.0)
	return MusicLevers.shared().foes_percent(energy)


## One line per floor the log saw, in floor order: what was playing, the mood it made, and
## what that did to the enemies and the traps (`MusicLevers.floor_line`).
static func floor_lines(floors: Array) -> PackedStringArray:
	var entries: Array[Dictionary] = []
	for entry: Variant in floors:
		if entry is Dictionary:
			entries.append(entry as Dictionary)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("floor", 0)) < int(b.get("floor", 0))
	)
	var out := PackedStringArray()
	var levers := MusicLevers.shared()
	for entry: Dictionary in entries:
		out.append(
			levers.floor_line(
				int(entry.get("floor", 0)),
				str(entry.get("title", "")),
				clampf(float(entry.get("energy", 0.5)), 0.0, 1.0),
				float(entry.get("tempo", 0.0)),
				bool(entry.get("playing", true))
			)
		)
	return out


## The "Floors" section: a heading and one dim line per floor, full width under the two
## columns. Hidden when the run logged no floors (a summary shown from a fixture without them).
func _fill_floors() -> void:
	for child in _floors.get_children():
		_floors.remove_child(child)
		child.queue_free()
	var lines := floor_lines(_music_floors())
	_floors.visible = not lines.is_empty()
	if lines.is_empty():
		return
	var heading := _heading("Floors")
	_floors.add_child(heading)
	for line: String in lines:
		_floors.add_child(_foot_line(line, &"Dim"))


func _make_floors() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Floors"
	box.add_theme_constant_override("separation", UiTheme.GAP_NONE)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(box)
	return box


## The two full-width lines at the foot of the panel: what the radio did, and what the run
## earned. Full width on purpose - the table beside the build column is about thirteen
## characters across, and a sentence put there wraps into a ragged stack of single words.
##
## The section replaces the old "Tracks played" heading and its list of song titles. A list of
## songs connects the music to nothing the player saw, which is most of why the music levers
## read as doing nothing; and a run that ends without naming what it earned is a run with no
## reason to start another one.
func _fill_music() -> void:
	for child in _tracks.get_children():
		_tracks.remove_child(child)
		child.queue_free()
	var tracks: Variant = data.get("tracks", [])
	var list: Array = tracks if tracks is Array else []
	var progress := progress_line(_earned_unlocks(), _next_unlock(), _counter_gains())
	for text: String in [music_line(list), music_summary(_music_floors())]:
		if not text.is_empty():
			_tracks.add_child(_foot_line(text, &"Dim"))
	if not progress.is_empty():
		_tracks.add_child(_foot_line(progress, &"Accent"))


## One full-width line at the foot of the panel. It wraps rather than eliding: these lines sit
## below the scroll region now, so a second line costs the build column two pixels of height,
## and half a sentence about what the run unlocked is worth less than none.
static func _foot_line(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## "Music: Super Space, Dotfiles +1 more" - the playlist, and nothing else. What the radio did
## to the floors is its own sentence (`music_summary`) on its own line: the two were joined
## with a dash, and a song title followed by "F1 driving +0% foes" read as one run-on string
## of which half was a debug readout.
static func music_line(list: Array, _floors: Array = []) -> String:
	var names := tracks_line(list)
	return "" if names.is_empty() else "Music: %s" % names


## "Unlocked The Ranger. Next: The Wizard - Defeat 120 enemies. 12 / 120  (+42 kills)"
static func progress_line(earned: Array[Dictionary], next: Dictionary, gains: Dictionary) -> String:
	var parts: PackedStringArray = []
	if not earned.is_empty():
		parts.append("Unlocked %s." % earned_line(earned))
	if not next.is_empty():
		parts.append(next_line(next))
	var gain_text := gains_line(gains)
	if not gain_text.is_empty():
		parts.append("(%s this run)" % gain_text)
	return " ".join(parts)


func _music_floors() -> Array:
	var supplied: Variant = data.get("music_floors", null)
	if supplied is Array:
		return supplied as Array
	var music := _autoload(^"/root/Music")
	if music == null or not music.has_method(&"floor_log"):
		return []
	var entries: Variant = music.call(&"floor_log")
	return entries if entries is Array else []


func _earned_unlocks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rows := _progress_rows()
	for row: Dictionary in rows:
		if bool(row.get("earned_this_run", false)):
			out.append(row)
	return out


func _next_unlock() -> Dictionary:
	for row: Dictionary in _progress_rows():
		if not bool(row.get("unlocked", false)):
			return row
	return {}


func _progress_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var supplied: Variant = data.get("progress_rows", null)
	var rows: Variant = supplied
	if not (rows is Array):
		var save_manager := _autoload(^"/root/SaveManager")
		if save_manager == null or not save_manager.has_method(&"progress_rows"):
			return out
		rows = save_manager.call(&"progress_rows")
	if rows is Array:
		for row: Variant in rows as Array:
			if row is Dictionary:
				out.append(row as Dictionary)
	return out


func _counter_gains() -> Dictionary:
	var supplied: Variant = data.get("counter_gains", null)
	if supplied is Dictionary:
		return supplied as Dictionary
	var save_manager := _autoload(^"/root/SaveManager")
	if save_manager == null or not save_manager.has_method(&"counter_gains_this_run"):
		return {}
	var gains: Variant = save_manager.call(&"counter_gains_this_run")
	return gains if gains is Dictionary else {}


## An autoload by path, or null when it is not up (unit tests that build this screen alone).
func _autoload(path: NodePath) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null(path)


## The playlist on one line: "Neon Corridors, Dotfiles +1 more".
static func tracks_line(list: Array) -> String:
	var parts: PackedStringArray = []
	for i in mini(list.size(), MAX_TRACKS):
		parts.append(str(list[i]))
	var text := ", ".join(parts)
	if list.size() > MAX_TRACKS:
		text += " +%d more" % (list.size() - MAX_TRACKS)
	return text


func headline_text() -> String:
	return _headline.text


func subline_text_shown() -> String:
	return _subline.text


## True when the run was given up rather than lost: the player pressed Abandon on a live run.
## `RunManager` records it on the summary and in the profile, and the two must not disagree.
static func is_abandoned(source: Dictionary) -> bool:
	return bool(source.get("abandoned", false)) and not bool(source.get("victory", false))


## The word across the top of the screen. An abandoned run is not a death: the run tally still
## carries the last enemy that hit the player, and a screen built from it used to announce a
## death - and blame an enemy for it - to someone who had simply walked away.
static func headline_for(victory: bool, abandoned: bool) -> String:
	if victory:
		return "VICTORY"
	return "RUN ABANDONED" if abandoned else "YOU DIED"


## Palette role the headline is drawn in: a win reads as a gain, a death as a loss, and a run
## the player ended themselves as neither.
static func headline_role(victory: bool, abandoned: bool) -> StringName:
	if victory:
		return &"heal"
	return &"text_dim" if abandoned else &"danger"


## The line under the headline. A death names what killed the player and where, which is the
## single most useful fact about a run and was the one the screen never carried.
static func subline_text(source: Dictionary, class_name_text: String, theme_name: String) -> String:
	var killer := str(source.get("killer", ""))
	if (
		not bool(source.get("victory", false))
		and not is_abandoned(source)
		and not killer.is_empty()
	):
		return "Killed by %s on floor %d" % [killer, int(source.get("floor", 1))]
	if class_name_text.is_empty():
		return "Dungeon of %s" % theme_name
	return "%s in the Dungeon of %s" % [class_name_text, theme_name]


## The gear + ability panel: the build the run was spent assembling. A build rogue-like's
## death screen is where the player looks at what they made, and this one listed a playlist.
func _fill_build() -> void:
	for child in _build.get_children():
		_build.remove_child(child)
		child.queue_free()
	var equipment := _rows("equipment")
	var abilities := _rows("abilities")
	if equipment.is_empty() and abilities.is_empty():
		_build.visible = false
		return
	_build.visible = true
	if not equipment.is_empty():
		_build.add_child(_heading("Gear"))
		_build_grid(equipment)
	if not abilities.is_empty():
		if not equipment.is_empty():
			_build.add_child(_section_gap())
		_build.add_child(_heading("Abilities"))
		_build_grid(abilities)
	var innate := str(data.get("innate", ""))
	if not innate.is_empty():
		var label := Label.new()
		label.theme_type_variation = &"Accent"
		label.text = "Innate: " + innate
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_build.add_child(label)


func _rows(key: String) -> Array:
	var value: Variant = data.get(key, [])
	return value if value is Array else []


## Blank row that turns the next heading into a new section. A spacer rather than raising the
## column's separation, which would also push every heading away from its own grid.
func _section_gap() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, SECTION_GAP_PX)
	return spacer


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Heading"
	label.text = text
	return label


func _build_grid(rows: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiTheme.GAP)
	grid.add_theme_constant_override("v_separation", UiTheme.GAP_NONE)
	_build.add_child(grid)
	for entry: Variant in rows:
		var row: Dictionary = entry if entry is Dictionary else {}
		var slot := Label.new()
		slot.theme_type_variation = &"Dim"
		slot.text = str(row.get("slot", ""))
		slot.custom_minimum_size = Vector2(46, 0)
		# A wrapped gear name makes its row two lines tall; without this the slot name is
		# centred against it and "Armor" lines up with the *second* half of its own item.
		slot.size_flags_vertical = Control.SIZE_FILL
		slot.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		grid.add_child(slot)
		var name := Label.new()
		var text := str(row.get("name", ""))
		name.text = text if not text.is_empty() else "-"
		name.theme_type_variation = &"Bright" if not text.is_empty() else &"Dim"
		# Wraps instead of eliding. This panel's whole job is to show the build the run was
		# spent assembling, and "VITAL LEATHER JERK..." shows the player a build they cannot
		# read; the column is narrow, so the second line is the only place the name can go.
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var role := StringName(str(row.get("role", "")))
		if role != &"" and not text.is_empty():
			name.add_theme_color_override("font_color", UiTheme.text_color(role))
		grid.add_child(name)


## One line of final primaries: "VIT 8  MGT 7  PRE 2  ARC 1  SWI 3  FOR 2".
func _fill_stat_line() -> void:
	var value: Variant = data.get("stats", {})
	var stats: Dictionary = value if value is Dictionary else {}
	var parts: PackedStringArray = []
	for stat: StringName in Stats.PRIMARY:
		if stats.has(stat):
			parts.append("%s %d" % [STAT_SHORT.get(stat, String(stat)), int(stats[stat])])
	_stat_line.text = "   ".join(parts)
	_stat_line.visible = not parts.is_empty()


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]


## One label/value row of the left-hand table. `wrap` lets a value fold onto a second line
## rather than widen the whole column, which is only ever right for a value whose length the
## game does not control; the table has vertical slack and the Gear column beside it has none.
func _add_row(label_text: String, value_text: String, wrap: bool = false) -> void:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = label_text
	label.size_flags_vertical = Control.SIZE_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_grid.add_child(label)
	var value := Label.new()
	value.theme_type_variation = &"Bright"
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(value)
	if wrap:
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size.x = wrap_width(value)


## The width a wrapping value column asks for: the whole string when it is short enough that
## the table can afford it, and never narrower than the longest word. The panel used to be
## 344 px wide and every pixel the table took came off the gear column, so the theme name was
## squeezed to its longest word and "Catppuccin Latte" broke over two lines while the row above
## it read "212". At the panel's full width the table can hold an ordinary theme name whole.
static func wrap_width(label: Label) -> float:
	var font := label.get_theme_font(&"font")
	if font == null:
		return 0.0
	var font_size := label.get_theme_font_size(&"font_size")
	var whole := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return maxf(word_floor(label), minf(ceilf(whole), WRAP_VALUE_MAX))


## The narrowest a wrapping label may be if every word in it is to stay whole.
## `AUTOWRAP_WORD_SMART` wraps between words but falls back to splitting one when the column
## is narrower than the word itself, and a theme row reading "CATPPUCC / IN LATTE" looks like
## a typo rather than a wrap. Measured from the label's own font, so it follows the theme.
static func word_floor(label: Label) -> float:
	var font := label.get_theme_font(&"font")
	if font == null:
		return 0.0
	var font_size := label.get_theme_font_size(&"font_size")
	var widest := 0.0
	for word: String in label.text.split(" ", false):
		widest = maxf(
			widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	return ceilf(widest)


func _animate_in() -> void:
	_panel.pivot_offset = _panel.size * 0.5
	if not Accessibility.animates():
		_panel.scale = Vector2.ONE
		_panel.modulate.a = 1.0
		return
	_panel.scale = Vector2(0.92, 0.92)
	_panel.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
