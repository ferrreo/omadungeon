## Reward chest spawned when a room clears (docs §8). Kind is rolled by room type and floor;
## the UI module reads `kind` on EventBus.chest_opened to build the 1-of-3 offer.
## Frames in assets/sprites/props/chest.png (16x16): closed, open, glow, wobble.
class_name Chest
extends Interactable

enum Kind { STAT, ITEM, ABILITY, GOLD, CURSED }

const SPRITE_PATH := "res://assets/sprites/props/chest.png"
const FRAME_CLOSED := 0
const FRAME_OPEN := 1
const FRAME_GLOW := 2
const FRAME_WOBBLE := 3
const FRAME_COUNT := 4
## Base weights per room type (docs §8: stat chests most common). CURSED grows with floor.
const WEIGHTS: Dictionary = {
	FloorData.RoomType.COMBAT:
	{Kind.STAT: 45, Kind.ITEM: 22, Kind.ABILITY: 15, Kind.GOLD: 12, Kind.CURSED: 3},
	FloorData.RoomType.ELITE:
	{Kind.STAT: 30, Kind.ITEM: 28, Kind.ABILITY: 30, Kind.GOLD: 5, Kind.CURSED: 5},
	FloorData.RoomType.TRAP:
	{Kind.STAT: 35, Kind.ITEM: 25, Kind.ABILITY: 15, Kind.GOLD: 20, Kind.CURSED: 3},
	FloorData.RoomType.TREASURE:
	{Kind.STAT: 20, Kind.ITEM: 35, Kind.ABILITY: 10, Kind.GOLD: 28, Kind.CURSED: 5},
	FloorData.RoomType.BOSS:
	{Kind.STAT: 15, Kind.ITEM: 35, Kind.ABILITY: 40, Kind.GOLD: 3, Kind.CURSED: 5},
}
## Extra CURSED weight per floor index.
const CURSED_PER_FLOOR := 1
const WOBBLE_INTERVAL := 2.4
const WOBBLE_FLASH := 0.12
const GLOW_PERIOD := 1.4

## Nodes in this group are asked `can_open_chest(chest) -> bool` *before* a chest is
## consumed, and any "no" leaves it closed, prompt and all. RunManager joins the group so the
## Oligarch's Buyout price is charged first: a chest they cannot pay for can be tried again
## once they have the gold, instead of being lost. With nobody in the group every chest opens.
const OPEN_GUARD_GROUP := &"chest_open_guard"

var kind: Kind = Kind.STAT
## True once the lid is open: the player pressed the key and the offer went up. It is *not*
## "the player has the reward" — see `reward_taken`.
var is_opened: bool = false
## True once the offer this chest put on screen was actually answered (a prize taken, or the
## board knowingly skipped for the gold). `RunManager._finish_offer()` is the only thing that
## sets it, through `mark_taken()`.
##
## The two used to be one flag, and that is how a reward could be destroyed: the autosave a
## room clear queues fires while the picker is up (the tree is paused, `SaveManager` is
## `PROCESS_MODE_ALWAYS`), so `run.json` recorded the chest as looted with nothing granted. A
## session that ended there — Alt-F4, a crash, a power cut — resumed to an opened, empty
## chest. The save contract reads this flag now (`FloorRestore.reward_taken`), so a chest
## saved mid-offer comes back closed and still worth opening.
var reward_taken: bool = false
## Trapped chests (Treasure rooms) wobble faintly; the traps module decides the payload.
var is_trapped: bool = false:
	set(value):
		is_trapped = value
		_refresh_wobble()
var sprite: Sprite2D
var glow: Sprite2D
## The loot-coloured light a closed chest throws (`LightEmitter`), out when it opens.
var _light: LightEmitter
var _glow_tween: Tween
var _wobble_tween: Tween


func _init() -> void:
	super()
	prompt_text = "Open chest"
	detect_size = Vector2(36, 36)


func _ready() -> void:
	super()
	var tex := _load_sprite()
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	sprite.hframes = FRAME_COUNT
	sprite.frame = FRAME_OPEN if is_opened else FRAME_CLOSED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	glow = Sprite2D.new()
	glow.name = "Glow"
	glow.texture = tex
	glow.hframes = FRAME_COUNT
	glow.frame = FRAME_GLOW
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow.z_index = 1
	add_child(glow)
	if not is_opened:
		_light = LightEmitter.attach(self, &"chest")
	_apply_palette(TileRamp.live_palette())
	EventBus.palette_changed.connect(_on_palette_changed)
	_start_glow()
	_pop_in()
	_refresh_wobble()


## Weight table for a room type: `data/rooms/rooms_content.tres` when it defines one,
## else the WEIGHTS constant. `content` is injectable for tests.
static func weights_for(room_type: FloorData.RoomType, content: RoomsContent = null) -> Dictionary:
	var res := RoomsContent.resolve(content)
	if res != null:
		var table: Dictionary = res.weights_for(int(room_type))
		if not table.is_empty():
			return table
	return WEIGHTS.get(room_type, WEIGHTS[FloorData.RoomType.COMBAT])


## Extra CURSED weight per floor index: from `rooms_content.tres` when it sets a non-negative
## value, else the CURSED_PER_FLOOR constant. `content` is injectable for tests.
static func cursed_per_floor(content: RoomsContent = null) -> int:
	var res := RoomsContent.resolve(content)
	if res != null and res.chest_cursed_per_floor >= 0:
		return res.chest_cursed_per_floor
	return CURSED_PER_FLOOR


## Rolls the chest kind for a cleared room (docs §8). Deterministic per rng.
static func roll_kind(
	rng: RandomNumberGenerator, room_type: FloorData.RoomType, floor_index: int
) -> Kind:
	var table := weights_for(room_type)
	var per_floor := cursed_per_floor()
	var total := 0
	var weights: Dictionary = {}
	for k: Kind in Kind.values():
		var w: int = int(table.get(k, 0))
		if k == Kind.CURSED:
			w += per_floor * maxi(floor_index, 0)
		weights[k] = w
		total += w
	var roll := rng.randi_range(0, maxi(total - 1, 0))
	for k: Kind in Kind.values():
		roll -= int(weights[k])
		if roll < 0:
			return k
	return Kind.STAT


static func kind_name(k: Kind) -> String:
	return String(Kind.keys()[k]).capitalize()


## Finalises the chest once RunManager's offer flow ended (idempotent). This — and only this
## — is what makes the reward spent, so a save taken before it still owes the player a pick.
func mark_taken() -> void:
	is_opened = true
	reward_taken = true
	enabled = false
	_refresh_wobble()
	if sprite != null:
		sprite.frame = FRAME_OPEN
	if glow != null:
		glow.modulate.a = 0.0
	_put_light_out()
	super()


## True while the chest is closed. The open guards are not consulted here: one of them may
## charge gold, so only the actual open attempt in `_on_interact` may ask them.
func can_interact() -> bool:
	return enabled and not is_opened


## Asks every node in OPEN_GUARD_GROUP whether this chest may open now. A guard that says no
## has already told the player why.
func _open_allowed() -> bool:
	if not is_inside_tree():
		return true
	for node: Node in get_tree().get_nodes_in_group(OPEN_GUARD_GROUP):
		if node.has_method(&"can_open_chest") and not bool(node.call(&"can_open_chest", self)):
			return false
	return true


## Resume: puts the lid back open for an offer that was still on screen when the run was
## saved, without the open guards, the burst or the `chest_opened` signal — `RunManager`
## re-drives the offer itself, and the Oligarch's Buyout was already paid for this open.
## False when there is nothing to re-open (the reward is spent, or the lid is already up).
func reopen_offer() -> bool:
	if reward_taken or is_opened:
		return false
	_open_lid()
	return true


## Opens the chest; emits EventBus.chest_opened(self). Returns false when already open or when
## a guard refused — the chest is then left closed and usable, nothing has been consumed.
##
## Note what this does *not* do: it does not mark the reward taken. The offer it raises has
## not been answered yet, and until it is, this chest still owes the player a pick.
func _on_interact(_by: Node2D) -> bool:
	if is_opened:
		return false
	if not _open_allowed():
		return false
	_open_lid()
	_burst()
	EventBus.chest_opened.emit(self)
	return true


## The lid animation and the "no longer interactable" state, shared by a real open and a
## resumed one.
func _open_lid() -> void:
	is_opened = true
	prompt_text = "Open chest"
	enabled = false
	_refresh_wobble()
	if sprite != null:
		sprite.frame = FRAME_OPEN
		var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		sprite.scale = Vector2(1.25, 0.75)
		t.tween_property(sprite, ^"scale", Vector2.ONE, 0.22)
	if glow != null:
		if _glow_tween != null and _glow_tween.is_valid():
			_glow_tween.kill()
		var g := create_tween()
		g.tween_property(glow, ^"modulate:a", 0.0, 0.3)
	_put_light_out()


## An open chest throws no light.
func _put_light_out() -> void:
	if _light != null and is_instance_valid(_light):
		_light.release()
	_light = null


func _load_sprite() -> Texture2D:
	if ResourceLoader.exists(SPRITE_PATH):
		var tex := load(SPRITE_PATH) as Texture2D
		if tex != null:
			return tex
	if FileAccess.file_exists(SPRITE_PATH):
		var img_file := Image.load_from_file(SPRITE_PATH)
		if img_file != null:
			return ImageTexture.create_from_image(img_file)
	var img := Image.create(Layers.TILE * FRAME_COUNT, Layers.TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for f in range(FRAME_COUNT):
		img.fill_rect(Rect2i(f * Layers.TILE + 2, 4, 12, 10), TileRamp.RAMP[3])
	return ImageTexture.create_from_image(img)


func _apply_palette(palette: ThemePalette) -> void:
	if glow == null:
		return
	var c := palette.get_color(&"loot")
	glow.modulate = Color(c.r, c.g, c.b, glow.modulate.a)


func _on_palette_changed(palette: ThemePalette) -> void:
	if glow == null or not is_inside_tree():
		return
	var c := palette.get_color(&"loot")
	var t := create_tween()
	t.tween_property(
		glow, ^"modulate", Color(c.r, c.g, c.b, glow.modulate.a), TileRamp.RETINT_SECONDS
	)


## Starts/stops the single looping wobble tween that tells the player a chest is trapped.
func _refresh_wobble() -> void:
	if _wobble_tween != null and _wobble_tween.is_valid():
		_wobble_tween.kill()
	_wobble_tween = null
	if sprite != null and not is_opened:
		sprite.frame = FRAME_CLOSED
	if not is_trapped or is_opened or sprite == null or not is_inside_tree():
		return
	_wobble_tween = create_tween().set_loops()
	_wobble_tween.tween_interval(WOBBLE_INTERVAL)
	_wobble_tween.tween_callback(func() -> void: _set_frame(FRAME_WOBBLE))
	_wobble_tween.tween_interval(WOBBLE_FLASH)
	_wobble_tween.tween_callback(func() -> void: _set_frame(FRAME_CLOSED))


func _set_frame(frame_index: int) -> void:
	if sprite != null and not is_opened:
		sprite.frame = frame_index


func _start_glow() -> void:
	if glow == null or is_opened:
		if glow != null:
			glow.modulate.a = 0.0
		return
	glow.modulate.a = 0.35
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(glow, ^"modulate:a", 0.85, GLOW_PERIOD / 2.0).set_trans(
		Tween.TRANS_SINE
	)
	_glow_tween.tween_property(glow, ^"modulate:a", 0.35, GLOW_PERIOD / 2.0).set_trans(
		Tween.TRANS_SINE
	)


func _pop_in() -> void:
	if sprite == null or is_opened:
		return
	sprite.scale = Vector2(0.2, 1.4)
	var t := create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_property(sprite, ^"scale", Vector2.ONE, 0.45)


func _burst() -> void:
	var p := CPUParticles2D.new()
	p.name = "Burst"
	p.one_shot = true
	p.emitting = true
	p.amount = 14
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, 220)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = TileRamp.live_palette().get_color(&"loot")
	add_child(p)
	var t := create_tween()
	t.tween_interval(p.lifetime + 0.1)
	t.tween_callback(p.queue_free)
