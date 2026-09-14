## Shadow casters for the walls of a floor: every WALL tile of a `FloorData` is covered by one
## `LightOccluder2D`, and the tiles are merged into as few rectangles as the wall runs allow,
## so a 40-room floor carries a few hundred polygons rather than a few thousand.
##
## A wall casts from its *core*, not its whole cell: each face that touches walkable ground is
## stood in by `inset` px (`LightingProfile.occluder_inset_px`), so the lip of the wall the
## lantern hangs on is lit and the shadow begins behind it. Faces that touch another wall or
## the void stay flush, which is what keeps two runs meeting at a corner gap-free: the cores
## of adjacent wall cells always touch. A light that sat inside a closed occluder would light
## nothing (every ray leaves through its boundary), which is why lanterns hang on the lip
## (`WallLantern.facing`) and never on the cell centre.
class_name WallOccluders
extends RefCounted


## One merged wall rectangle, in world pixels.
class Run:
	var rect: Rect2

	func _init(r: Rect2) -> void:
		rect = r


## Builds the merged rectangles for `data`. Pure: the same floor and inset give the same list.
static func runs_for(data: FloorData, inset: float) -> Array[Run]:
	var out: Array[Run] = []
	if data == null:
		return out
	var tile := float(Layers.TILE)
	# The core of every wall cell, as (top, bottom) extents and (left, right) extents in px
	# relative to the cell, keyed by cell. Cells with the same vertical extents merge along a
	# row; rows with identical runs then merge downward.
	var cores: Dictionary = {}
	for y in range(data.height):
		for x in range(data.width):
			if data.get_tile(x, y) != FloorData.Tile.WALL:
				continue
			var p := Vector2i(x, y)
			var l := inset if data.is_walkable(x - 1, y) else 0.0
			var r := inset if data.is_walkable(x + 1, y) else 0.0
			var t := inset if data.is_walkable(x, y - 1) else 0.0
			var b := inset if data.is_walkable(x, y + 1) else 0.0
			cores[p] = Rect2(
				Vector2(x, y) * tile + Vector2(l, t), Vector2(tile - l - r, tile - t - b)
			)
	var used: Dictionary = {}
	for y in range(data.height):
		for x in range(data.width):
			var p := Vector2i(x, y)
			if not cores.has(p) or used.has(p):
				continue
			var first: Rect2 = cores[p]
			# Extend right while the next core is flush with this one on both vertical edges.
			var x1 := x
			while true:
				var q := Vector2i(x1 + 1, y)
				if not cores.has(q) or used.has(q):
					break
				var c: Rect2 = cores[q]
				if not _same_rows(first, c) or not _touch_x(cores[Vector2i(x1, y)], c):
					break
				x1 += 1
			# Extend down while every cell of the row below matches the row above exactly.
			var y1 := y
			while true:
				var ok := true
				for xx in range(x, x1 + 1):
					var q := Vector2i(xx, y1 + 1)
					var above := Vector2i(xx, y1)
					if not cores.has(q) or used.has(q):
						ok = false
						break
					var c: Rect2 = cores[q]
					var a: Rect2 = cores[above]
					if not _same_cols(a, c) or not _touch_y(a, c):
						ok = false
						break
					if xx > x and not _touch_x(cores[Vector2i(xx - 1, y1 + 1)], c):
						ok = false
						break
				if not ok:
					break
				y1 += 1
			var top_left: Rect2 = cores[Vector2i(x, y)]
			var bottom_right: Rect2 = cores[Vector2i(x1, y1)]
			var merged := Rect2(top_left.position, bottom_right.end - top_left.position)
			for yy in range(y, y1 + 1):
				for xx in range(x, x1 + 1):
					used[Vector2i(xx, yy)] = true
			out.append(Run.new(merged))
	return out


## The occluder nodes for `data`, one per merged run, ready to add under a floor.
static func build(data: FloorData, inset: float) -> Array[LightOccluder2D]:
	var out: Array[LightOccluder2D] = []
	var i := 0
	for run: Run in runs_for(data, inset):
		var occluder := LightOccluder2D.new()
		occluder.name = "WallOccluder_%d" % i
		i += 1
		var polygon := OccluderPolygon2D.new()
		polygon.closed = true
		polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED
		var r := run.rect
		polygon.polygon = PackedVector2Array(
			[r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		)
		occluder.occluder = polygon
		out.append(occluder)
	return out


## True when the wall cell at `tile` lies inside one of `runs` (its core, at least). The test
## for "every wall run is covered".
static func covers(runs: Array[Run], tile: Vector2i) -> bool:
	var centre := (Vector2(tile) + Vector2(0.5, 0.5)) * float(Layers.TILE)
	for run: Run in runs:
		if run.rect.has_point(centre):
			return true
	return false


static func _same_rows(a: Rect2, b: Rect2) -> bool:
	return is_equal_approx(a.position.y, b.position.y) and is_equal_approx(a.end.y, b.end.y)


static func _same_cols(a: Rect2, b: Rect2) -> bool:
	return is_equal_approx(a.position.x, b.position.x) and is_equal_approx(a.end.x, b.end.x)


static func _touch_x(left: Rect2, right: Rect2) -> bool:
	return is_equal_approx(left.end.x, right.position.x)


static func _touch_y(above: Rect2, below: Rect2) -> bool:
	return is_equal_approx(above.end.y, below.position.y)
