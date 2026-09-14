## A pooled gameplay light: the glow on a sword swing, a bolt in flight, a fireball, the bloom
## of an explosion, the shimmer on a chest. Every one is a row of `LightingProfile.emitters`
## (kind -> palette role, energy, radius, fade), so a spell's light is data and its colour is
## the theme's: `LightRig.light_color_for(role)` resolves the role through the live palette and
## the music mood, and a theme swap mid-run retints every emitter alight.
##
## Two shapes of life. `attach(host, kind)` follows `host` and goes out when the host leaves
## the tree, hides, or - when the row has a `fade` - after that many seconds; `flash(kind, pos)`
## is a one-shot at a point that blooms for `ATTACK` seconds and fades over the row's `fade`.
## Both hand the node back to the rig's pool: a barrage of two hundred bolts allocates no
## light past the high-water mark, and the cap (`LightingProfile.emitter_max`) drops a request
## rather than queueing it, so a fight cannot store up light to release later.
##
## Which masks a light reaches is the shape of its life, not a second light. A light that *lives
## with its host* - a chest's shimmer, an altar's, the stairs', a fire, a bolt in flight, the
## player's own - has no fade of its own and is on `LightRig.LIT_MASK`: it lifts the floor and
## the bodies standing in that pool by the same amount, the way a door torch does, so the prop
## ladder measured against the floor as drawn survives the pool. A light that is *on its way out
## from the moment it appears* - every one-shot, and every row with a fade: a swing, a spell
## bloom, an explosion - is on `LightRig.ENV_MASK` and lights the ground only, because a light
## gone in a fifth of a second has no business rewriting what a crate looks like.
##
## Nothing here ever pulses: the only motion an emitter makes is one rise and one fall.
class_name LightEmitter
extends PointLight2D

## Seconds a one-shot takes to reach full energy before it starts to fade.
const ATTACK := 0.06

var kind: StringName = &""
var role: StringName = &"accent"
## Energy at full, before the mood; `energy` is what is drawn this frame.
var base_energy: float = 0.4
var fade: float = 0.0
var may_shadow: bool = false
## What the light follows, or null for a one-shot.
var host: Node2D
## True for a light that follows a host, even after that host has been freed.
var following: bool = false
var age: float = 0.0
var alive: bool = false
var _rig: LightRig


func _init() -> void:
	name = "Emitter"
	blend_mode = Light2D.BLEND_MODE_ADD
	shadow_enabled = false
	shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	shadow_filter_smooth = 2.0
	top_level = true
	visible = false
	set_process(false)


## A light that follows `host` (any Node2D in the tree). Null when the layer is off, the pool
## is capped, or there is no live floor to light.
static func attach(target: Node2D, emitter_kind: StringName) -> LightEmitter:
	var rig := LightRig.current()
	if rig == null or target == null or not is_instance_valid(target):
		return null
	return rig.acquire_emitter(emitter_kind, target, target.global_position)


## A one-shot at `pos`: rises for `ATTACK` seconds and fades over the row's `fade` (a row with
## no fade gets `min_fade`, so a flash is never a single frame).
static func flash(emitter_kind: StringName, pos: Vector2, min_fade: float = 0.3) -> LightEmitter:
	var rig := LightRig.current()
	if rig == null:
		return null
	var e := rig.acquire_emitter(emitter_kind, null, pos)
	if e != null and e.fade <= 0.0:
		e.fade = min_fade
	return e


## Starts this light on `spec` (a `LightingProfile.emitter_spec` row) at `pos`.
func start(
	emitter_kind: StringName, spec: Dictionary, target: Node2D, pos: Vector2, rig: LightRig
) -> void:
	_rig = rig
	kind = emitter_kind
	role = spec["role"]
	base_energy = float(spec["energy"])
	texture_scale = float(spec["radius"])
	fade = float(spec["fade"])
	may_shadow = bool(spec["shadow"])
	host = target
	following = target != null
	# A standing light lights the bodies in its pool as well as the ground, at the same energy,
	# or the floor it lifts would stand off the prop carrying it; a passing one lights the
	# ground only.
	range_item_cull_mask = LightRig.LIT_MASK if lights_bodies() else LightRig.ENV_MASK
	age = 0.0
	alive = true
	global_position = pos
	visible = true
	shadow_enabled = false
	color = rig.light_color_for(role)
	energy = 0.0 if host == null else _target_energy()
	set_process(true)


## Fraction of full energy this light is at right now: the rise and the fall.
func envelope() -> float:
	if following:
		if fade <= 0.0:
			return 1.0
		return clampf(1.0 - age / fade, 0.0, 1.0)
	if age < ATTACK:
		return clampf(age / ATTACK, 0.0, 1.0)
	if fade <= 0.0:
		return 0.0
	var t := clampf((age - ATTACK) / fade, 0.0, 1.0)
	# Ease out: most of the light leaves early, the tail lingers, nothing steps.
	return (1.0 - t) * (1.0 - t)


## Puts the light out and returns it to the pool.
func release() -> void:
	if not alive:
		return
	alive = false
	host = null
	following = false
	visible = false
	shadow_enabled = false
	energy = 0.0
	set_process(false)
	if _rig != null and is_instance_valid(_rig):
		_rig.release_emitter(self)


## Re-reads the colour for the role (a theme swap, a mood shift).
func retint() -> void:
	if _rig != null and is_instance_valid(_rig) and alive:
		color = _rig.light_color_for(role)


## Whether this light reaches bodies as well as the ground: a standing light does, a passing
## one does not. Read off the row, so it is the same answer before and after `start()`.
func lights_bodies() -> bool:
	return fade <= 0.0 and following


func _target_energy() -> float:
	var scale := 1.0 if _rig == null else _rig.light_scale()
	return base_energy * scale * envelope()


func _process(delta: float) -> void:
	if not alive:
		return
	age += delta
	if following:
		if (
			host == null
			or not is_instance_valid(host)
			or not host.is_inside_tree()
			or not host.visible
		):
			release()
			return
		global_position = host.global_position
		if fade > 0.0 and age >= fade:
			release()
			return
	elif age >= ATTACK + fade:
		release()
		return
	energy = _target_energy()
