## What every offerable ability is worth, asked of the value function directly.
##
## The project's only evidence that build variety was real used to be a pick-rate table, and a
## pick rate is the *softmax* of a value, not the value. With `pick_temperature` at 0.06 a card
## that changed nothing at all still won a third of the boards it appeared on, so four cards
## that scored exactly 1.0000 for every class — Thorns, Lucky Coin, Verbose Logging and
## Undervolt — sat comfortably in the middle of the table. That check could not have failed.
##
## Three numbers replace it, all measured on `SimOfferPolicy.score_of()` itself and on builds a
## real run produced rather than on a naked starter:
##
## * **gain** — the power a card adds, in plain ratio terms. A card whose best gain over every
##   reference build is zero is inert: nothing the policy can see changes when it is taken.
## * **share** — that gain against the *best* card of the same kind for the same build. The
##   best card is a stable yardstick; a median is not, because a build with both active slots
##   full values most actives at nothing and drags the median to zero.
## * **top share** — how often a card is the single best of its kind. An option that is the
##   right answer for most builds is not a decision.
class_name SimCardValue
extends RefCounted

## Power gain below which a card has no measurable effect on the value function at all.
const INERT_GAIN := 0.002
## A card whose best build still values it below this share of that build's best card of the
## same kind is dead: there is nothing in it for anybody.
const DEAD_SHARE := 0.15
## Share of builds for which a card may be the single best of its kind before taking it stops
## being a decision.
const MAX_TOP_SHARE := 0.5
## ... and by how much it has to beat the runner-up on those builds before "usually the best"
## becomes "obviously the best". A pool where the top two cards are within a fifth of each
## other still poses the player a question, however often the same one wins on paper.
const DOMINANT_MARGIN := 1.25
## A build whose best card of a kind is worth less than this is not asked about that kind: its
## slots are full of things it likes better, which says nothing about the pool.
const MIN_YARDSTICK := 0.01
## Floors the reference builds are taken from: the opening, the middle and the deep end.
const REFERENCE_FLOORS: Array[int] = [0, 4, 8]
## Seeds tried per class until `RUNS_PER_CLASS` of them have produced a build set.
const SEED_ATTEMPTS := 30
## Runs sampled per class, deep or not.
##
## Three was not enough, and the cost was not accuracy but *stability*: `gain_spread` is a
## largest-over-smallest ratio, so with a dozen builds per class it is decided by whichever one
## build happened to be the unluckiest, and `top_share` for a class-locked card is decided by
## ten builds of one class. Any edit anywhere in the loot roller shifts which seeds produce
## which builds, and the same content measured 0, 1, 4 and 8 build-sensitive actives across
## five runs that differed only in how a chest picks a weapon. At eight runs a class the
## numbers move by a card, not by the whole answer, and the suite stops flipping on changes it
## has nothing to do with. `test_the_check_can_see_a_pool_of_flat_multipliers` is what keeps
## the wider sample from quietly lowering the bar: a flat damage card has to stay under it.
const RUNS_PER_CLASS := 8
## Marker for "this build is never shown this card", so it is excluded rather than counted as a
## zero. A card that is class-locked is not dead for the classes it is locked away from.
const NOT_OFFERED := -1000.0

## The builds every card was scored against, and a readable name per build.
var builds: Array[SimPlayer] = []
var build_names: PackedStringArray = PackedStringArray()
## Ability id -> power gain per build, parallel to `builds`. A card a build cannot be offered
## records `NOT_OFFERED`.
var gains: Dictionary = {}
## `Ability.Kind` -> best gain of that kind per build, parallel to `builds`.
var yardsticks: Dictionary = {}
## Ability id -> `Ability.Kind`, so a card that is not in the shipped registry (a synthetic one
## a test builds to prove these checks can fail) is measured like any other.
var kinds: Dictionary = {}

var _registry: AbilityRegistry


## Scores `candidates` against `reference_builds`. `names` labels the builds for the report.
static func measure(
	sim: RunSimulator,
	candidates: Array[Ability],
	reference_builds: Array[SimPlayer],
	names: PackedStringArray
) -> SimCardValue:
	var out := SimCardValue.new()
	out._registry = sim.abilities
	out.builds = reference_builds
	out.build_names = names
	for ability: Ability in candidates:
		var row: Array[float] = []
		for build: SimPlayer in reference_builds:
			row.append(out._gain(sim, ability, build))
		out.gains[ability.id] = row
		out.kinds[ability.id] = int(ability.kind)
	for kind: int in [int(Ability.Kind.ACTIVE), int(Ability.Kind.PASSIVE)]:
		var best: Array[float] = []
		for i in range(reference_builds.size()):
			var top := 0.0
			for ability: Ability in candidates:
				if int(ability.kind) != kind:
					continue
				var value := (out.gains[ability.id] as Array[float])[i]
				if value > NOT_OFFERED * 0.5:
					top = maxf(top, value)
			best.append(top)
		out.yardsticks[kind] = best
	return out


## Reference builds from real runs: the simulator is asked to keep a copy of the player as it
## entered each of `REFERENCE_FLOORS`, so a card that only pays off once the player is wearing
## four items or standing on floor 9 is judged where it pays off. Scoring every card on a
## floor-1 starter is how Dotfiles ("+1 per equipped item", on a build wearing one) reads as
## worthless when it is not.
##
## The first `RUNS_PER_CLASS` seeds are kept whatever they did, plus the first one that reached
## the deep end if none of them did. It used to keep only runs that reached the deepest
## reference floor, and that made the whole measurement turn on luck: four runs in five die
## before floor 9, so whether a class found three deep seeds inside `SEED_ATTEMPTS` decided
## whether the set held thirty builds or forty - and with them whether it held any of the weak,
## unlucky builds a card's worth is measured against. The same content measured 8 build-
## sensitive actives on one sample and 0 on the next because of it. A run that died on floor 6
## is a build the game produced; excluding it threw away the whole bottom of the range.
static func reference_builds(sim: RunSimulator, base_seed: int) -> Array[SimPlayer]:
	var out: Array[SimPlayer] = []
	for class_id: StringName in BalanceSim.CLASS_IDS:
		var def := load("%s/%s.tres" % [BalanceSim.CLASS_DIR, class_id]) as ClassDef
		if def == null:
			continue
		var kept: Array[Dictionary] = []
		var has_deep := false
		for attempt in range(SEED_ATTEMPTS):
			sim.snapshot_floors = REFERENCE_FLOORS
			sim.snapshots = {}
			sim.simulate(def, RunRng.hash_combine(base_seed, attempt))
			var reached_the_end := sim.snapshots.size() >= REFERENCE_FLOORS.size()
			if kept.size() < RUNS_PER_CLASS or (reached_the_end and not has_deep):
				kept.append(sim.snapshots)
				has_deep = has_deep or reached_the_end
			if kept.size() >= RUNS_PER_CLASS and has_deep:
				break
		for snapshots: Dictionary in kept:
			for index: int in REFERENCE_FLOORS:
				if snapshots.has(index):
					out.append(snapshots[index] as SimPlayer)
		# Plus the class as it starts, owning nothing but its innate and its class active. Runs
		# pick cards up, so on a sampled build most class cards are only ever offerable as
		# tier-ups - and a tier-up of something you already have is a different decision from
		# taking it. Without this build, Hostile Takeover read as dead at 0.10 in one sample and
		# as healthy at 0.65 in the next, depending on whether the sampled Oligarch had it.
		var rng := RandomNumberGenerator.new()
		rng.seed = RunRng.hash_combine(base_seed, 0x5747)
		out.append(SimPlayer.create(def, sim.items, sim.abilities, sim.profile, rng))
	sim.snapshot_floors = []
	sim.snapshots = {}
	return out


## Labels matching `reference_builds()`, in the same order.
static func reference_names(built: Array[SimPlayer]) -> PackedStringArray:
	var out := PackedStringArray()
	for build: SimPlayer in built:
		out.append("%s F%d" % [String(build.class_def.id), build.floor_index + 1])
	return out


## Best power gain `id` manages on any reference build, in plain ratio terms (0.08 = +8% power).
## Zero means the card does not move the value function at all for anybody.
func best_gain(id: StringName) -> float:
	var best := 0.0
	for value: float in gains.get(id, [] as Array[float]) as Array[float]:
		if value > NOT_OFFERED * 0.5:
			best = maxf(best, value)
	return best


## `id`'s gain as a share of the best card of its kind, per build. Builds that are never shown
## the card, and builds with no worthwhile card of that kind left, are left out.
func shares(id: StringName) -> Array[float]:
	var out: Array[float] = []
	if not kinds.has(id):
		return out
	var row := gains.get(id, [] as Array[float]) as Array[float]
	var yard := yardsticks.get(int(kinds[id]), [] as Array[float]) as Array[float]
	for i in range(row.size()):
		if row[i] <= NOT_OFFERED * 0.5 or i >= yard.size() or yard[i] < MIN_YARDSTICK:
			continue
		out.append(row[i] / yard[i])
	return out


## Best share `id` reaches on any build that can be offered it, or -1.0 when none can.
func best_share(id: StringName) -> float:
	var values := shares(id)
	if values.is_empty():
		return -1.0
	var best := -INF
	for value: float in values:
		best = maxf(best, value)
	return best


## Share of the builds that can be offered `id` for which it is the single best card of its
## kind (within a rounding hair of the yardstick).
func top_share(id: StringName) -> float:
	var values := shares(id)
	if values.is_empty():
		return 0.0
	var tops := 0
	for value: float in values:
		if value >= 0.999:
			tops += 1
	return float(tops) / float(values.size())


## How far `id` beats the next best card of its kind on the builds where it wins, as a median
## over those builds. 1.0 means it ties; 1.5 means it is half again as good as anything else.
func winning_margin(id: StringName) -> float:
	if not kinds.has(id):
		return 1.0
	var kind := int(kinds[id])
	var row := gains.get(id, [] as Array[float]) as Array[float]
	var margins: Array[float] = []
	for i in range(row.size()):
		if row[i] <= NOT_OFFERED * 0.5:
			continue
		var runner_up := 0.0
		for other: StringName in gains.keys():
			if other == id or int(kinds.get(other, -1)) != kind:
				continue
			var value := (gains[other] as Array[float])[i]
			if value > NOT_OFFERED * 0.5:
				runner_up = maxf(runner_up, value)
		if runner_up < MIN_YARDSTICK or row[i] < runner_up:
			continue
		margins.append(row[i] / runner_up)
	if margins.is_empty():
		return 1.0
	margins.sort()
	var middle := margins.size() / 2
	if margins.size() % 2 == 1:
		return margins[middle]
	return (margins[middle - 1] + margins[middle]) * 0.5


## How much `id`'s worth depends on the build it lands in: its best gain over its worst, across
## the builds that can be offered it.
##
## 1.0 is a card that is worth exactly the same to everybody. That is what a flat damage
## multiplier is, by construction: `power()` is `dps^w * ehp^(1-w)`, so multiplying dps by a
## constant multiplies power by a constant whatever the build — Rootkit's gain came back
## bit-identical (0.09544511501033) on 27 of 37 reference builds. A pool made of those has no
## build decisions in it however healthy every other column here looks, and nothing in the
## suite used to notice.
##
## A card the build cannot spend at all (Ricochet on a sword) reads as a very large spread,
## which is right: that is the strongest form of "this card is for a different build".
func gain_spread(id: StringName) -> float:
	var lowest := INF
	var highest := 0.0
	for value: float in gains.get(id, [] as Array[float]) as Array[float]:
		if value <= NOT_OFFERED * 0.5:
			continue
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	if lowest == INF or highest <= 0.0:
		return 1.0
	return highest / maxf(INERT_GAIN, lowest)


## Ids of `candidates` of `kind` whose value varies by at least `threshold` across builds.
func build_sensitive(
	candidates: Array[StringName], kind: int, threshold: float
) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in candidates:
		if int(kinds.get(id, -1)) != kind or best_share(id) < 0.0:
			continue
		if gain_spread(id) >= threshold:
			out.append(id)
	return out


## Cards no reference build could be offered as a *new* option, so nothing here measures them.
## Every one should be a class's own starting ability, which every build of that class already
## carries and no other class is ever shown - an honest blind spot, named rather than quietly
## scored as dead.
func unmeasured(candidates: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in candidates:
		if best_share(id) < 0.0:
			out.append(id)
	return out


## "active" or "passive", for the report.
func kind_name(id: StringName) -> String:
	if not kinds.has(id):
		return "?"
	return "active" if int(kinds[id]) == int(Ability.Kind.ACTIVE) else "passive"


## Cards out of band: {id: {"kind": "inert"|"dead"|"dominant", "gain", "share", "top"}}.
##
## Dead means *no* build values it at `DEAD_SHARE` of the best card of its kind — a card that is
## strong for one class and useless for the others is a build choice, not a dead option.
## Dominant means it is the right answer for more than `MAX_TOP_SHARE` of builds.
func outliers(candidates: Array[StringName]) -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in candidates:
		var share := best_share(id)
		if share < 0.0:
			continue
		var entry := {
			"gain": best_gain(id),
			"share": share,
			"top": top_share(id),
			"margin": winning_margin(id),
		}
		if best_gain(id) < INERT_GAIN:
			entry["kind"] = "inert"
		elif share < DEAD_SHARE:
			entry["kind"] = "dead"
		elif top_share(id) > MAX_TOP_SHARE and winning_margin(id) > DOMINANT_MARGIN:
			entry["kind"] = "dominant"
		else:
			continue
		out[id] = entry
	return out


## The score table, sorted by how much the best build wants each card.
func to_text(candidates: Array[StringName]) -> String:
	var lines := PackedStringArray()
	lines.append("Card value over %d reference builds from real runs" % builds.size())
	lines.append("Ability            kind     best gain  best share  top%  margin  spread  flag")
	var ids := candidates.duplicate()
	ids.sort_custom(
		func(a: StringName, b: StringName) -> bool: return best_share(a) > best_share(b)
	)
	var flagged := outliers(candidates)
	for id: StringName in ids:
		if not kinds.has(id):
			continue
		if best_share(id) < 0.0:
			lines.append("%-18s %-8s %35s" % [String(id), kind_name(id), "never a fresh option"])
			continue
		var entry := flagged.get(id, {}) as Dictionary
		(
			lines
			. append(
				(
					"%-18s %-8s %9.3f %11.2f %5.0f %7.2f %7.2f  %s"
					% [
						String(id),
						kind_name(id),
						best_gain(id),
						best_share(id),
						top_share(id) * 100.0,
						winning_margin(id),
						gain_spread(id),
						str(entry.get("kind", "")),
					]
				)
			)
		)
	return "\n".join(lines)


## Power gain `ability` itself contributes to `build`, or `NOT_OFFERED` when the build is never
## shown it.
##
## On a build whose slots of that kind are full, taking a card means dropping another one, and
## `SimOfferPolicy.score_of()` returns the net of the two — which is what the run simulator
## wants and exactly what a card valuation must not use. A build carrying a curse scored +16%
## for a card that does nothing at all, because taking the card evicted the curse. So when the
## slots are full the baseline here is the build with one already emptied: what is measured is
## the card and not the eviction.
func _gain(sim: RunSimulator, ability: Ability, build: SimPlayer) -> float:
	if not sim.abilities.is_offerable(ability, build.class_def.id, build.owned_tiers()):
		return NOT_OFFERED
	if build.abilities.has(ability.id):
		# The build already carries it, so the card on the board is a tier-up. Raising a tier is
		# a different decision from taking a card, and scoring the two together is how Hostile
		# Takeover - the Oligarch's own starting active, and therefore never a fresh option to
		# an Oligarch - read as a dead option at 0.10 while the model valued it at +27.7%.
		return NOT_OFFERED
	var baseline := build
	if build.counted(ability.kind) >= SimPlayer.slots_for(ability.kind):
		baseline = build.clone()
		baseline.drop_weakest(ability.kind)
	return SimOfferPolicy.score_of(ability, baseline, sim.profile) - 1.0
