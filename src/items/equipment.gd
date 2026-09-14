## The player's worn items: weapon, armor, ring1, ring2, trinket. Applies/removes item stat
## modifiers on a Stats object, drives legendary unique effects (through an own
## `ItemUniqueHost` node on the player, unless another system has called `set_unique_host`),
## and serialises to/from a Dictionary for saves.
class_name Equipment
extends RefCounted

## A slot changed (`item` is null after an unequip).
signal changed(slot: StringName, item: ItemInstance)
## A legendary's PassiveAbility should be registered (uncounted) with the abilities system.
## Always emitted, whoever hosts the passive: it is an announcement, not a handover. Who hosts
## is decided by `set_unique_host()` and by nothing else (see `_install_unique`).
signal unique_added(passive: PassiveAbility)
signal unique_removed(passive: PassiveAbility)

const SLOTS: Array[StringName] = [&"weapon", &"armor", &"ring1", &"ring2", &"trinket"]

## Worn items keyed by slot name ({&"weapon": ItemInstance, ...}). Public: the HUD, the pause
## menu and the Dotfiles passive read it directly.
var slots: Dictionary = {}
## Player node the unique effects live on. Set by `bind()`, else resolved from the
## `player` group the first time a legendary is equipped.
var holder: Node2D
var _uniques: Dictionary = {}
var _weapon_skill: ActiveAbility
## True once another system has said it will host legendary unique passives itself.
var _external_unique_host: bool = false


## Slot names an item of `slot` type can occupy.
static func slot_names_for(slot: ItemBase.Slot) -> Array[StringName]:
	match slot:
		ItemBase.Slot.WEAPON:
			return [&"weapon"]
		ItemBase.Slot.ARMOR:
			return [&"armor"]
		ItemBase.Slot.RING:
			return [&"ring1", &"ring2"]
	return [&"trinket"]


## Points the unique-effect plumbing at the player that wears these items. Call once after
## creating the Equipment (`Equipment.new()` then `bind(player)`), before equipping.
func bind(player: Node2D) -> void:
	if holder == player:
		return
	holder = player
	if _external_unique_host:
		return
	for passive: PassiveAbility in _uniques.values():
		_host_add(passive)


## Declares who installs a legendary's unique passive. `true` means a caller (the abilities
## module) takes them off `unique_added` and registers them itself; `false`, the default, means
## Equipment hosts them on the player through `ItemUniqueHost`.
##
## This used to be inferred from `unique_added.get_connections().size()`, which is the
## anti-pattern docs/TESTING.md forbids: a listener that only wanted to *watch* silently took
## ownership, and the legendary it was watching stopped doing anything. Ownership is a
## statement somebody makes, not a side effect of observing.
func set_unique_host(external: bool) -> void:
	if _external_unique_host == external:
		return
	_external_unique_host = external
	if external:
		var host := _host(false)
		if host != null:
			for passive: PassiveAbility in _uniques.values():
				host.remove_passive(passive)
		return
	for passive: PassiveAbility in _uniques.values():
		_host_add(passive)


## Whether another system has claimed the unique passives (see `set_unique_host`).
func hosts_uniques_externally() -> bool:
	return _external_unique_host


func get_item(slot_name: StringName) -> ItemInstance:
	return slots.get(slot_name) as ItemInstance


func has_item(slot_name: StringName) -> bool:
	return slots.has(slot_name)


## Every equipped item in SLOTS order.
func items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for slot_name: StringName in SLOTS:
		if slots.has(slot_name):
			out.append(slots[slot_name])
	return out


## Equipped weapon base, or null.
func weapon() -> WeaponBase:
	var item := get_item(&"weapon")
	return item.base as WeaponBase if item != null else null


## Per-equip copy of the weapon's skill (own cooldown state), or null.
func weapon_skill() -> ActiveAbility:
	return _weapon_skill


## ItemBase.Slot ints that still have a free slot (both rings count as one type).
func empty_slots() -> Array[int]:
	var out: Array[int] = []
	for slot: int in [
		ItemBase.Slot.WEAPON, ItemBase.Slot.ARMOR, ItemBase.Slot.RING, ItemBase.Slot.TRINKET
	]:
		for slot_name: StringName in slot_names_for(slot as ItemBase.Slot):
			if not slots.has(slot_name):
				out.append(slot)
				break
	return out


## The ItemBase.Slot an offer would help most: the first slot with a free spot, else the slot
## whose worn item has the lowest rarity. Item chests bias one of their offers to it so a
## player with no armour is never shown three rings (docs §8).
func weakest_slot() -> int:
	var empty := empty_slots()
	if not empty.is_empty():
		return empty[0]
	var best := int(ItemBase.Slot.WEAPON)
	var best_rarity := ItemInstance.RARITY_NAMES.size()
	for slot_name: StringName in SLOTS:
		var item := get_item(slot_name)
		if item == null:
			continue
		if int(item.rarity) < best_rarity:
			best_rarity = int(item.rarity)
			best = int(item.slot())
	return best


## Slot name `item` would go into: the first empty matching slot, else the first matching one.
func target_slot(item: ItemInstance) -> StringName:
	var names := slot_names_for(item.slot())
	for slot_name: StringName in names:
		if not slots.has(slot_name):
			return slot_name
	return names[0]


## Slots an offered `item` would have to displace, in `SLOTS` order: every slot of its family
## when all of them are full, and none at all while any one of them is free.
##
## `target_slot()` cannot answer this. It returns one name - `names[0]` once the family is full
## - so a player offered a third ring was always shown Ring 1 and never asked about Ring 2. A
## family with two slots makes "which one goes?" a real question, and this is the list the
## trade view pages through to ask it.
func occupied_slots_for(item: ItemInstance) -> Array[StringName]:
	var none: Array[StringName] = []
	if item == null:
		return none
	var names := slot_names_for(item.slot())
	for slot_name: StringName in names:
		if not slots.has(slot_name):
			return none
	return names


## The worn items `occupied_slots_for` names, in the order the trade view pages them.
func occupied_items_for(item: ItemInstance) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for slot_name: StringName in occupied_slots_for(item):
		var worn := get_item(slot_name)
		if worn != null:
			out.append(worn)
	return out


## The worn item an offered `item` would displace, or null while its family has a free slot.
## What an offer card prints as "replaces"; the trade view asks `occupied_items_for` instead,
## because on a full ring family this can only ever name the first of the two.
func worn_for(item: ItemInstance) -> ItemInstance:
	return null if item == null else get_item(target_slot(item))


## The slot a trade view's answer picked, or `&""` for "the slot this item would take anyway".
## `choice` indexes `occupied_slots_for(item)`; -1 (nothing was asked) and the default slot both
## answer `&""`, so a caller can keep using its own equip path for everything except the second
## slot of a multi-slot family - which is the one `target_slot()` could never reach.
func chosen_slot(item: ItemInstance, choice: int) -> StringName:
	if item == null or choice < 0:
		return &""
	var names := occupied_slots_for(item)
	if choice >= names.size() or names[choice] == target_slot(item):
		return &""
	return names[choice]


## Equips `item` (into `slot_name`, or `target_slot(item)` when empty) applying its modifiers
## to `stats` (may be null). Returns the replaced item or null.
## Re-equipping an item whose modifiers are already registered on `stats` (save restore) is
## idempotent: the item's owner id is cleared before its modifiers go back on.
func equip(item: ItemInstance, stats: Stats, slot_name: StringName = &"") -> ItemInstance:
	if item == null or item.base == null:
		return null
	var target := slot_name if slot_name != &"" else target_slot(item)
	if not slot_names_for(item.slot()).has(target):
		push_warning("Equipment: %s cannot go in slot %s" % [item.display_name, target])
		return null
	var replaced := _detach(target, stats)
	slots[target] = item
	if stats != null:
		stats.remove_owner(item.owner_id())
		item.apply_to(stats)
	if target == &"weapon":
		var weapon_base := item.base as WeaponBase
		_weapon_skill = (
			weapon_base.skill.duplicate_ability() as ActiveAbility
			if weapon_base != null and weapon_base.skill != null
			else null
		)
	if item.unique_effect != &"":
		_install_unique(target, item.unique_effect)
	changed.emit(target, item)
	EventBus.item_equipped.emit(item.base, item.base.slot_name())
	EventBus.equipment_changed.emit(target, item)
	return replaced


## Removes the item in `slot_name` (modifiers removed from `stats`). Returns it or null.
func unequip(slot_name: StringName, stats: Stats) -> ItemInstance:
	var removed := _detach(slot_name, stats)
	if removed != null:
		changed.emit(slot_name, null)
		EventBus.equipment_changed.emit(slot_name, null)
	return removed


## Unequips everything.
func clear(stats: Stats) -> void:
	for slot_name: StringName in SLOTS:
		unequip(slot_name, stats)


## Stat deltas {stat: delta} if `item` were equipped in place of what its slot holds now.
## Only stats that would actually change are present.
func compare(item: ItemInstance, stats: Stats) -> Dictionary:
	var out: Dictionary = {}
	if item == null or stats == null:
		return out
	var preview := Stats.new()
	preview.from_dict(stats.to_dict())
	var current := get_item(target_slot(item))
	if current != null:
		current.remove_from(preview)
	preview.remove_owner(item.owner_id())
	item.apply_to(preview)
	for stat: StringName in Stats.PRIMARY + Stats.SECONDARY:
		var delta := preview.get_value(stat) - stats.get_value(stat)
		if absf(delta) > 0.0005:
			out[stat] = delta
	return out


## Every ON_HIT_STATUS affix across worn items: [{kind: StatusEffect.Kind, chance: float}].
func on_hit_statuses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: ItemInstance in items():
		for entry: Dictionary in item.affixes:
			var affix: Affix = entry["affix"]
			if affix.mode == Affix.Mode.ON_HIT_STATUS:
				out.append({"kind": affix.status_kind, "chance": float(entry["value"])})
	return out


## Rolls the on-hit statuses for one attack; attach the result to a DamageInfo.
## The magnitude is built from the weapon that swung and the wearer's elemental damage stat,
## so an on-hit affix keeps pace with the weapon ladder instead of staying a floor-1 constant.
func roll_on_hit_statuses(rng: RandomNumberGenerator, source: Node2D = null) -> Array[StatusEffect]:
	var out: Array[StatusEffect] = []
	for entry: Dictionary in on_hit_statuses():
		if rng.randf() < float(entry["chance"]):
			out.append(
				make_on_hit_status(
					entry["kind"] as StatusEffect.Kind, source, weapon(), _stats_of(source)
				)
			)
	return out


## Numbers for a weapon-inflicted status. The DoT kinds tick for a fraction of the weapon's
## hit damage (`ItemTuning`), multiplied by the wearer's `damage_<element>` stat — which is
## what finally gives `damage_fire` / `damage_poison` a weapon-side source to multiply.
## `weapon_base` null means unarmed (an on-hit affix on a ring); `stats` null means no build.
static func make_on_hit_status(
	kind: StatusEffect.Kind,
	source: Node2D = null,
	weapon_base: WeaponBase = null,
	stats: Stats = null
) -> StatusEffect:
	var tuning := ItemTuning.shared()
	var hit := weapon_base.base_damage if weapon_base != null else tuning.unarmed_hit_damage
	var magnitude := tuning.status_dps(kind, hit)
	if magnitude > 0.0 and stats != null:
		magnitude *= maxf(0.0, 1.0 + stats.get_value(damage_stat_for(kind)))
	return StatusEffect.make(kind, tuning.status_duration(kind), magnitude, source)


## The `damage_<element>` stat that scales a status of `kind` ("damage_fire" for BURN).
static func damage_stat_for(kind: StatusEffect.Kind) -> StringName:
	var probe := StatusEffect.make(kind, 0.0, 0.0)
	return StringName("damage_" + String(probe.damage_tag()))


## The Stats of whoever is swinging (the player node), or null.
static func _stats_of(source: Node2D) -> Stats:
	var entity := source as Entity
	return entity.stats if entity != null else null


## Damage multiplier contributed by self-hosted unique effects (sudo's elite bonus).
## Only needed while the abilities module does not own the passives; it returns 1.0 when the
## uniques live in AbilitySlots (which applies them itself).
func outgoing_damage_multiplier(target: Node2D, info: DamageInfo) -> float:
	var host := _host(false)
	return host.multiplier(target, info) if host != null else 1.0


## Unique-effect passives currently driven by this Equipment (one per legendary worn).
func uniques() -> Array[PassiveAbility]:
	var out: Array[PassiveAbility] = []
	for passive: PassiveAbility in _uniques.values():
		out.append(passive)
	return out


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for slot_name: StringName in SLOTS:
		if slots.has(slot_name):
			out[String(slot_name)] = (slots[slot_name] as ItemInstance).to_dict()
	return out


## Rebuilds from `to_dict()` output; applies modifiers to `stats` when given (idempotent, so
## restoring onto a Stats that already carries the saved `item:<uid>` entries is safe).
static func from_dict(
	data: Dictionary, registry: ItemRegistry, stats: Stats = null, player: Node2D = null
) -> Equipment:
	var eq := Equipment.new()
	if player != null:
		eq.bind(player)
	for slot_name: StringName in SLOTS:
		var raw: Variant = data.get(String(slot_name))
		if raw is Dictionary:
			var item := ItemGenerator.from_dict(raw as Dictionary, registry)
			if item != null:
				eq.equip(item, stats, slot_name)
	return eq


func _detach(slot_name: StringName, stats: Stats) -> ItemInstance:
	var removed := get_item(slot_name)
	if removed == null:
		return null
	slots.erase(slot_name)
	if stats != null:
		removed.remove_from(stats)
	if slot_name == &"weapon":
		_weapon_skill = null
	_remove_unique(slot_name)
	return removed


## Installs the unique effect of a newly equipped legendary. The system that called
## `set_unique_host(true)` owns the passive; with nobody claiming it, Equipment hosts it on the
## player itself so legendaries are never inert.
func _install_unique(slot_name: StringName, effect_id: StringName) -> void:
	for existing: PassiveAbility in _uniques.values():
		if existing.id == effect_id:
			return  # one copy of each unique at a time (owner ids would collide)
	var passive := UniqueEffects.find(effect_id)
	if passive == null:
		return
	_uniques[slot_name] = passive
	unique_added.emit(passive)
	if not _external_unique_host:
		_host_add(passive)


func _remove_unique(slot_name: StringName) -> void:
	if not _uniques.has(slot_name):
		return
	var passive: PassiveAbility = _uniques[slot_name]
	_uniques.erase(slot_name)
	var host := _host(false)
	if host != null:
		host.remove_passive(passive)
	unique_removed.emit(passive)


func _host_add(passive: PassiveAbility) -> void:
	var host := _host(true)
	if host == null:
		return
	host.claim(self)
	host.add_passive(passive)


## The player's ItemUniqueHost node (created on demand when `create`).
func _host(create: bool) -> ItemUniqueHost:
	var player := _resolve_holder()
	if player == null or not player.is_inside_tree():
		return null
	return ItemUniqueHost.attach(player) if create else ItemUniqueHost.of(player)


## The bound player, or the first node in the `player` group as a fallback.
func _resolve_holder() -> Node2D:
	if holder != null and is_instance_valid(holder):
		return holder
	holder = null
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	holder = loop.get_first_node_in_group(&"player") as Node2D
	return holder
