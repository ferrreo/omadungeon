## Test double for the shipped Player's shield contract: a `set_shield(amount, duration)`
## method plus a Health pool that reports absorption through `shield_absorbed`, so Bulwark's
## production path (not the BulwarkShield fallback) is the one exercised.
class_name ShieldedDummyPlayer
extends DummyPlayer

var shield_amount: float = 0.0
var shield_duration: float = 0.0


func _ready() -> void:
	var pool := ShieldedDummyHealth.new()
	pool.name = "Health"
	add_child(pool)
	super()


func set_shield(amount: float, duration: float = 0.0) -> void:
	shield_amount = maxf(0.0, amount)
	shield_duration = duration
	var pool := health as ShieldedDummyHealth
	if pool != null:
		pool.shield = shield_amount
