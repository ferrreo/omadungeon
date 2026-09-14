## Runtime home for item-borne unique effects (legendary PassiveAbilities). Lives as a child
## node named `ItemUniques` on the player so the passives have a Node lifetime, get `apply()`
## called and receive the PassiveAbility hooks the abilities module dispatches for its own
## slots. `Equipment` creates one on demand; if the abilities module ever takes ownership of
## item uniques (by calling `Equipment.set_unique_host(true)`) no host is created at all.
class_name ItemUniqueHost
extends Node

const NODE_NAME := "ItemUniques"

var passives: Array[PassiveAbility] = []
var owner_entity: Node2D
## The Equipment whose legendaries are hosted here. A restored run builds a fresh Equipment
## for the same player; the newcomer claims the host and the stale passives are dropped.
var owner_equipment: RefCounted


## The host on `player`, or null.
static func of(player: Node) -> ItemUniqueHost:
	if player == null:
		return null
	return player.get_node_or_null(NodePath(NODE_NAME)) as ItemUniqueHost


## The host on `player`, created and added when missing.
static func attach(player: Node2D) -> ItemUniqueHost:
	var host := of(player)
	if host != null:
		return host
	host = ItemUniqueHost.new()
	host.name = NODE_NAME
	host.owner_entity = player
	player.add_child(host)
	return host


func _enter_tree() -> void:
	if owner_entity == null:
		owner_entity = get_parent() as Node2D
	for pair: Array in _bus_hooks():
		var sig: Signal = pair[0]
		var handler: Callable = pair[1]
		if not sig.is_connected(handler):
			sig.connect(handler)
	var entity := owner_entity as Entity
	if entity != null and not entity.hit_received.is_connected(_on_hit_received):
		entity.hit_received.connect(_on_hit_received)


func _exit_tree() -> void:
	for pair: Array in _bus_hooks():
		var sig: Signal = pair[0]
		var handler: Callable = pair[1]
		if sig.is_connected(handler):
			sig.disconnect(handler)
	var entity := owner_entity as Entity
	if (
		entity != null
		and is_instance_valid(entity)
		and entity.hit_received.is_connected(_on_hit_received)
	):
		entity.hit_received.disconnect(_on_hit_received)


## The EventBus signals this host listens on, paired with their handlers.
func _bus_hooks() -> Array[Array]:
	return [
		[EventBus.player_hit_dealt, _on_player_hit_dealt],
		[EventBus.room_cleared, _on_room_cleared],
		[EventBus.enemy_died, _on_enemy_died],
		[EventBus.player_dodged, _on_player_dodged],
	]


## Hands the host to `equipment`, removing passives left by a previous one.
func claim(equipment: RefCounted) -> void:
	if owner_equipment == equipment:
		return
	owner_equipment = equipment
	clear_passives()


## Removes every hosted passive (and its stat modifiers).
func clear_passives() -> void:
	for passive: PassiveAbility in passives.duplicate():
		remove_passive(passive)


## Registers and applies `passive` (no-op when it is already hosted).
func add_passive(passive: PassiveAbility) -> void:
	if passive == null or passives.has(passive):
		return
	passives.append(passive)
	if owner_entity != null:
		passive.apply(owner_entity)


## Removes `passive` and its stat modifiers.
func remove_passive(passive: PassiveAbility) -> void:
	if passive == null or not passives.has(passive):
		return
	passives.erase(passive)
	if owner_entity != null and is_instance_valid(owner_entity):
		passive.remove(owner_entity)


## Product of the hosted passives' conditional damage multipliers (sudo).
func multiplier(target: Node2D, info: DamageInfo) -> float:
	var out := 1.0
	if owner_entity == null:
		return out
	for passive: PassiveAbility in passives:
		out *= passive.outgoing_damage_multiplier(owner_entity, target, info)
	return out


func _on_player_hit_dealt(target: Node2D, info: DamageInfo) -> void:
	if owner_entity == null:
		return
	for passive: PassiveAbility in passives:
		passive.on_hit_dealt(owner_entity, target, info)


func _on_room_cleared(_room_id: int) -> void:
	if owner_entity == null:
		return
	for passive: PassiveAbility in passives:
		passive.on_room_cleared(owner_entity)


func _on_enemy_died(enemy: Node2D, killer: Node2D) -> void:
	if owner_entity == null or killer == null:
		return
	if killer != owner_entity and not owner_entity.is_ancestor_of(killer):
		return
	for passive: PassiveAbility in passives:
		passive.on_kill(owner_entity, enemy)


func _on_player_dodged(_style: StringName) -> void:
	if owner_entity == null:
		return
	for passive: PassiveAbility in passives:
		passive.on_dodge(owner_entity)


func _on_hit_received(info: DamageInfo) -> void:
	if owner_entity == null:
		return
	for passive: PassiveAbility in passives:
		passive.on_hit_received(owner_entity, info)
