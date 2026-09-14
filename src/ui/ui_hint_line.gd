## A screen's one-line prompt, and the one-off answers that borrow it.
##
## A hint line normally says what the screen's controls are. Now and then it has to answer
## something instead - a button the screen cannot honour, pressed anyway - and then go back to
## what it was saying. The rules for that are the same wherever it happens, so they live here:
## the notice holds for `UiNavProfile.notice_seconds`, and any ordinary rewrite of the line
## cancels it, because by then it is answering a question the player has stopped asking.
##
## The other half of an answer is a twitch on the control that *can* do what was asked, which
## is what `shake` is: a line of text at the bottom of the screen is easy to miss, and a
## control that moves is not.
class_name UiHintLine
extends RefCounted

## What an offer board says when Start is pressed and there is no way out at all (a mandatory
## pick - the opening passive). Nothing to point at, so it says why the board is not moving.
const MANDATORY_NOTICE := "This one is not optional - pick an offer to carry on"
## Pixels the shake throws a control either side of where it sits.
const SHAKE_PIXELS := 2.0
## Seconds of each leg of the shake. Four legs plus the settle, so about a fifth of a second.
const SHAKE_STEP := 0.03

## The prompt being written to. Null is tolerated so a screen can be built headless.
var label: UiPrompt
## Seconds a notice holds before the screen's normal hint comes back.
var seconds: float
var _left: float = 0.0


func _init(hint: UiPrompt, hold_seconds: float) -> void:
	label = hint
	seconds = maxf(hold_seconds, 0.0)


## Writes the screen's ordinary hint, cancelling any notice sitting on top of it.
func set_text(text: String) -> void:
	_left = 0.0
	if label != null:
		label.text = text


## Puts `text` up as a notice for `seconds`.
func notice(text: String) -> void:
	if label == null:
		return
	label.text = text
	_left = seconds


## True while a notice is up rather than the screen's ordinary hint.
func showing_notice() -> bool:
	return _left > 0.0


## Counts a notice down. Returns true on the tick it runs out, which is the caller's cue to
## draw its ordinary hint again.
func tick(delta: float) -> bool:
	if _left <= 0.0:
		return false
	_left -= delta
	return _left <= 0.0


## What a screen says when the player presses a button that does not leave it, on a screen
## that has a way out: names the button that does, drawn for the device in their hands, and
## the caption that button carries - "Skip (+5g)" and "Leave" are different promises and the
## player is about to act on one of them.
static func leave_notice(leave_label: String) -> String:
	return (
		"The run is already on hold - {ui_cancel} %s, or pick one of these" % leave_label.to_lower()
	)


## Twitches `control` from side to side without moving where it ends up. Silent under
## reduce-motion, which is the setting that asked for exactly that.
static func shake(control: Control) -> void:
	if control == null or not control.is_inside_tree() or not Accessibility.animates():
		return
	var origin := control.position
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i in 4:
		var offset := SHAKE_PIXELS if i % 2 == 0 else -SHAKE_PIXELS
		tween.tween_property(control, "position:x", origin.x + offset, SHAKE_STEP)
	tween.tween_property(control, "position:x", origin.x, SHAKE_STEP)
	tween.tween_callback(resettle.bind(control))


## Hands a shaken control back to its container.
##
## The tween's last step restores the position the control held when the shake started, and
## that is a guess: a row laid out (or re-laid out) while the shake was running has moved its
## children since. A control shaken in the same frame its row was built started from (0, 0)
## and was pinned to the left edge of that row permanently - which is what a board answering
## Start in the frame it was filled did to its Skip button. The container is the authority on
## where its children sit, so it is asked rather than second-guessed.
static func resettle(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return
	var box := control.get_parent() as Container
	if box != null:
		box.queue_sort()
