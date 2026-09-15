## Finding the loot a scenario has to walk over.
##
## Kept out of `TestScenarios` because it is a query about the scene rather than a step in a
## scenario, and because that file sits against its 1200-line cap.
class_name ScenarioLoot
extends RefCounted


## Every drop still lying on the floor: the homing pickups (gold, hearts, stat orbs) and the
## item drops an elite leaves, which are different node families in different parents.
static func loose(view: Node) -> Array[Node]:
	var out: Array[Node] = []
	if view == null or not is_instance_valid(view):
		return out
	for node: Node in view.find_children("", "Area2D", true, false):
		var live_drop := (
			(node is PickupBase and not (node as PickupBase).is_collected())
			or (node is ItemPickup and (node as ItemPickup).item != null)
		)
		if live_drop and not node.is_queued_for_deletion():
			out.append(node)
	return out
