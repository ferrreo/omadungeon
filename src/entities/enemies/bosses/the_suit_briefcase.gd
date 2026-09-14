## One of the two briefcases The Suit opens in phase 3 ("Exit Liquidity"). While a briefcase
## is intact the boss buys its own health back, so the fight is about breaking them.
##
## The case is invulnerable to normal damage: its armoured shell ignores the *amount* of every
## hit and pops one latch per landed player hit instead, so a slow hammer and a fast dagger
## break it in the same number of swings and no damage stat can trivialise the phase. Latches
## are drawn as pips above the case so the player can read the progress at 480x270.
class_name TheSuitBriefcase
extends Node2D

## Emitted when the last latch popped (the boss stops healing once both cases are broken).
signal broken(briefcase: TheSuitBriefcase)
## Emitted on every latch that pops (remaining latches).
signal latch_popped(left: int)

const SIZE := Vector2(14.0, 10.0)
const HURTBOX_SIZE := Vector2(16.0, 14.0)
## Seconds of immunity after a latch pops (a multi-hit weapon may not strip it in one frame).
const HIT_COOLDOWN := 0.12
const FALLBACK_GOLD := Color(0.95, 0.78, 0.25)

## Latches left; the case bursts at 0.
var latches: int = 4
var max_latches: int = 4
var is_broken: bool = false
var hurtbox: Hurtbox

var _cooldown: float = 0.0
var _flash: float = 0.0
var _bob: float = 0.0


func _ready() -> void:
	add_to_group(&"briefcase")
	z_index = 1
	var box := LatchHurtbox.new()
	box.name = "Hurtbox"
	box.owner_case = self
	box.team = Layers.Team.ENEMY
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = HURTBOX_SIZE
	shape.shape = rect
	box.add_child(shape)
	add_child(box)
	hurtbox = box
	EventBus.palette_changed.connect(_on_palette_changed)
	set_physics_process(true)


## Configures the case before it is added to the tree.
func setup(latch_count: int) -> void:
	max_latches = maxi(1, latch_count)
	latches = max_latches


## Pops one latch. Returns true when this hit counted (false while on cooldown/broken).
func pop_latch() -> bool:
	if is_broken or _cooldown > 0.0:
		return false
	_cooldown = HIT_COOLDOWN
	_flash = 1.0
	latches -= 1
	latch_popped.emit(latches)
	EventBus.screen_shake.emit(1.5, 0.12)
	queue_redraw()
	if latches <= 0:
		_burst()
	return true


func _burst() -> void:
	is_broken = true
	if hurtbox != null:
		hurtbox.set_deferred(&"monitorable", false)
		hurtbox.set_deferred(&"collision_layer", 0)
	broken.emit(self)
	var burst := CPUParticles2D.new()
	burst.amount = 18
	burst.lifetime = 0.5
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.spread = 180.0
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 90.0
	burst.gravity = Vector2(0.0, 160.0)
	burst.color = _gold_color()
	burst.emitting = true
	add_child(burst)
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.35)
	fade.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	_bob += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		queue_redraw()


func _draw() -> void:
	var gold := _gold_color()
	var dark := gold.darkened(0.55)
	var lift := sin(_bob * 3.0) * 0.8
	var body := Rect2(-SIZE.x * 0.5, -SIZE.y + lift, SIZE.x, SIZE.y)
	draw_rect(body.grow(1.0), Color(0.05, 0.05, 0.06, 0.9))
	draw_rect(body, gold if _flash <= 0.0 else gold.lightened(_flash * 0.6))
	draw_rect(Rect2(body.position.x, body.position.y + SIZE.y * 0.45, SIZE.x, 1.0), dark)
	draw_rect(Rect2(-3.0, body.position.y - 2.0, 6.0, 2.0), dark)
	for i in range(max_latches):
		var x := -float(max_latches - 1) * 1.5 + float(i) * 3.0
		var popped := i >= latches
		var pip := Color(0.25, 0.25, 0.28, 0.9) if popped else gold
		draw_rect(Rect2(x - 1.0, body.position.y - 6.0, 2.0, 2.0), pip)


func _gold_color() -> Color:
	if Desktop.palette == null:
		return FALLBACK_GOLD
	return Desktop.palette.get_color(&"accent")


func _on_palette_changed(_palette: ThemePalette) -> void:
	queue_redraw()


## Hurtbox that translates any incoming player hit into exactly one popped latch.
class LatchHurtbox:
	extends Hurtbox

	var owner_case: TheSuitBriefcase

	func receive(info: DamageInfo) -> float:
		if owner_case == null or not is_instance_valid(owner_case) or info == null:
			return 0.0
		if info.team == Layers.Team.ENEMY:
			return 0.0
		if not owner_case.pop_latch():
			return 0.0
		hit_received.emit(info)
		return 1.0
