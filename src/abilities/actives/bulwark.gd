## Bulwark (Fighter): a shield absorbing a fraction of max HP for a few seconds; each absorbed
## hit reflects a melee pulse around the player. Uses `player.set_shield(...)` when the player
## implements it (the shipped Player does), otherwise a BulwarkShield health pool routed
## through the Hurtbox.
class_name BulwarkAbility
extends ActiveAbility

## Minimum gap between reflect pulses so a multi-hit burst cannot spam hitboxes.
const PULSE_INTERVAL := 0.2

@export var shield_fraction: float = 0.3
## Extra shield fraction per tier above 1.
@export var shield_per_tier: float = 0.05
@export var duration: float = 3.0
@export var reflect_fraction: float = 0.5
@export var pulse_radius: float = 28.0
@export var pulse_knockback: float = 120.0

var _absorb_handler: Callable
var _absorb_source: Object
var _hit_handler: Callable
var _hit_source: Entity
var _pulse_ready_at: float = 0.0


func _activate(player: Node2D, _aim: Vector2) -> bool:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree() or entity.health == null:
		return false
	var amount := entity.health.max_hp * (shield_fraction + shield_per_tier * (tier - 1))
	if player.has_method("set_shield"):
		_call_set_shield(player, amount)
		_watch_absorption(entity)
	else:
		var existing := entity.get_node_or_null("BulwarkShield") as BulwarkShield
		if existing != null:
			existing.queue_free()
		var shield := BulwarkShield.new().setup(self, amount, duration)
		shield.name = "BulwarkShield"
		shield.reflect_fraction = reflect_fraction
		shield.pulse_radius = pulse_radius
		shield.pulse_knockback = pulse_knockback
		entity.add_child(shield)
	AbilityFx.flash(entity, &"accent", 0.2)
	AbilityFx.squash(entity, -0.15, 0.25)
	return true


## Calls the player's own `set_shield`, honouring either `(amount)` or `(amount, duration)`.
func _call_set_shield(player: Node2D, amount: float) -> void:
	var argc := 1
	for method: Dictionary in player.get_method_list():
		if method.get("name", "") == "set_shield":
			argc = (method.get("args", []) as Array).size()
			break
	if argc >= 2:
		player.call("set_shield", amount, duration)
	else:
		player.call("set_shield", amount)


## Pulses whenever the player's shield actually soaks damage. `PlayerHealth.shield_absorbed`
## is the precise signal; `Entity.hit_received` is the fallback for players whose health pool
## does not report absorption (it fires only on damage that got through, so it is strictly
## worse - see docs 4.4). A second cast replaces the previous handler instead of stacking.
func _watch_absorption(entity: Entity) -> void:
	_clear_handlers()
	_pulse_ready_at = 0.0
	var absorber := entity.health as Object
	if absorber != null and absorber.has_signal(&"shield_absorbed"):
		_absorb_handler = func(amount: float, _info: DamageInfo) -> void:
			_request_pulse(entity, amount)
		_absorb_source = absorber
		absorber.connect(&"shield_absorbed", _absorb_handler)
	else:
		_hit_handler = func(info: DamageInfo) -> void: _request_pulse(entity, info.amount)
		_hit_source = entity
		entity.hit_received.connect(_hit_handler)
	entity.get_tree().create_timer(duration).timeout.connect(_clear_handlers)


func _clear_handlers() -> void:
	if _absorb_handler.is_valid() and is_instance_valid(_absorb_source):
		if _absorb_source.is_connected(&"shield_absorbed", _absorb_handler):
			_absorb_source.disconnect(&"shield_absorbed", _absorb_handler)
	_absorb_handler = Callable()
	_absorb_source = null
	if _hit_handler.is_valid() and is_instance_valid(_hit_source):
		if _hit_source.hit_received.is_connected(_hit_handler):
			_hit_source.hit_received.disconnect(_hit_handler)
	_hit_handler = Callable()
	_hit_source = null


## Hits arrive inside physics callbacks, where new Area2D state cannot be set: defer.
func _request_pulse(entity: Entity, absorbed: float) -> void:
	if not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _pulse_ready_at:
		return
	_pulse_ready_at = now + PULSE_INTERVAL
	_pulse.bind(entity, maxf(1.0, absorbed * reflect_fraction)).call_deferred()


func _pulse(entity: Entity, reflected: float) -> void:
	if not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	AbilityUtil.spawn_hitbox(
		entity,
		self,
		AbilityUtil.world_of(entity),
		entity.global_position,
		pulse_radius,
		0.12,
		[DamageInfo.TAG_ABILITY, DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL],
		pulse_knockback,
		[],
		0.0,
		reflected / tier_damage_scale()
	)
