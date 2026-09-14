## Snapshot of the music state used as a generation input (docs §10.2): energy 0..1,
## tempo (BPM estimate, 0 when unknown), a stable track hash and the track title.
class_name MusicProfile
extends RefCounted

## Rolling RMS energy, 0..1.
var energy: float = 0.5
## Estimated BPM (0 = unknown).
var tempo: float = 0.0
## Stable hash of the track file/title (0 when silent).
var track_hash: int = 0
var title: String = ""
var artist: String = ""


## Profile for "nothing playing": mid energy, no tempo, hash 0.
static func silent() -> MusicProfile:
	return MusicProfile.new()


## Tempo folded to a 0..1 range (70 BPM -> 0, 180 BPM -> 1); 0.5 when unknown.
func tempo_normalized() -> float:
	if tempo <= 0.0:
		return 0.5
	return clampf((tempo - 70.0) / 110.0, 0.0, 1.0)


## Multiplier for the enemy count: `MusicLevers.foes_calm` at energy 0, `foes_loud` at 1.
func density_multiplier() -> float:
	return MusicLevers.shared().foes_scale(energy)


func to_dict() -> Dictionary:
	return {
		"energy": energy,
		"tempo": tempo,
		"track_hash": track_hash,
		"title": title,
		"artist": artist,
	}


static func from_dict(d: Dictionary) -> MusicProfile:
	var p := MusicProfile.new()
	p.energy = float(d.get("energy", 0.5))
	p.tempo = float(d.get("tempo", 0.0))
	p.track_hash = int(d.get("track_hash", 0))
	p.title = str(d.get("title", ""))
	p.artist = str(d.get("artist", ""))
	return p


func _to_string() -> String:
	return "MusicProfile(%s, energy=%.2f, tempo=%.0f)" % [title, energy, tempo]
