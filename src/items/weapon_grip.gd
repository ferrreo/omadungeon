## How one weapon family is *held*: where the hand closes on its 16x16 atlas cell, which way
## the weapon points inside that cell, and how far the hand sits from the body.
##
## A weapon cell is an inventory icon first — every one of them is drawn diagonally across the
## square with the grip in a corner, because that is what reads best in a slot. Pinning that
## square by its centre, which is what a plain `Sprite2D` does, hangs the weapon half a cell
## away from the character: the sword floated beside the player's head, and rotating the pivot
## to aim swung that whole offset around the body, so turning around put the weapon on the
## wrong side at the wrong angle. Anchoring at `grip` instead makes the rotation happen around
## the hand, which is the only point on a held weapon that does not move.
##
## Angles use the screen convention the rest of the 2D code uses: +X is 0, +Y (down) is +90, so
## a weapon drawn pointing up and to the right has a negative `axis_degrees`.
class_name WeaponGrip
extends Resource

## Family word matched against the weapon id, the same keys `WeaponController.ATLAS_INDEX` uses.
@export var family: StringName = &"sword"
## Pixel inside the 16x16 cell the hand closes on (origin top-left, y down).
@export var grip: Vector2 = Vector2(8.0, 8.0)
## Direction the weapon points inside its cell, in degrees.
@export var axis_degrees: float = 0.0
## Distance from the body centre to the hand, along the aim.
@export var reach: float = 5.0
## Distance from the aim line to the hand, towards the near side of the body. Mirrored with the
## character, so the hand is on the same side of the body whichever way they are turned.
@export var lateral: float = 3.0
## Drawn size relative to the 16 px cell. Weapon icons are authored to fill their square, which
## next to a 16 px character reads as a weapon nearly as tall as its owner.
@export var sprite_scale: float = 1.0


## The grip as a `Sprite2D.offset`: the vector that moves the drawn cell so `grip` lands on the
## node's own origin. `cell` is the cell's pixel size (16 for the shipped weapon atlas).
func sprite_offset(cell: float) -> Vector2:
	return Vector2(cell, cell) * 0.5 - grip


## Rotation that turns the weapon's own axis into "forward is +X", in radians.
func rest_rotation() -> float:
	return -deg_to_rad(axis_degrees)


## Where the hand sits relative to the weapon pivot, in the pivot's frame (+X is the aim).
## `mirror` is -1 while the character is drawn facing left.
func hand_position(mirror: float) -> Vector2:
	return Vector2(reach, lateral * mirror)
