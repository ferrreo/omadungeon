## Which way the character is turned, and whether the weapon in their hand passes in front of
## their body or behind it. Split out of `Player` because it is a two-state machine with
## hysteresis on both halves, and hysteresis is the whole point: an aim that sits exactly on a
## boundary must not make the decision flip every frame.
##
## * **Flip.** The character (and with them the weapon) turns to the other side only once the
##   aim is `FLIP_DEADZONE` off the vertical. A stick held near straight up or down crosses
##   x = 0 constantly, and without the deadzone the body and the sword in its hand strobed
##   between the two sides - which is the "especially when changing direction" half of the
##   weapon-anchoring report: not one bad pose, an alternation between two.
## * **Depth.** A weapon held on the far side of a body is behind it, so aiming upscreen draws
##   the whole weapon pivot behind the character. The two thresholds are deliberately apart:
##   with one, an aim resting on it flickers the weapon through the character.
class_name WeaponCarry
extends RefCounted

## How far off the vertical the aim must be before the character turns to the other side.
const FLIP_DEADZONE := 0.15
## Aim `y` at which the weapon passes behind the body, and the one at which it comes back.
const BEHIND_ENTER := -0.45
const BEHIND_EXIT := -0.2

## True while the character is drawn mirrored (facing left).
var flipped: bool = false
## True while the weapon is drawn behind the body (aiming away from the camera).
var behind: bool = false


## Folds a direction into the carry state. Returns true when either half changed, so a caller
## can skip the node work on the frames where nothing moved.
func update(dir: Vector2) -> bool:
	var d := dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	var was_flipped := flipped
	var was_behind := behind
	if absf(d.x) > FLIP_DEADZONE:
		flipped = d.x < 0.0
	behind = d.y < (BEHIND_EXIT if behind else BEHIND_ENTER)
	return flipped != was_flipped or behind != was_behind
