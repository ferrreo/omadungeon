## One resolved fight: how long it took, what it cost and what it paid.
##
## The model is deliberately coarse-grained — a fight is a race between two damage-per-second
## numbers, not a physics simulation — but every input is a shipped number: `EnemyDef`'s
## scaled HP and damage, its attack timings, the weapon's damage and rate, the player's
## `Stats`. The three things the model has to invent (how much of a fight the player spends
## attacking, how much of a pack is still alive, how many hits get avoided) live in
## `BalanceProfile` and are the same for every class and every floor.
class_name SimEncounter
extends RefCounted

## Slowest a fight may be reported as, so a hopeless build ends the run instead of the loop.
const MAX_SECONDS := 600.0

var seconds: float = 0.0
var damage_taken: float = 0.0
var damage_dealt: float = 0.0
var healing: float = 0.0
var gold: int = 0
var kills: int = 0


## Resolves a pack of `defs` on `floor_index`. `rng` supplies the loot rolls and the per-room
## variance that makes one run unluckier than another.
static func resolve(
	player: SimPlayer,
	defs: Array[EnemyDef],
	floor_index: int,
	is_boss: bool,
	profile: BalanceProfile,
	rng: RandomNumberGenerator
) -> SimEncounter:
	var out := SimEncounter.new()
	if defs.is_empty():
		return out
	var pack_hp := 0.0
	var pack_dps := 0.0
	for def: EnemyDef in defs:
		pack_hp += def.scaled_hp(floor_index) * (1.0 + def.armor / 100.0)
		var dps := def.scaled_damage(floor_index) / attack_cycle(def)
		pack_dps += dps * boss_phase_pressure(def)
	out.kills = defs.size()
	out.damage_dealt = pack_hp
	out.seconds = clampf(pack_hp / player.dps(), 1.0, MAX_SECONDS)
	if is_boss:
		out.seconds += profile.boss_overhead_seconds
	var exposure := out.seconds * (1.0 if is_boss else profile.pack_alive_fraction)
	var avoid := avoidance_of(player, floor_index, is_boss, profile)
	var raw := pack_dps * exposure * (1.0 - avoid) * (1.0 - player.effect.mitigation)
	var noise := maxf(0.25, 1.0 + rng.randfn(0.0, profile.room_noise))
	out.damage_taken = raw * Stats.armor_multiplier(player.stats.get_value(&"armor")) * noise
	out.healing = _healing(player, out, defs, rng)
	out.gold = _gold(player, defs, floor_index, rng)
	return out


## How much harder a boss hits, averaged over the whole fight, because of its phases.
##
## `BossBase` adds `phase_damage_step` to a boss's damage and `phase_speed_step` to how often
## it attacks for every phase past the first. The player spends a share of the fight in each
## phase proportional to the slice of the HP bar that phase covers (the damage race runs at a
## constant rate), so the fight's average pressure is that HP-weighted mean. 1.0 for anything
## that is not a boss.
static func boss_phase_pressure(def: EnemyDef) -> float:
	if def == null or not def.is_boss:
		return 1.0
	var damage_step := def.param(&"phase_damage_step", BossBase.DEFAULT_PHASE_DAMAGE_STEP)
	var speed_step := def.param(&"phase_speed_step", BossBase.DEFAULT_PHASE_SPEED_STEP)
	var edges := BossBase.DEFAULT_THRESHOLDS.duplicate()
	edges.append(0.0)
	var previous := 1.0
	var total := 0.0
	for i in range(edges.size()):
		var share := maxf(0.0, previous - edges[i])
		total += share * (1.0 + damage_step * float(i)) * (1.0 + speed_step * float(i))
		previous = edges[i]
	return maxf(1.0, total)


## Share of incoming damage the build avoids outright on this floor.
static func avoidance_of(
	player: SimPlayer, floor_index: int, is_boss: bool, profile: BalanceProfile
) -> float:
	var base := profile.avoidance_for(floor_index, is_boss)
	var build := (
		player.effect.avoid + player.stats.get_value(&"dodge_chance") + player.mobility_avoidance()
	)
	if player.is_ranged():
		build += profile.ranged_avoidance_bonus
	return clampf(base + build, 0.0, 0.95)


## Seconds between the starts of two of this enemy's attacks.
##
## Not the sum of the four timings: `EnemyBase` starts `attack_cooldown` when it *enters*
## RECOVER, so the cooldown and the recovery run together and only the longer of the two is
## spent (`_enter_state(State.RECOVER)` sets `_attack_cooldown_left`, and `can_start_attack()`
## waits for it). Adding them made the model believe a honker attacks every 2.7 s when the
## live game has it attacking every 2.25 s, and so believe the floor was 20% gentler than it
## is — the sort of thing only a test that fights a real enemy can catch, which is why
## `live_calibration_test` exists.
static func attack_cycle(def: EnemyDef) -> float:
	var cycle := def.windup_time + def.attack_time + maxf(def.recover_time, def.attack_cooldown)
	return maxf(0.2, cycle)


static func _healing(
	player: SimPlayer, result: SimEncounter, defs: Array[EnemyDef], rng: RandomNumberGenerator
) -> float:
	var total := player.effect.lifesteal * result.damage_dealt
	total += player.stats.get_value(&"lifesteal") * result.damage_dealt
	total += player.effect.heal_per_second * result.seconds
	total += player.stats.get_value(&"life_on_kill") * float(result.kills)
	for _def: EnemyDef in defs:
		if rng.randf() < EnemyBase.HEART_DROP_CHANCE:
			total += float(EnemyBase.HEART_HEAL)
	return total


static func _gold(
	player: SimPlayer, defs: Array[EnemyDef], floor_index: int, rng: RandomNumberGenerator
) -> int:
	var find := 1.0 + player.stats.get_value(&"gold_find")
	var floor_bonus := 1.0 + EnemyBase.GOLD_PER_FLOOR * float(floor_index)
	var total := 0.0
	for def: EnemyDef in defs:
		total += float(rng.randi_range(def.gold_min, def.gold_max)) * floor_bonus * find
	return int(roundf(total))
