## Data definition for one trap kind: which scene/script to spawn, where it may appear and
## the numbers (damage, cycle timings). Behaviour lives in the TrapBase subclass; numbers here
## so content can be tuned in `data/traps/*.tres` without touching code.
class_name TrapDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = "Trap"
## Optional packed scene (root must be a TrapBase). When null, `script` is instantiated.
@export var scene: PackedScene
## Script extending TrapBase used when `scene` is not set.
@export var script_class: GDScript
## Biome ids this trap may be generated in (crypt, forge, frost, library, void). Empty = all.
@export var biomes: Array[StringName] = []
## True for hazards spawned at runtime by enemies/bosses rather than by the floor generator.
@export var is_hazard: bool = false
@export var damage: float = 15.0
@export var knockback: float = 40.0
## Seconds the tell is shown before the trap becomes dangerous.
@export var telegraph_time: float = 0.5
## Seconds the trap stays dangerous.
@export var active_time: float = 0.4
## Seconds after the active window before the trap can fire again.
@export var cooldown_time: float = 2.0
## Default lifetime for hazards (seconds); 0 = permanent.
@export var duration: float = 0.0
## Enemy hurtboxes are skipped (Tinkerer-placed traps).
@export var enemies_immune: bool = false
## Generator weight when picking a trap for a room.
@export var weight: float = 1.0


## True when this trap may be placed in `biome`.
func allows_biome(biome: StringName) -> bool:
	return biomes.is_empty() or biomes.has(biome)


## Damage one hit of this trap does on `floor_index`, scaled by the shipped difficulty curve
## (`data/balance/difficulty_curve.tres`) the same way `EnemyDef.scaled_damage()` is. A flat
## `damage` made the hazard layer a floor-1 threat and cosmetic afterwards, which is exactly
## when the generator turns trap density up. Harmless kinds (`damage` 0) stay harmless.
func scaled_damage(floor_index: int) -> float:
	if damage <= 0.0:
		return damage
	return damage * DifficultyCurve.shared().trap_multiplier(floor_index)
