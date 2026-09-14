## Tuning for the dungeon's own light sources (docs §14: "simple 2D light on player + point
## lights on torches/lava"). The player's light lives on `player.tscn`; everything the *floor*
## lights - wall torches today, lava and braziers later - is sized from here, together with
## the one surface the floor paints that no light source reaches: the surround outside the
## rooms (`FloorRoot._build_void_backdrop`, `src/rooms/void_surround.gdshader`), whose whole
## job is to be the dark the torches are read against.
##
## `res://data/rooms/dungeon_light.tres` holds the numbers a designer tunes. A missing file is
## not an error: `resolve()` hands back a fresh resource carrying the same defaults, so the
## floor lights itself the same way in a test that never touches `data/`.
class_name DungeonLight
extends Resource

const PATH := "res://data/rooms/dungeon_light.tres"

## Shape of a light's falloff from its centre to its edge: alpha = (1 - t) ^ `FALLOFF_POWER`,
## sampled at `FALLOFF_STOPS` points along the radius.
##
## It was a straight line from 1 to 0, and that is a fine pool on a floor that is already lit.
## On a floor at a third of its light it is not a pool at all: light is *additive*, so the
## outer tenth of a linear ramp is still a large relative lift over near-black, and every
## lantern threw a halo most of a room wide. Six of them washed the room back to even - which
## is precisely the "lighting is there but BARELY makes a difference" the darkness round was
## opened by, surviving the darkness itself.
##
## A power falloff fixes the shape rather than the level: at 2.5 the pool keeps a bright core,
## is down to a quarter by half its radius and to a twentieth by three quarters of it, so it
## ends somewhere a person can see it end. Perceived lightness goes roughly as the cube root
## of luminance, which is what flattens a linear ramp into a haze and what this undoes.
const FALLOFF_POWER := 2.5
const FALLOFF_STOPS := 8

## Brightness of one torch light, on every theme: the dark exactly undone
## (`LightingProfile.unlit_floor + torch_energy = 1`), so at the flame the wall and the floor in
## front of it come back to the level the theme authored them at and no further.
##
## It was 0.5 with an exposure tracker in front of it (`torch_energy_reference`,
## `torch_energy_min_scale`) and a 0.4 turn-down on light themes. All three existed to stop an
## additive pool blowing out a floor that was *already lit by an ambient wash*. There is no such
## floor any more (`LightingProfile.unlit_floor`), so there is nothing to protect and the
## trackers were only holding the torches under the level that makes them the light in the room.
@export var torch_energy: float = 0.94
## Radius, as a multiple of the 96 px light texture (so ~3 tiles of falloff per unit), before
## the music mood scales it. Read it with `FALLOFF_POWER`: the nominal radius is about seven
## tiles, but a 2.5 power falloff is down to a quarter by half of it, so what a player sees is a
## pool about four tiles across with an edge.
@export var torch_texture_scale: float = 1.9
## Where the light sits inside the 16 px torch cell: at the flame, not at the sconce.
@export var torch_offset: Vector2 = Vector2(0, -3)
## How far the flicker swings the energy, as a fraction of it, and how fast. Damped by the
## reduced-flash accessibility setting and off entirely under reduce-motion.
@export var torch_flicker: float = 0.14
@export var torch_flicker_hz: float = 2.3
## Most torch lights one floor may carry. Past it torches are still drawn, just unlit - a
## 40-room floor would otherwise put 150 lights in one viewport for no visible gain.
@export var torch_max_lights: int = 96
## Side of the square radial gradient every floor light is drawn with, in pixels.
@export var light_texture_size: int = 96
## How far a light colour is pulled toward full value before it is used. A palette's `heat`
## has been guarded for contrast against a *surface*, which can leave it dark enough to light
## nothing; a light source is not a surface.
@export var light_value: float = 1.0
## ...and how far its chroma is pushed while doing so, as a multiplier on the role's own.
##
## It was 1.7, and 1.7 was right while an ambient wash drew most of the room and a pool was a
## tint laid on top of it. With the wash gone the light *is* the room - every pixel a player can
## see is the theme's colour multiplied by the flame's - and a saturated flame does two things
## that are now unaffordable. It paints the theme out: on `lighting_frame` tokyo-night a 1.7 flame
## rendered the whole navy floor magenta. And it flattens what it lights: measured on
## `prop_frame`, the crypt barrel's four body rungs drew 1.01 apart under a saturated pool
## against a `Prop.LIT_BODY_STEP` of 1.12, because the channels the flame is dim in crush every
## difference the art put there.
##
## 0.8 is a flame that is warm rather than coloured. The hue is still the theme's fire turned
## toward the theme's accent (`torch_role_color`) and a player still reads it as fire; what it no
## longer does is decide what colour the floor is or how many shades a crate has.
@export var light_saturation: float = 0.6
## How far a torch's hue is turned from the theme's `heat` toward its `accent`, as a fraction
## of the shortest arc between them. Every theme's `heat` is an orange, so at 0 every dungeon
## was lit by the same fire and the light - the one thing that touches every surface in a room
## - said nothing about the desktop. At 0.35 tokyo-night's torches pool pink over its navy,
## gruvbox's amber over its sand and nord's straw over its slate; the flame *sprite* stays on
## `heat`/`loot` (`TileRamp.flame_colors`), so a torch is still read as fire. Ignored when the
## accent has no chroma (a greyscale theme is lit by plain fire).
@export var torch_accent_mix: float = 0.35
## Chroma the accent needs before it may turn the light at all.
@export var torch_accent_min_saturation: float = 0.15

@export_group("Surround")
## How much darker the surround gets where nothing has been built, as a fraction of the lit
## `void` colour. At 480x270 with 16 px tiles the viewport is 30x17 tiles and a floor-1 room
## averages about 11x12 (docs §3.3), so a third of the frame is surround on many floors; flat
## and untextured it reads as an unfinished level rather than as a dungeon. This is the depth
## that stops it - and it only ever darkens, so a room's measured contrast against
## `void_color()` stays a lower bound.
@export var surround_depth_drop: float = 0.38
## How far from the nearest built tile, in tiles, the surround reaches full depth. Roughly the
## width of a small room, so a neighbouring room is still haloed and the gaps between wings of
## the floor go properly dark.
@export var surround_falloff_tiles: float = 7.0
## Speckle amplitude on the surround and the size of one speckle cell in world pixels. Small:
## this is a surface, not an effect, and the tiles are 16 px.
@export var surround_grain: float = 0.09
@export var surround_grain_px: float = 4.0


## The project's light resource, or null when it has not been authored.
## ResourceLoader caches it, so callers may resolve it per use.
static func load_default() -> DungeonLight:
	if not ResourceLoader.exists(PATH):
		return null
	return load(PATH) as DungeonLight


## `profile` when given, else the shipped resource, else a fresh one with the same defaults.
static func resolve(profile: DungeonLight = null) -> DungeonLight:
	if profile != null:
		return profile
	var shipped := load_default()
	return shipped if shipped != null else DungeonLight.new()


## `role_color` turned into something that can light a room: same hue, chroma scaled by
## `light_saturation`, value raised to `light_value`.
func light_color(role_color: Color) -> Color:
	var s := clampf(role_color.s * light_saturation, 0.0, 1.0)
	return Color.from_hsv(role_color.h, s, clampf(light_value, 0.0, 1.0), 1.0)


## The palette role a torch burns in: `heat` turned `torch_accent_mix` of the way toward
## `accent`, keeping `heat`'s own chroma and value. This is the colour before `light_color`.
func torch_role_color(palette: ThemePalette) -> Color:
	var heat := palette.get_color(&"heat")
	var accent := palette.get_color(&"accent")
	if accent.s < torch_accent_min_saturation or torch_accent_mix <= 0.0:
		return heat
	var hue := ThemePalette.rotate_hue(heat.h, accent.h, torch_accent_mix)
	return Color.from_hsv(hue, heat.s, heat.v, heat.a)


## --- The live light contract (docs §10.2) -------------------------------------------------
## What the music's mood does to the dungeon's light *this frame*, as the numbers a light
## system drives a `PointLight2D` or `CanvasModulate` with. Every one reads
## `Music.mood_state()`, which is already crossfaded over `MusicMoodLevers.crossfade_seconds`
## and is exactly neutral when the lights are off, the amount slider is at zero, or nothing is
## playing - so a caller gets a smooth, bounded number and never reaches into the music module.
## `FloorRoot` lights its torches from these; `LightRig` drives its lanterns, its emitters and
## the player's own pool from the same four.
##
## There used to be six. `ambient_color()` and `ambient_energy()` were the two the music moved
## the *room* with rather than the lights in it, and the owner's ruling deleted them outright:
## a mood may change what a flame looks like, how hard it burns, how far it reaches and how it
## wanders, and it may not reach a pixel by any other road.


## The colour a torch burns in on `palette` under the current mood: the theme's fire turned
## toward its accent (`torch_role_color`), made a light (`light_color`), then tinted and pulled
## the way the surfaces under it are - at full value, so it is still a light.
func torch_color(palette: ThemePalette) -> Color:
	return Music.mood_state().light_color(light_color(torch_role_color(palette)))


## Multiplier on a torch's authored energy under the current mood (1.0 when neutral):
## `MusicMoodLevers.torch_calm` .. `torch_loud`, capped at 1 on a light theme.
func torch_energy_scale() -> float:
	return Music.mood_state().torch


## Multiplier on a torch light's *radius* under the current mood (1.0 when neutral):
## `MusicMoodLevers.torch_radius_calm` .. `torch_radius_loud`. Multiply `torch_texture_scale`
## (or `LightingProfile.lantern_texture_scale`) by it. A pool that draws in under a brooding
## track and opens out under a fierce one is the mood changing the *shape* of a room lit in
## pockets, which is what a player notices without being told where to look; it arrives
## already crossfaded over seconds, like every other lever on this contract.
func torch_radius_scale() -> float:
	return Music.mood_state().radius


## How far the flicker may swing a torch's energy right now, as a fraction of it: the tuned
## `torch_flicker` scaled by the mood (`MusicMoodLevers.flicker_calm` .. `flicker_loud`) and
## damped by the accessibility policy - a tenth under reduced flash, nothing under reduce
## motion. Drive it with slow noise, never a sine (`FloorRoot._process`).
func torch_flicker_amplitude() -> float:
	return Accessibility.flash(torch_flicker * Music.mood_state().flicker)


## The radial gradient a point light is drawn with. One texture is shared by every light on a
## floor; it carries no colour of its own, so the light's own colour is what tints it.
static func make_texture(size: int) -> Texture2D:
	var tex := GradientTexture2D.new()
	tex.width = maxi(size, 8)
	tex.height = tex.width
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1, 1, 1, 0))
	for i in range(1, FALLOFF_STOPS - 1):
		var t := float(i) / float(FALLOFF_STOPS - 1)
		gradient.add_point(t, Color(1, 1, 1, pow(1.0 - t, FALLOFF_POWER)))
	tex.gradient = gradient
	return tex
