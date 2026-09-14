## Autoload `RunManager`: owns the run lifecycle (title -> class select -> floors -> summary),
## wires the modules together through EventBus and drives the chest/altar/shrine/shop offer
## flows. It is the only place that knows about both the UI and the simulation.
##
## Scene ownership: `new_run()` / `resume_run()` swap the current scene for `src/game.tscn`;
## `_end_run()`, `save_and_quit()` and `abandon_run()` swap back to `src/main.tscn` (which shows
## the title or the run summary). Set `manage_scenes = false` in headless tests to keep the
## SceneTree's `current_scene` untouched; the Game node is then parented to the tree root.
extends Node

enum OfferSource { NONE, CHEST, ALTAR, SHRINE, SHOP, STARTING_PASSIVE }

const GAME_SCENE_PATH := "res://src/game.tscn"
const MAIN_SCENE_PATH := "res://src/main.tscn"
const CLASS_DIR := "res://data/classes"
const ENEMY_REGISTRY_PATH := "res://data/enemies/registry.tres"
const CLASS_IDS: Array[StringName] = [&"fighter", &"ranger", &"wizard", &"oligarch"]
## Floors per run; the last one (index 8) ends the run when its stairs are used.
const FLOOR_COUNT := 9
## 0-based floor indices that hold a boss arena, and the boss that owns each of them.
const BOSS_FLOORS: Array[int] = [2, 5, 8]
const BOSS_IDS: Array[StringName] = [&"ringmaster", &"elder_greybeard", &"the_suit"]
## Base gold price of one shop item, plus the growth per floor.
const SHOP_BASE_PRICE := 40
const SHOP_PRICE_PER_FLOOR := 15
## Gold handed out for skipping a chest (docs §8).
const SKIP_GOLD_BASE := 10
const SKIP_GOLD_PER_FLOOR := 3
## Oligarch Buyout (docs §4.3): gold a chest costs to open, and the growth per floor. Kept
## small deliberately - at 10 + 8/floor the economy class finished runs poorest of the four.
const BUYOUT_BASE_PRICE := 12
const BUYOUT_PRICE_PER_FLOOR := 2
## Profile counter raised by every abandoned run, so the stats page can tell a player who
## walked away from one who was killed (`Profile.counters`, shown by `StatsScreen`).
const ABANDON_COUNTER := &"runs_abandoned"
## Seconds the death animation is given before the summary screen appears.
const DEATH_DELAY := 1.2
## Shown when Save & Quit could not write the run; it says the run is still here because the
## run really is, and the player just pressed a button that normally ends the session.
const SAVE_FAILED_TEXT := "Could not save — your run is still here"
const SAVE_FAILED_SECONDS := 6.0
## RNG streams whose *position* is part of the run's saved state (docs §12): they are drawn
## from all run long, so a resume continues where the save left off instead of rewinding to the
## seed and handing out a free chest reroll. Per-floor streams derive from (seed, floor index).
const PERSISTENT_RNG_STREAMS: Array[StringName] = [&"loot", &"combat", &"ai"]

## False in headless tests: the Game node is added to the tree root and `current_scene`,
## the title screen and the summary screen are never touched.
var manage_scenes: bool = true
## Docs §2 step "Pick 1 starting passive". Turned off automatically for `--test-scenario`
## captures (the picker would cover every rendered check) and settable by tests.
var offer_starting_passive: bool = true
var rng: RunRng
var run_seed: int = 0
var floor_index: int = 0
var class_def: ClassDef
var floor_data: FloorData
var gen_params: GenParams
var game: Node2D
## Summary of the run that just ended; `Main` renders it and clears it.
var pending_summary: Dictionary = {}
var enemy_registry: EnemyRegistry
var item_registry: ItemRegistry
var ability_registry: AbilityRegistry
var classes: Dictionary = {}

var _run_active: bool = false
var _tally := RunTally.new()
var _descend := DescendNotice.new()
var _rerolls_this_floor: int = 0
var _free_reroll_used: bool = false
var _cleared_rooms: Array[int] = []
## Which enemies of each unfinished room the player has already killed and been paid for, so a
## resumed pack is thinned rather than re-sold (docs §12).
var _packs := PackLedger.new()
## Room whose chest has an offer on screen that a resume still owes the player, or -1.
var _pending_chest_offer_room: int = -1
var _current_room_id: int = -1
var _offer_source: OfferSource = OfferSource.NONE
var _offer_node: Node2D
var _offer_kind: int = 0
var _offers: Array = []
var _shrine_options: Array[Dictionary] = []
## True once the board on screen has been rerolled; a rerolled board pays no skip bonus.
var _offers_rerolled: bool = false
## True while the mandatory floor-1 starting-passive pick is still owed. Saved into RunState
## so closing the window on the picker re-offers the pick instead of losing it.
var _starting_passive_pending: bool = false
## True while this offer is the thing holding the tree paused.
var _paused_for_offer: bool = false
## Curse rolled alongside a CURSED chest's Legendary; attached when the prize is taken.
var _pending_curse: Ability
## Every board rolled on this floor and not answered yet, keyed by the interactable that owes
## it (`FloorRestore.record_board`, `RunState.offer_boards`). Cleared on a floor change: the
## next floor numbers its rooms the same way.
var _boards: Array[Dictionary] = []
var _resume_room_id: int = -1
## Bumped by every `new_run()` / `resume_run()`. Handlers that await (the death delay) capture
## it first and bail when it moved, so a finished run can never end the one that replaced it.
var _run_token: int = 0


## Releases the resources this autoload caches: an autoload outlives the resource system, so
## holding one to process exit makes the engine log "resources still in use at exit".
func _exit_tree() -> void:
	classes.clear()
	class_def = null
	enemy_registry = null
	item_registry = null
	ability_registry = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Content cannot load from an autoload's _ready(): the scripts it references are still
	# initialising, so ResourceLoader returns null. ensure_registries() does it on first idle.
	ensure_registries.call_deferred()
	EventBus.floor_exit_requested.connect(_on_floor_exit_requested)
	EventBus.chest_opened.connect(_on_chest_opened)
	EventBus.altar_used.connect(_on_altar_used)
	EventBus.shrine_used.connect(_on_shrine_used)
	EventBus.shop_opened.connect(_on_shop_opened)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.player_fell.connect(_on_player_fell)
	EventBus.spawn_enemy_requested.connect(_on_spawn_enemy_requested)
	SaveManager.state_provider = build_run_state
	add_to_group(Chest.OPEN_GUARD_GROUP)
	TestScenarios.start_if_requested(get_tree())


## Loads the enemy/item/ability registries and the class defs once. Safe to call repeatedly.
func ensure_registries() -> void:
	if enemy_registry == null:
		enemy_registry = load(ENEMY_REGISTRY_PATH) as EnemyRegistry
	if item_registry == null:
		item_registry = ItemRegistry.load_default()
	if ability_registry == null:
		ability_registry = AbilityRegistry.load_default()
	if classes.is_empty():
		for id: StringName in CLASS_IDS:
			var def := load("%s/%s.tres" % [CLASS_DIR, id]) as ClassDef
			if def != null:
				classes[id] = def


## True between `new_run()`/`resume_run()` and the end of the run.
func is_run_active() -> bool:
	return _run_active


## The live player, or null outside a run.
func player() -> Player:
	if game == null or not is_instance_valid(game):
		return null
	return (game as Game).player


## The live floor root, or null outside a run.
func floor_root() -> FloorRoot:
	if game == null or not is_instance_valid(game):
		return null
	return (game as Game).floor_root


## True on the floors that end with a boss arena (0-based indices 2, 5, 8).
static func is_boss_floor(index: int) -> bool:
	return BOSS_FLOORS.has(index)


## Boss id for a boss floor, or an empty StringName for an ordinary floor.
static func boss_id_for_floor(index: int) -> StringName:
	var slot := BOSS_FLOORS.find(index)
	return BOSS_IDS[slot] if slot >= 0 else &""


# ---------------------------------------------------------------- lifecycle


## Starts a fresh run with `class_id` and a fixed seed. Replaces the current scene with the
## game scene and builds floor 1.
func new_run(seed_value: int, class_id: StringName) -> bool:
	ensure_registries()
	var def := classes.get(class_id) as ClassDef
	if def == null:
		push_error("RunManager: unknown class %s" % class_id)
		return false
	_reset_run_stats()
	run_seed = seed_value
	rng = RunRng.new(run_seed)
	class_def = def
	floor_index = 0
	_tally.begin()
	_run_active = true
	_run_token += 1
	GameState.run_seed = run_seed
	GameState.class_id = class_id
	GameState.floor_index = 0
	SaveManager.delete_run()
	_enter_game_scene()
	_setup_player()
	_tally.prime_gold(player())
	EventBus.run_started.emit(run_seed)
	Music.set_shuffle_seed(run_seed)
	_build_floor(0)
	# Recorded *before* the first autosave: the picker pauses the tree but SaveManager runs
	# anyway, so the snapshot that reaches disk while the cards are up has to say "still owed".
	_starting_passive_pending = offer_starting_passive
	SaveManager.request_autosave()
	_offer_starting_passive()
	return true


## Resumes the saved run. Returns false when there is nothing to resume.
func resume_run() -> bool:
	ensure_registries()
	var state := SaveManager.load_run()
	if state == null:
		return false
	var def := classes.get(state.class_id) as ClassDef
	if def == null:
		push_error("RunManager: saved run has unknown class %s" % state.class_id)
		return false
	_reset_run_stats()
	run_seed = state.run_seed
	rng = RunRng.new(run_seed)
	class_def = def
	floor_index = maxi(0, state.floor_index)
	_tally.restore(state)
	_cleared_rooms = state.cleared_room_ids.duplicate()
	_packs = PackLedger.from_entries(state.defeated_spawns)
	_resume_room_id = state.current_room_id
	_run_active = true
	_run_token += 1
	GameState.run_seed = run_seed
	GameState.class_id = class_def.id
	GameState.floor_index = floor_index
	_enter_game_scene()
	_setup_player()
	var live := player()
	if live != null:
		live.restore_from_dict(state.player, item_registry, ability_registry)
	_tally.prime_gold(player())
	# After the loadout: `_setup_player()` replays the start-weapon roll on a fresh stream, so
	# the saved positions have to land on top of it, not before it.
	if rng != null:
		rng.restore(state.rng_states)
	EventBus.run_started.emit(run_seed)
	Music.set_shuffle_seed(run_seed)
	Music.restore_tracks(state.tracks_played)
	_build_floor(floor_index, state)
	if live != null and state.hp_fraction > 0.0:
		live.health.hp = clampf(live.health.max_hp * state.hp_fraction, 1.0, live.health.max_hp)
		live.health.hp_changed.emit(live.health.hp, live.health.max_hp)
	# A run whose opening passive pick never resolved (the window was closed on the picker)
	# gets it back instead of losing it: the pick is mandatory, so a resume must re-offer it.
	_starting_passive_pending = state.starting_passive_pending
	# A chest whose offer was still on screen when the run was saved owes the player a pick for
	# exactly the same reason, and the chest was deliberately left unspent for it.
	_pending_chest_offer_room = state.chest_offer_room_id
	# ... and the cards themselves come back with it: rolling them again was the free reroll
	# (the saved loot stream is already past the board the player saw).
	_boards = FloorRestore.offer_boards_from(state, item_registry, ability_registry)
	if _starting_passive_pending:
		_offer_starting_passive()
	else:
		_resume_chest_offer()
	return true


## Pause menu "Save and Quit": writes the run, then returns to the title. Returns false when
## the write did not reach the disk, leaving the run live, on screen and resumable with a
## banner saying so - a full disk must not silently destroy half an hour of play.
func save_and_quit() -> bool:
	if _run_active and not SaveManager.save_run(build_run_state()):
		push_warning("RunManager: Save & Quit could not write the run; keeping it live")
		EventBus.toast.emit(SAVE_FAILED_TEXT, SAVE_FAILED_SECONDS)
		return false
	_run_active = false
	_teardown_run()
	_show_main()
	return true


## Pause menu "Abandon Run": deletes the save and shows the summary. Not a death - the player
## walked away from a live run - so the summary and the profile are told which it was.
func abandon_run() -> void:
	if not _run_active:
		return
	SaveManager.delete_run()
	_end_run(false, true)


func _reset_run_stats() -> void:
	_tally.begin()
	_rerolls_this_floor = 0
	_free_reroll_used = false
	_boards.clear()
	_cleared_rooms = []
	_packs.clear()
	_pending_chest_offer_room = -1
	_current_room_id = -1
	_resume_room_id = -1
	_descend.reset()
	_clear_offer_state()
	pending_summary = {}


func _enter_game_scene() -> void:
	var tree := get_tree()
	# A run started while a Game is still up (two `new_run` calls in a row, a resume over a live
	# run) used to overwrite the reference and orphan the old scene: its player stayed in group
	# "player" and its enemies in group "enemy" for the rest of the process, so every later
	# lookup by group saw a dead run's nodes.
	if game != null and is_instance_valid(game):
		var stale := game as Game
		if stale != null:
			stale.unload_floor()
		game.queue_free()
		game = null
	var scene := load(GAME_SCENE_PATH) as PackedScene
	game = scene.instantiate() as Node2D
	if manage_scenes:
		var old := tree.current_scene
		tree.root.add_child(game)
		tree.current_scene = game
		if old != null and is_instance_valid(old) and old != game:
			old.queue_free()
	else:
		tree.root.add_child(game)
	var view := game as Game
	view.pause_menu.save_quit_pressed.connect(save_and_quit)
	view.pause_menu.abandon_pressed.connect(abandon_run)
	view.chest_ui.chosen.connect(_on_offer_chosen)
	view.chest_ui.rerolled.connect(_on_offer_rerolled)
	view.chest_ui.skipped.connect(_on_offer_skipped)
	view.pause_menu.bind(view.player)


func _teardown_run() -> void:
	_clear_offer_state()
	if game != null and is_instance_valid(game):
		(game as Game).unload_floor()
		game.queue_free()
	game = null
	floor_data = null
	Music.stop()


## Returns to `main.tscn` (title, or the run summary when `pending_summary` is filled).
func _show_main() -> void:
	if not manage_scenes:
		return
	var tree := get_tree()
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	var next := scene.instantiate()
	var old := tree.current_scene
	tree.root.add_child(next)
	tree.current_scene = next
	if old != null and is_instance_valid(old) and old != next:
		old.queue_free()


## Builds the player's class, weapon, innate passive and class active.
func _setup_player() -> void:
	var live := player()
	if live == null:
		return
	live.rng = rng.stream(&"combat")
	live.apply_class(class_def)
	var slots := live.ability_slots as AbilitySlots
	if slots != null:
		slots.rng = rng.stream(&"combat")
	var base := item_registry.find_base(class_def.start_weapon_id)
	if base != null:
		# The same grant site as every reward, with no answer to honour: the slots are all empty.
		RewardEffects.grant_item(live, ItemGenerator.instance_of(base, rng.stream(&"loot")))
	if slots == null:
		return
	var innate := ability_registry.innate_for(class_def.id)
	if innate != null:
		slots.add_innate(innate)
	var active := ability_registry.instance(class_def.class_active_id)
	if active != null:
		slots.add(active)
	# One grant only: `starting_actives_for(class_def)` already resolves `extra_ability_ids`.
	# Adding the same id twice would tier the ability up, so the Oligarch would start its
	# Contract at tier 2 (docs §4.3: it starts *with a* Contract, not an upgraded one).
	for starting: ActiveAbility in ability_registry.starting_actives_for(class_def):
		slots.add(starting)


# ---------------------------------------------------------------- floors


## Generates and builds floor `index`. `saved` is the RunState a resume is replaying: its
## `gen_params` rebuild the exact parameters the floor was generated with, and its floor
## block puts back everything the player already spent or opened on it (docs §12). Null on a
## fresh floor, which reads the live theme and starts untouched.
func _build_floor(index: int, saved: RunState = null) -> void:
	floor_index = index
	GameState.floor_index = index
	_rerolls_this_floor = saved.rerolls_this_floor if saved != null else 0
	_free_reroll_used = saved.free_reroll_used if saved != null else false
	gen_params = FloorRestore.gen_params_for(index, saved.gen_params if saved != null else {})
	floor_data = FloorGenerator.generate(gen_params, rng.floor_stream(&"gen", index))
	var view := game as Game
	view.load_floor(floor_data, index, rng.floor_stream(&"loot", index), gen_params.light_scale)
	view.hud.set_seed(run_seed)
	var root := view.floor_root
	FloorRestore.apply(root, saved, _cleared_rooms, floor_data.boss_room)
	var spawn := root.player_spawn_position()
	var entry_room := floor_data.start_room
	if _resume_room_id >= 0 and floor_data.room_by_id(_resume_room_id) != null:
		spawn = root.room_entry_position(_resume_room_id)
		entry_room = _resume_room_id
	_resume_room_id = -1
	# The player is standing in `entry_room` from this frame on; `room_entered` only confirms
	# it a physics frame later, and an autosave in between would record "no room".
	_current_room_id = entry_room
	root.set_current_room(entry_room)
	var live := player()
	if live != null:
		live.global_position = spawn
		live.velocity = Vector2.ZERO
		view.camera.follow(live)
		view.camera.snap_to(spawn)
		root.bind_player(live)
	view.camera.set_limits(root.camera_limits())
	_populate_rooms()
	_stock_shops(saved)
	view.refresh_minimap()
	EventBus.floor_started.emit(index)
	# After `floor_started`, deliberately; `FloorRestore.apply_loose_loot` documents why.
	FloorRestore.apply_loose_loot(root, view.pickup_spawner, saved, item_registry)
	# Boss music is a room, not a floor (docs 10.2): the radio plays the approach and
	# `_on_room_entered` switches to the boss subset on the threshold of the arena.
	Music.play_playlist()
	_descend.refresh_prompt(floor_root(), floor_data, is_boss_floor(floor_index + 1))
	# Through the HUD: it drops the banner of the floor before, which a fast descent leaves
	# queued behind the floor it names.
	view.hud.announce_floor(index, String(floor_data.biome))
	view.hud.announce_desktop(Hud.desktop_line(Desktop.palette.name, Desktop.wallpaper != null))
	view.hud.announce_music(Music.floor_banner(index))


## Fills the floor's rooms with enemies. `FloorPopulator` owns the rules, including leaving
## out the enemies this run already killed in a room it never finished (docs §12).
func _populate_rooms() -> void:
	var root := floor_root()
	if root == null:
		return
	var populator := FloorPopulator.new()
	populator.registry = enemy_registry
	populator.packs = _packs
	populator.floor_index = floor_index
	populator.apply_params(gen_params)
	populator.boss_id = boss_id_for_floor(floor_index)
	populator.faction_weights = Desktop.profile.faction_weights
	populator.populate(root, floor_data, _cleared_rooms, rng.floor_stream(&"spawn", floor_index))


## Fills every shop counter of the floor with three items priced by rarity. A resumed floor
## restores the stock the save recorded instead: an item the player bought stays bought and a
## reroll they paid for is not refunded, so Save & Quit is not a free restock (docs §12).
func _stock_shops(saved: RunState = null) -> void:
	var root := floor_root()
	if root == null:
		return
	var loot := rng.floor_stream(&"shop", floor_index)
	var luck := _player_luck()
	for node: Node in root.get_shops():
		var shop := node as Shop
		if shop == null:
			continue
		if FloorRestore.restore_shop(shop, saved, item_registry):
			continue
		var offers: Array = []
		for _i in range(Shop.MAX_OFFERS):
			var item := ItemGenerator.generate(item_registry, floor_index, loot, luck)
			if item != null:
				offers.append(item)
		shop.stock(offers, SHOP_BASE_PRICE + floor_index * SHOP_PRICE_PER_FLOOR)


func _player_luck() -> float:
	var live := player()
	return live.stats.get_value(&"luck") if live != null else 0.0


func _on_floor_exit_requested() -> void:
	if not _run_active:
		return
	if floor_index + 1 >= FLOOR_COUNT:
		_end_run(true)
		return
	# Descending was one unconfirmed keypress that abandoned the rest of the floor.
	if _descend.intercept(floor_root(), floor_data):
		return
	_cleared_rooms = []
	_packs.clear()
	_pending_chest_offer_room = -1
	_current_room_id = -1
	_boards.clear()
	_build_floor(floor_index + 1)
	SaveManager.request_autosave()


func _on_room_entered(room_id: int) -> void:
	if not _run_active:
		return
	_current_room_id = room_id
	if floor_data != null and room_id >= 0 and room_id == floor_data.boss_room:
		Music.play_boss()
	var view := game as Game
	if view == null or not is_instance_valid(view):
		return
	# FloorRoot listens to the same signal, but this autoload connected first (in its own
	# `_ready()`, long before the floor existed) so its `current_room_id` is still the previous
	# room here. Write it before the minimap reads it, instead of drawing a room-late marker.
	var root := view.floor_root
	if root != null and is_instance_valid(root):
		root.set_current_room(room_id)
	view.refresh_minimap()
	# Visiting a room changes what descending would leave behind, so the stairs prompt is
	# re-costed here rather than only once per floor.
	_descend.refresh_prompt(floor_root(), floor_data, is_boss_floor(floor_index + 1))


func _on_room_cleared(room_id: int) -> void:
	if not _run_active:
		return
	if not _cleared_rooms.has(room_id):
		_cleared_rooms.append(room_id)
	# The pack is never rebuilt now, so its kill record is dead weight in every later run.json.
	_packs.forget(room_id)
	var view := game as Game
	if view != null and is_instance_valid(view):
		view.refresh_minimap()
	# An elite's drop lands here, and what is on the floor is half of what descending costs.
	_descend.refresh_prompt(floor_root(), floor_data, is_boss_floor(floor_index + 1))


func _on_player_fell(_pos: Vector2) -> void:
	var root := floor_root()
	var live := player()
	if root == null or live == null:
		return
	var room_id := _current_room_id if _current_room_id >= 0 else floor_data.start_room
	live.global_position = root.room_entry_position(room_id)
	live.velocity = Vector2.ZERO


func _on_spawn_enemy_requested(id: StringName, pos: Vector2) -> void:
	var root := floor_root()
	if root == null or not _run_active:
		return
	var def := enemy_registry.find(id)
	if def == null:
		return
	var enemy := EnemySpawner.instantiate(def, floor_index, pos, rng.stream(&"ai"))
	if enemy == null:
		return
	var room := root.room_at_world(pos)
	root.add_enemy(enemy, room.id if room != null else _current_room_id)


# ---------------------------------------------------------------- offer flows


## Docs §2 ("Pick 1 starting passive"): floor 1 opens on a passive choice, so two runs of the
## same class never start identically. The start room holds no enemies, so nothing happens
## behind the picker. Shown through the ordinary offer UI; rerollable, not skippable.
func _offer_starting_passive() -> void:
	if not offer_starting_passive or not _run_active:
		_starting_passive_pending = false
		return
	var live := player()
	var view := game as Game
	if live == null or view == null or not is_instance_valid(view):
		_starting_passive_pending = false
		return
	_offer_kind = Chest.Kind.ABILITY
	var offers := _open_board(OfferSource.STARTING_PASSIVE, null, _offer_kind)
	if offers.is_empty():
		_starting_passive_pending = false
		return
	_starting_passive_pending = true
	_offer_source = OfferSource.STARTING_PASSIVE
	_offer_node = null
	_offers = offers
	_show_offers(StartingPassive.CONTEXT)


func _roll_starting_passives() -> Array:
	var live := player()
	if live == null or ability_registry == null or class_def == null:
		return []
	var slots := live.ability_slots as AbilitySlots
	var owned: Dictionary = slots.owned_tiers() if slots != null else {}
	return StartingPassive.roll(
		ability_registry, rng.stream(&"loot"), class_def.id, owned, SaveManager.is_unlocked
	)


## Gold the Oligarch's Buyout charges to open a chest on the current floor; 0 for every class
## without the `chest_costs_gold` flag (docs §4.3).
func chest_open_price() -> int:
	var live := player()
	if live == null or not bool(live.flags.get("chest_costs_gold", false)):
		return 0
	return BUYOUT_BASE_PRICE + floor_index * BUYOUT_PRICE_PER_FLOOR


## `Chest.OPEN_GUARD_GROUP` hook: charges the Buyout price *before* the chest consumes itself.
## Returns false when the player cannot pay — the chest is left closed and usable, and the
## toast says exactly what it costs — so an Oligarch short of gold never loses a chest.
func can_open_chest(_chest: Node2D) -> bool:
	# One offer at a time. Without this the interact key opens a second chest while the cards
	# are up, and the first chest - already consumed by `Chest._on_interact` - pays nothing.
	if is_offer_open():
		EventBus.toast.emit("Finish choosing first", 1.2)
		return false
	var live := player()
	if live == null:
		# No live run means nobody to charge: never stand in the way of a chest.
		return true
	var price := chest_open_price()
	if price <= 0:
		return true
	if not live.spend_gold(price):
		EventBus.toast.emit("Buyout: %dg to open (you have %dg)" % [price, live.gold], 2.0)
		return false
	EventBus.toast.emit("Buyout: paid %dg" % price, 1.2)
	return true


## True while an offer UI is up and its source has not been resolved yet.
func is_offer_open() -> bool:
	return _offer_source != OfferSource.NONE


## The Curse a CURSED chest has rolled and will attach when its prize is taken, or null.
func pending_curse() -> Ability:
	return _pending_curse


func _on_chest_opened(chest: Node2D) -> void:
	if not _run_active or game == null or is_offer_open():
		return
	var live := player()
	if live == null:
		return
	_offer_source = OfferSource.CHEST
	_offer_node = chest
	_offer_kind = int(chest.get("kind"))
	_offers = _open_board(OfferSource.CHEST, chest, _offer_kind)
	_show_offers()


func _on_altar_used(altar: Node2D) -> void:
	# Altars, shops and shrines are not consumed until `_finish_offer`, so refusing here simply
	# leaves them usable once the board that is already up has been answered.
	if not _run_active or game == null or is_offer_open():
		return
	_offer_source = OfferSource.ALTAR
	_offer_node = altar
	_offer_kind = Chest.Kind.ABILITY
	_offers = _open_board(OfferSource.ALTAR, altar, Chest.Kind.ABILITY)
	_show_offers()


func _on_shrine_used(shrine: Node2D) -> void:
	if not _run_active or game == null or is_offer_open():
		return
	var node := shrine as Shrine
	if node == null:
		return
	_offer_source = OfferSource.SHRINE
	_offer_node = shrine
	_offer_kind = Chest.Kind.STAT
	_shrine_options = node.options.duplicate()
	# Cards are built from the shrine's own options, in its order: card N charges option N.
	var board := ChestOffers.shrine_cards(_shrine_options, player())
	_offers = board["offers"]
	_show_offers({"prices": board["prices"], "title": "Shrine"})


func _on_shop_opened(shop_node: Node2D) -> void:
	if not _run_active or game == null or is_offer_open():
		return
	var shop := shop_node as Shop
	if shop == null:
		return
	_offer_source = OfferSource.SHOP
	_offer_node = shop
	_offer_kind = Chest.Kind.ITEM
	_offers = []
	for offer: RefCounted in shop.offers:
		_offers.append(offer)
	_show_offers(ChestOffers.shop_context(shop))


## The cards `node` shows for `source`: the board it already owes the player, or a fresh roll
## that becomes its board. Every board goes through this one door, so "restore it, never roll it
## again" holds for chests, altars and the opening pick alike - what the reroll price rests on.
func _open_board(source: OfferSource, node: Node2D, kind: int) -> Array:
	var entry := FloorRestore.board_for(_boards, int(source), node)
	if not entry.is_empty():
		_pending_curse = entry.get("curse") as Ability
		_offers_rerolled = bool(entry.get("rerolled", false))
		return (entry["offers"] as Array).duplicate()
	var rolled := (
		_roll_starting_passives() if source == OfferSource.STARTING_PASSIVE else _roll_offers(kind)
	)
	_remember_board(source, node, rolled)
	return rolled


## Records `offers` as the board this interactable owes, replacing any earlier one of its own.
func _remember_board(source: OfferSource, node: Node2D, offers: Array) -> void:
	FloorRestore.record_board(
		_boards, int(source), node, _offer_kind, offers, _pending_curse, _offers_rerolled
	)


## Rolls the offers for a chest kind (docs §8); `ChestOffers` owns the content rules.
func _roll_offers(kind: int) -> Array:
	var live := player()
	if live == null:
		return []
	var rolled := ChestOffers.for_player(
		kind, live, floor_index, rng.stream(&"loot"), item_registry, ability_registry, class_def.id
	)
	_pending_curse = rolled.curse
	return rolled.offers


func _show_offers(extra_context: Dictionary = {}) -> void:
	var live := player()
	var view := game as Game
	if live == null or view == null:
		return
	var slots := live.ability_slots as AbilitySlots
	var free_reroll := (
		bool(live.flags.get("free_reroll_per_floor", false)) and not _free_reroll_used
	)
	var context := {
		"gold": live.gold,
		"reroll_cost": _reroll_cost(),
		"free_reroll": free_reroll,
		"can_reroll": _can_reroll_offer(live, free_reroll),
		# Only a chest pays for being skipped (docs §8); the picker captions the button.
		"skip_gold": skip_gold() if _offer_source == OfferSource.CHEST else 0,
		"skip_keeps": _skip_keeps_offer(),
		# The starting-passive pick is mandatory; a Skip that re-opens the same cards with a
		# scolding toast reads as a bug rather than as a rule, so the button is hidden.
		"no_skip": _offer_source == OfferSource.STARTING_PASSIVE,
		"current_stats": ChestOffers.current_stats(live),
		"extra_option": bool(live.flags.get("chest_extra_option", false)),
	}
	# The cursed chest's price is not a card of its own, so the prize card has to state it.
	if _pending_curse != null:
		context["curse_text"] = RewardEffects.curse_card_text(_pending_curse, slots)
	if live.equipment != null:
		context["weapon"] = (live.equipment as Equipment).weapon()
		context["compare"] = Callable(live.equipment, "compare").bind(live.stats)
		# What the slot holds now, so the card can print the weapon numbers it would replace
		# (Stats cannot see them) and tell an upgrade from filling an empty slot.
		context["equipped"] = Callable(live.equipment, "worn_for")
	if slots != null:
		context["needs_replace"] = _needs_replace
	# The Curse is the price, so it is the card on the right of the second trade: the player is
	# choosing which passive it takes, not which passive the ring goes into.
	if _pending_curse != null:
		context["price_replace"] = _price_replace
		context["price_offer"] = _pending_curse
	for key: String in extra_context.keys():
		context[key] = extra_context[key]
	_hold_pause()
	view.chest_ui.show_offers(_offer_kind, _offers, context)


## Gold a skipped board is worth (docs §8). Zero once the board has been rerolled: paying the
## skip bonus on a rerolled board makes reroll-then-skip free money from the floor where the
## bonus catches up with the reroll price.
func skip_gold() -> int:
	if _offers_rerolled:
		return 0
	return SKIP_GOLD_BASE + floor_index * SKIP_GOLD_PER_FLOOR


## True when closing this board leaves the thing that opened it usable: an Altar, a Shrine and
## a Shop are only spent by *taking* something, while a chest is gone the moment it is opened -
## which is what the skip bonus pays for.
func _skip_keeps_offer() -> bool:
	var keeps: Array[OfferSource] = [OfferSource.ALTAR, OfferSource.SHRINE, OfferSource.SHOP]
	return keeps.has(_offer_source)


## Whether this board may be rerolled. A Shrine's menu is carved into the shrine (docs §8), and
## the docs §2 starting pick happens before the player has any gold, so neither offers one.
func _can_reroll_offer(live: Player, free_reroll: bool) -> bool:
	if _offer_source == OfferSource.SHRINE:
		return false
	if _offer_source == OfferSource.STARTING_PASSIVE and not free_reroll:
		return live.gold >= _reroll_cost()
	return true


## Makes the offer modal: the run stops while the cards are up. Otherwise the player walks and
## attacks behind them, the confirm key also rolls the character (`ui_accept` shares Space and
## gamepad A with `dodge`), and interact opens a second chest whose reward is discarded. The
## picker is PROCESS_MODE_ALWAYS, so only the run freezes. Player input is withdrawn too: the
## pause already stops polled actions, and this makes the refusal explicit to anything asking.
func _hold_pause() -> void:
	_set_player_input(false)
	var tree := get_tree()
	if tree == null or _paused_for_offer or tree.paused:
		return
	_paused_for_offer = true
	tree.paused = true


## Hands the run back. Never unpauses a pause somebody else owns (the pause menu, a test).
func _release_pause() -> void:
	_set_player_input(true)
	if not _paused_for_offer:
		return
	_paused_for_offer = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false


## Takes the player's input away while an offer is up and gives it back afterwards; a dead
## player never gets it back (`_die` took it for good).
func _set_player_input(enabled: bool) -> void:
	var live := player()
	if live == null or not is_instance_valid(live):
		return
	if enabled and live.state == Player.State.DEAD:
		return
	live.input_enabled = enabled


## What taking `offer` would displace (`RewardEffects.needs_replace`), for the picker.
func _needs_replace(offer: Variant) -> Array:
	return RewardEffects.needs_replace(player(), offer)


## What the price of a cursed board's prize would displace: the picker asks this second, after
## the prize's own slot question, so a Legendary ring bought with a Curse costs a ring the
## player picked and a passive the player picked - never one of each in silence.
func _price_replace(_offer: Variant) -> Array:
	return RewardEffects.curse_needs_replace(player(), _pending_curse)


func _reroll_cost() -> int:
	if _offer_source == OfferSource.SHOP and _offer_node is Shop:
		return (_offer_node as Shop).reroll_price()
	var base := Shop.reroll_base_price()
	return int(round(base * pow(Shop.reroll_growth(), _rerolls_this_floor)))


## Resolves the answers the picker came back with. A source may charge, refuse or have nothing
## to hand over; granting is `_apply_offer`'s and nothing else's. The shop used to grant its own
## purchase with a hard-coded -1, throwing away the answer the trade view had just asked for.
func _on_offer_chosen(offer: Variant, replace_index: int, price_index: int) -> void:
	var live := player()
	if live == null:
		_finish_offer()
		return
	if _offer_source == OfferSource.SHRINE:
		if _use_shrine(offer, live):
			_finish_offer()
		return
	var taken: Variant = offer
	if _offer_source == OfferSource.SHOP:
		if not _charge_shop(offer, live):
			return
		taken = _take_from_shop(offer)
	if taken != null:
		_apply_offer(taken, replace_index, live, price_index)
	_finish_offer()


## Applies a taken offer. `replace_index` answers what the offer itself displaces (which ring,
## which ability slot); `price_index` answers what its price displaces (which passive a cursed
## board's Curse takes). Both are -1 when nothing had to be given up.
func _apply_offer(offer: Variant, replace_index: int, live: Player, price_index: int = -1) -> void:
	if offer is Dictionary:
		var entry := offer as Dictionary
		live.add_stat(StringName(str(entry.get("stat", &"might"))), int(entry.get("points", 1)))
	elif offer is ItemInstance:
		# A ring family has two slots, so `replace_index` is a real answer and Ring 2 is
		# reachable - on a cursed board too, where the Curse's own slot is `price_index`.
		RewardEffects.grant_item(live, offer as ItemInstance, replace_index)
		if _offer_kind == Chest.Kind.CURSED:
			RewardEffects.attach_curse(
				live.ability_slots as AbilitySlots, _pending_curse, price_index
			)
			_pending_curse = null
	elif offer is Ability:
		RewardEffects.grant_ability(live, offer as Ability, replace_index)
	elif offer is int or offer is float:
		live.add_gold(int(offer))


## Charges a shop offer's price. False only when the player cannot pay it, which is the one
## answer that leaves the board open; a board whose Shop has gone charges nothing and agrees.
func _charge_shop(offer: Variant, live: Player) -> bool:
	var shop := _offer_node as Shop
	if shop == null:
		return true
	var index := _offers.find(offer)
	if index < 0:
		return true
	var price := shop.prices[index] if index < shop.prices.size() else 0
	if price > 0 and not live.spend_gold(price):
		EventBus.toast.emit("Not enough gold", 1.2)
		return false
	return true


## Takes the bought entry off the counter and hands it back for `_apply_offer` to grant. Null
## when there is nothing to take (no Shop, or a foreign offer): the board then grants nothing.
func _take_from_shop(offer: Variant) -> Variant:
	var shop := _offer_node as Shop
	if shop == null:
		return null
	var index := _offers.find(offer)
	return null if index < 0 else shop.take_offer(index)


func _use_shrine(offer: Variant, live: Player) -> bool:
	var index := _offers.find(offer)
	if index < 0 or index >= _shrine_options.size():
		return true
	return RewardEffects.apply_shrine_option(_shrine_options[index], live)


func _on_offer_rerolled() -> void:
	var live := player()
	if live == null:
		return
	var free_reroll := (
		bool(live.flags.get("free_reroll_per_floor", false)) and not _free_reroll_used
	)
	# A Shrine's options are the shrine's, not a rolled board: rerolling one used to replace the
	# cards with plain stat orbs while `_shrine_options` stayed behind, so card N still charged
	# option N's price and granted option N's buff. There is nothing here to reroll.
	if not _can_reroll_offer(live, free_reroll):
		return
	var cost := _reroll_cost()
	if free_reroll:
		_free_reroll_used = true
	elif not live.spend_gold(cost):
		EventBus.toast.emit("Not enough gold", 1.2)
		return
	_offers_rerolled = true
	if _offer_source == OfferSource.STARTING_PASSIVE:
		_rerolls_this_floor += 1
		_offers = _roll_starting_passives()
		_remember_board(_offer_source, null, _offers)
		_show_offers(StartingPassive.CONTEXT)
		return
	if _offer_source == OfferSource.SHOP:
		var shop := _offer_node as Shop
		if shop != null:
			shop.mark_rerolled()
			var loot := rng.stream(&"loot")
			var offers: Array = []
			for _i in range(Shop.MAX_OFFERS):
				var item := ItemGenerator.generate(
					item_registry, floor_index, loot, live.stats.get_value(&"luck")
				)
				if item != null:
					offers.append(item)
			shop.stock(offers, SHOP_BASE_PRICE + floor_index * SHOP_PRICE_PER_FLOOR)
			_offers = []
			for entry: RefCounted in shop.offers:
				_offers.append(entry)
			_show_offers(ChestOffers.shop_context(shop))
			return
	_rerolls_this_floor += 1
	_offers = _roll_offers(_offer_kind)
	# The board the player paid for is the board they come back to, rerolled flag and all.
	_remember_board(_offer_source, _offer_node, _offers)
	_show_offers()


func _on_offer_skipped() -> void:
	if _offer_source == OfferSource.STARTING_PASSIVE:
		# Docs §2 makes this a choice, not an option: re-show it rather than start floor 1
		# with both passive slots empty. ChestUi closes itself right after it emits `skipped`,
		# so the same cards go back up on the next idle frame, not inside the emission.
		EventBus.toast.emit("Pick a starting passive", 1.5)
		_show_offers.call_deferred(StartingPassive.CONTEXT)
		return
	# Only taking something spends an Altar, a Shrine or a Shop; closing the board used to run
	# the `_finish_offer()` a pick does and destroy it (docs §5.1, §8).
	if _skip_keeps_offer():
		# The board stays recorded against the altar: unanswered, so walking back shows it again.
		_clear_offer_state()
		SaveManager.request_autosave()
		return
	var live := player()
	if live != null and _offer_source == OfferSource.CHEST:
		live.add_gold(skip_gold())
	_finish_offer()


func _finish_offer() -> void:
	if _offer_source == OfferSource.STARTING_PASSIVE:
		_starting_passive_pending = false
	# Answered: the board is spent with the thing that rolled it.
	FloorRestore.drop_board(_boards, int(_offer_source), _offer_node)
	if _offer_node != null and is_instance_valid(_offer_node):
		if _offer_node.has_method(&"mark_taken"):
			_offer_node.call(&"mark_taken")
		if _offer_node is Altar:
			(_offer_node as Altar).consume()
		elif _offer_node is Shrine:
			(_offer_node as Shrine).consume()
	_clear_offer_state()
	SaveManager.request_autosave()
	# A resume can owe two picks at once (the opening passive and a chest the save caught
	# mid-offer); the second one goes up as soon as the first is answered.
	_resume_chest_offer()


## Re-opens the chest picker a resumed run still owes the player. The chest was deliberately left
## unspent by the save, so nothing has been granted and nothing consumed, and the board comes back
## card for card out of `RunState.offer_boards` — rolling it fresh here is what made Alt-F4 ->
## Continue a better reroll than the 25g one. No-op outside a resume, or while another is up.
func _resume_chest_offer() -> void:
	if _pending_chest_offer_room < 0 or not _run_active or is_offer_open():
		return
	var room := floor_root().get_room(_pending_chest_offer_room) if floor_root() != null else null
	_pending_chest_offer_room = -1
	var chest := room.chest if room != null else null
	if chest == null or not is_instance_valid(chest) or not chest.reopen_offer():
		return
	_on_chest_opened(chest)


## Room whose chest offer is unanswered right now, or -1. Written into the save so an abnormal
## exit with the picker on screen resumes owing the pick instead of eating the reward.
func _chest_offer_room() -> int:
	if _offer_source == OfferSource.CHEST and _offer_node is Chest:
		return FloorRestore.room_id_of(_offer_node)
	return _pending_chest_offer_room


func _clear_offer_state() -> void:
	_release_pause()
	_offer_source = OfferSource.NONE
	_offer_node = null
	_offers = []
	_shrine_options = []
	_offers_rerolled = false
	_pending_curse = null


# ---------------------------------------------------------------- run stats & end


func _on_enemy_died(enemy: Node2D, killer: Node2D) -> void:
	if not _run_active:
		return
	if killer != null and is_instance_valid(killer) and killer.is_in_group(&"player"):
		_tally.record_kill()
		SaveManager.increment(&"kills")
	var def := enemy.get(&"def") as EnemyDef
	if def != null:
		var counter := _faction_counter(def.faction)
		if counter != &"":
			SaveManager.increment(counter)
		# Only the enemies `_spawn_pack`/`_spawn_boss` placed carry the tag, so a split, a
		# summon or a mimic's enemy never thins the pack a resume rebuilds.
		if enemy.has_meta(&"pack_room"):
			_packs.record(int(enemy.get_meta(&"pack_room")), def.id)


static func _faction_counter(faction: EnemyDef.Faction) -> StringName:
	match faction:
		EnemyDef.Faction.CLOWNS:
			return &"clowns_killed"
		EnemyDef.Faction.GREYBEARDS:
			return &"greybeards_killed"
		EnemyDef.Faction.TINKERERS:
			return &"tinkerers_killed"
		_:
			return &""


func _on_player_damaged(amount: int, source: Node2D) -> void:
	if _run_active:
		_tally.record_damage(amount, source)


func _on_gold_changed(total: int) -> void:
	if _run_active:
		_tally.record_gold(total)


func _on_player_died() -> void:
	if not _run_active:
		return
	_run_active = false
	# Death is permanent (docs section 1), so the save dies with the player, before the delay
	# that lets the death animation play. Closing the window inside that delay quits the
	# process without reaching _finish_run(), and a save left on disk would resurrect the run.
	SaveManager.cancel_autosave()
	SaveManager.delete_run()
	var token := _run_token
	await get_tree().create_timer(DEATH_DELAY).timeout
	# A run started during the death delay (retry seed, a test) owns the game now; finishing
	# the dead one here would tear its scene down and overwrite `pending_summary`.
	if token != _run_token:
		return
	_finish_run(false)


func _end_run(victory: bool, abandoned: bool = false) -> void:
	_run_active = false
	_finish_run(victory, abandoned)


## Ends the run and builds the summary. `abandoned` separates "walked away" from "died": both
## are losses and both count as runs, but only one of them is a death, and a screen that says
## YOU DIED to a player who pressed Abandon is reporting something that did not happen. The
## profile keeps the same distinction in `ABANDON_COUNTER`, so lifetime deaths are
## `runs - wins - abandons` rather than every loss.
func _finish_run(victory: bool, abandoned: bool = false) -> void:
	SaveManager.delete_run()
	var theme := Desktop.palette.name if Desktop.palette != null else ""
	if abandoned:
		SaveManager.increment(ABANDON_COUNTER)
	SaveManager.record_run_end(
		victory, floor_index, class_def.id if class_def != null else &"fighter", theme
	)
	EventBus.run_ended.emit(victory)
	pending_summary = (
		_tally
		. to_summary(
			victory,
			{
				"floor": floor_index + 1,
				"seed": run_seed,
				"theme": theme,
				"class": class_def.display_name if class_def != null else "",
				"tracks": Music.tracks_played(),
				"abandoned": abandoned,
			}
		)
	)
	# Read before `_teardown_run()` frees the player.
	pending_summary.merge(RunBuild.snapshot(player()))
	_teardown_run()
	_show_main()


## `SaveManager.state_provider`: the snapshot written by every autosave. Null outside a run.
func build_run_state() -> RunState:
	if not _run_active or class_def == null:
		return null
	var state := RunState.new()
	state.run_seed = run_seed
	state.class_id = class_def.id
	state.floor_index = floor_index
	state.current_room_id = _current_room_id
	state.cleared_room_ids = _cleared_rooms.duplicate()
	state.rerolls_this_floor = _rerolls_this_floor
	state.free_reroll_used = _free_reroll_used
	state.defeated_spawns = _packs.to_entries()
	state.chest_offer_room_id = _chest_offer_room()
	state.offer_boards = FloorRestore.offer_boards_to_dicts(
		_boards, int(OfferSource.STARTING_PASSIVE)
	)
	FloorRestore.capture(floor_root(), state)
	FloorRestore.capture_loose_loot(floor_root(), FloorDrops.spawner_of(game), state)
	var live := player()
	if live != null:
		state.player = live.to_dict()
	state.kills = _tally.kills
	state.damage_taken = _tally.damage_taken
	state.gold_earned = _tally.gold_earned
	state.time_played = _tally.elapsed()
	state.theme_name = Desktop.palette.name if Desktop.palette != null else ""
	state.tracks_played = Music.tracks_played()
	state.starting_passive_pending = _starting_passive_pending
	state.rng_states = rng.states(PERSISTENT_RNG_STREAMS) if rng != null else {}
	state.gen_params = FloorRestore.gen_params_to_dict(gen_params)
	return state
