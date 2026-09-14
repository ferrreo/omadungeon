## Child node that heals its Entity parent by `total` HP spread evenly over `duration`,
## then frees itself. Used by Reboot.
class_name HealOverTime
extends Node

var total: float = 20.0
var duration: float = 3.0
var _healed: float = 0.0
var _elapsed: float = 0.0
var _entity: Entity
var _particles: CPUParticles2D


func setup(amount: float, seconds: float) -> HealOverTime:
	total = amount
	duration = maxf(0.05, seconds)
	return self


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null:
		queue_free()
		return
	_particles = CPUParticles2D.new()
	_particles.amount = 10
	_particles.lifetime = 0.6
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 6.0
	_particles.direction = Vector2.UP
	_particles.spread = 20.0
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 14.0
	_particles.initial_velocity_max = 24.0
	_particles.texture = AbilityFx.circle_texture(1)
	AbilityFx.bind_palette(_particles, &"heal")
	_entity.add_child(_particles)
	_particles.emitting = true


func _process(delta: float) -> void:
	if _entity == null or _entity.health == null or _entity.health.is_dead():
		_finish()
		return
	_elapsed += delta
	var target := total * clampf(_elapsed / duration, 0.0, 1.0)
	var step := target - _healed
	if step >= 1.0 or _elapsed >= duration:
		_entity.health.heal(step)
		_healed += step
	if _elapsed >= duration:
		_finish()


func _finish() -> void:
	if is_instance_valid(_particles):
		_particles.emitting = false
		_particles.get_tree().create_timer(0.7).timeout.connect(_particles.queue_free)
	queue_free()
