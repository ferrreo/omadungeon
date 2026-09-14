## Toast banners (top-centre): slide in, hold, fade.
##
## Two lanes, because they are two different kinds of message and they were sharing one slot:
##
##   * the **gameplay** lane (`push`, `push_now`, `EventBus.toast`) carries facts - "Equipped
##     X", "-1 Might - stolen!", a boss phase, "Not enough gold", the descend warning;
##   * the **radio** lane (`push_track`) carries the now-playing banner, which is decoration.
##
## They used to be one serial queue capped at three, so a track change could delay a permanent
## stat loss past its own floating number, or push it off the queue entirely. The radio now has
## its own smaller banner underneath, it never blocks or displaces a gameplay message, and it
## can be switched off (`track_banner`) without silencing anything the player needs.
##
## `push_now` jumps the gameplay queue for messages that are only true *right now*: the live
## retint (Toast watches `EventBus.palette_changed` itself) and any message that has a matching
## in-world floater, which must not desync from it.
class_name Toast
extends Control

const SLIDE_IN := 0.18
const FADE_OUT := 0.3
const DEFAULT_DURATION := 2.0
## Backlog cap: a burst of toasts must not still be replaying minutes later.
const MAX_QUEUED := 3
## Wording of the live-retint banner. `DesktopWatcher` emits the same string on
## `EventBus.toast`; the duplicate guard in `push` swallows it.
const THEME_PREFIX := "Theme: "
const THEME_DURATION := 2.5
## Settings key for the now-playing banner. Default on; it is cosmetic either way.
const SETTING_TRACK_BANNER := "track_banner"
## Where the radio banner sits: bottom-centre, this many pixels clear of the screen edge. It
## is deliberately nowhere near the gameplay banner and nowhere near the HUD plates - the
## status strip grows rightward as effects land on the player, and a "now playing" that covers
## a frost stack has simply moved the problem from the queue to the screen.
const TRACK_BOTTOM_MARGIN := 4
## Fallback gap under the gameplay banner, used when the control has no viewport to measure.
const TRACK_GAP := 2

## Gap kept between a banner and the HUD plate beside it.
const LANE_GAP := 4.0

@export var listen_to_bus: bool = true

## Where the two lanes may draw, as `Callable() -> Dictionary` with `top` and `bottom` each a
## `Vector2(left, right)` in screen x, or unset. The HUD supplies it from its live plates: the
## top lane is the gap between the HP block and the floor label, the bottom lane the gap
## between the ability bar and the minimap. A banner wider than its lane wraps rather than
## running under a plate; before this the now-playing line ran under the map's "rooms left"
## strip and the first-floor hint butted against the HP panel.
var lane_source: Callable = Callable()

var _queue: Array[Dictionary] = []
var _busy: bool = false
var _panel: PanelContainer
var _label: Label
var _tween: Tween
var _track_panel: PanelContainer
var _track_label: Label
var _track_tween: Tween
## Text of the last message shown, kept after it faded so a duplicate arriving right behind
## an interrupt (the desktop watcher's own "Theme: x") is not replayed.
var _last_shown: String = ""
## Text of the radio banner as pushed, before any line breaks the lane put into it.
var _track_text: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"Hud"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.theme_type_variation = &"Bright"
	_panel.add_child(_label)
	add_child(_panel)
	_panel.modulate.a = 0.0
	_track_panel = PanelContainer.new()
	_track_panel.theme_type_variation = &"HudPlate"
	_track_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track_label = Label.new()
	_track_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_track_label.theme_type_variation = &"Dim"
	_track_panel.add_child(_track_label)
	add_child(_track_panel)
	_track_panel.modulate.a = 0.0
	if listen_to_bus:
		EventBus.toast.connect(push)
		EventBus.palette_changed.connect(_on_palette_changed)


## Enqueues a toast; shown after the current one finishes. Consecutive duplicates collapse
## and the queue is capped at MAX_QUEUED (oldest dropped) so the newest message always shows.
func push(text: String, duration: float = DEFAULT_DURATION) -> void:
	if not _queue.is_empty() and str(_queue[-1]["text"]) == text:
		return
	if _busy and _queue.is_empty() and _last_shown == text:
		return
	_queue.append({"text": text, "duration": maxf(0.3, duration)})
	while _queue.size() > MAX_QUEUED:
		_queue.pop_front()
	if not _busy:
		_next()


## Drops `text` from the lane: removed from the queue, and faded out now if it is the message
## currently up. A banner is a sentence frozen at the moment it was pushed, and some of them
## stop being true while they are still on screen (the first-floor hint after the floor
## changed). Nothing else is disturbed - the queue keeps draining into the freed slot.
func dismiss(text: String) -> void:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _queue:
		if str(entry["text"]) != text:
			kept.append(entry)
	_queue = kept
	if not _busy or _last_shown != text:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# `_busy` stays true through the fade, so the lane is not handed to a queued message
	# mid-animation; the text is cleared instead, which is what `current_text()` reports.
	_last_shown = ""
	_label.text = ""
	var tween := create_tween()
	_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_panel, "modulate:a", 0.0, Accessibility.motion(FADE_OUT))
	tween.tween_callback(_next)


## Shows `text` immediately, cutting the banner that is up short. Use it only for messages
## that stop being true while they wait (the live theme change); everything else queues.
func push_now(text: String, duration: float = DEFAULT_DURATION) -> void:
	if _busy and _last_shown == text:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_queue.push_front({"text": text, "duration": maxf(0.3, duration)})
	_busy = false
	_next()


func _on_palette_changed(palette: ThemePalette) -> void:
	if palette == null:
		return
	push_now(THEME_PREFIX + palette.name, THEME_DURATION)


## Whether the now-playing banner is switched on. Nothing the player must read goes through
## this lane, so the answer only ever hides decoration.
static func track_banner_enabled() -> bool:
	return bool(GameState.settings.get(SETTING_TRACK_BANNER, true))


## Shows a radio banner in its own lane below the gameplay one. It never enters the gameplay
## queue, never delays a message already waiting there and never displaces one at the cap.
## Returns false when the player has the banner switched off.
func push_track(text: String, duration: float = DEFAULT_DURATION) -> bool:
	if not track_banner_enabled() or text.is_empty():
		return false
	if _track_tween != null and _track_tween.is_valid():
		_track_tween.kill()
	_track_text = text
	_fit_to_lane(_track_panel, _track_label, "bottom", text)
	_position_track()
	_track_panel.modulate.a = 1.0
	var tween := create_tween()
	_track_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(maxf(0.3, duration))
	tween.tween_property(_track_panel, "modulate:a", 0.0, Accessibility.motion(FADE_OUT))
	return true


## Text on the radio lane right now, or "" when it is not showing.
func track_text() -> String:
	return _track_text if _track_panel != null and _track_panel.modulate.a > 0.0 else ""


func queued_count() -> int:
	return _queue.size()


## Screen rect of the gameplay banner while one is up, else an empty rect.
func panel_rect() -> Rect2:
	if _panel == null or not _busy or _panel.modulate.a <= 0.0:
		return Rect2()
	return _panel.get_global_rect()


## Screen rect of the radio banner while one is up, else an empty rect.
func track_rect() -> Rect2:
	if _track_panel == null or _track_panel.modulate.a <= 0.0:
		return Rect2()
	return _track_panel.get_global_rect()


## The span of screen x a lane may draw in: what `lane_source` says, else the whole width.
func lane(name: String) -> Vector2:
	var whole := Vector2(global_position.x, global_position.x + size.x)
	if not lane_source.is_valid():
		return whole
	var lanes: Variant = lane_source.call()
	if not (lanes is Dictionary) or not (lanes as Dictionary).has(name):
		return whole
	var span: Vector2 = (lanes as Dictionary)[name]
	return span if span.y - span.x >= 32.0 else whole


## Sizes `panel` for its text inside `lane_name`: a line that fits is one line; a longer one
## is broken into lines that fit the lane's width, padded, so nothing is ever drawn under a
## plate or cut. The breaks are put into the text (`wrap_words`) rather than left to
## `autowrap_mode`: an autowrapped Label reports a one-word-per-line minimum until it has
## been laid out, and a panel sized from that stood 773 px tall.
func _fit_to_lane(panel: PanelContainer, label: Label, lane_name: String, text: String) -> void:
	var span := lane(lane_name)
	var room := span.y - span.x - LANE_GAP * 2.0
	var style := panel.get_theme_stylebox(&"panel")
	var pad := style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT) if style != null else 0.0
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	# A widget with no lane and no size of its own (a bare Toast in a test) wraps nothing.
	label.text = text if room - pad < 32.0 else wrap_words(text, font, font_size, room - pad)
	panel.reset_size()


## `text` with newlines inserted so no line is wider than `width` (a single word wider than
## that stands alone on its line). Greedy, on spaces; existing newlines are kept.
static func wrap_words(text: String, font: Font, font_size: int, width: float) -> String:
	var lines: PackedStringArray = []
	for paragraph: String in text.split("\n"):
		var line := ""
		for word: String in paragraph.split(" ", false):
			var candidate := word if line.is_empty() else "%s %s" % [line, word]
			var w := font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if w <= width or line.is_empty():
				line = candidate
			else:
				lines.append(line)
				line = word
		lines.append(line)
	return "\n".join(lines)


## x at which a panel `width` wide sits centred in `lane_name`, in this control's space.
func _lane_x(width: float, lane_name: String) -> float:
	var span := lane(lane_name)
	return floorf((span.x + span.y) * 0.5 - width * 0.5 - global_position.x)


func is_showing() -> bool:
	return _busy


func current_text() -> String:
	return _last_shown if _busy else ""


## Centres the radio banner along the bottom of the screen, in this control's own space. The
## gameplay banner keeps the top slot to itself; nothing cosmetic is ever drawn over the HUD
## plates or over a message that matters.
func _position_track() -> void:
	var below := _panel.size.y if _panel.size.y > 0.0 else float(size.y)
	var y := below + TRACK_GAP
	var view := get_viewport_rect().size
	if view.y > 0.0:
		var bottom := view.y - _track_panel.size.y - float(TRACK_BOTTOM_MARGIN) - global_position.y
		if bottom > y:
			y = bottom
	_track_panel.position = Vector2(_lane_x(_track_panel.size.x, "bottom"), floorf(y))


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var entry: Dictionary = _queue.pop_front()
	_last_shown = str(entry["text"])
	_fit_to_lane(_panel, _label, "top", _last_shown)
	var target := Vector2(_lane_x(_panel.size.x, "top"), 0.0)
	_panel.position = target + Vector2(0, Accessibility.motion(-8.0))
	_panel.modulate.a = 0.0 if Accessibility.animates() else 1.0
	var tween := create_tween()
	_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	var slide := Accessibility.motion(SLIDE_IN)
	tween.tween_property(_panel, "position", target, slide).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_panel, "modulate:a", 1.0, slide)
	tween.set_parallel(false)
	# Hold for less time while messages are backed up, so the queue drains quickly.
	var hold := float(entry["duration"])
	if not _queue.is_empty():
		hold = minf(hold, 0.8)
	tween.tween_interval(hold)
	tween.tween_property(_panel, "modulate:a", 0.0, Accessibility.motion(FADE_OUT))
	tween.tween_callback(_next)
