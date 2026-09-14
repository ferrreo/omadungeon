## Deterministic per-subsystem random streams derived from one run seed.
## Generation is reproducible regardless of how much combat RNG was consumed.
class_name RunRng
extends RefCounted

var run_seed: int
var _streams: Dictionary = {}


func _init(seed_value: int) -> void:
	run_seed = seed_value


## Returns the named stream, creating it deterministically on first use.
func stream(name: StringName) -> RandomNumberGenerator:
	if _streams.has(name):
		return _streams[name]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_combine(run_seed, hash(name))
	_streams[name] = rng
	return rng


## Current positions of `names` (stream name -> `RandomNumberGenerator.state`), for the save
## file. Streams that have not been used yet are created first, so the snapshot always lists
## every name and a resume never has to guess.
func states(names: Array[StringName]) -> Dictionary:
	var out: Dictionary = {}
	for name: StringName in names:
		out[name] = stream(name).state
	return out


## Puts the streams in `saved` (as produced by `states()`) back where they were. Names that are
## absent keep the position they derive from the seed, so an older save still resumes.
func restore(saved: Dictionary) -> void:
	for key: Variant in saved.keys():
		var name := StringName(str(key))
		stream(name).state = int(saved[key])


## Returns a fresh stream for one floor of one subsystem (e.g. gen for floor 3).
func floor_stream(name: StringName, floor_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_combine(hash_combine(run_seed, hash(name)), floor_index + 1)
	return rng


static func hash_combine(a: int, b: int) -> int:
	# splitmix64-style mixing, kept in signed 64-bit range.
	var x := a ^ (b + -7046029254386353131 + (a << 6) + (a >> 2))  # 0x9E3779B97F4A7C15 as signed
	x = (x ^ (x >> 30)) * -4658895280553007687  # 0xBF58476D1CE4E5B9 as signed
	x = (x ^ (x >> 27)) * -7723592293110705685  # 0x94D049BB133111EB as signed
	return x ^ (x >> 31)


static func seed_from_string(text: String) -> int:
	if text.is_valid_int():
		return text.to_int()
	return hash(text)
