## Data definition for one enemy type. Behaviour lives in the scene's EnemyBase subclass;
## numbers live here so content agents can tune without touching code.
class_name EnemyDef
extends Resource

enum Faction { CLOWNS, GREYBEARDS, TINKERERS, BOSS }

@export var id: StringName = &""
@export var display_name: String = "Enemy"
@export var faction: Faction = Faction.CLOWNS
@export var scene: PackedScene
## Sprite sheet: 4 columns, rows = idle/move/windup/attack/hurt/death (see EnemyBase).
@export var texture: Texture2D
## Frame size in px of `texture` (16 or 32).
@export var sprite_size: int = 16
@export var max_hp: float = 30.0
@export var damage: float = 8.0
@export var move_speed: float = 60.0
@export var armor: float = 0.0
@export var knockback_resistance: float = 0.0
@export var is_elite: bool = false
@export var is_boss: bool = false
## Difficulty budget cost when populating a room (docs §7).
@export var cost: float = 1.0
@export var min_floor: int = 0
@export var max_floor: int = 99
@export var gold_min: int = 2
@export var gold_max: int = 6
@export var weight: float = 1.0

@export_group("Behaviour")
## Seconds of the danger-flash tell before the attack lands.
@export var windup_time: float = 0.4
## Seconds the ATTACK state lasts (hitbox window / dash / throw).
@export var attack_time: float = 0.25
## Seconds of vulnerability after an attack before approaching again.
@export var recover_time: float = 0.5
## Minimum seconds between two attacks (counted from the end of recovery).
@export var attack_cooldown: float = 0.4
## Distance (px) to the target at which the enemy may start an attack.
@export var attack_range: float = 18.0
## Distance the enemy tries to hold; ranged enemies keep this, melee ignore it.
@export var preferred_range: float = 0.0
## Walk away when the target is closer than preferred_range (kiting).
@export var retreat_when_close: bool = false
## Distance (px) this enemy notices the player from, with a clear line of sight. 0 means the
## shared awareness profile's range (`data/enemies/awareness.tres`), which is what nearly
## every enemy should use; set it only for one that is meant to be keener or dozier than the
## rest. Whatever is set here, an enemy always sees at least as far as it can attack.
@export var sight_range: float = 0.0
## Floats over PIT areas (balloon clown).
@export var ignores_pits: bool = false
## Body collision radius in px.
@export var body_radius: float = 5.0
## Hurtbox size in px.
@export var hurtbox_size: Vector2 = Vector2(10, 12)
## Enemies this one can summon (clown car, dotfile golem). Empty for most.
@export var summon_defs: Array[EnemyDef] = []
## Free-form tuning numbers read by the concrete script (`param(&"charge_speed", 220.0)`).
@export var params: Dictionary = {}


## HP on `floor_index`: `max_hp` times the floor's multiplier from the shipped difficulty
## curve (`data/balance/difficulty_curve.tres`), times the curve's elite multiplier for an
## elite. The per-floor shape is data so the ramp can be shaped floor by floor instead of
## being a straight line hard-coded here.
func scaled_hp(floor_index: int) -> float:
	var curve := DifficultyCurve.shared()
	var elite_mult := curve.elite_hp_multiplier if is_elite else 1.0
	return max_hp * curve.hp_multiplier(floor_index) * elite_mult


## Damage on `floor_index`, scaled by the same curve. Elites normally get no damage
## multiplier — their `damage` field is the number the player is hit for, so the .tres stays
## the source of truth — but the curve may override that.
func scaled_damage(floor_index: int) -> float:
	var curve := DifficultyCurve.shared()
	var elite_mult := curve.elite_damage_multiplier if is_elite else 1.0
	return damage * curve.damage_multiplier(floor_index) * elite_mult


## Reads a tuning number from `params` with a code default.
func param(key: StringName, default: float) -> float:
	return float(params.get(key, default))


## Reads an integer tuning number from `params` with a code default.
func param_int(key: StringName, default: int) -> int:
	return int(params.get(key, default))
