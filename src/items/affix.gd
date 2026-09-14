## One rollable item affix: a stat modifier range plus naming fragments.
class_name Affix
extends Resource

enum Mode { FLAT, PERCENT, ON_HIT_STATUS, SPECIAL }

@export var id: StringName = &""
@export var stat: StringName = &"might"
@export var mode: Mode = Mode.FLAT
@export var min_value: float = 1.0
@export var max_value: float = 3.0
## Name fragments: prefix ("Sharp") or suffix ("of Embers").
@export var prefix: String = ""
@export var suffix: String = ""
## Slots this affix may roll on (empty = any).
@export var slots: Array[StringName] = []
@export var weight: float = 1.0
## For ON_HIT_STATUS: which status.
@export var status_kind: StatusEffect.Kind = StatusEffect.Kind.BURN
## Minimum rarity index (0 common .. 3 legendary).
@export var min_rarity: int = 0
## WeaponBase.Style ints this affix may roll on when the base is a weapon (empty = any style).
## This is what keeps projectile affixes off a sword, where nothing ever reads them.
@export var weapon_styles: Array[int] = []
## Damage tags the weapon must carry when the base is a weapon (empty = any). "+% Melee Damage"
## on a bow can never multiply anything, because a bow hit is never tagged melee.
@export var weapon_tags: Array[StringName] = []


## True when this affix may roll on `base` *and* does something there: the slot list, plus the
## weapon style/tag gates for weapon bases. A null base accepts everything (pool listings).
func can_roll_on(base: ItemBase) -> bool:
	if base == null:
		return true
	if not slots.is_empty() and not slots.has(base.slot_name()):
		return false
	var weapon := base as WeaponBase
	if weapon == null:
		return true
	if not weapon_styles.is_empty() and not weapon_styles.has(int(weapon.style)):
		return false
	for tag: StringName in weapon_tags:
		if not weapon.tags.has(tag):
			return false
	return true


func roll(rng: RandomNumberGenerator, rarity_scale: float = 1.0) -> float:
	var v := rng.randf_range(min_value, max_value) * rarity_scale
	if mode == Mode.FLAT:
		return roundf(v)
	return snappedf(v, 0.005)


func describe(value: float) -> String:
	match mode:
		Mode.FLAT:
			return "+%d %s" % [int(value), String(stat).capitalize()]
		Mode.PERCENT:
			return "+%d%% %s" % [int(roundf(value * 100.0)), String(stat).capitalize()]
		Mode.ON_HIT_STATUS:
			return (
				"%d%% chance to %s on hit"
				% [
					int(roundf(value * 100.0)),
					(StatusEffect.Kind.keys()[status_kind] as String).to_lower()
				]
			)
	return String(id)
