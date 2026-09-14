## Synthetic desktop inputs for the reactivity suites: wallpapers built from generated images
## (never from the developer's real desktop), theme profiles from the shipped fixtures and
## music profiles with hand-set levers. Nothing here touches the live `Desktop`/`Music` state.
class_name ReactivityFixtures
extends RefCounted

const FIXTURES := "res://tests/fixtures/omarchy"
## Sampling size the analyzer downscales to; building images at this size keeps the synthetic
## edge patterns intact instead of letting the bilinear resize blur them away.
const W := WallpaperAnalyzer.SAMPLE_W
const H := WallpaperAnalyzer.SAMPLE_H


static func palette_for(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


static func profile_for(theme: String) -> ThemeProfile:
	return ThemeProfile.from_palette(palette_for(theme))


## Analyses `image` and stamps the identity an on-disk wallpaper would have had.
static func wallpaper_of(image: Image, path: String) -> WallpaperAnalyzer.Result:
	var r := WallpaperAnalyzer.analyze_image(image)
	r.source_path = path
	r.seed_hash = hash(path)
	return r


## A single flat colour: zero edges, luminance entirely under our control.
static func flat(c: Color, path: String = "res://flat.png") -> WallpaperAnalyzer.Result:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(c)
	return wallpaper_of(img, path)


## Two-pixel vertical stripes: a busy wallpaper. One-pixel stripes would be invisible to a
## 3x3 Sobel kernel, whose horizontal taps land on two identical columns.
static func striped(
	a: Color, b: Color, path: String = "res://striped.png"
) -> WallpaperAnalyzer.Result:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for x in range(W):
		img.fill_rect(Rect2i(x, 0, 1, H), a if (x / 2) % 2 == 0 else b)
	return wallpaper_of(img, path)


## Bright band across the top third over a dark body (or the reverse) so `ambient` — which
## only reads the top third — can be driven independently of the rest of the picture.
static func top_band(top: Color, body: Color, path: String) -> WallpaperAnalyzer.Result:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(body)
	img.fill_rect(Rect2i(0, 0, W, H / 3), top)
	return wallpaper_of(img, path)


## Copy of `source` that differs only in the image-path hash, isolating the seed lever.
static func reseeded(source: WallpaperAnalyzer.Result, path: String) -> WallpaperAnalyzer.Result:
	var r := WallpaperAnalyzer.Result.new()
	r.dominant = source.dominant.duplicate()
	r.ambient = source.ambient
	r.edge_density = source.edge_density
	r.source_path = path
	r.seed_hash = hash(path)
	return r


static func music(energy: float, tempo: float, title: String) -> MusicProfile:
	var p := MusicProfile.new()
	p.energy = energy
	p.tempo = tempo
	p.title = title
	p.track_hash = hash(title)
	return p


## Stable signature of everything a floor's *fill* decided: templates, props, traps and
## enemy spawn points, on top of the tile grid itself.
static func floor_signature(data: FloorData) -> String:
	var parts := PackedStringArray([str(data.layout_hash())])
	for room: FloorData.Room in data.rooms:
		(
			parts
			. append(
				(
					"%d:%s:%d:%d:%d"
					% [
						room.id,
						String(room.fill_template),
						room.prop_positions.size(),
						room.trap_positions.size(),
						room.enemy_spawns.size(),
					]
				)
			)
		)
	return "|".join(parts)


## Fraction of tiles (0..1) on which two floors disagree, compared over the union of their
## grids so a floor that is merely a different size already counts as different. This is the
## machine-readable form of "did the theme change the dungeon, or only its colours".
static func tile_difference(a: FloorData, b: FloorData) -> float:
	var w := maxi(a.width, b.width)
	var h := maxi(a.height, b.height)
	if w <= 0 or h <= 0:
		return 0.0
	var diff := 0
	for y in range(h):
		for x in range(w):
			if a.get_tile(x, y) != b.get_tile(x, y):
				diff += 1
	return float(diff) / float(w * h)


## Fill templates of a floor, in room order.
static func fill_templates(data: FloorData) -> PackedStringArray:
	var out := PackedStringArray()
	for room: FloorData.Room in data.rooms:
		out.append(String(room.fill_template))
	return out


## Total number of enemy spawn points on a floor.
static func spawn_point_count(data: FloorData) -> int:
	var total := 0
	for room: FloorData.Room in data.rooms:
		total += room.enemy_spawns.size()
	return total


static func generate(params: GenParams, seed_value: int) -> FloorData:
	var rng := RunRng.new(seed_value).floor_stream(&"gen", params.floor_index)
	return FloorGenerator.generate(params, rng)
