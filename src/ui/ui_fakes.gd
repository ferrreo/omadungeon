## Deterministic fake game objects for the UI gallery and UI tests (never used in play).
class_name UiFakes
extends RefCounted

## A ten-stat comparison, wider than a card can show: the extra rows must collapse.
const LONG_COMPARE: Dictionary = {
	&"might": 3.0,
	&"vitality": 2.0,
	&"precision": -1.0,
	&"arcana": 4.0,
	&"swiftness": 2.0,
	&"fortune": 1.0,
	&"max_hp": 25.0,
	&"armor": -6.0,
	&"crit_chance": 0.08,
	&"crit_mult": 0.5,
}

## Blurbs the shipped abilities really carry, keyed by id. A gallery whose cards all read
## "Deals damage in a wide arc around you." is a gallery that cannot show whether two cards
## side by side are readable, which is the whole question the swap view exists to answer.
const ACTIVE_BLURBS: Dictionary = {
	"fireball": "Hurls a bolt that bursts on impact and sets everything nearby alight.",
	"frost_nova": "Freezes every enemy around you; three stacks and they stop moving.",
	"whirlwind": "Spins through a wide arc, striking everything within reach twice.",
	"shadowstep": "Blink behind the nearest enemy and land a guaranteed critical hit.",
}
## Damage the fake actives carry, so a before/after row has two different numbers to print.
const ACTIVE_DAMAGE: Dictionary = {
	"fireball": 26.0,
	"frost_nova": 14.0,
	"whirlwind": 32.0,
	"shadowstep": 40.0,
}

## Atlas each fake gear slot borrows its picture from, so a fake card carries the same picture
## the real board would. Rings and trinkets have no atlas: they are drawn by `ProcSprite` from
## the instance's own seed, which is what `PROC_FAMILIES` asks for.
const ATLAS_CELLS: Dictionary = {
	ItemBase.Slot.WEAPON: "res://assets/sprites/items/weapons.png",
	ItemBase.Slot.ARMOR: "res://assets/sprites/items/armor.png",
}
## The fakes each slot can be built as: the display name and - where the slot has an atlas -
## the cell of `tools/art/item_cells.json` it is drawn from.
##
## Entry 0 is what every caller gets unless it asks for another, and is what the equipped gear
## of `make_player` is: the fakes are fixtures as well as gallery furniture, and several UI
## tests read the worn weapon's name out of a card heading.
##
## The later entries exist because one fake per slot cannot answer the question the gallery is
## for. A reviewer looking at the offer board asks "do any two item icons collide?", and a trade
## view showing the same rusty sword on both sides of the arrow tells them nothing; `make_offers`
## therefore offers a different object from the one the fake player is wearing. Names track the
## art (`item_cells.json` is the contract `tests/unit/art/art_assets_test.gd` pins), so a card
## that says "Iron Plate" shows the iron plate.
const FAKE_GEAR: Dictionary = {
	ItemBase.Slot.WEAPON:
	[
		{"name": "Rusty Sword", "cell": 0},
		{"name": "Longsword", "cell": 1},
		{"name": "Battleaxe", "cell": 2},
		{"name": "Greatsword", "cell": 12},
	],
	ItemBase.Slot.ARMOR:
	[
		{"name": "Leather Jerkin", "cell": 0},
		{"name": "Chain Mail", "cell": 2},
		{"name": "Iron Plate", "cell": 4},
		{"name": "Adamant Plate", "cell": 5},
	],
	ItemBase.Slot.RING:
	[
		{"name": "Copper Ring", "cell": -1},
		{"name": "Signet Ring", "cell": -1},
		{"name": "Band of Embers", "cell": -1},
		{"name": "Obsidian Band", "cell": -1},
	],
	ItemBase.Slot.TRINKET:
	[
		{"name": "Lucky Coin", "cell": -1},
		{"name": "Cracked Die", "cell": -1},
		{"name": "Brass Compass", "cell": -1},
		{"name": "Broken Watch", "cell": -1},
	],
}
## The class every fake player is: the one everyone starts with.
const CLASS_PATH := "res://data/classes/fighter.tres"
## `ItemBase.proc_sprite_family` per slot for the slots the atlases do not cover.
const PROC_FAMILIES: Dictionary = {
	ItemBase.Slot.RING: &"ring",
	ItemBase.Slot.TRINKET: &"trinket",
}


## A stand-in player exposing the duck-typed fields the HUD and pause menu read.
class FakePlayer:
	extends Node2D

	## Mirrors `Player.potion_used`, so the HUD's heal floater has something to listen to.
	signal potion_used(amount: float)

	var health: Health
	var stats: Stats = Stats.new()
	var gold: int = 137
	var potions: int = 2
	var max_potions: int = 2
	var equipment: FakeEquipment = FakeEquipment.new()
	var ability_slots: FakeSlots = FakeSlots.new()
	var status: FakeStatus = FakeStatus.new()
	## Duck-typed stand-in for `Player.weapon_controller`, so the HUD's weapon-skill slot has
	## something to show.
	var weapon_controller: FakeWeaponController = FakeWeaponController.new()
	## The class the build screen names and reads its base stats from.
	var class_def: ClassDef = load(CLASS_PATH) as ClassDef

	func _init() -> void:
		health = Health.new()
		health.max_hp = 120.0
		add_child(health)
		add_child(status)
		add_child(weapon_controller)

	## `Health._ready()` resets hp to max_hp, so the wounded value is applied afterwards:
	## the gallery has to show a damaged (and, at 24/120, danger-pulsing) bar.
	func _ready() -> void:
		health.max_hp = 120.0
		health.hp = 24.0
		stats.add_primary(&"vitality", 6)
		stats.add_primary(&"might", 6)
		stats.add_primary(&"precision", 2)
		stats.add_primary(&"arcana", 1)
		stats.add_primary(&"swiftness", 3)
		stats.add_primary(&"fortune", 2)


## A frozen StatusController stand-in: the HUD's `StatusRow` only reads `effects`, and a
## gallery screenshot must not have durations ticking down between captures.
class FakeStatus:
	extends Node
	var effects: Dictionary = {}

	## Adds one non-ticking effect at `fraction` of its duration left.
	func add(kind: StatusEffect.Kind, stacks: int = 1, fraction: float = 0.7) -> void:
		var effect := StatusEffect.make(kind, 6.0, 4.0)
		effect.stacks = stacks
		effect.remaining = 6.0 * fraction
		effects[kind] = effect


class FakeEquipment:
	extends RefCounted
	var slots: Dictionary = {}


## Only what `Hud._bind_weapon_skill` reads: the skill and the signal that says it changed.
class FakeWeaponController:
	extends Node
	signal weapon_changed(weapon: Resource)
	var skill: ActiveAbility


class FakeSlots:
	extends RefCounted
	signal changed
	var actives: Array[Resource] = []
	var passives: Array[Resource] = []
	## Uncounted passives: the class innate and any legendary unique effect.
	var innates: Array[Resource] = []


static func make_affix(
	id: String, stat: StringName, mode: Affix.Mode, lo: float, hi: float
) -> Affix:
	var a := Affix.new()
	a.id = StringName(id)
	a.stat = stat
	a.mode = mode
	a.min_value = lo
	a.max_value = hi
	return a


## A fake item. Weapons get a real `WeaponBase` with damage/rate/reach that grows with rarity,
## because the weapon block and its vs-equipped deltas are the whole point of an item card and
## a bare `ItemBase` would render a weapon with no numbers at all.
static func make_item(
	rng: RandomNumberGenerator, rarity: int, slot: ItemBase.Slot, variant: int = 0
) -> ItemInstance:
	var base: ItemBase = WeaponBase.new() if slot == ItemBase.Slot.WEAPON else ItemBase.new()
	var gear := gear_for(slot, variant)
	base.id = StringName(str(gear["name"]).to_lower().replace(" ", "_"))
	base.display_name = str(gear["name"])
	base.slot = slot
	# The real board draws a sword, a jerkin and a ring as three different pictures - weapons
	# and armour from their own atlases, rings and trinkets as per-instance proc sprites. The
	# fakes used to wear one rarity gem in three hues, and then one picture per slot, so the
	# gallery could not show whether two weapons a player might hold side by side collide.
	base.icon = _atlas_icon(slot, int(gear["cell"]))
	base.proc_sprite_family = StringName(str(PROC_FAMILIES.get(slot, &"")))
	if slot == ItemBase.Slot.WEAPON:
		base.implicit_flat = {&"might": 2}
		var weapon := base as WeaponBase
		weapon.base_damage = 8.0 + 4.0 * rarity
		weapon.attacks_per_second = 2.0 - 0.2 * rarity
		weapon.range_px = 20.0 + 4.0 * rarity
	elif slot == ItemBase.Slot.ARMOR:
		base.implicit_flat = {&"armor": 6}
	var item := ItemInstance.new()
	item.uid = rng.randi() % 100000
	item.base = base
	item.rarity = rarity as ItemInstance.Rarity
	var pool: Array[Affix] = [
		make_affix("sharp", &"might", Affix.Mode.FLAT, 1, 3),
		make_affix("swift", &"move_speed", Affix.Mode.PERCENT, 0.05, 0.12),
		make_affix("keen", &"crit_chance", Affix.Mode.PERCENT, 0.03, 0.08),
		make_affix("vital", &"max_hp", Affix.Mode.FLAT, 5, 15),
	]
	var prefixes: PackedStringArray = ["Sharp", "Swift", "Keen", "Vital"]
	for i in rarity + 1:
		var idx := (i + rng.randi() % 2) % pool.size()
		item.affixes.append({"affix": pool[idx], "value": pool[idx].roll(rng)})
	item.display_name = "%s %s" % [prefixes[rarity], base.display_name]
	if rarity == ItemInstance.Rarity.LEGENDARY:
		# A registered unique, so the compare screen shows the effect's sentence in full: the
		# old fake named one the registry did not know and every legendary read "Carries a
		# unique effect", which is the cut the compare screen exists to remove.
		item.display_name += " of Root"
		item.unique_effect = &"sudo"
	return item


## Entry `variant` of `slot`'s fakes, clamped, so a caller asking for one the table has no
## entry for gets the last rather than nothing.
static func gear_for(slot: ItemBase.Slot, variant: int) -> Dictionary:
	var entries: Array = FAKE_GEAR.get(slot, [])
	if entries.is_empty():
		return {"name": "Curio", "cell": -1}
	return entries[clampi(variant, 0, entries.size() - 1)] as Dictionary


## Cell `index` of the shipped atlas for `slot`; null for a slot with no atlas or a fake with
## no cell, which is how `ProcSprite` gets asked for the picture instead.
static func _atlas_icon(slot: ItemBase.Slot, index: int) -> Texture2D:
	if index < 0 or not ATLAS_CELLS.has(slot):
		return null
	var sheet := load(str(ATLAS_CELLS[slot])) as Texture2D
	if sheet == null:
		return null
	var cell := AtlasTexture.new()
	cell.atlas = sheet
	cell.region = Rect2(index * UiTheme.ICON_CELL, 0, UiTheme.ICON_CELL, UiTheme.ICON_CELL)
	return cell


static func make_active(
	id: String, name: String, cooldown: float, left: float = 0.0
) -> ActiveAbility:
	var a := ActiveAbility.new()
	a.id = StringName(id)
	a.display_name = name
	a.description = str(ACTIVE_BLURBS.get(id, "Deals damage in a wide arc around you."))
	a.cooldown = cooldown
	a.damage = float(ACTIVE_DAMAGE.get(id, 20.0))
	a.cooldown_left = left
	a.icon = UiTheme.ability_icon(a.id)
	if a.icon == null:
		a.icon = UiTheme.icon(UiTheme.Icon.ARCANA)
	return a


static func make_passive(id: String, name: String, description: String) -> PassiveAbility:
	var p := PassiveAbility.new()
	p.id = StringName(id)
	p.display_name = name
	p.description = description
	p.icon = UiTheme.ability_icon(p.id)
	if p.icon == null:
		p.icon = UiTheme.icon(UiTheme.Icon.FORTUNE)
	return p


static func make_player() -> FakePlayer:
	var player := FakePlayer.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	player.equipment.slots = {
		"weapon": make_item(rng, ItemInstance.Rarity.RARE, ItemBase.Slot.WEAPON),
		"armor": make_item(rng, ItemInstance.Rarity.COMMON, ItemBase.Slot.ARMOR),
		"ring_1": make_item(rng, ItemInstance.Rarity.EPIC, ItemBase.Slot.RING),
		# Both deliberately empty: an offer landing in a free slot has to say so instead of
		# printing a comparison against nothing, and `chest_ui_test` presses one press on a
		# trinket to prove it.
		"ring_2": null,
		"trinket": null,
	}
	player.ability_slots.actives = [
		make_active("fireball", "Fireball", 6.0, 2.5), make_active("frost_nova", "Frost Nova", 9.0)
	]
	player.ability_slots.passives = [
		make_passive("thorns", "Thorns", "Reflect 20% of melee damage taken."),
		make_passive("vampiric", "Vampiric", "3% lifesteal on every hit."),
	]
	player.ability_slots.innates = [
		make_passive("second_wind", "Second Wind", "Heal 15% of max HP on a room clear.")
	]
	player.weapon_controller.skill = make_active("whirlwind", "Lunge", 4.0, 1.6)
	return player


## `make_player()` with both ring slots worn, which is the case an offered ring has to ask
## about: two candidates, so the trade view pages them ("Slot 1 of 2"). Kept apart from
## `make_player` deliberately - that one's free ring slot is what proves an offer landing in an
## empty slot says so instead of printing a comparison against nothing.
static func make_player_two_rings() -> FakePlayer:
	var player := make_player()
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	player.equipment.slots["ring_2"] = make_item(
		rng, ItemInstance.Rarity.COMMON, ItemBase.Slot.RING
	)
	return player


## Offers for a chest of `kind` (ChestUi.Kind).
static func make_offers(kind: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	match kind:
		ChestUi.Kind.ITEM:
			# Variants 1 and 2 for the gear the fake player already wears, so the trade view
			# shows a longsword against their rusty sword and iron plate against their jerkin -
			# two different pictures on the two sides of the arrow, which is what makes the
			# screen usable for judging whether any two item icons collide.
			return [
				make_item(rng, ItemInstance.Rarity.COMMON, ItemBase.Slot.WEAPON, 1),
				make_item(rng, ItemInstance.Rarity.EPIC, ItemBase.Slot.ARMOR, 2),
				make_item(rng, ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.RING),
			]
		ChestUi.Kind.ABILITY:
			return [
				make_active("whirlwind", "Whirlwind", 8.0),
				make_passive("glass_cannon", "Glass Cannon", "+40% damage, -30% max HP."),
				make_active("shadowstep", "Shadowstep", 7.0),
			]
		ChestUi.Kind.GOLD:
			return [40, 65, 25]
	return [
		{"stat": &"might", "points": 1},
		{"stat": &"vitality", "points": 2},
		{"stat": &"fortune", "points": 1},
	]


static func chest_context(player: FakePlayer) -> Dictionary:
	var stats: Dictionary = {}
	for stat: StringName in Stats.PRIMARY:
		stats[stat] = int(player.stats.get_value(stat))
	return {
		"current_stats": stats,
		"compare": func(item: ItemInstance) -> Dictionary: return _compare(player, item),
		"equipped": func(item: ItemInstance) -> ItemInstance: return equipped_for(player, item),
		"reroll_cost": 25,
		"free_reroll": false,
		"skip_gold": 10,
		"gold": player.gold,
		"needs_replace": func(offer: Variant) -> Array: return _needs_replace(player, offer),
	}


## Shop context: per-offer prices (one unaffordable) and a deliberately long comparison,
## so the gallery exercises the price line and the card's line caps.
static func shop_context(player: FakePlayer) -> Dictionary:
	var stats: Dictionary = {}
	for stat: StringName in Stats.PRIMARY:
		stats[stat] = int(player.stats.get_value(stat))
	return {
		"shop": true,
		"prices": [250, 80, 35],
		"reroll_cost": 40,
		"gold": player.gold,
		"current_stats": stats,
		"compare": func(_item: ItemInstance) -> Dictionary: return LONG_COMPARE,
		# The counter compares against the same worn gear a chest does. Without this the shop
		# was the one board in the gallery that could not name what it would displace, and the
		# screenshot showed three cards carrying the same unlabelled column of deltas.
		"equipped": func(item: ItemInstance) -> ItemInstance: return equipped_for(player, item),
	}


## A real `Equipment` wearing the fake player's gear, for widgets typed against the items
## module (`ItemTooltip`) rather than duck-typed.
static func worn_gear(player: FakePlayer) -> Equipment:
	var gear := Equipment.new()
	for key: String in player.equipment.slots.keys():
		var worn: Variant = player.equipment.slots[key]
		if worn is ItemInstance:
			gear.equip(worn as ItemInstance, player.stats)
	return gear


## The worn item `item` would replace, or null when a slot of that type is still free (the
## real `Equipment.target_slot()` fills an empty slot before it displaces anything).
static func equipped_for(player: FakePlayer, item: ItemInstance) -> ItemInstance:
	var keys := slot_keys(item.slot())
	for key: String in keys:
		if player.equipment.slots.get(key) == null:
			return null
	return player.equipment.slots[keys[0]] as ItemInstance


## Fake equipment keys an item of `slot` type can occupy (mirrors `Equipment.slot_names_for`).
static func slot_keys(slot: ItemBase.Slot) -> PackedStringArray:
	match slot:
		ItemBase.Slot.WEAPON:
			return PackedStringArray(["weapon"])
		ItemBase.Slot.ARMOR:
			return PackedStringArray(["armor"])
		ItemBase.Slot.RING:
			return PackedStringArray(["ring_1", "ring_2"])
	return PackedStringArray(["trinket"])


static func _compare(player: FakePlayer, item: ItemInstance) -> Dictionary:
	var deltas: Dictionary = {}
	for line: Dictionary in item.affixes:
		var affix: Affix = line["affix"]
		deltas[affix.stat] = float(deltas.get(affix.stat, 0.0)) + float(line["value"])
	var current: Variant = null
	for key: String in player.equipment.slots.keys():
		var owned: Variant = player.equipment.slots[key]
		if owned is ItemInstance and (owned as ItemInstance).slot() == item.slot():
			current = owned
			break
	if current is ItemInstance:
		for line: Dictionary in (current as ItemInstance).affixes:
			var affix: Affix = line["affix"]
			deltas[affix.stat] = float(deltas.get(affix.stat, 0.0)) - float(line["value"])
	return deltas


## What taking `offer` would displace, the way `RunManager._needs_replace` answers it: a full
## pair of ability slots, or every full slot of the family an item goes into.
static func _needs_replace(player: FakePlayer, offer: Variant) -> Array:
	if offer is ActiveAbility and player.ability_slots.actives.size() >= 2:
		return player.ability_slots.actives.duplicate()
	if offer is PassiveAbility and player.ability_slots.passives.size() >= 2:
		return player.ability_slots.passives.duplicate()
	if offer is ItemInstance:
		return worn_pair(player, offer as ItemInstance)
	return []


## Every worn item an offered item would have to displace (mirrors
## `Equipment.occupied_items_for`): both rings when both hands are full, one piece for the
## single-slot families, nothing while a slot of that family is free.
static func worn_pair(player: FakePlayer, item: ItemInstance) -> Array:
	var out: Array = []
	var keys := slot_keys(item.slot())
	for key: String in keys:
		if player.equipment.slots.get(key) == null:
			return []
		out.append(player.equipment.slots[key])
	return out


## A half-explored floor, shaped so one screenshot shows every minimap channel at once: two
## cleared rooms, the room you are standing in, a fogged treasure room (still a secret) and
## the stairs one corridor away from somewhere you have been (no longer a secret).
## `id` and `visited` are what `MinimapModel.rooms` really feeds; leaving them out made the
## gallery's map thirteen identical fog stubs, which is not what the game draws.
static func minimap_rooms() -> Array[Dictionary]:
	return [
		{
			"id": 0,
			"rect": Rect2i(0, 6, 7, 6),
			"cleared": true,
			"visited": true,
			"current": false,
			"type": 0
		},
		{
			"id": 1,
			"rect": Rect2i(10, 4, 9, 8),
			"cleared": true,
			"visited": true,
			"current": false,
			"type": 1
		},
		{
			"id": 2,
			"rect": Rect2i(22, 8, 7, 5),
			"cleared": false,
			"visited": true,
			"current": true,
			"type": 2
		},
		{
			"id": 3,
			"rect": Rect2i(12, 16, 6, 6),
			"cleared": false,
			"visited": false,
			"current": false,
			"type": 4
		},
		{
			"id": 4,
			"rect": Rect2i(32, 2, 8, 7),
			"cleared": false,
			"visited": false,
			"current": false,
			"type": 8
		},
	]


static func minimap_edges() -> Array[Vector4i]:
	return [
		Vector4i(3, 9, 14, 8),
		Vector4i(14, 8, 25, 10),
		Vector4i(14, 8, 15, 19),
		Vector4i(25, 10, 36, 5)
	]


static func summary_data(victory: bool) -> Dictionary:
	return {
		"victory": victory,
		"floor": 7 if victory else 4,
		"kills": 212,
		"gold": 1180,
		"time": 1463.0,
		"seed": 20240911,
		"theme": Desktop.palette.name if Desktop.palette != null else "Fallback",
		"class": "Fighter",
		"damage_taken": 0 if victory else 418,
		"killer": "" if victory else "Config Gremlin",
		"tracks":
		# The radio's own effect on the floors it built. Without it the summary's music line is
		["Neon Corridors - Kai Nakamura", "Dotfiles - The Greybeards", "Rm -rf - Clownware"],
		# a list of song titles, which is the half of that section the screen already had.
		"music_floors":
		[
			{"floor": 1, "title": "Neon Corridors", "energy": 0.12, "tempo": 96.0, "playing": true},
			{"floor": 2, "title": "Dotfiles", "energy": 0.55, "tempo": 118.0, "playing": true},
			{"floor": 3, "title": "Rm -rf", "energy": 0.93, "tempo": 148.0, "playing": true},
		],
		"innate": "Second Wind",
		"equipment":
		[
			{"slot": "Weapon", "name": "Sharp Rusty Sword", "role": "rarity_rare"},
			{"slot": "Armor", "name": "Vital Leather Jerkin", "role": "rarity_common"},
			{"slot": "Ring 1", "name": "Keen Copper Ring", "role": "rarity_epic"},
			{"slot": "Ring 2", "name": "", "role": ""},
			{"slot": "Trinket", "name": "", "role": ""},
			{"slot": "Skill", "name": "Lunge", "role": "accent"},
		],
		"abilities":
		[
			{"slot": "Active 1", "name": "Fireball II", "role": ""},
			{"slot": "Active 2", "name": "Frost Nova", "role": ""},
			{"slot": "Passive 1", "name": "Thorns", "role": "magic"},
			{"slot": "Passive 2", "name": "Vampiric II", "role": "magic"},
		],
		"stats":
		{
			&"vitality": 9,
			&"might": 11,
			&"precision": 3,
			&"arcana": 1,
			&"swiftness": 5,
			&"fortune": 4,
		},
	}


## A finished victory with nothing left empty: every gear and ability slot filled with names
## the length `ItemGenerator` really produces, the longest class and theme names in the game,
## and the whole playlist. `summary_data()` leaves Ring 2 and Trinket blank and names the
## default theme, so it is the *easy* case - a screen that fits it can still overflow the
## frame on a real finished run, which is exactly what shipped.
static func summary_data_full() -> Dictionary:
	var data := summary_data(true)
	data["class"] = "Oligarch"
	data["theme"] = "Catppuccin Latte"
	data["equipment"] = [
		{"slot": "Weapon", "name": "Gruvboxen Greatsword of the Bear", "role": "rarity_epic"},
		{"slot": "Armor", "name": "Vital Leather Jerkin of Warding", "role": "rarity_rare"},
		{"slot": "Ring 1", "name": "Keen Copper Ring of Fortune", "role": "rarity_epic"},
		{"slot": "Ring 2", "name": "Glimmering Signet of the Archivist", "role": "rarity_rare"},
		{"slot": "Trinket", "name": "Cracked Terminal Fragment", "role": "rarity_common"},
		{"slot": "Skill", "name": "Overwhelming Lunge", "role": "accent"},
	]
	data["abilities"] = [
		{"slot": "Active 1", "name": "Chain Lightning III", "role": ""},
		{"slot": "Active 2", "name": "Frost Nova II", "role": ""},
		{"slot": "Passive 1", "name": "Thorned Carapace", "role": "magic"},
		{"slot": "Passive 2", "name": "Vampiric Resonance II", "role": "magic"},
	]
	data["innate"] = "Buyout Negotiator"
	data["tracks"] = [
		"Neon Corridors - Kai Nakamura",
		"Dotfiles - The Greybeards",
		"Rm -rf - Clownware",
		"Kernel Panic Waltz - Modprobe",
		"No Title Bar - Obstinatus",
	]
	return data


static func profile_stats() -> Dictionary:
	return {
		"runs": 23,
		"wins": 4,
		"kills": 3120,
		"play_time": "6h 12m",
		"best_floor": {"fighter": 7, "ranger": 5, "wizard": 6, "oligarch": 3},
		"theme_wins": {"Tokyo Night": 2, "Gruvbox": 1, "Nord": 1},
	}
