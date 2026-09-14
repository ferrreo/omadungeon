## RadioPlaylist parsing, explicit filtering, deterministic shuffle, subsets and LRC parsing.
class_name RadioPlaylistTest
extends GdUnitTestSuite

const SAMPLE := """
{
  "station": "omarchy",
  "name": "Omarchy",
  "tracks": [
    {"title": "Omarchy Oligarchy (Synthwave Mix)", "artist": "YZL81", "file": "a.mp3"},
    {"title": "public code, private yacht", "artist": "Kevin Koontz", "file": "b.mp3"},
    {"title": "It's fork o clock", "artist": "Boyd", "file": "c.mp3", "explicit": true},
    {"title": "Beware the Omarchy Oligarchy", "artist": "Rich Kilmer", "file": "d.mp3", "lyrics": "d.lrc"},
    {"title": "Hyprland After Dark", "artist": "Ryan R. Hughes", "file": "e.mp3"}
  ]
}
"""
## Least mean step in measured energy between two tracks played in a row, over the bundled
## playlist, and least tenth-percentile step. Both are floors.
const MIN_MEAN_MOOD_STEP := 0.45
const MIN_TENTH_MOOD_STEP := 0.25
## Shuffles measured when the two are read off the bundled set.
const SPREAD_SEEDS := 40


func test_parse_fields() -> void:
	var p := RadioPlaylist.from_json_text(SAMPLE)
	assert_str(p.station).is_equal("omarchy")
	assert_int(p.tracks.size()).is_equal(5)
	assert_str(p.tracks[0].title).is_equal("Omarchy Oligarchy (Synthwave Mix)")
	assert_str(p.tracks[0].artist).is_equal("YZL81")
	assert_bool(p.tracks[0].explicit).is_false()
	assert_bool(p.tracks[2].explicit).is_true()
	assert_str(p.tracks[3].lyrics).is_equal("d.lrc")
	assert_str(p.track_path(p.tracks[1])).is_equal("res://assets/music/radio/b.mp3")


func test_invalid_json_gives_empty_playlist() -> void:
	assert_int(RadioPlaylist.from_json_text("not json").tracks.size()).is_equal(0)
	assert_int(RadioPlaylist.load_file("res://nope.json").tracks.size()).is_equal(0)


func test_explicit_filter() -> void:
	var p := RadioPlaylist.from_json_text(SAMPLE)
	assert_int(p.filtered(true).size()).is_equal(5)
	var clean := p.filtered(false)
	assert_int(clean.size()).is_equal(4)
	for t in clean:
		assert_bool(t.explicit).is_false()
	var old: bool = GameState.settings.get("explicit_music", true)
	GameState.settings["explicit_music"] = false
	assert_int(p.playable().size()).is_equal(4)
	GameState.settings["explicit_music"] = old


func test_shuffle_is_deterministic_and_complete() -> void:
	var p := RadioPlaylist.from_json_text(SAMPLE)
	var a := p.shuffle(RunRng.new(42).stream(&"music"))
	var b := p.shuffle(RunRng.new(42).stream(&"music"))
	var c := p.shuffle(RunRng.new(43).stream(&"music"))
	assert_int(a.size()).is_equal(5)
	for i in a.size():
		assert_str(a[i].file).is_equal(b[i].file)
	var same := true
	for i in a.size():
		if a[i].file != c[i].file:
			same = false
	assert_bool(same).override_failure_message("different seeds gave identical order").is_false()
	var files: Array[String] = []
	for t in a:
		files.append(t.file)
	files.sort()
	assert_array(files).contains_exactly(["a.mp3", "b.mp3", "c.mp3", "d.mp3", "e.mp3"])


func test_boss_and_menu_subsets() -> void:
	var p := RadioPlaylist.from_json_text(SAMPLE)
	var boss := p.boss_tracks()
	assert_int(boss.size()).is_equal(2)
	assert_str(boss[0].file).is_equal("a.mp3")
	assert_str(boss[1].file).is_equal("d.mp3")
	var menu := p.menu_track(&"oligarch")
	assert_object(menu).is_not_null()
	assert_str(menu.title).is_equal("public code, private yacht")
	assert_object(p.menu_track(&"fighter")).is_null()


func test_bundled_playlist_loads_when_present() -> void:
	var p := RadioPlaylist.load_default()
	if p.tracks.is_empty():
		return
	assert_int(p.boss_tracks().size()).is_greater_equal(1)
	assert_object(p.menu_track(&"oligarch")).is_not_null()
	for t in p.tracks:
		assert_str(t.file).ends_with(".mp3")
	var with_lyrics := p.find_by_title("We Can Fix Everything (The Ultimate Machine)")
	if with_lyrics != null and not p.lyrics_path(with_lyrics).is_empty():
		assert_int(p.lyrics_for(with_lyrics).size()).is_greater(5)


func test_parse_lrc_timed() -> void:
	var text := "[ar:Someone]\n[ti:Song]\n[00:12.50]first line\n[00:05.00]earlier\n[01:00.25][01:30]repeated\n"
	var lines := RadioPlaylist.parse_lrc(text)
	assert_int(lines.size()).is_equal(4)
	assert_bool(RadioPlaylist.lyrics_synced(lines)).is_true()
	assert_float(float(lines[0]["time"])).is_equal_approx(5.0, 0.001)
	assert_str(str(lines[0]["text"])).is_equal("earlier")
	assert_float(float(lines[1]["time"])).is_equal_approx(12.5, 0.001)
	assert_float(float(lines[2]["time"])).is_equal_approx(60.25, 0.001)
	assert_float(float(lines[3]["time"])).is_equal_approx(90.0, 0.001)
	assert_str(str(lines[3]["text"])).is_equal("repeated")


func test_parse_lrc_untimed() -> void:
	var lines := RadioPlaylist.parse_lrc("I was stuck\n\nPretty screen\n")
	assert_int(lines.size()).is_equal(2)
	assert_bool(RadioPlaylist.lyrics_synced(lines)).is_false()
	assert_float(float(lines[0]["time"])).is_equal(-1.0)
	assert_str(str(lines[1]["text"])).is_equal("Pretty screen")


func test_bundled_playlist_loads_with_tracks() -> void:
	var playlist := RadioPlaylist.load_default()
	(
		assert_int(playlist.tracks.size())
		. override_failure_message(
			"assets/music/radio/playlist.json missing or empty (run tools/sync-radio.sh)"
		)
		. is_greater_equal(30)
	)
	assert_int(playlist.boss_tracks().size()).is_greater_equal(1)
	assert_object(playlist.menu_track(&"oligarch")).is_not_null()


func test_custom_directories_are_used_for_paths() -> void:
	var playlist := RadioPlaylist.from_json_text(
		'{"tracks": [{"title": "T", "artist": "A", "file": "t.wav", "lyrics": "t.lrc"}]}'
	)
	playlist.track_dir = "user://x/"
	playlist.lyrics_dir = "user://y/"
	assert_str(playlist.track_path(playlist.tracks[0])).is_equal("user://x/t.wav")
	assert_str(playlist.lyrics_path(playlist.tracks[0])).is_equal("user://y/t.lrc")
	assert_bool(playlist.has_track_file(playlist.tracks[0])).is_false()


static func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v: float in values:
		total += v
	return total / float(values.size()) if not values.is_empty() else 0.0


static func _tenth(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[maxi(sorted.size() / 10, 0)] if not sorted.is_empty() else 0.0


## The owner's complaint, measured where it actually lands: not between the calmest and the
## loudest bundled track, which is what every previous round measured, but between the track
## playing and the one that follows it.
##
## The bundled moods are ranks spread evenly over 0..1, so a plain shuffle deals those pairs at
## random: the mean step a player hears is about a third of the range and one change in ten
## moves the look by almost nothing. `RadioPlaylist.spread` draws the next track from those at
## least `MOOD_MIN_STEP` away instead, which is the difference between a mood mapping that
## exists and one a person notices existing.
##
## Measured over `SPREAD_SEEDS` shuffles of the bundled playlist, and asserted both against the
## absolute floors and against the plain shuffle, so the test says the reordering *did* it
## rather than only that the numbers are large.
func test_the_played_order_spreads_the_mood_between_the_tracks_a_player_hears() -> void:
	var p := RadioPlaylist.load_default()
	if p.tracks.size() < 10:
		return
	var spread_means: Array[float] = []
	var spread_tenths: Array[float] = []
	var plain_means: Array[float] = []
	var plain_tenths: Array[float] = []
	for i in SPREAD_SEEDS:
		var rng := RunRng.new(6100 + i).stream(&"music")
		var plain := p.shuffle(rng)
		var plain_steps := RadioPlaylist.mood_steps(plain)
		plain_means.append(_mean(plain_steps))
		plain_tenths.append(_tenth(plain_steps))
		var spread_steps := RadioPlaylist.mood_steps(RadioPlaylist.spread(plain, rng))
		spread_means.append(_mean(spread_steps))
		spread_tenths.append(_tenth(spread_steps))
	var mean_step := _mean(spread_means)
	var tenth_step := _mean(spread_tenths)
	(
		assert_float(mean_step)
		. override_failure_message(
			(
				(
					"two tracks in a row differ by %.3f of the energy range on average "
					+ "(plain shuffle: %.3f); under %.2f the look barely moves when the song does"
				)
				% [mean_step, _mean(plain_means), MIN_MEAN_MOOD_STEP]
			)
		)
		. is_greater_equal(MIN_MEAN_MOOD_STEP)
	)
	(
		assert_float(tenth_step)
		. override_failure_message(
			(
				(
					"the quietest tenth of track changes move the energy by %.3f "
					+ "(plain shuffle: %.3f): those are the changes a player sees nothing at"
				)
				% [tenth_step, _mean(plain_tenths)]
			)
		)
		. is_greater_equal(MIN_TENTH_MOOD_STEP)
	)
	# And the reordering is what did it, not the bundled set being lucky.
	assert_float(mean_step).is_greater(_mean(plain_means) * 1.2)
	assert_float(tenth_step).is_greater(_mean(plain_tenths) * 2.0)
	print(
		(
			"adjacent mood step: shuffled mean %.3f p10 %.3f -> spread mean %.3f p10 %.3f"
			% [_mean(plain_means), _mean(plain_tenths), mean_step, tenth_step]
		)
	)


## The spread is a reordering and nothing else: every track exactly once, and the same run seed
## replays the same order - the playlist is part of what a seeded run is.
func test_the_spread_plays_every_track_once_and_replays_with_the_seed() -> void:
	var p := RadioPlaylist.from_json_text(SAMPLE)
	var a := RadioPlaylist.spread(p.filtered(true), RunRng.new(77).stream(&"music"))
	var b := RadioPlaylist.spread(p.filtered(true), RunRng.new(77).stream(&"music"))
	assert_int(a.size()).is_equal(5)
	var files: Array[String] = []
	for i in a.size():
		assert_str(a[i].file).is_equal(b[i].file)
		files.append(a[i].file)
	files.sort()
	assert_array(files).contains_exactly(["a.mp3", "b.mp3", "c.mp3", "d.mp3", "e.mp3"])
	# A playlist too short to have two ends is handed back untouched rather than reordered.
	var pair := p.filtered(true).slice(0, 2)
	assert_int(RadioPlaylist.spread(pair, RunRng.new(1).stream(&"music")).size()).is_equal(2)


## The three numbers this suite judges the played order by, bounded by literals.
##
## `MOOD_MIN_STEP` is what the reordering asks for and the other two are what it achieves; all
## three are floors, and lowering any of them lets the order slide back toward a plain shuffle,
## where half the track changes a player hears move the dungeon by less than a third of what
## the calm-versus-loud measurement advertises. The mechanism has teeth - dropping
## `MOOD_MIN_STEP` to 0 makes `spread` a no-op and both measured floors fail at once.
func test_the_adjacent_mood_numbers_are_guarantees_not_variables() -> void:
	(
		assert_float(RadioPlaylist.MOOD_MIN_STEP)
		. override_failure_message(
			(
				(
					"MOOD_MIN_STEP is %.2f: under 0.30 the next track is allowed to be nearly "
					+ "as calm or as loud as this one and the change stops being visible"
				)
				% RadioPlaylist.MOOD_MIN_STEP
			)
		)
		. is_greater_equal(0.30)
	)
	assert_float(MIN_MEAN_MOOD_STEP).is_greater_equal(0.45)
	assert_float(MIN_TENTH_MOOD_STEP).is_greater_equal(0.25)
