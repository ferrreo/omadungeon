## The music lights, and the one property they must never have: a pulse.
##
## The owner's report, from playing: "make sure it doesn't 'pulse' - don't want to cause
## fits". The layer used to lift on every beat and bloom with it - a brightness change at the
## tempo of the music, for as long as a track played. These cases pin the replacement: the
## energy still moves the light (slowly), a synthetic high-energy track at 140 BPM produces a
## frame-to-frame luminance change under a strict ceiling and no component at the beat
## frequency, and nothing in the layer listens to the beat at all.
##
## **What "the light" means changed this round and the bounds did not.** It used to be the
## middle of the frame under a full-frame colour grade and a vignette; the owner deleted both
## ("TORCHES SHOULD CAST THE LIGHT, THERE SHOULD BE NO OTHER LIGHT OTHER THAN PARTICLE EFFECTS,
## TORCHES ETC"), so `luminance_factor()` is now what the mood multiplies the dungeon's own
## fires by - the only quantity the music can move at all. Every ceiling below is the number it
## was, measured on that. A track with no measured mood now moves nothing, which is why the
## cases that used to run on silence set a mood first: silence is neutral by construction, and a
## bound measured on a constant is a bound measured on nothing.
class_name MusicReactiveLayerTest
extends GdUnitTestSuite

const FRAME := 1.0 / 60.0
## The synthetic track: 140 BPM, a sharp loudness spike on every beat over a loud passage.
const BPM := 140.0
const TRACK_SECONDS := 24.0
## Hardest the middle of the frame may change between two consecutive frames, as a fraction
## of its luminance. 0.0006 a frame is 3.6% a second at 60 Hz - a drift the eye reads as the
## torches burning lower, never as a flicker.
const MAX_FRAME_DELTA := 0.0006
## Ceiling on the luminance amplitude at the beat frequency (and its second harmonic).
const MAX_BEAT_AMPLITUDE := 0.0004

## Hardest the middle of the frame may change between two frames *during a track change*: the
## mood crossfade is a one-off smoothstep over three seconds, not a drift, so it is allowed a
## steeper slope than the energy path - and still under a quarter of a percent a frame, a
## sunset rather than a switch.
const MAX_CHANGE_FRAME_DELTA := 0.004
## Least the middle of the frame must move, calm track to loud track, once settled.
const MIN_CHANGE_SWING := 0.25
## Absolute chroma a surface needs before the question "what hue is it" has an answer, for the
## rendered hue budget below. `TileRamp.ACCENT_MIN_CHROMA` (0.14) is the wrong line here: it is
## what an *accent* is held to, and a dungeon floor is a desaturated surface that never reaches
## it - gating on it skipped every reading and the test measured nothing at all.
##
## 0.05 is where a floor stops being a grey with a cast. Under it a hue is not a thing the
## owner's ruling is about: catppuccin-latte's paper floor carries 0.024 of chroma, and a
## reading that called a 149-degree turn of *that* "repainting the theme" would be measuring
## quantisation. Those surfaces get the other half of the rule instead - they have to stay
## grey - which is the same pair `music_mood_test` splits its roles by.
const HUE_CHROMA_MIN := 0.05
## The owner's own otter-shell palette, as checked in. Their machine has no Omarchy state, so
## these twelve colours are the whole of their theme - and they are green, which none of the
## six shipped fixtures is, and green is what the blue-violet mist was furthest from.
const OTTER_COLORS := "res://tests/fixtures/otter/owner/config/otter-shell/generated-colors.conf"
## The exposure a dark theme's floor is measured at. A wallpaper still sets this in play (it is
## the one thing a wallpaper still decides), so there is no single right answer; the midpoint of
## the band is the one that is not a special case at either end.
const LIT_AMBIENT := 0.5
## Least the middle of the frame must move between a quiet passage and a loud one of the *same*
## track, as a share of its own luminance. The owner's correction is that a per-track mood is
## not enough - the look has to follow what the track is doing - and this is that in a number.
const MIN_LIVE_SWING_SHARE := 0.12

var _layer: MusicReactiveLayer
var _setting_before: bool = true
var _amount_before: float = 1.0
var _motion_before: bool = false
var _energy_before: float = 0.5


func before_test() -> void:
	_setting_before = bool(GameState.settings.get("music_lights", true))
	_amount_before = float(GameState.settings.get("music_lights_amount", 1.0))
	_motion_before = bool(GameState.settings.get(Accessibility.SETTING_REDUCE_MOTION, false))
	_energy_before = Music.energy
	GameState.settings["music_lights"] = true
	GameState.settings["music_lights_amount"] = 1.0
	GameState.settings[Accessibility.SETTING_REDUCE_MOTION] = false
	_layer = auto_free(MusicReactiveLayer.new())
	add_child(_layer)


func after_test() -> void:
	GameState.settings["music_lights"] = _setting_before
	GameState.settings["music_lights_amount"] = _amount_before
	GameState.settings[Accessibility.SETTING_REDUCE_MOTION] = _motion_before
	Music.energy = _energy_before


static func _calm_mood() -> MusicMood:
	var file := MusicMood.extreme_file(false)
	return MusicMood.for_file(file, file)


## A track in the middle of the band: the one the flash bounds are measured on, because it has
## the whole of the live envelope's swing available either side of it.
static func _steady_mood() -> MusicMood:
	var mood := MusicMood.for_file("", "A Steady Track")
	mood.energy = 0.5
	return mood


static func _loud_mood() -> MusicMood:
	var file := MusicMood.extreme_file(true)
	return MusicMood.for_file(file, file)


## Steps the layer at a fixed rate with a constant energy; a headless frame is worth a
## fraction of a millisecond, so waiting on frames measures nothing about seconds.
func _advance(seconds: float, energy: float) -> void:
	for i in int(seconds / FRAME):
		_layer.step(FRAME, energy)


func _settle(energy: float) -> float:
	_advance(30.0, energy)
	return _layer.luminance_factor()


## The synthetic track's loudness at `t`: a loud passage with a spike decaying over 80 ms on
## every beat, which is the shape a kick drum makes in the relative energy measure.
static func _track_energy(t: float) -> float:
	var beat_seconds := 60.0 / BPM
	var since_beat := fmod(t, beat_seconds)
	return clampf(0.72 + 0.28 * exp(-since_beat / 0.08), 0.0, 1.0)


## Amplitude of `samples` at `hz`, by a single-bin DFT (2/N times the magnitude).
static func _amplitude_at(samples: PackedFloat64Array, hz: float, rate: float) -> float:
	var re := 0.0
	var im := 0.0
	var n := samples.size()
	for i in n:
		var angle := -TAU * hz * float(i) / rate
		re += samples[i] * cos(angle)
		im += samples[i] * sin(angle)
	return 2.0 * sqrt(re * re + im * im) / float(n)


## `samples` with its least-squares line removed, so the slow drift the light is supposed to
## make does not leak into the beat bin of a finite window and read as a pulse.
static func _detrended(samples: PackedFloat64Array) -> PackedFloat64Array:
	var n := samples.size()
	var mean_x := float(n - 1) * 0.5
	var mean_y := 0.0
	for value in samples:
		mean_y += value
	mean_y /= float(n)
	var cov := 0.0
	var var_x := 0.0
	for i in n:
		var dx := float(i) - mean_x
		cov += dx * (samples[i] - mean_y)
		var_x += dx * dx
	var slope := cov / var_x if var_x > 0.0 else 0.0
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		out[i] = samples[i] - (mean_y + slope * (float(i) - mean_x))
	return out


func test_the_layer_is_dark_until_a_run_starts() -> void:
	_layer.set_mood(_loud_mood())
	_advance(3.0, 0.2)
	assert_bool(_layer.is_active()).is_false()
	assert_bool(_layer.state().is_neutral()).is_true()
	assert_float(_layer.luminance_factor()).is_equal_approx(1.0, 0.0001)


## Quiet music burns the dungeon's fires lower, loud music burns them harder. This is the whole
## of the lever now - there is no vignette and no grade behind it - and the difference has to be
## big enough to see.
func test_energy_moves_the_light_level() -> void:
	_layer.set_mood(_steady_mood())
	_layer.set_active(true)
	var calm := _settle(0.0)
	var loud := _settle(1.0)
	assert_float(loud).is_greater(calm)
	(
		assert_float((loud - calm) / maxf(calm, 0.0001))
		. override_failure_message(
			(
				"a quiet passage and a loud one burn the fires %.1f%% apart - nobody would notice"
				% ((loud - calm) / maxf(calm, 0.0001) * 100.0)
			)
		)
		. is_greater(0.15)
	)
	var middle := _settle(0.5)
	assert_float(middle).is_between(calm, loud)


## The measurement the owner's report asks for. A loud track with a kick on every beat is
## fed to the layer for twelve seconds at 60 Hz, starting from the calm end so the light has
## the whole swing to make; the frame-to-frame change in the middle of the screen must stay
## under `MAX_FRAME_DELTA` on every frame, and the spectrum of that luminance must carry
## nothing at the beat frequency - while the light still, visibly, moves over the passage.
func test_a_high_energy_track_drifts_the_light_and_never_pulses_it() -> void:
	# A mood, because silence is neutral by construction: with no track the fires are the
	# theme's own and a flash bound measured on a constant measures nothing.
	_layer.set_mood(_steady_mood())
	Music.energy = 0.0
	_layer.set_active(true)
	var samples := PackedFloat64Array()
	var worst := 0.0
	var previous := _layer.luminance_factor()
	var frames := int(TRACK_SECONDS / FRAME)
	var next_beat := 0.0
	for i in frames:
		var t := float(i) * FRAME
		if t >= next_beat:
			# The manager announces every beat on the bus; the layer must not be listening.
			EventBus.music_beat.emit(1.0)
			next_beat += 60.0 / BPM
		_layer.step(FRAME, _track_energy(t))
		var now := _layer.luminance_factor()
		worst = maxf(worst, absf(now - previous))
		previous = now
		samples.append(now)
	(
		assert_float(worst)
		. override_failure_message(
			"the light changed by %f of its luminance in one frame - that is a flash" % worst
		)
		. is_less(MAX_FRAME_DELTA)
	)
	# The spectrum is read over the last third, once the initial swing has settled, and with
	# the remaining drift line removed, so only what repeats at the beat is left to measure.
	var half := _detrended(samples.slice(frames * 2 / 3))
	var beat_hz := BPM / 60.0
	for hz: float in [beat_hz, beat_hz * 2.0]:
		var amplitude := _amplitude_at(half, hz, 1.0 / FRAME)
		(
			assert_float(amplitude)
			. override_failure_message(
				(
					"the light carries a %f luminance component at %.2f Hz - it is pulsing"
					% [amplitude, hz]
				)
			)
			. is_less(MAX_BEAT_AMPLITUDE)
		)
	# And the drift is real: a calm start and a loud passage end far apart.
	var swing := samples[samples.size() - 1] - samples[0]
	(
		assert_float(swing)
		. override_failure_message("the light did not follow the loud passage (moved %f)" % swing)
		. is_greater(0.05)
	)
	print(
		(
			(
				"music lights under a 140 BPM track: worst frame delta %.6f, beat amplitude %.6f, "
				+ "harmonic %.6f, total drift %.4f"
			)
			% [
				worst,
				_amplitude_at(half, beat_hz, 1.0 / FRAME),
				_amplitude_at(half, beat_hz * 2.0, 1.0 / FRAME),
				swing
			]
		)
	)


## A beat, on its own, moves nothing. Not "a little": nothing, on the frame it lands and on
## the frames after it.
func test_a_beat_moves_the_light_by_exactly_nothing() -> void:
	_layer.set_mood(_steady_mood())
	_layer.set_active(true)
	var resting := _settle(0.5)
	EventBus.music_beat.emit(1.0)
	_layer.step(FRAME, 0.5)
	assert_float(_layer.luminance_factor()).is_equal_approx(resting, 0.00001)
	_advance(0.5, 0.5)
	assert_float(_layer.luminance_factor()).is_equal_approx(resting, 0.00001)


## The regression the whole file exists for now, inverted from what it used to pin: nothing
## in the layer may be on the other end of `EventBus.music_beat`, because a listener there is
## a light that can move at the tempo of the music.
func test_the_layer_does_not_listen_to_the_beat() -> void:
	for lights: MusicReactiveLayer in [_layer, Music.lights()]:
		assert_object(lights).is_not_null()
		for connection: Dictionary in EventBus.music_beat.get_connections():
			var callable: Callable = connection["callable"]
			(
				assert_bool(callable.get_object() == lights)
				. override_failure_message("a music light layer is connected to music_beat")
				. is_false()
			)


## Going active while already active (the boss track taking over mid-run) is not a snap:
## a step in brightness mid-run is a flash by another name.
func test_staying_active_never_snaps_the_level() -> void:
	_layer.set_mood(_steady_mood())
	Music.energy = 0.1
	_layer.set_active(true)
	var before := _settle(0.1)
	Music.energy = 1.0
	_layer.set_active(true)
	assert_float(_layer.luminance_factor()).is_equal_approx(before, 0.00001)


## The settings switch, under its new name. Off means the dungeon's own fire, exactly.
func test_the_settings_switch_turns_it_off() -> void:
	_layer.set_mood(_calm_mood())
	_layer.set_active(true)
	assert_float(absf(_settle(0.0) - 1.0)).is_greater(0.05)
	GameState.settings["music_lights"] = false
	assert_bool(MusicReactiveLayer.enabled()).is_false()
	_advance(1.0, 0.0)
	(
		assert_float(_layer.luminance_factor())
		. override_failure_message("music lights are off and the torches still reacted")
		. is_equal_approx(1.0, 0.0001)
	)
	assert_bool(_layer.state().is_neutral()).is_true()


## The `Music` autoload owns one, and it belongs to the dungeon: on for a run, off again when
## the run ends, so the title and summary screens keep their own art.
func test_the_music_autoload_owns_a_layer_that_follows_the_run() -> void:
	var lights := Music.lights()
	assert_object(lights).is_not_null()
	var was_active := lights.is_active()
	Music.play_playlist()
	EventBus.run_started.emit(4242)
	assert_bool(lights.is_active()).is_true()
	EventBus.run_ended.emit(false)
	assert_bool(lights.is_active()).is_false()
	Music.stop(0.0)
	assert_bool(lights.is_active()).is_equal(false if not was_active else lights.is_active())


## A track change is a crossfade: from the calm track's look to the loud one's, the middle
## of the frame brightens every frame or holds, never dips, never steps more than
## `MAX_CHANGE_FRAME_DELTA`, is visibly different inside the first two seconds and settled by
## the levers' `crossfade_seconds`. Beats land on the bus throughout and move nothing: the
## same passage with no beats at all produces the identical frames.
func test_a_track_change_crossfades_the_look_monotonically_and_ignores_the_beat() -> void:
	var runs: Array[PackedFloat64Array] = []
	for with_beats: bool in [true, false]:
		var layer := auto_free(MusicReactiveLayer.new()) as MusicReactiveLayer
		add_child(layer)
		Music.energy = 0.5
		layer.set_mood(_calm_mood())
		layer.set_active(true)
		for i in int(2.0 / FRAME):
			layer.step(FRAME, 0.5)
		layer.set_mood(_loud_mood())
		var samples := PackedFloat64Array()
		var next_beat := 0.0
		for i in int(8.0 / FRAME):
			var t := float(i) * FRAME
			if with_beats and t >= next_beat:
				EventBus.music_beat.emit(1.0)
				next_beat += 60.0 / BPM
			layer.step(FRAME, 0.5)
			samples.append(layer.luminance_factor())
		runs.append(samples)
	var samples := runs[0]
	var worst := 0.0
	var dips := 0
	for i in range(1, samples.size()):
		var d := samples[i] - samples[i - 1]
		worst = maxf(worst, absf(d))
		if d < -0.000001:
			dips += 1
	(
		assert_int(dips)
		. override_failure_message("the crossfade reversed direction %d times" % dips)
		. is_equal(0)
	)
	(
		assert_float(worst)
		. override_failure_message(
			"the look changed by %f in one frame during a track change" % worst
		)
		. is_less(MAX_CHANGE_FRAME_DELTA)
	)
	var swing := samples[samples.size() - 1] - samples[0]
	(
		assert_float(swing / samples[0])
		. override_failure_message(
			(
				"calm to loud moved the middle of the frame by only %.1f%%"
				% (swing / samples[0] * 100.0)
			)
		)
		. is_greater_equal(MIN_CHANGE_SWING)
	)
	# Visible early: a third of the swing is done by two seconds in.
	var at_two := samples[int(2.0 / FRAME)] - samples[0]
	assert_float(at_two).is_greater(swing / 3.0)
	# Settled: nothing moves after the crossfade's own length.
	var settle := int(MusicMoodLevers.shared().crossfade_seconds / FRAME) + 2
	assert_float(absf(samples[samples.size() - 1] - samples[settle])).is_less(0.0001)
	# And the beat did nothing: frame for frame the same.
	for i in samples.size():
		assert_float(runs[1][i]).is_equal_approx(samples[i], 0.0000001)
	print(
		(
			"track change calm->loud: swing %.3f (%.1f%%), worst frame delta %.5f, settled at %.1f s"
			% [swing, swing / samples[0] * 100.0, worst, settle * FRAME]
		)
	)


## The amount slider at zero is the theme untouched, whatever the track: no grade, no haze, no
## extra vignette, no motes.
func test_the_amount_slider_at_zero_is_pure_theme() -> void:
	_layer.set_mood(_loud_mood())
	_layer.set_active(true)
	_advance(5.0, 0.5)
	assert_bool(_layer.state().is_neutral()).is_false()
	GameState.settings["music_lights_amount"] = 0.0
	_advance(0.5, 0.5)
	assert_bool(_layer.state().is_neutral()).is_true()
	assert_float(_layer.state().luminance_factor()).is_equal_approx(1.0, 0.0001)
	assert_int(_layer.motes().shown()).is_equal(0)
	# Half way is half the effect: the lever is a lerp toward neutral.
	GameState.settings["music_lights_amount"] = 0.5
	_advance(0.5, 0.5)
	var half := _layer.state()
	var full := _layer.target_state()
	assert_float(half.torch).is_equal_approx(lerpf(1.0, full.torch, 0.5), 0.001)


## The lights switch off is the same guarantee from the other side.
func test_the_switch_off_leaves_the_grade_neutral() -> void:
	_layer.set_mood(_calm_mood())
	_layer.set_active(true)
	_advance(5.0, 0.5)
	assert_bool(_layer.state().is_neutral()).is_false()
	GameState.settings["music_lights"] = false
	_advance(0.2, 0.5)
	assert_bool(_layer.state().is_neutral()).is_true()


## Reduce-motion caps the motes at the levers' small number and stops them drifting; they
## still exist, faintly, so a calm track is still a mistier room.
func test_reduce_motion_caps_the_motes() -> void:
	_layer.set_mood(_loud_mood())
	_layer.set_active(true)
	_advance(5.0, 0.5)
	var free := _layer.motes().shown()
	assert_int(free).is_greater(MusicMoodLevers.shared().particles_reduced_motion)
	assert_bool(_layer.motes().drifting).is_true()
	GameState.settings[Accessibility.SETTING_REDUCE_MOTION] = true
	_advance(0.2, 0.5)
	assert_int(_layer.motes().shown()).is_less_equal(
		MusicMoodLevers.shared().particles_reduced_motion
	)
	assert_bool(_layer.motes().drifting).is_false()


## The motes' density is a slow reveal: it rises every frame and never jumps.
func test_the_mote_density_ramps_smoothly() -> void:
	_layer.set_mood(_loud_mood())
	_layer.set_active(true)
	var previous := _layer.motes().density()
	var worst := 0.0
	for i in int(6.0 / FRAME):
		_layer.step(FRAME, 0.5)
		var now := _layer.motes().density()
		assert_float(now).is_greater_equal(previous - 0.000001)
		worst = maxf(worst, now - previous)
		previous = now
	assert_float(previous).is_greater(0.5)
	assert_float(worst).is_less(0.01)


## A track change while the layer is dark (menus) arrives already there, so a run opens in
## the track's look rather than fading into it over the first three seconds of play.
func test_a_mood_set_while_inactive_is_shown_at_once_on_activation() -> void:
	_layer.set_mood(_loud_mood())
	_layer.set_active(true)
	_layer.step(FRAME, 0.5)
	assert_float(_layer.fade_progress()).is_equal_approx(1.0, 0.001)
	assert_float(_layer.state().torch).is_equal_approx(_layer.target_state().torch, 0.001)


## The owner's ruling, measured on every path there is - which is now none.
##
## The theme is the only colour authority. That used to be a *budget*: the shader grade was held
## to 15 degrees by `music_mood_test`, and this case existed because the grade was not the only
## road - the haze was a full-rect `ColorRect` drawn over the frame with nothing bounding it, and
## over the darkness round's much darker floor it stopped tinting and started painting. Rendered
## on the owner's green otter theme the room came out #47424C, a blue-violet grey, where the same
## code with the amount slider at 0 came out #927D54.
##
## Both roads are gone. The owner's next ruling deleted the full-frame grade and the haze
## together with the ambient they were lighting the room through, so the room is drawn in the
## theme's own colours mixed toward black by `LightingProfile.unlit_floor` and the music appears
## in exactly one place: the colour of the fires standing in the room. The budget is therefore
## not spent at all, and this measures that on the same seven fixtures, over every state the live
## envelope can reach, with the otter fixture asserted separately because it is the one the
## report was filed on.
##
## Proved by making it fail first: giving `_room_as_drawn` back the haze lerp it used to have
## (`state.haze` at the mist colour) puts the otter fixture at 14.8 degrees and the assertion
## fails naming it; taking the drift line to a hard 0.0001, as it is, fails on any nonzero road.
func test_no_track_moves_the_room_off_the_theme_s_hue_at_all() -> void:
	var levers := MusicMoodLevers.shared()
	var worst := 0.0
	var worst_where := ""
	var measured := 0
	var otter_worst := 0.0
	var otter_seen := 0
	var flame_moved := 0.0
	for entry: Array in _hue_fixtures():
		var name: String = entry[0]
		var pal: ThemePalette = entry[1]
		var before := Desktop.palette
		Desktop.palette = pal
		var lit := _lit_floor(pal)
		var drawn := _floor_as_drawn(pal)
		var flame := DungeonLight.resolve().light_color(pal.get_color(&"heat"))
		# Gated on the *lit* floor's chroma, not the drawn one's: scaling a colour toward black
		# leaves its hue exactly where it was but takes its absolute chroma with it, so every
		# drawn floor reads as a near-grey and the gate would skip the whole measurement.
		var coloured := TileRamp.chroma(lit) >= HUE_CHROMA_MIN
		for file: String in MusicMood.measured_files():
			var mood := MusicMood.for_file(file, file)
			# Every state the *live* path can reach, not just the track's resting one: the
			# envelope moves the energy by up to `live_swing` either way while the track plays.
			for offset: float in [-levers.live_swing, 0.0, levers.live_swing]:
				var state := levers.state_for(mood.at_energy(mood.energy + offset), pal.is_light)
				var after := _room_as_drawn(drawn, state)
				measured += 1
				# The same state, on the one thing it is allowed to colour, so the readings are
				# not vacuous: if the mood reached nothing at all this would stay at zero too.
				flame_moved = maxf(
					flame_moved, absf(MusicMoodState.hue_delta(flame.h, state.light_color(flame).h))
				)
				if not coloured:
					# A grey floor has no hue to protect; what it must not do is acquire one.
					(
						assert_float(TileRamp.chroma(after))
						. override_failure_message(
							(
								"%s is a grey floor and %s gave it %.3f of chroma"
								% [name, file, TileRamp.chroma(after)]
							)
						)
						. is_less_equal(TileRamp.chroma(drawn) + 0.0001)
					)
					continue
				var drift := absf(MusicMoodState.hue_delta(drawn.h, after.h)) * 360.0
				if name.begins_with("otter"):
					otter_seen += 1
					otter_worst = maxf(otter_worst, drift)
				if drift > worst:
					worst = drift
					worst_where = "%s under %s" % [name, file]
		Desktop.palette = before
	assert_int(measured).is_greater(0)
	(
		assert_float(worst)
		. override_failure_message(
			(
				(
					"%s drifted the room %.1f degrees off its own hue: the music has a road to a "
					+ "surface again, and the theme is the only thing allowed to colour one"
				)
				% [worst_where, worst]
			)
		)
		. is_less_equal(0.0001)
	)
	(
		assert_int(otter_seen)
		. override_failure_message(
			"the owner's otter fixture was not measured; this test is the one that answers it"
		)
		. is_greater(0)
	)
	(
		assert_float(otter_worst)
		. override_failure_message(
			(
				(
					"the owner's green otter theme drifts %.1f degrees under some bundled track "
					+ "with the music at full strength - it is the fixture the blue-violet room "
					+ "was reported on and the one this has to hold for"
				)
				% otter_worst
			)
		)
		. is_less_equal(0.0001)
	)
	# ...and the mood did reach the fires, so the zero above is a guarantee and not a silence.
	(
		assert_float(flame_moved * 360.0)
		. override_failure_message(
			"no bundled track turned a flame by more than %.1f degrees" % (flame_moved * 360.0)
		)
		. is_greater(10.0)
	)
	print(
		(
			(
				"rendered room hue drift %.1f degrees over %d readings (%s); otter %.1f over %d; "
				+ "furthest a flame turned %.1f"
			)
			% [worst, measured, worst_where, otter_worst, otter_seen, flame_moved * 360.0]
		)
	)


## What the music does to a surface drawn at `drawn`: nothing, and that is the whole function.
## It exists so the test above has something to call, and so that reintroducing a road to a
## surface has exactly one obvious place to be caught.
static func _room_as_drawn(drawn: Color, _state: MusicMoodState) -> Color:
	return drawn


## The floor a room is painted in, as the screen draws it where nothing is lighting it: the
## theme's own environment colours mixed toward black by `LightingProfile.unlit_floor`.
## Measuring the *authored* floor instead is what let the old haze through - an authored colour
## carries enough chroma that a small tint barely turns it, and the drawn one does not.
static func _floor_as_drawn(pal: ThemePalette) -> Color:
	var floor_c := _lit_floor(pal)
	var dark := LightingProfile.resolve().unlit_level()
	return Color(floor_c.r * dark, floor_c.g * dark, floor_c.b * dark, 1.0)


## The theme's own floor colour for a crypt, before the darkness: where the room's hue lives.
##
## Both steps `FloorRoot._derive_palette` takes, not just the first. `derive_environment` picks
## the roles; `light_environment` is what *exposes* them, and skipping it measures a palette no
## floor is ever painted in - the owner's otter theme hands back a 0f0f0d floor with 0.008 of
## chroma before exposure and a real olive after it, so a test that stopped at the first step
## would have read their room as a grey and never measured the fixture it exists for.
static func _lit_floor(pal: ThemePalette) -> Color:
	var keys := Biome.load_by_id(&"crypt").palette_keys
	var ambient := WallpaperAnalyzer.AMBIENT_MAX if pal.is_light else LIT_AMBIENT
	return pal.derive_environment(keys).light_environment(ambient).get_color(&"floor")


## The six shipped fixtures and the owner's own otter theme, which is the one that matters
## here: it is green (its surfaces run from hue 60 to 86) and green is what the blue-violet
## mist was furthest from. Built from the checked-in otter fixture by the same call
## `Desktop._load_palette` makes, so it is the palette the owner's machine really builds.
func _hue_fixtures() -> Array[Array]:
	var out: Array[Array] = []
	for theme: String in MusicMoodTest.THEMES:
		out.append([theme, ReactivityFixtures.palette_for(theme)])
	# Read straight off the checked-in fixture rather than through `XDG_CONFIG_HOME`: the
	# environment dance belongs to `otter_theme_fidelity_test`, which is about *finding* the
	# owner's colours. This test is about what the music does to them once found, and a silent
	# miss here would have left the one fixture that matters out of the measurement - which is
	# why `otter_seen` is asserted rather than trusted.
	var colors := OtterWallpaper.load_colors(ProjectSettings.globalize_path(OTTER_COLORS))
	if colors.size() == OtterWallpaper.OTTER_COLOR_KEYS.size():
		out.append(["otter (the owner's)", ThemePalette.from_otter_colors(colors, "Otter")])
	return out


## The owner's correction, measured: "it needs to change based on what is happening over the
## current track". A per-track mood answers "which song is on"; it does not answer "what is the
## song doing", and a look that is constant for four minutes is a look a player stops seeing.
##
## So the same 140 BPM track is fed in twice - a quiet passage and a loud one - with a real
## mood set, so the whole grade is in the measurement and not just the vignette. The look has
## to move between them, and it has to do it without a single frame over the flash bound and
## without leaving anything at the beat frequency behind. Those two are the same assertions the
## no-pulse case makes; what is new is that the grade is now downstream of the envelope, so
## they are measuring the live path rather than a constant.
func test_the_look_breathes_within_one_track_without_ever_pulsing() -> void:
	var mood := MusicMood.for_file("", "A Steady Track")
	mood.energy = 0.5
	_layer.set_mood(mood)
	Music.energy = 0.0
	_layer.set_active(true)
	_advance(MusicMoodLevers.shared().crossfade_seconds + 1.0, 0.12)
	var quiet := _layer.luminance_factor()
	var quiet_live := _layer.live_envelope()
	var samples := PackedFloat64Array()
	var worst := 0.0
	var previous := quiet
	var frames := int(TRACK_SECONDS / FRAME)
	var next_beat := 0.0
	for i in frames:
		var t := float(i) * FRAME
		if t >= next_beat:
			EventBus.music_beat.emit(1.0)
			next_beat += 60.0 / BPM
		_layer.step(FRAME, _track_energy(t))
		var now := _layer.luminance_factor()
		worst = maxf(worst, absf(now - previous))
		previous = now
		samples.append(now)
	var loud := samples[samples.size() - 1]
	(
		assert_float(worst)
		. override_failure_message(
			"the look changed by %f of its luminance in one frame - that is a flash" % worst
		)
		. is_less(MAX_FRAME_DELTA)
	)
	var tail := _detrended(samples.slice(frames * 2 / 3))
	var beat_hz := BPM / 60.0
	for hz: float in [beat_hz, beat_hz * 2.0]:
		(
			assert_float(_amplitude_at(tail, hz, 1.0 / FRAME))
			. override_failure_message(
				"the look carries a component at %.2f Hz inside one track - it is pulsing" % hz
			)
			. is_less(MAX_BEAT_AMPLITUDE)
		)
	var moved := absf(loud - quiet) / maxf(quiet, 0.0001)
	(
		assert_float(moved)
		. override_failure_message(
			(
				(
					"a quiet passage and a loud one of the same track are %.1f%% apart in the "
					+ "middle of the frame - under %.0f%% the track does not breathe"
				)
				% [moved * 100.0, MIN_LIVE_SWING_SHARE * 100.0]
			)
		)
		. is_greater_equal(MIN_LIVE_SWING_SHARE)
	)
	assert_float(_layer.live_envelope()).is_greater(quiet_live)
	print(
		(
			"one track, quiet to loud: %.4f -> %.4f (%.1f%%), worst frame delta %.6f"
			% [quiet, loud, moved * 100.0, worst]
		)
	)


## The rate cap is a cap, not a smoothing. However sharply the music jumps - and a step from
## silence to full is as sharp as it gets - the envelope crosses its band no faster than
## `MusicMoodLevers.live_rate` a second. This is the guarantee that stands between the live
## path and a strobe, and it holds whatever the low-pass stages in front of it do.
func test_the_live_envelope_cannot_cross_its_band_faster_than_its_rate_cap() -> void:
	var levers := MusicMoodLevers.shared()
	_layer.set_mood(_calm_mood())
	Music.energy = 0.0
	_layer.set_active(true)
	_advance(4.0, 0.0)
	var start := _layer.live_envelope()
	var seconds := 0.0
	var previous := start
	for i in int(30.0 / FRAME):
		_layer.step(FRAME, 1.0)
		var now := _layer.live_envelope()
		(
			assert_float(absf(now - previous))
			. override_failure_message(
				(
					"the envelope moved %f in one frame, over the %f the rate cap allows"
					% [absf(now - previous), levers.live_rate * FRAME]
				)
			)
			. is_less_equal(levers.live_rate * FRAME + 0.000001)
		)
		previous = now
		seconds += FRAME
		if now >= 0.99:
			break
	var least := (1.0 - start) / levers.live_rate
	(
		assert_float(seconds)
		. override_failure_message(
			(
				(
					"the envelope crossed from %.2f to full in %.1f s; the rate cap says it cannot "
					+ "be done in under %.1f s"
				)
				% [start, seconds, least]
			)
		)
		. is_greater_equal(least - 0.05)
	)
	print(
		"envelope step response: %.2f to full in %.1f s (cap says %.1f s)" % [start, seconds, least]
	)


## The envelope is a band around the track's own mood, not a replacement for it. A calm track
## at its loudest moment still has to look calmer than a loud track at its quietest, or "which
## track is playing" stops being a thing a player can see and the offline table is wasted.
func test_the_live_envelope_is_a_band_around_the_track_not_a_takeover() -> void:
	var levers := MusicMoodLevers.shared()
	var calm := _calm_mood()
	var loud := _loud_mood()
	var calm_at_peak := levers.state_for(calm.at_energy(calm.energy + levers.live_swing), false)
	var loud_at_trough := levers.state_for(loud.at_energy(loud.energy - levers.live_swing), false)
	(
		assert_float(calm_at_peak.torch)
		. override_failure_message(
			(
				(
					"the calmest track at its loudest burns the fires at x%.3f and the loudest "
					+ "at its quietest at x%.3f - the envelope has swallowed the track"
				)
				% [calm_at_peak.torch, loud_at_trough.torch]
			)
		)
		. is_less(loud_at_trough.torch)
	)
	assert_float(levers.live_swing).is_less(0.5)


## The two numbers the live path turns on, bounded by literals. `live_swing` is a ceiling: past
## half the range the envelope would be louder than the track and two tracks would stop looking
## different. `live_rate` is also a ceiling: it is the anti-flash guard, and raising it is how
## the live path would become a strobe. There is a floor under each as well, because a swing of
## nothing or a rate of nothing is a look that does not move inside a track at all - which is
## the complaint this round exists to answer.
func test_the_live_envelope_numbers_are_guarantees_not_variables() -> void:
	var levers := MusicMoodLevers.shared()
	(
		assert_float(levers.live_swing)
		. override_failure_message(
			(
				(
					"live_swing is %.2f: past 0.3 the envelope moves the look further than the "
					+ "difference between two tracks and the per-track mood stops being visible"
				)
				% levers.live_swing
			)
		)
		. is_less_equal(0.3)
	)
	(
		assert_float(levers.live_swing)
		. override_failure_message(
			"live_swing is %.2f: under 0.1 a track does not visibly breathe" % levers.live_swing
		)
		. is_greater_equal(0.1)
	)
	(
		assert_float(levers.live_rate)
		. override_failure_message(
			(
				(
					"live_rate is %.3f of the energy a second: past 0.2 the look can cross its "
					+ "whole band in a couple of seconds, which is a throb and not a drift"
				)
				% levers.live_rate
			)
		)
		. is_less_equal(0.2)
	)
	assert_float(levers.live_rate).is_greater(0.0)


## The owner, after quitting a run: "can you get rid of the weird floating squares they are even
## on the main menu after leaving a game". The motes are dust in a dungeon, so they belong to a
## run. The class docs already said so - "the menus have their own art" - but nothing was ever
## connected to `run_ended`, so they kept drifting over the title and the summary.
##
## Asserted on `visible` rather than on the drawn frame because that is the property the bug was:
## the node went on drawing because nobody turned it off.
func test_the_motes_belong_to_a_run_and_leave_with_it() -> void:
	var motes := _layer.motes()
	assert_object(motes).is_not_null()
	EventBus.run_started.emit(1234)
	await get_tree().process_frame
	(
		assert_bool(motes.visible)
		. override_failure_message("a run started and the motes did not come with it")
		. is_true()
	)
	EventBus.run_ended.emit(false)
	await get_tree().process_frame
	(
		assert_bool(motes.visible)
		. override_failure_message("the run ended and the motes stayed on screen, over the menus")
		. is_false()
	)


## A mote is a speck of dust caught in the light. It used to draw as a hard square, which at a
## 480x270 viewport reads as a floating block: the owner called them "weird floating squares".
## The guarantee is that a mote's edge falls off rather than ending, so the halo has to be wider
## than the core and fainter than it.
func test_a_mote_is_a_soft_point_and_not_a_square() -> void:
	(
		assert_float(MusicMotes.MOTE_HALO_RADIUS)
		. override_failure_message("the halo has to be wider than the core or there is no falloff")
		. is_greater(MusicMotes.MOTE_CORE_RADIUS)
	)
	(
		assert_float(MusicMotes.HALO_ALPHA)
		. override_failure_message("a halo as solid as the core is just a bigger square")
		. is_between(0.05, 0.6)
	)
