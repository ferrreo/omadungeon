## "Enemies should only path to the user after spotting them or the user is in their room so
## they don't just hunt the user down as soon as the level starts" — the owner, after playing
## the shipped build.
##
## Every case here is about that sentence. The rule itself is asserted once without a scene
## (`EnemyAwareness` is a plain object), and then the four ways a real enemy in a real tree can
## come to notice a real player — sight, the room trigger, a hit, and a neighbour passing the
## word — are each measured with the thing that causes them, not by calling the wake directly.
class_name EnemyAwarenessTest
extends GdUnitTestSuite

const PHYSICS_HZ := 60.0
## A wall thick and tall enough that nothing sees past it.
const WALL_SIZE := Vector2(8, 320)


func _profile() -> AwarenessProfile:
	return AwarenessProfile.shared()


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## Frames worth of `seconds`, plus a few for the physics step the answer lands on.
func _frames_for(seconds: float) -> int:
	return int(ceilf(seconds * PHYSICS_HZ)) + 4


## One perception probe's worth of frames.
func _probe_frames() -> int:
	return _frames_for(_profile().probe_interval)


func _root() -> Node2D:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	return root


func _player(root: Node2D, pos: Vector2) -> EnemyTestPlayer:
	var player := EnemyTestPlayer.new()
	root.add_child(player)
	player.global_position = pos
	return player


# --- the rule, with no scene in the way ------------------------------------------------------


func test_the_rule_wakes_on_sight_only_and_settles_after_it_loses_contact() -> void:
	var profile := _profile()
	var sense := EnemyAwareness.new()
	sense.configure(profile, 160.0, false)
	assert_bool(sense.is_awake()).is_false()
	(
		assert_bool(sense.perceive(200.0, true))
		. override_failure_message("woke to something 200 px away with a 160 px sight range")
		. is_false()
	)
	(
		assert_bool(sense.perceive(100.0, false))
		. override_failure_message("woke to something it could not see")
		. is_false()
	)
	assert_bool(sense.perceive(100.0, true)).is_true()
	assert_bool(sense.is_awake()).is_true()
	# Only the first probe is a wake-up: the tell must not re-fire every probe of a long fight.
	assert_bool(sense.perceive(100.0, true)).is_false()
	# Contact survives a step past the sight range, so a player edging backwards does not
	# switch the fight off and on again.
	assert_bool(sense.perceive(160.0 * profile.forget_slack - 1.0, true)).is_false()
	assert_bool(sense.has_contact()).is_true()
	sense.perceive(600.0, false)
	assert_that(sense.stance).is_equal(EnemyAwareness.Stance.SEARCHING)
	assert_bool(sense.is_awake()).is_true()
	var step := 1.0 / PHYSICS_HZ
	var spent := 0.0
	while sense.is_awake() and spent < profile.search_seconds + 1.0:
		sense.tick(step)
		spent += step
	assert_bool(sense.is_awake()).is_false()
	assert_float(spent).is_equal_approx(profile.search_seconds, 0.1)


func test_a_close_enough_target_is_noticed_with_no_line_of_sight_at_all() -> void:
	var profile := _profile()
	var sense := EnemyAwareness.new()
	sense.configure(profile, 160.0, false)
	assert_bool(sense.perceive(profile.close_range - 1.0, false)).is_true()


func test_a_boss_never_sleeps_and_cannot_be_settled() -> void:
	var sense := EnemyAwareness.new()
	sense.configure(_profile(), 160.0, true)
	assert_bool(sense.is_awake()).is_true()
	sense.perceive(9000.0, false)
	sense.settle()
	assert_bool(sense.is_awake()).is_true()
	(
		assert_that(sense.stance)
		. override_failure_message("a boss that cannot settle was left searching for the player")
		. is_equal(EnemyAwareness.Stance.ALERT)
	)


# --- a real pack in a real tree --------------------------------------------------------------


## The owner's complaint, in one case: enemies that have not seen you do not walk at you.
func test_a_pack_across_the_floor_holds_its_post() -> void:
	var root := _root()
	var player := _player(root, Vector2.ZERO)
	EnemyTestHelpers.wall(root, Vector2(200, 0), WALL_SIZE)
	var pack: Array[EnemyBase] = [
		EnemyTestHelpers.spawn(&"honker", root, Vector2(400, 0)),
		EnemyTestHelpers.spawn(&"juggler", root, Vector2(430, 40)),
		EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(460, -40)),
	]
	var posts: Array[Vector2] = []
	var openings: Array[float] = []
	await _frames(2)
	for enemy: EnemyBase in pack:
		posts.append(enemy.global_position)
		openings.append(enemy.global_position.distance_to(player.global_position))
	await _frames(int(PHYSICS_HZ))
	# The leash, not zero: `EnemyIdle` shifts a sleeping enemy a few px around its post so a
	# room does not read as statues. What must not happen is any of that drift being *toward*
	# the player, which the second assertion is what actually measures.
	var leash := EnemyIdle.DRIFT_RADIUS + _profile().home_tolerance
	for i in range(pack.size()):
		var enemy := pack[i]
		(
			assert_bool(enemy.is_asleep())
			. override_failure_message(
				(
					"%s woke up on its own %.0f px away behind a wall"
					% [enemy.def.id, enemy.global_position.distance_to(player.global_position)]
				)
			)
			. is_true()
		)
		(
			assert_float(enemy.global_position.distance_to(posts[i]))
			. override_failure_message("%s left its post without noticing anything" % enemy.def.id)
			. is_less(leash)
		)
		(
			assert_float(enemy.global_position.distance_to(player.global_position))
			. override_failure_message("%s closed on a player it has not seen" % enemy.def.id)
			. is_greater(openings[i] - leash)
		)


func test_a_wall_between_them_is_not_seen_through() -> void:
	var root := _root()
	_player(root, Vector2(100, 0))
	EnemyTestHelpers.wall(root, Vector2(50, 0), WALL_SIZE)
	var enemy := EnemyTestHelpers.spawn(&"juggler", root, Vector2.ZERO)
	await _frames(_probe_frames() * 2)
	(
		assert_bool(enemy.is_asleep())
		. override_failure_message("saw the player through a wall 100 px away")
		. is_true()
	)


func test_walking_into_its_line_of_sight_wakes_it_and_it_then_comes() -> void:
	var root := _root()
	var player := _player(root, Vector2(300, 0))
	var enemy := EnemyTestHelpers.spawn(&"config_gremlin", root, Vector2.ZERO)
	await _frames(_probe_frames())
	assert_bool(enemy.is_asleep()).is_true()
	assert_bool(enemy.alert_mark.is_showing()).is_false()
	# The player walks into view. Nothing else changes.
	player.global_position = Vector2(120, 0)
	await _frames(_probe_frames())
	(
		assert_bool(enemy.is_asleep())
		. override_failure_message("stayed asleep with the player in plain sight 120 px away")
		. is_false()
	)
	(
		assert_bool(enemy.alert_mark.is_showing())
		. override_failure_message("noticed the player with nothing on screen to show for it")
		. is_true()
	)
	# Measured from where it stands *now*, not from where the player used to be: comparing
	# against the pre-walk distance would be satisfied by the player having moved closer, and
	# would pass just as happily against an enemy that never took a step.
	var gap := enemy.global_position.distance_to(player.global_position)
	await _frames(30)
	(
		assert_float(enemy.global_position.distance_to(player.global_position))
		. override_failure_message(
			(
				"noticed the player %.0f px away and was still %.0f px away half a second later"
				% [gap, enemy.global_position.distance_to(player.global_position)]
			)
		)
		. is_less(gap - 20.0)
	)


## The "!" is a tell, not a state: it clears itself and leaves the enemy chasing.
func test_the_wake_up_tell_pops_above_the_health_bar_and_clears_itself() -> void:
	var root := _root()
	_player(root, Vector2(60, 0))
	var enemy := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	await _frames(_probe_frames())
	assert_bool(enemy.alert_mark.is_showing()).is_true()
	assert_bool(enemy.alert_mark.visible).is_true()
	(
		assert_float(enemy.alert_mark.position.y)
		. override_failure_message("the tell is drawn on top of the health bar")
		. is_less(enemy.hp_bar.position.y)
	)
	await _frames(_frames_for(_profile().mark_seconds))
	assert_bool(enemy.alert_mark.is_showing()).is_false()
	assert_bool(enemy.alert_mark.visible).is_false()
	assert_bool(enemy.is_asleep()).is_false()


func test_a_hit_wakes_an_enemy_that_never_saw_it_coming() -> void:
	var root := _root()
	_player(root, Vector2(600, 0))
	var enemy := EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2.ZERO)
	await _frames(_probe_frames())
	assert_bool(enemy.is_asleep()).is_true()
	EnemyTestHelpers.hit(enemy, 5.0)
	assert_bool(enemy.is_asleep()).is_false()


## A hit is loud. The neighbours turn a beat later — the ripple is deliberate, so a pack
## noticing you reads as a pack and not as one synchronised snap — and only the neighbours.
func test_a_wake_up_ripples_to_nearby_allies_and_no_further() -> void:
	var profile := _profile()
	var root := _root()
	_player(root, Vector2(900, 0))
	var hit_one := EnemyTestHelpers.spawn(&"honker", root, Vector2.ZERO)
	var near := EnemyTestHelpers.spawn(&"juggler", root, Vector2(profile.ally_wake_radius - 8.0, 0))
	var far := EnemyTestHelpers.spawn(&"juggler", root, Vector2(profile.ally_wake_radius * 3.0, 0))
	await _frames(2)
	EnemyTestHelpers.hit(hit_one, 5.0)
	assert_bool(hit_one.is_asleep()).is_false()
	(
		assert_bool(near.is_asleep())
		. override_failure_message("the whole pack turned on the same frame")
		. is_true()
	)
	await _frames(_frames_for(profile.ally_wake_delay))
	(
		assert_bool(near.is_asleep())
		. override_failure_message("the neighbour never heard the fight next to it")
		. is_false()
	)
	(
		assert_bool(far.is_asleep())
		. override_failure_message(
			(
				"a fight %.0f px away woke an enemy it should not have"
				% (profile.ally_wake_radius * 3.0)
			)
		)
		. is_true()
	)


func test_an_enemy_that_loses_the_player_settles_back_and_walks_home() -> void:
	var profile := _profile()
	var root := _root()
	var player := _player(root, Vector2(120, 0))
	var enemy := EnemyTestHelpers.spawn(&"config_gremlin", root, Vector2.ZERO)
	var home := enemy.global_position
	await _frames(_probe_frames())
	assert_bool(enemy.is_asleep()).is_false()
	await _frames(40)
	(
		assert_float(enemy.global_position.distance_to(home))
		. override_failure_message("never left its post, so there is nothing to settle from")
		. is_greater(8.0)
	)
	player.queue_free()
	var gave_up := 0.0
	for _i in range(_frames_for(profile.search_seconds + 2.0)):
		await get_tree().physics_frame
		gave_up += 1.0 / PHYSICS_HZ
		if enemy.is_asleep():
			break
	(
		assert_bool(enemy.is_asleep())
		. override_failure_message("still hunting a player that is not there any more")
		. is_true()
	)
	(
		assert_float(gave_up)
		. override_failure_message(
			"gave up after %.1f s; the profile says %.1f s" % [gave_up, profile.search_seconds]
		)
		. is_between(profile.search_seconds * 0.75, profile.search_seconds + 1.0)
	)
	var settled := false
	for _i in range(_frames_for(6.0)):
		await get_tree().physics_frame
		if enemy.global_position.distance_to(home) <= profile.home_tolerance:
			settled = true
			break
	(
		assert_bool(settled)
		. override_failure_message(
			(
				"gave up %.0f px from its post and stayed there"
				% enemy.global_position.distance_to(home)
			)
		)
		. is_true()
	)


func test_a_boss_is_already_in_the_fight_when_the_player_arrives() -> void:
	var root := _root()
	_player(root, Vector2(400, 0))
	var boss := EnemyTestHelpers.spawn(&"ringmaster", root, Vector2.ZERO)
	await _frames(2)
	assert_bool(boss.is_asleep()).is_false()


func test_what_an_enemy_spawns_mid_fight_arrives_awake() -> void:
	var root := _root()
	_player(root, Vector2(100, 0))
	var golem := EnemyTestHelpers.spawn(&"dotfile_golem", root, Vector2.ZERO)
	await _frames(_probe_frames())
	assert_bool(golem.is_asleep()).is_false()
	EnemyTestHelpers.hit(golem, 99999.0)
	await _frames(2)
	var spawned := 0
	for child: Node in root.get_children():
		var gremlin := child as EnemyBase
		if gremlin == null or gremlin == golem:
			continue
		spawned += 1
		(
			assert_bool(gremlin.is_asleep())
			. override_failure_message("a %s split out of a fight and stood there" % gremlin.def.id)
			. is_false()
		)
	assert_int(spawned).is_equal(3)


# --- the room trigger ------------------------------------------------------------------------


## The other half of the owner's sentence: "or the user is in their room". The player is moved
## into a real room's real trigger, and the enemy it wakes is one that cannot see them — a wall
## stands between the door and where it is posted.
func test_entering_the_room_wakes_the_pack_that_cannot_see_the_door() -> void:
	var floor_root := auto_free(FloorRoot.new()) as FloorRoot
	add_child(floor_root)
	floor_root.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	var player := auto_free(RoomsTestFixtures.make_player()) as CharacterBody2D
	add_child(player)
	player.global_position = Vector2(-400, -400)
	var room := floor_root.get_room(1)
	var post := Vector2(248, 72)
	var enemy := EnemySpawner.instantiate(
		EnemyTestHelpers.def(&"config_gremlin"), 0, post, EnemyTestHelpers.seeded(7)
	)
	var pack: Array[Node2D] = [enemy]
	room.populate(pack)
	enemy.global_position = post
	# A blind corner inside the room: the enemy is 48 px from the doorway and cannot see it.
	EnemyTestHelpers.wall(floor_root, Vector2(232, 64), Vector2(6, 44))
	await _frames(4)
	assert_int(enemy.room_id).is_equal(1)
	assert_bool(enemy.is_asleep()).is_true()
	# Inside the room's trigger, which is the room rect shrunk by a tile (world x 208..256,
	# y 48..80), and on the far side of the blind corner from the enemy.
	player.global_position = Vector2(216, 56)
	await _frames(_probe_frames())
	(
		assert_bool(enemy.has_line_of_sight(player.global_position))
		. override_failure_message("the blind corner does not block sight; the case proves nothing")
		. is_false()
	)
	(
		assert_bool(enemy.is_asleep())
		. override_failure_message("the player walked into its room and it never looked up")
		. is_false()
	)


## A summon's post is where it lands, not the origin of the world. `PhysicsFlush` writes a
## spawned node's position after the insertion, so an enemy that read its home in `_ready`
## recorded (0, 0) and walked off the floor the first time it settled.
func test_a_spawned_enemy_takes_the_place_it_landed_as_its_post() -> void:
	var root := _root()
	var far_post := Vector2(720, 480)
	var enemy := EnemySpawner.instantiate(
		EnemyTestHelpers.def(&"juggler"), 0, far_post, EnemyTestHelpers.seeded(3)
	)
	PhysicsFlush.add_child_at(root, enemy, far_post)
	await _frames(3)
	(
		assert_float(enemy.home_position.distance_to(far_post))
		. override_failure_message("its post is %s, not where it was put" % enemy.home_position)
		. is_less(1.0)
	)


## A taunt is being noticed at. An enemy pulled onto a target it has not spotted must not
## stand at its post with the taunt ticking away on it.
func test_a_taunt_wakes_the_enemy_it_pulls() -> void:
	var root := _root()
	_player(root, Vector2(700, 0))
	var enemy := EnemyTestHelpers.spawn(&"juggler", root, Vector2.ZERO)
	await _frames(_probe_frames())
	assert_bool(enemy.is_asleep()).is_true()
	var taunter := auto_free(EnemyTestPlayer.new()) as EnemyTestPlayer
	root.add_child(taunter)
	taunter.global_position = Vector2(0, 600)
	enemy.status.apply(StatusEffect.make(StatusEffect.Kind.TAUNT, 1.0, 0.0, taunter))
	await _frames(2)
	assert_object(enemy.target).is_same(taunter)
	(
		assert_bool(enemy.is_asleep())
		. override_failure_message("taunted onto a target it is not willing to walk toward")
		. is_false()
	)


## The tell is not only the mark: a 16 px figure turning to face you is what reads from across
## a room. An enemy posted facing away must be looking at the player on the frame it notices.
func test_it_turns_to_face_whoever_it_just_noticed() -> void:
	var root := _root()
	var player := _player(root, Vector2(-120, 0))
	var enemy := EnemyTestHelpers.spawn(&"juggler", root, Vector2.ZERO)
	await _frames(2)
	enemy.face(Vector2(200, 0))
	assert_float(enemy.facing.x).is_greater(0.0)
	await _frames(_probe_frames())
	assert_bool(enemy.is_asleep()).is_false()
	(
		assert_float(enemy.facing.x)
		. override_failure_message("noticed the player behind it and kept looking the other way")
		. is_less(0.0)
	)
	assert_bool(enemy.sprite.flip_h).is_true()


## Same guard as the health bars': `shared()` falls back to script defaults when the resource
## cannot be loaded, and those defaults match the shipped file, so a broken path would go
## unnoticed by every other case here.
func test_the_shipped_awareness_file_is_the_one_the_enemies_read() -> void:
	(
		assert_bool(ResourceLoader.exists(AwarenessProfile.PATH))
		. override_failure_message("%s is missing" % AwarenessProfile.PATH)
		. is_true()
	)
	var on_disk := load(AwarenessProfile.PATH) as AwarenessProfile
	assert_object(on_disk).is_not_null()
	(
		assert_object(AwarenessProfile.shared())
		. override_failure_message("enemies notice from code defaults, not from the .tres")
		. is_same(on_disk)
	)


## The other half of the owner's report ("they either just stand still or only dash"): holding
## a post must not mean being a statue. `EnemyIdle` ambles a sleeping enemy a few px around
## where it was placed, which is life the player can see; what it must never do is close
## distance on a player it has not noticed, or wake itself up by wandering into sight. All
## three are measured here - it moved, it stayed leashed, and the gap to the player did not
## shrink - because only the first two together are what the owner asked for.
func test_a_sleeping_enemy_shifts_about_its_post_without_coming_for_you() -> void:
	var root := _root()
	var player := _player(root, Vector2(600, 0))
	var enemy := EnemyTestHelpers.spawn(&"vim_zealot", root, Vector2(100, 100))
	await _frames(2)
	var home := enemy.global_position
	var opening := enemy.global_position.distance_to(player.global_position)
	var wandered := 0.0
	for _i in range(_frames_for(6.0)):
		await get_tree().physics_frame
		wandered = maxf(wandered, enemy.global_position.distance_to(home))
		if not enemy.is_asleep():
			break
	var leash := EnemyIdle.DRIFT_RADIUS + _profile().home_tolerance
	(
		assert_bool(enemy.is_asleep())
		. override_failure_message("woke up with the player 600 px away and nothing to see")
		. is_true()
	)
	(
		assert_float(wandered)
		. override_failure_message("never moved a pixel in six seconds: a statue, not an enemy")
		. is_greater(EnemyIdle.MIN_STEP * 0.5)
	)
	(
		assert_float(wandered)
		. override_failure_message("left its post by %.0f px without noticing anything" % wandered)
		. is_less(leash)
	)
	(
		assert_float(enemy.global_position.distance_to(player.global_position))
		. override_failure_message("drifted toward a player it has not seen")
		. is_greater(opening - leash)
	)
