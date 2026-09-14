## Interior fill template for a room (docs 5.1 #5). The `pattern` names a code pattern in
## RoomFiller (empty, pillars, cross, ring, rubble, pits); `mask` optionally stamps a fixed
## drawing instead. Numbers live in data/rooms/<id>.tres.
class_name RoomTemplate
extends Resource

## Mask characters: '.' floor, '#' wall, '~' pit, 'o' prop, ' ' or '?' leave untouched.
const MASK_FLOOR := "."
const MASK_WALL := "#"
const MASK_PIT := "~"
const MASK_PROP := "o"

@export var id: StringName = &"empty"
## Code pattern applied when `mask` is empty.
@export var pattern: StringName = &"empty"
@export var weight: float = 1.0
## Smallest interior the template fits into.
@export var min_size: Vector2i = Vector2i(5, 5)
## Room types (FloorData.RoomType values) allowed to use it; empty = any.
@export var allowed_types: Array[int] = []
## Biome ids allowed to use it; empty = any.
@export var allowed_biomes: Array[StringName] = []
## Biome id -> weight multiplier, so each biome has a look (a library leans on pillars, a
## forge on pits). A biome not listed rolls at 1.
@export var biome_weights: Dictionary = {}
## Grid spacing for pillar/ring style patterns.
@export var spacing: int = 3
## Feature density for scatter patterns (0..1).
@export var density: float = 0.5
## Optional multi-line mask stamped centred in the room.
@export_multiline var mask: String = ""


func fits(room_size: Vector2i, type: int, biome_id: StringName) -> bool:
	if room_size.x < min_size.x or room_size.y < min_size.y:
		return false
	if not allowed_types.is_empty() and not (type in allowed_types):
		return false
	if not allowed_biomes.is_empty() and not (biome_id in allowed_biomes):
		return false
	if not mask.is_empty():
		var lines := mask_lines()
		if lines.is_empty() or lines.size() > room_size.y:
			return false
		for line: String in lines:
			if line.length() > room_size.x:
				return false
	return true


## Roll weight in `biome_id`: `weight` times the biome's multiplier.
func weight_in(biome_id: StringName) -> float:
	return weight * float(biome_weights.get(biome_id, 1.0))


## Mask rows without trailing blank lines.
func mask_lines() -> PackedStringArray:
	var lines := mask.split("\n")
	while not lines.is_empty() and lines[lines.size() - 1].strip_edges().is_empty():
		lines.remove_at(lines.size() - 1)
	return lines
