## Entry point of the balance simulation: runs many seeded runs of every class and formats the
## result as the table a balance pass is read from.
##
## Usage from a test or from `sim_main.gd`:
## [codeblock]
## var sim := BalanceSim.run(200, 20260912)
## print(sim.to_text())
## [/codeblock]
class_name BalanceSim
extends RefCounted

const CLASS_DIR := "res://data/classes"
const CLASS_IDS: Array[StringName] = [&"fighter", &"ranger", &"wizard", &"oligarch"]
## Default sample size: enough that a clear rate moves by about a point, not ten.
const DEFAULT_RUNS := 200

var simulator: RunSimulator
## class id -> SimReport.
var reports: Dictionary = {}
## class id -> the `ClassDef` its runs were played with, so the identity tables can ask what a
## class *starts* holding rather than carry a hand-written second copy of that, which is a
## thing that can silently disagree with `data/classes/*.tres`.
var class_defs: Dictionary = {}
## Every class folded together.
var overall: SimReport
var runs_per_class: int = 0


## Simulates `runs_per_class` runs of every class. `locked` names the ability ids a profile
## has not unlocked yet (pass `Profile.GATED_UNLOCKS` for a fresh profile); empty is the whole
## content pool, which is the mode the dominant/dead-option check wants.
static func run(
	runs_per_class: int = DEFAULT_RUNS,
	base_seed: int = 1,
	locked: Array[StringName] = [],
	sim_profile: BalanceProfile = null
) -> BalanceSim:
	var out := BalanceSim.new()
	out.runs_per_class = runs_per_class
	out.simulator = RunSimulator.create(sim_profile)
	out.simulator.locked = locked
	for class_id: StringName in CLASS_IDS:
		var def := load("%s/%s.tres" % [CLASS_DIR, class_id]) as ClassDef
		if def == null:
			continue
		out.class_defs[class_id] = def
		var results: Array = []
		for i in range(runs_per_class):
			results.append(out.simulator.simulate(def, RunRng.hash_combine(base_seed, i)))
		out.reports[class_id] = SimReport.of(results)
	out.overall = SimReport.merged(out.reports.values())
	return out


## Every ability id the offer pool can present (innates and curses excluded), so the outlier
## check covers the same set the player can actually be shown.
func offerable_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for ability: Ability in simulator.abilities.abilities:
		if ability == null or ability.weight <= 0.0:
			continue
		if AbilityRegistry.INNATE_IDS.has(ability.id):
			continue
		out.append(ability.id)
	return out


## The offerable ids every class competes for: class-locked cards are left out, because a
## card only its own class is ever shown is measured against a pool the other three fill.
## The Oligarch taking Hostile Takeover three times in four is that card working, not an
## imbalance in the general pool.
func generic_offerable_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for ability: Ability in simulator.abilities.abilities:
		if ability == null or ability.weight <= 0.0 or ability.class_only != &"":
			continue
		if AbilityRegistry.INNATE_IDS.has(ability.id):
			continue
		out.append(ability.id)
	return out


## Ability ids whose take-up is out of band relative to the pool, across all classes.
func outliers() -> Dictionary:
	return overall.outliers(generic_offerable_ids())


## How differently the four classes treat the same card: id -> {conversion per class, spread}.
##
## The third playtest round found the largest per-class spread in the whole generic pool was
## 0.27 and the median 0.13 - so outside the four class-locked actives, which class you picked
## barely changed the build you ended with. This is the table that says whether that is still
## true, and `balance_targets_test` asserts on it.
func identity_spread() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in generic_offerable_ids():
		var rates: Dictionary = {}
		var lowest := INF
		var highest := -INF
		for class_id: StringName in CLASS_IDS:
			var report := reports.get(class_id) as SimReport
			if report == null or report.offer_rate(id) <= 0.0:
				continue
			var conversion := report.conversion_rate(id)
			rates[class_id] = conversion
			lowest = minf(lowest, conversion)
			highest = maxf(highest, conversion)
		if rates.size() < CLASS_IDS.size():
			continue
		out[id] = {"rates": rates, "spread": highest - lowest}
	return out


## The `WeaponBase.Family` a class is built around: the family of the weapon it *starts* the
## run holding (docs §4.3, "the starting weapon is half of what a class is"). Both melee
## classes come out as MELEE - the Oligarch's Golden Cane is a melee arc, and what separates
## it from the Fighter is its economy, not its swing.
func class_family(class_id: StringName) -> WeaponBase.Family:
	var def := class_defs.get(class_id) as ClassDef
	if def == null or simulator == null or simulator.items == null:
		return WeaponBase.Family.MELEE
	var weapon := simulator.items.find_base(def.start_weapon_id) as WeaponBase
	return weapon.family() if weapon != null else WeaponBase.Family.MELEE


## Share of `class_id`'s runs that finished holding a weapon of `family`.
func weapon_family_share(class_id: StringName, family: WeaponBase.Family) -> float:
	var report := reports.get(class_id) as SimReport
	if report == null:
		return 0.0
	return report.weapon_family_share(WeaponBase.styles_in_family(family))


## What each class finished the run holding: every family's share and the single most likely
## base. This is the table the "a Wizard and a Fighter play alike by floor 9" verdict is read
## off, and the one no earlier round could produce because nothing recorded the weapon at all.
func weapon_text() -> String:
	var lines := PackedStringArray()
	lines.append("Final weapon - the family each class was still fighting with at the end")
	var header := "Class         started  own share"
	for index in range(WeaponBase.FAMILY_NAMES.size()):
		header += "  %10s" % String(WeaponBase.FAMILY_NAMES[index])
	lines.append(header + "   most likely base")
	for class_id: StringName in CLASS_IDS:
		var report := reports.get(class_id) as SimReport
		if report == null:
			continue
		var own := class_family(class_id)
		var row := (
			"%-12s %9s %10.2f"
			% [
				String(class_id),
				String(WeaponBase.family_name(own)),
				weapon_family_share(class_id, own),
			]
		)
		for index in range(WeaponBase.FAMILY_NAMES.size()):
			row += "  %10.2f" % weapon_family_share(class_id, index as WeaponBase.Family)
		var top := report.top_weapon()
		row += "   %s %.0f%%" % [String(top["id"]), float(top["share"]) * 100.0]
		lines.append(row)
	lines.append("")
	lines.append("Build variety - distinct end-of-run builds (weapon + abilities + tiers)")
	lines.append("Class          runs  distinct  most common build")
	for class_id: StringName in CLASS_IDS:
		var report := reports.get(class_id) as SimReport
		if report == null:
			continue
		(
			lines
			. append(
				(
					"%-13s %5d %9d %17.1f%%"
					% [
						String(class_id),
						report.runs,
						report.distinct_loadouts(),
						report.top_loadout_share() * 100.0,
					]
				)
			)
		)
	return "\n".join(lines)


## Median per-class spread across the whole generic pool: the number that says whether the
## pool *as a whole* answers to the class you picked, rather than whether one lucky card does.
##
## The widest spread anywhere in a pool of thirty-odd cards is an extreme of a noisy sample and
## moves several points between seeds; the median of the same set moves by a point. Round three
## measured a median of 0.13 in the state a tester called a failure.
func median_identity_spread() -> float:
	var spread := identity_spread()
	var values: Array[float] = []
	for id: StringName in spread.keys():
		values.append(float((spread[id] as Dictionary)["spread"]))
	if values.is_empty():
		return 0.0
	values.sort()
	var middle := values.size() / 2
	if values.size() % 2 == 1:
		return values[middle]
	return (values[middle - 1] + values[middle]) * 0.5


## The identity table as text, widest per-class spread first.
func identity_text() -> String:
	var spread := identity_spread()
	var ids := spread.keys()
	ids.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return (
				float((spread[a] as Dictionary)["spread"])
				> float((spread[b] as Dictionary)["spread"])
			)
	)
	var lines := PackedStringArray()
	var header := "Card               spread"
	for class_id: StringName in CLASS_IDS:
		header += "  %8s" % String(class_id)
	lines.append("Per-class taken|offered - how much the class you picked changes the build")
	var widest := 0.0
	for id: StringName in ids:
		widest = maxf(widest, float((spread[id] as Dictionary)["spread"]))
	lines.append(
		(
			"%d generic cards, median spread %.2f, widest %.2f"
			% [ids.size(), median_identity_spread(), widest]
		)
	)
	lines.append(header)
	for id: StringName in ids:
		var entry := spread[id] as Dictionary
		var row := "%-18s %6.2f" % [String(id), float(entry["spread"])]
		for class_id: StringName in CLASS_IDS:
			row += "  %8.2f" % float((entry["rates"] as Dictionary)[class_id])
		lines.append(row)
	return "\n".join(lines)


## The difficulty ramp as a table: what each floor costs, how much more than the floor before
## it, and how often it kills. A negative step is a sawtooth and is marked, because the thing
## a reader has to be able to see at a glance is "did the run just get easier?".
func ramp_text() -> String:
	var lines := PackedStringArray()
	lines.append("Ramp   taken/maxHP   step   rooms only   step  x mean   death%  note")
	var previous := 0.0
	var previous_rooms := 0.0
	var ratios := overall.room_ramp_ratios(SimReport.RAMP_SETTLED_FLOOR)
	for i in range(RunSimulator.FLOOR_COUNT):
		var share := overall.avg_damage_share(i)
		var rooms := overall.avg_room_damage_share(i)
		var step := share - previous if i > 0 else share
		var room_step := rooms - previous_rooms if i > 0 else rooms
		var ratio := ratios[i - 1] if i > 0 and i - 1 < ratios.size() else 0.0
		var note := "SAWTOOTH" if i > 0 and step < 0.0 else ""
		(
			lines
			. append(
				(
					"F%-5d %11.2f %6.2f %12.2f %6.2f %7.2f %8.1f  %s"
					% [
						i + 1,
						share,
						step,
						rooms,
						room_step,
						ratio,
						overall.death_rate(i) * 100.0,
						note,
					]
				)
			)
		)
		previous = share
		previous_rooms = rooms
	return "\n".join(lines)


## The whole report as plain text tables.
func to_text() -> String:
	var lines := PackedStringArray()
	lines.append(
		"Omadungeon balance simulation - %d runs x %d classes" % [runs_per_class, reports.size()]
	)
	lines.append("")
	lines.append_array(_class_table())
	lines.append("")
	lines.append_array(_floor_table())
	lines.append("")
	lines.append_array(_boss_table())
	lines.append("")
	lines.append_array(_rarity_table())
	lines.append("")
	lines.append_array(_ability_table())
	lines.append("")
	lines.append(ramp_text())
	lines.append("")
	lines.append(weapon_text())
	return "\n".join(lines)


func _class_table() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(
		"Class          clear%  floors  died<=F3  likely death  run min  dealt/taken  gold"
	)
	for class_id: StringName in CLASS_IDS:
		var report := reports.get(class_id) as SimReport
		if report == null:
			continue
		lines.append(_class_row(String(class_id), report))
	lines.append(_class_row("ALL", overall))
	return lines


## One row of the class table. `floors` is `SimReport.avg_floors_reached()`: the clear rate is
## a rare event and moves several points between seeds, the depth barely moves at all, so the
## two together say whether a gap is content or luck.
static func _class_row(label: String, report: SimReport) -> String:
	var death := report.likely_death_floor()
	return (
		"%-13s %6.1f %7.2f %9.1f %13s %8.1f %12.2f %5.0f"
		% [
			label,
			report.clear_rate() * 100.0,
			report.avg_floors_reached(),
			report.cumulative_death_rate(2) * 100.0,
			("F%d" % (death + 1)) if death >= 0 else "-",
			report.avg_run_minutes(),
			_ratio(report),
			report.total_gold / float(maxi(1, report.runs)),
		]
	)


func _floor_table() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Floor  minutes  end HP%  dmg taken  taken/maxHP  dmg dealt  gold  death%")
	for i in range(RunSimulator.FLOOR_COUNT):
		(
			lines
			. append(
				(
					"F%-5d %8.2f %8.1f %10.0f %12.2f %10.0f %5.0f %7.1f"
					% [
						i + 1,
						overall.avg_seconds(i) / 60.0,
						overall.avg_hp_fraction(i) * 100.0,
						overall.avg_damage_taken(i),
						overall.avg_damage_share(i),
						overall.avg_damage_dealt(i),
						overall.avg_gold(i),
						overall.death_rate(i) * 100.0,
					]
				)
			)
		)
	return lines


func _boss_table() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Boss              floor  reached  seconds  net HP cost  share of pool  prev rung")
	var dips := overall.boss_threat_dips()
	for slot in range(RunSimulator.BOSS_IDS.size()):
		var reached := float(overall.boss_fights[slot]) / float(maxi(1, overall.runs))
		(
			lines
			. append(
				(
					"%-17s F%-5d %7.1f %8.1f %12.0f %13.1f%% %9.1f%%  %s"
					% [
						String(RunSimulator.BOSS_IDS[slot]),
						RunSimulator.BOSS_FLOORS[slot] + 1,
						reached * 100.0,
						overall.avg_boss_seconds(slot),
						overall.avg_boss_damage(slot),
						overall.boss_hp_share(slot) * 100.0,
						overall.previous_boss_hp_share(slot) * 100.0,
						"ANTICLIMAX" if dips.has(slot) else "",
					]
				)
			)
		)
	return lines


func _rarity_table() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Item rarity      " + _rarity_row(overall.offered_rarity_share()) + "  (offered)")
	lines.append("                 " + _rarity_row(overall.rarity_share()) + "  (worn)")
	return lines


static func _rarity_row(share: Array[float]) -> String:
	var parts := PackedStringArray()
	for i in range(share.size()):
		parts.append("%s %5.1f%%" % [ItemInstance.RARITY_NAMES[i], share[i] * 100.0])
	return "  ".join(parts)


func _ability_table() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Ability            offer%  pick%  taken|offered  x median  flag")
	var ids := offerable_ids()
	ids.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return overall.conversion_rate(a) > overall.conversion_rate(b)
	)
	var median := overall.median_conversion(ids)
	var flagged := overall.outliers(ids, median)
	for id: StringName in ids:
		var conversion := overall.conversion_rate(id)
		var entry := flagged.get(id, {}) as Dictionary
		(
			lines
			. append(
				(
					"%-18s %6.1f %6.1f %14.2f %9.2f  %s"
					% [
						String(id),
						overall.offer_rate(id) * 100.0,
						overall.pick_rate(id) * 100.0,
						conversion,
						conversion / maxf(0.001, median),
						str(entry.get("kind", "")),
					]
				)
			)
		)
	lines.append("median taken|offered %.2f" % median)
	return lines


static func _ratio(report: SimReport) -> float:
	var taken := 0.0
	var dealt := 0.0
	for i in range(RunSimulator.FLOOR_COUNT):
		taken += report.damage_taken[i]
		dealt += report.damage_dealt[i]
	return dealt / maxf(1.0, taken)
