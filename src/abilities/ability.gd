## Base resource for every ability (active or passive). Concrete abilities extend
## ActiveAbility / PassiveAbility and live in data/abilities/*.tres with a script.
class_name Ability
extends Resource

enum Kind { ACTIVE, PASSIVE }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.ACTIVE
@export var icon: Texture2D
@export var max_tier: int = 3
## Only offered to this class (empty = everyone).
@export var class_only: StringName = &""
## Weight in the offer pool.
@export var weight: float = 1.0
var tier: int = 1


func is_active() -> bool:
	return kind == Kind.ACTIVE


func describe(for_tier: int = -1) -> String:
	var t := tier if for_tier < 0 else for_tier
	return description.format({"tier": t})


func duplicate_ability() -> Ability:
	var copy := duplicate() as Ability
	copy.tier = tier
	return copy
