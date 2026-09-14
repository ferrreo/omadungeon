## Snapshot of how many objects the engine is holding, so a build/teardown cycle can be proven
## to return to baseline instead of drifting upwards.
##
## `orphans` is Godot's OBJECT_ORPHAN_NODE_COUNT: nodes that exist but sit outside the scene
## tree. A `queue_free()`d node counts as one until the frame it is actually deleted, so always
## let two frames pass between a teardown and `take()`.
class_name NodeCensus
extends RefCounted

## Groups whose live membership a run must return to zero after a teardown.
const RUN_GROUPS: Array[StringName] = [
	&"player", &"enemy", &"ally", &"interactable", &"trap", &"hazard"
]


## Current counts. Keys: nodes, orphans, objects, resources, plus one entry per RUN_GROUPS id.
static func take(tree: SceneTree) -> Dictionary:
	var out: Dictionary = {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}
	for group: StringName in RUN_GROUPS:
		out[group] = group_size(tree, group)
	return out


## Members of `group` that are alive and not already queued for deletion.
static func group_size(tree: SceneTree, group: StringName) -> int:
	if tree == null:
		return 0
	var live := 0
	for node: Node in tree.get_nodes_in_group(group):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			live += 1
	return live


## `after - before` for every key the two censuses share.
static func diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in after:
		if before.has(key):
			out[key] = int(after[key]) - int(before[key])
	return out


## Human-readable census or diff, sorted so two reports line up.
static func describe(census: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var keys: Array = census.keys()
	keys.sort()
	for key: Variant in keys:
		parts.append("%s=%s" % [key, census[key]])
	return " ".join(parts)
