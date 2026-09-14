class_name ClownsTest
extends GdUnitTestSuite


func _is_projectile(node: Node) -> bool:
	return node is Projectile


func test_juggler_throws_three_pins() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(170, 100)
	var juggler := EnemyTestHelpers.spawn(&"juggler", root, Vector2(100, 100))
	var attacks: Array[int] = [0]
	juggler.attack_started.connect(func() -> void: attacks[0] += 1)
	for _i in range(90):
		await get_tree().physics_frame
		if attacks[0] > 0:
			break
	assert_int(attacks[0]).is_equal(1)
	await get_tree().physics_frame
	assert_int(EnemyTestHelpers.count_children(root, _is_projectile)).is_equal(3)
	for child: Node in root.get_children():
		var shot := child as Projectile
		if shot != null:
			assert_that(shot.team).is_equal(Layers.Team.ENEMY)
			assert_object(shot.source).is_same(juggler)


func test_honker_charge_stuns_on_wall() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var target := Node2D.new()
	target.add_to_group(&"player")
	root.add_child(target)
	target.global_position = Vector2(100, 0)
	EnemyTestHelpers.wall(root, Vector2(140, 0), Vector2(8, 64))
	var honker := EnemyTestHelpers.spawn(&"honker", root, Vector2(0, 0))
	var stunned := false
	for _i in range(200):
		await get_tree().physics_frame
		if honker.status.is_stunned():
			stunned = true
			break
	(
		assert_bool(stunned)
		. override_failure_message("state %s pos %s" % [honker.state, honker.global_position])
		. is_true()
	)
	assert_float(honker.global_position.x).is_greater(100.0)
	assert_float(honker.global_position.x).is_less(140.0)


func test_balloon_pops_into_confetti() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var balloon := EnemyTestHelpers.spawn(&"balloon_clown", root, Vector2(80, 80))
	assert_bool(balloon.ignores_pits()).is_true()
	await get_tree().physics_frame
	EnemyTestHelpers.hit(balloon, 9999.0)
	assert_int(EnemyTestHelpers.count_children(root, _is_projectile)).is_equal(6)


func test_mime_places_wall_between_itself_and_player() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var mime := EnemyTestHelpers.spawn(&"mime", root, Vector2(100, 100)) as Mime
	await get_tree().physics_frame
	var wall := mime.place_wall(Vector2(160, 100))
	assert_object(wall).is_not_null()
	assert_int(wall.collision_layer).is_equal(Layers.WORLD)
	assert_float(wall.global_position.x).is_between(114.0, 132.0)
	assert_float(wall.global_position.y).is_equal_approx(100.0, 0.01)
	assert_int(mime.walls_placed).is_equal(1)
	await get_tree().physics_frame
	assert_bool(mime.has_line_of_sight(Vector2(160, 100))).is_false()


## docs §10 promises 16x16 tiles, integer scaling and snapped 2D transforms, and the mime's wall
## was the one object on the floor that did not keep that promise: `wall.rotation = dir.angle()`
## laid a soft-edged diagonal slab across an aligned grid, most obvious on a light theme where it
## reads as a large flat lozenge. The facing is quantised to a quarter turn now.
##
## The second assertion in the loop is the property that quantisation must not cost: a wall
## raised toward a *diagonal* target still stands between the mime and that target. Snapping the
## facing of a barrier whose whole job is to break a sight line is exactly the kind of fix that
## opens the hole next door.
func test_the_mime_wall_is_axis_aligned_and_still_blocks_a_diagonal_target() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var mime := EnemyTestHelpers.spawn(&"mime", root, Vector2(100, 100)) as Mime
	await get_tree().physics_frame
	var diagonals: Array[Vector2] = [
		Vector2(140, 140), Vector2(60, 140), Vector2(140, 60), Vector2(60, 60), Vector2(150, 118)
	]
	for target: Vector2 in diagonals:
		var wall := mime.place_wall(target)
		assert_object(wall).is_not_null()
		var turns := wall.rotation / Mime.WALL_FACING_STEP
		(
			assert_float(absf(turns - roundf(turns)))
			. override_failure_message(
				(
					"the wall toward %s faces %.3f rad, which is not a quarter turn"
					% [target, wall.rotation]
				)
			)
			. is_less(0.001)
		)
		await get_tree().physics_frame
		(
			assert_bool(mime.has_line_of_sight(target))
			. override_failure_message(
				"the snapped wall toward %s no longer breaks the sight line to it" % target
			)
			. is_false()
		)
		wall.queue_free()
		await get_tree().physics_frame


## The mime's barrier is a `StaticBody2D` on `Layers.WORLD`, not a TileMapLayer, so this is
## the second, independent shape of "projectiles collide with walls": a shot that used to sail
## through the barrier - past the one thing the mime exists to put between you and it - now
## dies on it. `tests/unit/combat/projectile_test.gd` holds the tilemap half.
func test_a_mime_wall_stops_a_projectile_that_used_to_fly_through_it() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var mime := EnemyTestHelpers.spawn(&"mime", root, Vector2(100, 100)) as Mime
	await get_tree().physics_frame
	var wall := mime.place_wall(Vector2(160, 100))
	assert_object(wall).is_not_null()
	await get_tree().physics_frame
	var shot := Projectile.new()
	shot.trail_enabled = false
	shot.impact_puff = false
	shot.setup(null, Layers.Team.PLAYER, Vector2.LEFT, Callable(), 200.0, 3.0)
	var grave: Array[Vector2] = []
	shot.expired.connect(func(p: Projectile) -> void: grave.append(p.global_position))
	root.add_child(shot)
	# Fired from beyond the wall, back toward the mime: the barrier is the only thing between
	# them, and a shot that gets through it would go on to hit the mime's hurtbox instead.
	shot.global_position = Vector2(220.0, 100.0)
	for _i in range(60):
		await get_tree().physics_frame
		if not is_instance_valid(shot) or shot.is_queued_for_deletion():
			break
	assert_int(grave.size()).is_equal(1)
	assert_float(grave[0].x).is_greater(wall.global_position.x)
	assert_float(grave[0].x).is_less(wall.global_position.x + 16.0)


func test_clown_car_summons_four_clowns_first() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(200, 100)
	var car := EnemyTestHelpers.spawn(&"clown_car", root, Vector2(100, 100))
	var attacks: Array[int] = [0]
	car.attack_started.connect(func() -> void: attacks[0] += 1)
	for _i in range(120):
		await get_tree().physics_frame
		if attacks[0] > 0:
			break
	assert_int(attacks[0]).is_equal(1)
	var clowns := 0
	for child: Node in root.get_children():
		if child is EnemyBase and child != car:
			clowns += 1
			assert_that((child as EnemyBase).def.faction).is_equal(EnemyDef.Faction.CLOWNS)
	assert_int(clowns).is_equal(4)


## A wall you collide with has to look like a wall. The Mime's barrier shipped as a 0.12-0.20
## alpha fill in the ink colour: on a light theme that is a faintly tinted pane of glass over a
## near-white floor, and a first-time player walked into it and read it as a rendering
## artefact. Opacity and contrast are the two halves of "solid", so both are asserted, on every
## fixture including the two light ones.
func test_the_mime_wall_reads_as_solid_on_every_theme() -> void:
	for name: String in [
		"tokyo-night", "gruvbox", "nord", "catppuccin", "catppuccin-latte", "white"
	]:
		var toml := ColorsToml.load_file(
			"res://tests/fixtures/omarchy/%s/state/current/theme/colors.toml" % name
		)
		var palette := ThemePalette.from_colors_toml(toml, name)
		var body := ThemePalette.separate(
			palette.get_color(&"danger"), palette.get_color(&"floor"), MimeWall.FLOOR_CONTRAST
		)
		(
			assert_float(ThemePalette.contrast_ratio(body, palette.get_color(&"floor")))
			. override_failure_message(
				"%s: the barrier body %s does not stand off the floor" % [name, body.to_html(false)]
			)
			. is_greater_equal(MimeWall.FLOOR_CONTRAST - 0.01)
		)
		(
			assert_float(ThemePalette.contrast_ratio(MimeWall.edge_color(body), body))
			. override_failure_message("%s: the barrier has no visible edge" % name)
			. is_greater_equal(MimeWall.EDGE_CONTRAST - 0.01)
		)
	# ...and it is never see-through, at any phase of its shimmer.
	assert_float(MimeWall.FILL_ALPHA).is_greater_equal(0.8)
	assert_float(MimeWall.HATCH_ALPHA - MimeWall.SHIMMER).is_greater_equal(0.6)
	# ...and not a painted-out hole either: an enemy standing behind it still has to be seen.
	assert_float(MimeWall.FILL_ALPHA).is_less(1.0)
