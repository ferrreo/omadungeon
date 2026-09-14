## Weapon base: adds attack parameters and a weapon skill (secondary attack).
class_name WeaponBase
extends ItemBase

enum Style { MELEE_ARC, MELEE_THRUST, RANGED_BOW, RANGED_WAND, THROWN }

## The three weapon families (docs §4.3: the starting weapon is half of what a class *is*).
## A family, not a style, is the unit a class is built around and the unit "am I still playing
## the class I picked?" has to be asked in: a crossbow and a shortbow are the same answer to a
## Ranger, a greatsword is not. Each family also scales off exactly one primary stat, which is
## what makes a class's own family measurably its best - MELEE off Might (`damage_melee`),
## PROJECTILE off Precision (`damage_ranged`), ARCANE off Arcana (`damage_ability`).
enum Family { MELEE, PROJECTILE, ARCANE }

## Styles in each `Family`, indexed by it. The single source of truth for the grouping: the
## chest's style bias and the balance simulation's identity table both read it here rather
## than keeping a second copy that can drift.
## Plain array literals, not `PackedInt32Array(...)`: a constructor call is not a constant
## expression, and GDScript rejects the whole script - and every suite that depends on it -
## when one appears in a `const`. `styles_in_family` packs it on the way out.
const FAMILY_STYLES: Array[Array] = [
	[Style.MELEE_ARC, Style.MELEE_THRUST],
	[Style.RANGED_BOW, Style.THROWN],
	[Style.RANGED_WAND],
]
const FAMILY_NAMES: Array[StringName] = [&"melee", &"projectile", &"arcane"]

@export var style: Style = Style.MELEE_ARC
@export var base_damage: float = 10.0
@export var attacks_per_second: float = 2.0
@export var range_px: float = 20.0
@export var knockback: float = 60.0
@export var tags: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 220.0
@export var combo_length: int = 1
## Weapon skill (RMB / LT): an ActiveAbility resource.
@export var skill: ActiveAbility


func _init() -> void:
	slot = Slot.WEAPON


## Shots one attack puts out: `projectile_count` is a flat modifier on a base stat of 1, so an
## implicit of +1 fires two, and every one of them carries the full hit.
func implicit_shots() -> float:
	return 1.0 + maxf(0.0, float(implicit_flat.get(&"projectile_count", 0.0)))


## Attacks per second the player actually gets at `attack_speed`. For every style but the bow
## that is simply the weapon's rate times the stat; a bow's cycle is the longer of its charge
## and its attack interval, both of which shorten with attack speed (`ItemTuning`).
func effective_rate(attack_speed: float = 1.0) -> float:
	var speed := maxf(0.2, attack_speed)
	if style != Style.RANGED_BOW:
		return maxf(0.1, attacks_per_second) * speed
	return 1.0 / ItemTuning.shared().bow_cycle_seconds(attacks_per_second, speed)


## Damage multiplier one sustained attack carries. Holding the attack button on a bow fires at
## full charge and immediately starts the next, so a bow sustains its full-charge multiplier;
## every other style just hits for its base damage.
func sustained_damage_multiplier() -> float:
	if style != Style.RANGED_BOW:
		return 1.0
	return ItemTuning.shared().bow_full_damage_mult


## Damage per second holding the attack button produces at `attack_speed`, before the wearer's
## damage stats. This — not `base_damage * attacks_per_second` — is what the power ladder in
## `ItemTuning` is measured in, because a bow's charge model makes those two different numbers.
func effective_dps(attack_speed: float = 1.0) -> float:
	return (
		base_damage
		* sustained_damage_multiplier()
		* effective_rate(attack_speed)
		* implicit_shots()
	)


## `effective_dps()` at x1 attack speed, for callers with no wearer to hand (item cards, the
## authoring ladder). Kept as a name because it is the number weapon bases are authored to.
func raw_dps() -> float:
	return effective_dps(1.0)


## True for a style whose attack spawns projectiles (the only styles that read the
## projectile_count / pierce / projectile_size / projectile_speed stats).
func is_projectile_style() -> bool:
	return style == Style.RANGED_BOW or style == Style.RANGED_WAND or style == Style.THROWN


## Family `style` belongs to.
static func family_of(style_value: Style) -> Family:
	for index in range(FAMILY_STYLES.size()):
		if FAMILY_STYLES[index].has(int(style_value)):
			return index as Family
	return Family.MELEE


## `WeaponBase.Style` ints that make up `family`.
static func styles_in_family(family_value: Family) -> PackedInt32Array:
	return PackedInt32Array(FAMILY_STYLES[clampi(int(family_value), 0, FAMILY_STYLES.size() - 1)])


## Short name of `family`, for report tables and failure messages.
static func family_name(family_value: Family) -> StringName:
	return FAMILY_NAMES[clampi(int(family_value), 0, FAMILY_NAMES.size() - 1)]


## Family this weapon belongs to.
func family() -> Family:
	return family_of(style)
