## The one visual language for "this will hurt". Every threat that arms before it lands —
## an enemy windup ring, a trap's floor tell, a boss slam marker — draws with these numbers so
## the player learns a single pattern: the theme `danger` colour, pulsing at `tell_pulse_hz`,
## getting brighter, faster and slightly larger as the strike approaches, with a growing ring
## and an exclamation mark above the source.
##
## Pure functions of (elapsed, total) so callers stay stateless; the numbers live in
## `FeelProfile` and are mirrored by `TrapBase`'s own constants (locked by a test).
class_name DangerTell
extends RefCounted

## Palette role every tell is drawn in (docs §10: tells are one of the two theme-tinted
## exceptions to "enemies keep their authored colours").
const ROLE := &"danger"
## Fallback colour before `Desktop.palette` is ready.
const FALLBACK := Color(0.9, 0.3, 0.3)
## Fraction of the pulse that is replaced by "always bright" at full urgency.
const URGENCY_BOOST := 0.5
## The ring starts at this fraction of its final radius: already clear of a 16 px body on the
## first frame, so the tell is readable the instant it appears and only grows from there.
const RING_START := 0.75
## Fraction of the tell alpha the filled area under a ring is washed in, so an enemy windup and
## a trap's floor overlay read as the same "this patch of ground is about to hurt".
const AREA_ALPHA_SCALE := 0.55
## Base ring line width in px, plus `pulse` on top.
const RING_WIDTH := 1.0
## Exclamation mark geometry above the source (px, in the tell's local space).
const MARK_STEM := Rect2(-1.0, -24.0, 2.0, 5.0)
const MARK_DOT := Rect2(-1.0, -18.0, 2.0, 2.0)

static var _cached: FeelProfile = null


## Live `danger` colour (opaque), or FALLBACK before the palette exists.
static func color() -> Color:
	if Desktop.palette == null:
		return FALLBACK
	return Desktop.palette.get_color(ROLE)


## 0..1 pulse at `tell_pulse_hz`. Time-based, so a long tell and a short one throb alike.
static func pulse(elapsed: float, hz: float = -1.0) -> float:
	var rate := hz if hz > 0.0 else default_profile().tell_pulse_hz
	return 0.5 + 0.5 * sin(elapsed * TAU * rate)


## 0..1 "how close is the hit", used to brighten and speed the tell up as it lands.
static func urgency(elapsed: float, total: float) -> float:
	return clampf(elapsed / maxf(total, 0.01), 0.0, 1.0)


## Tell alpha at `elapsed` of a `total`-second arming window: the pulse, pushed toward full
## brightness by urgency, mapped into the profile's alpha band.
static func alpha(elapsed: float, total: float, prof: FeelProfile = null) -> float:
	var p := prof if prof != null else default_profile()
	var t := lerpf(pulse(elapsed, p.tell_pulse_hz), 1.0, urgency(elapsed, total) * URGENCY_BOOST)
	return lerpf(p.tell_alpha_min, p.tell_alpha_max, t)


## `color()` at the tell alpha for this moment.
static func tinted(elapsed: float, total: float, prof: FeelProfile = null) -> Color:
	var c := color()
	c.a = alpha(elapsed, total, prof)
	return c


## Radius the growing windup ring has at `elapsed` of `total`, given its final `radius`.
static func ring_radius(elapsed: float, total: float, radius: float) -> float:
	return lerpf(radius * RING_START, radius, urgency(elapsed, total))


## Scale a tell polygon/sprite breathes to (traps scale their floor overlay by this).
static func breathe(elapsed: float, hz: float = -1.0) -> float:
	return 1.0 + 0.04 * pulse(elapsed, hz)


## The shared profile, loaded once per process.
static func default_profile() -> FeelProfile:
	if _cached == null:
		_cached = FeelProfile.load_default()
	return _cached
