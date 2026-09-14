## The freed-instance landmine, on the shipped paths that really do carry a reference across a
## frame boundary or across an arbitrary listener. All three subjects are an enemy dying and
## something it left behind still running.
##
## `tests/unit/freed_instance_test.gd` establishes the first half of the mechanics: with no
## script debugger attached - every headless run, every capture, the packaged game - a GDScript
## *call* on a freed instance is a SIGSEGV, not an error.
##
## These cases establish the second half, which is quieter and turned out to be the one shipped
## code was actually falling into. Measured on this build (Godot 4.7): `freed != null` is
## **false**, so a plain null check does notice a freed reference - but *passing one on* to a
## **statically typed** boundary raises and abandons the call. `DamageInfo.create(..., from:
## Node2D, ...)` is such a boundary, and the two producers below both handed it an attacker they
## had never checked. Nothing crashes. The hit simply deals nothing, the burn simply stops
## burning, and the only trace is one line on stderr.
##
## The cases, all built on real nodes rather than on a probe:
##
## * **An enemy dying while a listener tears the floor down.** `EnemyBase._die` emits
##   `EventBus.enemy_died` and then keeps working on itself. A boss kill can end the run and a
##   room clear can start the next floor, and both reach `FloorRoot.clear_floor()`, which
##   `remove_child`s the whole branch *synchronously*. Everything after the emit then runs on a
##   node whose `get_tree()` is null - including the fallback timer that is the only thing
##   guaranteeing the corpse is ever freed.
## * **A projectile outliving the enemy that fired it.** `Hitbox.source` is the one reference a
##   hitbox keeps to something it does not own, and a shot in the air routinely outlives its
##   shooter by the whole death animation.
## * **A burn or a taunt outliving the enemy that applied it.** `StatusController` holds
##   `StatusEffect.source` for the whole duration of the effect, which is longer than the
##   `DEATH_FALLBACK_TIME` the corpse is freed after.
class_name EnemyDeathTeardownTest
extends GdUnitTestSuite

## An ordinary melee enemy: the death path under test is `EnemyBase`'s, not a boss override's.
const ENEMY_ID := &"honker"
## The COMBAT room of `RoomsTestFixtures.three_rooms()`.
const COMBAT_ROOM := 1
## More than any enemy in the registry has.
const LETHAL := 100000.0
## Long enough that the burn is still running after its applier has been freed.
const BURN_SECONDS := 3.0
const BURN_DPS := 6.0
## Physics frames a DoT tick is waited for (`StatusController.DOT_TICK` is 0.5 s at 60 Hz).
const TICK_FRAMES := 90

var _root: FloorRoot
var _probe := EventBusProbe.new()


func before_test() -> void:
	_root = auto_free(FloorRoot.new())
	add_child(_root)
	_root.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)


func after_test() -> void:
	_probe.release()


func _settle(frames: int = 2) -> void:
	for _i in range(frames):
		await get_tree().process_frame


## The known instance. A listener on `enemy_died` tears the floor down the way `RunManager` does
## at a run end, so the rest of `_die` runs on an enemy that has already left the tree. The
## enemy has to retire itself anyway: the fallback timer it would normally schedule cannot
## exist, because there is no `SceneTree` left to create it in, and the corpse is nobody else's
## job. A run that does not reach the assertion at all - an abort on a null tree, or worse - is
## the same regression.
func test_death_survives_the_floor_being_torn_down_by_the_death_signal() -> void:
	var room := _root.get_room(COMBAT_ROOM)
	assert_object(room).is_not_null()
	var enemy := EnemyTestHelpers.spawn(ENEMY_ID, room, room.center_world())
	var pack: Array[Node2D] = [enemy]
	room.populate(pack)
	var torn := [false]
	_probe.watch(
		EventBus.enemy_died,
		func(_enemy: Node2D, _killer: Node2D) -> void:
			torn[0] = true
			_root.clear_floor()
	)

	EnemyTestHelpers.hit(enemy, LETHAL)

	assert_bool(bool(torn[0])).override_failure_message("the teardown listener never ran").is_true()
	assert_bool(is_instance_valid(enemy)).is_true()
	(
		assert_bool(enemy.is_inside_tree())
		. override_failure_message("clear_floor() was expected to pull the enemy out of the tree")
		. is_false()
	)
	(
		assert_bool(enemy.is_queued_for_deletion())
		. override_failure_message(
			(
				"EnemyBase._die left the corpse behind: the floor was torn down inside "
				+ "EventBus.enemy_died, so get_tree() is null and the death fallback timer "
				+ "could not be created. The death path must finish itself instead."
			)
		)
		. is_true()
	)
	await _settle()


## The same guard on the ordinary path: nothing torn down, so the enemy still gets its
## animation and its fallback timer, and it frees itself the way it always did.
func test_an_ordinary_death_still_schedules_its_own_removal() -> void:
	var room := _root.get_room(COMBAT_ROOM)
	var enemy := EnemyTestHelpers.spawn(ENEMY_ID, room, room.center_world())
	var pack: Array[Node2D] = [enemy]
	room.populate(pack)

	EnemyTestHelpers.hit(enemy, LETHAL)

	assert_bool(is_instance_valid(enemy)).is_true()
	assert_bool(enemy.is_inside_tree()).is_true()
	assert_bool(enemy.is_queued_for_deletion()).is_false()
	assert_int(enemy.state).is_equal(EnemyBase.State.DEAD)
	await _settle()


## `Hitbox.source` outliving its owner. The shooter is freed while the shot is still in the air
## - an enemy is freed `DEATH_FALLBACK_TIME` after it dies and a shot lives `lifetime` seconds -
## and `build_info` handed that reference straight to `DamageInfo.create(..., from: Node2D, ...)`
## without checking it. The typed parameter refuses it, the call is abandoned, and the shot flies
## through its target dealing nothing. The attacker has to be validated before it is passed on,
## and what reaches the listeners has to be null rather than dangling - `RunTally`,
## `SaveManager.attribution_id` and `Player` all re-check, and they can only do that honestly if
## what they were given is honest.
func test_a_shot_still_builds_damage_after_its_shooter_is_freed() -> void:
	var arena := auto_free(Node2D.new()) as Node2D
	add_child(arena)
	var shooter := EnemyTestHelpers.spawn(ENEMY_ID, arena, Vector2.ZERO)
	var shot := auto_free(Projectile.new()) as Projectile
	shot.trail_enabled = false
	shot.impact_puff = false
	shot.setup(shooter, Layers.Team.ENEMY, Vector2.RIGHT, Callable())
	arena.add_child(shot)
	shot.global_position = Vector2(40.0, 0.0)
	shot.set_physics_process(false)
	assert_object(shot.hitbox.source).is_same(shooter)

	shooter.queue_free()
	await _settle()

	assert_bool(is_instance_valid(shot.hitbox.source)).is_false()
	# Standing exactly on the shot is the degenerate direction that sent `build_info` looking at
	# the shooter for a fallback.
	var victim := auto_free(Node2D.new()) as Node2D
	arena.add_child(victim)
	victim.global_position = shot.global_position

	var info := shot.hitbox.build_info(victim)

	assert_object(info).is_not_null()
	(
		assert_object(info.source)
		. override_failure_message("a freed attacker must reach listeners as null, not dangling")
		. is_null()
	)
	assert_float(info.amount).is_greater(0.0)


## A burn outliving the enemy that lit it. `StatusController` keeps `StatusEffect.source` for the
## whole duration of the effect, and the enemy that applied it is freed a second and a half after
## it dies - well inside a three-second burn. The tick then hands that reference to
## `DamageInfo.create`, the typed parameter refuses it, and the tick is abandoned: the burn stops
## dealing damage for the rest of its duration and the player never knows.
func test_a_burn_keeps_ticking_after_the_enemy_that_lit_it_is_freed() -> void:
	var arena := auto_free(Node2D.new()) as Node2D
	add_child(arena)
	var burner := EnemyTestHelpers.spawn(ENEMY_ID, arena, Vector2.ZERO)
	var victim := auto_free(EnemyTestPlayer.new()) as EnemyTestPlayer
	arena.add_child(victim)
	victim.global_position = Vector2(64.0, 0.0)
	victim.status.apply(StatusEffect.make(StatusEffect.Kind.BURN, BURN_SECONDS, BURN_DPS, burner))
	var burn: StatusEffect = victim.status.effects[StatusEffect.Kind.BURN]
	assert_object(burn.source).is_same(burner)

	burner.queue_free()
	await _settle()
	assert_bool(victim.status.has(StatusEffect.Kind.BURN)).is_true()

	var before := victim.health.hp
	var ticked := false
	for _frame in range(TICK_FRAMES):
		await get_tree().physics_frame
		if victim.health.hp < before:
			ticked = true
			break

	(
		assert_bool(ticked)
		. override_failure_message(
			(
				"the burn stopped dealing damage when the enemy that applied it was freed: "
				+ "StatusController handed the freed source to DamageInfo.create()"
			)
		)
		. is_true()
	)
	assert_object(burn.source).is_null()


## The taunt half of the same reference. This one was already harmless - `EnemyBase._update_target`
## asks `is_instance_valid(taunter)` before it latches on - so it is a pin rather than a repair:
## the controller now drops the dead reference itself, and this is what says so.
func test_taunt_source_reports_null_once_the_taunter_is_freed() -> void:
	var arena := auto_free(Node2D.new()) as Node2D
	add_child(arena)
	var taunter := EnemyTestHelpers.spawn(ENEMY_ID, arena, Vector2.ZERO)
	var victim := auto_free(EnemyTestPlayer.new()) as EnemyTestPlayer
	arena.add_child(victim)
	victim.status.apply(StatusEffect.make(StatusEffect.Kind.TAUNT, BURN_SECONDS, 0.0, taunter))
	assert_object(victim.status.taunt_source()).is_same(taunter)

	taunter.queue_free()
	await _settle()

	assert_bool(victim.status.is_taunted()).is_true()
	assert_object(victim.status.taunt_source()).is_null()
