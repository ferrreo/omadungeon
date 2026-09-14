## Stand-in for the player's Equipment mirroring the real contract (src/items/equipment.gd):
## `slots` only holds the occupied slot names and `items()` returns them in SLOTS order.
class_name DummyEquipment
extends RefCounted

const SLOTS: Array[StringName] = [&"weapon", &"armor", &"ring1", &"ring2", &"trinket"]

var slots: Dictionary = {}


## Every equipped item in SLOTS order, like Equipment.items().
func items() -> Array:
	var out: Array = []
	for slot_name: StringName in SLOTS:
		if slots.has(slot_name):
			out.append(slots[slot_name])
	return out


func get_item(slot_name: StringName) -> Variant:
	return slots.get(slot_name)
