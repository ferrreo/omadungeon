## The `music_within` capture: the same room, photographed at the quietest, the typical and the
## loudest passage of **one** track, plus one control frame with the music lights switched off.
## All six points are measured; four are photographed (see `run`).
##
## It exists because the owner's correction moved the goalposts: "it needs to change based on
## what is happening over the current track". Every earlier piece of evidence compared one
## track against another, which answers "can you see which song is on" and says nothing about
## whether a song *does* anything while it plays. A look that is constant for four minutes is a
## look a player stops seeing, and that is the state the report "music STILL doesn't seem to do
## anything" was describing.
##
## The three energies are the track's own, not numbers somebody picked: `tools/analyze-radio.py`
## decodes the real waveform and runs the same two exponential means `MusicManager._push_energy`
## runs, then ships the 10th, 50th and 90th percentile of the result as `live_quiet`, `live_mid`
## and `live_loud` (`MusicMood.live_points`). They are injected rather than heard because the
## headless audio driver produces no spectrum at all - the number is the track's, the delivery
## is the harness's.
##
## The track is the one whose own quiet and loud passages sit furthest apart
## (`MusicMood.widest_live_file`), because the question here is whether a track breathes and
## that is the track with the most breath in it.
##
## Lives in its own file only because `TestScenarios` is at the 1200-line cap.
class_name MusicWithinScenario
extends RefCounted

## Seconds each photograph is given to settle after the envelope is *placed* at its value
## (`MusicReactiveLayer.place_envelope`). The live path is deliberately slow in play - two
## multi-second low-pass stages and then `MusicMoodLevers.live_rate`, a hard cap of 0.065 of the
## energy a second - and walking between six passages at that rate would spend most of the
## scenario's 75-second budget travelling rather than photographing. What the walk looks like
## frame by frame is measured in `music_reactive_layer_test` against the flash bound; this
## capture is about where the track *arrives*, so the camera is placed rather than driven.
const ARRIVE_SECONDS := 1.2
## Least the frame's measured luminance must differ between the quiet and loud passages, as a
## share of the quiet one. The unit suite measures this on the grade; here it is measured on a
## drawn frame of a real room, which is the thing the owner is actually looking at.
const MIN_RENDERED_SWING := 0.08


## Runs the capture on `driver` (a `TestScenarios`). Shoots six frames, writes the strip and
## the measurement lines, and fails the scenario when the room did not move.
static func run(driver: TestScenarios) -> void:
	if not await driver._start_run():
		return
	var file := MusicMood.widest_live_file()
	var points := MusicMood.live_points(file)
	if not driver.require(points.size() == 3, "the mood table carries no live envelope"):
		return
	if not driver.require(Music.play_track_file(file), "cannot play %s" % file):
		return
	await driver.get_tree().create_timer(TestScenarios.MOOD_SETTLE).timeout
	driver._reset_music_records()
	var labels: PackedStringArray = ["quiet", "mid", "loud"]
	var lit: PackedFloat32Array = []
	for lights_on: bool in [true, false]:
		GameState.settings[MusicReactiveLayer.SETTING_ON] = lights_on
		for i in labels.size():
			var label := "%s_%s" % [labels[i], "on" if lights_on else "off"]
			# Every point is *measured*; only the lit three and one control are *photographed*.
			# A frame costs a settle and a 1440x810 PNG encode, and this row already pays a
			# project import like every other; at six shots it was the row that timed out the
			# whole scenarios matrix on a loaded machine. Three numbers make the control's point
			# as well as three pictures would - they are all the same number.
			var shoot := lights_on or i == labels.size() - 1
			if not await _measure_at(driver, file, label, points[i], shoot):
				return
			if lights_on:
				lit.append(driver._room_luminance())
	GameState.settings[MusicReactiveLayer.SETTING_ON] = true
	_judge(driver, file, points, lit)
	driver._write_lines("music_within", driver._music_lines)
	driver._write_strip(driver._music_frames, "music_within_strip")


## One point: the live energy placed, the frame given `ARRIVE_SECONDS` to settle on it, then
## the measurement - and the screenshot too when `shoot` is set.
static func _measure_at(
	driver: TestScenarios, file: String, label: String, energy: float, shoot: bool
) -> bool:
	Music.energy = clampf(energy, 0.0, 1.0)
	var lights := Music.lights()
	if lights != null:
		lights.place_envelope(energy)
	await driver.get_tree().create_timer(ARRIVE_SECONDS).timeout
	await driver._settle()
	if shoot:
		var name := "music_within_%s" % label
		if not await driver._shoot(name):
			return false
		var image := Image.load_from_file(driver.screenshot_path(name))
		if image != null:
			driver._music_frames.append(image)
	driver._music_lines.append(driver._measure_line(label, file))
	return true


## The room has to have moved between the quiet passage and the loud one, and it has to have
## moved *up*: a drop that dims the dungeon is the mapping inverted.
static func _judge(
	driver: TestScenarios, file: String, points: PackedFloat32Array, lit: PackedFloat32Array
) -> void:
	if not driver.require(lit.size() == 3, "the lit series is short"):
		return
	var swing := (lit[2] - lit[0]) / maxf(lit[0], 0.0001)
	driver.require(
		swing >= MIN_RENDERED_SWING,
		(
			(
				"%s moved the room %.1f%% between its own quiet (%.2f) and loud (%.2f) passages, "
				+ "under the %.0f%% a track has to breathe by"
			)
			% [file, swing * 100.0, points[0], points[2], MIN_RENDERED_SWING * 100.0]
		)
	)
	driver.require(lit[1] >= lit[0], "the typical passage is darker than the quietest one")
