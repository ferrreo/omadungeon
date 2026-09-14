## The grip table: one `WeaponGrip` per weapon family, shipped as `data/items/weapon_grips.tres`
## so the hand position of a sword is data a pass over the art can edit, not a constant buried
## in the weapon controller (docs ARCHITECTURE §1, "content is data").
##
## Lookup is by the longest family word contained in the weapon id, which matters: `longsword`
## and `greatsword` both contain `sword`, and a shortest-first match handed them the rusty
## sword's grip (and, for weapons with no icon of their own, the rusty sword's *cell*).
class_name WeaponGrips
extends Resource

const DEFAULT_PATH := "res://data/items/weapon_grips.tres"
## Family a weapon falls back to when its id matches nothing, indexed by `WeaponBase.Style`.
const STYLE_FAMILY: Array[StringName] = [&"sword", &"spear", &"shortbow", &"wand", &"knives"]

static var _shared: WeaponGrips

## One entry per family word. Order does not matter; the longest match wins.
@export var entries: Array[WeaponGrip] = []
## Used for a weapon that matches neither a family word nor its style's family.
@export var fallback: WeaponGrip


## The shipped table, loaded once. Falls back to code defaults if the resource is missing, so a
## weapon is never drawn pinned by the centre of its icon again.
static func shared() -> WeaponGrips:
	if _shared == null:
		_shared = load(DEFAULT_PATH) as WeaponGrips
	if _shared == null:
		_shared = WeaponGrips.new()
	return _shared


## Test seam: replaces the shared table (pass null to go back to the shipped one).
static func set_shared(table: WeaponGrips) -> void:
	_shared = table


## The grip for a weapon: the longest family word its id contains, else the family its style
## defaults to, else the table's fallback. Never null.
func for_weapon(weapon_id: StringName, style: int) -> WeaponGrip:
	var found := match_family(String(weapon_id))
	if found != null:
		return found
	if style >= 0 and style < STYLE_FAMILY.size():
		found = match_family(String(STYLE_FAMILY[style]))
	if found != null:
		return found
	return fallback if fallback != null else WeaponGrip.new()


## The entry whose family word `text` contains, longest first, or null when none does.
func match_family(text: String) -> WeaponGrip:
	var lowered := text.to_lower()
	var best: WeaponGrip = null
	var best_length := 0
	for entry in entries:
		if entry == null:
			continue
		var key := String(entry.family).to_lower()
		if key.is_empty() or not lowered.contains(key):
			continue
		if key.length() > best_length:
			best_length = key.length()
			best = entry
	return best
