## Kernel spike (hazard, boss/Greybeard attack): the tile is marked for 0.6 s, then spikes erupt
## for `duration` seconds and the hazard removes itself. Enemies are immune.
class_name KernelSpike
extends TrapBase

const DEFAULT_DURATION := 1.5


func _init() -> void:
	kind = &"kernel_spike"
	damage = 20.0
	knockback = 90.0
	telegraph_time = 0.6
	active_time = DEFAULT_DURATION
	cooldown_time = 0.15
	enemies_immune = true
	one_shot = true
	trigger_on_spawn = true
	multi_hit_interval = 0.5


func configure(extra: Dictionary) -> void:
	super.configure(extra)
	if extra.has("duration"):
		active_time = maxf(0.1, float(extra["duration"]))
	lifetime = 0.0


func _tell_color(t: float) -> Color:
	var c := _danger.lerp(Color.WHITE, 0.2)
	c.a = lerpf(0.3, 0.7, t)
	return c
