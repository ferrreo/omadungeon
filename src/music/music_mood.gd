## What a *track* is like (docs §10.2): its energy, tempo and brightness as measured offline
## by `tools/analyze-radio.py` and shipped in `data/music/track_moods.json`, plus a hue seed
## from the track's identity so two calm tracks still colour the dungeon differently.
##
## Why offline and per track rather than the live analyser: the live `Music.energy` is a
## *relative* number - "louder than this track usually is" - which is the right input for a
## breakdown-versus-drop drift but says nothing about which track is playing, and the owner's
## report was "I still see no difference when the song changes". Under the headless Dummy
## audio driver the live spectrum is nothing at all. The mood of a track is a property of the
## file, so it is measured once and read here by file name; anything not in the table (a
## fallback loop, a custom stream) gets a middling mood derived from its title hash, so
## nothing depends on the table being complete, and silence is exactly neutral.
class_name MusicMood
extends RefCounted

const TABLE_PATH := "res://data/music/track_moods.json"

static var _table: Dictionary = {}
static var _table_loaded: bool = false

## Loudness rank across the bundled set, 0 (calmest) .. 1 (loudest). 0.5 for silence.
var energy: float = 0.5
## Treble share rank across the bundled set, 0 (dark) .. 1 (bright). 0.5 for silence.
var brightness: float = 0.5
## Tempo in BPM, 0 when unknown.
var tempo: float = 0.0
## 0..1 from the track identity: where on the hue circle this track leans, so the mapping can
## tell two tracks of the same energy apart.
var hue_seed: float = 0.5
var title: String = ""
var file: String = ""
## True when the values came from the measured table rather than from a hash.
var measured: bool = false


## The neutral mood: what silence, and a music-lights amount of zero, resolve to.
static func silent() -> MusicMood:
	return MusicMood.new()


## The mood of a playlist track: measured when the table knows its file, hashed otherwise.
static func for_track(track: RadioTrack) -> MusicMood:
	if track == null:
		return silent()
	return for_file(track.file, track.title)


## The mood of a track by file name and title. A file the table has not measured (or an
## empty one - a custom stream) gets a middling mood from the title hash: energy inside
## 0.35..0.65, so a track nobody measured can never be the calmest or the loudest thing the
## dungeon has seen, and a stable hue seed.
static func for_file(file_name: String, track_title: String) -> MusicMood:
	var mood := MusicMood.new()
	mood.file = file_name
	mood.title = track_title
	var key := file_name if not file_name.is_empty() else track_title
	mood.hue_seed = seed_for(key)
	var row: Variant = _rows().get(file_name, null)
	if row is Dictionary:
		var d := row as Dictionary
		mood.energy = clampf(float(d.get("energy", 0.5)), 0.0, 1.0)
		mood.brightness = clampf(float(d.get("brightness", 0.5)), 0.0, 1.0)
		mood.tempo = maxf(float(d.get("tempo", 0.0)), 0.0)
		mood.measured = true
		return mood
	if key.is_empty():
		return mood
	var h := hash(key + "|energy")
	mood.energy = 0.35 + 0.3 * float(h % 1000) / 999.0
	mood.brightness = 0.35 + 0.3 * float(hash(key + "|bright") % 1000) / 999.0
	return mood


## The track's own live energy at its quietest, typical and loudest sustained passages, as
## `tools/analyze-radio.py` measured them by mirroring `MusicManager._push_energy` over the
## real waveform. Empty when the table has not measured this file.
##
## These are what "what is happening over the current track" is, as numbers: 0.5 is as loud as
## this track usually is. A rendered capture injects them because the headless audio driver
## produces no spectrum at all, so the alternative is a number somebody picked - these at least
## are the track's own.
static func live_points(file_name: String) -> PackedFloat32Array:
	var row: Variant = _rows().get(file_name, null)
	if row is not Dictionary:
		return PackedFloat32Array()
	var d := row as Dictionary
	if not d.has("live_quiet") or not d.has("live_loud"):
		return PackedFloat32Array()
	return PackedFloat32Array(
		[float(d["live_quiet"]), float(d.get("live_mid", 0.5)), float(d["live_loud"])]
	)


## The bundled file whose own quiet and loud passages sit furthest apart - the track to
## photograph when the question is "does one track breathe", rather than the calmest or the
## loudest, which answer a different question.
static func widest_live_file() -> String:
	var best := ""
	var best_span := -1.0
	for file_name: String in measured_files():
		var points := live_points(file_name)
		if points.size() < 3:
			continue
		var span := points[2] - points[0]
		if span > best_span:
			best_span = span
			best = file_name
	return best


## Where on the hue circle a track leans, 0..1, from its identity alone. Stable across runs
## and machines: `hash()` of a String is the engine's own string hash.
static func seed_for(key: String) -> float:
	if key.is_empty():
		return 0.5
	return float(hash(key) % 4096) / 4095.0


## File names the table has measured, sorted. Tests and capture tooling pick the calmest and
## loudest bundled tracks from this rather than hard-coding titles that a re-sync may drop.
static func measured_files() -> PackedStringArray:
	var out := PackedStringArray(_rows().keys())
	out.sort()
	return out


## The measured file with the lowest (`loudest == false`) or highest energy; "" when the table
## is empty.
static func extreme_file(loudest: bool) -> String:
	var best := ""
	var best_energy := -1.0 if loudest else 2.0
	for file_name: String in measured_files():
		var row := _rows()[file_name] as Dictionary
		var e := float(row.get("energy", 0.5))
		if (loudest and e > best_energy) or (not loudest and e < best_energy):
			best_energy = e
			best = file_name
	return best


## This mood with its energy moved to `value`, everything else kept. The live envelope
## (`MusicReactiveLayer`) uses it to ask "what would this same track look like if it were this
## loud right now" - the track's identity, brightness and hue seed stay put, so a quiet passage
## of a fierce track is still that track, shown quieter.
func at_energy(value: float) -> MusicMood:
	var out := MusicMood.new()
	out.energy = clampf(value, 0.0, 1.0)
	out.brightness = brightness
	out.tempo = tempo
	out.hue_seed = hue_seed
	out.title = title
	out.file = file
	out.measured = measured
	return out


## True when this mood is the silent one: nothing playing, or nothing known.
func is_silent() -> bool:
	return file.is_empty() and title.is_empty()


## The mood in two or three words - "brooding, slow", "fierce, fast and bright" - for the
## now-playing banner. Energy always gets a word; pace and brightness only when they are
## remarkable, so the line stays short enough for the radio lane.
func words(levers: MusicMoodLevers = null) -> PackedStringArray:
	var l := levers if levers != null else MusicMoodLevers.shared()
	var out: PackedStringArray = [l.energy_word(energy)]
	var pace := MusicLevers.shared().pace_word(tempo)
	if not pace.is_empty():
		out.append(pace)
	var shade := l.brightness_word(brightness)
	if not shade.is_empty():
		out.append(shade)
	return out


## `words()` joined for a banner: "brooding, slow and dark".
func words_line(levers: MusicMoodLevers = null) -> String:
	var w := words(levers)
	if w.size() <= 1:
		return "".join(w)
	var head: PackedStringArray = w.slice(0, w.size() - 1)
	return "%s and %s" % [", ".join(head), w[w.size() - 1]]


func to_dict() -> Dictionary:
	return {
		"energy": energy,
		"brightness": brightness,
		"tempo": tempo,
		"hue_seed": hue_seed,
		"title": title,
		"file": file,
		"measured": measured,
	}


func _to_string() -> String:
	return (
		"MusicMood(%s, energy=%.2f, brightness=%.2f, tempo=%.0f, hue=%.2f)"
		% [title, energy, brightness, tempo, hue_seed]
	)


## The measured rows, keyed by file name, loaded once. A missing or malformed table is an
## empty one: every track then reads as its hashed middling mood, and nothing errors.
static func _rows() -> Dictionary:
	if _table_loaded:
		return _table
	_table_loaded = true
	_table = {}
	if not FileAccess.file_exists(TABLE_PATH):
		return _table
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		return _table
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var rows: Variant = (parsed as Dictionary).get("tracks", {})
		if rows is Dictionary:
			_table = rows as Dictionary
	return _table
