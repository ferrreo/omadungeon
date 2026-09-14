## Bounds a *restored* drop has to satisfy (docs §12: "quitting is always resumable" — but a
## save is a file on disk, not a promise).
##
## `PickupSpawner.from_dict()` rebuilds a `PickupBase` out of whatever `run.json` holds. Until
## these bounds existed it validated the kind and clamped `amount` to `>= 1`, which is no bound
## at all: a hand-edited or half-written file resumed into a live, collectable stat orb worth
## `999` primary stat points (`StatOrbPickup._collect` passes `amount` straight to
## `player.add_stat`), and a coin planted at `x: 1e30` that sat in the tree and was written
## back out on every autosave from then on.
##
## Two different kinds of bound live here and they are not the same claim:
##
## 1. `stat_orb` is pinned to 1 because that is what the class *means* — `set_stat_index()`
##    chooses the stat and never the magnitude, so every orb the game can drop is worth one
##    point. That is an invariant, not a tunable, and the shipped value should stay 1.
## 2. The gold and heart ceilings are corruption guards, set well above anything the content
##    can roll (the richest enemy in `data/enemies` is a boss at `gold_max = 400`, ×1.8 on
##    floor 9, before `gold_find`), so an honest save is never quietly shaved. They are not an
##    anti-cheat: a player editing their own single-player save is their own business, and a
##    number *inside* these bounds restores exactly as written.
##
## `res://data/pickups/pickup_limits.tres` holds the shipped values. A missing file is not an
## error: `resolve()` hands back a fresh resource carrying the same defaults, so a test that
## never touches `data/` validates drops the same way the game does.
class_name PickupLimits
extends Resource

const PATH := "res://data/pickups/pickup_limits.tres"

## Kind -> the largest `amount` a restored drop of that kind may carry. A kind with no row
## falls back to the amount the freshly built node came with, so adding a pickup type without
## adding a row here restores its own default rather than whatever the file says.
@export var max_amount: Dictionary = {
	"gold": 5000,
	"heart": 200,
	"stat_orb": 1,
}
## How far outside the floor's camera limits a restored drop may lie, in pixels. A drop is
## always dropped on a walkable tile and pops a few dozen px at most, so this only has to
## absorb that pop. Only applied when the caller knows the floor rect.
@export var bounds_margin_px: float = 64.0
## Largest world coordinate, in pixels, a restored drop may name when the caller does *not*
## know the floor rect. A floor grid is a few hundred tiles across at the very most
## (`FloorGenerator` sizes it from the room layout), so 20 000 px is over a thousand tiles and
## cannot reject an honest drop; what it does reject is the `1e30` a corrupt file names, which
## is finite and therefore survives an `is_finite` check while being nowhere at all.
@export var max_abs_position_px: float = 20000.0


## The shipped limits, or null when the resource has not been authored.
## ResourceLoader caches it, so callers may resolve it per use.
static func load_default() -> PickupLimits:
	if not ResourceLoader.exists(PATH):
		return null
	return load(PATH) as PickupLimits


## `limits` when given, else the shipped resource, else a fresh one with the same defaults.
static func resolve(limits: PickupLimits = null) -> PickupLimits:
	if limits != null:
		return limits
	var shipped := load_default()
	return shipped if shipped != null else PickupLimits.new()


## `value` brought inside this kind's bounds. `fallback` is the amount the node was built
## with, used both as the floor's replacement for a kind with no row and as the answer for a
## kind pinned to a single legal value.
func clamp_amount(kind: StringName, value: int, fallback: int) -> int:
	if not max_amount.has(String(kind)):
		return maxi(1, fallback)
	return clampi(value, 1, maxi(1, int(max_amount[String(kind)])))


## True when `pos` is a place a drop could actually have been lying. `bounds` is the floor's
## camera limits (`FloorRoot.camera_limits()`); an empty rect means the caller does not know
## the floor, and then the coarse `max_abs_position_px` bound is the only one that applies.
## A non-finite coordinate is never restorable, whatever floor it claims to be on.
func accepts_position(pos: Vector2, bounds: Rect2 = Rect2()) -> bool:
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return false
	if absf(pos.x) > max_abs_position_px or absf(pos.y) > max_abs_position_px:
		return false
	if bounds.size == Vector2.ZERO:
		return true
	return bounds.grow(bounds_margin_px).has_point(pos)
