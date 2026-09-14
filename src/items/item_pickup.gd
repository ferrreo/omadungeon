## Ground drop of a generated item (docs §7: "elites always drop a Rare+ item"). Unlike gold,
## hearts and stat orbs this is *not* a homing pickup: an item changes the build, so the
## player has to ask for it. It is an `Interactable` — walk up, read the compare card the
## HUD shows while you stand on it, press the interact key to equip. Whatever it displaces is
## dropped back on the floor as another ItemPickup, so a swap is always reversible and nothing
## is ever destroyed.
##
## Because it carries a RefCounted payload it cannot travel through
## `EventBus.spawn_pickup(kind, pos, amount)`; `EnemyBase._drop_elite_item()` builds it
## directly with `ItemPickup.drop(parent, item, pos, rng)`. It frees itself when a new floor
## starts, so an uncollected drop never follows the player down the stairs.
class_name ItemPickup
extends Interactable

## Emitted after a successful equip. `replaced` is the item put back on the floor, or null.
signal equipped(item: ItemInstance, replaced: ItemInstance)

## Seconds before the drop accepts an interact, so the key press that equipped one item
## cannot immediately re-equip the item it displaced.
const SETTLE_TIME := 0.4
## How far the spawn hop throws the drop.
const SCATTER_DISTANCE := 11.0
const SCATTER_TIME := 0.35
## Distance from the wearer the displaced item is put down at.
const DISPLACE_DISTANCE := 13.0
const DETECT_SIZE := Vector2(30, 30)
const RADIUS := 3.5
const RETINT_TIME := 0.6
## How close the player has to stand for the HUD to put the full compare card up
## (`ItemTooltip.Level.CLOSE`); inside the detection box but outside this only the name tag
## shows. The card used to appear at the edge of the 30 px box and block half the room.
const CLOSE_RADIUS := 12.0

## The item handed to the player on interact. Set before the node enters the tree.
var item: ItemInstance
## Where the drop lands; applied when it enters the tree (see `drop`).
var spawn_position: Vector2 = Vector2.ZERO
## Direction of the spawn hop; applied on `_ready`.
var hop_direction: Vector2 = Vector2.ZERO

var _age: float = 0.0
var _color: Color = Color(0.95, 0.8, 0.3)
## The rim behind the diamond, transparent when the ink clears every surface alone (`LootInk`).
var _halo: Color = Color.TRANSPARENT
## The hover level last told to the HUD (`ItemTooltip.Level`), so it is only re-sent on change.
var _hover: int = 0
var _retint: Tween


func _init() -> void:
	super()
	detect_size = DETECT_SIZE
	prompt_text = "Equip"


## Spawns a drop for `item` under `parent` at `pos` with a small scatter hop.
## Returns the node (null when `parent` or `item` is missing). `rng` picks the hop direction;
## without one the hop is derived from the item's uid, so no drop ever calls global `randf()`.
##
## `scatter` is false for a drop that is being *put back* rather than dropped: the hop belongs
## to the moment of the drop, and replaying it on every resume walks the item further from its
## saved spot each time (`FloorPickups.apply`). It has to be answered here, before the node
## enters the tree, because `_ready` performs the hop - clearing `hop_direction` on the
## returned node only worked while every insertion was deferred.
##
## The insertion is deferred *while the physics server is flushing its queries* and only then,
## which is the distinction `PhysicsFlush` exists to make: an elite dies inside a `Hitbox`
## overlap callback, and an Area2D entering the tree during that window has its collider
## refused by the server. Outside one - `FloorPickups.apply()` replaying a resume, an equip
## swap putting the old item down - the insertion happens immediately, so the node the caller
## gets back is already in the tree. Deferring unconditionally meant a snapshot taken in the
## same frame as a resume (`SaveManager` flushes on `NOTIFICATION_WM_CLOSE_REQUEST` with no
## debounce) swept a floor whose items were still in the message queue and wrote them away.
static func drop(
	parent: Node,
	drop_item: ItemInstance,
	pos: Vector2,
	rng: RandomNumberGenerator = null,
	scatter: bool = true
) -> ItemPickup:
	if parent == null or drop_item == null:
		return null
	var pickup := ItemPickup.new()
	pickup.item = drop_item
	pickup.spawn_position = pos
	var angle := rng.randf() * TAU if rng != null else float(drop_item.uid % 360) * TAU / 360.0
	pickup.hop_direction = Vector2.RIGHT.rotated(angle) if scatter else Vector2.ZERO
	if PhysicsFlush.is_flushing():
		pickup._attach.call_deferred(parent)
	else:
		pickup._attach(parent)
	return pickup


## The insertion itself, called directly by `drop` outside a physics flush and deferred into
## the frame's message queue inside one.
func _attach(parent: Node) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		# queue_free() rather than free(): the export build's parser rejects both the bare
		# and the qualified form here ("Function free() not found in base self"), and this
		# node has no parent to detach from, so deferred deletion is equivalent.
		queue_free()
		return
	parent.add_child(self)
	global_position = spawn_position


func _ready() -> void:
	super()
	z_index = 2
	global_position = spawn_position
	_color = _rarity_color()
	_halo = LootInk.halo_for(_color, PickupBase.world_palette_for(self))
	hop(hop_direction)
	if item != null:
		prompt_text = "Equip %s" % item.display_name
	body_entered.connect(_on_player_near)
	body_exited.connect(_on_player_away)
	tree_exiting.connect(_on_leaving)
	EventBus.floor_started.connect(_on_floor_started)
	EventBus.equipment_changed.connect(_on_equipment_changed)
	EventBus.palette_changed.connect(_on_palette_changed)
	# Out of the darkness on a dark theme, with the surface under it on a light one
	# (`LightRig.loot_mask`, docs 10).
	_mask_loot()
	set_process(true)


## Throws the drop a short distance in `direction` when it lands on the floor.
func hop(direction: Vector2) -> void:
	if direction.length_squared() < 0.001:
		return
	var target := global_position + direction.normalized() * SCATTER_DISTANCE
	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, ^"global_position", target, SCATTER_TIME)


## Only after the settle hop, and only while it still holds an item.
func can_interact() -> bool:
	return enabled and item != null and _age >= SETTLE_TIME


func _process(delta: float) -> void:
	_age += delta
	if _age < SETTLE_TIME + 0.1:
		_refresh_prompt()
	_refresh_hover()
	queue_redraw()


## Tells the HUD how close the player is: the name tag inside the box, the compare card only
## within `CLOSE_RADIUS`. Sent on change only, so a player standing still costs nothing.
func _refresh_hover() -> void:
	var player := nearby_player()
	var want := 0
	if player != null and item != null and enabled:
		var close := global_position.distance_to(player.global_position) <= CLOSE_RADIUS
		want = 2 if close else 1
	if want == _hover:
		return
	_hover = want
	EventBus.item_hover.emit(self, item, want)


## The hover level last sent (`ItemTooltip.Level`), for tests.
func hover_level() -> int:
	return _hover


## Equips the item for `by`, puts whatever it displaced back on the floor, and says so.
func _on_interact(by: Node2D) -> bool:
	# `Interactable.interact()` only checks `enabled`, so the settle guard has to be re-stated
	# here: a direct call must not be able to equip a drop the dispatcher would refuse.
	if by == null or not can_interact():
		return false
	var gear := _equipment_of(by)
	var displaced: ItemInstance = null
	if gear != null:
		displaced = gear.get_item(gear.target_slot(item))
	if not PickupBase.call_player(by, &"equip", [item]):
		push_warning("ItemPickup: player has no equip(item)")
		return false
	if displaced != null and displaced != item:
		_put_down(displaced, by)
		EventBus.toast.emit(
			"Equipped %s — %s dropped" % [item.display_name, displaced.display_name], 2.0
		)
	else:
		EventBus.toast.emit("Equipped %s" % item.display_name, 1.5)
	equipped.emit(item, displaced)
	item = null
	enabled = false
	_refresh_hover()
	queue_free()
	return true


## The player's Equipment, when the items module owns their loadout.
static func _equipment_of(player: Node2D) -> Equipment:
	if player == null:
		return null
	return player.get(&"equipment") as Equipment


## Drops `displaced` next to `by` so the swap can be undone. The direction is derived from the
## item's uid rather than a global roll, so the same swap always puts it in the same place.
func _put_down(displaced: ItemInstance, by: Node2D) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var angle := float(displaced.uid % 360) * TAU / 360.0
	var pos := by.global_position + Vector2.RIGHT.rotated(angle) * DISPLACE_DISTANCE
	# The new drop starts its own SETTLE_TIME, so the key press that displaced this item
	# cannot pick it straight back up.
	ItemPickup.drop(parent, displaced, pos)


## Pickups belong to the floor they dropped on (see PickupSpawner.clear_pickups).
func _on_floor_started(_floor_index: int) -> void:
	queue_free()


func _on_player_near(body: Node2D) -> void:
	if body.is_in_group(Interactable.PLAYER_GROUP):
		_refresh_hover()


func _on_player_away(_body: Node2D) -> void:
	_refresh_hover()


## The drop is leaving the tree (picked up, or the floor torn down): the HUD must not keep
## showing a tag for something that is gone.
func _on_leaving() -> void:
	if _hover != 0:
		_hover = 0
		EventBus.item_hover.emit(self, item, 0)


## The worn gear changed under the card: send the level again so the HUD rebuilds it.
func _on_equipment_changed(_slot: StringName, _worn: RefCounted) -> void:
	if _hover == 2:
		EventBus.item_hover.emit(self, item, _hover)


## The colour the diamond is painted right now, including a retint still crossfading. Read by
## `PickupWorldRolesTest` and by the `pickup_frame` rendered check, which need the colour the
## node chose rather than the one the palette would hand out.
func draw_color() -> Color:
	return _color


## The rim behind the diamond, transparent when the ink needs none (`LootInk`).
func draw_halo() -> Color:
	return _halo


## The colour the diamond is painted, from the rarity of the item lying under it.
##
## `world_color()` and not `get_color()`, for the reason `PickupBase` gives: a drop is not a
## piece of HUD sitting on a plate, it is an object lying in the room that pops, bobs and gets
## knocked against the wall, so it is guarded against every surface the dungeon paints rather
## than the three a widget can sit on. This node is the one the first pass of that guard missed
## - it is an `Interactable` rather than a `PickupBase`, so routing the homing pickups through
## `world_color()` left the item drop still reading the plain role and still invisible on a
## light floor while the coin beside it was fixed.
func _rarity_color() -> Color:
	var palette := PickupBase.world_palette_for(self)
	if item == null or palette == null:
		return _color
	return palette.world_color(item.rarity_role())


## Deferred for the reason `PickupBase._on_palette_changed` gives: the floor re-exposes its own
## palette from this same signal and nothing orders the two handlers.
func _on_palette_changed(_palette: ThemePalette) -> void:
	_mask_loot()
	_start_retint.call_deferred()


## Puts the drop and every part of it on the mask loot draws itself with right now.
func _mask_loot() -> void:
	var mask := LightRig.loot_mask()
	light_mask = mask
	for child: Node in get_children():
		if child is CanvasItem:
			(child as CanvasItem).light_mask = mask


func _start_retint() -> void:
	if not is_inside_tree():
		return
	if _retint != null and _retint.is_valid():
		_retint.kill()
	_retint = create_tween()
	_retint.tween_method(_set_color, _color, _rarity_color(), RETINT_TIME)


func _set_color(c: Color) -> void:
	_color = c
	_halo = LootInk.halo_for(_color, PickupBase.world_palette_for(self))
	queue_redraw()


## Rarity-tinted diamond, so a dropped item never reads as a coin.
func _draw() -> void:
	if item == null:
		return
	var bob := sin(_age * 5.0) * 1.0
	draw_circle(Vector2(0.0, RADIUS * 0.7), RADIUS * 0.9, Color(0, 0, 0, 0.3))
	var center := Vector2(0.0, -RADIUS - bob)
	var points := PackedVector2Array(
		[
			center + Vector2(0, -RADIUS),
			center + Vector2(RADIUS, 0),
			center + Vector2(0, RADIUS),
			center + Vector2(-RADIUS, 0),
		]
	)
	# The halo is the same diamond drawn first and left as a rim (`LootInk`). The vertices go
	# out by twice `HALO_WIDTH`, not once: a diamond's edges move out by the corner offset over
	# root two, so a one-pixel corner is a 0.7 px edge that rounds away at this size. Measured
	# on `pickup_frame` catppuccin-latte, a 1.5x reach left the rim covering the tile's outline
	# rung and almost none of the wall speckle, and the drop still read 2.51:1 on `wall`; at 2x
	# it reads 4.39:1.
	if LootInk.has_halo(_halo):
		var reach := RADIUS + LootInk.HALO_WIDTH * 2.0
		draw_colored_polygon(
			PackedVector2Array(
				[
					center + Vector2(0, -reach),
					center + Vector2(reach, 0),
					center + Vector2(0, reach),
					center + Vector2(-reach, 0),
				]
			),
			_halo
		)
	draw_colored_polygon(points, _color)
	draw_circle(
		center + Vector2(-RADIUS * 0.25, -RADIUS * 0.3), RADIUS * 0.28, _color.lightened(0.6)
	)
