## The walls cast shadow: every WALL tile of a floor lies inside one of the merged occluder
## rectangles `WallOccluders` builds, the rectangles are few (runs, not cells), a face that
## touches walkable ground is stood in by the inset and one that touches wall or void is not,
## and the lantern anchors the generator rolls (`LanternAnchors`) hang where a light can
## actually shine: on a wall, facing open ground, never in or beside a doorway, spaced.
class_name LightingOccludersTest
extends GdUnitTestSuite

const INSET := 5.0
const THEMES: PackedStringArray = ["tokyo-night", "gruvbox", "catppuccin-latte"]


static func _generated(theme: String, floor_index: int) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913 + floor_index
	return FloorGenerator.generate(params, rng)


func _floors() -> Array[FloorData]:
	var out: Array[FloorData] = [RoomsTestFixtures.three_rooms()]
	for theme: String in THEMES:
		out.append(_generated(theme, 0))
	out.append(_generated("tokyo-night", 2))
	return out


## Every wall tile is covered, on a hand-built floor and on generated ones.
func test_every_wall_tile_is_inside_an_occluder_run() -> void:
	for data: FloorData in _floors():
		var runs := WallOccluders.runs_for(data, INSET)
		var walls := 0
		for y in range(data.height):
			for x in range(data.width):
				if data.get_tile(x, y) != FloorData.Tile.WALL:
					continue
				walls += 1
				(
					assert_bool(WallOccluders.covers(runs, Vector2i(x, y)))
					. override_failure_message(
						"wall %d,%d of floor %d is not covered" % [x, y, data.seed_value]
					)
					. is_true()
				)
		assert_int(walls).is_greater(0)
		# Runs, not cells: a floor of N wall tiles must not carry N polygons.
		(
			assert_int(runs.size())
			. override_failure_message(
				"floor %d: %d runs for %d wall tiles" % [data.seed_value, runs.size(), walls]
			)
			. is_less(walls / 2)
		)


## A wall face that touches walkable ground is stood in; one that touches wall or void is
## flush, so two runs meeting at a corner leave no gap for light to leak through.
func test_faces_toward_the_room_are_inset_and_the_rest_flush() -> void:
	var data := RoomsTestFixtures.three_rooms()
	var runs := WallOccluders.runs_for(data, INSET)
	var tile := float(Layers.TILE)
	# Room A is Rect2i(2, 2, 5, 4): its top wall is y = 1, facing the floor at y = 2 below and
	# the void at y = 0 above.
	var top_wall := Vector2i(4, 1)
	assert_int(data.get_tile(top_wall.x, top_wall.y)).is_equal(FloorData.Tile.WALL)
	var run := _run_covering(runs, top_wall)
	assert_object(run).is_not_null()
	assert_float(run.rect.position.y).is_equal_approx(float(top_wall.y) * tile, 0.01)
	assert_float(run.rect.end.y).is_equal_approx(float(top_wall.y + 1) * tile - INSET, 0.01)
	# The left wall x = 1 faces the floor at x = 2.
	var left_wall := Vector2i(1, 3)
	var left := _run_covering(runs, left_wall)
	assert_object(left).is_not_null()
	assert_float(left.rect.position.x).is_equal_approx(float(left_wall.x) * tile, 0.01)
	assert_float(left.rect.end.x).is_equal_approx(float(left_wall.x + 1) * tile - INSET, 0.01)
	# The corner (1, 1) touches wall on two sides and void on two: a full cell.
	var corner := _run_covering(runs, Vector2i(1, 1))
	assert_object(corner).is_not_null()
	assert_float(corner.rect.size.x).is_greater_equal(tile - 0.01)
	assert_float(corner.rect.size.y).is_greater_equal(tile - 0.01)


## The occluder nodes carry closed polygons matching the runs, in placement order.
func test_occluder_nodes_match_the_runs() -> void:
	var data := RoomsTestFixtures.three_rooms()
	var runs := WallOccluders.runs_for(data, INSET)
	var nodes := WallOccluders.build(data, INSET)
	assert_int(nodes.size()).is_equal(runs.size())
	for i in range(nodes.size()):
		var polygon := nodes[i].occluder
		assert_object(polygon).is_not_null()
		assert_bool(polygon.closed).is_true()
		assert_int(polygon.polygon.size()).is_equal(4)
		assert_vector(polygon.polygon[0]).is_equal(runs[i].rect.position)
		assert_vector(polygon.polygon[2]).is_equal(runs[i].rect.end)
		nodes[i].free()


## The anchors a lantern hangs on: a WALL tile with open ground on one side, never inside the
## door clearance, at least `MIN_APART` from every other anchor, and the same on every roll.
func test_lantern_anchors_hang_on_walls_facing_open_ground_and_clear_of_doors() -> void:
	for data: FloorData in _floors():
		var anchors := LightRig.anchors_for(data)
		(
			assert_int(anchors.size())
			. override_failure_message("floor %d rolled no anchors" % data.seed_value)
			. is_greater(0)
		)
		var zone := LanternAnchors.door_zone(data)
		for i in range(anchors.size()):
			var a := anchors[i]
			assert_int(data.get_tile(a.x, a.y)).is_equal(FloorData.Tile.WALL)
			assert_bool(zone.has(a)).override_failure_message("%s is beside a door" % a).is_false()
			var facing := LightRig.facing_of(data, a)
			var open := a + Vector2i(facing)
			assert_bool(data.is_walkable(open.x, open.y)).is_true()
			for j in range(i + 1, anchors.size()):
				(
					assert_int(GenUtil.chebyshev(a, anchors[j]))
					. override_failure_message("%s and %s too close" % [a, anchors[j]])
					. is_greater_equal(LanternAnchors.MIN_APART)
				)
		# Deterministic: a second read gives the same list.
		assert_array(LightRig.anchors_for(data)).is_equal(anchors)


## A lantern's light sits outside the wall core it hangs on, whichever way the wall faces.
func test_a_lantern_light_never_sits_inside_its_wall_occluder() -> void:
	var data := RoomsTestFixtures.three_rooms()
	var runs := WallOccluders.runs_for(data, INSET)
	var profile := LightingProfile.resolve()
	for a: Vector2i in LightRig.anchors_for(data):
		var centre := (Vector2(a) + Vector2(0.5, 0.5)) * float(Layers.TILE)
		var light := centre + LightRig.facing_of(data, a) * profile.lantern_lip_px
		for run: WallOccluders.Run in runs:
			(
				assert_bool(run.rect.has_point(light))
				. override_failure_message("lantern at %s lights from inside %s" % [a, run.rect])
				. is_false()
			)


static func _run_covering(runs: Array[WallOccluders.Run], tile: Vector2i) -> WallOccluders.Run:
	var centre := (Vector2(tile) + Vector2(0.5, 0.5)) * float(Layers.TILE)
	for run: WallOccluders.Run in runs:
		if run.rect.has_point(centre):
			return run
	return null
