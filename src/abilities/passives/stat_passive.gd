## A passive that is nothing but `Stats` modifiers, described entirely in its `.tres`.
##
## Most passives in the pool are a rule ("reflect melee damage", "kills refund cooldown") and
## need their own script. A good many are simply a number on a stat sheet, and those should
## not each cost a file: this one script plus a resource is the whole ability. Every entry in
## `percent_stats` adds the matching `percent_values` fraction as a percent modifier under
## `owner_id()`, and every entry in `flat_stats` adds the matching `flat_values` as a flat
## modifier. Both scale with `tier`, so a tier-3 copy is three times the tier-1 one.
##
## Primary stats (`vitality`, `might`, ...) belong in `flat_stats`: `Stats` reads their flat
## modifiers when it derives the secondaries, so "+1 Might" behaves exactly as a chest stat
## point does.
class_name StatPassive
extends PassiveAbility

## Stat names touched by percent modifiers, parallel to `percent_values`.
@export var percent_stats: Array[StringName] = []
## Fractions added as percent modifiers (0.4 = +40%, -0.3 = -30%), per tier.
@export var percent_values: PackedFloat32Array = PackedFloat32Array()
## Stat names touched by flat modifiers, parallel to `flat_values`.
@export var flat_stats: Array[StringName] = []
## Amounts added as flat modifiers, per tier.
@export var flat_values: PackedFloat32Array = PackedFloat32Array()


func apply(player: Node2D) -> void:
	var entity := player as Entity
	if entity == null:
		return
	apply_to_stats(entity.stats)


## Registers this passive's modifiers on `stats` under `owner_id()`. Split out so the balance
## simulation can fold a passive into a bare `Stats` with no `Entity` around it.
func apply_to_stats(stats: Stats) -> void:
	if stats == null:
		return
	var oid := owner_id()
	for i in range(mini(percent_stats.size(), percent_values.size())):
		stats.add_percent(percent_stats[i], oid, percent_values[i] * tier)
	for i in range(mini(flat_stats.size(), flat_values.size())):
		stats.add_flat(flat_stats[i], oid, flat_values[i] * tier)
