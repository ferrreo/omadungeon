## The look a track's mood resolves to, as numbers the *lights* can be driven by.
##
## It used to be a colour grade over every environment surface, a vignette and a haze as well,
## and the owner's ruling took all three out: "TORCHES SHOULD CAST THE LIGHT, THERE SHOULD BE NO
## OTHER LIGHT OTHER THAN PARTICLE EFFECTS, TORCHES ETC". A full-frame grade is a light with no
## source in the room, so there is no longer a `music_grade` shader include, no `music_tint` /
## `music_tone` globals, no full-rect mist and no intensity multiplier on the theme's colours.
## The theme reaches the screen exactly as the theme authored it.
##
## What is left is what a flame is allowed to do. `torch` is how hard every light in the dungeon
## burns, `radius` how far its pool reaches, `flicker` how far it wanders, `particles` how many
## motes drift, and `tint`, `saturation`, `hue_target`, `hue_rotate` and `light_hue_pull` are the
## colour of the flame itself - a much wider budget than a surface ever had, because a fire is
## allowed to change temperature and a floor is not (`light_color`).
##
## `neutral()` is the theme untouched: white tint, unit chroma, no hue pull, torches as authored,
## no motes. Every other state is `blended()` from it, so the settings amount slider is one lerp
## toward neutral and "at zero the visuals are pure theme" is true by construction rather than by
## a list of ifs.
class_name MusicMoodState
extends RefCounted

## Rec. 709 luma weights.
const LUMA := Vector3(0.2126, 0.7152, 0.0722)
## Absolute chroma (max channel less min channel) a colour needs before its hue is a thing the
## guard below protects. Under it a light is a white lamp and its "hue" is quantisation - the
## same line `ThemePalette.ROOM_CAST_OWN_CHROMA_MIN` draws, for the same reason: HSV saturation
## lies about a near-black, absolute chroma does not.
const HUE_GUARD_CHROMA := 0.012

## Colour multiplier at unit luminance on a *light's own colour* (so it changes the flame's
## temperature, not how much light there is - that is `torch`).
var tint: Color = Color.WHITE
## Chroma multiplier around the luma of a light's colour.
var saturation: float = 1.0
## Hue a light's colour is turned toward (turns), and the furthest it may be turned
## (`light_hue_pull`, 0.10 turns = 36 degrees). A pull of 0 leaves the hue alone whatever the
## target says. There is no separate surface budget any more, because the music no longer
## touches a surface.
var hue_target: float = 0.0
var light_hue_pull: float = 0.0
## Signed rotation of a light's hue (turns) on top of the pull: the track's seed at mid energy.
var hue_rotate: float = 0.0
## Multipliers on the torch flicker amplitude and on every light's energy.
var flicker: float = 1.0
var torch: float = 1.0
## Multiplier on every light's *radius*: how wide the pool of light is.
var radius: float = 1.0
## Share of the drifting motes the layer may show, 0..1.
var particles: float = 0.0


## The theme untouched.
static func neutral() -> MusicMoodState:
	return MusicMoodState.new()


## A tint of `chroma` at `hue` (turns), scaled so its luma is exactly 1: multiplying by it
## warms or cools a colour without making it brighter or darker.
static func unit_tint(hue: float, chroma: float) -> Color:
	var c := Color.from_hsv(fposmod(hue, 1.0), clampf(chroma, 0.0, 1.0), 1.0, 1.0)
	var luma := LUMA.dot(Vector3(c.r, c.g, c.b))
	if luma <= 0.0:
		return Color.WHITE
	return Color(c.r / luma, c.g / luma, c.b / luma, 1.0)


## Signed shortest way round the hue circle from `from` to `to`, in turns (-0.5..0.5).
static func hue_delta(from: float, to: float) -> float:
	var d := fposmod(to - from + 0.5, 1.0) - 0.5
	return d


## The way round the circle a crossfading hue target takes from `from` to `to`, in turns:
## the shortest arc unless that arc crosses green (1/3), in which case the other way. The
## targets live between a cool blue and a warm amber and `MusicMoodLevers.target_hue` walks
## between them through the reds; a crossfade that cut through green instead would swing every
## pulled hue the wrong way for a second in the middle of the fade.
static func target_route(from: float, to: float) -> float:
	var d := hue_delta(from, to)
	var a := fposmod(from, 1.0)
	var lo := minf(a, a + d)
	var hi := maxf(a, a + d)
	for green: float in [1.0 / 3.0, 4.0 / 3.0, -2.0 / 3.0]:
		if green > lo and green < hi:
			return d - signf(d)
	return d


## Every field lerped `t` of the way from this state to `other`. The hue target moves on the
## short arc, and takes the other side's target outright when this side has no pull (a
## neutral state has no hue of its own to fade from).
func blended(other: MusicMoodState, t: float) -> MusicMoodState:
	var k := clampf(t, 0.0, 1.0)
	var out := MusicMoodState.new()
	out.tint = tint.lerp(other.tint, k)
	out.saturation = lerpf(saturation, other.saturation, k)
	out.light_hue_pull = lerpf(light_hue_pull, other.light_hue_pull, k)
	out.hue_rotate = lerpf(hue_rotate, other.hue_rotate, k)
	if light_hue_pull <= 0.0001:
		out.hue_target = other.hue_target
	elif other.light_hue_pull <= 0.0001:
		out.hue_target = hue_target
	else:
		out.hue_target = fposmod(hue_target + target_route(hue_target, other.hue_target) * k, 1.0)
	out.flicker = lerpf(flicker, other.flicker, k)
	out.torch = lerpf(torch, other.torch, k)
	out.radius = lerpf(radius, other.radius, k)
	out.particles = lerpf(particles, other.particles, k)
	return out


## This state `amount` of the way out from neutral: the settings slider.
func scaled(amount: float) -> MusicMoodState:
	return neutral().blended(self, amount)


## True when nothing here would change a pixel: the test for "pure theme".
func is_neutral(epsilon: float = 0.0005) -> bool:
	return (
		tint.is_equal_approx(Color.WHITE)
		and absf(saturation - 1.0) < epsilon
		and light_hue_pull < epsilon
		and absf(hue_rotate) < epsilon
		and absf(flicker - 1.0) < epsilon
		and absf(torch - 1.0) < epsilon
		and absf(radius - 1.0) < epsilon
		and particles < epsilon
	)


## The colour a light burns in under this mood: the authored light colour, turned on the hue
## circle by the light's own budget, its chroma scaled about its luma, and warmed or cooled by
## the temperature tint - at full value, so it is still a light.
##
## This is the *only* road the music has to a colour on the screen. It runs on lights, never on
## surfaces: a flame is the one thing in the room allowed to change temperature with the music,
## and with the dungeon lit in pockets it is the biggest coloured thing a player sees.
func light_color(light: Color) -> Color:
	var out := graded(light, light_hue_pull)
	return Color.from_hsv(out.h, out.s, maxf(light.v, 0.5), light.a)


## `light_color` without the value floor, kept separate so the hue guard below and the tests
## that measure it can work on the raw result: hue pull and rotation, chroma about the luma,
## then the temperature tint, then the budget enforced.
func graded(c: Color, pull: float) -> Color:
	var out := c
	if (pull > 0.0 or hue_rotate != 0.0) and c.s > 0.0:
		var d := hue_delta(c.h, hue_target)
		var rot := clampf(d, -pull, pull) + hue_rotate
		out = Color.from_hsv(fposmod(c.h + rot, 1.0), c.s, c.v, c.a)
	var rgb := Vector3(out.r, out.g, out.b)
	var luma := LUMA.dot(rgb)
	rgb = Vector3(luma, luma, luma) + (rgb - Vector3(luma, luma, luma)) * saturation
	rgb = rgb * Vector3(tint.r, tint.g, tint.b)
	var done := Color(
		clampf(rgb.x, 0.0, 1.0), clampf(rgb.y, 0.0, 1.0), clampf(rgb.z, 0.0, 1.0), c.a
	)
	return hue_guarded(c, done, pull)


## `done` pulled back to within the hue budget of `source`. The rotation above is bounded, but
## nothing after it was: the chroma scaling, the temperature tint and the clip to 0..1 all move
## a hue, and on a *desaturated* colour they move it a long way, because there is little of the
## original left for them to be small against. A colour under `HUE_GUARD_CHROMA` is left alone -
## it has no hue to preserve, and forcing a near-white lamp to keep its quantisation noise would
## be worse than the tint.
func hue_guarded(source: Color, done: Color, pull: float) -> Color:
	if chroma_of(source) < HUE_GUARD_CHROMA:
		return done
	var allowed := absf(pull) + absf(hue_rotate)
	var d := hue_delta(source.h, done.h)
	if absf(d) <= allowed:
		return done
	return Color.from_hsv(
		fposmod(source.h + clampf(d, -allowed, allowed), 1.0), done.s, done.v, done.a
	)


## Absolute chroma: the spread between a colour's brightest and darkest channel.
static func chroma_of(c: Color) -> float:
	return maxf(maxf(c.r, c.g), c.b) - minf(minf(c.r, c.g), c.b)


## What this state multiplies the light landing on a surface by, and therefore the luminance of
## every lit pixel in the dungeon: `torch` (how hard the lights burn) times what the temperature
## tint does to the luminance of the light's own colour, which is by construction almost nothing
## because `unit_tint` is normalised to unit luma.
##
## This is the quantity the anti-flash suite measures frame by frame. It used to be the middle
## of the screen under the full-frame grade; with the grade gone, the light itself is the only
## thing the music can move, so this is the same guarantee pointed at the thing that moved.
func luminance_factor() -> float:
	var lamp := Color(1.0, 1.0, 1.0, 1.0)
	return torch * maxf(light_color(lamp).get_luminance(), 0.0001)


func to_dict() -> Dictionary:
	return {
		"tint": tint,
		"saturation": saturation,
		"hue_target": hue_target,
		"light_hue_pull": light_hue_pull,
		"hue_rotate": hue_rotate,
		"flicker": flicker,
		"torch": torch,
		"radius": radius,
		"particles": particles,
	}
