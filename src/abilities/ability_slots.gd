## Player ability loadout: 2 active + 2 passive slots plus an uncounted registry for class
## innates and legendary unique effects. Child of the player Entity, named `AbilitySlots`.
## Ticks active cooldowns, casts actives, installs passives and dispatches their hooks from
## EventBus/owner signals. Unified slot indices: 0-1 actives, 2-3 passives.
##
## Flags (`set_flag`/`get_flag`) are written into `owner.flags` when the owner exposes a
## Dictionary property of that name, otherwise into the local `flags` dictionary. Every key a
## passive sets has a consumer today: `free_reroll_per_floor` and `chest_extra_option` /
## `chest_costs_gold` (RunManager chest flow), `projectile_bounces` (WeaponController) and
## `trap_immune_dodge` (Player). Passives whose effect had no reader now go through Stats
## instead (Heavy Hands scales melee knockback in `outgoing_damage_multiplier`, Buyout adds
## `gold_find`, Lucky Coin adds `luck`), so no flag here is dead weight.
class_name AbilitySlots
extends Node

## Mirrors EventBus.ability_slot_changed for local listeners.
signal slot_changed(index: int, ability: Ability)
## An active in slot `index` was cast.
signal active_used(index: int, ability: ActiveAbility)
## An uncounted passive (class innate, legendary unique) was installed or removed.
signal uncounted_changed(passive: PassiveAbility, installed: bool)

const ACTIVE_COUNT := 2
const PASSIVE_COUNT := 2
const SLOT_COUNT := ACTIVE_COUNT + PASSIVE_COUNT
## One-hit buff: the next outgoing hit is a guaranteed crit.
const BUFF_CRIT := &"crit"
## Node name the player looks for (`player.get_node_or_null("AbilitySlots")`).
const NODE_NAME := "AbilitySlots"

var actives: Array[ActiveAbility] = [null, null]
var passives: Array[PassiveAbility] = [null, null]
## Class innates and legendary unique effects: applied and hooked like slotted passives but
## never occupying one of the two passive slots.
var innates: Array[PassiveAbility] = []
## Local flag store (used only when the owner has no `flags` property).
var flags: Dictionary = {}
## Slots switched off by an outside effect (The Suit's Hostile Takeover buys one per
## phase). A disabled active refuses to cast and a disabled passive is uninstalled until
## the slot is re-enabled. Indices match the unified slot indices.
var disabled_slots: Array[bool] = [false, false, false, false]
## When true, the next successful cast skips its cooldown (Overflow).
var free_cast_next: bool = false
## Damage multiplier stamped on the next free cast (Overflow: 1.25).
var free_cast_power: float = 1.0
## Combat RNG for crits; RunManager should assign `RunRng.stream(&"combat")`.
var rng := RandomNumberGenerator.new()
var owner_entity: Entity
var _next_hit_buffs: Array[StringName] = []
var _cast_power: Dictionary = {}
var _connected := false
var _pending_apply: Array[PassiveAbility] = []


## Creates (or returns) the `AbilitySlots` child of `player`, optionally seeding its combat
## RNG. Use this when the player scene does not already ship the node.
static func attach(player: Node, combat_rng: RandomNumberGenerator = null) -> AbilitySlots:
	if player == null:
		return null
	var slots := player.get_node_or_null(NodePath(NODE_NAME)) as AbilitySlots
	if slots == null:
		slots = AbilitySlots.new()
		slots.name = NODE_NAME
		player.add_child(slots)
	if combat_rng != null:
		slots.rng = combat_rng
	return slots


func _enter_tree() -> void:
	_resolve_owner()
	_connect_hooks()
	_flush_pending_apply()


func _ready() -> void:
	_resolve_owner()
	_connect_hooks()
	_flush_pending_apply()


func _exit_tree() -> void:
	_disconnect_hooks()
	_uninstall_all()


func _process(delta: float) -> void:
	for ability: ActiveAbility in actives:
		if ability != null:
			ability.tick(delta)


func _resolve_owner() -> void:
	if owner_entity != null and is_instance_valid(owner_entity):
		return
	owner_entity = get_parent() as Entity
	if owner_entity == null:
		push_warning("AbilitySlots must be a child of an Entity")


## Applies passives that were installed before the owner existed (loadout built off-tree).
func _flush_pending_apply() -> void:
	if owner_entity == null or _pending_apply.is_empty():
		return
	var pending := _pending_apply.duplicate()
	_pending_apply.clear()
	for p: PassiveAbility in pending:
		if p != null:
			p.apply(owner_entity)


# --- slots -----------------------------------------------------------------------------------


## Ability in unified slot `index` (0-1 active, 2-3 passive) or null.
func get_ability(index: int) -> Ability:
	if index < 0 or index >= SLOT_COUNT:
		return null
	if index < ACTIVE_COUNT:
		return actives[index]
	return passives[index - ACTIVE_COUNT]


func is_active_index(index: int) -> bool:
	return index >= 0 and index < ACTIVE_COUNT


func is_passive_index(index: int) -> bool:
	return index >= ACTIVE_COUNT and index < SLOT_COUNT


## Every slotted ability, actives first, nulls skipped (innates excluded).
func all() -> Array[Ability]:
	var out: Array[Ability] = []
	for a: ActiveAbility in actives:
		if a != null:
			out.append(a)
	for p: PassiveAbility in passives:
		if p != null:
			out.append(p)
	return out


## Every passive whose hooks fire: the two slots plus the uncounted innates/uniques.
func all_passives() -> Array[PassiveAbility]:
	var out: Array[PassiveAbility] = []
	for i in range(PASSIVE_COUNT):
		var p := passives[i]
		if p != null and not disabled_slots[i + ACTIVE_COUNT]:
			out.append(p)
	for p: PassiveAbility in innates:
		if p != null:
			out.append(p)
	return out


func index_of(id: StringName) -> int:
	for i in range(SLOT_COUNT):
		var a := get_ability(i)
		if a != null and a.id == id:
			return i
	return -1


func has(id: StringName) -> bool:
	return index_of(id) >= 0 or _innate_with(id) != null


func tier_of(id: StringName) -> int:
	var i := index_of(id)
	if i >= 0:
		return get_ability(i).tier
	var innate := _innate_with(id)
	return innate.tier if innate != null else 0


## id -> tier map for registry offers and saves (slots + innates/uniques).
func owned_tiers() -> Dictionary:
	var out: Dictionary = {}
	for a: Ability in all():
		out[a.id] = a.tier
	for p: PassiveAbility in innates:
		if p != null:
			out[p.id] = p.tier
	return out


## Alias of `owned_tiers()` kept for older callers.
func owned() -> Dictionary:
	return owned_tiers()


func is_full(kind: Ability.Kind) -> bool:
	return _first_empty(kind) < 0


## Slots that `offer` would displace, in the order `replace(index, ...)` expects. Empty when
## the offer is a tier-up, not an Ability, or a slot of that kind is still free — i.e. when
## `add()` will succeed on its own. ChestUI calls this and returns the chosen array index.
func would_need_replace(offer: Variant) -> Array:
	var ability := offer as Ability
	if ability == null:
		return []
	if index_of(ability.id) >= 0 or _innate_with(ability.id) != null:
		return []
	if not is_full(ability.kind):
		return []
	return actives.duplicate() if ability.is_active() else passives.duplicate()


## Adds an ability. Owning the same id tiers it up instead. Returns false when every slot of
## that kind is taken (the UI should then ask which slot to `replace`) or when a tier-up would
## exceed `max_tier` (nothing changes in either case).
func add(ability: Ability) -> bool:
	if ability == null:
		return false
	var innate := _innate_with(ability.id)
	if innate != null:
		return _tier_up_passive(innate)
	var existing := index_of(ability.id)
	if existing >= 0:
		return _tier_up(existing)
	var slot := _first_empty(ability.kind)
	if slot < 0:
		return false
	_install(slot, _own_copy(ability))
	return true


## Registers a class innate passive: applied and hooked, but outside the two passive slots.
func add_innate(ability: PassiveAbility) -> void:
	add_uncounted(ability)


## Registers an uncounted passive (class innate, legendary unique effect). Duplicates tier up.
func add_uncounted(passive: PassiveAbility) -> void:
	if passive == null:
		return
	var existing := _innate_with(passive.id)
	if existing != null:
		_tier_up_passive(existing)
		return
	var copy := _own_copy(passive) as PassiveAbility
	copy.tier = clampi(copy.tier, 1, copy.max_tier)
	innates.append(copy)
	_apply_passive(copy)
	uncounted_changed.emit(copy, true)


## Removes an uncounted passive previously registered by id (or by instance).
func remove_uncounted(passive: PassiveAbility) -> void:
	if passive == null:
		return
	var existing := _innate_with(passive.id)
	if existing == null:
		return
	innates.erase(existing)
	_pending_apply.erase(existing)
	if owner_entity != null:
		existing.remove(owner_entity)
	uncounted_changed.emit(existing, false)


## Puts `ability` into slot `index`, returning the ability it displaced (or null). `index` may
## be a unified index (0-3) or, for a passive, the index within `passives` (0-1) — which is
## what `would_need_replace()` hands the UI. Out-of-range or kind-mismatched calls change
## nothing. Replacing with an id already installed elsewhere tiers that copy up instead.
func replace(index: int, ability: Ability) -> Ability:
	if ability == null:
		return null
	var slot := _resolve_slot_index(index, ability)
	if slot < 0:
		push_warning("AbilitySlots.replace: invalid slot %d for %s" % [index, ability.id])
		return null
	var innate := _innate_with(ability.id)
	if innate != null:
		_tier_up_passive(innate)
		return null
	var duplicate_at := index_of(ability.id)
	if duplicate_at >= 0 and duplicate_at != slot:
		_tier_up(duplicate_at)
		return null
	var previous := get_ability(slot)
	if previous != null:
		_uninstall(slot)
	_install(slot, _own_copy(ability))
	return previous


## Unified slot for `index` given the ability's kind, or -1 when it cannot be resolved.
func _resolve_slot_index(index: int, ability: Ability) -> int:
	if ability.is_active():
		return index if index >= 0 and index < ACTIVE_COUNT else -1
	if index >= 0 and index < PASSIVE_COUNT:
		return index + ACTIVE_COUNT
	if is_passive_index(index):
		return index
	return -1


## Empties slot `index`, returning the removed ability.
func remove(index: int) -> Ability:
	var previous := get_ability(index)
	if previous != null:
		_uninstall(index)
		_store(index, null)
		_emit_changed(index, null)
	return previous


## Empties both kinds of slot. `keep_innates` false also drops innates/uniques.
func clear(keep_innates: bool = true) -> void:
	for i in range(SLOT_COUNT):
		remove(i)
	if not keep_innates:
		for p: PassiveAbility in innates.duplicate():
			remove_uncounted(p)


## Disables (or re-enables) slot `index` from outside the loadout: a disabled active cannot
## be cast and a disabled passive's stat modifiers and hooks are uninstalled meanwhile. The
## ability itself stays in the slot, so re-enabling restores exactly what was taken.
func set_slot_disabled(index: int, disabled: bool) -> void:
	if index < 0 or index >= SLOT_COUNT or disabled_slots[index] == disabled:
		return
	disabled_slots[index] = disabled
	var ability := get_ability(index)
	var passive := ability as PassiveAbility
	if passive != null and owner_entity != null and is_instance_valid(owner_entity):
		if disabled:
			passive.remove(owner_entity)
			_pending_apply.erase(passive)
		else:
			passive.apply(owner_entity)
	_emit_changed(index, ability)


func is_slot_disabled(index: int) -> bool:
	return index >= 0 and index < SLOT_COUNT and disabled_slots[index]


func _innate_with(id: StringName) -> PassiveAbility:
	for p: PassiveAbility in innates:
		if p != null and p.id == id:
			return p
	return null


## Defensive copy: registry `.tres` instances are shared, and installing mutates `tier`.
func _own_copy(ability: Ability) -> Ability:
	if ability.resource_path.is_empty():
		return ability
	return ability.duplicate_ability()


func _first_empty(kind: Ability.Kind) -> int:
	if kind == Ability.Kind.ACTIVE:
		for i in range(ACTIVE_COUNT):
			if actives[i] == null:
				return i
	else:
		for i in range(PASSIVE_COUNT):
			if passives[i] == null:
				return i + ACTIVE_COUNT
	return -1


func _store(index: int, ability: Ability) -> void:
	if index < 0 or index >= SLOT_COUNT:
		push_warning("AbilitySlots: slot %d out of range" % index)
		return
	if is_active_index(index):
		actives[index] = ability as ActiveAbility
	else:
		passives[index - ACTIVE_COUNT] = ability as PassiveAbility


func _install(index: int, ability: Ability) -> void:
	ability.tier = clampi(ability.tier, 1, ability.max_tier)
	_store(index, ability)
	if ability is PassiveAbility and not is_slot_disabled(index):
		_apply_passive(ability as PassiveAbility)
	_emit_changed(index, ability)


## Applies a passive now, or queues it until the owner entity is known.
func _apply_passive(passive: PassiveAbility) -> void:
	if owner_entity == null:
		if not _pending_apply.has(passive):
			_pending_apply.append(passive)
		return
	passive.apply(owner_entity)


func _uninstall(index: int) -> void:
	var ability := get_ability(index)
	if ability is PassiveAbility:
		_pending_apply.erase(ability)
		if owner_entity != null:
			(ability as PassiveAbility).remove(owner_entity)
	if ability is ActiveAbility:
		_cast_power.erase(ability.id)


## Removes every installed passive (slots + uncounted) so stat modifiers and EventBus
## listeners die with the owner. Called from `_exit_tree`; the passives are queued for
## re-apply so a reparent (floor teardown) restores them on the way back in.
func _uninstall_all() -> void:
	if owner_entity == null or not is_instance_valid(owner_entity):
		return
	for p: PassiveAbility in all_passives():
		p.remove(owner_entity)
		if not _pending_apply.has(p):
			_pending_apply.append(p)


func _tier_up(index: int) -> bool:
	var ability := get_ability(index)
	if ability == null or ability.tier >= ability.max_tier:
		return false
	ability.tier += 1
	if ability is PassiveAbility and owner_entity != null:
		(ability as PassiveAbility).on_tier_changed(owner_entity)
	_emit_changed(index, ability)
	return true


func _tier_up_passive(passive: PassiveAbility) -> bool:
	if passive.tier >= passive.max_tier:
		return false
	passive.tier += 1
	if owner_entity != null:
		passive.on_tier_changed(owner_entity)
	uncounted_changed.emit(passive, true)
	return true


func _emit_changed(index: int, ability: Ability) -> void:
	slot_changed.emit(index, ability)
	EventBus.ability_slot_changed.emit(index, ability)


# --- casting ---------------------------------------------------------------------------------


## Casts the active in slot `index` (0 or 1) toward `aim` (world-space direction).
func try_use(index: int, aim: Vector2) -> bool:
	if not is_active_index(index) or owner_entity == null or is_slot_disabled(index):
		return false
	var ability := actives[index]
	if ability == null or not ability.is_ready() or not owner_entity.can_act():
		return false
	var free := free_cast_next
	if free:
		_cast_power[ability.id] = free_cast_power
	else:
		_cast_power.erase(ability.id)
	if not ability.try_activate(owner_entity, aim, free):
		_cast_power.erase(ability.id)
		return false
	if free:
		free_cast_next = false
	for p: PassiveAbility in all_passives():
		p.on_active_used(owner_entity, ability)
	active_used.emit(index, ability)
	EventBus.ability_used.emit(index, ability)
	return true


## Damage multiplier for the most recent cast of `ability` (1.25 for an Overflow cast).
func cast_power(ability: ActiveAbility) -> float:
	if ability == null:
		return 1.0
	return float(_cast_power.get(ability.id, 1.0))


## Refunds a fraction of every active's cooldown (Hotkey passive).
func refund_all(fraction: float) -> void:
	for a: ActiveAbility in actives:
		if a != null:
			a.refund(fraction)


# --- one-hit buffs and multipliers -------------------------------------------------------------


## Queues a one-hit buff consumed by the next `outgoing_damage_multiplier` call.
func queue_next_hit(buff: StringName) -> void:
	if not _next_hit_buffs.has(buff):
		_next_hit_buffs.append(buff)


func has_next_hit(buff: StringName) -> bool:
	return _next_hit_buffs.has(buff)


func clear_next_hit_buffs() -> void:
	_next_hit_buffs.clear()


## Product of passive multipliers plus queued one-hit buffs. Call once per outgoing hit
## (the player's weapon code and AbilityUtil.make_damage do). Guaranteed crits set
## `info.is_crit` and return the crit multiplier when the hit was not already a crit.
func outgoing_damage_multiplier(target: Node2D, info: DamageInfo) -> float:
	var mult := 1.0
	if owner_entity == null:
		return mult
	for p: PassiveAbility in all_passives():
		mult *= p.outgoing_damage_multiplier(owner_entity, target, info)
	if _next_hit_buffs.has(BUFF_CRIT):
		_next_hit_buffs.erase(BUFF_CRIT)
		if info != null and not info.is_crit:
			info.is_crit = true
			mult *= owner_entity.stats.get_value(&"crit_mult")
	return mult


# --- flags -------------------------------------------------------------------------------------


## The dictionary flags live in: `owner.flags` when present, else the local one.
func flags_dict() -> Dictionary:
	if owner_entity != null:
		var owner_flags: Variant = owner_entity.get("flags")
		if owner_flags is Dictionary:
			return owner_flags
	return flags


func set_flag(key: StringName, value: Variant) -> void:
	flags_dict()[key] = value


func get_flag(key: StringName, default: Variant = null) -> Variant:
	return flags_dict().get(key, default)


func has_flag(key: StringName) -> bool:
	return flags_dict().has(key)


func clear_flag(key: StringName) -> void:
	flags_dict().erase(key)


# --- hook dispatch -----------------------------------------------------------------------------


func _connect_hooks() -> void:
	if _connected or owner_entity == null:
		return
	_connected = true
	if not owner_entity.hit_received.is_connected(_on_owner_hit_received):
		owner_entity.hit_received.connect(_on_owner_hit_received)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_hit_dealt.connect(_on_player_hit_dealt)
	EventBus.player_dodged.connect(_on_player_dodged)
	EventBus.room_cleared.connect(_on_room_cleared)


func _disconnect_hooks() -> void:
	if not _connected:
		return
	_connected = false
	if (
		is_instance_valid(owner_entity)
		and owner_entity.hit_received.is_connected(_on_owner_hit_received)
	):
		owner_entity.hit_received.disconnect(_on_owner_hit_received)
	EventBus.enemy_died.disconnect(_on_enemy_died)
	EventBus.player_hit_dealt.disconnect(_on_player_hit_dealt)
	EventBus.player_dodged.disconnect(_on_player_dodged)
	EventBus.room_cleared.disconnect(_on_room_cleared)


## True for the owner, anything parented under it, and hirelings that follow it (their hits
## and kills credit the player).
func _is_owner_or_child(node: Node) -> bool:
	if node == null or owner_entity == null:
		return false
	if node == owner_entity or owner_entity.is_ancestor_of(node):
		return true
	if node.is_in_group(&"hireling"):
		return node.get("leader") == owner_entity
	# One hop only (a projectile/turret credits its `source`); never walk a cycle.
	var node_owner: Variant = node.get("source")
	if node_owner is Node and node_owner != node:
		var source_node := node_owner as Node
		return source_node == owner_entity or owner_entity.is_ancestor_of(source_node)
	return false


func _on_enemy_died(enemy: Node2D, killer: Node2D) -> void:
	if not _is_owner_or_child(killer):
		return
	for p: PassiveAbility in all_passives():
		p.on_kill(owner_entity, enemy)


func _on_player_hit_dealt(target: Node2D, info: DamageInfo) -> void:
	if info == null or not _is_owner_or_child(info.source):
		return
	for p: PassiveAbility in all_passives():
		p.on_hit_dealt(owner_entity, target, info)


func _on_owner_hit_received(info: DamageInfo) -> void:
	for p: PassiveAbility in all_passives():
		p.on_hit_received(owner_entity, info)


func _on_player_dodged(_style: StringName) -> void:
	for p: PassiveAbility in all_passives():
		p.on_dodge(owner_entity)


func _on_room_cleared(_room_id: int) -> void:
	for p: PassiveAbility in all_passives():
		p.on_room_cleared(owner_entity)


# --- persistence -------------------------------------------------------------------------------


## Serializes ids, tiers, cooldowns, innates and per-passive runtime state (a passive may
## implement `to_state() -> Dictionary` / `from_state(Dictionary)`; the default is stateless).
func to_dict() -> Dictionary:
	var active_data: Array = []
	for a: ActiveAbility in actives:
		if a == null:
			active_data.append(null)
		else:
			active_data.append(
				{"id": String(a.id), "tier": a.tier, "cooldown_left": a.cooldown_left}
			)
	var passive_data: Array = []
	for p: PassiveAbility in passives:
		passive_data.append(null if p == null else _passive_entry(p))
	var innate_data: Array = []
	for p: PassiveAbility in innates:
		if p != null:
			innate_data.append(_passive_entry(p))
	return {
		"actives": active_data,
		"passives": passive_data,
		"innates": innate_data,
		"free_cast_next": free_cast_next,
		"free_cast_power": free_cast_power,
		"next_hit_buffs": _next_hit_buffs.duplicate(),
	}


func _passive_entry(p: PassiveAbility) -> Dictionary:
	var entry := {"id": String(p.id), "tier": p.tier}
	if p.has_method("to_state"):
		entry["state"] = p.call("to_state")
	return entry


## Restores a loadout from `to_dict()` output using `registry` to resolve ids.
func from_dict(data: Dictionary, registry: AbilityRegistry) -> void:
	clear(false)
	var active_data: Array = data.get("actives", [])
	for i in range(mini(ACTIVE_COUNT, active_data.size())):
		var entry: Variant = active_data[i]
		if not entry is Dictionary:
			continue
		var ability := _resolve(entry, registry) as ActiveAbility
		if ability == null:
			continue
		ability.cooldown_left = float((entry as Dictionary).get("cooldown_left", 0.0))
		_install(i, ability)
	var passive_data: Array = data.get("passives", [])
	for i in range(mini(PASSIVE_COUNT, passive_data.size())):
		var entry: Variant = passive_data[i]
		if not entry is Dictionary:
			continue
		var ability := _resolve(entry, registry) as PassiveAbility
		if ability == null:
			continue
		_install(i + ACTIVE_COUNT, ability)
		_restore_state(ability, entry as Dictionary)
	for entry: Variant in data.get("innates", []):
		if not entry is Dictionary:
			continue
		var ability := _resolve(entry, registry) as PassiveAbility
		if ability == null:
			continue
		add_uncounted(ability)
		var installed := _innate_with(ability.id)
		if installed != null:
			_restore_state(installed, entry as Dictionary)
	free_cast_next = bool(data.get("free_cast_next", false))
	free_cast_power = float(data.get("free_cast_power", 1.0))
	_next_hit_buffs.clear()
	for buff: Variant in data.get("next_hit_buffs", []):
		_next_hit_buffs.append(StringName(str(buff)))


func _restore_state(passive: PassiveAbility, entry: Dictionary) -> void:
	var state: Variant = entry.get("state")
	if state is Dictionary and passive.has_method("from_state"):
		passive.call("from_state", state)


func _resolve(entry: Dictionary, registry: AbilityRegistry) -> Ability:
	if registry == null:
		return null
	var found := registry.find(StringName(str(entry.get("id", ""))))
	if found == null:
		push_warning("AbilitySlots.from_dict: unknown ability %s" % str(entry.get("id", "")))
		return null
	var copy := found.duplicate_ability()
	copy.tier = clampi(int(entry.get("tier", 1)), 1, copy.max_tier)
	return copy
