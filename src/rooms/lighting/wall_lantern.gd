## One wall lantern: the sprite the biome hangs on a generator anchor (`FloorData.lantern_anchors`)
## and the `PointLight2D` that hangs with it. The sprite is drawn on the wall tile in the room's
## flame material, lit by nothing (`FloorRoot.TORCH_SPRITE_LIGHT_MASK`: a lantern is a light,
## not a surface a light falls on); the light sits `lip` px off the cell centre toward the open
## side, so it is never inside the wall's own occluder core (`WallOccluders`).
##
## One light, on `LightRig.LIT_MASK`: the dark undone on the floor and on everything standing in
## it by exactly the same amount, so at the pool's centre the floor and the crate on it both come
## back to the level the theme authored them at and no further.
##
## It carried two for a round - one for the floor and a weaker one for bodies - because bodies
## stood under a gentler dark than the floor did and the pool that restored one overshot the
## other. Bodies no longer get a gentler dark (`LightingProfile.unlit_floor`: a prop that is 65%
## visible with nothing lighting it is the ambient wash the owner deleted, in a crate's clothes),
## so there is one dark to undo and one light to undo it.
##
## Colour and energy come from `LightRig.relight()`, never from here: a lantern knows its kind
## and which way it faces, and nothing about the theme.
class_name WallLantern
extends Node2D

## Where the sprite hangs.
var tile: Vector2i = Vector2i.ZERO
## Unit direction from the wall into the open ground it lights.
var facing: Vector2 = Vector2.DOWN
## Sprite kind (`LightingProfile.LANTERN_KINDS`).
var kind: StringName = &"torch"
var sprite: Sprite2D
## The pool this lantern casts, on the floor, the walls and every body standing in it
## (`LightRig.LIT_MASK`; may cast a shadow).
var light: PointLight2D


## Builds the sprite and, when `texture` is given, the light. `column` is the atlas column on
## the special row; `tint` the room's flame material.
func setup(
	anchor: Vector2i,
	toward: Vector2,
	lantern_kind: StringName,
	atlas: Texture2D,
	column: int,
	tint: Material,
	texture: Texture2D,
	texture_scale: float,
	lip: float
) -> void:
	tile = anchor
	facing = toward.normalized() if toward.length_squared() > 0.0 else Vector2.DOWN
	kind = lantern_kind
	name = "Lantern_%d_%d" % [anchor.x, anchor.y]
	position = (Vector2(anchor) + Vector2(0.5, 0.5)) * float(Layers.TILE)
	sprite = FloorBuilder.atlas_sprite(atlas, column)
	sprite.name = "Sprite"
	sprite.material = tint
	sprite.light_mask = FloorRoot.TORCH_SPRITE_LIGHT_MASK
	add_child(sprite)
	if texture == null:
		return
	light = PointLight2D.new()
	light.name = "Light"
	light.texture = texture
	light.texture_scale = texture_scale
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.range_item_cull_mask = LightRig.LIT_MASK
	light.shadow_enabled = false
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	light.position = facing * lip
	add_child(light)


## Sets the light's colour, energy and reach (a lantern past the light budget has no light).
## `reach` is a `texture_scale`: the authored radius under the music mood's own radius lever.
func relight(color: Color, energy: float, reach: float = -1.0) -> void:
	if light == null:
		return
	light.color = color
	light.energy = energy
	if reach > 0.0:
		light.texture_scale = reach


## World position of the light (or of the sprite when there is none).
func light_position() -> Vector2:
	return light.global_position if light != null else global_position
