## Collects per-frame cost samples and reports the numbers the 60 fps budget is judged on:
## average, 95th percentile and worst frame, plus how many frames blew the budget.
##
## Samples are seconds in, milliseconds out — `feed()` takes what the engine hands you
## (`Performance.TIME_PROCESS` and friends are seconds) and every getter returns ms.
class_name FrameSampler
extends RefCounted

## Frames kept. Older samples are dropped, so a long soak reports its most recent window.
const DEFAULT_CAPACITY := 4096

var capacity: int = DEFAULT_CAPACITY

var _samples: PackedFloat32Array = PackedFloat32Array()


func _init(sample_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(1, sample_capacity)


## Records one frame. `seconds` may be 0 but never negative.
func feed(seconds: float) -> void:
	_samples.append(maxf(0.0, seconds) * 1000.0)
	if _samples.size() > capacity:
		_samples = _samples.slice(_samples.size() - capacity)


func count() -> int:
	return _samples.size()


func reset() -> void:
	_samples = PackedFloat32Array()


## Milliseconds of the average frame (0 with no samples).
func average_ms() -> float:
	if _samples.is_empty():
		return 0.0
	var total := 0.0
	for ms: float in _samples:
		total += ms
	return total / float(_samples.size())


## Milliseconds of the worst frame seen.
func worst_ms() -> float:
	if _samples.is_empty():
		return 0.0
	var worst := 0.0
	for ms: float in _samples:
		worst = maxf(worst, ms)
	return worst


## Milliseconds of the cheapest frame seen.
func best_ms() -> float:
	if _samples.is_empty():
		return 0.0
	var best := INF
	for ms: float in _samples:
		best = minf(best, ms)
	return best


## Nearest-rank percentile in ms. `p` is 0..1 (0.95 = the 95th percentile).
func percentile_ms(p: float) -> float:
	if _samples.is_empty():
		return 0.0
	var sorted := _samples.duplicate()
	sorted.sort()
	var rank := int(ceilf(clampf(p, 0.0, 1.0) * float(sorted.size())))
	return sorted[clampi(rank - 1, 0, sorted.size() - 1)]


## Frames per second the average frame corresponds to (0 when no time was spent).
func average_fps() -> float:
	var avg := average_ms()
	return 0.0 if avg <= 0.0 else 1000.0 / avg


## How many frames cost more than `budget_ms`.
func over_budget(budget_ms: float) -> int:
	var n := 0
	for ms: float in _samples:
		if ms > budget_ms:
			n += 1
	return n


## Machine-readable summary. Keys: frames, average_ms, p95_ms, worst_ms, best_ms, average_fps.
func to_dict() -> Dictionary:
	return {
		"frames": count(),
		"average_ms": average_ms(),
		"p95_ms": percentile_ms(0.95),
		"worst_ms": worst_ms(),
		"best_ms": best_ms(),
		"average_fps": average_fps(),
	}


## One-line report, e.g. `sim: 240 frames avg 3.11 ms p95 5.40 ms worst 9.02 ms (321 fps)`.
func format_line(label: String) -> String:
	return (
		"%s: %d frames avg %.2f ms p95 %.2f ms worst %.2f ms (%.0f fps)"
		% [label, count(), average_ms(), percentile_ms(0.95), worst_ms(), average_fps()]
	)
