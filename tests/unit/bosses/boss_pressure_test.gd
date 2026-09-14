## What a boss fight *costs*, for all three bosses at once.
##
## The playtest: "Bosses are HP sponges, not climaxes. The floor-3 boss takes 47 seconds and
## costs 13 HP." Every assertion here is about that: how long the pool survives a reference
## damage output, and how much harder the boss hits as its phases advance. The per-boss suites
## next door test the moveset; this one tests the shape of the encounter.
class_name BossPressureTest
extends GdUnitTestSuite

## Damage per second a run actually puts out when it reaches the first boss, and how much
## that grows per floor as gear and abilities stack up. Both come off the balance
## simulation's own boss table: the Ringmaster's pool divides out at ~36 DPS on floor 3 and
## The Suit's at ~100 on floor 9. A single flat number would be the wrong yardstick — a
## floor-9 build is three times the floor-3 one, which is exactly why a fixed boss HP pool
## cannot be right for all three.
const REFERENCE_DPS_AT_FIRST_BOSS := 36.0
const REFERENCE_DPS_GROWTH := 1.185
## Seconds of actual damage race a boss pool may cost. The arena adds roughly another twelve
## on top (entrance, phase transitions, repositioning), so this band is a 20-34 s fight. The
## shipped pools took 43-47 s of which the player spent most of it holding a button.
const MAX_FIGHT_SECONDS := 22.0
## ... and may not be so small that it dies before its second phase is seen.
const MIN_FIGHT_SECONDS := 8.0
## The last phase has to hit appreciably harder than the first.
const MIN_LAST_PHASE_DAMAGE_RATIO := 1.5
## Share of a boss's swings that connect against a player reading its tells well.
const LANDED_SHARE := 0.25
## Share of the player's health pool a boss must be able to take even so.
const MIN_THREAT_SHARE := 0.35

## Boss id -> the 0-based floor it is fought on (RunManager.BOSS_FLOORS).
const BOSSES: Dictionary = {&"ringmaster": 2, &"elder_greybeard": 5, &"the_suit": 8}


func _arena() -> Node2D:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	return root


## Damage per second a run puts out on `floor_index`.
func _reference_dps(floor_index: int) -> float:
	var boss_slot := RunSimulator.BOSS_FLOORS[0]
	return REFERENCE_DPS_AT_FIRST_BOSS * pow(REFERENCE_DPS_GROWTH, float(floor_index - boss_slot))


## Seconds of damage race `id`'s pool costs on the floor it is met.
func _fight_seconds(id: StringName, floor_index: int) -> float:
	var def := EnemyTestHelpers.def(id)
	var pool := def.scaled_hp(floor_index) / Stats.armor_multiplier(def.armor)
	return pool / _reference_dps(floor_index)


func _spawn(id: StringName, floor_index: int) -> BossBase:
	var boss := EnemyTestHelpers.spawn(id, _arena(), Vector2(160, 160), floor_index) as BossBase
	assert_object(boss).override_failure_message("%s did not spawn" % String(id)).is_not_null()
	boss.set_arena(Vector2(160, 160), 110.0)
	return boss


func test_every_boss_dies_inside_the_fight_window() -> void:
	for id: StringName in BOSSES.keys():
		var floor_index: int = BOSSES[id]
		var seconds := _fight_seconds(id, floor_index)
		(
			assert_float(seconds)
			. override_failure_message(
				(
					"%s on floor %d takes %.0f s of damage race at %.0f DPS"
					% [String(id), floor_index + 1, seconds, _reference_dps(floor_index)]
				)
			)
			. is_between(MIN_FIGHT_SECONDS, MAX_FIGHT_SECONDS)
		)


func test_every_boss_can_kill_the_player_it_is_fought_by() -> void:
	# A boss that cannot empty a health bar inside its own fight window threatens nothing. The
	# bar it is measured against is the one a run of that depth actually carries.
	for id: StringName in BOSSES.keys():
		var floor_index: int = BOSSES[id]
		var def := EnemyTestHelpers.def(id)
		var seconds := _fight_seconds(id, floor_index)
		var cycle := SimEncounter.attack_cycle(def)
		var swings := seconds / cycle
		var per_swing := def.scaled_damage(floor_index)
		# A generous player reads and dodges three swings in four; what lands still has to
		# threaten a floor-appropriate health bar (100 base + 5/vitality, grown over the run),
		# and it lands harder as the phases advance.
		var pressure := SimEncounter.boss_phase_pressure(def)
		var landed := swings * per_swing * pressure * LANDED_SHARE
		var player_pool := 130.0 + 22.0 * float(floor_index)
		(
			assert_float(landed / player_pool)
			. override_failure_message(
				(
					"%s lands %.0f damage over its fight against a %.0f HP player"
					% [String(id), landed, player_pool]
				)
			)
			. is_greater(MIN_THREAT_SHARE)
		)


func test_each_phase_hits_harder_and_more_often_than_the_last() -> void:
	for id: StringName in BOSSES.keys():
		var boss := _spawn(id, BOSSES[id])
		await get_tree().physics_frame
		var first := boss.phase_damage_multiplier(1)
		var last := boss.phase_damage_multiplier(boss.phase_count())
		(
			assert_float(last / maxf(0.01, first))
			. override_failure_message(
				"%s's last phase hits %.2fx as hard as its first" % [String(id), last / first]
			)
			. is_greater_equal(MIN_LAST_PHASE_DAMAGE_RATIO)
		)
		(
			assert_float(boss.phase_rate_multiplier(boss.phase_count()))
			. override_failure_message("%s never speeds up" % String(id))
			. is_greater(boss.phase_rate_multiplier(1))
		)


func test_the_moveset_escalates_with_the_phase_not_just_the_health_bar() -> void:
	# `base_damage()` is what every boss hitbox is built from, so this is the one number that
	# says whether phase 3 is actually more dangerous or merely later.
	var boss := _spawn(&"ringmaster", 2)
	await get_tree().physics_frame
	var opening := boss.base_damage()
	boss.phase = boss.phase_count()
	var closing := boss.base_damage()
	(
		assert_float(closing)
		. override_failure_message(
			"the Ringmaster's last phase swings for %.0f, its first for %.0f" % [closing, opening]
		)
		. is_greater(opening * MIN_LAST_PHASE_DAMAGE_RATIO * 0.99)
	)
	# And the escalation is data, not a constant buried in the script.
	assert_float(boss.def.param(&"phase_damage_step", -1.0)).is_greater(0.0)
	assert_float(boss.def.param(&"phase_speed_step", -1.0)).is_greater(0.0)
