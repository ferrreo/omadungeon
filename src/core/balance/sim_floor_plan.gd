## The room mix of one floor, without running the layout generator.
##
## `FloorGenerator` builds a real grid, which costs far more than the simulation needs — the
## balance question is "how many fights, how many chests, how many services", not "where are
## the walls". The mix is `RoomBudget.roll()` itself - the same table and the same draws
## `FloorGraph._assign_types()` makes - so the simulation cannot disagree with the generator
## about which floors hold a shop, an elite or a treasure room: one start, one stairs (or the
## boss arena on floors 3/6/9), one altar or shrine, a shop where the table says, the optional
## rooms the table and the `FloorGraph.combat_quota()` allow, fights for the rest. Room counts
## come from `GenParams.room_count_for()`.
class_name SimFloorPlan
extends RefCounted

## The floor's rooms as `FloorData.RoomType` values, start room excluded (it is always empty).
var rooms: Array[int] = []
## Enemy spawn points each room has, parallel to `rooms`. This is the real cap on a pack:
## `RunManager._spawn_pack()` drops everything the difficulty budget bought beyond the tiles
## `RoomFiller` laid down, so a deep floor's budget of twelve buys seven enemies, not twelve.
## The count comes from `RoomFiller._spawn_count()` itself rather than from a copy of its
## formula, so the simulation cannot quietly disagree with the generator about pack sizes.
var spawn_slots: Array[int] = []
var floor_index: int = 0
var is_boss_floor: bool = false


## Rolls the room mix of `floor_index`. Deterministic in `rng`.
static func build(floor_index: int, rng: RandomNumberGenerator) -> SimFloorPlan:
	var out := SimFloorPlan.new()
	out.floor_index = floor_index
	out.is_boss_floor = GenParams.is_boss_floor_index(floor_index)
	var count := GenParams.room_count_for(floor_index)
	# Start and the exit (stairs, or the boss arena that holds them) are structural.
	var ordinary := maxi(0, count - 2)
	out.rooms.append_array(RoomBudget.roll(floor_index, ordinary, rng))
	out.rooms.append(FloorData.RoomType.BOSS if out.is_boss_floor else FloorData.RoomType.STAIRS)
	var params := GenParams.new()
	params.floor_index = floor_index
	for room_type: int in out.rooms:
		out.spawn_slots.append(
			RoomFiller._spawn_count(room_type as FloorData.RoomType, params, rng)
		)
	return out


## True for the room types that hold enemies and therefore drop a chest when cleared.
static func is_fight(room_type: int) -> bool:
	return FloorGraph.FIGHT_TYPES.has(room_type) or room_type == FloorData.RoomType.BOSS


## Rooms a floor holds past the start room, whichever way its optional slots roll.
static func room_count(floor_index: int) -> int:
	return maxi(1, GenParams.room_count_for(floor_index) - 1)


## Fight rooms a floor is guaranteed, from the same `FloorGraph.combat_quota()` the layout
## generator uses, over the smallest free pool the floor can have (both service rooms
## present). The economy half of `SimPlayer.power()` needs this to know how much gold a
## floor is about to pay, without rolling a whole plan to find out.
static func fight_count(floor_index: int) -> int:
	var ordinary := maxi(0, GenParams.room_count_for(floor_index) - 2)
	var free_pool := maxi(0, ordinary - 2)
	var exit_fight := 1 if GenParams.is_boss_floor_index(floor_index) else 0
	return maxi(1, FloorGraph.combat_quota(free_pool) + exit_fight)


## Cards a floor puts in front of the player: every room past the start offers something (a
## cleared room's chest, an altar, a shop, a shrine, the treasure room's chest).
static func offer_count(floor_index: int) -> int:
	return room_count(floor_index)
