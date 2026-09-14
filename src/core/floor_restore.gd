## Save/resume glue for one floor (docs §12: "quitting is always resumable").
##
## A resumed floor comes back out of the generator untouched, so everything the player did to
## it has to be recorded and replayed by hand: cleared rooms, looted chests, spent altars and
## shrines, a shop's remaining stock, the rooms already walked and, above all, the stairs —
## on a boss floor they are built sealed and opened only by a live boss death, so a run saved
## after the boss died used to resume permanently unwinnable.
##
## `capture()` reads the live nodes rather than an event log, so the save holds exactly the
## floor the player is looking at; `apply()` puts that floor back without re-announcing any
## of it. `gen_params_for()` / `gen_params_to_dict()` carry the generation inputs, because the
## layout itself is not a pure function of (seed, floor index). Static functions over
## (FloorRoot, RunState): RunManager only says when.
class_name FloorRestore
extends RefCounted


## Records the live floor into `state`'s floor block.
static func capture(root: FloorRoot, state: RunState) -> void:
	if root == null or state == null:
		return
	state.visited_room_ids = root.visited_ids()
	state.stairs_unlocked = root.stairs != null and not root.stairs.locked
	var chests: Array[int] = []
	var looted: Array[int] = []
	for room: RoomNode in root.rooms:
		if not room.has_reward_chest():
			continue
		chests.append(room.id)
		if reward_taken(room):
			looted.append(room.id)
	state.chest_room_ids = chests
	state.looted_room_ids = looted
	state.broken_prop_tiles = root.broken_prop_tiles()
	state.revealed_mimic_tiles = root.revealed_mimic_tiles()
	var used_altars: Array[int] = []
	for node: Node in root.get_altars():
		var altar := node as Altar
		if altar != null and altar.used:
			used_altars.append(room_id_of(altar))
	state.used_altar_room_ids = used_altars
	var used_shrines: Array[int] = []
	for node: Node in root.get_shrines():
		var shrine := node as Shrine
		if shrine != null and shrine.used:
			used_shrines.append(room_id_of(shrine))
	state.used_shrine_room_ids = used_shrines
	var stock: Array[Dictionary] = []
	for node: Node in root.get_shops():
		var shop := node as Shop
		if shop == null or not shop.stock_is_serializable():
			continue
		var entry := shop.to_save_dict()
		entry["room_id"] = room_id_of(shop)
		stock.append(entry)
	state.shops = stock


## True when this room's reward chest has been *answered*, not merely interacted with.
##
## `RoomNode.chest_taken()` reads `Chest.is_opened`, which goes true the instant the player
## presses the key — before the offer it raises has been picked from. The autosave a room clear
## queued fires while that picker is up (the tree is paused, `SaveManager` is
## `PROCESS_MODE_ALWAYS`), so recording "looted" there wrote a run.json holding an opened,
## empty chest, and a session that ended abnormally in that ~0.5 s window lost the reward
## outright. `Chest.reward_taken` is set only by `mark_taken()`, which only
## `RunManager._finish_offer()` calls, so this is the honest answer to "has the player got it".
static func reward_taken(room: RoomNode) -> bool:
	var chest := room.chest
	return chest != null and is_instance_valid(chest) and chest.reward_taken


## Replays `state` onto the floor just rebuilt. `cleared_rooms` is RunManager's own list (the
## same ids as `state.cleared_room_ids`, and the only one that exists on a fresh floor), and
## `boss_room` is `FloorData.boss_room` so the exit can be derived as well as restored.
## `state` may be null: a floor entered for the first time only needs the stairs check.
static func apply(
	root: FloorRoot, state: RunState, cleared_rooms: Array[int], boss_room: int
) -> void:
	if root == null:
		return
	for id: int in cleared_rooms:
		var room := root.get_room(id)
		if room != null:
			room.restore_cleared()
	if state != null:
		# Chests are put back per room, opened or not: a room cleared but never looted keeps
		# its reward, an opened one stays opened (otherwise every Save & Quit is a free
		# second roll), and a room the generator left empty gets nothing invented for it.
		for id: int in state.chest_room_ids:
			var room := root.get_room(id)
			if room != null:
				room.restore_chest(state.looted_room_ids.has(id))
		for id: int in state.visited_room_ids:
			var room := root.get_room(id)
			if room != null:
				room.visited = true
		for node: Node in root.get_altars():
			var altar := node as Altar
			if altar != null and state.used_altar_room_ids.has(room_id_of(altar)):
				altar.restore_used()
		for node: Node in root.get_shrines():
			var shrine := node as Shrine
			if shrine != null and state.used_shrine_room_ids.has(room_id_of(shrine)):
				shrine.restore_used()
		# Props and mimic chests are the set dressing half of the same anti-farm rule the
		# chests, altars, shrines and shop stock above obey: a smashed barrel stays smashed
		# and a sprung mimic stays sprung, because both already paid out once.
		root.restore_broken_props(state.broken_prop_tiles)
		root.restore_revealed_mimics(state.revealed_mimic_tiles)
	# After the replay, so the mimics it just removed are not watched: from here on the floor
	# records every mimic the player springs, for the next save.
	root.watch_mimics()
	apply_stairs(root, state, cleared_rooms, boss_room)


## Opens the floor exit when the save says it was open, or when the boss whose death opens it
## is already dead. The saved flag alone would miss a run saved before that field existed; the
## derived answer alone would miss the elite-pack fallback `_spawn_boss` unlocks the exit for.
static func apply_stairs(
	root: FloorRoot, state: RunState, cleared_rooms: Array[int], boss_room: int
) -> void:
	if root == null or root.stairs == null or not root.stairs.locked:
		return
	var boss_dead := boss_room >= 0 and cleared_rooms.has(boss_room)
	if boss_dead or (state != null and state.stairs_unlocked):
		root.stairs.restore_unlocked()


## The floor's loose loot, recorded into `state`: *both* halves, because they are two separate
## node trees. The items an elite dropped or an equip swap put back down are `ItemPickup` nodes
## under a RoomNode (`FloorPickups`); the homing gold, hearts and stat orbs are `PickupBase`
## nodes under the `PickupSpawner`, off to the side of the floor root entirely (`FloorDrops`).
## A sweep of the floor root finds the first kind and none of the second, which is exactly how
## half of this hole came to be closed and half left open - so the two are captured and replayed
## through one pair of calls from here on, and cannot drift apart again.
static func capture_loose_loot(root: FloorRoot, spawner: PickupSpawner, state: RunState) -> void:
	if state == null:
		return
	state.floor_pickups = FloorPickups.capture(root)
	state.floor_drops = FloorDrops.capture(spawner)


## Replays both halves onto the floor just rebuilt. Call it *after* `EventBus.floor_started`:
## drops of either kind free themselves on that signal so none follows the player down the
## stairs, and the ones a resume replays are exactly the drops that must survive it.
static func apply_loose_loot(
	root: FloorRoot, spawner: PickupSpawner, state: RunState, registry: ItemRegistry
) -> void:
	FloorPickups.apply(root, state, registry)
	# The floor rect is what tells a restored drop's coordinates from a corrupt file's: a save
	# naming a coin at x = 1e30 is not describing this floor, or any floor.
	var bounds := root.camera_limits() if root != null else Rect2()
	FloorDrops.apply(spawner, state, bounds)


## Puts back one shop counter's saved stock. False when the save holds nothing for it (a floor
## entered for the first time, or a save written before shops were persisted), and the caller
## stocks it fresh instead.
static func restore_shop(shop: Shop, state: RunState, registry: ItemRegistry) -> bool:
	if shop == null or state == null:
		return false
	var entry := state.shop_for_room(room_id_of(shop))
	if entry.is_empty():
		return false
	var raw_offers: Array = entry.get("offers", []) as Array
	var raw_prices: Array = entry.get("prices", []) as Array
	var offers: Array[RefCounted] = []
	var prices: Array[int] = []
	for i in range(raw_offers.size()):
		if not (raw_offers[i] is Dictionary):
			continue
		var item := ItemGenerator.from_dict(raw_offers[i] as Dictionary, registry)
		if item == null:
			continue
		offers.append(item)
		prices.append(int(raw_prices[i]) if i < raw_prices.size() else 0)
	shop.restore_stock(offers, prices, int(entry.get("rerolls", 0)))
	return true


## The unanswered board `node` rolled for `source` in `boards` (`RunManager`'s live list), or an
## empty dictionary.
##
## Identity is the room the interactable stands in, because that is what a rebuilt floor hands
## back: the node itself is a different object after a resume, so an instance id cannot address
## a board across one. A node that is not in a room (a test's bare Altar) falls back to its
## instance id and is never saved, and `node` is null for the opening pick, which belongs to the
## run rather than to any room.
static func board_for(boards: Array[Dictionary], source: int, node: Node2D) -> Dictionary:
	var index := board_index(boards, source, node)
	return boards[index] if index >= 0 else {}


## Index of `board_for()`'s entry, or -1.
static func board_index(boards: Array[Dictionary], source: int, node: Node2D) -> int:
	var live := node != null and is_instance_valid(node)
	var room_id := room_id_of(node) if live else -1
	var instance_id := node.get_instance_id() if live else 0
	for i in range(boards.size()):
		var entry := boards[i]
		if int(entry.get("source", -1)) != source:
			continue
		if room_id >= 0:
			if int(entry.get("room_id", -1)) == room_id:
				return i
		elif int(entry.get("instance_id", 0)) == instance_id:
			return i
	return -1


## Records `offers` as the board `node` owes the player for `source`, replacing any earlier board
## of its own — a reroll is a new board for the same interactable. An empty roll records nothing:
## there is no board to come back to.
static func record_board(
	boards: Array[Dictionary],
	source: int,
	node: Node2D,
	kind: int,
	offers: Array,
	curse: Ability,
	rerolled: bool
) -> void:
	drop_board(boards, source, node)
	if offers.is_empty():
		return
	var live := node != null and is_instance_valid(node)
	(
		boards
		. append(
			{
				"source": source,
				"room_id": room_id_of(node) if live else -1,
				"instance_id": node.get_instance_id() if live else 0,
				"kind": kind,
				"offers": offers.duplicate(),
				"curse": curse,
				"rerolled": rerolled,
			}
		)
	)


## Drops the board `node` owed for `source`: it has been answered, and an answered board is not
## owed a second time.
static func drop_board(boards: Array[Dictionary], source: int, node: Node2D) -> void:
	var index := board_index(boards, source, node)
	if index >= 0:
		boards.remove_at(index)


## The unanswered offer boards of `boards` (`RunManager`'s live records), JSON-safe, for the
## floor block. A board belongs to the room its interactable stands in, because that is the
## identity that survives a rebuild: one rolled by a node outside a room (a test's bare Altar)
## could not be addressed again after a resume and is left out. So is one holding a card that
## cannot be written down - half a restored board would be worse than a fresh roll. The
## opening passive pick is the exception, and carries `room_id` -1: it belongs to the run.
static func offer_boards_to_dicts(
	boards: Array[Dictionary], run_scoped_source: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for board: Dictionary in boards:
		var source := int(board.get("source", -1))
		var room_id := int(board.get("room_id", -1))
		if room_id < 0 and source != run_scoped_source:
			continue
		var cards := offers_to_dicts(board.get("offers", []) as Array)
		if cards.is_empty():
			continue
		var curse := board.get("curse") as Ability
		(
			out
			. append(
				{
					"source": source,
					"room_id": room_id,
					"kind": int(board.get("kind", 0)),
					"offers": cards,
					"curse": String(curse.id) if curse != null else "",
					"rerolled": bool(board.get("rerolled", false)),
				}
			)
		)
	return out


## The inverse: `state`'s saved boards as live records again, cards rebuilt from the registries.
## A board whose cards cannot all be rebuilt (an item base or an ability id this build no longer
## ships) is dropped rather than restored short, and its owner rolls a fresh one.
static func offer_boards_from(
	state: RunState, items: ItemRegistry, abilities: AbilityRegistry
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	for entry: Dictionary in state.offer_boards:
		var cards := offers_from_dicts(entry.get("offers", []) as Array, items, abilities)
		if cards.is_empty():
			continue
		var curse_id := StringName(str(entry.get("curse", ""))) if abilities != null else &""
		(
			out
			. append(
				{
					"source": int(entry.get("source", -1)),
					"room_id": int(entry.get("room_id", -1)),
					"instance_id": 0,
					"kind": int(entry.get("kind", 0)),
					"offers": cards,
					"curse": abilities.instance(curse_id) if curse_id != &"" else null,
					"rerolled": bool(entry.get("rerolled", false)),
				}
			)
		)
	return out


## One offer board's cards as JSON-safe dictionaries, or an empty array when any card of it is
## of a shape that is not written down here. All-or-nothing on purpose: a board is the choice
## the player was given, and three cards restored as two is a different choice.
static func offers_to_dicts(offers: Array) -> Array:
	var out: Array = []
	for offer: Variant in offers:
		var card := _offer_to_dict(offer)
		if card.is_empty():
			return []
		out.append(card)
	return out


## The inverse of `offers_to_dicts()`; an empty array when any card cannot be rebuilt.
static func offers_from_dicts(raw: Array, items: ItemRegistry, abilities: AbilityRegistry) -> Array:
	var out: Array = []
	for entry: Variant in raw:
		if not (entry is Dictionary):
			return []
		var card: Variant = _offer_from_dict(entry as Dictionary, items, abilities)
		if card == null:
			return []
		out.append(card)
	return out


## One card of a board. A shrine's menu card is deliberately not among the shapes: a shrine's
## options are carved into the shrine (docs §8) and are rebuilt from it, never rolled.
static func _offer_to_dict(offer: Variant) -> Dictionary:
	if offer is ItemInstance:
		return {"card": "item", "item": (offer as ItemInstance).to_dict()}
	if offer is Ability:
		var ability := offer as Ability
		return {"card": "ability", "id": String(ability.id), "tier": ability.tier}
	if offer is int or offer is float:
		return {"card": "gold", "amount": int(offer)}
	if offer is Dictionary:
		var entry := offer as Dictionary
		if entry.has("stat") and entry.has("points") and not entry.has("cost_kind"):
			return {
				"card": "stat",
				"stat": String(entry["stat"]),
				"points": int(entry["points"]),
			}
	return {}


## One card rebuilt, or null when this build cannot make it any more.
static func _offer_from_dict(
	entry: Dictionary, items: ItemRegistry, abilities: AbilityRegistry
) -> Variant:
	match str(entry.get("card", "")):
		"item":
			return ItemGenerator.from_dict(entry.get("item", {}) as Dictionary, items)
		"ability":
			if abilities == null:
				return null
			var ability := abilities.instance(StringName(str(entry.get("id", ""))))
			if ability != null:
				ability.tier = maxi(1, int(entry.get("tier", 1)))
			return ability
		"gold":
			return int(entry.get("amount", 0))
		"stat":
			return {
				"stat": StringName(str(entry.get("stat", "might"))),
				"points": maxi(1, int(entry.get("points", 1))),
			}
	return null


## Generation inputs for floor `index`: the live ThemeProfile plus the music energy, or the
## exact values a resumed run recorded. Layout is not a pure function of (seed, floor index):
## it also depends on the desktop theme and the music energy at generation time, so a run
## saved under Gruvbox and continued under Nord has to be rebuilt from the recorded values or
## the cleared-room set and the current room point at rooms that no longer exist (docs §12).
static func gen_params_for(index: int, saved: Dictionary) -> GenParams:
	var params := GenParams.build(Desktop.profile, index, Music.profile(), Desktop.wallpaper)
	if saved.is_empty():
		return params
	params.corridor_wiggle = float(saved.get("corridor_wiggle", params.corridor_wiggle))
	params.room_size_bias = float(saved.get("room_size_bias", params.room_size_bias))
	params.trap_density = float(saved.get("trap_density", params.trap_density))
	params.prop_density = float(saved.get("prop_density", params.prop_density))
	params.biome = StringName(str(saved.get("biome", params.biome)))
	params.extra_loops = int(saved.get("extra_loops", params.extra_loops))
	params.enemy_count_scale = float(saved.get("enemy_count_scale", params.enemy_count_scale))
	params.ambush_scale = float(saved.get("ambush_scale", params.ambush_scale))
	params.light_scale = float(saved.get("light_scale", params.light_scale))
	params.sight_scale = float(saved.get("sight_scale", params.sight_scale))
	params.cadence_scale = float(saved.get("cadence_scale", params.cadence_scale))
	params.loot_scale = float(saved.get("loot_scale", params.loot_scale))
	params.accent_prop = int(saved.get("accent_prop", params.accent_prop))
	params.music_energy = float(saved.get("music_energy", params.music_energy))
	params.music_tempo = float(saved.get("music_tempo", params.music_tempo))
	params.track_hash = int(saved.get("track_hash", params.track_hash))
	params.wallpaper_seed = int(saved.get("wallpaper_seed", params.wallpaper_seed))
	# Saved like every other lever: `FloorArchetype.weights` reads it, so a floor resumed
	# under a different wallpaper would otherwise come back as a different floor plan.
	params.wallpaper_variety = float(saved.get("wallpaper_variety", params.wallpaper_variety))
	params.ambient = float(saved.get("ambient", params.ambient))
	params.theme_hash = int(saved.get("theme_hash", params.theme_hash))
	params.archetype = StringName(str(saved.get("archetype", params.archetype)))
	var hazards: Variant = saved.get("hazard_weights", null)
	if hazards is Dictionary:
		params.hazard_weights = {}
		for key: Variant in hazards as Dictionary:
			params.hazard_weights[StringName(str(key))] = float((hazards as Dictionary)[key])
	params.refresh_fill_bias()
	return params


## The inverse: the fields of `params` that a resume has to reproduce, JSON-safe.
static func gen_params_to_dict(params: GenParams) -> Dictionary:
	if params == null:
		return {}
	return {
		"corridor_wiggle": params.corridor_wiggle,
		"room_size_bias": params.room_size_bias,
		"trap_density": params.trap_density,
		"prop_density": params.prop_density,
		"biome": String(params.biome),
		"extra_loops": params.extra_loops,
		"enemy_count_scale": params.enemy_count_scale,
		"ambush_scale": params.ambush_scale,
		"light_scale": params.light_scale,
		"sight_scale": params.sight_scale,
		"cadence_scale": params.cadence_scale,
		"loot_scale": params.loot_scale,
		"accent_prop": params.accent_prop,
		"music_energy": params.music_energy,
		"music_tempo": params.music_tempo,
		"track_hash": params.track_hash,
		"wallpaper_seed": params.wallpaper_seed,
		"wallpaper_variety": params.wallpaper_variety,
		"ambient": params.ambient,
		"theme_hash": params.theme_hash,
		"archetype": String(params.archetype),
		"hazard_weights": _hazard_weights_json(params.hazard_weights),
	}


## `hazard_weights` with string keys, so JSON round-trips it (a StringName key is not JSON).
static func _hazard_weights_json(weights: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in weights:
		out[String(key)] = float(weights[key])
	return out


## Id of the room a floor interactable was placed in (FloorRoot parents them to the RoomNode),
## or -1 for one that is not in a room.
static func room_id_of(node: Node) -> int:
	var room := node.get_parent() as RoomNode
	return room.id if room != null else -1
