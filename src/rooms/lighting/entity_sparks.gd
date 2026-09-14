## The light a living thing carries: a few visible motes around it, and the glow those motes give.
##
## This is the owner's own answer to "the room is too dark to fight in", and the shape of it is
## the whole point: "the player and enemies are particles from both should illuminate a bit". A
## bare `PointLight2D` bolted to a body would light the sprite just as well and would be the
## ambient wash again, parented to a node - a lit pixel with nothing on screen causing it. Motes
## that glow are a light you can point at, and pointing at it is the rule.
##
## So the particles are the source, and the light follows them rather than the other way round:
## its energy is scaled by how many motes are actually drifting right now
## (`CPUParticles2D.amount` against the kind's own maximum), so cutting the density cuts the
## light, and a slow noise wander on top makes it breathe the way a handful of embers does. Never
## a sine and never anything at the tempo of the music: the wander is `FastNoiseLite` along time,
## like the torches (`FloorRoot._process`), and `Accessibility.flash` damps it.
##
## Under reduce-motion the motes stop drifting and their count is capped, which would take the
## light with it - so the light has its own floor (`REDUCED_MOTION_FLOOR`) that the density scale
## may not pull it under. An accessibility setting may make the dungeon calmer; it may not make it
## unplayable.
class_name EntitySparks
extends Node2D

const NODE_NAME := "Sparks"
const GROUP := &"entity_sparks"
## Least of its authored energy the light keeps once reduce-motion has capped the motes. Below
## this the accessibility path is a black screen, which is not an accessibility path.
const REDUCED_MOTION_FLOOR := 0.75
## How far the mote count may swing the light either way around its authored energy, and how fast
## the noise that drives it wanders. Slow: a handful of embers breathing, not a strobe.
const WANDER := 0.12
const WANDER_HZ := 0.9

## Palette role the player's motes burn in, by class id. Each class carries its own colour, which
## is also how a player finds themselves in a dark room.
const CLASS_ROLES: Dictionary = {
	&"fighter": &"heat",
	&"ranger": &"heal",
	&"wizard": &"magic",
	&"oligarch": &"loot",
}
## ...and the enemy factions, so a thing coming at you out of the dark announces which kind of
## thing it is a moment before it arrives (`EnemyDef.Faction`).
const FACTION_ROLES: Array[StringName] = [&"danger", &"magic", &"cold", &"danger"]

var particles: CPUParticles2D
var light: PointLight2D
## Energy the light burns at before the density scale and the wander.
var base_energy: float = 0.0
var base_amount: int = 0
## How far the glow is paled toward white against the motes' own colour (see `glow_of`).
var base_paleness: float = 0.0
var _noise := FastNoiseLite.new()
var _time: float = 0.0


func _init() -> void:
	name = NODE_NAME
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.01


## Builds the motes and the light they give. `radius` is a `texture_scale` on the shared 96 px
## gradient; `amount` is how many motes drift at full density; `mask` is the item cull mask the
## glow reaches (`LightRig.LIT_MASK`), passed in rather than read, because a light source may not
## depend on the rig that hangs it - `LightRig` already names this class and GDScript resolves
## neither of a pair that name each other.
func setup(
	texture: Texture2D,
	color: Color,
	energy: float,
	radius: float,
	amount: int,
	spread: float,
	mask: int,
	paleness: float
) -> void:
	base_energy = energy
	base_paleness = clampf(paleness, 0.0, 1.0)
	base_amount = maxi(amount, 1)
	particles = CPUParticles2D.new()
	particles.name = "Motes"
	particles.amount = base_amount
	particles.lifetime = 1.6
	particles.explosiveness = 0.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = spread
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0.0, -6.0)
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 8.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 1.0
	particles.color = color
	# The motes are the light's own body, so nothing lights them: they are already emitting.
	particles.light_mask = 0
	particles.z_index = 1
	add_child(particles)
	light = PointLight2D.new()
	light.name = "MoteLight"
	light.texture = texture
	light.texture_scale = radius
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.range_item_cull_mask = mask
	light.shadow_enabled = false
	light.color = glow_of(color, base_paleness)
	light.energy = energy
	add_child(light)
	add_to_group(GROUP)
	set_process(true)


## Re-reads the colour and the energy (a palette swap, a mood change, an enemy waking up).
func relight(color: Color, energy: float, radius: float = -1.0) -> void:
	base_energy = energy
	if particles != null:
		particles.color = color
	if light != null:
		light.color = glow_of(color, base_paleness)
		if radius > 0.0:
			light.texture_scale = radius


## The colour the motes *give*, against the colour the motes *are*: the same hue, paled toward
## white by `paleness`.
##
## The two are not the same thing and the difference is the whole of whether a player can read
## their own character. A saturated light multiplies a sprite channel for channel, so a warm glow
## crushes every blue in the art and a magic-coloured one crushes every red: the sprite stops
## being the colours the artist drew and becomes a monochrome of the flame. The motes themselves
## stay fully tinted - they are what a player sees and what tells four classes apart at a glance -
## and the light they throw is paler, so what it lands on keeps its own colours.
static func glow_of(color: Color, paleness: float) -> Color:
	return color.lerp(Color.WHITE, clampf(paleness, 0.0, 1.0))


## How many motes are drifting, as a share of the kind's own maximum: the light is scaled by it,
## so the particles really are what is lighting the room.
func density() -> float:
	if particles == null or base_amount <= 0:
		return 0.0
	return clampf(float(particles.amount) / float(base_amount), 0.0, 1.0)


## Applies the accessibility policy: reduce-motion caps the count and stops the drift, and the
## light keeps `REDUCED_MOTION_FLOOR` of itself whatever that does to the density.
func apply_accessibility(reduced: bool, capped: int) -> void:
	if particles == null:
		return
	particles.amount = mini(base_amount, maxi(capped, 1)) if reduced else base_amount
	particles.gravity = Vector2.ZERO if reduced else Vector2(0.0, -6.0)
	particles.initial_velocity_max = 0.0 if reduced else 8.0


func _process(delta: float) -> void:
	if light == null:
		return
	_time += delta
	var scale := maxf(density(), REDUCED_MOTION_FLOOR)
	var wander := Accessibility.flash(WANDER) * _noise.get_noise_1d(_time * WANDER_HZ * 40.0)
	light.energy = maxf(base_energy * scale * (1.0 + wander), 0.0)


## The palette role a class's motes burn in.
static func role_for_class(id: StringName) -> StringName:
	var role: Variant = CLASS_ROLES.get(id, &"accent")
	return role if role is StringName else &"accent"


## The palette role a faction's motes burn in.
static func role_for_faction(faction: int) -> StringName:
	return FACTION_ROLES[clampi(faction, 0, FACTION_ROLES.size() - 1)]
