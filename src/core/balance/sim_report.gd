## Aggregates many `SimRunResult`s into the numbers a balance pass is judged on: time and
## health per floor, damage dealt against damage taken, gold income, item rarity mix, ability
## pick rates, where runs die and how often they finish.
##
## Averages are taken over the runs that actually *reached* a floor, so floor 9's health curve
## is the health of the builds that got there rather than a number diluted by the runs that
## never did.
class_name SimReport
extends RefCounted

## An option whose taken-given-offered rate is more than this multiple of the pool median is
## dominant: the player never refuses it, so picking it is not a decision.
const DOMINANT_RATIO := 1.6
## An option whose taken-given-offered rate is below this multiple of the pool median is dead:
## it is on the board regularly and the player walks past it.
const DEAD_RATIO := 0.5
## First floor index (0-based, so 3 is floor 4) the difficulty ramp counts as *settled*: the
## yardstick a floor's climb is compared with is the mean step from here on. The opening floors
## are deliberately gentle (docs §2), so averaging them into the yardstick drags it below what a
## mid-run floor climbs and then marks the designed introduction as a non-event against it.
const RAMP_SETTLED_FLOOR := 3

var class_id: StringName = &""
var runs: int = 0
var clears: int = 0
## Runs that entered / died on each 0-based floor.
var entered: Array[int] = []
var deaths: Array[int] = []
## Per-floor sums, divided by `entered` for the averages.
var seconds: Array[float] = []
var hp_fraction: Array[float] = []
var damage_taken: Array[float] = []
## Damage taken as a share of the HP pool, summed over the runs that survived the floor.
var damage_share: Array[float] = []
## The same, minus whatever the floor's boss charged. The difficulty *ramp* is a statement
## about the rooms of a floor; the boss ladder is a statement about its boss. Measuring the
## ramp on the combined number coupled the two, so retuning a boss moved the evenness of the
## whole curve and a chest-offer change moved the boss ladder - which is exactly how a
## constant in `src/items/chest_offers.gd` came to flip two bands in one edit.
var room_damage_share: Array[float] = []
var damage_dealt: Array[float] = []
var gold: Array[float] = []
## Runs that entered a floor and walked off it alive (the health curve's denominator).
var survived: Array[int] = []
## Rarity counts across every run (`ItemInstance.Rarity` order).
var rarity_offered: Array[int] = [0, 0, 0, 0]
var rarity_equipped: Array[int] = [0, 0, 0, 0]
## Ability id -> runs in which it was offered at least once / taken at least once.
var offered_runs: Dictionary = {}
var picked_runs: Dictionary = {}
var total_seconds: float = 0.0
var total_gold: float = 0.0
var total_kills: float = 0.0
## Seconds and damage each boss cost, summed over the runs that reached it.
var boss_seconds: Array[float] = [0.0, 0.0, 0.0]
var boss_damage: Array[float] = [0.0, 0.0, 0.0]
var boss_fights: Array[int] = [0, 0, 0]
## Net HP each boss cost as a share of the pool of the run that fought it, summed over those
## runs. Recorded per run rather than derived from the floor averages: the runs that reach The
## Suit are a quarter of the sample and the strongest quarter at that, so dividing its damage
## by the *floor's* average pool measured one group's damage against another group's health.
var boss_pool_share: Array[float] = [0.0, 0.0, 0.0]
## For each boss, the share the boss *before* it cost in the very same runs. The ladder is a
## comparison between two rungs, and only a quarter of runs reach the third one: measured
## across all runs, a late boss's share of a strong build's pool is compared with an early
## boss's share of everybody's, which is two different players' experience. Every run that
## fights The Suit also fought Elder Greybeard, so the honest comparison is what *those* runs
## paid for each.
var boss_prev_pool_share: Array[float] = [0.0, 0.0, 0.0]
## `WeaponBase.Style` int -> runs that finished holding a weapon of that style, and
## `ItemBase.id` -> the same by base. The weapon is the half of a class that a run can lose
## (docs §4.3), and nothing else in this report can see it: two runs with identical ability
## take-up can finish one holding a greatsword and the other a staff.
var weapon_style_runs: Dictionary = {}
var weapon_id_runs: Dictionary = {}
## Runs that finished holding any weapon at all (the denominator of the two tables above).
var armed_runs: int = 0
## `SimRunResult.loadout_signature()` -> how many runs ended as exactly that build. The
## counterweight to the weapon-identity tables: a chest bias strong enough to hold every class
## to its own family would show as perfect identity *and* as a collapse here.
var loadout_runs: Dictionary = {}


## Folds `results` into one report. All results should share a class.
static func of(results: Array) -> SimReport:
	var out := SimReport.new()
	out._resize(RunSimulator.FLOOR_COUNT)
	for entry: Variant in results:
		out.add(entry as SimRunResult)
	return out


## Merges several per-class reports into one (the "all classes" row of the table).
static func merged(reports: Array) -> SimReport:
	var out := SimReport.new()
	out._resize(RunSimulator.FLOOR_COUNT)
	for entry: Variant in reports:
		out._absorb(entry as SimReport)
	return out


func add(result: SimRunResult) -> void:
	if result == null:
		return
	if class_id == &"":
		class_id = result.class_id
	runs += 1
	if result.victory:
		clears += 1
	total_seconds += result.total_seconds
	total_gold += float(result.total_gold)
	total_kills += float(result.kills)
	for i in range(result.floor_seconds.size()):
		if i >= entered.size():
			break
		entered[i] += 1
		seconds[i] += result.floor_seconds[i]
		damage_taken[i] += result.floor_damage_taken[i]
		damage_dealt[i] += result.floor_damage_dealt[i]
		gold[i] += float(result.floor_gold[i])
		if result.death_floor == i:
			continue
		survived[i] += 1
		hp_fraction[i] += result.floor_hp_fraction[i]
		var pool := maxf(1.0, result.floor_max_hp[i])
		damage_share[i] += result.floor_damage_taken[i] / pool
		room_damage_share[i] += (
			maxf(0.0, result.floor_damage_taken[i] - result.boss_damage_on_floor(i)) / pool
		)
	if result.death_floor >= 0 and result.death_floor < deaths.size():
		deaths[result.death_floor] += 1
	for i in range(3):
		boss_seconds[i] += result.boss_seconds[i]
		boss_damage[i] += result.boss_damage[i]
		boss_fights[i] += result.boss_kills[i]
		if result.boss_kills[i] > 0:
			boss_pool_share[i] += _run_boss_share(result, i)
			boss_prev_pool_share[i] += _run_boss_share(result, i - 1)
	for i in range(4):
		rarity_offered[i] += result.rarity_offered[i]
		rarity_equipped[i] += result.rarity_equipped[i]
	var signature := result.loadout_signature()
	loadout_runs[signature] = int(loadout_runs.get(signature, 0)) + 1
	if result.final_weapon_style >= 0:
		armed_runs += 1
		var style := result.final_weapon_style
		weapon_style_runs[style] = int(weapon_style_runs.get(style, 0)) + 1
		var weapon_id := result.final_weapon_id
		weapon_id_runs[weapon_id] = int(weapon_id_runs.get(weapon_id, 0)) + 1
	for id: StringName in result.abilities_offered.keys():
		offered_runs[id] = int(offered_runs.get(id, 0)) + 1
	for id: StringName in result.abilities_taken.keys():
		picked_runs[id] = int(picked_runs.get(id, 0)) + 1


## Net HP boss `slot` cost `result` as a share of that run's own pool on the boss's floor.
## 0 for a slot the run never reached (and for slot -1, which is "the boss before the first").
static func _run_boss_share(result: SimRunResult, slot: int) -> float:
	if slot < 0 or slot >= result.boss_damage.size() or result.boss_kills[slot] <= 0:
		return 0.0
	var floor_index: int = RunSimulator.BOSS_FLOORS[slot]
	if floor_index >= result.floor_max_hp.size():
		return 0.0
	return result.boss_damage[slot] / maxf(1.0, result.floor_max_hp[floor_index])


func clear_rate() -> float:
	return float(clears) / float(maxi(1, runs))


## Floors an average run of this class reaches, 1-based (9.0 = every run finished).
##
## The low-variance twin of `clear_rate()`. A clear is a rare event, so at a few hundred runs
## per class its sampling noise alone spans a ratio of 1.5 between the luckiest and unluckiest
## class - which is why the class-parity assertion cannot be read off clear rates alone and
## why this exists. Depth moves by a tenth of a floor between seeds, so a class that really is
## dying two floors earlier than the others cannot hide in the noise.
func avg_floors_reached() -> float:
	var total := 0
	for count: int in entered:
		total += count
	return float(total) / float(maxi(1, runs))


## Share of the runs that entered floor `index` and died there.
func death_rate(index: int) -> float:
	if index < 0 or index >= deaths.size() or entered[index] <= 0:
		return 0.0
	return float(deaths[index]) / float(entered[index])


## Share of all runs that ended on or before floor `index` (0-based).
func cumulative_death_rate(index: int) -> float:
	var total := 0
	for i in range(mini(index + 1, deaths.size())):
		total += deaths[i]
	return float(total) / float(maxi(1, runs))


## The floor a losing run is most likely to end on (0-based), or -1 when nothing died.
func likely_death_floor() -> int:
	var best := -1
	var best_count := 0
	for i in range(deaths.size()):
		if deaths[i] > best_count:
			best_count = deaths[i]
			best = i
	return best


func avg_seconds(index: int) -> float:
	return _avg(seconds, index)


func avg_hp_fraction(index: int) -> float:
	if index < 0 or index >= survived.size() or survived[index] <= 0:
		return 0.0
	return hp_fraction[index] / float(survived[index])


## Damage taken on floor `index` as a share of the HP pool, over the runs that survived it.
func avg_damage_share(index: int) -> float:
	if index < 0 or index >= survived.size() or survived[index] <= 0:
		return 0.0
	return damage_share[index] / float(survived[index])


## Damage taken on floor `index` as a share of the HP pool, *excluding* its boss. This is the
## curve the "difficulty rises smoothly" check reads: a boss is a designed spike and belongs to
## the boss ladder, not to the ramp, and on the combined curve the two floors either side of a
## boss look like a wall and a lull that neither of them is.
func avg_room_damage_share(index: int) -> float:
	if index < 0 or index >= survived.size() or survived[index] <= 0:
		return 0.0
	return room_damage_share[index] / float(survived[index])


func avg_damage_taken(index: int) -> float:
	return _avg(damage_taken, index)


func avg_damage_dealt(index: int) -> float:
	return _avg(damage_dealt, index)


func avg_gold(index: int) -> float:
	return _avg(gold, index)


## Seconds one boss fight lasted on average, over the runs that fought it.
func avg_boss_seconds(slot: int) -> float:
	return boss_seconds[slot] / float(maxi(1, boss_fights[slot]))


## Net HP one boss fight cost on average, over the runs that fought it.
func avg_boss_damage(slot: int) -> float:
	return boss_damage[slot] / float(maxi(1, boss_fights[slot]))


func avg_run_minutes() -> float:
	return total_seconds / float(maxi(1, runs)) / 60.0


## Health pool a run carries into floor `index`: what the floor took, divided by what it took
## as a share of the pool. Derived rather than recorded because the pool grows over a run and
## the runs that reach floor 9 are not the runs that reached floor 1.
func hp_pool_on(index: int) -> float:
	return avg_damage_taken(index) / maxf(0.01, avg_damage_share(index))


## Share of the health pool it is fought with that boss `slot` costs. The number a player
## feels: forty HP off a floor-3 bar is a fight, the same forty off a floor-9 bar is a speed
## bump, so a boss is only comparable to the boss before it in these terms.
##
## Averaged over the runs that fought it, each against its *own* pool. It used to be the
## boss's average damage over the floor's average pool, which is two different populations
## either side of the divide - only a quarter of runs reach The Suit and they are the
## strongest quarter - and it also read `avg_damage_share`, so an edit anywhere in the ramp
## moved the boss ladder.
func boss_hp_share(slot: int) -> float:
	if slot < 0 or slot >= boss_pool_share.size() or boss_fights[slot] <= 0:
		return 0.0
	return boss_pool_share[slot] / float(boss_fights[slot])


## Boss slots that do not cost meaningfully more of the pool than the boss before them — the
## mid-run anticlimax. The floor-6 boss used to cost 11% of the pool between a floor-3 boss at
## 21% and a floor-9 one at 24%, and a per-boss floor of 8% could not see it: every one of the
## three passed.
##
## `margin` is how much of a climb counts as one (1.0 = any rise at all, which is what this
## used to ask). Asking for a bare rise made the ladder a coin flip once two rungs were within
## a point of each other, so the caller states the step it means.
func boss_threat_dips(margin: float = 1.0) -> Array[int]:
	var out: Array[int] = []
	for slot in range(1, boss_pool_share.size()):
		if boss_fights[slot] <= 0:
			continue
		var previous := previous_boss_hp_share(slot)
		if previous <= 0.0:
			continue
		if boss_hp_share(slot) < previous * maxf(1.0, margin):
			out.append(slot)
	return out


## What the boss before `slot` cost, averaged over the runs that went on to fight `slot`. The
## like-for-like half of `boss_hp_share`: the same players, the same run, two rungs apart.
func previous_boss_hp_share(slot: int) -> float:
	if slot <= 0 or slot >= boss_prev_pool_share.size() or boss_fights[slot] <= 0:
		return 0.0
	return boss_prev_pool_share[slot] / float(boss_fights[slot])


## Share of every worn item that had each rarity.
func rarity_share() -> Array[float]:
	return _share(rarity_equipped)


## Share of every item the run was shown that had each rarity.
func offered_rarity_share() -> Array[float]:
	return _share(rarity_offered)


static func _share(counts: Array[int]) -> Array[float]:
	var total := 0
	for count: int in counts:
		total += count
	var out: Array[float] = []
	for count: int in counts:
		out.append(float(count) / float(maxi(1, total)))
	return out


## Share of runs in which `id` was taken at least once.
func pick_rate(id: StringName) -> float:
	return float(int(picked_runs.get(id, 0))) / float(maxi(1, runs))


## Share of runs in which `id` was on a card at least once.
func offer_rate(id: StringName) -> float:
	return float(int(offered_runs.get(id, 0))) / float(maxi(1, runs))


## Share of the runs that were shown `id` and took it. This is the number that says whether
## an option is *worth* taking, as opposed to `pick_rate`, which also reflects how often the
## pool happened to show it.
func conversion_rate(id: StringName) -> float:
	var offer := offer_rate(id)
	return pick_rate(id) / offer if offer > 0.0 else 0.0


## Median conversion rate over `candidates`, the yardstick the outlier band is measured
## against. A fixed threshold cannot say anything about a pool whose whole range has moved;
## the median can.
func median_conversion(candidates: Array[StringName]) -> float:
	var values: Array[float] = []
	for id: StringName in candidates:
		if offer_rate(id) > 0.0:
			values.append(conversion_rate(id))
	if values.is_empty():
		return 0.0
	values.sort()
	var middle := values.size() / 2
	if values.size() % 2 == 1:
		return values[middle]
	return (values[middle - 1] + values[middle]) * 0.5


## Ability ids whose take-up is out of band *relative to the pool they sit in*.
##
## The old test asked whether an ability was picked in more than 60% of runs ("dominant") or
## in exactly none ("dead"). Both halves were unfalsifiable in practice: nothing is ever
## picked in literally zero runs, and a pool whose best option converts at 0.69 never reaches
## 0.6 pick rate either, so a seven-fold spread between the best and worst option passed
## clean. What matters is the ratio of *taken given offered* to the pool median: an option
## the player refuses three times out of four when it is on the board is dead whether or not
## someone once took it, and an option nobody ever refuses is dominant however rarely the
## pool shows it.
##
## Returns {id: {"pick", "offer", "conversion", "ratio", "kind"}} with kind "dominant" or
## "dead". `median` defaults to the pool's own median conversion.
func outliers(candidates: Array[StringName], median: float = -1.0) -> Dictionary:
	var mid := median if median >= 0.0 else median_conversion(candidates)
	var out: Dictionary = {}
	if mid <= 0.0:
		return out
	for id: StringName in candidates:
		var offer := offer_rate(id)
		if offer <= 0.0:
			continue
		var conversion := conversion_rate(id)
		var ratio := conversion / mid
		var kind := ""
		if ratio > DOMINANT_RATIO:
			kind = "dominant"
		elif ratio < DEAD_RATIO:
			kind = "dead"
		if kind == "":
			continue
		out[id] = {
			"pick": pick_rate(id),
			"offer": offer,
			"conversion": conversion,
			"ratio": ratio,
			"kind": kind,
		}
	return out


## Share of the runs that finished holding a weapon of `style` (a `WeaponBase.Style`).
func weapon_style_share(style: int) -> float:
	return float(int(weapon_style_runs.get(style, 0))) / float(maxi(1, armed_runs))


## Share of the runs that finished holding a weapon from `styles` - a weapon *family*, which
## is the unit a class is built around: a Ranger who ends the run on a crossbow is still a
## Ranger, one who ends it on a greatsword is not.
func weapon_family_share(styles: PackedInt32Array) -> float:
	var total := 0
	for style: int in styles:
		total += int(weapon_style_runs.get(style, 0))
	return float(total) / float(maxi(1, armed_runs))


## Distinct end-of-run builds (weapon + abilities + tiers) across every run in this report.
func distinct_loadouts() -> int:
	return loadout_runs.size()


## Share of the runs that ended as the single most common build. 1.0 would mean every run of
## this class finished identically.
func top_loadout_share() -> float:
	var most := 0
	for count: int in loadout_runs.values():
		most = maxi(most, count)
	return float(most) / float(maxi(1, runs))


## The base id most runs finished holding, and its share: {"id", "share"}.
func top_weapon() -> Dictionary:
	var best := &""
	var best_count := 0
	for weapon_id: StringName in weapon_id_runs.keys():
		var count := int(weapon_id_runs[weapon_id])
		if count > best_count:
			best_count = count
			best = weapon_id
	return {"id": best, "share": float(best_count) / float(maxi(1, armed_runs))}


## Change in `avg_damage_share` from each floor to the next: entry `i` is floor `i+2` minus
## floor `i+1`. A negative entry is a sawtooth — the run got *easier* one floor deeper.
func ramp_steps() -> Array[float]:
	var out: Array[float] = []
	for index in range(1, entered.size()):
		out.append(avg_damage_share(index) - avg_damage_share(index - 1))
	return out


## The same steps on the boss-free curve (`avg_room_damage_share`). What the evenness check
## reads, so that retuning a boss cannot make the ramp look like a sawtooth and retuning the
## rooms cannot make a boss look like an anticlimax.
func room_ramp_steps() -> Array[float]:
	var out: Array[float] = []
	for index in range(1, entered.size()):
		out.append(avg_room_damage_share(index) - avg_room_damage_share(index - 1))
	return out


## Mean of `room_ramp_steps()` over the steps that land on floor index `first_index` or later
## — the size of a typical floor-to-floor climb once the run has stopped introducing itself.
##
## The opening floors are deliberately gentle (docs §2 and `test_first_floor_is_forgiving`), so
## averaging them in drags the yardstick below what a mid-run floor actually climbs and then
## makes those same gentle floors look like non-events against it.
func mean_room_ramp_step(first_index: int = RAMP_SETTLED_FLOOR) -> float:
	var steps := room_ramp_steps()
	var total := 0.0
	var count := 0
	for index in range(steps.size()):
		if index + 1 < first_index:
			continue
		total += steps[index]
		count += 1
	if count == 0:
		return 0.0
	return total / float(count)


## Each boss-free step as a multiple of the mean one: entry `i` is floor `i+2`. 1.0 is a floor
## that climbs exactly as much as the average floor does.
##
## Stated per floor rather than as one biggest-over-smallest ratio, because that ratio is the
## product of two independent floors: a flat floor early and a wall late multiply into one
## number that names neither of them, and moving either end changes it. A band on each floor
## separately is the same promise with the two ends uncoupled, and its failure message can say
## which floor is the wall.
func room_ramp_ratios(first_index: int = RAMP_SETTLED_FLOOR) -> Array[float]:
	var mean := mean_room_ramp_step(first_index)
	var out: Array[float] = []
	for step: float in room_ramp_steps():
		out.append(step / maxf(0.0001, mean))
	return out


## 0-based indices of the floors that cost the player *less* of their health pool than the
## floor before them — the sawtooth. A curve with any entry here is not a ramp, however
## convincing its endpoints look: the shipped one used to peak on floor 6 and then fall, and
## a check that only sampled floors 1/3/5/7/9 could not see it.
func sawtooth_floors() -> Array[int]:
	var out: Array[int] = []
	var steps := ramp_steps()
	for i in range(steps.size()):
		if steps[i] <= 0.0:
			out.append(i + 1)
	return out


## Ratio of the largest ramp step to the smallest. 1.0 is a perfectly even climb; a large
## number means some floors are a wall and others a non-event, which reads as a sawtooth to a
## player even when every step is technically positive. 0.0 when a step is not positive.
func ramp_evenness() -> float:
	var steps := ramp_steps()
	if steps.is_empty():
		return 1.0
	var smallest := INF
	var largest := 0.0
	for step: float in steps:
		if step <= 0.0:
			return 0.0
		smallest = minf(smallest, step)
		largest = maxf(largest, step)
	return largest / smallest


func _avg(series: Array[float], index: int) -> float:
	if index < 0 or index >= series.size() or entered[index] <= 0:
		return 0.0
	return series[index] / float(entered[index])


func _resize(count: int) -> void:
	entered.resize(count)
	survived.resize(count)
	damage_share.resize(count)
	room_damage_share.resize(count)
	deaths.resize(count)
	seconds.resize(count)
	hp_fraction.resize(count)
	damage_taken.resize(count)
	damage_dealt.resize(count)
	gold.resize(count)
	entered.fill(0)
	survived.fill(0)
	damage_share.fill(0.0)
	room_damage_share.fill(0.0)
	deaths.fill(0)
	seconds.fill(0.0)
	hp_fraction.fill(0.0)
	damage_taken.fill(0.0)
	damage_dealt.fill(0.0)
	gold.fill(0.0)


func _absorb(other: SimReport) -> void:
	if other == null:
		return
	runs += other.runs
	clears += other.clears
	total_seconds += other.total_seconds
	total_gold += other.total_gold
	total_kills += other.total_kills
	for i in range(entered.size()):
		entered[i] += other.entered[i]
		survived[i] += other.survived[i]
		damage_share[i] += other.damage_share[i]
		room_damage_share[i] += other.room_damage_share[i]
		deaths[i] += other.deaths[i]
		seconds[i] += other.seconds[i]
		hp_fraction[i] += other.hp_fraction[i]
		damage_taken[i] += other.damage_taken[i]
		damage_dealt[i] += other.damage_dealt[i]
		gold[i] += other.gold[i]
	for i in range(3):
		boss_seconds[i] += other.boss_seconds[i]
		boss_damage[i] += other.boss_damage[i]
		boss_fights[i] += other.boss_fights[i]
		boss_pool_share[i] += other.boss_pool_share[i]
		boss_prev_pool_share[i] += other.boss_prev_pool_share[i]
	for i in range(4):
		rarity_offered[i] += other.rarity_offered[i]
		rarity_equipped[i] += other.rarity_equipped[i]
	armed_runs += other.armed_runs
	for signature: String in other.loadout_runs.keys():
		loadout_runs[signature] = (
			int(loadout_runs.get(signature, 0)) + int(other.loadout_runs[signature])
		)
	for style: int in other.weapon_style_runs.keys():
		weapon_style_runs[style] = (
			int(weapon_style_runs.get(style, 0)) + int(other.weapon_style_runs[style])
		)
	for weapon_id: StringName in other.weapon_id_runs.keys():
		weapon_id_runs[weapon_id] = (
			int(weapon_id_runs.get(weapon_id, 0)) + int(other.weapon_id_runs[weapon_id])
		)
	for id: StringName in other.offered_runs.keys():
		offered_runs[id] = int(offered_runs.get(id, 0)) + int(other.offered_runs[id])
	for id: StringName in other.picked_runs.keys():
		picked_runs[id] = int(picked_runs.get(id, 0)) + int(other.picked_runs[id])
