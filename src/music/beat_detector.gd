## Pure onset detector on a bass-energy series: an onset fires when the energy exceeds
## `threshold` x the rolling average and at least `min_interval` seconds passed since the
## last onset. Tempo is estimated from the median onset interval. No audio APIs inside.
class_name BeatDetector
extends RefCounted

## Multiplier over the rolling average that counts as an onset.
var threshold: float = 1.4
## Minimum seconds between onsets (240 BPM cap).
var min_interval: float = 0.25
## Seconds of history kept for the rolling average.
var window: float = 1.0
## Energies below this never trigger (silence guard).
var noise_floor: float = 0.0005

var _times: PackedFloat64Array = PackedFloat64Array()
var _energies: PackedFloat64Array = PackedFloat64Array()
var _sum: float = 0.0
var _last_onset: float = -1.0e9
var _intervals: PackedFloat64Array = PackedFloat64Array()
var _last_strength: float = 0.0
var _onset_count: int = 0


## Feeds one sample. Returns true when this sample is an onset.
func feed(bass_energy: float, t: float) -> bool:
	var avg := average()
	var onset := false
	if (
		_energies.size() >= 4
		and avg > noise_floor
		and bass_energy > avg * threshold
		and t - _last_onset >= min_interval
	):
		onset = true
		if _last_onset > -1.0e8:
			_intervals.append(t - _last_onset)
			if _intervals.size() > 24:
				_intervals.remove_at(0)
		_last_onset = t
		_onset_count += 1
		_last_strength = clampf((bass_energy / maxf(avg, 1e-9) - threshold) / 2.0 + 0.4, 0.3, 1.0)
	_push(bass_energy, t)
	return onset


## Rolling average of the recent energies (0 when empty).
func average() -> float:
	if _energies.is_empty():
		return 0.0
	return _sum / float(_energies.size())


## Strength (0.3..1) of the most recent onset.
func last_strength() -> float:
	return _last_strength


## Total onsets detected since reset.
func onset_count() -> int:
	return _onset_count


## Tempo estimate in BPM from the median onset interval, folded into 70..180. 0 when unknown.
func bpm() -> float:
	if _intervals.size() < 2:
		return 0.0
	var sorted := Array(_intervals)
	sorted.sort()
	var mid := sorted.size() / 2
	var median: float
	if sorted.size() % 2 == 0:
		median = (float(sorted[mid - 1]) + float(sorted[mid])) * 0.5
	else:
		median = float(sorted[mid])
	if median <= 0.0:
		return 0.0
	var result := 60.0 / median
	while result < 70.0:
		result *= 2.0
	while result > 180.0:
		result *= 0.5
	return result


## Seconds since the last onset (huge before the first).
func since_last_onset(t: float) -> float:
	return t - _last_onset


func reset() -> void:
	_times = PackedFloat64Array()
	_energies = PackedFloat64Array()
	_sum = 0.0
	_last_onset = -1.0e9
	_intervals = PackedFloat64Array()
	_last_strength = 0.0
	_onset_count = 0


func _push(energy: float, t: float) -> void:
	_times.append(t)
	_energies.append(energy)
	_sum += energy
	while not _times.is_empty() and t - _times[0] > window:
		_sum -= _energies[0]
		_times.remove_at(0)
		_energies.remove_at(0)
	if _energies.is_empty():
		_sum = 0.0
