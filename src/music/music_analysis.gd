## Tunables for the music analysis chain and the music lights (docs §10.2).
##
## Why the numbers live here rather than in `MusicManager`: the first version measured
## *absolute* loudness (a 30 s rolling RMS mapped onto -42..-8 dBFS) and every mastered radio
## track landed in the same place. Measured over five bundled tracks with ffmpeg, the mean
## energy was 0.713 / 0.712 / 0.717 / 0.715 / 0.713 - a spread of 0.005 across wildly different
## music - so `energy` was a constant 0.71 in practice and the generation lever it feeds moved
## enemy counts by less than a percent between tracks. It was alive in the code and dead in the
## game.
##
## The measure is *relative* now: a short loudness average against the track's own rolling
## baseline, in dB, so `energy` says where in the music you are (breakdown vs. drop) rather
## than how loud the mastering engineer left it. The same five tracks then swing 0.10..0.81
## with a per-track standard deviation of 0.09-0.19, which is a lever a floor can be built on.
class_name MusicAnalysis
extends Resource

const PATH := "res://data/music/music_analysis.tres"

## Seconds between energy samples. The bands themselves are read every frame.
@export var sample_interval: float = 0.05
## "Now" window: the loudness the player is currently hearing. Also the measure's warm-up -
## before this much audio has been heard the short and long means are the same estimator and
## `energy` sits at 0.5 - so it is kept short enough that the first floor of a run still gets a
## real reading.
@export var short_window: float = 1.5
## Baseline window the short one is compared against - roughly a verse and a chorus.
@export var long_window: float = 40.0
## dB above/below the baseline that maps to energy 1.0 / 0.0. Smaller = more swing.
@export var relative_span_db: float = 3.0
## Below this short-window level the track counts as silent and energy reads 0.
@export var silence_floor_db: float = -60.0
## Spectrum readings are only trusted once the active player is at least this loud, so a
## crossfade or a duck does not read as a breakdown.
@export var analysis_min_gain: float = 0.5
## Onset detector (see `BeatDetector`).
@export var beat_threshold: float = 1.4
@export var beat_min_interval: float = 0.25
@export var beat_window: float = 1.0
## --- music lights (settings key `music_lights`) --------------------------------------------
## Time constant (seconds) of each of the two low-pass stages the energy goes through before
## it may move the light. Two seconds twice attenuates a 140 BPM beat by about 1/900; a drop
## or a breakdown, which lasts tens of seconds, comes through whole.
## The vignette these three used to drive is gone: it dimmed the whole frame, middle included,
## with nothing in the room casting the dimming, and the owner's ruling took it out with the rest
## of the full-frame effects. The smoothing stays because the live envelope still runs through
## it, and the envelope now reaches the torches (`MusicMoodLevers.torch_calm`/`_loud`) instead.
@export var light_smoothing: float = 2.0


## The tuned profile from `data/music/`, or a default-valued one when it is missing.
static func load_default() -> MusicAnalysis:
	if ResourceLoader.exists(PATH):
		var res := load(PATH) as MusicAnalysis
		if res != null:
			return res
	return MusicAnalysis.new()
