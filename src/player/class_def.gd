## Data definition of a playable class (docs §4.2/4.3): base stats, start loadout ids,
## dodge flavour and art paths. Instances live in `data/classes/<id>.tres`.
class_name ClassDef
extends Resource

## How the dodge button behaves for this class.
enum DodgeStyle { ROLL, DASH, BLINK, DELEGATE }

const DODGE_STYLE_NAMES: Array[StringName] = [&"roll", &"dash", &"blink", &"delegate"]

@export var id: StringName = &"fighter"
@export var display_name: String = "Fighter"
@export_multiline var description: String = ""

@export_group("Base stats")
@export var vitality: int = 6
@export var might: int = 6
@export var precision: int = 2
@export var arcana: int = 1
@export var swiftness: int = 3
@export var fortune: int = 2

@export_group("Loadout")
## WeaponBase id resolved by the items module registry.
@export var start_weapon_id: StringName = &"rusty_sword"
## PassiveAbility id applied as an uncounted innate.
@export var innate_passive_id: StringName = &"second_wind"
## ActiveAbility id that is only offered to this class.
@export var class_active_id: StringName = &"bulwark"
## Extra ability ids granted at run start (e.g. the Oligarch's Contract).
@export var extra_ability_ids: Array[StringName] = []
@export var start_gold: int = 0
@export var dodge_style: DodgeStyle = DodgeStyle.ROLL

@export_group("Art")
## 16x16 frame sheet: row0 idle x4, row1 run x6, row2 dodge x4, row3 hurt x2, row4 death x6.
@export_file("*.png") var sprite_sheet: String = "res://assets/sprites/player/fighter.png"
@export_file("*.png") var portrait: String = "res://assets/sprites/player/fighter_portrait.png"


## Primary stat totals keyed by `Stats.PRIMARY` names.
func base_stats() -> Dictionary:
	return {
		&"vitality": vitality,
		&"might": might,
		&"precision": precision,
		&"arcana": arcana,
		&"swiftness": swiftness,
		&"fortune": fortune,
	}


## Dodge style as a StringName (what `EventBus.player_dodged` carries).
func dodge_style_name() -> StringName:
	return DODGE_STYLE_NAMES[dodge_style]


## Sprite sheet path; falls back to the id-derived path when the export is empty.
func sprite_sheet_path() -> String:
	if sprite_sheet.is_empty():
		return "res://assets/sprites/player/%s.png" % id
	return sprite_sheet


func portrait_path() -> String:
	if portrait.is_empty():
		return "res://assets/sprites/player/%s_portrait.png" % id
	return portrait
