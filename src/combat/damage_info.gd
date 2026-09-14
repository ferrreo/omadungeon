## Immutable-ish description of one damage event. Built by attackers, consumed by Health.
class_name DamageInfo
extends RefCounted

## Damage tags drive stat multipliers and resistances.
const TAG_MELEE := &"melee"
const TAG_RANGED := &"ranged"
const TAG_ABILITY := &"ability"
const TAG_PHYSICAL := &"physical"
const TAG_FIRE := &"fire"
const TAG_FROST := &"frost"
const TAG_SHOCK := &"shock"
const TAG_POISON := &"poison"
const TAG_ARCANE := &"arcane"
const TAG_TRAP := &"trap"
const TAG_TRUE := &"true"  # ignores armor

var amount: float = 0.0
var tags: Array[StringName] = []
var source: Node2D = null
var team: Layers.Team = Layers.Team.NEUTRAL
var knockback: Vector2 = Vector2.ZERO
var is_crit: bool = false
## Status effects to apply on hit: Array[StatusEffect].
var statuses: Array[StatusEffect] = []
## Final amount actually applied — never more than the target's remaining HP (filled by Health).
var applied: float = 0.0
## Mitigated damage that exceeded the target's remaining HP (filled by Health). Kept so shield
## pools can forward what they could not soak without inflating run statistics.
var overkill: float = 0.0


static func create(
	dmg: float, dmg_tags: Array[StringName], from: Node2D, from_team: Layers.Team
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = dmg
	info.tags = dmg_tags.duplicate()
	info.source = from
	info.team = from_team
	return info


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func with_knockback(dir: Vector2, strength: float) -> DamageInfo:
	knockback = dir.normalized() * strength
	return self


func with_status(effect: StatusEffect) -> DamageInfo:
	statuses.append(effect)
	return self


func duplicate_info() -> DamageInfo:
	var copy := DamageInfo.new()
	copy.amount = amount
	copy.tags = tags.duplicate()
	copy.source = source
	copy.team = team
	copy.knockback = knockback
	copy.is_crit = is_crit
	copy.statuses = statuses.duplicate()
	return copy
