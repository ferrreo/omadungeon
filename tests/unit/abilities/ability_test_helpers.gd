## Shared builders for the abilities test suites.
class_name AbilityTestHelpers
extends RefCounted


static func registry() -> AbilityRegistry:
	return AbilityRegistry.load_default()


## Fresh tier-1 copy of an ability from the registry.
static func ability(id: StringName) -> Ability:
	var a := registry().instance(id)
	assert(a != null, "unknown ability %s" % id)
	return a


static func active(id: StringName) -> ActiveAbility:
	return ability(id) as ActiveAbility


static func passive(id: StringName) -> PassiveAbility:
	return ability(id) as PassiveAbility


static func make_player(pos: Vector2 = Vector2.ZERO) -> DummyPlayer:
	var p := DummyPlayer.new()
	p.name = "Player"
	p.position = pos
	return p


static func make_enemy(pos: Vector2, elite: bool = false) -> DummyEnemy:
	var e := DummyEnemy.new()
	e.name = "Enemy"
	e.position = pos
	e.is_elite = elite
	return e


static func make_convertible_enemy(pos: Vector2) -> DummyConvertibleEnemy:
	var e := DummyConvertibleEnemy.new()
	e.name = "Convertible"
	e.position = pos
	return e


## Adds an AbilitySlots child named "AbilitySlots" to `player` (call after it is in the tree).
static func attach_slots(player: Entity) -> AbilitySlots:
	var slots := AbilitySlots.new()
	slots.name = "AbilitySlots"
	slots.rng.seed = 12345
	player.add_child(slots)
	return slots


## Melee DamageInfo from `attacker` for thorns/bulwark tests.
static func melee_hit(attacker: Entity, amount: float) -> DamageInfo:
	var tags: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
	return DamageInfo.create(amount, tags, attacker, attacker.team)
