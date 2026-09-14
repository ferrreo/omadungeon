## Tunables for driving the UI from a pad: how far the left stick has to be pushed before it
## counts as a UI direction, how far it has to come back before the next flick counts, the
## auto-repeat timings while it is held, and the two timings the rebind capture and the offer
## boards need. Shipped as `data/ui/nav.tres`; the script defaults are the fallback when that
## file is missing (tests that build the node by hand).
##
## Push and release are two different numbers on purpose. One threshold makes a stick resting
## near the edge of the deadzone rattle the selection back and forth; the gap between them is
## the hysteresis that stops it.
class_name UiNavProfile
extends Resource

## Path of the shipped profile.
const DEFAULT_PATH := "res://data/ui/nav.tres"

## Stick deflection (0..1) that starts a UI direction.
@export_range(0.1, 1.0, 0.01) var press_threshold: float = 0.55
## Deflection the stick has to fall back under before a new flick can start. Must be lower
## than `press_threshold`; `clean()` enforces that.
@export_range(0.05, 1.0, 0.01) var release_threshold: float = 0.3
## Seconds a direction is held before it starts repeating.
@export_range(0.05, 2.0, 0.01) var repeat_delay: float = 0.4
## Seconds between repeats once repeating has started.
@export_range(0.02, 1.0, 0.01) var repeat_interval: float = 0.13
## How long the rebind capture's cancel button (B) has to be held before it binds itself
## instead of backing out. Long enough that the tap which leaves every other screen still
## leaves this one, short enough to be a gesture rather than a wait.
@export_range(0.2, 2.0, 0.05) var capture_hold_seconds: float = 0.6
## How long a screen's answer to a button it cannot honour - Start on an offer board - stays
## on the hint line before the hint goes back to saying what the screen's controls are. Long
## enough to read a short sentence, short enough that it is gone by the next decision.
@export_range(0.5, 8.0, 0.1) var notice_seconds: float = 2.5
## How long the pad has to have been quiet before mouse *motion* makes the keyboard the active
## device (`InputGlyphs.observe`). A click or a key does it at once; motion is what a nudged
## mouse or a cursor warp sends, and it used to flip every prompt to key-caps mid-fight.
@export_range(0.0, 5.0, 0.05) var mouse_grace_seconds: float = 1.0


## The shipped profile, or a script-default one when it is not on disk.
static func load_default() -> UiNavProfile:
	if ResourceLoader.exists(DEFAULT_PATH):
		var res := load(DEFAULT_PATH) as UiNavProfile
		if res != null:
			return res.clean()
	return UiNavProfile.new()


## Returns this profile with `release_threshold` forced below `press_threshold`. A profile
## edited the other way round would make every flick a single step with no hysteresis at all,
## which is the bug the two thresholds exist to prevent.
func clean() -> UiNavProfile:
	release_threshold = minf(release_threshold, press_threshold - 0.05)
	return self
