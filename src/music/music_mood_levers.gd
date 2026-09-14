## How far a track's mood (`MusicMood`) may move what the player sees *right now*, as data
## (`data/music/music_mood.tres`) - the live counterpart of `MusicLevers`, which only ever
## reaches a floor when it is built.
##
## Every lever here is a pair read as "energy 0 -> calm value, energy 1 -> loud value", lerped
## between, and every pair is chosen so that energy 0.5 - silence, or a track nobody measured -
## lands on or near the theme's own look. The mapping runs through `MusicMoodState`, so a test
## can measure exactly what a track does to a flame without rendering a frame.
##
## Every lever here drives a **light**, and there is nothing else left for one to drive. The
## round before this one still had `intensity_calm`/`_loud` over every environment colour,
## `vignette_calm`/`_loud` over the whole frame and `haze_calm`/`_loud` as a mist laid on top,
## and the owner deleted the three of them in one sentence: a dungeon is lit by the things
## burning in it and by nothing else. So a track's mood now says how hard the torches burn
## (`torch_calm`/`_loud`), how wide their pools reach (`torch_radius_*`), how far the flames
## wander (`flicker_*`), what colour the fire is (`light_hue_pull`, `tint_chroma`,
## `saturation_*`) and how many motes drift through it (`particles_*`). Turn every one of them
## down and the dungeon is the theme's own colours lit by the theme's own fire.
##
## The theme's 15-degree hue guarantee is therefore now exact rather than budgeted: the music
## does not touch a surface at all, so no environment role moves by any amount under any track
## (`tests/unit/audio/music_mood_test.gd`). The flame keeps its own, much wider budget -
## `light_hue_pull` is 36 degrees - because a fire is allowed to change temperature, and with
## the dungeon lit in pockets the colour and the size of those pockets are the largest coloured
## things on the screen and the whole of how a player hears the music with their eyes.
class_name MusicMoodLevers
extends Resource

const PATH := "res://data/music/music_mood.tres"

static var _cached: MusicMoodLevers

## --- hue ----------------------------------------------------------------------------------
## Where a calm track pulls the dungeon's colours toward, in turns of the hue circle
## (0.60 is a blue at 216 degrees), and where a loud one does (0.08 is an amber at 29).
@export var cool_hue: float = 0.60
@export var warm_hue: float = 0.08
## How far the track's own hue seed may move that target either way, in turns. 0.07 is 25
## degrees: two calm tracks can lean cyan and violet respectively.
@export var hue_seed_spread: float = 0.07
## Furthest a *light's* own colour is rotated toward the target hue, in turns:
## 0.10 is 36 degrees, which takes a torch from the theme's fire well toward the track's own
## temperature. The theme's hue guarantee is a guarantee about the dungeon, not about the
## flames burning in it, and with few strong lights the flame colour is the headline the mood
## has to speak through. Scaled by how extreme the track is.
@export var light_hue_pull: float = 0.10
## Signed rotation of a light's hue, in turns, that a track's seed applies at *middling* energy
## (seed 0 turns the flame `-hue_seed_rotate`, seed 1 `+hue_seed_rotate`). The pull above is
## scaled by how far the energy is from 0.5 and this by how close it is, so the two never add:
## the calmest and loudest tracks are pure pull, two steady tracks differ purely by seed, and
## the total rotation of any colour is never more than the larger of the two.
##
## 0.045 is 16 degrees, up from the 9.4 it was. It used to land on every *surface* in the room,
## where 9.4 was most of the theme's whole 15-degree budget; it only reaches flames now, whose
## budget is `light_hue_pull` at 36 degrees, and at 9.4 two steady tracks lit the same room in
## fires 8.6 degrees apart - which is a difference nobody sees, and "two tracks look the same" is
## the report this lever exists to answer.
@export var hue_seed_rotate: float = 0.045
## Chroma of the temperature tint laid over a light's own colour (an HSV saturation at the
## target hue, normalised to unit luminance so it changes the flame's colour and not how much
## light it gives). It was small because it used to land on every surface in the dungeon and a
## tint turns a low-chroma surface's hue a long way; it only reaches flames now, which carry
## plenty of chroma of their own, so it can be worth seeing.
@export var tint_chroma: float = 0.12
## Chroma multiplier on a light's own colour at energy 0 and 1: a brooding track burns a paler
## fire, a fierce one a fully saturated one.
@export var saturation_calm: float = 0.72
@export var saturation_loud: float = 1.30
## --- torches ------------------------------------------------------------------------------
## Multiplier on the torch flicker amplitude at energy 0 and 1. The flicker is slow noise and
## stays slow noise; only how far it wanders changes.
@export var flicker_calm: float = 0.5
@export var flicker_loud: float = 1.6
## Multiplier on every light's energy at energy 0 and 1 - the torches, the lanterns, the
## player's own pool and every emitter alike. This is the whole of what the music does to how
## bright the dungeon is, and it does it by turning the fires up and down.
##
## The band used to be shared with `intensity_calm`/`_loud`, which moved every surface whether
## anything was lighting it or not; with that gone this carries the mood on its own, so it is
## wider than it was. It is bounded by the anti-flash guarantee rather than by taste: a
## crossfade of this swing over `crossfade_seconds` has a steepest frame of
## `1.5 * (torch_loud - torch_calm) / crossfade_seconds / 60`, which
## `music_reactive_layer_test.MAX_CHANGE_FRAME_DELTA` holds to 0.004.
@export var torch_calm: float = 0.70
@export var torch_loud: float = 1.35
## How far a bright (treble-heavy) track lifts that multiplier, and a dark one lowers it: the
## shift at brightness 1 is `+brightness_push`, at 0 `-brightness_push`. It used to push the
## whole frame's exposure; it pushes the fires now, which is the same sentence about the same
## track told by something a player can point at.
@export var brightness_push: float = 0.04
## Multiplier on every torch light's *radius* at energy 0 and 1 (`DungeonLight.torch_radius_scale`,
## applied to `torch_texture_scale` and `LightingProfile.lantern_texture_scale`). A pool that
## draws in to three quarters of itself under a brooding track and opens to a quarter over
## itself under a fierce one changes the shape of the room, not only its level - and a shape is
## the thing a person notices without being told to look. Bounded well inside the falloff: a
## light never reaches further than the room it is in.
@export var torch_radius_calm: float = 0.78
@export var torch_radius_loud: float = 1.28
## --- particles ----------------------------------------------------------------------------
## Share of `particles_max` ambient motes drifting over the frame at energy 0 and 1, the most
## there can be, and the most under reduce-motion.
@export var particles_calm: float = 0.18
@export var particles_loud: float = 1.0
@export var particles_max: int = 48
@export var particles_reduced_motion: int = 8
## --- the live envelope --------------------------------------------------------------------
## How far the music's *own loudness right now* may move the track's energy, either way.
##
## The per-track mood is the base - it is what makes two tracks look different - and this is
## what makes one track breathe as it plays. The owner's words were "it needs to change based
## on what is happening over the current track": a static look per track answers "which song is
## on" and not "what is the song doing". `MusicReactiveLayer` follows the track's *envelope*
## (`Music.energy`, a slow relative loudness) through two multi-second low-pass stages and the
## rate cap below, and offsets the track's own energy by up to this much.
##
## 0.22 is a band, not a takeover: a track measured at 0.5 breathes between 0.28 and 0.72, so a
## quiet passage of a lively track never looks like the calmest track in the set and a drop
## never looks like the loudest. The bound is what keeps "different tracks look different"
## true while "one track breathes" is also true.
@export_range(0.0, 0.5) var live_swing: float = 0.22
## Most the live offset may move in one second, in energy. This is the anti-flash guard on the
## live path and it is a hard cap, not a smoothing: however sharply the music jumps, the look
## crosses the whole band in no less than `2 * live_swing / live_rate` seconds - about 6.8 s at
## these values. Together with the two low-pass stages in front of it, nothing periodic in the
## music survives to a pixel, which `music_reactive_layer_test` measures on a 140 BPM track.
##
## 0.065 rather than a rounder 0.08 because the bound it serves is measured, not assumed: at
## 0.08 a quiet-to-loud passage moved the middle of the frame by 0.000623 in its steepest frame
## against the 0.0006 `MAX_FRAME_DELTA` allows. The bound is the owner's - "don't want to cause
## fits" - so the rate came down rather than the bound going up.
@export var live_rate: float = 0.065
## --- timing -------------------------------------------------------------------------------
## Seconds the whole look takes to cross from one track's mood to the next's: a smoothstep,
## so it is monotonic, starts and ends still, and is visible within its first second.
##
## 4.5 rather than 3, because the light band is wide: `torch_calm`..`torch_loud` is x0.70..x1.35
## and the played order puts far-apart moods next to each other on purpose
## (`RadioPlaylist.spread`), so the typical change crosses most of it. A smoothstep's steepest
## frame goes as the swing over the duration, and at 3 s that swing lands at 0.0054 a frame
## against the 0.004 the anti-flash bound allows
## (`music_reactive_layer_test.MAX_CHANGE_FRAME_DELTA`). The bound is the owner's - "don't want
## to cause fits" - so the duration moved instead. A bigger change taking longer is also the
## right shape: still a sunset, over more sky.
@export var crossfade_seconds: float = 4.5
## --- words --------------------------------------------------------------------------------
## Energy below which a track is "brooding", below which "quiet", above which "lively" and
## above which "fierce"; the band between reads "steady".
@export var word_brooding: float = 0.25
@export var word_quiet: float = 0.45
@export var word_lively: float = 0.55
@export var word_fierce: float = 0.8
## Brightness below which a track is "dark" and above which "bright"; in between, no word.
@export var word_dark: float = 0.25
@export var word_bright: float = 0.75


## The shipped levers, loaded once; a default-valued set when the resource is missing.
static func shared() -> MusicMoodLevers:
	if _cached != null:
		return _cached
	if ResourceLoader.exists(PATH):
		_cached = load(PATH) as MusicMoodLevers
	if _cached == null:
		_cached = MusicMoodLevers.new()
	return _cached


## The hue a track pulls toward, in turns: cool for calm, warm for loud, leaned by the seed.
func target_hue(mood: MusicMood) -> float:
	var e := clampf(mood.energy, 0.0, 1.0)
	# Lerp on the short arc through the reds (0.60 -> 1.08 wraps to 0.08), so a middling
	# track lands on a magenta-ish neutral rather than on a green nobody asked for.
	var base := lerpf(cool_hue, warm_hue + 1.0, e)
	return fposmod(base + (clampf(mood.hue_seed, 0.0, 1.0) - 0.5) * 2.0 * hue_seed_spread, 1.0)


## The visual state a mood resolves to, before any crossfade or amount scaling. Silence -
## nothing playing - is the neutral state exactly, not the middle of every band.
##
## `light_theme` no longer changes anything and is kept so the call site reads the same. It used
## to pick a narrower intensity band and cap the torch multiplier at 1, both because an additive
## pool had nowhere to land on a floor that was already near white. There is no such floor now
## (`LightingProfile.unlit_floor`): a paper dungeon is as dark between its lights as a navy one,
## and its lights restore it to paper.
func state_for(mood: MusicMood, _light_theme: bool) -> MusicMoodState:
	var s := MusicMoodState.new()
	if mood == null or mood.is_silent():
		return s
	var e := clampf(mood.energy, 0.0, 1.0)
	var b := clampf(mood.brightness, 0.0, 1.0)
	var extreme := absf(e - 0.5) * 2.0
	s.hue_target = target_hue(mood)
	s.light_hue_pull = light_hue_pull * extreme
	s.hue_rotate = hue_seed_rotate * (1.0 - extreme) * (clampf(mood.hue_seed, 0.0, 1.0) - 0.5) * 2.0
	s.tint = MusicMoodState.unit_tint(s.hue_target, tint_chroma)
	s.saturation = lerpf(saturation_calm, saturation_loud, e)
	s.flicker = lerpf(flicker_calm, flicker_loud, e)
	s.torch = lerpf(torch_calm, torch_loud, e) + (b - 0.5) * 2.0 * brightness_push
	s.radius = lerpf(torch_radius_calm, torch_radius_loud, e)
	s.particles = lerpf(particles_calm, particles_loud, e)
	return s


## "brooding" / "quiet" / "steady" / "lively" / "fierce".
func energy_word(energy: float) -> String:
	if energy < word_brooding:
		return "brooding"
	if energy < word_quiet:
		return "quiet"
	if energy > word_fierce:
		return "fierce"
	if energy > word_lively:
		return "lively"
	return "steady"


## "dark" / "bright", or "" for an unremarkable brightness.
func brightness_word(brightness: float) -> String:
	if brightness < word_dark:
		return "dark"
	if brightness > word_bright:
		return "bright"
	return ""
