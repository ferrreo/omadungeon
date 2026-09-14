## The owner's report, measured on a real floor rather than on a rig: "enemies should only path
## to the user after spotting them ... so they don't just hunt the user down as soon as the
## level starts".
##
## `awareness_test.gd` pins the rule and each way of waking one enemy. This asks the only
## question the player actually asked: start a run, stand still, and see whether the floor
## comes to you. Eight rounds of review missed this because nobody ever started a run and
## watched the dots.
class_name FloorAwarenessTest
extends GdUnitTestSuite

const SEED := 20250912
const CLASS_ID := &"fighter"
## Seconds of standing still at the spawn point.
const WATCH_SECONDS := 1.5
const PHYSICS_HZ := 60.0
## Longest a run's floor may take to build and populate before the case gives up on it.
const BUILD_TIMEOUT_MS := 10000
## Physics frames the floor's enemy count must hold still for before it counts as populated.
const SETTLE_FRAMES := 8
## How far an enemy may drift while asleep: `EnemyIdle`'s leash, plus the separation nudges
## between two enemies posted on the same spawn tile. Wider than a footstep and far narrower
## than a room - the case is "did it come for the player", not "did it move at all".
const DRIFT_TOLERANCE := EnemyIdle.DRIFT_RADIUS + 4.0
## How far around the player counts as "in this fight" when the pile-up is measured.
const FIGHT_RADIUS := 200.0
## Seconds a fight is watched for before the pile-up is counted.
const FIGHT_SECONDS := 6.0
## Enemies a room's own pack may be joined by before the fight has stopped being that room's.
## Not zero: a neighbouring room's pack that hears the fight through a doorway is the ally
## wake-up working, and one or two of those is a fight getting louder rather than a floor
## emptying itself into one room.
const NEIGHBOUR_SLACK := 2


func before_test() -> void:
	RunManager.manage_scenes = false
	RunManager.pending_summary = {}
	RunManager.offer_starting_passive = false
	SaveManager.delete_run()


func after_test() -> void:
	if RunManager.is_run_active():
		RunManager.abandon_run()
	RunManager.pending_summary = {}
	SaveManager.delete_run()
	await _frames(2)
	RunManager.manage_scenes = true
	RunManager.offer_starting_passive = true


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## Starts the run and waits for the floor to be *finished*: a deadline rather than a frame
## count, and settled rather than merely non-empty.
##
## Both halves of that matter and both were learned the hard way. A floor is assembled over
## several frames and its spawns go in through `PhysicsFlush`, so "six frames" is a guess that
## holds on an idle machine and fails on a loaded one; and "the first enemy has appeared" is
## not "the packs are in", so a whole-tree run - where everything is slower - measured one
## room's pack and reported that the floor had nothing to watch. The population has to stop
## changing before anything is counted.
func _start_run() -> FloorRoot:
	assert_bool(RunManager.new_run(SEED, CLASS_ID)).is_true()
	var deadline := Time.get_ticks_msec() + BUILD_TIMEOUT_MS
	var last := -1
	var settled := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var root := RunManager.floor_root()
		if root == null or RunManager.player() == null:
			continue
		var count := _floor_enemies(root).size()
		settled = settled + 1 if count > 0 and count == last else 0
		last = count
		if settled >= SETTLE_FRAMES:
			return root
	return null


## The enemies of the floor this run built — not everything in the "enemy" group. A suite that
## ran before this one can still have an enemy of its own in the tree when this one starts, and
## one of those, standing next to its own leftover player, walks: it made this case fail once
## in a whole-subtree run and pass every time it was run alone, which is the shape of a test
## that is measuring the wrong thing rather than of a bug.
func _floor_enemies(root: FloorRoot) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	if root == null:
		return out
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dying:
			continue
		if enemy.is_inside_tree() and root.is_ancestor_of(enemy):
			out.append(enemy)
	return out


func test_a_fresh_floor_does_not_send_its_enemies_at_a_player_who_is_standing_still() -> void:
	var floor_root := await _start_run()
	(
		assert_object(floor_root)
		. override_failure_message("the run never produced a populated floor")
		. is_not_null()
	)
	var player := RunManager.player()
	assert_object(player).is_not_null()
	var watched: Array[EnemyBase] = []
	var posts: Array[Vector2] = []
	for enemy: EnemyBase in _floor_enemies(floor_root):
		# Only the ones that cannot possibly have seen the player: anything nearer than that is
		# allowed to notice, and the start room is a legitimate place to be noticed in.
		if enemy.global_position.distance_to(player.global_position) <= enemy.awareness.sight:
			continue
		watched.append(enemy)
		posts.append(enemy.global_position)
	(
		assert_int(watched.size())
		. override_failure_message(
			(
				(
					"of %d enemies on this floor, %d are out of sight of the player; the case has"
					+ " nothing to watch and proves nothing"
				)
				% [_floor_enemies(floor_root).size(), watched.size()]
			)
		)
		. is_greater(1)
	)
	await _physics_frames(int(WATCH_SECONDS * PHYSICS_HZ))
	var marched: Array[String] = []
	for i in range(watched.size()):
		var enemy := watched[i]
		if not is_instance_valid(enemy):
			continue
		var moved := enemy.global_position.distance_to(posts[i])
		if moved > DRIFT_TOLERANCE or not enemy.is_asleep():
			marched.append(
				"%s moved %.0f px, asleep=%s" % [enemy.def.id, moved, str(enemy.is_asleep())]
			)
	(
		assert_array(marched)
		. override_failure_message(
			(
				"%d of %d enemies came for a player who had not moved: %s"
				% [marched.size(), watched.size(), ", ".join(marched)]
			)
		)
		. is_empty()
	)


## The other half of the same complaint: what a fight is *made of*. Standing in one room used
## to gather the floor, because every enemy on it had been walking toward the player since the
## first frame. A fight should be the pack of the room you are in.
func test_a_fight_is_the_pack_of_the_room_you_are_standing_in() -> void:
	var root := await _start_run()
	assert_object(root).is_not_null()
	var player := RunManager.player()
	assert_object(player).is_not_null()
	var room := _busiest_room(root)
	(
		assert_object(room)
		. override_failure_message("the generated floor has no room with a pack in it")
		. is_not_null()
	)
	var pack := room.pending_enemy_count()
	# The measurement is "who turns up", not "who wins": six seconds of standing in a pack is
	# survivable on floor one today, and a later tuning pass to the difficulty curve must not
	# turn this case into a crash when the player dies halfway through it.
	player.health.invulnerable = true
	player.global_position = room.center_world()
	player.velocity = Vector2.ZERO
	await _physics_frames(int(FIGHT_SECONDS * PHYSICS_HZ))
	var crowd := 0
	for enemy: EnemyBase in _floor_enemies(root):
		if enemy.global_position.distance_to(player.global_position) <= FIGHT_RADIUS:
			crowd += 1
	print(
		(
			"[awareness] room %d: pack of %d, %d enemies within %.0f px after %.0f s"
			% [room.id, pack, crowd, FIGHT_RADIUS, FIGHT_SECONDS]
		)
	)
	(
		assert_int(crowd)
		. override_failure_message(
			(
				"standing in room %d for %.0f s gathered %d enemies around a pack of %d"
				% [room.id, FIGHT_SECONDS, crowd, pack]
			)
		)
		. is_less_equal(pack + NEIGHBOUR_SLACK)
	)


## The room on this floor with the most enemies still alive in it.
func _busiest_room(root: FloorRoot) -> RoomNode:
	var best: RoomNode = null
	for room: RoomNode in root.rooms:
		if best == null or room.pending_enemy_count() > best.pending_enemy_count():
			best = room
	if best != null and best.pending_enemy_count() <= 0:
		return null
	return best
