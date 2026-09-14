## The live side of the music levers (docs §10.2): the track playing now reaches the torches
## and the next room's enemies without a floor rebuild. `Music.play_track_file` puts a chosen
## bundled track on, the torch lights take the mood's colour and level and flicker amplitude,
## the room the player then walks into gets the aggression nudge once per enemy - never a boss,
## never twice, never the room already in - and the now-playing words name the mood.
class_name MusicLiveMoodTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"

var _floors: Array[FloorRoot] = []
var _setting_before: bool = true
var _amount_before: float = 1.0


func before_test() -> void:
	_setting_before = bool(GameState.settings.get("music_lights", true))
	_amount_before = float(GameState.settings.get("music_lights_amount", 1.0))
	GameState.settings["music_lights"] = true
	GameState.settings["music_lights_amount"] = 1.0


func after_test() -> void:
	for root: FloorRoot in _floors:
		if is_instance_valid(root):
			root.clear_floor()
			root.free()
	_floors.clear()
	EventBus.run_ended.emit(false)
	Music.stop(0.0)
	GameState.settings["music_lights"] = _setting_before
	GameState.settings["music_lights_amount"] = _amount_before
	await get_tree().process_frame
	await get_tree().process_frame


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _floor(theme: String = "tokyo-night") -> FloorRoot:
	var root := FloorRoot.new()
	_floors.append(root)
	add_child(root)
	root.build_with_biome(
		RoomsTestFixtures.three_rooms(), Biome.load_by_id(&"crypt"), null, _palette(theme)
	)
	return root


## Starts a run's worth of music on `file` and lets the lights settle on its mood.
func _play(file: String) -> void:
	EventBus.run_started.emit(4242)
	(
		assert_bool(Music.play_track_file(file))
		. override_failure_message("cannot play %s" % file)
		. is_true()
	)
	assert_bool(Music.lights().is_active()).is_true()
	for i in 400:
		Music.lights().step(1.0 / 60.0, 0.5)


## Whether this machine has the measured tracks these tests need, asserted rather than merely
## returned.
##
## Every mood test in this file used to open with `if not _has_tracks(): return`, which is a
## silent pass: emptying `data/music/track_moods.json` left the suite reporting six cases and
## zero failures while four of them did nothing at all. That is the same disease as a check
## nobody runs, one level down - a guarantee that evaporates with its fixture and says nothing
## on the way out. The catalogue is shipped, so its absence is a broken tree, not a skip.
func _has_tracks() -> bool:
	var files := MusicMood.measured_files()
	(
		assert_int(files.size())
		. override_failure_message(
			(
				(
					"no measured tracks: data/music/track_moods.json holds %d. Every mood "
					+ "assertion in this suite is silently skipped without it."
				)
				% files.size()
			)
		)
		. is_greater_equal(2)
	)
	(
		assert_bool(Music.playlist.available().is_empty())
		. override_failure_message("the playlist is empty, so no mood test below runs")
		. is_false()
	)
	return not Music.playlist.available().is_empty() and files.size() >= 2


func test_a_chosen_track_plays_with_its_measured_mood_and_words() -> void:
	if not _has_tracks():
		return
	var loud := MusicMood.extreme_file(true)
	_play(loud)
	assert_str(Music.current_track.file).is_equal(loud)
	assert_float(Music.mood().energy).is_equal_approx(1.0, 0.001)
	assert_str(Music.mood_words()).is_not_empty()
	assert_str(Music.mood_words()).contains("fierce")
	assert_bool(Music.play_track_file("no-such-file.mp3")).is_false()
	assert_str(Music.current_track.file).is_equal(loud)


## The torches: calm and loud tracks light the same floor in different colours and at
## different levels, and a calm track's flicker wanders less.
func test_the_torches_follow_the_track() -> void:
	if not _has_tracks():
		return
	var root := _floor()
	assert_int(root.torch_lights().size()).is_greater(0)
	_play(MusicMood.extreme_file(false))
	root._relight_torches()
	var calm_color: Color = root.torch_lights()[0].color
	var calm_energy: float = root.torch_lights()[0].energy
	var calm_flicker := root.torch_flicker_amount()
	_play(MusicMood.extreme_file(true))
	root._relight_torches()
	var loud_color: Color = root.torch_lights()[0].color
	var loud_energy: float = root.torch_lights()[0].energy
	var loud_flicker := root.torch_flicker_amount()
	assert_float(loud_energy).is_greater(calm_energy * 1.2)
	assert_float(loud_flicker).is_greater(calm_flicker * 2.0)
	assert_bool(calm_color.is_equal_approx(loud_color)).is_false()
	# Both are still lights: full value, a hue of their own.
	assert_float(calm_color.v).is_greater_equal(0.5)
	assert_float(loud_color.v).is_greater_equal(0.5)
	# And the base energy the readability model is written against is untouched by the mood.
	assert_float(root.torch_light_energy()).is_equal_approx(root.torch_light_energy(), 0.0001)


## The contract a lighting system reads (`DungeonLight.torch_color/torch_energy_scale/
## torch_radius_scale/torch_flicker_amplitude`): under the loudest track every number leans
## loud, under the calmest calm, and with the switch off every one is the theme's own - so a
## consumer never needs to know whether the music lights are on.
##
## Four numbers, not six. `ambient_color()` and `ambient_energy()` were the pair the music moved
## the *room* with rather than the lights in it, and the owner's ruling deleted them: there is no
## ambient for a mood to reach.
func test_the_light_contract_publishes_the_mood_and_is_neutral_when_off() -> void:
	if not _has_tracks():
		return
	var profile := DungeonLight.resolve()
	var pal := _palette("tokyo-night")
	_play(MusicMood.extreme_file(false))
	var calm_torch := profile.torch_energy_scale()
	var calm_radius := profile.torch_radius_scale()
	var calm_flicker := profile.torch_flicker_amplitude()
	var calm_color := profile.torch_color(pal)
	assert_float(calm_torch).is_less(1.0)
	assert_float(calm_radius).is_less(1.0)
	_play(MusicMood.extreme_file(true))
	assert_float(profile.torch_energy_scale()).is_greater(calm_torch)
	assert_float(profile.torch_energy_scale()).is_greater(1.0)
	assert_float(profile.torch_radius_scale()).is_greater(calm_radius)
	assert_float(profile.torch_flicker_amplitude()).is_greater(calm_flicker)
	assert_bool(profile.torch_color(pal).is_equal_approx(calm_color)).is_false()
	# The flame keeps its value under every mood: it is a light, not a surface.
	assert_float(profile.torch_color(pal).v).is_greater_equal(0.5)
	# And the contract has no road to a room left at all.
	for gone: String in ["ambient_color", "ambient_energy"]:
		(
			assert_bool(profile.has_method(gone))
			. override_failure_message(
				"DungeonLight.%s() is back: that is the music lighting the room again" % gone
			)
			. is_false()
		)
	GameState.settings["music_lights"] = false
	Music.lights().step(1.0 / 60.0, 0.5)
	assert_float(profile.torch_energy_scale()).is_equal_approx(1.0, 0.0001)
	assert_float(profile.torch_radius_scale()).is_equal_approx(1.0, 0.0001)
	assert_float(profile.torch_flicker_amplitude()).is_equal_approx(
		Accessibility.flash(profile.torch_flicker), 0.0001
	)
	var plain := profile.light_color(profile.torch_role_color(pal))
	assert_bool(profile.torch_color(pal).is_equal_approx(plain)).is_true()


## The flicker is noise, not a cycle: sampled over eight seconds, the torch energy carries no
## peak at the old 2.3 Hz sine frequency that stands out from its neighbours.
func test_the_flicker_has_no_periodic_component() -> void:
	var root := _floor()
	var light: PointLight2D = root.torch_lights()[0]
	var samples := PackedFloat64Array()
	var frame := 1.0 / 60.0
	for i in int(8.0 / frame):
		root._process(frame)
		samples.append(light.energy)
	var hz := root._light_profile.torch_flicker_hz
	var at := _amplitude_at(samples, hz, 60.0)
	var beside := maxf(
		_amplitude_at(samples, hz * 0.8, 60.0), _amplitude_at(samples, hz * 1.25, 60.0)
	)
	assert_float(at).override_failure_message("a %.1f Hz peak of %f" % [hz, at]).is_less(
		beside * 3.0 + 0.002
	)


static func _amplitude_at(samples: PackedFloat64Array, hz: float, rate: float) -> float:
	var re := 0.0
	var im := 0.0
	var n := samples.size()
	for i in n:
		var angle := -TAU * hz * float(i) / rate
		re += samples[i] * cos(angle)
		im += samples[i] * sin(angle)
	return 2.0 * sqrt(re * re + im * im) / float(n)


## The gameplay nudge: entering a room under the loudest track makes its enemies a tenth
## keener, faster and quicker to swing - once, never a boss, and never the enemies of another
## room.
func test_entering_a_room_nudges_its_enemies_once_by_the_live_mood() -> void:
	if not _has_tracks():
		return
	var host := auto_free(Node2D.new()) as Node2D
	add_child(host)
	var here := EnemyTestHelpers.spawn(&"juggler", host, Vector2(64, 64))
	var elsewhere := EnemyTestHelpers.spawn(&"juggler", host, Vector2(128, 64))
	here.room_id = 3
	elsewhere.room_id = 4
	var sight_before := here.awareness.sight
	var speed_before := here.stats.get_value(&"move_speed")
	var cooldown_before := here.attack_cooldown()
	_play(MusicMood.extreme_file(true))
	assert_float(Music.live_aggression()).is_equal_approx(1.1, 0.0001)
	EventBus.room_entered.emit(3)
	assert_float(here.awareness.sight).is_equal_approx(sight_before * 1.1, 0.01)
	assert_float(here.stats.get_value(&"move_speed")).is_equal_approx(speed_before * 1.1, 0.01)
	assert_float(here.attack_cooldown()).is_equal_approx(cooldown_before / 1.1, 0.001)
	assert_float(elsewhere.awareness.sight).is_equal_approx(sight_before, 0.001)
	# Entering again - or a louder track later - changes nothing for an enemy already nudged.
	EventBus.room_entered.emit(3)
	assert_float(here.awareness.sight).is_equal_approx(sight_before * 1.1, 0.01)
	assert_float(here.stats.get_value(&"move_speed")).is_equal_approx(speed_before * 1.1, 0.01)


func test_silence_nudges_nothing() -> void:
	var host := auto_free(Node2D.new()) as Node2D
	add_child(host)
	var enemy := EnemyTestHelpers.spawn(&"juggler", host, Vector2(64, 64))
	enemy.room_id = 7
	var sight_before := enemy.awareness.sight
	Music.stop(0.0)
	EventBus.run_started.emit(4243)
	assert_float(Music.live_aggression()).is_equal_approx(1.0, 0.0001)
	EventBus.room_entered.emit(7)
	assert_float(enemy.awareness.sight).is_equal_approx(sight_before, 0.001)
	assert_float(enemy.stats.get_value(&"move_speed")).is_equal_approx(enemy.def.move_speed, 0.001)
