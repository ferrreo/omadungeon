## The in-run scene: floor root, player, camera, HUD and overlays. Owned by `RunManager`,
## which builds floors through `load_floor()`. This node holds only view concerns: minimap
## refreshes, damage numbers, screen tint, unlock toasts and the pause/chest input guard.
class_name Game
extends Node2D

## Seconds the Kernel-Panic style full-screen tint takes to fade out when none is given.
const TINT_FADE := 0.6

var floor_root: FloorRoot
var floor_index: int = 0

@onready var floor_container: Node2D = %FloorContainer
@onready var player: Player = %Player
@onready var camera: PlayerCamera = %Camera
@onready var hud: Hud = %Hud
@onready var chest_ui: ChestUi = %ChestUi
@onready var pause_menu: PauseMenu = %PauseMenu
@onready var loadout: LoadoutScreen = %Loadout
@onready var hazard_spawner: HazardSpawner = %HazardSpawner
@onready var pickup_spawner: PickupSpawner = %PickupSpawner
@onready var tint: ColorRect = %Tint


func _ready() -> void:
	hud.bind(player)
	camera.follow(player)
	pause_menu.bind(player)
	loadout.bind(player)
	pause_menu.open_guard = func() -> bool: return not (chest_ui.is_open() or loadout.is_open())
	tint.color = Color(0, 0, 0, 0)
	EventBus.player_hit_dealt.connect(_on_player_hit_dealt)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.screen_tint.connect(_on_screen_tint)
	EventBus.unlock_earned.connect(_on_unlock_earned)
	EventBus.palette_changed.connect(_on_palette_changed)
	_refresh_clear_color()


## Builds `data` as the live floor. `loot_rng` drives the build-time rolls (chest kinds,
## props); pass a deterministic stream from `RunRng`. `light_scale` is the music's multiplier
## on the floor light (`GenParams.light_scale`, docs 10.2).
func load_floor(
	data: FloorData, index: int, loot_rng: RandomNumberGenerator = null, light_scale: float = 1.0
) -> void:
	unload_floor()
	floor_index = index
	floor_root = FloorRoot.new()
	floor_root.name = "FloorRoot"
	floor_root.light_scale = light_scale
	floor_container.add_child(floor_root)
	data.floor_index = index
	floor_root.build_with_biome(data, Biome.load_by_id(data.biome), loot_rng)
	hazard_spawner.parent_node = floor_root
	pickup_spawner.container_path = pickup_spawner.get_path()
	camera.set_limits(floor_root.camera_limits())
	hud.set_floor(index, String(data.biome).capitalize())
	loadout.set_context(Hud.floor_text(index, String(data.biome).capitalize()), GameState.run_seed)
	refresh_minimap()


## Tears the current floor down (rooms stop reacting to stray signals first).
func unload_floor() -> void:
	if is_instance_valid(floor_root):
		floor_root.clear_floor()
		floor_root.queue_free()
	floor_root = null


## Pushes the floor's room/corridor model into the HUD minimap.
func refresh_minimap() -> void:
	if not is_instance_valid(floor_root) or floor_root.data == null:
		return
	hud.set_minimap(
		floor_root.minimap_rooms(), floor_root.minimap_edges(), floor_root.minimap_links()
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and not chest_ui.is_open() and not loadout.is_open():
		pause_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"map") and not chest_ui.is_open() and not pause_menu.is_open():
		# Tab (Back on a pad): the build screen, straight from the run and back out again.
		loadout.toggle()
		get_viewport().set_input_as_handled()


func _on_player_hit_dealt(target: Node2D, info: DamageInfo) -> void:
	if not _damage_numbers_on() or target == null or not is_instance_valid(target):
		return
	var amount := info.applied if info.applied > 0.0 else info.amount
	if amount <= 0.0:
		return
	EventBus.damage_number.emit(target.global_position, amount, info.is_crit, _damage_color(info))


func _on_player_damaged(amount: int, _source: Node2D) -> void:
	if not _damage_numbers_on() or amount <= 0 or not is_instance_valid(player):
		return
	EventBus.damage_number.emit(
		player.global_position, float(amount), false, _palette_color(&"danger")
	)


static func _damage_numbers_on() -> bool:
	return bool(GameState.settings.get("damage_numbers", true))


static func _palette_color(role: StringName) -> Color:
	if Desktop.palette == null:
		return Color.WHITE
	return Desktop.palette.get_color(role)


## Element colour of a hit, so fire/frost/shock numbers read differently.
static func _damage_color(info: DamageInfo) -> Color:
	if info.has_tag(DamageInfo.TAG_FIRE):
		return _palette_color(&"heat")
	if info.has_tag(DamageInfo.TAG_FROST):
		return _palette_color(&"cold")
	if info.has_tag(DamageInfo.TAG_ARCANE) or info.has_tag(DamageInfo.TAG_SHOCK):
		return _palette_color(&"magic")
	if info.is_crit:
		return _palette_color(&"loot")
	return _palette_color(&"text_bright")


func _on_screen_tint(color: Color, duration: float) -> void:
	tint.color = color
	var fade := duration if duration > 0.0 else TINT_FADE
	var tween := create_tween()
	tween.tween_property(tint, "color:a", 0.0, fade)


func _on_unlock_earned(_id: StringName, title: String) -> void:
	EventBus.toast.emit("Unlocked: %s" % title, 3.0)


func _on_palette_changed(_palette: ThemePalette) -> void:
	_refresh_clear_color()


## Everything outside the floor grid is the theme's void colour, not the engine default grey.
static func _refresh_clear_color() -> void:
	RenderingServer.set_default_clear_color(_palette_color(&"void"))
