## Base for things the player can use with the interact action (chest, stairs, altar, shop,
## shrine). Area2D on Layers.INTERACTABLE (group "interactable") that watches for the player
## body (group "player") and shows the HUD prompt via EventBus.interact_prompt. The prompt is
## owned by the class, not by the node: with several interactables in reach only the nearest
## one's text is shown, and the prompt hides only when none is left.
## Wiring: `FloorRoot.bind_player(player)` connects the player's `interact_pressed` signal to
## `Interactable.dispatch(player)` (FloorRoot also auto-binds the first node in group "player"
## when it builds), which calls `interact(player)` on the nearest usable interactable. Nodes
## in group "interactable" that merely expose an `interact` method count too (mimic chests).
class_name Interactable
extends Area2D

signal interacted(by: Node2D)

const PLAYER_GROUP := &"player"
const GROUP := &"interactable"
## Radius within which `nearest_for()` accepts a group member that is not an Interactable.
const DISPATCH_RADIUS := 24.0
## Interactables currently in reach of the player. The SceneTree owns this list (no static
## state): nodes that leave the tree drop out of it by themselves.
const NEARBY_GROUP := &"interact_in_reach"
## SceneTree metadata key holding the text last emitted with visible=true ("" while hidden).
const PROMPT_META := &"omadungeon_interact_prompt"

## Text shown in the interaction prompt while the player is nearby.
@export var prompt_text: String = "Interact":
	set(value):
		prompt_text = value
		_refresh_prompt()
## Full size of the detection box in pixels (roughly 2 tiles across = ~1 tile of reach).
@export var detect_size: Vector2 = Vector2(32, 32)
## When false, interact() does nothing and no prompt is shown.
var enabled: bool = true:
	set(value):
		enabled = value
		_refresh_prompt()
var _player: Node2D


func _init() -> void:
	collision_layer = Layers.INTERACTABLE
	collision_mask = Layers.PLAYER
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _ready() -> void:
	add_to_group(GROUP)
	if get_node_or_null("Detect") == null:
		var shape := CollisionShape2D.new()
		shape.name = "Detect"
		var rect := RectangleShape2D.new()
		rect.size = detect_size
		shape.shape = rect
		add_child(shape)
	tree_exiting.connect(_on_tree_exiting)


## Called by the player. Returns true when the interaction happened.
func interact(by: Node2D = null) -> bool:
	if not enabled:
		return false
	if not _on_interact(by):
		return false
	interacted.emit(by)
	_refresh_prompt()
	return true


## RunManager calls this once the offer flow that `interact()` started has finished
## (chest taken/skipped, altar pick made, shrine buff applied, shop closed). Subclasses
## override it to spend themselves; the base only makes sure no prompt is left hanging.
func mark_taken() -> void:
	_refresh_prompt()


## True while the player body overlaps the detection shape.
func player_nearby() -> bool:
	return _player != null and is_instance_valid(_player)


## The player node currently nearby, or null.
func nearby_player() -> Node2D:
	return _player if player_nearby() else null


## True when `interact()` would currently do something (override for locked/used states).
func can_interact() -> bool:
	return enabled


## Nearest usable node in group "interactable" to `player`: an enabled Interactable whose
## detection box the player overlaps, or any other group member exposing `interact` within
## DISPATCH_RADIUS (mimic chests). Null when nothing is in reach.
static func nearest_for(player: Node2D) -> Node:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return null
	var best: Node = null
	var best_d := INF
	var origin := player.global_position
	for node: Node in player.get_tree().get_nodes_in_group(GROUP):
		if not (node is Node2D) or not node.has_method(&"interact"):
			continue
		var d := (node as Node2D).global_position.distance_to(origin)
		if node is Interactable:
			var it := node as Interactable
			if not it.can_interact() or it.nearby_player() != player:
				continue
		elif d > DISPATCH_RADIUS:
			continue
		if d < best_d:
			best_d = d
			best = node
	return best


## Calls `interact(player)` on `nearest_for(player)` (with no argument when the target's
## `interact` takes none). Returns true when something was used.
static func dispatch(player: Node2D) -> bool:
	var target := nearest_for(player)
	if target == null:
		return false
	var result: Variant = null
	if target.get_method_argument_count(&"interact") > 0:
		result = target.call(&"interact", player)
	else:
		result = target.call(&"interact")
	if result is bool:
		return result as bool
	return true


## Drops the class-wide prompt state and hides the prompt (floor teardown, tests).
static func reset_prompt(tree: SceneTree) -> void:
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(NEARBY_GROUP):
		node.remove_from_group(NEARBY_GROUP)
	var shown := String(tree.get_meta(PROMPT_META, ""))
	tree.set_meta(PROMPT_META, "")
	if not shown.is_empty():
		EventBus.interact_prompt.emit(shown, false)


## Override: perform the interaction; return false to reject it.
func _on_interact(_by: Node2D) -> bool:
	return true


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(PLAYER_GROUP):
		_player = body
		_refresh_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_refresh_prompt()


func _on_tree_exiting() -> void:
	_player = null
	_refresh_prompt()


## Adds/removes this node from the tree-wide nearby group and re-emits the prompt.
func _refresh_prompt() -> void:
	if not is_inside_tree():
		return
	var want := enabled and player_nearby() and can_interact()
	if want and not is_in_group(NEARBY_GROUP):
		add_to_group(NEARBY_GROUP)
	elif not want and is_in_group(NEARBY_GROUP):
		remove_from_group(NEARBY_GROUP)
	_emit_prompt(get_tree())


## Emits interact_prompt for the nearest member of NEARBY_GROUP (or hides it when empty).
static func _emit_prompt(tree: SceneTree) -> void:
	if tree == null:
		return
	var owner_node: Interactable = null
	var best_d := INF
	for node: Node in tree.get_nodes_in_group(NEARBY_GROUP):
		var it := node as Interactable
		if it == null or not it.player_nearby():
			continue
		var d := it.global_position.distance_to(it.nearby_player().global_position)
		if d < best_d:
			best_d = d
			owner_node = it
	var shown := String(tree.get_meta(PROMPT_META, ""))
	if owner_node == null:
		if not shown.is_empty():
			tree.set_meta(PROMPT_META, "")
			EventBus.interact_prompt.emit(shown, false)
		return
	if owner_node.prompt_text != shown:
		tree.set_meta(PROMPT_META, owner_node.prompt_text)
		EventBus.interact_prompt.emit(owner_node.prompt_text, true)
