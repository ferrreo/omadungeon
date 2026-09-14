## One entry of the Omarchy Radio playlist (title, artist, file, explicit flag, lyrics file).
class_name RadioTrack
extends RefCounted

var title: String = ""
var artist: String = ""
## File name inside assets/music/radio/ (e.g. "cam-omarchy.mp3").
var file: String = ""
var explicit: bool = false
## Lyrics file name inside assets/music/radio/lyrics/, or "" when none.
var lyrics: String = ""


static func from_dict(d: Dictionary) -> RadioTrack:
	var t := RadioTrack.new()
	t.title = str(d.get("title", ""))
	t.artist = str(d.get("artist", ""))
	t.file = str(d.get("file", ""))
	t.explicit = bool(d.get("explicit", false))
	t.lyrics = str(d.get("lyrics", ""))
	return t


## Stable hash of the track identity (used by MusicProfile tie-breaks).
func track_hash() -> int:
	return hash(file if not file.is_empty() else title)


func to_dict() -> Dictionary:
	return {"title": title, "artist": artist, "file": file, "explicit": explicit, "lyrics": lyrics}


func _to_string() -> String:
	return "%s - %s" % [artist, title]
