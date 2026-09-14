## Plays one whole run headlessly: nine floors of rooms, fights, chests, shops and shrines,
## with a scripted average player (`SimPlayer` + `SimOfferPolicy`) making every choice.
##
## Content comes from the shipped registries, so this is a measurement of `data/**` and not of
## a second copy of the rules: packs come from `EnemySpawner.pick_for_room()`, chest kinds from
## `Chest.roll_kind()`, offers from `ChestOffers` and `AbilityRegistry.offer()`, items from
## `ItemGenerator`, shrine options from `Shrine.default_options()`, prices from `Shop`.
##
## Determinism: every roll comes from a stream of the run's own `RunRng`, never from a global
## `randf()`, so the same (seed, class) always produces the same `SimRunResult`.
class_name RunSimulator
extends RefCounted

## Floors per run and the boss floors inside it. Mirrors RunManager.FLOOR_COUNT / BOSS_FLOORS /
## BOSS_IDS, which live on an autoload the simulation must not depend on;
## `tests/unit/balance/balance_sim_test.gd` fails if the two ever drift apart.
const FLOOR_COUNT := 9
const BOSS_FLOORS: Array[int] = [2, 5, 8]
const BOSS_IDS: Array[StringName] = [&"ringmaster", &"elder_greybeard", &"the_suit"]
## Room types that hold no enemies but still put a chest on the floor.
const CHEST_ONLY_TYPES: Array[int] = [FloorData.RoomType.TREASURE]

var enemies: EnemyRegistry
var items: ItemRegistry
var abilities: AbilityRegistry
var profile: BalanceProfile
## Ability ids a profile has NOT unlocked yet, so they never reach a card. Mirrors
## `Profile.GATED_UNLOCKS` semantics: everything not listed is available (docs §12), which is
## why this is a block list and not an allow list. Empty = the whole content pool, which is
## the mode the dominant/dead-option check runs in: a meta-locked ability is not a balance bug.
var locked: Array[StringName] = []
## Faction weights are a theme lever (docs §7); balance is measured on an even mix.
var faction_weights: Dictionary = {}
## What one trap hit is worth, averaged over `data/traps/**` by placement weight.
var trap_hit_damage: float = 0.0
## Damage the last `simulate()` took from hazards rather than from fights. The offer policy
## needs this split to know what a resistance card is worth, and it is measured rather than
## assumed (`BalanceProfile.hazard_damage_share` is pinned to it by the calibration suite).
var hazard_damage: float = 0.0

## Floors at which `simulate()` keeps a deep copy of the player, for anything that needs to
## judge a card against a build a run actually produced rather than against a naked starter.
## A passive that scales with worn items (Dotfiles) or with a deep floor's pressure (Thorns) is
## worth almost nothing to a floor-1 loadout, so scoring it there says nothing about whether it
## is dead. Empty = no snapshots, which is what a plain measurement run wants.
var snapshot_floors: Array[int] = []
## floor index -> the player as it entered that floor, filled while `snapshot_floors` is set.
var snapshots: Dictionary = {}

## True while this floor's free Lucky Coin reroll is still in hand (AbilitySlots flag
## `free_reroll_per_floor`, spent by `RunManager._on_offer_rerolled`).
var _free_reroll: bool = false


## Loads the shipped registries and simulation profile.
static func create(sim_profile: BalanceProfile = null) -> RunSimulator:
	var out := RunSimulator.new()
	out.enemies = load("res://data/enemies/registry.tres") as EnemyRegistry
	out.items = ItemRegistry.load_default()
	out.abilities = AbilityRegistry.load_default()
	out.profile = sim_profile if sim_profile != null else BalanceProfile.load_default()
	out.trap_hit_damage = average_trap_damage(TrapRegistry.load_default())
	return out


## Damage one trap hit is worth: every placeable (non-hazard) `TrapDef.damage` weighted by the
## chance `TrapRegistry.pick()` places that kind. Harmless kinds (ice slide, pressure plate)
## pull the average down exactly as often as they appear on a floor.
static func average_trap_damage(registry: TrapRegistry) -> float:
	if registry == null:
		return 0.0
	var total := 0.0
	var weight := 0.0
	for kind: StringName in registry.kinds():
		var def := registry.get_def(kind)
		if def == null or def.is_hazard or def.weight <= 0.0:
			continue
		total += def.damage * def.weight
		weight += def.weight
	return total / maxf(0.001, weight)


## Boss of a boss floor, or an empty StringName for an ordinary floor.
static func boss_id_for_floor(index: int) -> StringName:
	var slot := BOSS_FLOORS.find(index)
	return BOSS_IDS[slot] if slot >= 0 else &""


## Runs `class_def` from floor 1 to death or victory.
func simulate(class_def: ClassDef, seed_value: int) -> SimRunResult:
	var rng := RunRng.new(seed_value)
	var loot := rng.stream(&"loot")
	var player := SimPlayer.create(class_def, items, abilities, profile, loot)
	hazard_damage = 0.0
	var result := SimRunResult.new()
	result.class_id = class_def.id
	result.run_seed = seed_value
	_offer_starting_passive(player, result, loot)
	for index in range(FLOOR_COUNT):
		result.deepest_floor = index
		var alive := _run_floor(player, result, index, rng)
		if not alive:
			result.death_floor = index
			_record_final_build(player, result)
			return result
	result.victory = true
	_record_final_build(player, result)
	return result


## Writes the build the run ended with onto `result`: the abilities and, above all, the worn
## weapon. Recorded for a losing run too - a run that died on floor 6 still made six floors of
## build decisions, and reading identity off winners alone would sample only the lucky ones.
func _record_final_build(player: SimPlayer, result: SimRunResult) -> void:
	for id: StringName in player.abilities.keys():
		result.final_loadout[id] = (player.abilities[id] as Ability).tier
	var weapon := player.equipment.weapon()
	if weapon == null:
		return
	result.final_weapon_id = weapon.id
	result.final_weapon_style = int(weapon.style)


# ---------------------------------------------------------------- floors


## Walks one floor room by room. Returns false when the player died on it.
func _run_floor(player: SimPlayer, result: SimRunResult, index: int, rng: RunRng) -> bool:
	player.floor_index = index
	if snapshot_floors.has(index):
		snapshots[index] = player.clone()
	var plan := SimFloorPlan.build(index, rng.floor_stream(&"gen", index))
	var spawn := rng.floor_stream(&"spawn", index)
	var loot := rng.stream(&"loot")
	var combat := rng.stream(&"combat")
	var seconds := 0.0
	var taken := 0.0
	var dealt := 0.0
	var gold_before := player.gold
	_free_reroll = player.abilities.has(&"lucky_coin")
	for room_index in range(plan.rooms.size()):
		var room_type := plan.rooms[room_index]
		seconds += profile.seconds_per_room
		player.gold += int(roundf(profile.prop_gold_per_room))
		if SimFloorPlan.is_fight(room_type):
			var fight := _fight_room(
				player, result, room_type, index, plan.spawn_slots[room_index], spawn, combat
			)
			seconds += fight.seconds
			taken += fight.damage_taken
			dealt += fight.damage_dealt
			result.kills += fight.kills
			if player.hp <= 0.0:
				result.add_floor(
					seconds, 0.0, taken, dealt, player.gold - gold_before, player.max_hp()
				)
				return false
		taken += _room_hazards(player, room_type, index, combat)
		if player.hp <= 0.0:
			result.add_floor(seconds, 0.0, taken, dealt, player.gold - gold_before, player.max_hp())
			return false
		seconds += _room_reward(player, result, plan, room_type, loot)
		_drink_if_hurt(player, result)
	result.add_floor(
		seconds, player.hp_fraction(), taken, dealt, player.gold - gold_before, player.max_hp()
	)
	return true


## Resolves the fight in one room and folds its result into the player.
func _fight_room(
	player: SimPlayer,
	result: SimRunResult,
	room_type: int,
	index: int,
	slots: int,
	spawn: RandomNumberGenerator,
	combat: RandomNumberGenerator
) -> SimEncounter:
	var defs := _pack_for(room_type, index, slots, spawn)
	var is_boss := room_type == FloorData.RoomType.BOSS
	var fight := SimEncounter.resolve(player, defs, index, is_boss, profile, combat)
	var boss_slot := BOSS_FLOORS.find(index)
	if is_boss and boss_slot >= 0:
		result.boss_seconds[boss_slot] += fight.seconds
		result.boss_damage[boss_slot] += maxf(0.0, fight.damage_taken - fight.healing)
		result.boss_kills[boss_slot] += 1
	player.gold += fight.gold
	_apply_damage(player, result, fight.damage_taken - fight.healing)
	if room_type == FloorData.RoomType.ELITE and player.hp > 0.0:
		_elite_drop(player, result, index, combat)
	return fight


## The enemies a room holds: the floor's boss, or a budgeted pack from the registry.
func _pack_for(
	room_type: int, index: int, slots: int, spawn: RandomNumberGenerator
) -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	if room_type == FloorData.RoomType.BOSS:
		var boss := enemies.find(boss_id_for_floor(index))
		if boss != null:
			out.append(boss)
		return out
	var picked := EnemySpawner.pick_for_room(enemies, room_type, index, faction_weights, spawn)
	# The floor has only so many spawn tiles; RunManager drops the rest of the budget.
	for i in range(mini(picked.size(), maxi(0, slots))):
		out.append(picked[i])
	return out


## Trap damage: always in a TRAP room, and in a share of ordinary rooms (docs §9).
func _room_hazards(
	player: SimPlayer, room_type: int, index: int, rng: RandomNumberGenerator
) -> float:
	var hit := room_type == FloorData.RoomType.TRAP
	if not hit and SimFloorPlan.is_fight(room_type):
		hit = rng.randf() < profile.trap_room_fraction
	if not hit:
		return 0.0
	var damage := (
		trap_hit_damage
		* DifficultyCurve.shared().trap_multiplier(index)
		* profile.trap_hits_for(index)
		* Stats.armor_multiplier(player.stats.get_value(&"armor"))
		* player.threat.trap_resist_multiplier(player.stats)
	)
	if player.is_trap_immune():
		damage *= 1.0 - clampf(profile.trap_immune_share, 0.0, 1.0)
	player.hp -= damage
	hazard_damage += damage
	return damage


## Docs §7: elites always drop a Rare+ item. Worn when it is an upgrade.
func _elite_drop(
	player: SimPlayer, result: SimRunResult, index: int, rng: RandomNumberGenerator
) -> void:
	player.add_stat(Stats.PRIMARY[rng.randi_range(0, Stats.PRIMARY.size() - 1)], 1)
	var rarity := maxi(
		int(EnemyBase.ELITE_DROP_MIN_RARITY),
		int(ItemGenerator.roll_rarity(index, rng, player.stats.get_value(&"luck")))
	)
	var item := ItemGenerator.generate(
		items, index, rng, player.stats.get_value(&"luck"), [], rarity
	)
	if item == null:
		return
	result.rarity_offered[int(item.rarity)] += 1
	if SimOfferPolicy.score_of(item, player, profile) > 1.0:
		_equip(player, result, item)


# ---------------------------------------------------------------- rewards


## Chest, altar, shop or shrine for `room_type`. Returns the seconds it cost.
func _room_reward(
	player: SimPlayer,
	result: SimRunResult,
	plan: SimFloorPlan,
	room_type: int,
	loot: RandomNumberGenerator
) -> float:
	match room_type:
		FloorData.RoomType.ALTAR:
			_ability_offer(player, result, plan.floor_index, loot)
			return profile.seconds_per_chest
		FloorData.RoomType.SHOP:
			_visit_shop(player, result, plan.floor_index, loot)
			return profile.seconds_per_chest
		FloorData.RoomType.SHRINE:
			_visit_shrine(player, loot)
			return profile.seconds_per_chest
	if not SimFloorPlan.is_fight(room_type) and not CHEST_ONLY_TYPES.has(room_type):
		return 0.0
	_open_chest(player, result, plan.floor_index, room_type, loot)
	return profile.seconds_per_chest


func _open_chest(
	player: SimPlayer, result: SimRunResult, index: int, room_type: int, loot: RandomNumberGenerator
) -> void:
	var price := profile.buyout_price_for(index) if player.abilities.has(&"buyout") else 0
	if price > 0:
		if player.gold < price:
			return
		player.gold -= price
	var kind := Chest.roll_kind(loot, room_type as FloorData.RoomType, index)
	var count := 4 if player.abilities.has(&"buyout") else 3
	var rolled := _roll_offers(player, kind, count, index, loot)
	if _should_reroll(rolled, player):
		_free_reroll = false
		rolled = _roll_offers(player, kind, count, index, loot)
	_take_best(player, result, rolled, loot)


## Docs §4.4 Lucky Coin: one free reroll per floor, spent on the first board that is not worth
## taking. It is only consumed when it is actually used, so a good first chest keeps it.
func _should_reroll(rolled: ChestOffers, player: SimPlayer) -> bool:
	if not _free_reroll:
		return false
	return SimOfferPolicy.best_score(rolled.offers, player, profile) < profile.reroll_below_score


## Mirrors `ChestOffers.roll()`, except that ability cards are drawn here so the simulation
## controls which ids count as unlocked instead of reading the machine's real profile.
func _roll_offers(
	player: SimPlayer, kind: int, count: int, index: int, loot: RandomNumberGenerator
) -> ChestOffers:
	if kind != Chest.Kind.ABILITY:
		return ChestOffers.roll(
			kind,
			count,
			index,
			loot,
			player.stats.get_value(&"luck"),
			items,
			abilities,
			player.equipment,
			player.class_def.id,
			player.owned_tiers()
		)
	var out := ChestOffers.new()
	out.offers = _ability_cards(player, count, loot)
	return out


## An ability board, drawn the way `ChestOffers._roll_abilities()` draws one: a single kind,
## chosen by which kind still has a free slot. The kind rule is `ChestOffers.board_kind()`
## itself, so the simulation cannot model a board shape the game does not ship.
func _ability_cards(player: SimPlayer, count: int, loot: RandomNumberGenerator) -> Array:
	var kind := ChestOffers.board_kind(prefer_kind_for(player), loot)
	var pool := abilities.offer(
		loot, count + ChestOffers.LOCKED_HEADROOM, player.class_def.id, player.owned_tiers(), kind
	)
	var out: Array = []
	var spare: Array = []
	for ability: Ability in pool:
		if locked.has(ability.id):
			continue
		if int(ability.kind) == kind and out.size() < count:
			out.append(ability)
		else:
			spare.append(ability)
	for ability: Ability in spare:
		if out.size() >= count:
			break
		out.append(ability)
	return out


## `ChestOffers.prefer_kind_for()` for a scripted player: the `Ability.Kind` with a free slot,
## or -1 when both kinds are free or both are full.
static func prefer_kind_for(player: SimPlayer) -> int:
	var actives_full := (
		player.counted(Ability.Kind.ACTIVE) >= SimPlayer.slots_for(Ability.Kind.ACTIVE)
	)
	var passives_full := (
		player.counted(Ability.Kind.PASSIVE) >= SimPlayer.slots_for(Ability.Kind.PASSIVE)
	)
	if actives_full == passives_full:
		return -1
	return int(Ability.Kind.PASSIVE) if actives_full else int(Ability.Kind.ACTIVE)


## Ability altars (docs §8) show the same cards a chest would, free of charge.
func _ability_offer(
	player: SimPlayer, result: SimRunResult, index: int, loot: RandomNumberGenerator
) -> void:
	var rolled := _roll_offers(player, Chest.Kind.ABILITY, 3, index, loot)
	if _should_reroll(rolled, player):
		_free_reroll = false
		rolled = _roll_offers(player, Chest.Kind.ABILITY, 3, index, loot)
	_take_best(player, result, rolled, loot)


func _offer_starting_passive(
	player: SimPlayer, result: SimRunResult, loot: RandomNumberGenerator
) -> void:
	var pool := abilities.offer(
		loot,
		StartingPassive.COUNT + StartingPassive.HEADROOM,
		player.class_def.id,
		player.owned_tiers(),
		Ability.Kind.PASSIVE
	)
	var cards: Array = []
	for ability: Ability in pool:
		if cards.size() >= StartingPassive.COUNT:
			break
		if ability.kind != Ability.Kind.PASSIVE:
			continue
		if not locked.has(ability.id):
			cards.append(ability)
	var rolled := ChestOffers.new()
	rolled.offers = cards
	_take_best(player, result, rolled, loot)


## Scores the row, takes the winner and records what was on it.
func _take_best(
	player: SimPlayer, result: SimRunResult, rolled: ChestOffers, rng: RandomNumberGenerator
) -> void:
	for offer: Variant in rolled.offers:
		if offer is Ability:
			result.note_offered((offer as Ability).id)
		elif offer is ItemInstance:
			result.rarity_offered[int((offer as ItemInstance).rarity)] += 1
	var index := SimOfferPolicy.pick_index(rolled.offers, player, profile, rng)
	if index < 0:
		return
	_apply_offer(player, result, rolled.offers[index])
	if rolled.curse != null:
		_attach_curse(player, rolled.curse)


func _apply_offer(player: SimPlayer, result: SimRunResult, offer: Variant) -> void:
	if offer is Dictionary:
		var entry := offer as Dictionary
		if entry.has("stat"):
			player.add_stat(StringName(str(entry["stat"])), int(entry.get("points", 1)))
	elif offer is ItemInstance:
		_equip(player, result, offer as ItemInstance)
	elif offer is Ability:
		var ability := (offer as Ability).duplicate_ability()
		result.note_taken(ability.id)
		if not player.take_ability(ability):
			player.replace_ability(ability)
	elif offer is int or offer is float:
		player.gold += int(offer)


func _equip(player: SimPlayer, result: SimRunResult, item: ItemInstance) -> void:
	player.equip(item)
	result.rarity_equipped[int(item.rarity)] += 1


## Docs §8: the Legendary's price is a Curse passive holding a passive slot.
func _attach_curse(player: SimPlayer, curse: Ability) -> void:
	if not player.take_ability(curse):
		player.replace_ability(curse)


func _visit_shop(
	player: SimPlayer, result: SimRunResult, index: int, loot: RandomNumberGenerator
) -> void:
	var price_base := profile.shop_price_for(index)
	var best: ItemInstance = null
	var best_score := 1.0
	for _i in range(Shop.MAX_OFFERS):
		var item := ItemGenerator.generate(items, index, loot, player.stats.get_value(&"luck"))
		if item == null:
			continue
		result.rarity_offered[int(item.rarity)] += 1
		var price := Shop.price_for(item, price_base)
		if price > player.gold:
			continue
		var score := SimOfferPolicy.score_of(item, player, profile)
		if score > best_score:
			best_score = score
			best = item
	if best == null:
		return
	player.gold -= Shop.price_for(best, price_base)
	_equip(player, result, best)


## Shrines trade a resource for a buff (docs §8). An empty potion slot is refilled first — a
## heal in hand beats two stat points and the policy has no way to say so — and every other
## option, cleansing included, is scored on what it does to the build and drawn with the same
## softmax as a chest card.
##
## Cleansing used to be unconditional: carry a curse, pay the health, remove it. That is a
## hard-coded belief about how much a curse costs, and what it costs depends on the build:
## `curse_1`'s 30% of the HP pool is cheap for a build that is never hit and ruinous for one
## that tanks, so what a cleanse is worth has to be measured, not assumed. Paying HP at every
## shrine regardless skewed every number the shrine touches, and no amount of re-tuning
## `data/abilities/curse_*.tres` could show up in the report while the simulation refused to
## read them.
func _visit_shrine(player: SimPlayer, loot: RandomNumberGenerator) -> void:
	var options: Array[Dictionary] = []
	var cards: Array = []
	for option: Dictionary in Shrine.default_options():
		if not _can_pay(player, option):
			continue
		var buff := StringName(str(option.get("buff", &"")))
		if buff == &"potion":
			if player.potions <= 0:
				_pay(player, option)
				return
			continue
		if buff == &"cleanse":
			var gain := cleanse_score(player)
			if gain <= 1.0:
				continue
			options.append(option)
			cards.append({"score": gain})
			continue
		options.append(option)
		cards.append({"stat": buff, "points": option.get("amount", 1)})
	var index := SimOfferPolicy.pick_index(cards, player, profile, loot)
	if index >= 0:
		_pay(player, options[index])


## Power ratio removing the carried curse would produce, 1.0 when there is nothing to remove.
## Above 1.0 means cleansing is worth its price; how far above depends on which curse landed
## on which build. Measured the same way every other card is: on a clone.
func cleanse_score(player: SimPlayer) -> float:
	if not _has_curse(player):
		return 1.0
	var preview := player.clone()
	_cleanse(preview)
	return preview.power() / maxf(0.01, player.power())


func _has_curse(player: SimPlayer) -> bool:
	for id: StringName in player.abilities.keys():
		if String(id).begins_with("curse_"):
			return true
	return false


func _can_pay(player: SimPlayer, option: Dictionary) -> bool:
	var cost := float(option.get("cost", 0))
	match str(option.get("cost_kind", "gold")):
		"gold":
			return float(player.gold) >= cost
		"hp":
			return player.hp > cost + 1.0
		"max_hp":
			return player.max_hp() > cost + 10.0
	return false


## Charges the option's cost (gold, HP or max HP) and applies its buff.
func _pay(player: SimPlayer, option: Dictionary) -> void:
	var cost := float(option.get("cost", 0))
	match str(option.get("cost_kind", "gold")):
		"gold":
			player.gold -= int(cost)
		"hp":
			player.hp = maxf(1.0, player.hp - cost)
		"max_hp":
			player.stats.add_flat(&"max_hp", &"shrine", -cost)
			player.recompute()
	var buff := StringName(str(option.get("buff", &"might")))
	var amount := int(option.get("amount", 1))
	if buff == &"potion":
		player.potions += amount
	elif buff == &"cleanse":
		_cleanse(player)
	else:
		player.add_stat(buff, amount)


func _cleanse(player: SimPlayer) -> void:
	for id: StringName in player.abilities.keys():
		if String(id).begins_with("curse_"):
			player.abilities.erase(id)
			player.recompute()
			return


# ---------------------------------------------------------------- player upkeep


func _apply_damage(player: SimPlayer, result: SimRunResult, net: float) -> void:
	player.hp = minf(player.max_hp(), player.hp - net)
	if player.hp > 0.0 or player.potions <= 0:
		return
	player.potions -= 1
	result.potions_drunk += 1
	player.hp += player.max_hp() * Player.POTION_HEAL_FRACTION


func _drink_if_hurt(player: SimPlayer, result: SimRunResult) -> void:
	if player.potions <= 0 or player.hp_fraction() >= profile.potion_threshold:
		return
	player.potions -= 1
	result.potions_drunk += 1
	player.hp = minf(player.max_hp(), player.hp + player.max_hp() * Player.POTION_HEAL_FRACTION)
