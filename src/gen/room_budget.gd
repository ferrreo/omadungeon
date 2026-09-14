## Which room types a floor may hold (docs 5.1 #4, the per-floor curation table). Not every
## type turns up on every floor: the first floor has no elite and no trap gauntlet, a floor
## holds an altar *or* a shrine and never both, the shop is guaranteed only on the middle floor
## of each act and rolled elsewhere, and treasure rooms come and go. `FloorGraph` rolls the
## mix from here, `SimFloorPlan` (the balance simulation) rolls the same mix the same way, and
## `FloorValidator` checks a finished floor against the caps and guarantees.
class_name RoomBudget
extends RefCounted

## Per floor (0-based): chance the blessing room is an ALTAR (else a SHRINE), chance of a SHOP
## (1.0 = guaranteed), and the chance of each optional room when a slot is free for it. A
## chance of 0 means "never on this floor", and the validator enforces that as a cap.
const TABLE: Array[Dictionary] = [
	{"altar": 1.00, "shop": 0.00, "elite": 0.00, "trap": 0.00, "treasure": 0.40},
	{"altar": 0.60, "shop": 1.00, "elite": 0.50, "trap": 0.40, "treasure": 0.60},
	{"altar": 0.50, "shop": 0.35, "elite": 0.40, "trap": 0.50, "treasure": 0.25},
	{"altar": 0.50, "shop": 0.45, "elite": 0.60, "trap": 0.50, "treasure": 0.50},
	{"altar": 0.50, "shop": 1.00, "elite": 0.60, "trap": 0.60, "treasure": 0.60},
	{"altar": 0.50, "shop": 0.35, "elite": 0.40, "trap": 0.60, "treasure": 0.30},
	{"altar": 0.50, "shop": 0.50, "elite": 0.60, "trap": 0.50, "treasure": 0.50},
	{"altar": 0.50, "shop": 1.00, "elite": 0.90, "trap": 0.80, "treasure": 0.50},
	{"altar": 0.40, "shop": 0.30, "elite": 0.50, "trap": 0.70, "treasure": 0.30},
]
## Optional types in the order their chances are keyed.
const OPTIONAL_KEYS := {
	FloorData.RoomType.ELITE: "elite",
	FloorData.RoomType.TRAP: "trap",
	FloorData.RoomType.TREASURE: "treasure",
}


## The table row for `floor_index` (clamped to the last row past the end).
static func for_floor(floor_index: int) -> Dictionary:
	return TABLE[clampi(floor_index, 0, TABLE.size() - 1)]


## True when the floor always holds a shop.
static func shop_guaranteed(floor_index: int) -> bool:
	return float(for_floor(floor_index)["shop"]) >= 1.0


## Most rooms of `type` a floor may hold: 1 for an optional type with a non-zero chance,
## 0 for one this floor never rolls.
static func max_count(floor_index: int, type: FloorData.RoomType) -> int:
	if type == FloorData.RoomType.SHOP:
		return 1 if float(for_floor(floor_index)["shop"]) > 0.0 else 0
	if OPTIONAL_KEYS.has(type):
		return 1 if float(for_floor(floor_index)[OPTIONAL_KEYS[type]]) > 0.0 else 0
	return 0


## Rolls the types of the `ordinary` non-structural rooms of a floor (everything but START
## and STAIRS/BOSS): the blessing room first, then the shop if rolled, then the optional
## rooms that fit past the combat quota, then COMBAT for the rest. The order is the order the
## graph hands rooms out in (dead ends first), so services and treasure land in dead ends.
## Deterministic in `rng`, and it always spends the same draws whatever the floor.
static func roll(floor_index: int, ordinary: int, rng: RandomNumberGenerator) -> Array[int]:
	var row := for_floor(floor_index)
	var out: Array[int] = []
	var blessing := (
		FloorData.RoomType.ALTAR if rng.randf() < float(row["altar"]) else FloorData.RoomType.SHRINE
	)
	var shop := rng.randf() < float(row["shop"])
	if ordinary >= 1:
		out.append(blessing)
	if ordinary >= 2 and shop:
		out.append(FloorData.RoomType.SHOP)
	var free_pool := maxi(0, ordinary - out.size())
	var slots := maxi(0, free_pool - FloorGraph.combat_quota(free_pool))
	var optionals: Array[int] = []
	for type: int in OPTIONAL_KEYS:
		optionals.append(type)
	GenUtil.shuffle_ints(optionals, rng)
	var chosen: Array[int] = []
	for type: int in optionals:
		var wanted := rng.randf() < float(row[OPTIONAL_KEYS[type]])
		if wanted and chosen.size() < slots:
			chosen.append(type)
	out.append_array(chosen)
	while out.size() < ordinary:
		out.append(FloorData.RoomType.COMBAT)
	return out
