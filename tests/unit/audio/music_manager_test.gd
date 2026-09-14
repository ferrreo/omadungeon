## MusicManager headless: track switching with music_track_changed, crossfade gains, ducking,
## profile/lyrics, looping fallback, playlist resume/idempotence, auto-advance, explicit
## toggle, beat emission and the per-run tracks_played list. Playlist tests use short tones
## written to user:// so no radio download is needed.
class_name MusicManagerTest
extends GdUnitTestSuite

const TEST_DIR := "user://music_test/"

var _music: MusicManager
var _changes: Array[String] = []
var _beats: Array[float] = []
var _explicit_before: bool = true


func before() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	make_tone(0.3, 220.0).save_to_wav(TEST_DIR + "short_a.wav")
	make_tone(0.3, 330.0).save_to_wav(TEST_DIR + "short_b.wav")
	make_tone(6.0, 220.0).save_to_wav(TEST_DIR + "long_a.wav")
	make_tone(6.0, 330.0).save_to_wav(TEST_DIR + "long_b.wav")
	make_tone(6.0, 440.0).save_to_wav(TEST_DIR + "long_boss.wav")


func before_test() -> void:
	_changes = []
	_beats = []
	_explicit_before = bool(GameState.settings.get("explicit_music", true))
	GameState.settings["explicit_music"] = true
	_music = auto_free(MusicManager.new())
	add_child(_music)
	EventBus.music_track_changed.connect(_on_changed)
	EventBus.music_beat.connect(_on_beat)


func after_test() -> void:
	EventBus.music_track_changed.disconnect(_on_changed)
	EventBus.music_beat.disconnect(_on_beat)
	GameState.settings["explicit_music"] = _explicit_before


func _on_changed(title: String, artist: String) -> void:
	_changes.append("%s|%s" % [title, artist])


func _on_beat(strength: float) -> void:
	_beats.append(strength)


static func make_tone(seconds: float, hz: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var n := int(seconds * 22050)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := int(sin(TAU * hz * i / 22050.0) * 12000.0)
		data.encode_s16(i * 2, v)
	wav.data = data
	return wav


## Playlist of user:// tones: two normal tracks, one boss-titled track, optional explicit one.
static func make_test_playlist(long_tracks: bool, with_explicit: bool = false) -> RadioPlaylist:
	var prefix := "long_" if long_tracks else "short_"
	var tracks := [
		{"title": "Alpha", "artist": "Test", "file": prefix + "a.wav"},
		{"title": "Beta", "artist": "Test", "file": prefix + "b.wav"},
	]
	if long_tracks:
		tracks.append({"title": "Test Oligarchy", "artist": "Test", "file": "long_boss.wav"})
	if with_explicit:
		tracks.append(
			{
				"title": "Explicit Gamma",
				"artist": "Test",
				"file": prefix + "a.wav",
				"explicit": true
			}
		)
	var playlist := RadioPlaylist.from_json_text(JSON.stringify({"tracks": tracks}))
	playlist.track_dir = TEST_DIR
	playlist.lyrics_dir = TEST_DIR
	return playlist


func _titles(tracks: Array[RadioTrack]) -> Array[String]:
	var out: Array[String] = []
	for t in tracks:
		out.append(t.title)
	return out


func test_play_stream_switches_and_emits() -> void:
	_music.play_stream(make_tone(2.0, 220.0), "Tone A", "Test")
	assert_bool(_music.is_playing()).is_true()
	assert_str(_music.current_title).is_equal("Tone A")
	await get_tree().process_frame
	_music.play_stream(make_tone(2.0, 440.0), "Tone B", "Test")
	assert_array(_changes).contains_exactly(["Tone A|Test", "Tone B|Test"])
	assert_int(_music.track_count()).is_equal(2)
	assert_str(_music.current_title).is_equal("Tone B")
	assert_array(_music.tracks_played()).contains_exactly(["Tone A - Test", "Tone B - Test"])
	await get_tree().create_timer(MusicManager.CROSSFADE + 0.3).timeout
	var players := _music.get_children().filter(
		func(c: Node) -> bool: return c is AudioStreamPlayer
	)
	var playing := 0
	for p: AudioStreamPlayer in players:
		if p.playing:
			playing += 1
	(
		assert_int(playing)
		. override_failure_message("old player should stop after the crossfade")
		. is_equal(1)
	)


func test_no_toast_by_default() -> void:
	var toasts: Array[String] = []
	var handler := func(text: String, _duration: float) -> void: toasts.append(text)
	EventBus.toast.connect(handler)
	_music.play_stream(make_tone(1.0, 220.0), "Tone", "Test")
	assert_bool(_music.announce_tracks).is_false()
	assert_array(toasts).is_empty()
	_music.announce_tracks = true
	_music.play_stream(make_tone(1.0, 330.0), "Tone 2", "Test")
	assert_array(toasts).contains_exactly(["Tone 2 - Test"])
	EventBus.toast.disconnect(handler)


func test_duck_and_stop() -> void:
	_music.play_stream(make_tone(2.0, 220.0), "Tone", "Test")
	EventBus.music_duck.emit(0.3, true)
	await get_tree().create_timer(MusicManager.DUCK_TIME + 0.15).timeout
	assert_float(_music.duck_gain()).is_equal_approx(0.7, 0.02)
	EventBus.music_duck.emit(0.3, false)
	await get_tree().create_timer(MusicManager.DUCK_TIME + 0.15).timeout
	assert_float(_music.duck_gain()).is_equal_approx(1.0, 0.02)
	_music.stop(0.0)
	assert_bool(_music.is_playing()).is_false()
	assert_int(_music.mode).is_equal(MusicManager.Mode.STOPPED)


func test_profile_reflects_track_and_is_silent_after_stop() -> void:
	assert_int(_music.profile().track_hash).is_equal(0)
	_music.play_stream(make_tone(3.0, 330.0), "Hyprland After Dark", "Ryan R. Hughes")
	var p := _music.profile()
	assert_str(p.title).is_equal("Hyprland After Dark")
	assert_int(p.track_hash).is_not_equal(0)
	assert_float(p.energy).is_between(0.0, 1.0)
	assert_float(p.density_multiplier()).is_between(0.85, 1.15)
	var d := p.to_dict()
	assert_str(str(MusicProfile.from_dict(d).title)).is_equal("Hyprland After Dark")
	_music.stop(1.0)
	# Still fading out, but the profile must already read as silent.
	assert_bool(_music.is_playing()).is_true()
	assert_int(_music.profile().track_hash).is_equal(0)
	assert_str(_music.profile().title).is_equal("")


func test_process_runs_headless_without_errors() -> void:
	_music.play_stream(make_tone(1.0, 110.0), "Tone", "Test")
	for i in 10:
		await get_tree().process_frame
	assert_float(_music.bass).is_greater_equal(0.0)
	assert_float(_music.energy).is_between(0.0, 1.0)


## Drives `MusicManager._process` at a fixed 20 Hz for `seconds`. A headless frame is worth a
## fraction of a millisecond, so "await 40 frames" buys about two energy samples and nothing
## about a 1.5 s average can be observed through it. Time has to be driven, not waited on.
func _advance(seconds: float) -> void:
	for i in int(seconds / 0.05):
		_music._process(0.05)


## `energy` is relative to the track's own baseline (see `MusicAnalysis`), so a steady level
## reads 0.5 whatever that level is, a rise reads above it and a fall below it.
##
## The measurement that made this necessary: with the old absolute mapping, the five bundled
## radio tracks produced mean energies of 0.713, 0.712, 0.717, 0.715 and 0.713 - the lever was
## a constant in the only place it mattered, the real game. The shape below is one that
## constant could never have.
func test_band_override_drives_beats_and_energy() -> void:
	_music.play_stream(make_tone(30.0, 110.0), "Tone", "Test")
	_music.band_override = Vector3(0.1, 0.0, 0.0)
	_advance(6.0)
	assert_array(_beats).is_empty()
	var steady := _music.energy
	(
		assert_float(steady)
		. override_failure_message(
			"a steady level read %f, not the middle of its own range" % steady
		)
		. is_equal_approx(0.5, 0.05)
	)
	# Half a stop louder than this track has been: a lift, not a drop.
	_music.band_override = Vector3(0.15, 0.0, 0.0)
	await get_tree().process_frame
	assert_int(_beats.size()).is_equal(1)
	assert_float(_beats[0]).is_between(0.3, 1.0)
	_advance(3.0)
	var loud := _music.energy
	(
		assert_float(loud)
		. override_failure_message("a passage louder than the track's baseline read %f" % loud)
		. is_greater(steady + 0.15)
	)
	# ... and a breakdown falls back through the middle.
	_music.band_override = Vector3(0.05, 0.0, 0.0)
	_advance(6.0)
	var quiet := _music.energy
	(
		assert_float(quiet)
		. override_failure_message("a breakdown read %f, which is not below the baseline" % quiet)
		. is_less(steady - 0.15)
	)
	assert_float(loud - quiet).is_greater(0.3)
	_music.band_override = Vector3(-1.0, -1.0, -1.0)


## Silence is 0, not "average". Anything else would have a stopped radio quietly asking the
## generator for a middling floor.
func test_silence_reads_as_zero_energy() -> void:
	_music.play_stream(make_tone(30.0, 110.0), "Tone", "Test")
	_music.band_override = Vector3(0.0, 0.0, 0.0)
	_advance(3.0)
	assert_float(_music.energy).is_equal(0.0)
	_music.band_override = Vector3(-1.0, -1.0, -1.0)


## A track change restarts the "now" average but keeps the baseline, so a quieter song after a
## louder one reads calmer immediately instead of going blind for a second and a half - which
## is where floor one is generated.
func test_a_quieter_next_track_reads_calmer_at_once() -> void:
	_music.play_stream(make_tone(30.0, 110.0), "Loud", "Test")
	_music.band_override = Vector3(0.4, 0.0, 0.0)
	_advance(8.0)
	assert_float(_music.energy).is_equal_approx(0.5, 0.05)
	_music.play_stream(make_tone(30.0, 330.0), "Quiet", "Test")
	_music.band_override = Vector3(0.2, 0.0, 0.0)
	_advance(1.0)
	(
		assert_float(_music.energy)
		. override_failure_message("the quieter track still reads as average music")
		. is_less(0.4)
	)
	_music.band_override = Vector3(-1.0, -1.0, -1.0)


## Each `profile()` call is one floor generated, so the log is what the run summary reports.
func test_the_floor_log_records_what_the_music_did_per_floor() -> void:
	var before := GameState.floor_index
	_music.play_stream(make_tone(4.0, 110.0), "Alpha", "Test")
	GameState.floor_index = 0
	_music.profile()
	GameState.floor_index = 1
	_music.play_stream(make_tone(4.0, 330.0), "Beta", "Test")
	_music.profile()
	# A resume rebuilds floor 2: the entry is replaced, not duplicated.
	_music.profile()
	GameState.floor_index = before
	var entries := _music.floor_log()
	assert_int(entries.size()).is_equal(2)
	assert_int(int(entries[0]["floor"])).is_equal(1)
	assert_str(str(entries[0]["title"])).is_equal("Alpha")
	assert_int(int(entries[1]["floor"])).is_equal(2)
	assert_str(str(entries[1]["title"])).is_equal("Beta")
	assert_bool(bool(entries[1]["playing"])).is_true()
	_music.set_shuffle_seed(7)
	assert_array(_music.floor_log()).is_empty()
	_music.restore_floor_log(entries)
	assert_int(_music.floor_log().size()).is_equal(2)


## The floor-start line comes from the log entry of that floor: the track, and what its
## energy and tempo made of the floor. A floor the log never saw gets no line.
func test_the_floor_banner_names_the_track_and_what_it_did() -> void:
	var before := GameState.floor_index
	_music.play_stream(make_tone(4.0, 110.0), "Alpha", "Test")
	GameState.floor_index = 2
	_music.energy = 0.95
	_music.profile()
	GameState.floor_index = before
	var text := _music.floor_banner(2)
	assert_str(text).starts_with("Built to Alpha - dense")
	assert_str(text).ends_with("bright")
	assert_str(_music.floor_banner(5)).is_empty()
	_music.stop(0.0)
	GameState.floor_index = 3
	_music.profile()
	GameState.floor_index = before
	assert_str(_music.floor_banner(3)).is_equal("Built in silence - a steady floor")


func test_empty_playlist_uses_fallback_loops() -> void:
	_music.playlist = RadioPlaylist.from_json_text('{"tracks": []}')
	_music.play_playlist()
	assert_int(_music.mode).is_equal(MusicManager.Mode.PLAYLIST)
	assert_bool(_music.is_playing()).is_true()
	assert_str(_music.current_artist).is_equal(MusicManager.FALLBACK_ARTIST)
	var first := _music.current_title
	_music.next()
	assert_str(_music.current_title).is_not_equal(first)
	_music.play_boss()
	assert_int(_music.mode).is_equal(MusicManager.Mode.BOSS)
	assert_bool(_music.is_playing()).is_true()
	_music.play_menu(&"oligarch")
	assert_int(_music.mode).is_equal(MusicManager.Mode.MENU)
	assert_bool(_music.is_playing()).is_true()


func test_fallback_loop_keeps_playing() -> void:
	_music.playlist = RadioPlaylist.from_json_text('{"tracks": []}')
	_music.play_playlist()
	await get_tree().create_timer(0.4).timeout
	(
		assert_bool(_music.is_playing())
		. override_failure_message("fallback loop must not finish on the first mix")
		. is_true()
	)
	assert_float(_music.playback_position()).is_greater(0.0)
	assert_int(_music.track_count()).is_equal(1)
	assert_int(_changes.size()).is_equal(1)
	# The loader-cached resource must stay untouched (the loop is set on a private copy).
	var cached := load(MusicManager.FALLBACK_DIR + MusicManager.FALLBACK_FILES[0]) as AudioStreamWAV
	assert_int(cached.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)


func test_play_playlist_is_idempotent_and_resumes_after_boss() -> void:
	_music.playlist = make_test_playlist(true)
	_music.set_shuffle_seed(3)
	_music.play_playlist()
	assert_int(_music.track_count()).is_equal(1)
	var queue: Array[RadioTrack] = _music._queue.duplicate()
	var pos: int = _music._queue_pos
	assert_int(queue.size()).is_equal(3)
	_music.play_playlist()
	_music.play_playlist()
	(
		assert_int(_music.track_count())
		. override_failure_message("play_playlist() while playing must not restart")
		. is_equal(1)
	)
	_music.play_boss()
	assert_int(_music.mode).is_equal(MusicManager.Mode.BOSS)
	assert_bool(_music.current_track.title.to_lower().contains("oligarchy")).is_true()
	_music.play_playlist()
	assert_int(_music.mode).is_equal(MusicManager.Mode.PLAYLIST)
	var expected := queue[(pos + 1) % queue.size()]
	assert_str(_music.current_track.title).is_equal(expected.title)
	assert_array(_titles(_music._queue)).is_equal(_titles(queue))


func test_shuffle_is_deterministic_per_seed_and_run_started_reseeds() -> void:
	_music.playlist = make_test_playlist(true)
	_music.set_shuffle_seed(11)
	_music.play_playlist()
	var order_a := _titles(_music._queue)
	_music.play_stream(make_tone(1.0, 220.0), "Jingle", "")
	EventBus.run_started.emit(11)
	assert_array(_music.tracks_played()).is_empty()
	_music.play_playlist()
	assert_array(_titles(_music._queue)).is_equal(order_a)
	assert_array(_music.tracks_played()).has_size(1)
	_music.set_shuffle_seed(12)
	_music.play_playlist()
	var order_c := _titles(_music._queue)
	var differs := false
	for seed_value in range(13, 40):
		_music.set_shuffle_seed(seed_value)
		_music.play_playlist()
		if _titles(_music._queue) != order_c:
			differs = true
			break
	assert_bool(differs).override_failure_message("different seeds should reorder").is_true()


func test_auto_advances_when_track_finishes() -> void:
	_music.playlist = make_test_playlist(false)
	_music.set_shuffle_seed(1)
	_music.play_playlist()
	var first := _music.current_title
	await get_tree().create_timer(0.7).timeout
	assert_int(_music.track_count()).is_greater_equal(2)
	assert_str(_changes[1].split("|")[0]).is_not_equal(first)
	assert_int(_music.tracks_played().size()).is_greater_equal(2)
	assert_int(_music.mode).is_equal(MusicManager.Mode.PLAYLIST)


func test_explicit_toggle_rebuilds_queue_both_ways() -> void:
	_music.playlist = make_test_playlist(true, true)
	_music.set_shuffle_seed(2)
	_music.play_playlist()
	assert_int(_music._queue.size()).is_equal(4)
	while not _music.current_track.explicit:
		_music.next()
	GameState.settings["explicit_music"] = false
	EventBus.settings_changed.emit("explicit_music")
	assert_bool(_music.current_track.explicit).is_false()
	assert_int(_music._queue.size()).is_equal(3)
	var kept := _music.current_track
	GameState.settings["explicit_music"] = true
	EventBus.settings_changed.emit("explicit_music")
	assert_int(_music._queue.size()).is_equal(4)
	assert_object(_music.current_track).is_same(kept)
	assert_int(_music._queue_pos).is_equal(_music._queue.find(kept))


func test_menu_track_and_bundled_radio_when_present() -> void:
	var radio := RadioPlaylist.load_default()
	if radio.available().is_empty():
		return
	_music.set_shuffle_seed(7)
	_music.play_playlist()
	assert_bool(_music.is_playing()).is_true()
	assert_object(_music.current_track).is_not_null()
	_music.play_boss()
	assert_bool(_music.current_track.title.to_lower().contains("oligarchy")).is_true()
	_music.play_menu(&"oligarch")
	assert_str(_music.current_track.title).is_equal(RadioPlaylist.OLIGARCH_MENU_TITLE)


func test_unsynced_lyrics_spread_over_track() -> void:
	_music.play_stream(make_tone(1.0, 110.0), "Tone", "Test")
	_music._lyrics = RadioPlaylist.parse_lrc("one\ntwo\nthree")
	_music._lyrics_synced = false
	assert_str(_music.current_lyric()).is_equal("one")
	_music._lyrics = RadioPlaylist.parse_lrc("[00:00.00]start\n[00:30.00]later")
	_music._lyrics_synced = true
	assert_str(_music.current_lyric()).is_equal("start")
	assert_int(_music.lyric_lines().size()).is_equal(2)


func test_overlapping_ducks_nest() -> void:
	_music.play_stream(make_tone(4.0, 220.0), "Tone", "Test")
	EventBus.music_duck.emit(0.5, true)
	EventBus.music_duck.emit(0.4, true)
	await get_tree().create_timer(MusicManager.DUCK_TIME + 0.15).timeout
	assert_float(_music.duck_gain()).is_equal_approx(0.5, 0.02)
	EventBus.music_duck.emit(0.4, false)
	await get_tree().create_timer(MusicManager.DUCK_TIME + 0.15).timeout
	(
		assert_float(_music.duck_gain())
		. override_failure_message("the deeper duck must survive its overlapping neighbour")
		. is_equal_approx(0.5, 0.02)
	)
	EventBus.music_duck.emit(0.5, false)
	await get_tree().create_timer(MusicManager.DUCK_TIME + 0.15).timeout
	assert_float(_music.duck_gain()).is_equal_approx(1.0, 0.02)


func test_menu_track_loops_forever() -> void:
	var tracks := [
		{"title": RadioPlaylist.OLIGARCH_MENU_TITLE, "artist": "Test", "file": "short_a.wav"},
	]
	var menu_playlist := RadioPlaylist.from_json_text(JSON.stringify({"tracks": tracks}))
	menu_playlist.track_dir = TEST_DIR
	menu_playlist.lyrics_dir = TEST_DIR
	_music.playlist = menu_playlist
	_music.play_menu(&"oligarch")
	assert_int(_music.mode).is_equal(MusicManager.Mode.MENU)
	assert_bool(_music.is_playing()).is_true()
	var title := _music.current_title
	await get_tree().create_timer(0.6).timeout
	(
		assert_bool(_music.is_playing())
		. override_failure_message("the menu track must loop instead of falling silent")
		. is_true()
	)
	assert_str(_music.current_title).is_equal(title)
	assert_int(_music.track_count()).is_equal(1)
	_music.play_menu(&"oligarch")
	(
		assert_int(_music.track_count())
		. override_failure_message("play_menu() must not restart the same menu track")
		. is_equal(1)
	)


func test_play_boss_is_idempotent() -> void:
	_music.playlist = make_test_playlist(true)
	_music.set_shuffle_seed(6)
	_music.play_playlist()
	_music.play_boss()
	var count := _music.track_count()
	_music.play_boss()
	_music.play_boss()
	(
		assert_int(_music.track_count())
		. override_failure_message("play_boss() while the boss theme plays must not restart it")
		. is_equal(count)
	)


func test_playlist_resumes_while_stop_is_still_fading() -> void:
	_music.playlist = make_test_playlist(true)
	_music.set_shuffle_seed(8)
	_music.play_playlist()
	var queue: Array[RadioTrack] = _music._queue.duplicate()
	var pos: int = _music._queue_pos
	_music.stop(MusicManager.CROSSFADE)
	_music.play_playlist()
	assert_int(_music.mode).is_equal(MusicManager.Mode.PLAYLIST)
	var expected := queue[(pos + 1) % queue.size()]
	assert_str(_music.current_track.title).is_equal(expected.title)
	await get_tree().create_timer(MusicManager.CROSSFADE + 0.4).timeout
	var playing := 0
	for p: AudioStreamPlayer in _music.get_children().filter(
		func(c: Node) -> bool: return c is AudioStreamPlayer
	):
		if p.playing:
			playing += 1
	(
		assert_int(playing)
		. override_failure_message("the interrupted stop fade must not leave a player running")
		. is_equal(1)
	)
	assert_bool(_music.is_playing()).is_true()


func test_explicit_setting_is_picked_up_without_the_event() -> void:
	_music.playlist = make_test_playlist(true, true)
	_music.set_shuffle_seed(9)
	_music.play_playlist()
	assert_int(_music._queue.size()).is_equal(4)
	GameState.settings["explicit_music"] = false
	await get_tree().create_timer(MusicManager.SETTINGS_POLL + 0.25).timeout
	(
		assert_int(_music._queue.size())
		. override_failure_message("settings are polled: nothing emits EventBus.settings_changed")
		. is_equal(3)
	)
	for t: RadioTrack in _music._queue:
		assert_bool(t.explicit).is_false()
	assert_bool(_music.current_track.explicit).is_false()


func test_boss_picks_do_not_disturb_the_seeded_playlist_order() -> void:
	_music.playlist = make_test_playlist(true)
	_music.set_shuffle_seed(21)
	_music.play_playlist()
	var order_a := _titles(_music._queue)
	_music.set_shuffle_seed(21)
	_music.play_boss()
	_music.play_stream(make_tone(1.0, 220.0), "Jingle", "")
	_music.play_playlist()
	(
		assert_array(_titles(_music._queue))
		. override_failure_message("boss/menu picks must not consume the shuffle stream")
		. is_equal(order_a)
	)
