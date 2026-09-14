class_name GreybeardsTest
extends GdUnitTestSuite

## Every EventBus handler this suite connects goes through the probe, which hands them all back
## in after_test: an autoload signal outlives the suite, so a leaked lambda silently changes
## the result of whatever runs next (see tests/unit/tools/test_isolation_test.gd).
## Longest run of motionless physics frames an approaching enemy may show: 0.15 s at 60 Hz,
## which is about the shortest pause a player reads as a stutter.
const STALL_FRAMES := 9
## Frames the approach is watched for - three seconds, comfortably short of the distance set
## up below, so the zealot is still closing when the window ends.
const APPROACH_FRAMES := 180
## Movement under this (px in one physics frame) is numerical noise, not a step.
const STEP_EPSILON := 0.25
## A single physics frame's travel (px) that only a dash can produce. A zealot walks at
## `move_speed` 90 (1.5 px a frame) and dashes at 240 (4.0 px a frame), so anything clear of
## the walk proves the burst actually fired.
const DASH_STEP := 2.5
## Interior of the cramped space the dash is measured in: barely taller than an enemy body is
## wide (`enemy_base.tscn`, radius 5), with the lane set hard against the top wall. A zealot
## crossing it is in contact for every frame of the crossing and still has somewhere to go -
## which is the condition the owner's tiny room produced and the whole point of the case.
const ROOM := Rect2(Vector2.ZERO, Vector2(170, 12))
## Y the pack and the player share, half a pixel into the top wall.
const LANE := 4.5
const WALL_THICK := 16.0

var _probe := EventBusProbe.new()


func after_test() -> void:
	_probe.release()


func test_beard_warden_blocks_frontal_hits() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var warden := EnemyTestHelpers.spawn(&"beard_warden", root, Vector2(100, 100)) as BeardWarden
	await get_tree().physics_frame
	warden.face(Vector2(200, 100))
	var front := auto_free(Node2D.new()) as Node2D
	root.add_child(front)
	front.global_position = Vector2(130, 100)
	var back := auto_free(Node2D.new()) as Node2D
	root.add_child(back)
	back.global_position = Vector2(70, 100)
	var full := EnemyTestHelpers.hit(warden, 40.0, back)
	assert_bool(warden.last_hit_blocked).is_false()
	var blocked := EnemyTestHelpers.hit(warden, 40.0, front)
	assert_bool(warden.last_hit_blocked).is_true()
	assert_float(blocked).is_less(full * 0.2)
	assert_float(blocked).is_greater(0.0)
	var flank := auto_free(Node2D.new()) as Node2D
	root.add_child(flank)
	flank.global_position = Vector2(100, 160)
	EnemyTestHelpers.hit(warden, 40.0, flank)
	assert_bool(warden.last_hit_blocked).is_false()


func test_rant_priest_empowers_allies() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var priest := EnemyTestHelpers.spawn(&"rant_priest", root, Vector2(100, 100)) as RantPriest
	var near := EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(130, 100))
	var far := EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(300, 100))
	await get_tree().physics_frame
	var buffed := priest.pulse_aura()
	assert_int(buffed.size()).is_equal(1)
	assert_bool(near.status.has(StatusEffect.Kind.EMPOWER)).is_true()
	assert_bool(far.status.has(StatusEffect.Kind.EMPOWER)).is_false()
	assert_float(near.status.damage_multiplier()).is_equal_approx(1.25, 0.001)


func test_vim_zealot_moves_cardinally() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(300, 140)
	var zealot := EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(100, 100))
	# 200 px away is past a zealot's sight range, and this case is about *how* it moves once it
	# is coming, not about when it notices. Awareness itself is measured in awareness_test.gd.
	zealot.alert()
	var start := zealot.global_position
	for _i in range(12):
		await get_tree().physics_frame
	var moved := zealot.global_position - start
	assert_float(moved.length()).is_greater(4.0)
	(
		assert_bool(absf(moved.x) < 0.5 or absf(moved.y) < 0.5)
		. override_failure_message("moved diagonally: %s" % moved)
		. is_true()
	)


## The owner, after playing: "green guys with swords are not walking around they either just
## stand still or only dash". A zealot used to hop one body-length and then stand for 0.3 s -
## eighteen physics frames of nothing, over and over, which reads as a broken enemy rather than
## a characterful one. Its steps are still cardinal (the case above); this one is about the
## gaps between them, so it measures the longest run of frames in which it did not move at all
## while it had a target and was still out of reach.
func test_vim_zealot_never_stalls_while_closing() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(420, 220)
	var zealot := EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(100, 100))
	zealot.alert()
	await get_tree().physics_frame
	var run := 0
	var worst := 0
	var last := zealot.global_position
	var frames := 0
	for _i in range(APPROACH_FRAMES):
		await get_tree().physics_frame
		if zealot.state != EnemyBase.State.APPROACH:
			break
		frames += 1
		run = run + 1 if zealot.global_position.distance_to(last) < STEP_EPSILON else 0
		worst = maxi(worst, run)
		last = zealot.global_position
	(
		assert_int(frames)
		. override_failure_message("never spent a frame approaching, so nothing was measured")
		. is_greater(APPROACH_FRAMES / 2)
	)
	(
		assert_int(worst)
		. override_failure_message(
			"stood still for %d physics frames (%.2f s) mid-approach" % [worst, worst / 60.0]
		)
		. is_less(STALL_FRAMES)
	)


## Walls around the interior of `ROOM`, plus a solid prop set flush into the top wall so a body
## crossing the room scrapes a PROP collider as well as a WORLD one.
func _tiny_room(root: Node2D) -> void:
	var half := WALL_THICK * 0.5
	var span := Vector2(ROOM.size.x + WALL_THICK * 2.0, WALL_THICK)
	var side := Vector2(WALL_THICK, ROOM.size.y + WALL_THICK * 2.0)
	EnemyTestHelpers.wall(root, Vector2(ROOM.size.x * 0.5, -half), span)
	EnemyTestHelpers.wall(root, Vector2(ROOM.size.x * 0.5, ROOM.size.y + half), span)
	EnemyTestHelpers.wall(root, Vector2(-half, ROOM.size.y * 0.5), side)
	EnemyTestHelpers.wall(root, Vector2(ROOM.size.x + half, ROOM.size.y * 0.5), side)
	EnemyTestHelpers.wall(root, Vector2(96, -6), Vector2(12, 12), Layers.PROP)


## The owner, shown the first fix: "it wasn't a large room it was a tiny room with 2 of them in
## - they never dashed even when I walked up and hit them".
##
## The cancel used to read `get_slide_collision_count() > 0`, and an enemy body masks
## WORLD | PROP (`enemy_base.tscn`, 4097). Somewhere cramped a zealot is in contact with a wall
## or a solid prop on nearly every frame - props only became solid colliders this round - so
## every dash died on the frame it started and the pause restarted, forever. Hitting them
## changed nothing: they woke, tried to dash, and were cancelled again.
##
## So the burst itself is what is measured, in a space narrow enough that the contact never
## stops. Grazing a wall it is sliding along, or brushing a prop, must not stop a dash; only a
## contact that actually opposes travel may.
func test_vim_zealots_still_dash_in_a_room_they_are_scraping_the_walls_of() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	_tiny_room(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(ROOM.size.x - 12.0, LANE)
	var pack: Array[EnemyBase] = [
		EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(14, LANE)),
		EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(44, LANE)),
	]
	await get_tree().physics_frame
	var opening: Array[float] = []
	var last: Array[Vector2] = []
	for zealot: EnemyBase in pack:
		EnemyTestHelpers.hit(zealot, 1.0, player)
		opening.append(zealot.global_position.distance_to(player.global_position))
		last.append(zealot.global_position)
	var fastest := 0.0
	var scraped := 0
	var chasing := 0
	for _i in range(APPROACH_FRAMES):
		await get_tree().physics_frame
		for i in range(pack.size()):
			var zealot := pack[i]
			if zealot.state == EnemyBase.State.APPROACH:
				chasing += 1
				fastest = maxf(fastest, zealot.global_position.distance_to(last[i]))
				scraped += mini(1, zealot.get_slide_collision_count())
			last[i] = zealot.global_position
	var closed := 0.0
	for i in range(pack.size()):
		var gap := pack[i].global_position.distance_to(player.global_position)
		closed = maxf(closed, opening[i] - gap)
	(
		assert_int(scraped)
		. override_failure_message(
			(
				"touched something on %d of %d chasing frames: the room proves nothing"
				% [scraped, chasing]
			)
		)
		. is_greater(chasing / 2)
	)
	(
		assert_float(closed)
		. override_failure_message("closed only %.0f px on a player in the same room" % closed)
		. is_greater(40.0)
	)
	(
		assert_float(fastest)
		. override_failure_message(
			"fastest frame was %.2f px, a walk: the dash was cancelled by wall contact" % fastest
		)
		. is_greater(DASH_STEP)
	)


func test_kernel_panic_spawns_six_spikes_and_tints() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(200, 200)
	var panic := EnemyTestHelpers.spawn(&"kernel_panic", root, Vector2(100, 100)) as KernelPanic
	var hazards: Array[Vector2] = []
	var tints: Array[int] = [0]
	_probe.watch(
		EventBus.spawn_hazard,
		func(kind: StringName, pos: Vector2, duration: float) -> void:
			if kind == &"kernel_spike":
				hazards.append(pos)
				assert_float(duration).is_equal(5.0)
	)
	_probe.watch(EventBus.screen_tint, func(_c: Color, _d: float) -> void: tints[0] += 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	panic.panic()
	_probe.release()
	assert_int(hazards.size()).is_equal(6)
	assert_int(tints[0]).is_equal(1)
	for pos: Vector2 in hazards:
		assert_float(pos.distance_to(player.global_position)).is_less(120.0)


func test_manpage_hurler_lobs_tome() -> void:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = Vector2(220, 100)
	var hurler := EnemyTestHelpers.spawn(&"manpage_hurler", root, Vector2(100, 100))
	var attacks: Array[int] = [0]
	hurler.attack_started.connect(func() -> void: attacks[0] += 1)
	for _i in range(120):
		await get_tree().physics_frame
		if attacks[0] > 0:
			break
	assert_int(attacks[0]).is_equal(1)
	var tomes := 0
	for child: Node in root.get_children():
		var shot := child as Projectile
		if shot != null:
			tomes += 1
			assert_float(shot.arc_gravity).is_greater(0.0)
			assert_float(shot.direction.y).is_less(0.0)
	assert_int(tomes).is_equal(1)
