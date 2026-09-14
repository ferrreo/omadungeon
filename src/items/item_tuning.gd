## Tunable numbers shared by every generated item: the weapon power ladder and the strength of
## on-hit status affixes. Shipped as `data/items/tuning.tres` so a balance pass edits data, not
## code (docs ARCHITECTURE §1: "content is data").
##
## The ladder is the contract weapon bases are authored against: a tier-`t` weapon is built to
## `weapon_tier_dps[t]` raw DPS (`base_damage * attacks_per_second`) and may only drop from
## `weapon_tier_min_floor[t]` onwards, so "a floor-7 sword" means a measurably stronger sword.
class_name ItemTuning
extends Resource

const DEFAULT_PATH := "res://data/items/tuning.tres"

static var _shared: ItemTuning

## Raw DPS each weapon tier is built around (index = tier).
@export var weapon_tier_dps: PackedFloat32Array = PackedFloat32Array([20.0, 30.0, 45.0])
## First floor index a tier may drop on (index = tier).
@export var weapon_tier_min_floor: PackedInt32Array = PackedInt32Array([0, 3, 6])
## How far a base's authored DPS may sit from its tier target (0.25 = +-25%), which leaves room
## for role flavour (a heavy axe, a cheap starting sword) without breaking the ladder.
@export var weapon_tier_tolerance: float = 0.25

## Share of the off-family weapon cards a chest re-rolls into the family the player is already
## fighting with (`WeaponBase.Family`, docs §4.3). 1.0 would make the weapon slot a prison -
## a run could never be offered the greatsword that turns a Ranger into something else - and
## 0.0 is the state the third playtest round measured, where every class converged on whatever
## base rolled highest and a Wizard and a Fighter played alike by floor 9. Shops and elite
## drops are never biased at all, so an off-family weapon always has a way in.
@export_range(0.0, 1.0) var weapon_family_bias: float = 0.8
## When a card *is* re-rolled, how often it is pulled towards the class's own family rather
## than towards whatever the player happens to be holding. Biasing only towards the worn
## weapon is a ratchet: one good sword out of a shop and a Ranger's chests start reinforcing
## the sword, so the class the player picked stops being offered its own weapons at all. At
## 0.5 the two doors stay open - a run can be talked back into its class, or out of it.
@export_range(0.0, 1.0) var weapon_home_bias: float = 0.5

## Seconds a bow needs to reach a full charge at x1 attack speed. The real charge time is this
## divided by the wearer's `attack_speed`: without that division the charge is a hard floor on
## the shot cycle and the whole attack-speed stat is worth nothing to a bow user.
@export var bow_charge_seconds: float = 0.75
## Damage multiplier of an uncharged tap shot.
@export var bow_tap_damage_mult: float = 0.65
## Damage multiplier of a full-charge shot (which also pierces). Holding the attack button
## fires at full charge and starts the next one, so this is the multiplier a bow *sustains*
## and therefore the one `WeaponBase.effective_dps()` prices the ladder against.
@export var bow_full_damage_mult: float = 1.35
## Projectile speed multipliers at zero charge and full charge.
@export var bow_tap_speed_mult: float = 0.8
@export var bow_full_speed_mult: float = 1.25

## Burn damage per second per point of weapon hit damage (0.5 = a weapon that hits for 20
## burns for 10/s), before the wearer's `damage_fire`.
@export var burn_dps_per_hit: float = 0.5
@export var burn_duration: float = 3.0
## Poison ticks less per second than burn but lasts longer.
@export var poison_dps_per_hit: float = 0.35
@export var poison_duration: float = 4.0
## Frost is a slow, not a DoT: only the duration matters (3 stacks freeze, docs §6).
@export var frost_duration: float = 2.5
## Shock procs read as a brief stagger. Short on purpose: it lands on every weapon hit roll.
@export var stun_duration: float = 0.35
## Hit damage assumed when the wearer has no weapon (an on-hit affix rolled on a ring).
@export var unarmed_hit_damage: float = 8.0


## The shipped tuning resource (a default-constructed one when the file is missing).
static func shared() -> ItemTuning:
	if _shared == null:
		_shared = load_default()
	return _shared


static func load_default() -> ItemTuning:
	var res := load(DEFAULT_PATH) as ItemTuning if ResourceLoader.exists(DEFAULT_PATH) else null
	return res if res != null else ItemTuning.new()


## Highest weapon tier that may drop on `floor_index`.
func tier_for_floor(floor_index: int) -> int:
	var best := 0
	for i in range(weapon_tier_min_floor.size()):
		if floor_index >= weapon_tier_min_floor[i]:
			best = i
	return best


## Raw DPS target for a tier (clamped to the table).
func dps_for_tier(tier: int) -> float:
	if weapon_tier_dps.is_empty():
		return 0.0
	return weapon_tier_dps[clampi(tier, 0, weapon_tier_dps.size() - 1)]


## First floor a tier may drop on (clamped to the table).
func min_floor_for_tier(tier: int) -> int:
	if weapon_tier_min_floor.is_empty():
		return 0
	return weapon_tier_min_floor[clampi(tier, 0, weapon_tier_min_floor.size() - 1)]


## Number of tiers the ladder defines.
func tier_count() -> int:
	return weapon_tier_dps.size()


## Seconds one full-charge bow shot takes end to end at `attack_speed`: the charge itself, or
## the weapon's own attack interval when that is the slower of the two (a crossbow). Both
## terms scale with attack speed, so the cycle is strictly proportional to 1/attack_speed.
func bow_cycle_seconds(attacks_per_second: float, attack_speed: float = 1.0) -> float:
	var speed := maxf(0.2, attack_speed)
	var interval := 1.0 / maxf(0.1, attacks_per_second)
	return maxf(bow_charge_seconds, interval) / speed


## Damage multiplier for a charge `fraction` (0 = tap, 1 = full).
func bow_damage_multiplier(fraction: float) -> float:
	return lerpf(bow_tap_damage_mult, bow_full_damage_mult, clampf(fraction, 0.0, 1.0))


## Projectile-speed multiplier for a charge `fraction`.
func bow_speed_multiplier(fraction: float) -> float:
	return lerpf(bow_tap_speed_mult, bow_full_speed_mult, clampf(fraction, 0.0, 1.0))


## Duration of the status an on-hit affix of `kind` applies.
func status_duration(kind: StatusEffect.Kind) -> float:
	match kind:
		StatusEffect.Kind.BURN:
			return burn_duration
		StatusEffect.Kind.POISON:
			return poison_duration
		StatusEffect.Kind.FROST:
			return frost_duration
		StatusEffect.Kind.STUN:
			return stun_duration
	return 1.0


## Damage-per-second an on-hit DoT of `kind` deals for a weapon hitting for `hit_damage`,
## before the wearer's elemental damage stat. Non-DoT kinds return 0.
func status_dps(kind: StatusEffect.Kind, hit_damage: float) -> float:
	var hit := maxf(0.0, hit_damage)
	match kind:
		StatusEffect.Kind.BURN:
			return hit * burn_dps_per_hit
		StatusEffect.Kind.POISON:
			return hit * poison_dps_per_hit
	return 0.0
