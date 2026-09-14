## Spike floor (docs §9): the tile darkens for 0.5 s, then spikes pop for 0.4 s dealing 15.
## Proximity-triggered by anything stepping on it; 2 s cooldown. Hits enemies too.
class_name SpikeFloor
extends TrapBase


func _init() -> void:
	kind = &"spike_floor"
	proximity_trigger = true
	damage = 15.0
	telegraph_time = 0.5
	active_time = 0.4
	cooldown_time = 2.0


## Spike tells darken the tile rather than glow.
func _tell_color(t: float) -> Color:
	var dark := Color(0.0, 0.0, 0.0, 1.0).lerp(_danger, 0.35)
	dark.a = lerpf(0.3, 0.6, t)
	return dark
