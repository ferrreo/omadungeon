## Tunables of the headless balance simulation (`src/core/balance/**`).
##
## Two very different kinds of number live here and they must not be confused:
##
## 1. **Model calibration** — how a scripted "average player" behaves (how much of a fight it
##    spends actually landing hits, how many incoming attacks it avoids, how long it takes to
##    walk a room). These describe the *simulation*, not the game. Tuning them changes what the
##    simulation believes; they were calibrated once against the docs §2 pacing target
##    (20-35 min for nine floors) and should be left alone while balancing content.
## 2. **Mirrored game economy** — numbers the live game keeps in script constants outside this
##    module (`RunManager.SHOP_BASE_PRICE`, ...). `tests/unit/balance/balance_sim_test.gd`
##    asserts they still match, so a drift here or there is caught rather than silently
##    simulated wrong.
##
## Everything the simulation can read straight from shipped content (`EnemyDef`, `WeaponBase`,
## `Ability`, `RoomsContent`, ...) is read from there instead of being duplicated here.
class_name BalanceProfile
extends Resource

const PATH := "res://data/balance/sim_profile.tres"

@export_group("Scripted player")
## Share of a fight's seconds the player is actually landing weapon hits (the rest is
## approaching, repositioning and dodging). Calibrated so a floor-1 pack takes ~8-10 s.
@export var weapon_uptime: float = 0.3
## Share of the casts an ability's cooldown allows that the player actually gets off.
@export var ability_uptime: float = 0.8
## Average share of a pack still alive (and attacking) over the length of a fight.
@export var pack_alive_fraction: float = 0.55
## Share of incoming damage the player avoids on floor 1 by moving and dodging.
@export var avoidance_base: float = 0.72
## How much of that avoidance is lost per floor as packs get denser and faster.
@export var avoidance_per_floor: float = 0.012
## Extra avoidance in a boss arena. A boss is a *single* attacker with a long danger-coloured
## tell (docs §6) and the player's whole attention, so more of its swings are read and dodged
## than a seven-strong pack's - it hits much harder when it does land.
@export var boss_avoidance_bonus: float = 0.12
## Extra avoidance a ranged weapon buys: it fights at 140-240 px, outside most melee reach.
@export var ranged_avoidance_bonus: float = 0.06
## Standard deviation of the per-room multiplier on damage taken (bad rooms happen).
@export var room_noise: float = 0.3
## HP fraction below which the scripted player drinks its potion between rooms.
@export var potion_threshold: float = 0.45

@export_group("Pacing")
## Seconds spent walking to, entering and leaving one room.
@export var seconds_per_room: float = 7.0
## Seconds spent reading a chest's cards and picking one.
@export var seconds_per_chest: float = 5.0
## Seconds added by a boss arena on top of the time its HP pool takes.
@export var boss_overhead_seconds: float = 12.0

@export_group("Hazards")
## Trap hits a triggered room lands on floor 1, and the growth per floor (deeper floors are
## bigger and carry more trap tiles). What each hit is *worth* is not a number here: it comes
## from the shipped `TrapDef.damage` values, weighted by how often each kind is placed, so
## retuning `data/traps/**` retunes the simulation.
@export var trap_hits_base: float = 1.0
@export var trap_hits_per_floor: float = 0.22
## Share of ordinary fight rooms that also cost the player some trap damage.
@export var trap_room_fraction: float = 0.35
## Share of what a floor costs the player that is hazard damage rather than fight damage.
## `resist_*` only ever reduces trap damage — ordinary enemies deal melee/ranged physical and
## status ticks are tagged `true`, which skips resistances entirely in `Health` — so this is
## what decides whether a resistance card is worth anything. It is not a free number:
## `balance_targets_test.test_the_model_is_calibrated_against_its_own_measurements` fails when
## it drifts from the split the simulation actually produces.
@export var hazard_damage_share: float = 0.18
## Share of a room's trap damage a trap-immune dodge turns away (docs §4.3, Sure-footed:
## `Player.is_trap_immune()` while the Ranger's dash is running). Without this the Ranger's
## innate is invisible to the simulation and the class reads as weaker than it plays.
@export var trap_immune_share: float = 0.4
## Gold a room's breakable props are worth on average.
@export var prop_gold_per_room: float = 3.0

@export_group("Offer policy")
## Weight of offence in the scripted player's value function; survivability gets the rest.
@export var power_offense_weight: float = 0.5
## How fussy the scripted player is when it chooses between cards: the softmax temperature
## over the power gain each card offers. A card `pick_temperature` worse than the best on the
## board is taken about a third as often as it; a card worth nothing to the build is taken
## almost never. Smaller = a min-maxer, larger = picks nearly at random.
@export var pick_temperature: float = 0.06
## Power a single gold coin is worth when a card offers gold instead of power.
@export var gold_power_per_coin: float = 0.0006
## Score below which a free reroll (Lucky Coin) is spent rather than banked.
@export var reroll_below_score: float = 1.04

@export_group("Ability modelling")
## Px of floor one enemy occupies; area abilities hit `radius / this` targets.
@export var enemy_spacing_px: float = 34.0
## Most targets any one area ability is credited with.
@export var max_ability_targets: float = 4.0
## Targets a single-target ability is credited with.
@export var single_target_count: float = 1.0
## Share of the repeat ticks of a multi-hit active (a turret's twenty shots, a whirlwind's six
## sweeps) that actually land: the first one does, the rest chase a moving target.
@export var tick_hit_share: float = 0.6
## Seconds of healing that count as extra effective HP when the offer policy values a card.
@export var sustain_horizon_seconds: float = 20.0
## Share of a fight Adrenaline's post-dodge attack-speed window is up for.
@export var adrenaline_uptime: float = 0.45
## Share of a fight Tiling WM's alignment condition holds for.
@export var tiling_uptime: float = 0.3
## Share of a fight Second Wind's "below 40% HP" condition holds for.
@export var low_hp_uptime: float = 0.25
## Avoidance gained per +100% move speed (Sure-footed, move-speed affixes).
@export var speed_to_avoidance: float = 0.12
## Avoidance gained per +100% knockback (Heavy Hands): staggered enemies do not swing.
@export var knockback_to_avoidance: float = 0.04
## Extra ranged damage per Ricochet bounce (a bounced projectile sometimes hits again).
@export var bounce_dps_gain: float = 0.1
## Share of a first projectile's damage that an *affix-granted* extra projectile is worth.
## Below 1.0 because a wider fan overlaps: against one body only part of the volley connects.
## A weapon's own implicit fan is not priced here — it is inside `WeaponBase.effective_dps()`,
## which is the ladder's number and therefore the simulation's too.
@export var extra_projectile_value: float = 0.45
## Share of kills that arrive while an active is on cooldown, for Hotkey's refund.
@export var hotkey_kill_share: float = 0.6
## Extra damage Shadowstep's guaranteed crit adds to the hit that follows it, as a multiple
## of one ordinary swing (a 1.5x crit on top of a normal hit is +0.5).
@export var shadowstep_crit_bonus: float = 0.7
## Avoidance a pure-mobility active (Shadowstep, rm -rf) is worth per cast per second.
@export var utility_avoid_per_cast: float = 0.55
## Share of incoming damage removed while a crowd-control ability holds the pack.
@export var cc_mitigation_share: float = 0.45
## Share of the casts of an execute ability (kill -9, rm -rf) that land on a target already
## under its execute threshold. Everything else is a plain hit.
@export var execute_share: float = 0.3
## Share of a fight's hits that are the *first* hit on a given enemy (Rootkit). A pack of six
## fought with a weapon that lands thirty swings gives one first hit in five.
@export var first_hit_share: float = 0.2
## Average share of its cap a decaying kill-stack passive (Pipeline) is holding.
@export var kill_stack_uptime: float = 0.45
## Seconds of fighting one room clear is worth, for passives that pay out per cleared room
## (Cron Job). Their per-room value is divided by this to become a healing rate.
@export var room_fight_seconds: float = 14.0

@export_group("Mirrored game economy")
## Mirrors RunManager.SHOP_BASE_PRICE / SHOP_PRICE_PER_FLOOR.
@export var shop_base_price: int = 40
@export var shop_price_per_floor: int = 15
## Mirrors RunManager.BUYOUT_BASE_PRICE / BUYOUT_PRICE_PER_FLOOR (the Oligarch's chest price).
@export var buyout_base_price: int = 12
@export var buyout_price_per_floor: int = 2
## Mirrors RunManager.SKIP_GOLD_BASE / SKIP_GOLD_PER_FLOOR.
@export var skip_gold_base: int = 10
@export var skip_gold_per_floor: int = 3


## The shipped profile, or a fresh default when the resource has not been authored.
static func load_default() -> BalanceProfile:
	if not ResourceLoader.exists(PATH):
		return BalanceProfile.new()
	var res := load(PATH) as BalanceProfile
	return res if res != null else BalanceProfile.new()


## Avoidance the scripted player reaches on `floor_index` before build bonuses.
func avoidance_for(floor_index: int, is_boss: bool) -> float:
	var value := avoidance_base - avoidance_per_floor * float(maxi(0, floor_index))
	if is_boss:
		value += boss_avoidance_bonus
	return clampf(value, 0.0, 0.95)


## Trap hits one trap-carrying room lands on `floor_index`.
func trap_hits_for(floor_index: int) -> float:
	return maxf(0.0, trap_hits_base + trap_hits_per_floor * float(maxi(0, floor_index)))


## Gold one shop item costs on `floor_index`.
func shop_price_for(floor_index: int) -> int:
	return shop_base_price + shop_price_per_floor * maxi(0, floor_index)


## Gold the Oligarch's Buyout charges to open a chest on `floor_index`.
func buyout_price_for(floor_index: int) -> int:
	return buyout_base_price + buyout_price_per_floor * maxi(0, floor_index)


## Gold skipping a chest is worth on `floor_index`.
func skip_gold_for(floor_index: int) -> int:
	return skip_gold_base + skip_gold_per_floor * maxi(0, floor_index)
