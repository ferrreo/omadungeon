## Small deterministic helpers shared by the generation pipeline. Every function that
## makes a choice takes the RandomNumberGenerator explicitly.
class_name GenUtil
extends RefCounted

const DIRS4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIRS8: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]


## In-place Fisher-Yates shuffle.
static func shuffle_ints(items: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp


## In-place Fisher-Yates shuffle.
static func shuffle_vec2i(items: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp


## In-place Fisher-Yates shuffle.
static func shuffle_names(items: Array[StringName], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp


## Index chosen proportionally to `weights` (all >= 0). Returns -1 when nothing can be picked.
static func weighted_index(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for i in range(weights.size()):
		roll -= maxf(weights[i], 0.0)
		if roll < 0.0:
			return i
	return weights.size() - 1


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Smallest axis-aligned gap (in tiles) between two rects; 0 when they touch or overlap.
static func rect_gap(a: Rect2i, b: Rect2i) -> int:
	var dx := maxi(maxi(b.position.x - a.end.x, a.position.x - b.end.x), 0)
	var dy := maxi(maxi(b.position.y - a.end.y, a.position.y - b.end.y), 0)
	return maxi(dx, dy)


## Tiles of `rect` as a list, row-major.
static func rect_tiles(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out
