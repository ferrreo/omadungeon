## Omarchy Radio playlist model: parses playlist.json, filters explicit tracks, shuffles
## deterministically, picks boss/menu subsets and parses .lrc lyrics. Pure data; no audio.
class_name RadioPlaylist
extends RefCounted

const PLAYLIST_PATH := "res://assets/music/radio/playlist.json"
const TRACK_DIR := "res://assets/music/radio/"
const LYRICS_DIR := "res://assets/music/radio/lyrics/"
## Titles containing this word form the boss subset.
const BOSS_KEYWORD := "oligarchy"
## Least a track's measured energy (`MusicMood.energy`) should differ from the one before it in
## the played order, 0..1. This is the number the owner's "the music STILL doesn't seem to do
## anything" turned out to be about, after a round that widened the mapping and measured it.
##
## The mapping was never the problem. The bundled moods are *ranks*, spread evenly across 0..1,
## so a plain shuffle deals adjacent energies at random: the mean step between two tracks a
## player actually hears in a row was 0.355 of the range and the tenth-percentile step was
## 0.080 - nearly half of all track changes moved the look by less than a third of what the
## calmest-versus-loudest measurement promised, and one in ten moved it by essentially nothing.
## A change nobody can see happening is a change nobody believes is there.
##
## `spread()` is the fix, and 0.30 is what it asks for: the next track is drawn at random from
## those at least this far from the current one in energy. Measured over 400 shuffles of the
## bundled 33 that takes the mean step to 0.495 and the tenth percentile to 0.316 - the quiet
## transitions are gone, and the deal is still random rather than a march from calm to loud.
const MOOD_MIN_STEP := 0.30
## Menu track for the Oligarch class.
const OLIGARCH_MENU_TITLE := "public code, private yacht"
const OLIGARCH_CLASS := &"oligarch"

## Directory holding the audio files (tests point this at user://).
var track_dir: String = TRACK_DIR
## Directory holding the .lrc lyrics files.
var lyrics_dir: String = LYRICS_DIR
var station: String = ""
var name: String = ""
var tracks: Array[RadioTrack] = []


## Loads the bundled playlist (empty playlist when the file is absent).
static func load_default() -> RadioPlaylist:
	return load_file(PLAYLIST_PATH)


## Loads a playlist from a JSON file path (res:// or absolute).
static func load_file(path: String) -> RadioPlaylist:
	if not FileAccess.file_exists(path):
		return RadioPlaylist.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return RadioPlaylist.new()
	return from_json_text(file.get_as_text())


## Parses playlist JSON text: {"station", "name", "tracks": [{title, artist, file, explicit?, lyrics?}]}.
static func from_json_text(text: String) -> RadioPlaylist:
	var playlist := RadioPlaylist.new()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return playlist
	var dict: Dictionary = parsed
	playlist.station = str(dict.get("station", ""))
	playlist.name = str(dict.get("name", ""))
	var raw: Variant = dict.get("tracks", [])
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Dictionary:
				var track := RadioTrack.from_dict(entry as Dictionary)
				if not track.file.is_empty() or not track.title.is_empty():
					playlist.tracks.append(track)
	return playlist


## True when GameState allows explicit tracks (defaults to true).
static func explicit_allowed() -> bool:
	return bool(GameState.settings.get("explicit_music", true))


## Tracks passing the explicit filter, in playlist order.
func filtered(allow_explicit: bool) -> Array[RadioTrack]:
	var out: Array[RadioTrack] = []
	for t in tracks:
		if allow_explicit or not t.explicit:
			out.append(t)
	return out


## Tracks allowed by the current settings.
func playable() -> Array[RadioTrack]:
	return filtered(explicit_allowed())


## Tracks allowed by the current settings whose audio file is actually present.
func available() -> Array[RadioTrack]:
	var out: Array[RadioTrack] = []
	for t in playable():
		if has_track_file(t):
			out.append(t)
	return out


## Deterministic Fisher-Yates shuffle of the filtered tracks (same rng state -> same order).
func shuffle(rng: RandomNumberGenerator, allow_explicit: bool = true) -> Array[RadioTrack]:
	var out := filtered(allow_explicit)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## `tracks` reordered so consecutive tracks are far apart in mood: starting from a random one,
## the next is drawn at random from those at least `MOOD_MIN_STEP` from it in measured energy
## (`MusicMood.for_track`), and from the furthest one left when nothing clears the step - which
## is what the last few tracks of a run come down to, once both ends of the range are spent.
##
## So the guarantee is on the shape of the whole order rather than on every single step, and
## that is how `radio_playlist_test` measures it: the mean and the tenth-percentile step over
## the bundled playlist, against the same numbers for a plain shuffle. Deterministic in `rng`,
## like `shuffle()`: the same run seed replays the same order.
static func spread(tracks: Array[RadioTrack], rng: RandomNumberGenerator) -> Array[RadioTrack]:
	var out: Array[RadioTrack] = []
	var pool := tracks.duplicate()
	if pool.size() < 3:
		return pool
	var energies: Array[float] = []
	for t: RadioTrack in pool:
		energies.append(MusicMood.for_track(t).energy)
	var index := rng.randi_range(0, pool.size() - 1)
	var last := energies[index]
	out.append(pool[index])
	pool.remove_at(index)
	energies.remove_at(index)
	while not pool.is_empty():
		var far: Array[int] = []
		var furthest := 0
		var furthest_step := -1.0
		for i in pool.size():
			var step := absf(energies[i] - last)
			if step >= MOOD_MIN_STEP:
				far.append(i)
			if step > furthest_step:
				furthest_step = step
				furthest = i
		var pick := far[rng.randi_range(0, far.size() - 1)] if not far.is_empty() else furthest
		last = energies[pick]
		out.append(pool[pick])
		pool.remove_at(pick)
		energies.remove_at(pick)
	return out


## The step in measured energy between each pair of tracks played in a row: what a player
## actually experiences of the mood mapping, as opposed to its calmest-to-loudest extremes.
static func mood_steps(tracks: Array[RadioTrack]) -> Array[float]:
	var out: Array[float] = []
	for i in range(1, tracks.size()):
		out.append(
			absf(MusicMood.for_track(tracks[i]).energy - MusicMood.for_track(tracks[i - 1]).energy)
		)
	return out


## Boss subset: titles containing "Oligarchy" (case-insensitive), explicit-filtered.
func boss_tracks(allow_explicit: bool = true) -> Array[RadioTrack]:
	var out: Array[RadioTrack] = []
	for t in filtered(allow_explicit):
		if t.title.to_lower().contains(BOSS_KEYWORD):
			out.append(t)
	return out


## Menu track for a class: the Oligarch gets "public code, private yacht"; others get null.
func menu_track(class_id: StringName) -> RadioTrack:
	if class_id != OLIGARCH_CLASS:
		return null
	return find_by_title(OLIGARCH_MENU_TITLE)


## Case-insensitive title lookup.
func find_by_title(title: String) -> RadioTrack:
	var needle := title.to_lower()
	for t in tracks:
		if t.title.to_lower() == needle:
			return t
	return null


## The track whose file name is `file` (case-sensitive: it is a file), or null.
func find_by_file(file: String) -> RadioTrack:
	for t in tracks:
		if t.file == file and not file.is_empty():
			return t
	return null


## Full resource path of a track's audio file.
func track_path(track: RadioTrack) -> String:
	return track_dir + track.file


## True when the audio file for `track` is importable/present.
func has_track_file(track: RadioTrack) -> bool:
	if track == null or track.file.is_empty():
		return false
	var path := track_path(track)
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## Lyrics path for a track: explicit `lyrics` field, else "<file stem>.lrc" if present, else "".
func lyrics_path(track: RadioTrack) -> String:
	if track == null:
		return ""
	if not track.lyrics.is_empty():
		return lyrics_dir + track.lyrics
	var guess := lyrics_dir + track.file.get_basename() + ".lrc"
	if FileAccess.file_exists(guess):
		return guess
	return ""


## Parsed lyrics for a track (empty when none shipped).
func lyrics_for(track: RadioTrack) -> Array[Dictionary]:
	var path := lyrics_path(track)
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	return parse_lrc(file.get_as_text())


## Parses LRC text into [{time: float, text: String}] sorted by time. Lines without a
## timestamp get time -1.0 (unsynced lyrics). Metadata tags like [ar:..] are skipped.
static func parse_lrc(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var re := RegEx.new()
	re.compile("\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]")
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var matches := re.search_all(line)
		if matches.is_empty():
			if line.begins_with("[") and line.ends_with("]") and line.contains(":"):
				continue
			out.append({"time": -1.0, "text": line})
			continue
		var last := matches[matches.size() - 1]
		var body := line.substr(last.get_end()).strip_edges()
		for m in matches:
			var seconds := float(m.get_string(1)) * 60.0 + float(m.get_string(2))
			out.append({"time": seconds, "text": body})
	var timed := out.filter(func(d: Dictionary) -> bool: return float(d["time"]) >= 0.0)
	if timed.size() == out.size():
		out.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"])
		)
	return out


## True when every parsed line carries a timestamp.
static func lyrics_synced(lines: Array[Dictionary]) -> bool:
	if lines.is_empty():
		return false
	for d in lines:
		if float(d["time"]) < 0.0:
			return false
	return true
