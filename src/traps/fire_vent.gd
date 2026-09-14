## Fire vent (docs §9): a smoke puff for 0.5 s, then a burning zone for 2 s that re-hits every
## 0.5 s and applies BURN. Cycles while the player is in the room.
class_name FireVent
extends TrapBase

const BURN_DURATION := 3.0
const BURN_DPS := 4.0

var flames: CPUParticles2D
var _heat: Color = Color(1.0, 0.55, 0.2)


func _init() -> void:
	kind = &"fire_vent"
	auto_cycle = true
	damage = 4.0
	knockback = 10.0
	telegraph_time = 0.5
	active_time = 2.0
	cooldown_time = 3.0
	multi_hit_interval = 0.5
	tags = [DamageInfo.TAG_TRAP, DamageInfo.TAG_FIRE]


func _on_setup() -> void:
	_heat = _palette_color(&"heat")
	statuses = [StatusEffect.make(StatusEffect.Kind.BURN, BURN_DURATION, BURN_DPS, self)]
	flames = CPUParticles2D.new()
	flames.name = "Flames"
	flames.emitting = false
	flames.amount = 18
	flames.lifetime = 0.5
	flames.direction = Vector2.UP
	flames.spread = 25.0
	flames.initial_velocity_min = 25.0
	flames.initial_velocity_max = 55.0
	flames.gravity = Vector2(0.0, -40.0)
	flames.scale_amount_min = 1.0
	flames.scale_amount_max = 3.0
	flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 5.0
	flames.color = _heat
	add_child(flames)
	particles.color = _heat.lerp(Color.WHITE, 0.6)
	particles.gravity = Vector2(0.0, -30.0)


func _tell_color(t: float) -> Color:
	var c := _heat.lerp(_danger, 0.4)
	c.a = lerpf(0.2, 0.55, t)
	return c


func _on_trigger() -> void:
	flames.emitting = true


func _on_cooldown() -> void:
	flames.emitting = false


func _on_idle() -> void:
	if flames != null:
		flames.emitting = false


func _on_palette_changed(palette: ThemePalette) -> void:
	super._on_palette_changed(palette)
	var target := palette.get_color(&"heat")
	if not is_inside_tree() or _tint_tween == null or not _tint_tween.is_valid():
		_heat = target
		return
	# Same (parallel) tween as the base crossfade: never a second, competing one.
	_tint_tween.tween_method(_set_heat, _heat, target, PALETTE_TWEEN)


func _set_heat(c: Color) -> void:
	_heat = c
	if flames != null:
		flames.color = c
