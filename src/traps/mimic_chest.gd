## Mimic chest (docs §9): looks like a chest and wobbles slightly. Its child `TrapInteractable`
## is a regular `Interactable` ("Open chest" prompt) so the player uses it like a real chest;
## `interact()` requests an enemy spawn via `EventBus.spawn_enemy_requested(enemy_id, pos)` and
## removes the decoy.
class_name MimicChest
extends TrapBase

signal revealed(mimic: MimicChest)

const WOBBLE_PERIOD := 2.4
const WOBBLE_DEGREES := 6.0
const ENEMY_REGISTRY_PATH := "res://data/enemies/registry.tres"

## Enemy the decoy turns into. There is no dedicated mimic EnemyDef yet, so this points at an
## existing one; RunManager resolves it through `data/enemies/registry.tres`, and the chest
## refuses to vanish (see `interact`) when the id cannot be served.
@export var enemy_id: StringName = &"mime"

var interactable: TrapInteractable
var _wobble_left: float = WOBBLE_PERIOD * 0.5
var _revealed: bool = false


func _init() -> void:
	kind = &"mimic_chest"
	damage = 0.0
	plate_controlled = false
	hitbox_size = Vector2(16.0, 14.0)


func configure(extra: Dictionary) -> void:
	super.configure(extra)
	if extra.has("enemy_id"):
		enemy_id = StringName(str(extra["enemy_id"]))


func _uses_hitbox() -> bool:
	return false


func _on_setup() -> void:
	interactable = TrapInteractable.new()
	interactable.name = "Interactable"
	add_child(interactable)
	particles.color = _palette_color(&"loot")
	particles.amount = 16


func _on_idle_process(delta: float) -> void:
	_wobble_left -= delta
	if _wobble_left <= 0.0:
		_wobble_left = WOBBLE_PERIOD
		_wobble()


## Slight, suspicious wobble.
func _wobble() -> void:
	if sprite == null or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(sprite, "rotation_degrees", -WOBBLE_DEGREES, 0.06)
	tween.tween_property(sprite, "rotation_degrees", WOBBLE_DEGREES, 0.1)
	tween.tween_property(sprite, "rotation_degrees", 0.0, 0.08)


## Prompt shown by the HUD (mirrors Chest so the decoy gives nothing away).
func interact_prompt() -> String:
	return TrapInteractable.CHEST_PROMPT


## True when `enemy_id` resolves to an EnemyDef. Unverifiable (missing registry) counts as
## servable so tools and isolated tests still work.
func spawn_is_servable() -> bool:
	if not ResourceLoader.exists(ENEMY_REGISTRY_PATH):
		return true
	var registry := load(ENEMY_REGISTRY_PATH) as EnemyRegistry
	if registry == null:
		return true
	return registry.find(enemy_id) != null


## The chest springs to life: request the mimic enemy, then remove this decoy.
## Returns false when it was already revealed or when nothing can serve `enemy_id`
## (the decoy stays put rather than silently vanishing with no enemy spawned).
func interact(_by: Node2D = null) -> bool:
	if _revealed:
		return false
	if not spawn_is_servable():
		push_error("MimicChest: no EnemyDef '%s' in %s" % [enemy_id, ENEMY_REGISTRY_PATH])
		return false
	_revealed = true
	_set_frame(FRAME_ACTIVE)
	_punch_sprite()
	EventBus.spawn_enemy_requested.emit(enemy_id, global_position)
	revealed.emit(self)
	queue_free()
	return true
