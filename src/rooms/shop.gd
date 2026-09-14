## Shop counter: holds up to MAX_OFFERS offers (item/ability/orb objects owned by RunManager)
## with gold prices and a reroll price that grows per use. interact() emits
## EventBus.shop_opened(self); the shop UI reads `offers`/`prices` and calls `take_offer()`.
class_name Shop
extends Interactable

signal offers_changed

const MAX_OFFERS := 3
const BASE_REROLL_PRICE := 25
const REROLL_GROWTH := 1.5
## Price multiplier per ItemInstance.Rarity index (common, rare, epic, legendary).
const RARITY_PRICE_MULT: Array[float] = [1.0, 1.4, 1.9, 2.6]

var offers: Array[RefCounted] = []
var prices: Array[int] = []
var reroll_count: int = 0
var sprite: Sprite2D


func _init() -> void:
	super()
	prompt_text = "Browse wares"
	detect_size = Vector2(40, 32)


func setup(atlas: Texture2D, tint: Material) -> void:
	if sprite != null:
		sprite.queue_free()
	sprite = FloorBuilder.atlas_sprite(atlas, FloorBuilder.SPECIAL_SHOP)
	sprite.material = tint
	add_child(sprite)


## Replaces the offers (truncated to MAX_OFFERS). `new_prices` must match in length.
func set_offers(new_offers: Array[RefCounted], new_prices: Array[int]) -> void:
	offers.clear()
	prices.clear()
	for i in range(mini(new_offers.size(), MAX_OFFERS)):
		offers.append(new_offers[i])
		prices.append(new_prices[i] if i < new_prices.size() else 0)
	offers_changed.emit()


## RunManager entry point: takes an untyped Array of offers (ItemInstance/Ability objects)
## and a base gold price, derives a price per offer from its rarity when it exposes one,
## then delegates to set_offers(). Offers that are not RefCounted are skipped.
func stock(new_offers: Array, base_price: int) -> void:
	var typed: Array[RefCounted] = []
	var new_prices: Array[int] = []
	for offer: Variant in new_offers:
		if not (offer is RefCounted):
			continue
		typed.append(offer as RefCounted)
		new_prices.append(price_for(offer as RefCounted, base_price))
	set_offers(typed, new_prices)


## Price multipliers per rarity: `data/rooms/rooms_content.tres` when it lists any, else the
## RARITY_PRICE_MULT constant. `content` is injectable for tests.
static func rarity_price_mult(content: RoomsContent = null) -> Array[float]:
	var res := RoomsContent.resolve(content)
	if res != null and not res.shop_rarity_price_mult.is_empty():
		return res.shop_rarity_price_mult
	return RARITY_PRICE_MULT


## Gold price of one offer: `base_price` scaled by its `rarity` (ItemInstance.Rarity) if any.
static func price_for(offer: RefCounted, base_price: int) -> int:
	var mult := 1.0
	var rarity: Variant = offer.get("rarity")
	if rarity is int or rarity is float:
		var table := rarity_price_mult()
		mult = table[clampi(int(rarity), 0, table.size() - 1)]
	return maxi(1, int(roundf(base_price * mult)))


## Gold cost of a shop's first reroll: `rooms_content.tres` when it sets a positive value,
## else BASE_REROLL_PRICE (docs §8: 25). `content` is injectable for tests.
static func reroll_base_price(content: RoomsContent = null) -> int:
	var res := RoomsContent.resolve(content)
	if res != null and res.shop_reroll_base_price > 0:
		return res.shop_reroll_base_price
	return BASE_REROLL_PRICE


## Reroll price multiplier per use: `rooms_content.tres` when it sets a positive value, else
## REROLL_GROWTH (docs §8: x1.5). `content` is injectable for tests.
static func reroll_growth(content: RoomsContent = null) -> float:
	var res := RoomsContent.resolve(content)
	if res != null and res.shop_reroll_growth > 0.0:
		return res.shop_reroll_growth
	return REROLL_GROWTH


## Removes and returns the offer at `index` (the buyer already paid). Null when invalid.
func take_offer(index: int) -> RefCounted:
	if index < 0 or index >= offers.size():
		return null
	var offer := offers[index]
	offers.remove_at(index)
	prices.remove_at(index)
	offers_changed.emit()
	return offer


## Gold cost of the next reroll (docs §8: base 25, x1.5 per use; tunable in rooms_content.tres).
func reroll_price() -> int:
	return int(roundf(reroll_base_price() * pow(reroll_growth(), reroll_count)))


## Call after the player paid for a reroll; RunManager then calls set_offers() again.
func mark_rerolled() -> void:
	reroll_count += 1


## Snapshot of the counter for the run save (docs §12): the offers still on it, their prices
## and how many rerolls have already been paid for. Offers go out through their own `to_dict()`
## (ItemInstance); one without it is dropped together with its price, and RunManager restocks
## the whole counter instead of restoring a half-remembered one.
func to_save_dict() -> Dictionary:
	var offer_data: Array = []
	var kept: Array[int] = []
	for i in range(offers.size()):
		var offer := offers[i]
		if offer == null or not offer.has_method(&"to_dict"):
			continue
		offer_data.append(offer.call(&"to_dict"))
		kept.append(prices[i] if i < prices.size() else 0)
	return {"offers": offer_data, "prices": Array(kept), "rerolls": reroll_count}


## True when `to_save_dict()` kept every offer, so the snapshot is a faithful record of the
## counter and a resume may restore it instead of restocking.
func stock_is_serializable() -> bool:
	for offer: RefCounted in offers:
		if offer == null or not offer.has_method(&"to_dict"):
			return false
	return true


## Resume: puts back exactly the stock `to_save_dict()` recorded. `rerolls` restores the
## escalating reroll price, so Save & Quit never refunds a reroll the player paid for.
func restore_stock(new_offers: Array[RefCounted], new_prices: Array[int], rerolls: int = 0) -> void:
	set_offers(new_offers, new_prices)
	reroll_count = maxi(0, rerolls)


func _on_interact(_by: Node2D) -> bool:
	EventBus.shop_opened.emit(self)
	return true
