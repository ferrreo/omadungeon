## Exit to the next floor. On boss floors it stays locked until an enemy flagged `is_boss`
## dies (EventBus.enemy_died). interact() emits EventBus.floor_exit_requested.
##
## The boss-death unlock only ever happens once, so it cannot be the only way out: a run saved
## after the boss died rebuilds the arena cleared, with no boss left to kill. RunManager
## restores the saved lock state through `restore_unlocked()` (docs §12).
class_name Stairs
extends Interactable

signal unlocked

var locked: bool = false
## True once the player has descended through this staircase (see `_on_interact`).
var used: bool = false
var sprite: Sprite2D
var _atlas: Texture2D


func _init() -> void:
	super()
	prompt_text = "Descend"
	detect_size = Vector2(34, 34)


func _ready() -> void:
	super()
	EventBus.enemy_died.connect(_on_enemy_died)


## Builds the sprite from the biome atlas (row 4: stairs / stairs locked).
func setup(atlas: Texture2D, tint: Material, is_locked: bool) -> void:
	_atlas = atlas
	locked = is_locked
	if sprite != null:
		sprite.queue_free()
	sprite = FloorBuilder.atlas_sprite(atlas, _column())
	sprite.material = tint
	add_child(sprite)
	_refresh()


func unlock() -> void:
	if not locked:
		return
	locked = false
	_refresh()
	if sprite != null and is_inside_tree():
		sprite.scale = Vector2(1.3, 1.3)
		var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(sprite, ^"scale", Vector2.ONE, 0.3)
	unlocked.emit()


## Resume: the exit was already open when the run was saved (the boss is dead, or the floor
## never had one). Same end state as `unlock()`, without the pop tween or the `unlocked`
## signal — nothing just happened, the player is only coming back to a floor they opened.
func restore_unlocked() -> void:
	locked = false
	_refresh()


## One descent per staircase. `floor_exit_requested` builds the next floor synchronously
## inside the emission while this node is only `queue_free`d, so it is still alive and still
## connected for the rest of the frame: a second call - a queued input, a scripted double
## emit - would descend twice and skip a floor and its rewards. `used` is set *before* the
## signal, the way Shrine and Altar spend themselves, so re-entrancy cannot get past it.
func _on_interact(_by: Node2D) -> bool:
	if used:
		return false
	if locked:
		EventBus.toast.emit("The way down is sealed", 1.5)
		return false
	used = true
	enabled = false
	EventBus.floor_exit_requested.emit()
	return true


## The descent did not happen after all: RunManager answered the request with a "you are
## leaving rewards behind" prompt instead of the next floor, and the confirmation is a second
## Descend press on this same staircase. Without putting it back the prompt would seal the
## only exit, because `_on_interact` spends the staircase *before* the signal it is answering.
func cancel_descent() -> void:
	used = false
	enabled = true
	_refresh()


static func is_boss_enemy(enemy: Node2D) -> bool:
	if enemy == null:
		return false
	var flag: Variant = enemy.get("is_boss")
	if flag is bool and flag:
		return true
	var def: Variant = enemy.get("def")
	if def is EnemyDef:
		return (def as EnemyDef).is_boss
	return false


func _on_enemy_died(enemy: Node2D, _killer: Node2D) -> void:
	if locked and is_boss_enemy(enemy):
		unlock()


func _column() -> int:
	return FloorBuilder.SPECIAL_STAIRS_LOCKED if locked else FloorBuilder.SPECIAL_STAIRS


func _refresh() -> void:
	prompt_text = "Sealed" if locked else "Descend"
	if sprite != null:
		sprite.region_rect = FloorBuilder.atlas_cell(_column(), FloorBuilder.ROW_SPECIAL)
