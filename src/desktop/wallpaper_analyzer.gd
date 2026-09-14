## Measures a wallpaper for the *generator*: how bright it is, how busy it is, how varied and
## how vivid its colours are, and a stable hash of where it came from.
##
## None of it reaches the palette. The wallpaper used to supply colour to the dungeon, and the
## owner removed that (docs/GAME_DESIGN.md, decisions log): an otter-shell palette is already
## generated from the wallpaper, so a second pass of the same image over the theme applied it
## twice. The numbers here shape the run - the floor plan, the room sizes, how cluttered and
## how trapped it is, and how lit - and the theme says what colour all of it is.
##
## `dominant` is still a list of colours because that is what the hue statistics are computed
## from; nothing draws with them.
## Pure and thread-safe: call `analyze_image` from a WorkerThreadPool task.
class_name WallpaperAnalyzer
extends RefCounted

const SAMPLE_W := 64
const SAMPLE_H := 36
const K := 4
const ITERATIONS := 8
## Ambient clamp from docs 3.4 ("mean luminance of top third -> ambient, clamped 0.55-1.0").
const AMBIENT_MIN := 0.55
const AMBIENT_MAX := 1.0
## Mean chroma at which `colour_energy` reads as fully vivid. Photographs and the shipped
## theme previews measure 0.2-0.45 across their dominants, so a third is the top of the range
## a real wallpaper reaches rather than the top of what HSV can express.
const COLOUR_ENERGY_FULL := 0.33
## Edge density that counts as "average clutter": below it props thin out, above it they
## thicken. Measured on the shipped theme previews, which sit around 0.12-0.20.
const EDGE_MID := 0.15
## Prop-density swing the Sobel edge density is allowed to add (docs 3.4: +-0.15).
const EDGE_SWING := 0.15


## Result of an analysis.
class Result:
	extends RefCounted
	var dominant: Array[Color] = []
	var ambient: float = 0.8
	var edge_density: float = 0.0
	var source_path: String = ""
	var seed_hash: int = 0

	## Prop-density offset from the Sobel edge density, in [-EDGE_SWING, +EDGE_SWING]:
	## a flat wallpaper empties rooms out, a busy one clutters them (docs 3.4).
	func prop_density_delta() -> float:
		return clampf(
			edge_density - WallpaperAnalyzer.EDGE_MID,
			-WallpaperAnalyzer.EDGE_SWING,
			WallpaperAnalyzer.EDGE_SWING
		)

	## Floor light level for this wallpaper, always inside the documented clamp. Light themes
	## are pinned to full ambient (docs 3.2: "mode == light ... ambient 1.0").
	func ambient_level(is_light: bool = false) -> float:
		if is_light:
			return WallpaperAnalyzer.AMBIENT_MAX
		return clampf(ambient, WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX)

	## How many different hues this wallpaper holds, 0 (one hue, or none) to 1 (its colours
	## point every which way round the circle). Circular variance of the dominant hues,
	## weighted by chroma so a near-grey dominant cannot vote for a hue it does not have.
	##
	## A *generation* lever, never a colour one: the picture's hues say how varied the floor
	## plan is, they never say what colour anything is (`GenParams.build`).
	func hue_spread() -> float:
		var x := 0.0
		var y := 0.0
		var sum := 0.0
		for c: Color in accents():
			x += cos(c.h * TAU) * c.s
			y += sin(c.h * TAU) * c.s
			sum += c.s
		if sum <= 0.0:
			return 0.0
		return clampf(1.0 - sqrt(x * x + y * y) / sum, 0.0, 1.0)

	## How vivid this wallpaper is, 0 (greyscale) to 1 (`COLOUR_ENERGY_FULL` mean chroma or
	## above). The other half of the pair above, and equally a generation lever only.
	func colour_energy() -> float:
		var list := accents()
		if list.is_empty():
			return 0.0
		var total := 0.0
		for c: Color in list:
			total += c.s
		return clampf(total / float(list.size()) / WallpaperAnalyzer.COLOUR_ENERGY_FULL, 0.0, 1.0)

	## The dominant colours whose hue means anything: the near-black and near-white ends of
	## the k-means result carry none, so they are dropped. Input to `hue_spread` and
	## `colour_energy` only - nothing in the game is drawn in these.
	func accents() -> Array[Color]:
		var out: Array[Color] = []
		for c: Color in dominant:
			var lum := c.get_luminance()
			if lum < 0.04 or lum > 0.96:
				continue
			out.append(c)
		return out


static func analyze_file(path: String) -> Result:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	var result := analyze_image(image)
	result.source_path = path
	result.seed_hash = hash(path)
	return result


static func analyze_image(source: Image) -> Result:
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGB8)
	image.resize(SAMPLE_W, SAMPLE_H, Image.INTERPOLATE_BILINEAR)
	var result := Result.new()
	var pixels: Array[Color] = []
	for y in range(SAMPLE_H):
		for x in range(SAMPLE_W):
			pixels.append(image.get_pixel(x, y))
	result.dominant = _kmeans(pixels, K, ITERATIONS)
	result.ambient = clampf(_top_third_luminance(image), 0.55, 1.0)
	result.edge_density = _edge_density(image)
	return result


static func _kmeans(pixels: Array[Color], k: int, iterations: int) -> Array[Color]:
	var centroids: Array[Color] = []
	var step := maxi(1, pixels.size() / k)
	for i in range(k):
		centroids.append(pixels[mini(i * step, pixels.size() - 1)])
	for _iter in range(iterations):
		var sums: Array[Vector3] = []
		var counts: Array[int] = []
		for _i in range(k):
			sums.append(Vector3.ZERO)
			counts.append(0)
		for p: Color in pixels:
			var best := 0
			var best_d := INF
			for i in range(k):
				var c := centroids[i]
				var d := (p.r - c.r) ** 2 + (p.g - c.g) ** 2 + (p.b - c.b) ** 2
				if d < best_d:
					best_d = d
					best = i
			sums[best] += Vector3(p.r, p.g, p.b)
			counts[best] += 1
		for i in range(k):
			if counts[i] > 0:
				var v := sums[i] / counts[i]
				centroids[i] = Color(v.x, v.y, v.z)
	# Sort by population is unnecessary for our use; sort by luminance for stability.
	centroids.sort_custom(
		func(a: Color, b: Color) -> bool: return a.get_luminance() > b.get_luminance()
	)
	return centroids


static func _top_third_luminance(image: Image) -> float:
	var total := 0.0
	var rows := maxi(1, image.get_height() / 3)
	for y in range(rows):
		for x in range(image.get_width()):
			total += image.get_pixel(x, y).get_luminance()
	return total / float(rows * image.get_width())


## Fraction of pixels whose 3x3 Sobel magnitude exceeds a threshold.
static func _edge_density(image: Image) -> float:
	var w := image.get_width()
	var h := image.get_height()
	var lum: PackedFloat32Array = []
	lum.resize(w * h)
	for y in range(h):
		for x in range(w):
			lum[y * w + x] = image.get_pixel(x, y).get_luminance()
	var edges := 0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var gx := (
				-lum[(y - 1) * w + x - 1]
				+ lum[(y - 1) * w + x + 1]
				- 2.0 * lum[y * w + x - 1]
				+ 2.0 * lum[y * w + x + 1]
				- lum[(y + 1) * w + x - 1]
				+ lum[(y + 1) * w + x + 1]
			)
			var gy := (
				-lum[(y - 1) * w + x - 1]
				- 2.0 * lum[(y - 1) * w + x]
				- lum[(y - 1) * w + x + 1]
				+ lum[(y + 1) * w + x - 1]
				+ 2.0 * lum[(y + 1) * w + x]
				+ lum[(y + 1) * w + x + 1]
			)
			if sqrt(gx * gx + gy * gy) > 0.5:
				edges += 1
	return float(edges) / float((w - 2) * (h - 2))
