## Music playback (autoload `Music`): two players on the Music bus with a 1.5 s crossfade,
## radio playlist / boss / menu modes, ducking, per-frame spectrum bands, beat detection and a
## rolling energy estimate feeding `MusicProfile` for generation. Works under the Dummy audio
## driver (headless): every audio-server lookup is null-guarded.
##
## `energy` is a *relative* measure (see `MusicAnalysis`): a short loudness average against the
## track's own rolling baseline. It used to be an absolute 30 s RMS, which measured the
## mastering engineer rather than the music - every bundled radio track sat at 0.71 - so the
## generation lever it feeds could not move a floor. It is also what drives the music lights
## (`MusicReactiveLayer`), slowly and never on the beat.
##
## `floor_log()` records what the music was doing at each `profile()` call, i.e. each time a
## floor was generated, so the floor banner and the run summary can say what the music did to
## the run instead of only naming the songs (`floor_banner()`, `MusicLevers`).
##
## The playlist order is shuffled once per run (seeded from `EventBus.run_started`) and survives
## boss/menu interruptions: `play_playlist()` resumes at the next unplayed track instead of
## restarting, and is a no-op while the playlist is already playing.
class_name MusicManager
extends Node

enum Mode { STOPPED, PLAYLIST, BOSS, MENU, CUSTOM }

const CROSSFADE := 1.5
const FADE_IN := 0.4
const DUCK_TIME := 0.3
const FALLBACK_DIR := "res://assets/music/fallback/"
const FALLBACK_FILES: Array[String] = ["arpeggio_run.wav", "bass_crawl.wav", "drum_cave.wav"]
const FALLBACK_TITLES: Array[String] = ["Arpeggio Run", "Bass Crawl", "Drum Cave"]
const FALLBACK_ARTIST := "Omadungeon"
## Music toast duration.
const TOAST_SECONDS := 3.5
## Debug/capture levers (user args, see `GameState.cli_args`): `--music-energy <0..1>` pins the
## energy and `--music-bpm <n>` pins the tempo the floor profile reports (and emits a metronome
## on `EventBus.music_beat`), so the rendered checks can build a floor to a chosen track under
## the headless Dummy driver, which produces no spectrum at all.
const ARG_ENERGY := "music-energy"
const ARG_BPM := "music-bpm"
## `--music-track <file>` starts the playlist on that bundled track, so a capture can be taken
## under a chosen mood (`MusicMood`) rather than whichever track the shuffle dealt.
const ARG_TRACK := "music-track"
## Metadata key marking an enemy the live mood has already reached (once per enemy).
const LIVE_MOOD_META := &"music_live_mood"
## How often GameState.settings is re-read (seconds). Nothing in the project reliably emits
## `EventBus.settings_changed`, so the settings that change playback are polled as well.
const SETTINGS_POLL := 0.25

## Emit a toast ("title - artist") on every track change. Off by default: the HUD renders
## `music_track_changed` itself; turn on only for scenes without a HUD.
var announce_tracks: bool = false
## Analysis and reactive-light tunables (`data/music/music_analysis.tres`).
var tuning: MusicAnalysis = null
## Debug/test hook: when `x >= 0` these values replace the analyzer bands (bass, mid, high).
var band_override: Vector3 = Vector3(-1.0, -1.0, -1.0)
var mode: Mode = Mode.STOPPED
## Latest spectrum band magnitudes (linear, normalised by the player gain; 0 when silent/headless).
var bass: float = 0.0
var mid: float = 0.0
var high: float = 0.0
## Loudness right now against the track's own baseline, 0..1. 0.5 means "as loud as this
## track usually is"; a breakdown falls, a drop rises. 0.5 until anything has been heard.
var energy: float = 0.5
var beat := BeatDetector.new()
var playlist: RadioPlaylist = null
var current_track: RadioTrack = null
var current_title: String = ""
var current_artist: String = ""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _gains: Array[float] = [0.0, 0.0]
var _duck_gain: float = 1.0
var _fade_tween: Tween = null
var _duck_tween: Tween = null
## Queue of the current mode (playlist order, boss subset or the single menu track).
var _queue: Array[RadioTrack] = []
var _queue_pos: int = 0
## Interrupted playlist order/position, restored by `play_playlist()` after boss/menu/stop.
var _playlist_queue: Array[RadioTrack] = []
var _playlist_pos: int = 0
## True when the playlist order must be rebuilt (new seed, never built yet).
var _queue_dirty: bool = true
## Consumed only by `_build_queue()` so the per-run track order depends on the seed alone.
var _shuffle_rng := RandomNumberGenerator.new()
## Incidental picks (boss subset, menu fallback) draw from here, never from `_shuffle_rng`.
var _pick_rng := RandomNumberGenerator.new()
var _analyzer: AudioEffectSpectrumAnalyzerInstance = null
## Exponential means of the band power, short ("now") and long ("this track usually").
## -1 = nothing heard since the last track change.
var _short_power: float = -1.0
var _long_power: float = -1.0
var _energy_samples: int = 0
var _energy_accum: float = 0.0
var _energy_accum_count: int = 0
var _energy_timer: float = 0.0
var _lyrics: Array[Dictionary] = []
var _lyrics_synced: bool = false
var _time: float = 0.0
var _fallback_index: int = -1
var _track_count: int = 0
var _tracks_played: Array[String] = []
## Active duck requests (0..1 depths); the deepest one wins so overlapping UIs nest correctly.
var _ducks: Array[float] = []
var _settings_poll: float = 0.0
## What the music was doing at every `profile()` call, i.e. once per floor generated.
var _floor_log: Array[Dictionary] = []
var _lights: MusicReactiveLayer = null
## The mood of the track playing now (`MusicMood`), silent when nothing is.
var _mood: MusicMood = MusicMood.silent()
## `--music-energy` / `--music-bpm`: a pinned energy and a metronome for rendered captures.
var _sim_energy: float = -1.0
var _sim_bpm: float = 0.0
var _sim_next_beat: float = 0.0
var _sim_track: String = ""
## True between `run_started` and `run_ended`; gates the reactive lights.
var _run_live: bool = false
var _explicit_seen: bool = true
var _ordered_seen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioManager.ensure_buses()
	if tuning == null:
		tuning = MusicAnalysis.load_default()
	beat.threshold = tuning.beat_threshold
	beat.min_interval = tuning.beat_min_interval
	beat.window = tuning.beat_window
	_read_debug_args()
	_shuffle_rng.randomize()
	_pick_rng.randomize()
	_explicit_seen = RadioPlaylist.explicit_allowed()
	_ordered_seen = bool(GameState.settings.get("music_playlist_order", false))
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = AudioManager.BUS_MUSIC
		p.volume_db = -80.0
		add_child(p)
		p.finished.connect(_on_player_finished.bind(i))
		_players.append(p)
	_acquire_analyzer()
	if playlist == null:
		playlist = RadioPlaylist.load_default()
	_lights = MusicReactiveLayer.new()
	_lights.tuning = tuning
	add_child(_lights)
	EventBus.music_duck.connect(_on_music_duck)
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.run_started.connect(set_shuffle_seed)
	EventBus.run_started.connect(_on_run_started_lights)
	EventBus.run_ended.connect(_on_run_ended_lights)
	EventBus.room_entered.connect(_on_room_entered)


func _process(delta: float) -> void:
	_time += delta
	_settings_poll += delta
	if _settings_poll >= SETTINGS_POLL:
		_settings_poll = 0.0
		_poll_settings()
	var playing := is_playing()
	# Spectrum magnitudes are read after the players' volume (crossfade + duck), so undo that
	# gain to keep bands/energy about the music rather than the UI state.
	var gain := clampf(_gains[_active] * _duck_gain, 0.25, 1.0) if playing else 1.0
	var analysing := playing and _gains[_active] * _duck_gain >= tuning.analysis_min_gain
	if band_override.x >= 0.0:
		bass = band_override.x
		mid = maxf(band_override.y, 0.0)
		high = maxf(band_override.z, 0.0)
		analysing = true
	elif _analyzer != null and playing:
		bass = _analyzer.get_magnitude_for_frequency_range(60.0, 250.0).length() / gain
		mid = _analyzer.get_magnitude_for_frequency_range(250.0, 2000.0).length() / gain
		high = _analyzer.get_magnitude_for_frequency_range(2000.0, 8000.0).length() / gain
	else:
		bass = lerpf(bass, 0.0, minf(1.0, delta * 10.0))
		mid = lerpf(mid, 0.0, minf(1.0, delta * 10.0))
		high = lerpf(high, 0.0, minf(1.0, delta * 10.0))
	if analysing and beat.feed(bass, _time):
		EventBus.music_beat.emit(beat.last_strength())
	if analysing:
		_energy_accum += bass * bass + mid * mid + high * high
		_energy_accum_count += 1
		_energy_timer += delta
		if _energy_timer >= tuning.sample_interval:
			_energy_timer = 0.0
			_push_energy(_energy_accum / float(maxi(_energy_accum_count, 1)))
			_energy_accum = 0.0
			_energy_accum_count = 0
	_tick_debug_sim(delta)


# --- playback control ---------------------------------------------------------------------


## Seeds the per-run shuffle so a run replays the same track order. Connected to
## `EventBus.run_started`; also resets the "tracks played" list of the run summary.
func set_shuffle_seed(seed_value: int) -> void:
	_shuffle_rng.seed = seed_value
	_pick_rng.seed = seed_value ^ 0x5f5e
	_queue_dirty = true
	_playlist_queue = []
	_playlist_pos = 0
	_tracks_played = []
	_floor_log = []
	_reset_energy_baseline()


## Starts (or resumes) the radio playlist. No-op while the playlist is already playing; after
## a boss/menu interruption it continues with the next unplayed track. Shuffled per run, or in
## playlist order when `settings.music_playlist_order` is true; chiptune fallback when empty.
func play_playlist() -> void:
	if mode == Mode.PLAYLIST and is_playing() and not _queue_dirty:
		return
	var resuming := mode != Mode.PLAYLIST and not _queue_dirty and not _playlist_queue.is_empty()
	mode = Mode.PLAYLIST
	_refresh_lights()
	if resuming:
		_queue = _playlist_queue
		_queue_pos = (_playlist_pos + 1) % _queue.size()
		if _queue_pos == 0:
			_queue = _build_queue()
	else:
		_queue = _build_queue()
		_queue_pos = 0
	_playlist_queue = []
	_queue_dirty = false
	_play_queue_head()


## Plays a track from the boss subset ("Oligarchy" titles); loops the subset on finish.
func play_boss() -> void:
	if mode == Mode.BOSS and is_playing():
		return
	_leave_playlist()
	mode = Mode.BOSS
	_refresh_lights()
	var candidates := _available(playlist.boss_tracks(RadioPlaylist.explicit_allowed()))
	if candidates.is_empty():
		candidates = _available(playlist.playable())
	if candidates.is_empty():
		_play_fallback((_fallback_index + 1) % FALLBACK_FILES.size())
		return
	_queue = candidates
	_queue_pos = _pick_rng.randi_range(0, candidates.size() - 1)
	_play_queue_head()


## Plays the class menu track (Oligarch: "public code, private yacht"); random track otherwise.
func play_menu(class_id: StringName) -> void:
	var track := playlist.menu_track(class_id)
	if mode == Mode.MENU and is_playing() and track != null and current_track == track:
		return
	_leave_playlist()
	mode = Mode.MENU
	_refresh_lights()
	if track == null or not playlist.has_track_file(track):
		var candidates := _available(playlist.playable())
		if candidates.is_empty():
			_play_fallback(0)
			return
		track = candidates[_pick_rng.randi_range(0, candidates.size() - 1)]
	_queue = [track]
	_queue_pos = 0
	_play_queue_head()


## Plays an arbitrary stream (tests, jingles). Mode becomes CUSTOM; no auto-advance.
func play_stream(stream: AudioStream, title: String = "", artist: String = "") -> void:
	_leave_playlist()
	mode = Mode.CUSTOM
	_refresh_lights()
	if _start_stream(stream, title, artist):
		current_track = null
		_lyrics = []
		_lyrics_synced = false


## Skips to the next track of the current queue (playlist/boss) or the next fallback loop.
func next() -> void:
	if _queue.is_empty():
		if mode == Mode.PLAYLIST or mode == Mode.BOSS:
			_play_fallback((_fallback_index + 1) % FALLBACK_FILES.size())
		return
	_queue_pos = (_queue_pos + 1) % _queue.size()
	if mode == Mode.PLAYLIST and _queue_pos == 0:
		_queue = _build_queue()
	_play_queue_head()


## Fades out and stops. `fade` seconds (0 = immediate). The playlist position is kept so a
## later `play_playlist()` resumes.
func stop(fade: float = CROSSFADE) -> void:
	_leave_playlist()
	mode = Mode.STOPPED
	_refresh_lights()
	current_track = null
	current_title = ""
	current_artist = ""
	_lyrics = []
	_mood = MusicMood.silent()
	if _lights != null:
		_lights.set_mood(_mood)
	_reset_energy_baseline()
	_kill_fade()
	if fade <= 0.0:
		for i in 2:
			_gains[i] = 0.0
			_players[i].stop()
		_apply_gains()
		return
	_fade_tween = create_tween().set_parallel(true)
	for i in 2:
		_fade_tween.tween_method(_set_gain.bind(i), _gains[i], 0.0, fade)
	_fade_tween.chain().tween_callback(
		func() -> void:
			for p in _players:
				p.stop()
	)


## True when the active player is producing sound.
func is_playing() -> bool:
	return _players.size() == 2 and _players[_active].playing


## Playback position (seconds) of the active player.
func playback_position() -> float:
	if not is_playing():
		return 0.0
	return _players[_active].get_playback_position()


## Length (seconds) of the current stream (0 when unknown).
func track_length() -> float:
	var stream := _players[_active].stream if _players.size() == 2 else null
	return stream.get_length() if stream != null else 0.0


## Number of track switches so far (diagnostics/tests).
func track_count() -> int:
	return _track_count


## Titles ("title - artist") heard since the run started, in order, for the run summary.
func tracks_played() -> Array[String]:
	return _tracks_played.duplicate()


## Puts a saved run's track list back after `set_shuffle_seed()` cleared it, so the run
## summary of a resumed run still lists what the player heard before the relaunch.
func restore_tracks(titles: Array[String]) -> void:
	_tracks_played = titles.duplicate()


## Snapshot for floor generation (docs §10.2). Silent profile when stopped or fading out.
##
## This is called exactly once per floor built (`FloorRestore.gen_params_for`), so it is also
## where the floor log is written: the run summary needs to be able to say *what the music did*
## to this run, and until now the only record was a flat list of song titles with no connection
## to anything the player saw.
func profile() -> MusicProfile:
	var p := MusicProfile.new()
	if mode == Mode.STOPPED or not is_playing():
		_record_floor(p, false)
		return p
	p.energy = energy
	p.tempo = _sim_bpm if _sim_bpm > 0.0 else beat.bpm()
	p.track_hash = current_track.track_hash() if current_track != null else hash(current_title)
	p.title = current_title
	p.artist = current_artist
	_record_floor(p, true)
	return p


## What the music was doing when each floor was generated, oldest first. Entries:
## `{floor: int, title: String, artist: String, energy: float, tempo: float, playing: bool}`.
func floor_log() -> Array[Dictionary]:
	return _floor_log.duplicate(true)


## Puts a saved run's floor log back after `set_shuffle_seed()` cleared it, so a resumed run's
## summary still reports the floors it played through before the relaunch.
func restore_floor_log(entries: Array) -> void:
	_floor_log = []
	for entry: Variant in entries:
		if entry is Dictionary:
			_floor_log.append((entry as Dictionary).duplicate(true))


## The music light layer this manager owns (null before `_ready()`).
func lights() -> MusicReactiveLayer:
	return _lights


## The mood of the track playing now: measured per file (docs 10.2), silent when nothing is.
func mood() -> MusicMood:
	return _mood


## The mood in words for the now-playing banner - "brooding, slow" - or "" when silent.
func mood_words() -> String:
	if _mood.is_silent() or mode == Mode.STOPPED or not is_playing():
		return ""
	return _mood.words_line()


## The look the lights are applying this frame (`MusicMoodState`, neutral when off).
func mood_state() -> MusicMoodState:
	return _lights.state() if _lights != null else MusicMoodState.neutral()


## Multiplier on the keenness of the enemies in the *next* room the player enters
## (`MusicLevers.live_aggression`): 1.0 in silence, 0.9 under the calmest track, 1.1 under
## the loudest. Never applied mid-fight - see `_on_room_entered`.
func live_aggression() -> float:
	if mode == Mode.STOPPED or not is_playing() or _mood.is_silent():
		return 1.0
	return MusicLevers.shared().live_aggression(_mood.energy)


## Plays the bundled track whose file name is `file` as the head of the playlist, keeping
## playlist mode so the queue continues from it. False when the playlist has no such file.
## For captures and tests that need a *chosen* mood; the shuffle is left alone otherwise.
func play_track_file(file: String) -> bool:
	var track := playlist.find_by_file(file)
	if track == null or not playlist.has_track_file(track):
		return false
	if mode != Mode.PLAYLIST or _queue_dirty or _queue.is_empty():
		_leave_playlist()
		mode = Mode.PLAYLIST
		_refresh_lights()
		_queue = _build_queue()
		_queue_dirty = false
		_playlist_queue = []
	var index := _queue.find(track)
	if index == -1:
		_queue.insert(0, track)
		index = 0
	_queue_pos = index
	_play_queue_head()
	return true


## The floor-start line for 0-based floor `index`, from what the log recorded when that floor
## was generated: "Built to Super Space - dense, fast and bright". "" for a floor the log
## never saw (a resumed run's earlier floors).
func floor_banner(index: int) -> String:
	for entry: Dictionary in _floor_log:
		if int(entry.get("floor", 0)) == index + 1:
			return MusicLevers.shared().banner(
				str(entry.get("title", "")),
				float(entry.get("energy", 0.5)),
				float(entry.get("tempo", 0.0)),
				bool(entry.get("playing", false))
			)
	return ""


## Adds (or replaces) this floor's entry. The floor number comes from `GameState.floor_index`,
## which `RunManager._build_floor` sets on the line before it asks for the profile, so a floor
## rebuilt by a resume overwrites its own entry instead of appending a duplicate.
func _record_floor(p: MusicProfile, playing: bool) -> void:
	var entry := {
		"floor": GameState.floor_index + 1,
		"title": p.title,
		"artist": p.artist,
		"energy": p.energy,
		"tempo": p.tempo,
		"playing": playing,
	}
	for i in _floor_log.size():
		if int(_floor_log[i]["floor"]) == int(entry["floor"]):
			_floor_log[i] = entry
			return
	_floor_log.append(entry)


## Current lyric line for the pause screen ("" when none). Unsynced lyrics are spread
## evenly over the track length.
func current_lyric() -> String:
	if _lyrics.is_empty() or not is_playing():
		return ""
	if not bool(GameState.settings.get("lyrics", true)):
		return ""
	var pos := playback_position()
	if _lyrics_synced:
		var text := ""
		for line in _lyrics:
			if float(line["time"]) <= pos:
				text = str(line["text"])
			else:
				break
		return text
	var length := track_length()
	if length <= 0.0:
		return str(_lyrics[0]["text"])
	var idx := clampi(int(pos / length * float(_lyrics.size())), 0, _lyrics.size() - 1)
	return str(_lyrics[idx]["text"])


## All parsed lyric lines of the current track.
func lyric_lines() -> Array[Dictionary]:
	return _lyrics


## Current duck gain (1 = not ducked).
func duck_gain() -> float:
	return _duck_gain


# --- internals ---------------------------------------------------------------------------


## Remembers the playlist order/position when another mode takes over.
func _leave_playlist() -> void:
	if mode == Mode.PLAYLIST and not _queue.is_empty():
		_playlist_queue = _queue
		_playlist_pos = _queue_pos


func _build_queue() -> Array[RadioTrack]:
	var ordered := bool(GameState.settings.get("music_playlist_order", false))
	var allow := RadioPlaylist.explicit_allowed()
	var tracks := playlist.filtered(allow) if ordered else playlist.shuffle(_shuffle_rng, allow)
	var out := _available(tracks)
	if not ordered:
		# Shuffled order deals adjacent moods at random, and half of the track changes a player
		# hears then move the look by almost nothing (`RadioPlaylist.MOOD_MIN_STEP`). Spread
		# after the availability filter, so the steps are between tracks that will really play.
		out = RadioPlaylist.spread(out, _shuffle_rng)
	if not _sim_track.is_empty():
		# The pinned capture track goes first; the rest of the order is the seed's as before.
		for i in out.size():
			if out[i].file == _sim_track:
				var pinned := out[i]
				out.remove_at(i)
				out.insert(0, pinned)
				break
	return out


func _available(tracks: Array[RadioTrack]) -> Array[RadioTrack]:
	var out: Array[RadioTrack] = []
	for t in tracks:
		if playlist.has_track_file(t):
			out.append(t)
	return out


func _play_queue_head() -> void:
	if _queue.is_empty():
		_play_fallback((_fallback_index + 1) % FALLBACK_FILES.size())
		return
	var track := _queue[_queue_pos]
	var stream := _load_track(track)
	if stream == null:
		_queue.remove_at(_queue_pos)
		if _queue.is_empty():
			_play_fallback((_fallback_index + 1) % FALLBACK_FILES.size())
			return
		_queue_pos = _queue_pos % _queue.size()
		_play_queue_head()
		return
	if _start_stream(stream, track.title, track.artist, track.file):
		current_track = track
		_lyrics = playlist.lyrics_for(track)
		_lyrics_synced = RadioPlaylist.lyrics_synced(_lyrics)


func _play_fallback(index: int) -> void:
	if FALLBACK_FILES.is_empty():
		return
	_fallback_index = posmod(index, FALLBACK_FILES.size())
	var path := FALLBACK_DIR + FALLBACK_FILES[_fallback_index]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		push_warning("MusicManager: no radio tracks and no fallback loop at %s" % path)
		return
	stream = _looping_copy(stream)
	if _start_stream(stream, FALLBACK_TITLES[_fallback_index], FALLBACK_ARTIST):
		current_track = null
		_lyrics = []
		_lyrics_synced = false


## Returns a private copy of a WAV stream set to loop over its whole length. The importer
## leaves loop_end at 0 when the WAV has no loop chunk, and a forward loop with loop_end 0
## finishes on the first mix, so the end is derived from the length here.
static func _looping_copy(stream: AudioStream) -> AudioStream:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return stream
	var copy := wav.duplicate() as AudioStreamWAV
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = maxi(int(round(wav.get_length() * float(wav.mix_rate))), 1)
	return copy


func _load_track(track: RadioTrack) -> AudioStream:
	var path := playlist.track_path(track)
	if ResourceLoader.exists(path):
		var res := load(path) as AudioStream
		if res != null:
			return res
	if FileAccess.file_exists(path):
		match path.get_extension().to_lower():
			"mp3":
				return AudioStreamMP3.load_from_file(path)
			"wav":
				return AudioStreamWAV.load_from_file(path)
			"ogg":
				return AudioStreamOggVorbis.load_from_file(path)
	push_warning("MusicManager: cannot load %s" % path)
	return null


## Crossfades to `stream`. Returns false when nothing was started (null stream, or the same
## title is already playing), so callers only commit `current_track`/lyrics on true.
func _start_stream(stream: AudioStream, title: String, artist: String, file: String = "") -> bool:
	if stream == null:
		return false
	if mode != Mode.CUSTOM and is_playing() and title == current_title and not title.is_empty():
		return false
	var old := _active
	var new_index := 1 - _active
	_active = new_index
	var player := _players[new_index]
	_kill_fade()
	player.stop()
	player.stream = stream
	_gains[new_index] = 0.0
	_apply_gains()
	player.play()
	_fade_tween = create_tween().set_parallel(true)
	var fade := CROSSFADE if _players[old].playing else FADE_IN
	_fade_tween.tween_method(_set_gain.bind(new_index), 0.0, 1.0, fade)
	if _players[old].playing:
		_fade_tween.tween_method(_set_gain.bind(old), _gains[old], 0.0, CROSSFADE)
		_fade_tween.chain().tween_callback(_players[old].stop)
	current_title = title
	current_artist = artist
	beat.reset()
	_reset_short_window()
	_track_count += 1
	# The mood is a property of the file, so it is known the instant the track starts; the
	# lights crossfade to it from here (docs 10.2), no floor rebuild involved.
	_mood = MusicMood.for_file(file, title)
	if _lights != null:
		_lights.set_mood(_mood)
	var label := "%s - %s" % [title, artist] if not artist.is_empty() else title
	if not label.is_empty() and (_tracks_played.is_empty() or _tracks_played.back() != label):
		_tracks_played.append(label)
	EventBus.music_track_changed.emit(title, artist)
	if announce_tracks and not title.is_empty():
		EventBus.toast.emit(label, TOAST_SECONDS)
	return true


func _set_gain(value: float, index: int) -> void:
	_gains[index] = value
	_apply_gains()


func _apply_gains() -> void:
	for i in _players.size():
		var g := clampf(_gains[i] * _duck_gain, 0.0, 1.0)
		_players[i].volume_db = linear_to_db(maxf(g, 0.0001))


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _on_player_finished(index: int) -> void:
	if index != _active:
		return
	match mode:
		Mode.PLAYLIST, Mode.BOSS:
			next()
		Mode.MENU:
			_players[index].play()
		_:
			pass


## Ducks nest: every `on=true` pushes a depth and the matching `on=false` pops it, so the
## music only returns to full volume once the last requester (chest UI, pause menu, ...)
## released it. An unbalanced release pops the newest entry rather than sticking forever.
func _on_music_duck(amount: float, on: bool) -> void:
	var depth := clampf(amount, 0.0, 1.0)
	if on:
		_ducks.append(depth)
	elif not _ducks.is_empty():
		var idx := _ducks.find(depth)
		_ducks.remove_at(idx if idx != -1 else _ducks.size() - 1)
	var deepest := 0.0
	for d in _ducks:
		deepest = maxf(deepest, d)
	var target := 1.0 - deepest
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck, _duck_gain, target, DUCK_TIME)


func _set_duck(value: float) -> void:
	_duck_gain = value
	_apply_gains()


func _on_run_started_lights(_run_seed: int) -> void:
	_run_live = true
	_refresh_lights()


func _on_run_ended_lights(_victory: bool) -> void:
	_run_live = false
	_refresh_lights()


## The live gameplay nudge (docs 10.2): the enemies of the room the player has just walked
## into get the current track's aggression multiplier on sight, move speed and attack
## cadence, once each, at the moment they wake. Never a room the player is already in, never
## an enemy that has already been nudged, never a boss - so a track change can never alter a
## fight in progress, only the next one.
func _on_room_entered(room_id: int) -> void:
	if not _run_live or room_id < 0:
		return
	var factor := live_aggression()
	var tree := get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy == null or enemy.room_id != room_id or enemy.has_meta(LIVE_MOOD_META):
			continue
		if enemy.def == null or enemy.def.is_boss:
			continue
		enemy.set_meta(LIVE_MOOD_META, factor)
		if is_equal_approx(factor, 1.0):
			continue
		enemy.set_mood(enemy.mood_sight * factor, enemy.mood_cadence / factor, enemy.mood_loot)
		enemy.stats.add_percent(&"move_speed", LIVE_MOOD_META, factor - 1.0)


## The vignette belongs to the dungeon, not to the menus: it is on while a run is live and the
## radio or the boss track is playing, and off everywhere else.
func _refresh_lights() -> void:
	if _lights == null:
		return
	_lights.set_active(_run_live and (mode == Mode.PLAYLIST or mode == Mode.BOSS))


## Explicit filter toggled: rebuild the upcoming playlist order (either direction) and keep the
## current track unless it is now disallowed.
func _on_settings_changed(key: String) -> void:
	if key != "explicit_music" and key != "music_playlist_order":
		return
	_explicit_seen = RadioPlaylist.explicit_allowed()
	_ordered_seen = bool(GameState.settings.get("music_playlist_order", false))
	if mode != Mode.PLAYLIST:
		# Forget the interrupted order so the playlist is rebuilt when it resumes.
		_playlist_queue = []
		return
	var allowed := RadioPlaylist.explicit_allowed()
	_queue = _build_queue()
	if current_track != null and current_track.explicit and not allowed:
		_queue_pos = 0
		_play_queue_head()
		return
	_queue_pos = maxi(_queue.find(current_track), 0)


## Nothing in the project reliably emits `EventBus.settings_changed`, so the two settings that
## change what plays are polled as well (cheap dictionary reads every SETTINGS_POLL seconds).
func _poll_settings() -> void:
	if RadioPlaylist.explicit_allowed() != _explicit_seen:
		_on_settings_changed("explicit_music")
	elif bool(GameState.settings.get("music_playlist_order", false)) != _ordered_seen:
		_on_settings_changed("music_playlist_order")


func _acquire_analyzer() -> void:
	var music_idx := AudioServer.get_bus_index(AudioManager.BUS_MUSIC)
	var fx_idx := AudioManager.spectrum_effect_index()
	if music_idx == -1 or fx_idx == -1:
		return
	_analyzer = (
		AudioServer.get_bus_effect_instance(music_idx, fx_idx)
		as AudioEffectSpectrumAnalyzerInstance
	)


## Folds one band-power sample into the short and long exponential means and re-derives
## `energy` from the gap between them, in dB.
##
## Measured, with ffmpeg, over five bundled radio tracks: the old absolute mapping (a 30 s RMS
## over -42..-8 dBFS) produced mean energies of 0.713, 0.712, 0.717, 0.715 and 0.713 - a 0.005
## spread across a synthwave mix, a shanty and a punk track, because mastering normalises
## loudness and the window was wider than any music ever gets. The relative measure below gives
## the same five tracks a 0.10..0.81 range and a per-track standard deviation of 0.09-0.19.
##
## The long mean grows at the running-mean rate (but never faster than the short mean), so the
## baseline is the track average while a track is young and settles into a 40 s memory after a
## couple of seconds; without that a quiet intro pins energy at 1.0 for twenty seconds.
func _push_energy(mean_square: float) -> void:
	_energy_samples += 1
	var interval := maxf(tuning.sample_interval, 0.001)
	var a_short := 1.0 - exp(-interval / maxf(tuning.short_window, interval))
	if _short_power < 0.0:
		_short_power = mean_square
	else:
		_short_power += a_short * (mean_square - _short_power)
	if _long_power < 0.0:
		_long_power = mean_square
	else:
		# The baseline catches up at the running-mean rate while the radio is young, but never
		# faster than the short mean: a long window that moves *before* the short one inverts
		# the measure and a drop then reads as a breakdown.
		var a_long := minf(
			maxf(
				1.0 - exp(-interval / maxf(tuning.long_window, interval)),
				1.0 / float(maxi(_energy_samples, 1))
			),
			a_short
		)
		_long_power += a_long * (mean_square - _long_power)
	var short_db := linear_to_db(sqrt(maxf(_short_power, 1e-12)))
	if short_db <= tuning.silence_floor_db:
		energy = 0.0
		return
	var long_db := linear_to_db(sqrt(maxf(_long_power, 1e-12)))
	var span := maxf(tuning.relative_span_db, 0.1)
	energy = clampf(0.5 + (short_db - long_db) / (2.0 * span), 0.0, 1.0)


## A new track restarts the "now" average but keeps the baseline: the player hears one
## continuous radio, so a track that really is quieter than the last one should read calmer
## straight away. Resetting both would put a 2.5 s blind spot - reading a flat 0.5 - at the
## start of every track, which is exactly where floors get generated.
func _reset_short_window() -> void:
	_short_power = -1.0
	_energy_accum = 0.0
	_energy_accum_count = 0
	_energy_timer = 0.0


## Forgets the loudness baseline entirely (new run, radio stopped). `energy` is left where it
## was; the means re-converge over the first couple of seconds of whatever plays next.
func _reset_energy_baseline() -> void:
	_reset_short_window()
	_long_power = -1.0
	_energy_samples = 0


## Reads `--music-energy` / `--music-bpm` off the command line. Both are capture/debug levers:
## the headless Dummy audio driver produces no spectrum at all, so without them a rendered
## check of what the music does to a floor would photograph the silent floor and prove nothing.
func _read_debug_args() -> void:
	var args := GameState.cli_args
	if args.has(ARG_ENERGY):
		_sim_energy = clampf(float(str(args[ARG_ENERGY])), 0.0, 1.0)
		energy = _sim_energy
	if args.has(ARG_BPM):
		_sim_bpm = maxf(float(str(args[ARG_BPM])), 0.0)
	if args.has(ARG_TRACK):
		_sim_track = str(args[ARG_TRACK])


## Holds the pinned energy and emits the metronome when the debug levers are on.
func _tick_debug_sim(delta: float) -> void:
	if _sim_energy >= 0.0:
		energy = _sim_energy
	if _sim_bpm <= 0.0:
		return
	_sim_next_beat -= delta
	if _sim_next_beat > 0.0:
		return
	_sim_next_beat = 60.0 / _sim_bpm
	EventBus.music_beat.emit(1.0)
