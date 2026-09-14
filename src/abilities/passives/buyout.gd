## Buyout (Oligarch innate): chests offer one extra option but cost gold to open, gold finds
## are richer, and the purse you are carrying is itself a weapon.
##
## The first two halves alone made the innate a net loss — the class whose identity is economy
## paid a fee at every chest and had nothing to spend the proceeds on, so it finished runs
## poorer *and* weaker than every other class. `damage_per_gold` is what closes that: gold in
## hand is damage, so the Oligarch's economy is a build rather than a scoreboard, and every
## purchase is a real decision instead of free value.
##
## Flags `chest_extra_option` / `chest_costs_gold` are read by RunManager; the gold-find half
## rides the canonical `gold_find` secondary rather than a private flag.
class_name BuyoutPassive
extends PassiveAbility

@export var gold_drop_bonus: float = 0.5
@export var per_tier: float = 0.15
## Fraction of extra damage per gold coin carried.
@export var damage_per_gold: float = 0.00025
## Most extra damage the purse may be worth, however deep the pockets go.
@export var damage_cap: float = 0.4

var _gold: int = 0
var _owner: Entity


func gold_bonus() -> float:
	return gold_drop_bonus + per_tier * (tier - 1)


## Extra damage fraction the purse is currently worth.
func wealth_bonus() -> float:
	return clampf(float(_gold) * damage_per_gold * float(tier), 0.0, damage_cap)


## Damage multiplier for `gold` coins carried, without needing a live player. Shared with the
## balance simulation so both sides of the game price the purse identically.
func wealth_multiplier(gold: int) -> float:
	return 1.0 + clampf(float(gold) * damage_per_gold * float(tier), 0.0, damage_cap)


func apply(player: Node2D) -> void:
	var entity := player as Entity
	if entity != null:
		entity.stats.add_flat(&"gold_find", owner_id(), gold_bonus())
		_owner = entity
	# The purse the player is *already* holding. `_gold` is otherwise fed only by
	# `EventBus.gold_changed`, and the Oligarch's 150 starting gold is announced by
	# `Player.apply_class()` *before* RunManager grants the innate - so the class whose whole
	# identity is "the gold in hand is itself damage" (docs §4.3) began every run with its own
	# starting gold priced at nothing, and only caught up on the first coin it picked up. The
	# balance model has always assumed otherwise (`SimPlayer.create()` sets `gold` from
	# `def.start_gold` before folding the effect), which is how the live calibration found it.
	# Read rather than injected, so this holds whenever the passive is applied.
	var carried: Variant = player.get(&"gold")
	if carried is int:
		_gold = maxi(0, carried)
	if not EventBus.gold_changed.is_connected(_on_gold_changed):
		EventBus.gold_changed.connect(_on_gold_changed)
	var slots := AbilityUtil.slots_of(player)
	if slots == null:
		return
	slots.set_flag(&"chest_extra_option", true)
	slots.set_flag(&"chest_costs_gold", true)


func remove(player: Node2D) -> void:
	if EventBus.gold_changed.is_connected(_on_gold_changed):
		EventBus.gold_changed.disconnect(_on_gold_changed)
	_gold = 0
	_owner = null
	super(player)
	var slots := AbilityUtil.slots_of(player)
	if slots == null:
		return
	slots.clear_flag(&"chest_extra_option")
	slots.clear_flag(&"chest_costs_gold")


func outgoing_damage_multiplier(_player: Node2D, _target: Node2D, _info: DamageInfo) -> float:
	return 1.0 + wealth_bonus()


func _on_gold_changed(amount: int) -> void:
	_gold = maxi(0, amount)
