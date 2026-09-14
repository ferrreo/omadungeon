## The scripted "average player" of the balance simulation: a real `Stats`, a real slot
## record of real `ItemInstance`s and a real set of `Ability` resources, with no scene tree.
##
## It is deliberately *not* a `Player`: the live Player is a `CharacterBody2D` that needs a
## floor, a camera, navigation and an `EventBus` to exist, and thousands of simulated runs
## cannot afford any of that. What it does share with the live game is every number —
## `ClassDef` base stats, `ItemInstance.apply_to()`, `AbilitySlots`' slot counts and the
## ability exports — so retuning content retunes the simulation.
class_name SimPlayer
extends RefCounted

## Mirrors AbilitySlots.ACTIVE_COUNT / PASSIVE_COUNT; innates sit outside both (uncounted).
const ACTIVE_SLOTS := AbilitySlots.ACTIVE_COUNT
const PASSIVE_SLOTS := AbilitySlots.PASSIVE_COUNT

var class_def: ClassDef
var stats: Stats
## Slot record only (`slots` is written directly): the sim applies item modifiers itself so
## no `EventBus` signal, unique-effect host or audio pool is touched per equip.
var equipment: Equipment
## id -> Ability (the instance carries its own `tier`).
var abilities: Dictionary = {}
## Ability ids granted by the class and never counted against a slot.
var innate_ids: Array[StringName] = []
var hp: float = 100.0
var gold: int = 0
var potions: int = 1
## Everything the loadout contributes that is not a `Stats` modifier.
var effect: SimEffect = SimEffect.new()
## Floor the build is currently on. The value of a defensive or economic card depends on what
## the dungeon is about to throw at it and on how many cards are left to buy, so the scoring
## functions below need to know where they are.
var floor_index: int = 0
## What the dungeon throws, read off `data/enemies/**` and `data/traps/**`.
var threat: SimThreat = SimThreat.shared()

var _profile: BalanceProfile
## The registries the build was created from, so the economy half of `power()` can ask
## `SimLootValue` what a point of luck is worth in *this* content.
var _items: ItemRegistry
var _abilities: AbilityRegistry
## Owner ids `recompute()` registered last time, so a replaced ability's modifiers go away.
var _applied_owners: Array[StringName] = []


## Builds the class's starting loadout: base stats, start gold, start weapon, innate passive
## and class active (docs §4.3).
static func create(
	def: ClassDef,
	items: ItemRegistry,
	registry: AbilityRegistry,
	profile: BalanceProfile,
	rng: RandomNumberGenerator
) -> SimPlayer:
	var out := SimPlayer.new()
	out._profile = profile
	out.class_def = def
	out.threat = SimThreat.shared()
	out._items = items
	out._abilities = registry
	out.stats = Stats.new()
	out.equipment = Equipment.new()
	for stat: StringName in Stats.PRIMARY:
		out.stats.add_primary(stat, int(def.base_stats().get(stat, 0)))
	out.gold = def.start_gold
	var base := items.find_base(def.start_weapon_id)
	if base != null:
		out.equip(ItemGenerator.instance_of(base, rng))
	var innate := registry.innate_for(def)
	if innate != null:
		out.innate_ids.append(innate.id)
		out.abilities[innate.id] = innate
	var active := registry.instance(def.class_active_id)
	if active != null:
		out.abilities[active.id] = active
	for extra: ActiveAbility in registry.starting_actives_for(def):
		out.abilities[extra.id] = extra
	out.recompute()
	out.hp = out.max_hp()
	return out


## A build with no class, no abilities and no stat growth, wearing `weapon` and nothing else.
##
## What the weapon-pricing check needs: `dps()` on one of these measures the weapon and only
## the weapon, so the simulation's opinion of a base can be compared with the ladder's
## (`WeaponBase.effective_dps()`) with nothing else in the way.
static func bare(weapon: ItemInstance, profile: BalanceProfile) -> SimPlayer:
	var out := SimPlayer.new()
	out._profile = profile
	out.stats = Stats.new()
	out.equipment = Equipment.new()
	if weapon != null:
		out.equip(weapon)
	out.hp = out.max_hp()
	return out


## Wears `item`, replacing whatever held its slot. Mirrors `Equipment.equip()` minus the
## signals and the unique-effect host.
func equip(item: ItemInstance) -> void:
	if item == null or item.base == null:
		return
	var slot := equipment.target_slot(item)
	var replaced := equipment.get_item(slot)
	if replaced != null:
		replaced.remove_from(stats)
	equipment.slots[slot] = item
	item.apply_to(stats)
	recompute()


## Adds `ability` (or raises its tier). Returns false when that kind's slots are full and the
## ability is new, exactly as `AbilitySlots.add()` does.
func take_ability(ability: Ability) -> bool:
	if ability == null:
		return false
	var owned := abilities.get(ability.id) as Ability
	if owned != null:
		if owned.tier >= owned.max_tier:
			return false
		owned.tier += 1
		recompute()
		return true
	if counted(ability.kind) >= slots_for(ability.kind):
		return false
	abilities[ability.id] = ability
	recompute()
	return true


## Replaces the weakest ability of `ability`'s kind with it (the "replace" prompt a live
## player answers when a kind is full).
func replace_ability(ability: Ability) -> void:
	var weakest := StringName()
	var weakest_tier := 99
	for id: StringName in abilities.keys():
		var owned := abilities[id] as Ability
		if innate_ids.has(id) or owned.kind != ability.kind:
			continue
		if owned.tier < weakest_tier:
			weakest_tier = owned.tier
			weakest = id
	if weakest != StringName():
		abilities.erase(weakest)
	abilities[ability.id] = ability
	recompute()


## Frees a slot of `kind` by discarding the weakest ability holding one, the way taking a card
## on a full build does. Returns the id it dropped, or an empty StringName.
func drop_weakest(kind: int) -> StringName:
	var weakest := StringName()
	var weakest_tier := 99
	for id: StringName in abilities.keys():
		var owned := abilities[id] as Ability
		if innate_ids.has(id) or int(owned.kind) != kind:
			continue
		if owned.tier < weakest_tier:
			weakest_tier = owned.tier
			weakest = id
	if weakest != StringName():
		abilities.erase(weakest)
		recompute()
	return weakest


## Abilities of `kind` that occupy a slot (innates do not).
func counted(kind: int) -> int:
	var total := 0
	for id: StringName in abilities.keys():
		if not innate_ids.has(id) and int((abilities[id] as Ability).kind) == kind:
			total += 1
	return total


static func slots_for(kind: int) -> int:
	return ACTIVE_SLOTS if kind == Ability.Kind.ACTIVE else PASSIVE_SLOTS


## `AbilitySlots.owned_tiers()`: id -> tier, for the offer roller.
func owned_tiers() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in abilities.keys():
		out[id] = (abilities[id] as Ability).tier
	return out


func add_stat(stat: StringName, points: int) -> void:
	stats.add_primary(stat, points)
	recompute()


## Re-applies every passive's `Stats` half from scratch and refolds the loadout's effects, so
## the order things were picked up in never changes the outcome.
func recompute() -> void:
	var worn := equipment.items().size()
	var ranged := _is_ranged()
	for owner_id: StringName in _applied_owners:
		stats.remove_owner(owner_id)
	_applied_owners = []
	for id: StringName in abilities.keys():
		var ability := abilities[id] as Ability
		_applied_owners.append(StringName("passive:" + String(id)))
		SimAbilityModel.apply_stats(ability, ability.tier, stats, _profile, worn)
	var folded := SimEffect.new()
	var context := {
		"ranged": ranged,
		"max_hp": stats.get_value(&"max_hp"),
		"hit_damage": _weapon_hit_damage(),
	}
	for id: StringName in abilities.keys():
		var ability := abilities[id] as Ability
		folded.merge(SimAbilityModel.effect_of(ability, ability.tier, stats, _profile, context))
	effect = folded
	hp = minf(hp, max_hp())


func max_hp() -> float:
	return stats.get_value(&"max_hp")


func hp_fraction() -> float:
	var cap := max_hp()
	return hp / cap if cap > 0.0 else 0.0


## Damage per second the build lands on a pack, weapon plus actives plus what it reflects.
##
## The weapon half is `WeaponBase.effective_dps()` — the same function the power ladder in
## `data/items/tuning.tres` is asserted against — so the simulation and the ladder cannot
## disagree about what a weapon is worth. They used to, by up to 1.8x inside a single tier,
## because the sim multiplied in a per-style fudge table and priced a weapon's own second
## projectile at 45%: on-tier chakrams scored 69% of their tier target and an on-tier longbow
## 125% of it, so the offer policy refused a whole weapon family the ladder called on-tier.
func dps() -> float:
	var weapon := equipment.weapon()
	var weapon_dps := 0.0
	if weapon != null:
		var tags := 1.0
		for tag: StringName in weapon.tags:
			tags *= 1.0 + stats.get_value(StringName("damage_" + String(tag)))
		var crit := 1.0 + stats.get_value(&"crit_chance") * (stats.get_value(&"crit_mult") - 1.0)
		weapon_dps = weapon.effective_dps(stats.get_value(&"attack_speed")) * tags * crit
		weapon_dps *= _affix_shot_multiplier(weapon) * _profile.weapon_uptime
	var ability_dps := effect.dps * effect.ability_rate_mult * effect.ability_damage_mult
	var dealt := (weapon_dps + ability_dps) * effect.damage_mult * _wealth_multiplier()
	return maxf(0.1, dealt + reflect_dps())


## Damage multiplier the purse is worth (the Oligarch's Buyout). Read at `dps()` time rather
## than folded into `effect` because gold moves every room while the loadout does not.
func _wealth_multiplier() -> float:
	if effect.damage_per_gold <= 0.0:
		return 1.0
	return 1.0 + clampf(float(gold) * effect.damage_per_gold, 0.0, effect.damage_per_gold_cap)


## Damage multiplier from projectiles the *build* added on top of the weapon's own.
##
## A weapon's implicit fan (the chakrams' second disc) is already inside
## `WeaponBase.effective_dps()` at full value, because that is what the tier ladder prices it
## at and what it was authored against; counting it a second time here is what made the two
## authorities disagree. Shots from affixes and Hardlink are worth less than the first, though,
## because a wider fan overlaps on a single body — that is what `extra_projectile_value`
## prices. Only the projectile styles read `projectile_count` at all
## (`WeaponBase.is_projectile_style()`); a melee arc swings once however many the stat says.
func _affix_shot_multiplier(weapon: WeaponBase) -> float:
	if not weapon.is_projectile_style():
		return 1.0
	var implicit := maxf(1.0, weapon.implicit_shots())
	var extra := maxf(0.0, stats.get_value(&"projectile_count") - implicit)
	return (implicit + extra * _profile.extra_projectile_value) / implicit


## Effective HP: the raw pool widened by armor, by the hits the build never takes (dodge,
## crowd control, mobility, raw walking speed), by the elemental damage its resistances turn
## away and by the healing it can expect over one fight. Without those terms the offer policy
## is blind to every defensive, mobility and resistance card on a board — which is exactly how
## Undervolt scored 1.0000 for all four classes while the report called it alive.
func ehp() -> float:
	var armor := stats.get_value(&"armor")
	var dodge := clampf(stats.get_value(&"dodge_chance"), 0.0, 0.9)
	var pool := max_hp() * (1.0 + armor / 100.0) / maxf(0.1, 1.0 - dodge)
	pool /= maxf(0.2, 1.0 - clampf(effect.mitigation, 0.0, 0.8))
	pool /= maxf(0.2, 1.0 - clampf(effect.avoid + mobility_avoidance(), 0.0, 0.6))
	pool /= maxf(0.2, hazard_multiplier())
	var lifesteal := effect.lifesteal + stats.get_value(&"lifesteal")
	var sustain := (effect.heal_per_second + lifesteal * dps()) * _profile.sustain_horizon_seconds
	return pool + maxf(0.0, sustain)


## Move speed a build with no swiftness and no gear walks at, so the avoidance a mobility card
## buys is measured against the game's own base rather than against a number typed in here.
static func base_move_speed() -> float:
	return Stats.new().get_value(&"move_speed")


## Share of incoming attacks the build simply outruns. The same conversion `SimEncounter` uses
## when it resolves a fight, so a card cannot be worth one thing to the policy and another to
## the damage model.
func mobility_avoidance() -> float:
	var gain := stats.get_value(&"move_speed") / maxf(1.0, base_move_speed()) - 1.0
	return maxf(0.0, gain) * _profile.speed_to_avoidance


## What the build pays of the hazard damage a floor charges, after `resist_*`. 1.0 is a build
## that resists nothing. The elemental share of a trap room comes from `data/traps/**` and the
## share of a floor's damage that is hazard rather than fight damage is
## `BalanceProfile.hazard_damage_share`, which `balance_targets_test` pins to the split the
## simulation itself measures rather than leaving it a free number.
func hazard_multiplier() -> float:
	if threat == null:
		return 1.0
	var share := clampf(_profile.hazard_damage_share, 0.0, 1.0)
	return 1.0 - share * (1.0 - threat.trap_resist_multiplier(stats))


## Damage the build sends back at whatever hit it (Thorns). It is real damage — the reflected
## hit kills things — but it is paid for out of damage the player is taking, so it is worth
## the melee share of this floor's pressure after everything that pressure is already reduced
## by. `SimEffect.reflect` was written by the ability model and read by nothing at all, which
## is why Thorns scored exactly 1.0000 for every class.
func reflect_dps() -> float:
	if threat == null or (effect.reflect <= 0.0 and effect.reflect_per_hit <= 0.0):
		return 0.0
	var landed := _profile.pack_alive_fraction
	landed *= 1.0 - SimEncounter.avoidance_of(self, floor_index, false, _profile)
	var incoming := threat.dps_on(floor_index) * threat.melee_share * landed
	incoming *= 1.0 - clampf(effect.mitigation, 0.0, 0.8)
	incoming *= Stats.armor_multiplier(stats.get_value(&"armor"))
	var hits := threat.melee_hits_on(floor_index) * landed
	return maxf(0.0, effect.reflect * incoming + effect.reflect_per_hit * hits)


## Offence and survivability, weighted. This is the fighting half of `power()`; it deliberately
## excludes the economy so that anything measuring the worth of an *item* (`SimLootValue`) can
## use it without the economy term reaching back for that measurement.
func combat_power() -> float:
	var w := clampf(_profile.power_offense_weight, 0.0, 1.0)
	return pow(maxf(0.01, dps()), w) * pow(maxf(1.0, ehp()), 1.0 - w)


## The single number the offer policy maximises: how well the build fights, times what its
## economy is about to buy it.
func power() -> float:
	return combat_power() * economy_multiplier()


## Power the build's economy stats turn into before the run is over.
##
## `gold_find` and `luck` change no fight and every subsequent card, so a value function that
## ignores them prices Verbose Logging and Lucky Coin at exactly 1.0000 — a card with no
## measurable effect, which is precisely what a dead-option check has to be able to see. Both
## are priced in currencies the policy already uses: a coin is worth `gold_power_per_coin`, and
## a point of luck is worth whatever `SimLootValue` measures it to add to an offered item by
## rolling the real generator.
##
## Not priced here: Lucky Coin's free reroll. It is simulated where it happens, in
## `RunSimulator._should_reroll`, and there is no honest way to value a reroll from a loadout
## alone — so the card's score reflects only its luck, and its reroll shows up in the run
## tables instead.
func economy_multiplier() -> float:
	if threat == null:
		return 1.0
	var gold := (
		threat.gold_on(floor_index)
		* float(SimFloorPlan.fight_count(floor_index))
		* maxf(0.0, stats.get_value(&"gold_find"))
		* _profile.gold_power_per_coin
	)
	var luck := (
		maxf(0.0, stats.get_value(&"luck"))
		* float(SimFloorPlan.offer_count(floor_index))
		* SimLootValue.power_per_luck(_items, _abilities, _profile)
	)
	return 1.0 + gold + luck


## A deep copy used to score a card before taking it. Shares the `ClassDef` and the shipped
## `Ability`/`ItemBase` resources (read-only), copies everything mutable.
func clone() -> SimPlayer:
	var out := SimPlayer.new()
	out._profile = _profile
	out._items = _items
	out._abilities = _abilities
	out.threat = threat
	out.floor_index = floor_index
	out.class_def = class_def
	out.stats = Stats.new()
	out.stats.from_dict(stats.to_dict())
	out.equipment = Equipment.new()
	out.equipment.slots = equipment.slots.duplicate()
	out.innate_ids = innate_ids.duplicate()
	out._applied_owners = _applied_owners.duplicate()
	for id: StringName in abilities.keys():
		out.abilities[id] = (abilities[id] as Ability).duplicate_ability()
	out.hp = hp
	out.gold = gold
	out.potions = potions
	out.effect = effect
	return out


## Damage one ordinary weapon swing lands before crit, for abilities that buff a single hit.
func _weapon_hit_damage() -> float:
	var weapon := equipment.weapon()
	if weapon == null:
		return 0.0
	var tags := 1.0
	for tag: StringName in weapon.tags:
		tags *= 1.0 + stats.get_value(StringName("damage_" + String(tag)))
	return weapon.base_damage * tags


## True when the build dodges through floor traps unharmed (docs §4.3 Sure-footed, which the
## live Player reads as `flags.trap_immune_dodge` in `is_trap_immune()`).
func is_trap_immune() -> bool:
	return abilities.has(&"sure_footed")


## True when the worn weapon fights at range (bows, wands, thrown).
func is_ranged() -> bool:
	return _is_ranged()


func _is_ranged() -> bool:
	var weapon := equipment.weapon()
	if weapon == null:
		return false
	return (
		weapon.style != WeaponBase.Style.MELEE_ARC and weapon.style != WeaponBase.Style.MELEE_THRUST
	)
