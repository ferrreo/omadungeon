## One meta-progression unlock (docs §12): what it grants, what the player has to do, and the
## achievement counter that measures it.
##
## Unlocks are content and options only, never raw power - a new class is a different way to
## play, not a stronger one, and the same goes for every ability in the table.
class_name UnlockDef
extends Resource

## What the id names, so the UI can say "class" or "ability" without a lookup table.
enum Kind { CLASS, ABILITY }

## The id granted. Must also appear in `Profile.GATED_UNLOCKS`.
@export var id: StringName = &""
## Short name shown in the toast and on the unlock board.
@export var title: String = ""
## One line telling the player what to do, in the imperative ("Clear a floor.").
@export var description: String = ""
@export var kind: Kind = Kind.ABILITY
## Achievement counter (`SaveManager.increment`) this unlock watches.
@export var counter: StringName = &""
## Value of `counter` that earns it.
@export var threshold: int = 1
## Sort order on the unlock board; low first.
@export var order: int = 0


## "3 / 50", or "50 / 50" once it is done. The number the player chases.
func progress_text(value: int) -> String:
	return "%d / %d" % [mini(maxi(value, 0), threshold), maxi(threshold, 1)]


## How far along, 0..1.
func fraction(value: int) -> float:
	return clampf(float(value) / float(maxi(threshold, 1)), 0.0, 1.0)


func grants_class() -> bool:
	return kind == Kind.CLASS
