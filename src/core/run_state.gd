## Serializable snapshot of a run in progress (docs §12). Pure data with a versioned
## `to_dict`/`from_dict` pair; `SaveManager` owns the file I/O. Mid-fight state is never
## stored: resume puts the player at the door of `current_room_id` with enemies reset.
##
## The canonical seed field is `run_seed` (matches RunRng/GameState); `seed` is an alias.
## The player block can be handled as one dictionary via the `player` property
## (`player_dict()` / `set_player_dict()`), or field by field (`gold`, `stats`, ...).
## The floor block (`floor_state_dict()` / `set_floor_state_dict()`) carries everything the
## player spent or opened on the floor they are standing on, because a resume rebuilds that
## floor from the seed and would otherwise hand every altar, shrine, shop and chest back
## fresh while the cleared rooms stay cleared. It also carries what the player has *earned*
## and not picked up: `floor_pickups` (dropped items) and `floor_drops` (gold, hearts, stat
## orbs), which exist as loose nodes and nowhere else, and what the player has already been
## *paid* for and must not be paid for twice: `broken_prop_tiles`, `revealed_mimic_tiles` and
## `defeated_spawns` (docs §12, "resume never pays twice"). It also carries what the player has
## been *offered* and has not answered — `chest_offer_room_id` and `offer_boards` — so an
## interrupted offer comes back as the cards it was interrupted on rather than a fresh deal.
class_name RunState
extends RefCounted

## Bump when the on-disk shape changes and add a step to `_migrate_step`.
const VERSION := 2

var version: int = VERSION
var run_seed: int = 0
## Alias of `run_seed` for callers written against the spec name.
var seed: int:
	get:
		return run_seed
	set(value):
		run_seed = value
var class_id: StringName = &"fighter"
var floor_index: int = 0
var current_room_id: int = 0
var cleared_room_ids: Array[int] = []
## True while the mandatory floor-1 starting-passive pick is still open. The first autosave
## of a run is written before the player has chosen, so without this a window closed on the
## picker would resume into a run that silently skipped its own opening choice.
var starting_passive_pending: bool = false

# --- player -------------------------------------------------------------------------
var hp_fraction: float = 1.0
var gold: int = 0
var potion: int = 0
## Potion capacity. 0 means "not recorded" (a pre-v2 save): the class default then stands,
## and `player_dict()` leaves the key out rather than clamping the player down to it.
var max_potions: int = 0
## `Stats.to_dict()` output.
var stats: Dictionary = {}
## slot name -> `ItemInstance.to_dict()`.
var equipment: Dictionary = {}
## Opaque ability slot data owned by the abilities module (e.g. {"actives": [...], "passives": [...]}).
var abilities: Dictionary = {}
## Free-form flags (e.g. altar used, shop visited, oligarch contract active).
var flags: Dictionary = {}
var shield: float = 0.0
## The whole player block as one dictionary (same shape as `to_dict()["player"]`).
## READ-ONLY SNAPSHOT: the getter returns a fresh deep copy, so `state.player["gold"] = 5`
## writes into a temporary and is lost. Assign a whole dictionary (`state.player = d`) to
## write, or use the individual fields (`state.gold = 5`).
var player: Dictionary:
	get = player_dict,
	set = set_player_dict

# --- floor state --------------------------------------------------------------------
## Rooms the player has walked into (the minimap draws them; docs §6).
var visited_room_ids: Array[int] = []
## Rooms that hold (or are about to hold) a reward chest. Recorded per room rather than
## derived from "the room is cleared": a lockable room the generator gave no enemies clears
## without a reward, and a resume must not invent one for it.
var chest_room_ids: Array[int] = []
## Rooms whose reward chest has already been opened (a subset of `chest_room_ids`, Treasure
## rooms included). One that is not in this list comes back closed and still worth opening.
var looted_room_ids: Array[int] = []
## Rooms whose Altar / Shrine the player already spent. Without these a save-and-continue
## loop hands out unlimited abilities and stat buffs.
var used_altar_room_ids: Array[int] = []
var used_shrine_room_ids: Array[int] = []
## One entry per shop counter on the floor:
## {"room_id": int, "offers": Array[Dictionary] (ItemInstance.to_dict()), "prices": Array[int],
## "rerolls": int}. Restored instead of restocking, so bought items stay bought and a paid
## reroll is not refunded by quitting.
var shops: Array[Dictionary] = []
## True once the floor exit is open. On a boss floor the stairs are built sealed and only a
## live boss death opens them, so a run saved after the boss died would resume unwinnable.
var stairs_unlocked: bool = false
## Items lying on the floor, uncollected: one entry per `ItemPickup`,
## {"room_id": int, "x": float, "y": float, "item": `ItemInstance.to_dict()`}.
## An elite's guaranteed Rare-or-better drop and anything a swap displaced live *only* as nodes
## under a RoomNode, and a resume rebuilds the floor from the seed with the room still cleared,
## so without this list Save & Quit silently destroyed the best item of the run. Empty means
## "the floor had nothing on it" - which is also how a save written before this field existed
## resumes, and that is the honest answer for one.
var floor_pickups: Array[Dictionary] = []
## The homing drops lying on the floor, uncollected: one entry per `PickupBase`,
## `{"kind": String, "amount": int, "x": float, "y": float}` plus whatever that kind adds (a
## stat orb carries its `stat`). Separate from `floor_pickups` because they are separate nodes
## in separate places - an item is parented to its RoomNode, a coin to the `PickupSpawner` -
## and the sweep that finds one finds none of the other. Without this list Save & Quit
## destroyed the stat orb every elite is guaranteed to drop, all loose gold and every heart.
## Empty means "nothing homing was lying on the floor", which is also how a save written
## before this field existed resumes.
var floor_drops: Array[Dictionary] = []
## Tiles whose breakable prop the player already smashed. `Prop` rolls its gold from a stream
## derived from (run seed, tile, floor index), so it is the *same* coins every time that tile
## is rebuilt: without this list Save & Quit -> Continue -> re-smash is an exactly repeatable
## gold source. Empty means "nothing on this floor is broken yet", which is also how a save
## written before this field existed resumes.
var broken_prop_tiles: Array[Vector2i] = []
## Tiles whose mimic chest the player already sprang. The decoy frees itself when it turns
## into an enemy, so a rebuilt floor hands it back armed and the enemy it becomes pays its
## gold, heart and elite drop again on every cycle.
var revealed_mimic_tiles: Array[Vector2i] = []
## One entry per room the player fought in and did not finish:
## {"room_id": int, "enemy_ids": Array[String]} (`EnemyDef.id` per enemy already killed there).
## Docs §12 resets mid-fight state, so the pack comes back - but the enemies already killed had
## already paid their gold, hearts and elite drops, so a resumed pack drops one enemy per
## recorded id rather than paying for the same kills twice. See `PackLedger`.
var defeated_spawns: Array[Dictionary] = []
## Room whose reward chest has an offer on screen that the player has not answered yet, or -1.
## A chest opens its lid the instant the player interacts, but the prize is not granted until
## the picker is answered - and the autosave the room clear queued lands while the picker is
## up, because the tree is paused and SaveManager is not. Recording that chest as looted is
## what used to destroy the reward when the session ended abnormally, so instead the resume
## re-opens the picker, exactly as `starting_passive_pending` does for the opening pick.
var chest_offer_room_id: int = -1
## Every offer board rolled on this floor and not answered yet, one entry per interactable that
## owes the player a pick:
## {"source": int (`RunManager.OfferSource`), "room_id": int (-1 for the opening passive pick,
## which belongs to the run rather than to a room), "kind": int (`Chest.Kind`), "offers":
## Array[Dictionary] (one card each, see `FloorRestore.offers_to_dicts()`), "curse": String (the
## Curse id a CURSED board attaches to its prize, "" for none), "rerolled": bool}.
##
## `chest_offer_room_id` records that a pick is owed; this records *which cards* it is owed on.
## A resume used to roll the board again, against a loot stream already advanced past it, so
## leaving an altar - or closing the window on a picker - and continuing dealt a brand-new hand,
## free and without limit, while the Reroll button charges 25g for exactly that. A board that
## has been rolled belongs to its interactable until it is answered.
var offer_boards: Array[Dictionary] = []
## Offer rerolls already paid for on this floor (the price grows with each one) and whether
## the class "one free reroll per floor" perk was used.
var rerolls_this_floor: int = 0
var free_reroll_used: bool = false
## The whole floor block as one dictionary (same shape as `to_dict()["floor_state"]`).
## READ-ONLY SNAPSHOT, like `player`: assign a whole dictionary to write.
var floor_state: Dictionary:
	get = floor_state_dict,
	set = set_floor_state_dict

# --- run statistics ------------------------------------------------------------------
var kills: int = 0
var damage_taken: int = 0
var gold_earned: int = 0
var time_played: float = 0.0
var tracks_played: Array[String] = []
var theme_name: String = ""
## Positions of the run-long RNG streams (stream name -> `RandomNumberGenerator.state`), so a
## resumed run continues drawing where the save left off instead of rewinding to the seed.
## Written and restored by `RunManager` (`PERSISTENT_RNG_STREAMS`); without it, repeated
## Save & Quit would reroll the next chest for free. Per-floor streams are derived from
## (seed, floor index) and are not listed here. Empty means "unknown": start from the seed.
var rng_states: Dictionary = {}
## Floor-generation inputs captured when the run was saved (`GenParams` fields that come from
## the live ThemeProfile: corridor_wiggle, room_size_bias, trap_density, prop_density, biome,
## extra_loops, enemy_count_scale, music_energy, theme_hash). Layout is *not* a pure function
## of (seed, floor_index): it also depends on the desktop theme and the music energy at
## generation time. Resuming must rebuild GenParams from these values instead of from the
## current `Desktop.profile`, otherwise switching theme between sessions (docs §12 allows it)
## regenerates a different graph and `cleared_room_ids` / `current_room_id` point at nothing.
## Empty means "unknown": fall back to the live profile.
var gen_params: Dictionary = {}


## Serializes to a JSON-safe dictionary. Large ints (seed, rng states) go out as strings
## because JSON numbers are doubles and would lose precision above 2^53.
func to_dict() -> Dictionary:
	var rooms: Array = []
	for id: int in cleared_room_ids:
		rooms.append(id)
	var rng_out: Dictionary = {}
	for key: Variant in rng_states.keys():
		rng_out[String(key)] = str(int(rng_states[key]))
	return {
		"version": VERSION,
		"seed": str(run_seed),
		"class_id": String(class_id),
		"floor_index": floor_index,
		"current_room_id": current_room_id,
		"cleared_room_ids": rooms,
		"starting_passive_pending": starting_passive_pending,
		"player": player_dict(),
		"floor_state": floor_state_dict(),
		"run_stats":
		{
			"kills": kills,
			"damage_taken": damage_taken,
			"gold_earned": gold_earned,
			"time_played": time_played,
			"tracks_played": Array(tracks_played),
			"theme_name": theme_name,
		},
		"rng_states": rng_out,
		"gen_params": gen_params.duplicate(true),
	}


## The player block as a deep-copied, JSON-safe dictionary. Every key `Player.to_dict()`
## writes has to appear here: `Player.restore_from_dict` reads this dictionary, not the
## player's own snapshot, so a key RunState does not know about is silently dropped on every
## resume (that is how potion capacity used to be lost). `max_potions` is the one omission,
## and only when it is unknown (0, a pre-v2 save) — writing 0 would clamp the player to a
## single potion instead of leaving the class default alone.
func player_dict() -> Dictionary:
	var out := {
		"hp_fraction": hp_fraction,
		"gold": gold,
		"potion": potion,
		"stats": stats.duplicate(true),
		"equipment": equipment.duplicate(true),
		"abilities": abilities.duplicate(true),
		"flags": flags.duplicate(true),
		"shield": shield,
	}
	if max_potions > 0:
		out["max_potions"] = max_potions
	return out


## Fills the player fields from a dictionary shaped like `player_dict()` (missing keys keep
## defaults, numbers are coerced from JSON floats).
func set_player_dict(data: Dictionary) -> void:
	hp_fraction = clampf(float(data.get("hp_fraction", 1.0)), 0.0, 1.0)
	gold = _to_int(data.get("gold", 0))
	potion = _to_int(data.get("potion", 0))
	stats = _dict(data.get("stats", {}))
	equipment = _dict(data.get("equipment", {}))
	abilities = _dict(data.get("abilities", {}))
	flags = _dict(data.get("flags", {}))
	shield = float(data.get("shield", 0.0))
	max_potions = maxi(0, _to_int(data.get("max_potions", 0)))


## The floor block as a deep-copied, JSON-safe dictionary.
func floor_state_dict() -> Dictionary:
	return {
		"visited_room_ids": _plain(visited_room_ids),
		"chest_room_ids": _plain(chest_room_ids),
		"looted_room_ids": _plain(looted_room_ids),
		"used_altar_room_ids": _plain(used_altar_room_ids),
		"used_shrine_room_ids": _plain(used_shrine_room_ids),
		"shops": shops.duplicate(true),
		"floor_pickups": floor_pickups.duplicate(true),
		"floor_drops": floor_drops.duplicate(true),
		"broken_prop_tiles": _flat(broken_prop_tiles),
		"revealed_mimic_tiles": _flat(revealed_mimic_tiles),
		"defeated_spawns": defeated_spawns.duplicate(true),
		"chest_offer_room_id": chest_offer_room_id,
		"offer_boards": offer_boards.duplicate(true),
		"stairs_unlocked": stairs_unlocked,
		"rerolls_this_floor": rerolls_this_floor,
		"free_reroll_used": free_reroll_used,
	}


## Fills the floor fields from a dictionary shaped like `floor_state_dict()`. Missing keys
## keep their defaults, so a save written before this block existed resumes as "nothing on
## this floor was spent yet" instead of failing to load.
func set_floor_state_dict(data: Dictionary) -> void:
	visited_room_ids = _ints(data.get("visited_room_ids", []))
	chest_room_ids = _ints(data.get("chest_room_ids", []))
	looted_room_ids = _ints(data.get("looted_room_ids", []))
	used_altar_room_ids = _ints(data.get("used_altar_room_ids", []))
	used_shrine_room_ids = _ints(data.get("used_shrine_room_ids", []))
	shops = _dict_entries(data.get("shops", []))
	floor_pickups = _dict_entries(data.get("floor_pickups", []))
	floor_drops = _dict_entries(data.get("floor_drops", []))
	broken_prop_tiles = _tiles(data.get("broken_prop_tiles", []))
	revealed_mimic_tiles = _tiles(data.get("revealed_mimic_tiles", []))
	defeated_spawns = _dict_entries(data.get("defeated_spawns", []))
	chest_offer_room_id = _to_int(data.get("chest_offer_room_id", -1))
	offer_boards = _dict_entries(data.get("offer_boards", []))
	stairs_unlocked = bool(data.get("stairs_unlocked", false))
	rerolls_this_floor = maxi(0, _to_int(data.get("rerolls_this_floor", 0)))
	free_reroll_used = bool(data.get("free_reroll_used", false))


## The saved stock of the shop in `room_id`, or an empty dictionary when that shop was never
## recorded (a fresh floor, or a save written before shops were persisted).
func shop_for_room(room_id: int) -> Dictionary:
	for entry: Dictionary in shops:
		if _to_int(entry.get("room_id", -1)) == room_id:
			return entry
	return {}


## The unanswered board `source` (a `RunManager.OfferSource` value) rolled in `room_id`, or an
## empty dictionary when the save holds none for it: a floor entered for the first time, a board
## already answered, or a save written before boards were persisted. The caller rolls a fresh
## board then, which is the honest answer for one nobody was looking at.
func offer_board_for(source: int, room_id: int) -> Dictionary:
	for entry: Dictionary in offer_boards:
		if _to_int(entry.get("source", -1)) != source:
			continue
		if _to_int(entry.get("room_id", -1)) == room_id:
			return entry
	return {}


## Builds a RunState from a (possibly older) dictionary. Returns null when the data is
## not a recognizable run, so callers can treat it as "no run".
static func from_dict(raw: Dictionary) -> RunState:
	var data := migrate(raw)
	if not is_valid(data):
		return null
	var state := RunState.new()
	state.version = VERSION
	state.run_seed = _to_int(data["seed"])
	state.class_id = StringName(str(data.get("class_id", "fighter")))
	state.floor_index = _to_int(data.get("floor_index", 0))
	state.current_room_id = _to_int(data.get("current_room_id", 0))
	state.cleared_room_ids = []
	for id: Variant in data.get("cleared_room_ids", []) as Array:
		state.cleared_room_ids.append(_to_int(id))
	state.starting_passive_pending = bool(data.get("starting_passive_pending", false))
	state.set_player_dict(_dict(data.get("player", {})))
	state.set_floor_state_dict(_dict(data.get("floor_state", {})))
	var run_stats := _dict(data.get("run_stats", {}))
	state.kills = _to_int(run_stats.get("kills", 0))
	state.damage_taken = _to_int(run_stats.get("damage_taken", 0))
	state.gold_earned = _to_int(run_stats.get("gold_earned", 0))
	state.time_played = float(run_stats.get("time_played", 0.0))
	state.tracks_played = _strings(run_stats.get("tracks_played", []))
	state.theme_name = str(run_stats.get("theme_name", ""))
	state.rng_states = {}
	for key: Variant in _dict(data.get("rng_states", {})).keys():
		state.rng_states[StringName(str(key))] = _to_int(data["rng_states"][key])
	state.gen_params = _dict(data.get("gen_params", {}))
	return state


## True when `data` (already migrated) has the minimum shape required to resume.
static func is_valid(data: Dictionary) -> bool:
	if _to_int(data.get("version", -1)) != VERSION:
		return false
	if not data.has("seed"):
		return false
	var seed_value: Variant = data["seed"]
	if not (seed_value is String or seed_value is int or seed_value is float):
		return false
	if seed_value is String and not (seed_value as String).is_valid_int():
		return false
	if not (data.get("player", {}) is Dictionary):
		return false
	if not (data.get("cleared_room_ids", []) is Array):
		return false
	return _to_int(data.get("floor_index", 0)) >= 0


## Migration hook: upgrades `raw` one version at a time until it reaches VERSION.
## A missing `version` key means 0 (the pre-release flat layout). Unknown future
## versions are returned untouched (and then rejected by `is_valid`).
static func migrate(raw: Dictionary) -> Dictionary:
	var data := raw.duplicate(true)
	var v := _to_int(data.get("version", 0))
	if v == 0 and not data.has("seed"):
		return data  # not a v0 run either; leave it for is_valid() to reject
	while v < VERSION:
		data = _migrate_step(v, data)
		v += 1
		data["version"] = v
	return data


static func _migrate_step(from_version: int, data: Dictionary) -> Dictionary:
	match from_version:
		0:
			return _migrate_0_to_1(data)
		1:
			return _migrate_1_to_2(data)
	return data


## v0 was a flat dictionary: {seed, class, floor, room, cleared, hp, gold, potion, stats,
## equipment, abilities, flags, kills, damage_taken, gold_earned, time_played, theme}.
static func _migrate_0_to_1(old: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	out["seed"] = str(_to_int(old.get("seed", 0)))
	out["class_id"] = str(old.get("class", old.get("class_id", "fighter")))
	out["floor_index"] = _to_int(old.get("floor", old.get("floor_index", 0)))
	out["current_room_id"] = _to_int(old.get("room", old.get("current_room_id", 0)))
	var cleared: Variant = old.get("cleared", old.get("cleared_room_ids", []))
	out["cleared_room_ids"] = cleared if cleared is Array else []
	var nested := _dict(old.get("player", {}))
	out["player"] = {
		"hp_fraction": float(old.get("hp", nested.get("hp_fraction", 1.0))),
		"gold": _to_int(old.get("gold", nested.get("gold", 0))),
		"potion": _to_int(old.get("potion", nested.get("potion", 0))),
		"stats": _dict(old.get("stats", nested.get("stats", {}))),
		"equipment": _dict(old.get("equipment", nested.get("equipment", {}))),
		"abilities": _dict(old.get("abilities", nested.get("abilities", {}))),
		"flags": _dict(old.get("flags", nested.get("flags", {}))),
		"shield": float(old.get("shield", nested.get("shield", 0.0))),
	}
	out["run_stats"] = {
		"kills": _to_int(old.get("kills", 0)),
		"damage_taken": _to_int(old.get("damage_taken", 0)),
		"gold_earned": _to_int(old.get("gold_earned", 0)),
		"time_played": float(old.get("time_played", 0.0)),
		"tracks_played": old.get("tracks_played", []),
		"theme_name": str(old.get("theme", old.get("theme_name", ""))),
	}
	out["rng_states"] = _dict(old.get("rng_states", {}))
	out["gen_params"] = _dict(old.get("gen_params", {}))
	return out


## v1 knew nothing about the floor the player was standing on, and nothing about potion
## capacity. Both blocks are additive: the defaults say "nothing spent yet / capacity
## unknown", which is exactly how a v1 run has to resume.
static func _migrate_1_to_2(old: Dictionary) -> Dictionary:
	var out := old.duplicate(true)
	if not (out.get("floor_state", null) is Dictionary):
		out["floor_state"] = {}
	return out


static func _to_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return 0


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


## A fresh, untyped copy of an int list. `Array(typed)` shares its storage, so handing that
## out would let a caller edit the state through the dictionary `to_dict()` returned.
static func _plain(list: Array[int]) -> Array:
	var out: Array = []
	for id: int in list:
		out.append(id)
	return out


## Coerces a JSON array into typed ints (JSON numbers come back as floats).
static func _ints(value: Variant) -> Array[int]:
	var out: Array[int] = []
	if value is Array:
		for item: Variant in value as Array:
			out.append(_to_int(item))
	return out


## A tile list flattened to plain ints (x, y, x, y, ...). JSON has no Vector2i, and a list of
## {"x": .., "y": ..} dictionaries spends four times the bytes on the same two numbers.
static func _flat(tiles: Array[Vector2i]) -> Array:
	var out: Array = []
	for tile: Vector2i in tiles:
		out.append(tile.x)
		out.append(tile.y)
	return out


## The inverse of `_flat()`. A trailing half-pair is dropped rather than guessed at.
static func _tiles(value: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not (value is Array):
		return out
	var flat := value as Array
	var i := 0
	while i + 1 < flat.size():
		out.append(Vector2i(_to_int(flat[i]), _to_int(flat[i + 1])))
		i += 2
	return out


## Coerces a saved list of dictionaries (shop counters, floor pickups), dropping anything that
## is not one.
static func _dict_entries(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array):
		return out
	for item: Variant in value as Array:
		if item is Dictionary:
			out.append((item as Dictionary).duplicate(true))
	return out


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value as Array:
			out.append(str(item))
	return out
