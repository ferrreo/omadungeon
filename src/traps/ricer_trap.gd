## Ricer trap (hazard, Tinkerers §7.3): a decorative prop dropped by a Ricer that shakes for 1 s,
## then turns into spikes for `duration` seconds and vanishes. Enemies are immune.
class_name RicerTrap
extends TrapBase

const DEFAULT_DURATION := 3.0
const SHAKE_PX := 1.0


func _init() -> void:
	kind = &"ricer_trap"
	damage = 12.0
	telegraph_time = 1.0
	active_time = DEFAULT_DURATION
	cooldown_time = 0.2
	enemies_immune = true
	one_shot = true
	trigger_on_spawn = true
	multi_hit_interval = 0.6


func configure(extra: Dictionary) -> void:
	super.configure(extra)
	if extra.has("duration"):
		active_time = maxf(0.1, float(extra["duration"]))
	lifetime = 0.0


func _on_telegraph_process(_delta: float) -> void:
	if sprite != null:
		var phase := int(state_time * 30.0) % 3 - 1
		sprite.position = Vector2(float(phase) * SHAKE_PX, 0.0)


func _on_trigger() -> void:
	if sprite != null:
		sprite.position = Vector2.ZERO
