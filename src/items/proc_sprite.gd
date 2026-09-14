## Procedural pixel icons (docs §10.1): a family template marks cells as solid / maybe / gem;
## a seeded RNG resolves the maybes on the left half, which is mirrored for symmetry, then
## outlined and shaded with an authored ramp. Deterministic per (seed, family, colours, size)
## and cached. Items keep their own colours (never theme-tinted).
class_name ProcSprite
extends RefCounted

## Ramp indices in `colors`: outline, dark, mid, light, highlight, accent (gem).
enum Ramp { OUTLINE, DARK, MID, LIGHT, HIGHLIGHT, ACCENT }

const FAMILIES: Array[StringName] = [&"ring", &"trinket", &"wand", &"prop"]

## Left half of each 16x16 family; '.' empty, '#' solid, '?' 50% solid, 'g' gem, 'h' 50% gem.
const TEMPLATES: Dictionary = {
	&"ring":
	[
		"........",
		"........",
		"....?hgg",
		"...?####",
		"..?##...",
		".?##....",
		".##.....",
		".##.....",
		".##.....",
		".##.....",
		".?##....",
		"..?##...",
		"...?####",
		"....??##",
		"........",
		"........",
	],
	&"trinket":
	[
		".......#",
		"......#.",
		"......#.",
		".......#",
		"....??##",
		"...?####",
		"..?##hg#",
		"..?#hggg",
		"..?#hggg",
		"..?##hg#",
		"...?####",
		"....??##",
		".....??#",
		"......?#",
		"........",
		"........",
	],
	&"wand":
	[
		"......?g",
		".....?gg",
		"......?g",
		".......#",
		".......#",
		"......?#",
		".......#",
		".......#",
		"......?#",
		".......#",
		".......#",
		"......?#",
		".......#",
		"......##",
		"......##",
		"........",
	],
	&"prop":
	[
		"........",
		"........",
		"..??????",
		".?######",
		".#?#####",
		".##?####",
		".#####?#",
		".##h####",
		".###?###",
		".#?#####",
		".####?##",
		".##?####",
		".?######",
		"..??????",
		"........",
		"........",
	],
}

## Authored default ramps per family (outline, dark, mid, light, highlight, accent).
const DEFAULT_COLORS: Dictionary = {
	&"ring":
	[
		Color("1a1420"),
		Color("8a6a1e"),
		Color("d4a63a"),
		Color("f2d675"),
		Color("fff5c2"),
		Color("4fc3f7"),
	],
	&"trinket":
	[
		Color("1a1420"),
		Color("4a3b5c"),
		Color("7b6494"),
		Color("a993c4"),
		Color("d8c9ea"),
		Color("ff6b6b"),
	],
	&"wand":
	[
		Color("1a1420"),
		Color("5a3a22"),
		Color("8c5a32"),
		Color("b87c48"),
		Color("dca872"),
		Color("8be9fd"),
	],
	&"prop":
	[
		Color("1a1420"),
		Color("4d3b2a"),
		Color("7a5c3c"),
		Color("a37f55"),
		Color("c9a479"),
		Color("c0392b"),
	],
}

## Gem colours picked by seed when the caller does not override the accent.
const GEM_COLORS: Array[Color] = [
	Color("4fc3f7"),
	Color("ff6b6b"),
	Color("7bed9f"),
	Color("c792ea"),
	Color("ffd166"),
	Color("f78fb3"),
]

const CACHE_META := &"proc_sprite_cache"
## Cached textures kept alive at once; the oldest entries are dropped past this (a run can
## show thousands of distinct item seeds).
const CACHE_LIMIT := 256


## Texture for (seed, family). `colors` may be empty (family defaults) or a partial ramp.
static func generate(
	seed_hash: int, family: StringName, colors: Array[Color] = [], size: int = 16
) -> ImageTexture:
	var key := "%d|%s|%d|%d" % [seed_hash, family, size, colors.hash()]
	var cache := _cache()
	if cache.has(key):
		return cache[key]
	var texture := ImageTexture.create_from_image(generate_image(seed_hash, family, colors, size))
	cache[key] = texture
	while cache.size() > CACHE_LIMIT:
		cache.erase(cache.keys()[0])
	return texture


## Same as `generate` but returns the Image (uncached); handy for tests and export.
static func generate_image(
	seed_hash: int, family: StringName, colors: Array[Color] = [], size: int = 16
) -> Image:
	var fam := family if TEMPLATES.has(family) else &"prop"
	var rng := RandomNumberGenerator.new()
	rng.seed = RunRng.hash_combine(seed_hash, hash(fam))
	var ramp := _ramp(fam, colors, rng)
	var half := size / 2
	var solid := _resolve_mask(fam, rng, size, half)
	var sparkle_seed := rng.randi()
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(size):
		for x in range(size):
			var cell := _cell(solid, x, y, size)
			if cell == 0:
				if _touches_solid(solid, x, y, size):
					image.set_pixel(x, y, ramp[Ramp.OUTLINE])
				continue
			image.set_pixel(x, y, _shade(solid, x, y, size, cell, ramp, sparkle_seed))
	return image


## Icon for an item: the authored icon when the base has one (weapons, armor), else a
## per-instance proc sprite from its seed and family (rings, trinkets). Never null, so every
## UI that shows items (chest cards, pause equipment rows, HUD) must call this instead of
## reading `item.base.icon`, which is null for half the droppable items.
static func for_item(item: ItemInstance) -> Texture2D:
	if item == null or item.base == null:
		return generate(0, &"prop")
	if item.base.icon != null:
		return item.base.icon
	var family := item.base.proc_sprite_family
	if family == &"" or not TEMPLATES.has(family):
		family = &"prop"
	return generate(item.seed_hash, family)


static func clear_cache() -> void:
	_cache().clear()


## Process-wide cache stored as meta on the main loop (static vars are not lint-clean here).
static func _cache() -> Dictionary:
	var loop := Engine.get_main_loop()
	if loop == null:
		return {}
	if not loop.has_meta(CACHE_META):
		loop.set_meta(CACHE_META, {})
	return loop.get_meta(CACHE_META)


## Builds the 6-colour ramp: caller colours first, family defaults for the rest, and a seeded
## gem colour when no accent was supplied.
static func _ramp(
	family: StringName, colors: Array[Color], rng: RandomNumberGenerator
) -> Array[Color]:
	var defaults: Array = DEFAULT_COLORS[family]
	var ramp: Array[Color] = []
	for i in range(6):
		if i < colors.size():
			ramp.append(colors[i])
		elif i == Ramp.ACCENT:
			ramp.append(GEM_COLORS[rng.randi_range(0, GEM_COLORS.size() - 1)])
		else:
			ramp.append(defaults[i])
	return ramp


## Resolves the template into a full grid of cell values: 0 empty, 1 body, 2 gem.
static func _resolve_mask(
	family: StringName, rng: RandomNumberGenerator, size: int, half: int
) -> PackedInt32Array:
	var rows: Array = TEMPLATES[family]
	var grid := PackedInt32Array()
	grid.resize(size * size)
	for y in range(size):
		var template_y := int(floor(float(y) * 16.0 / float(size)))
		var row: String = rows[template_y]
		for x in range(half):
			var template_x := int(floor(float(x) * 8.0 / float(half)))
			var ch := row[template_x]
			var value := 0
			match ch:
				"#":
					value = 1
				"?":
					value = 1 if rng.randf() < 0.5 else 0
				"g":
					value = 2
				"h":
					value = 2 if rng.randf() < 0.5 else 1
			grid[y * size + x] = value
			grid[y * size + (size - 1 - x)] = value
	return grid


static func _cell(grid: PackedInt32Array, x: int, y: int, size: int) -> int:
	if x < 0 or y < 0 or x >= size or y >= size:
		return 0
	return grid[y * size + x]


static func _touches_solid(grid: PackedInt32Array, x: int, y: int, size: int) -> bool:
	return (
		_cell(grid, x - 1, y, size) != 0
		or _cell(grid, x + 1, y, size) != 0
		or _cell(grid, x, y - 1, size) != 0
		or _cell(grid, x, y + 1, size) != 0
	)


## Top edge = light, bottom edge = dark, interior = mid, with a seeded sparkle. Symmetric:
## the sparkle hash uses the mirrored column so both halves match.
static func _shade(
	grid: PackedInt32Array,
	x: int,
	y: int,
	size: int,
	cell: int,
	ramp: Array[Color],
	sparkle_seed: int
) -> Color:
	if cell == 2:
		var gem_top := _cell(grid, x, y - 1, size) != 2
		return ramp[Ramp.ACCENT].lightened(0.35) if gem_top else ramp[Ramp.ACCENT]
	var above := _cell(grid, x, y - 1, size)
	var below := _cell(grid, x, y + 1, size)
	if above == 0:
		var mirrored_x := mini(x, size - 1 - x)
		var sparkle := (RunRng.hash_combine(sparkle_seed, mirrored_x * 131 + y) & 7) == 0
		return ramp[Ramp.HIGHLIGHT] if sparkle else ramp[Ramp.LIGHT]
	if below == 0:
		return ramp[Ramp.DARK]
	return ramp[Ramp.MID]
