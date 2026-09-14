## The music lights of docs §10.2: what the *current track* does to the look of the dungeon,
## and the two things it must never do, which are pulse and light the room.
##
## It used to be a full-frame colour grade, a vignette over the whole screen and a mist laid on
## top of both, and the owner deleted all three in one sentence: "TORCHES SHOULD CAST THE LIGHT,
## THERE SHOULD BE NO OTHER LIGHT OTHER THAN PARTICLE EFFECTS, TORCHES ETC". A grade that dims
## or brightens the frame is a light with nothing in the room casting it, and so is a mist, and
## so is a vignette that takes 45% of the middle of the screen with it. None of them exist now:
## there is no `music_grade` shader include, no `music_tint`/`music_tone` global, no full-rect
## `ColorRect` and no `TextureRect` in this layer at all.
##
## What is left is the state machine and the motes. The track's mood (`MusicMood`, measured
## offline per file) resolves through `MusicMoodLevers` into a `MusicMoodState` - the energy,
## radius, flicker and colour of every flame in the dungeon, plus a mote density - and a track
## change crossfades the whole state over `crossfade_seconds` with a smoothstep: monotonic,
## still at both ends, visible inside its first second. On top of that the live relative
## `energy` (breakdown versus drop) drifts the same state through two seconds-long low-pass
## stages and a hard rate cap. `FloorRoot` and `LightRig` read the result off
## `DungeonLight`'s contract and drive their lights with it, so every pixel the music moves is a
## pixel some torch is standing next to.
##
## Nothing here listens to `EventBus.music_beat`, nothing reads the spectrum, and nothing
## periodic reaches a pixel: the owner's report was "make sure it doesn't pulse - don't want to
## cause fits", and `tests/unit/audio/music_reactive_layer_test.gd` measures it with a synthetic
## 140 BPM track.
##
## The settings slider `music_lights_amount` scales every lever toward the neutral state, so
## at zero the visuals are the theme's own (`MusicMoodState.is_neutral`), and the switch
## `music_lights` turns the whole layer off. The layer is owned by the `Music` autoload and
## only shows itself during a run (mode PLAYLIST or BOSS between `run_started` and
## `run_ended`): the menus have their own art. It is a light effect and nothing else - it
## never moves a hitbox and never covers a tell.
class_name MusicReactiveLayer
extends CanvasLayer

## Above the world (0) and below the HUD (10) and the overlays (20) of `game.tscn`. Only the
## motes are drawn on it now.
const LAYER := 5
## Settings keys: the switch and the amount slider (0..1).
const SETTING_ON := "music_lights"
const SETTING_AMOUNT := "music_lights_amount"

var tuning: MusicAnalysis = null
var levers: MusicMoodLevers = null

var _motes: MusicMotes = null
## The two low-pass stages the energy goes through.
var _smooth_a: float = 0.5
var _smooth_b: float = 0.5
## The live envelope actually applied: `_smooth_b` behind a hard rate cap, 0..1. This is the
## "what is the track doing right now" input, as opposed to `_mood`'s "which track is this".
var _live: float = 0.5
var _active: bool = false
## The mood crossfade: from, to, and seconds into it.
var _mood: MusicMood = MusicMood.silent()
var _fade_from: MusicMoodState = MusicMoodState.neutral()
var _fade_to: MusicMoodState = MusicMoodState.neutral()
var _fade_t: float = 0.0
## The blended mood state before the amount and the switch...
var _mood_state: MusicMoodState = MusicMoodState.neutral()
## ...and what is actually applied this frame.
var _applied: MusicMoodState = MusicMoodState.neutral()
var _biome: StringName = &""


func _init() -> void:
	layer = LAYER
	name = "MusicReactiveLayer"


## Connecting here rather than in `_ready()` keeps the feed alive across a re-parent, and
## `_exit_tree()` takes it down so a freed layer never leaves a callable on the bus.
func _enter_tree() -> void:
	if not EventBus.palette_changed.is_connected(_on_palette_changed):
		EventBus.palette_changed.connect(_on_palette_changed)
	if not EventBus.floor_started.is_connected(_on_floor_started):
		EventBus.floor_started.connect(_on_floor_started)
	if not EventBus.run_started.is_connected(_on_run_started):
		EventBus.run_started.connect(_on_run_started)
	if not EventBus.run_ended.is_connected(_on_run_ended):
		EventBus.run_ended.connect(_on_run_ended)


func _exit_tree() -> void:
	if EventBus.palette_changed.is_connected(_on_palette_changed):
		EventBus.palette_changed.disconnect(_on_palette_changed)
	if EventBus.floor_started.is_connected(_on_floor_started):
		EventBus.floor_started.disconnect(_on_floor_started)
	if EventBus.run_started.is_connected(_on_run_started):
		EventBus.run_started.disconnect(_on_run_started)
	if EventBus.run_ended.is_connected(_on_run_ended):
		EventBus.run_ended.disconnect(_on_run_ended)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if tuning == null:
		tuning = MusicAnalysis.load_default()
	if levers == null:
		levers = MusicMoodLevers.shared()
	_motes = MusicMotes.new()
	_motes.name = "Motes"
	add_child(_motes)
	_motes.set_capacity(levers.particles_max)
	# The docs above say the motes belong to a run and the menus have their own art. That was
	# written and never wired, so they drifted over the title and the summary after a quit.
	_motes.visible = RunManager.is_run_active()
	_apply()


func _process(delta: float) -> void:
	step(delta, Music.energy)


## One frame of the light, fed `energy` (0..1). Public so a test can drive it with a
## synthetic track at a fixed rate; `_process` feeds it the live `Music.energy`.
func step(delta: float, energy: float) -> void:
	var on := _active and enabled()
	# Stage one and two: the same first-order low-pass twice, so a periodic component at the
	# beat is attenuated by the square of what one stage would do.
	var tau := maxf(tuning.light_smoothing, 0.001)
	var k := 1.0 - exp(-delta / tau)
	_smooth_a += (clampf(energy, 0.0, 1.0) - _smooth_a) * k
	_smooth_b += (_smooth_a - _smooth_b) * k
	# The live envelope: the same twice-smoothed loudness, behind a hard cap on how far it may
	# travel in a second (`MusicMoodLevers.live_rate`). The cap is the anti-flash guarantee on
	# this path - it does not smooth a spike, it makes one impossible to follow.
	var step_limit := maxf(levers.live_rate, 0.0) * delta
	_live += clampf(_smooth_b - _live, -step_limit, step_limit)
	# The mood crossfade: a smoothstep from the state the last track left to where this track
	# is *right now* - its own measured mood, offset by the live envelope within `live_swing`.
	# So a track change still crosses over seconds, and inside a track the look goes on moving.
	_fade_to = _state_for(_breathing_mood())
	var seconds := maxf(levers.crossfade_seconds, 0.001)
	_fade_t = minf(_fade_t + delta, seconds)
	var eased := smoothstep(0.0, 1.0, _fade_t / seconds)
	_mood_state = _fade_from.blended(_fade_to, eased)
	_applied = _mood_state.scaled(amount()) if on else MusicMoodState.neutral()
	if _motes != null:
		_motes.step(delta)
	_apply()


## True while the player has the music lights switched on (settings key `music_lights`).
static func enabled() -> bool:
	return bool(GameState.settings.get(SETTING_ON, true))


## How far the music may move the look, 0..1 (settings key `music_lights_amount`, default 1).
static func amount() -> float:
	return clampf(float(GameState.settings.get(SETTING_AMOUNT, 1.0)), 0.0, 1.0)


## Shows or hides the effect. `MusicManager` turns it on for a run and off again at the end,
## so menus and the summary screen keep their own art.
func set_active(on: bool) -> void:
	if on and not _active and tuning != null:
		# Snap rather than ramp, once, on the way in: a floor starts with the light the music
		# is already at, and a rendered capture taken a second into a run shows the dungeon
		# the player would be looking at. Staying active (the boss track taking over) snaps
		# nothing: that would be a step in brightness mid-run.
		_smooth_a = clampf(Music.energy, 0.0, 1.0)
		_smooth_b = _smooth_a
		_live = _smooth_b
		# The look the envelope has *just* been snapped to, not the one it had before: the two
		# are a whole `live_swing` apart when a run opens on a quiet passage, and resolving the
		# crossfade target after the snap is what stops the first processed frame being a step.
		_fade_to = _state_for(_breathing_mood())
		_fade_from = _fade_to
		_fade_t = levers.crossfade_seconds if levers != null else 0.0
		# ...and the state the lights are driven from arrives with it, rather than one frame
		# later. Without this the frame the layer goes live steps from the theme's own fire to
		# the track's, which is precisely a flash.
		_mood_state = _fade_to
		_active = true
		_applied = _mood_state.scaled(amount()) if enabled() else MusicMoodState.neutral()
		_apply()
	_active = on


func is_active() -> bool:
	return _active


## The track changed: crossfade the look from wherever it is now to `mood`'s. Called by
## `MusicManager` on every track start; a mood equal to the current one restarts nothing.
func set_mood(mood: MusicMood) -> void:
	_mood = mood if mood != null else MusicMood.silent()
	if levers == null:
		levers = MusicMoodLevers.shared()
	var next := _state_for(_breathing_mood())
	_fade_from = _mood_state
	_fade_to = next
	_fade_t = 0.0
	if not _active:
		# Nothing is showing: arrive already there, so the run opens in this track's look.
		_fade_from = next
		_fade_t = levers.crossfade_seconds


## The mood the layer is showing or crossfading toward.
func mood() -> MusicMood:
	return _mood


## The live envelope, 0..1: how loud the track is *right now* against its own baseline, after
## two low-pass stages and the rate cap. 0.5 is "as loud as this track usually is".
func live_envelope() -> float:
	return _live


## Places the live envelope at `value` outright, skipping the rate cap. For *captures only*:
## the headless audio driver produces no spectrum, so a rendered strip of one track's passages
## has to be told where in the track it is, and walking there at 0.065 of the energy a second
## would spend a minute of the scenario's budget travelling between six photographs. What the
## walk looks like is measured in `music_reactive_layer_test`, frame by frame, against the
## flash bound; this is only how the camera gets to each place.
func place_envelope(value: float) -> void:
	_live = clampf(value, 0.0, 1.0)
	_smooth_a = _live
	_smooth_b = _live


## The track's own mood with the live envelope folded in: the base the offline table measured,
## moved by up to `MusicMoodLevers.live_swing` toward calm or loud by what the track is doing
## now. Silence stays silent - a neutral state has nothing to breathe with.
func _breathing_mood() -> MusicMood:
	if _mood == null or _mood.is_silent():
		return MusicMood.silent()
	var swing := levers.live_swing if levers != null else 0.0
	return _mood.at_energy(_mood.energy + (_live - 0.5) * 2.0 * swing)


## The state actually driving the dungeon's lights this frame: the crossfaded mood, scaled by
## the amount, or neutral while the layer is off. `DungeonLight`'s contract reads it, and
## `FloorRoot` and `LightRig` read that.
func state() -> MusicMoodState:
	return _applied


## Where the crossfade is heading (before amount scaling).
func target_state() -> MusicMoodState:
	return _fade_to


## 0..1 through the current mood crossfade; 1 once it has settled.
func fade_progress() -> float:
	if levers == null:
		return 1.0
	return clampf(_fade_t / maxf(levers.crossfade_seconds, 0.001), 0.0, 1.0)


## Which biome's motes to draw (`FloorRoot` reports it through `floor_started`).
func set_biome(biome: StringName) -> void:
	_biome = biome
	if _motes != null:
		_motes.set_biome(biome)


func motes() -> MusicMotes:
	return _motes


## What the mood multiplies every lit pixel in the dungeon by this frame: the light the torches,
## lanterns, emitters and the player's own pool put on a surface (`MusicMoodState`). This is the
## per-frame quantity the no-pulsing tests measure, because with the grade and the vignette gone
## it is the only one the music can move at all.
func luminance_factor() -> float:
	return _applied.luminance_factor()


func _on_palette_changed(_palette: ThemePalette) -> void:
	_fade_to = _state_for(_mood)
	_apply()


func _on_floor_started(_index: int) -> void:
	var data: FloorData = RunManager.floor_data
	if data != null:
		set_biome(data.biome)


## The motes are dust in a dungeon, so they belong to a run and not to the title or the run
## summary behind it.
func _on_run_started(_run_seed: int) -> void:
	if _motes != null:
		_motes.visible = true


func _on_run_ended(_victory: bool) -> void:
	if _motes != null:
		_motes.visible = false


func _state_for(mood: MusicMood) -> MusicMoodState:
	if levers == null:
		levers = MusicMoodLevers.shared()
	return levers.state_for(mood, _light_theme())


static func _light_theme() -> bool:
	return Desktop.palette != null and Desktop.palette.is_light


func _apply() -> void:
	_apply_motes()


func _apply_motes() -> void:
	if _motes == null:
		return
	var reduced := Accessibility.reduce_motion()
	var count := int(round(float(_motes.capacity()) * _applied.particles))
	if reduced:
		count = mini(count, levers.particles_reduced_motion)
	_motes.set_shown(count)
	_motes.drifting = not reduced
	_motes.color = _mote_color()


## Embers burn in the theme's fire, void motes in its magic, snow is white, dust is a warm
## grey - each one graded as a *light* is, because a mote is a spark and not a surface. The
## motes are the "particle effects" half of the owner's rule, and the only thing on this layer
## that reaches a pixel at all.
func _mote_color() -> Color:
	var pal := Desktop.palette
	var base := Color(0.85, 0.80, 0.70)
	match _motes.kind:
		MusicMotes.Kind.EMBER:
			base = pal.get_color(&"heat") if pal != null else Color(1.0, 0.55, 0.2)
		MusicMotes.Kind.SNOW:
			base = Color(0.95, 0.97, 1.0)
		MusicMotes.Kind.MOTE:
			base = pal.get_color(&"magic") if pal != null else Color(0.7, 0.5, 1.0)
		_:
			if pal != null and pal.is_light:
				base = Color(0.35, 0.32, 0.28)
	return _applied.light_color(base)
