## A one-pixel rim stamped around an `AnimatedSprite2D`'s current frame, drawn behind it,
## **only while that sprite is mid hit-flash**.
##
## The rim exists for one moment: a flash pushes the sprite toward one flat colour, taking the
## sheet's own ink outline with it, and four flashed sprites standing on each other then have
## no edges left between them. Outside that moment the authored art already carries its own
## 1 px rim (a fighter's idle frame is 54 of 153 opaque pixels of ink), and stamping a second
## one over it put every 16 px character inside a 2-3 px black border: at 3x the player read as
## a dark token with a face, and the rim landed on the weapon's swing trail as a ragged cloud.
## So the sheet owns the silhouette and this owns the flash, instead of both owning both.
##
## It is not a shader on the sprite itself on purpose: every character frame is an
## `AtlasTexture` into a shared sheet, and a neighbourhood sample in a fragment shader would
## read the frame next door rather than transparent padding.
class_name SpriteOutline
extends Node2D

const SHADER_PATH := "res://src/ui/silhouette.gdshader"
## The four offsets a one-pixel rim is stamped at. Diagonals add nothing at this scale and
## cost 4 more draws per character per frame.
const OFFSETS: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
## Extra seconds the rim is held past the flash it was raised for, so it does not blink off
## one frame before the sprite's own colours are back.
const FLASH_TAIL := 0.05

## The sprite whose current frame is stamped. Set by whoever owns both nodes.
var source: AnimatedSprite2D
## Rim colour. Retint through `set_tint` so the shader parameter follows.
var tint: Color = Color(0, 0, 0, 0.85):
	set = set_tint

## Seconds of flash left to cover. The rim is drawn only while this is positive.
var _flash_left: float = 0.0
var _material := ShaderMaterial.new()
var _last_frame: int = -1
var _last_anim: StringName = &""
var _last_flip: bool = false
var _last_scale: Vector2 = Vector2.ONE
var _last_alpha: float = 1.0


func _ready() -> void:
	# Not a negative z: the dungeon's tile layers sit at z 0 and are opaque, so a rim below
	# them would never be drawn. It stays at z 0 and is ordered before the sprite among its
	# owner's children instead, which is what puts it behind the body and nothing else.
	z_index = 0
	z_as_relative = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_material.shader = load(SHADER_PATH) as Shader
	_material.set_shader_parameter(&"tint", tint)
	material = _material
	# Nothing has flashed yet, so there is nothing to rim. Hidden from frame zero rather than
	# from the first `_process`, so no character is ever drawn double-outlined for a frame.
	visible = false
	set_process(true)


func set_tint(value: Color) -> void:
	tint = value
	_material.set_shader_parameter(&"tint", value)
	queue_redraw()


## Raises the rim for `seconds` (plus a short tail). Call it wherever a hit flash starts;
## the rim is not drawn at any other time.
func flash_for(seconds: float) -> void:
	_flash_left = maxf(_flash_left, maxf(0.0, seconds) + FLASH_TAIL)
	# The cached frame state is stale after a spell of being hidden: forget it so the refresh
	# below stamps the rim on the frame that is actually up.
	_last_frame = -1
	_refresh()


## True while the rim has a flash to cover.
func is_flashing() -> bool:
	return _flash_left > 0.0


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
	_refresh()


## Follows the source sprite's transform and restamps the rim when anything about the frame it
## is tracking has moved. A no-op while there is no flash to cover.
func _refresh() -> void:
	if source == null or not is_instance_valid(source) or _flash_left <= 0.0:
		visible = false
		return
	visible = source.visible and source.sprite_frames != null
	if not visible:
		return
	position = source.position
	scale = source.scale
	rotation = source.rotation
	var alpha := source.modulate.a * source.self_modulate.a
	if (
		source.frame == _last_frame
		and source.animation == _last_anim
		and source.flip_h == _last_flip
		and scale.is_equal_approx(_last_scale)
		and is_equal_approx(alpha, _last_alpha)
	):
		return
	_last_frame = source.frame
	_last_anim = source.animation
	_last_flip = source.flip_h
	_last_scale = scale
	_last_alpha = alpha
	modulate.a = alpha
	queue_redraw()


func _draw() -> void:
	var texture := current_frame()
	if texture == null:
		return
	var size := texture.get_size()
	var base := source.offset
	if source.centered:
		base -= size * 0.5
	var flip := Vector2(-1.0 if source.flip_h else 1.0, -1.0 if source.flip_v else 1.0)
	for offset: Vector2 in OFFSETS:
		draw_set_transform(offset, 0.0, flip)
		draw_texture(texture, base)


## The frame currently on the source sprite, or null when there is nothing to stamp.
func current_frame() -> Texture2D:
	if source == null or not is_instance_valid(source) or source.sprite_frames == null:
		return null
	var frames := source.sprite_frames
	if not frames.has_animation(source.animation):
		return null
	if source.frame >= frames.get_frame_count(source.animation):
		return null
	return frames.get_frame_texture(source.animation, source.frame)
