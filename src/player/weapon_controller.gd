## Drives the player's primary/secondary attack from a WeaponBase (docs §4.5). Lives under the
## player's WeaponPivot (which the Player rotates to the aim direction), so +X is "forward".
## Styles: MELEE_ARC swing + combo, MELEE_THRUST thrust + lunging finisher, RANGED_BOW
## hold-to-charge, RANGED_WAND auto-fire homing bolts, THROWN lobbed shots. Damage is built
## through `Player.make_damage`.
##
## Every style obeys the one control model in docs §4.1: **holding the attack button keeps
## attacking**. A bow does that by firing itself the instant the charge tops out and starting
## the next draw, so a held button is a stream of full-power shots rather than an eternal
## wind-up; tapping still fires the weak, fast shot. The draw itself scales with the
## `attack_speed` stat (`full_charge_time()`), so attack speed is worth the same to a bow as
## to a sword — without that the charge is a hard floor and the stat buys a bow user nothing.
##
## Every melee attack runs three beats (`Phase`): a short ANTICIPATION wind-back, the IMPACT
## sweep, then a RECOVERY the player can cancel out of with a dodge or the weapon skill. The
## hitbox is live from the first frame of the anticipation, so the wind-back reads as weight
## without ever eating a swing the player already committed to.
##
## **How the weapon is held.** The visual hangs off three nodes, and each one owns exactly one
## thing, which is what stops a turn from putting the weapon on the wrong side of the body:
##
## * `Arm` is the animation. Its rotation is the swing arc and its `position.x` is the thrust
##   and the recoil, both in the pivot's frame, where +X is the aim.
## * `Hand` is where the weapon is gripped: `WeaponGrip.reach` along the aim and
##   `WeaponGrip.lateral` to the near side of the body, and `scale.y = -1` while the character
##   is drawn facing left. That negative scale is a **mirror about the aim line**, which is what
##   `set_mirrored` means: turning around flips the weapon's art the way it flips the
##   character's, instead of the aim rotation carrying the art through 180 degrees and standing
##   it on its head.
## * `WeaponSprite` is the art, offset so the *grip pixel* of its cell — not the middle of the
##   square inventory icon — sits on the Hand's origin, and pre-rotated so the weapon's own
##   diagonal axis points along +X.
##
## `Player.refresh_carry` drives the mirror, the tuck (the weapon is pulled in against the body
## through a dodge instead of swinging around on a straight arm) and the depth: aim far enough
## upscreen and the whole pivot draws behind the character, because a weapon held on the far
## side of a body is behind it.
class_name WeaponController
extends Node2D

signal attacked(style: WeaponBase.Style, combo_index: int)
signal projectile_fired(projectile: Projectile)
signal charge_changed(fraction: float)
signal skill_used(skill: ActiveAbility)
signal weapon_changed(weapon: WeaponBase)

## Beats of one attack. RECOVERY is the only phase a dodge or skill may cancel.
enum Phase { READY, ANTICIPATION, IMPACT, RECOVERY }

const WEAPON_ATLAS_PATH := "res://assets/sprites/items/weapons.png"
const ATLAS_FRAME := 16
## Atlas column per weapon family (docs art list).
## Matched longest-word-first, not in insertion order: `longsword` and `greatsword` both
## contain `sword`, and a first-match-wins scan drew both of them as the rusty sword.
const ATLAS_INDEX: Dictionary = {
	&"sword": 0,
	&"longsword": 1,
	&"greatsword": 1,
	&"axe": 2,
	&"spear": 3,
	&"dagger": 4,
	&"stiletto": 4,
	&"shortbow": 5,
	&"bow": 5,
	&"crossbow": 6,
	&"wand": 7,
	&"staff": 8,
	&"knives": 9,
	&"knife": 9,
	&"cane": 10,
	&"fists": 11,
}
## Authored projectile art per weapon `Style`, as `ProjectileSprites` frame indices.
##
## Every player shot used to be a 6x3 white rectangle tinted with the theme accent, while a
## 16-frame hand-drawn projectile sheet shipped and only enemies drew from it. The tint was also
## outside the documented tinting scope: docs §10 puts projectiles with enemies and items,
## keeping "their own authored colours so factions and threats stay readable under any theme".
## No shipped weapon sets `projectile_scene`, so this table is what a player's ranged attack
## actually looks like. Indexed by `WeaponBase.Style`; the melee entries are only reached by a
## skill that fires a shot from a melee weapon.
const STYLE_PROJECTILE_FRAME: Array[int] = [
	ProjectileSprites.BOLT,  # MELEE_ARC
	ProjectileSprites.BOLT,  # MELEE_THRUST
	ProjectileSprites.ARROW,  # RANGED_BOW
	ProjectileSprites.BOLT,  # RANGED_WAND
	ProjectileSprites.KNIFE,  # THROWN
]
## Damage tag to projectile frame, consulted before the style: an elemental shot reads as its
## element whatever launched it. `arcane` is deliberately absent - the wand/staff default is
## already the arcane bolt.
const TAG_PROJECTILE_FRAME: Dictionary = {
	DamageInfo.TAG_FIRE: ProjectileSprites.FIREBALL,
	DamageInfo.TAG_FROST: ProjectileSprites.ICE_SHARD,
	DamageInfo.TAG_SHOCK: ProjectileSprites.SPARK,
}
const MELEE_ACTIVE_TIME := 0.12
## Wind-back before the sweep. The hitbox is already live: the anticipation is weight, not lag.
const MELEE_ANTICIPATION := 0.05
## Extra wind-back angle (radians) on top of the swing arc, so the arm visibly loads up.
const ANTICIPATION_ANGLE := deg_to_rad(22.0)
## Scale the weapon pops to while loading up.
const ANTICIPATION_SCALE := 1.12
const COMBO_RESET_TIME := 0.8
## Extra recovery after a combo finisher, as a multiple of the attack interval.
const FINISHER_RECOVERY := 1.35
## How much further the finishing thrust reaches than the pokes before it.
const THRUST_FINISHER_REACH := 1.45
const WAND_HOMING := 1.5
## Longest a lobbed shot may hang in the air, however far its `range_px` reaches.
const THROWN_LIFETIME := 0.8
const SPREAD_STEP := deg_to_rad(8.0)
const ENEMY_SEARCH_RADIUS := 200.0
## Group every EnemyBase registers itself in (src/entities/enemies/enemy_base.gd).
const ENEMY_GROUP := &"enemy"
## Downward acceleration applied to thrown shots so they visibly arc (px/s²).
const THROWN_GRAVITY := 140.0
## Full turns per second a thrown weapon spins in flight.
const THROWN_SPIN := 3.0
## Arc one swing sweeps through, either side of the aim.
const SWING_ARC := deg_to_rad(70.0)
## Fraction of the normal reach the hand is pulled in to while the player is dodging. A weapon
## left out on a straight arm through a roll is the pose that reads worst of all: the character
## tumbles along the ground and the sword stays pinned in the air beside them.
const TUCK_REACH := 0.25
## How fast the hand travels between the carried and tucked positions (px/s).
const CARRY_SPEED := 90.0

var weapon: WeaponBase
## Equipped ItemInstance (or null for the default fists). Kept untyped to stay decoupled.
var item: RefCounted
## Secondary-attack skill: the Equipment's per-equip copy when given, else `weapon.skill`.
var skill: ActiveAbility
var player: Player
## Where projectiles are parented; defaults to the player's parent.
var projectile_parent: Node
var combo_index: int = 0
var charge_time: float = 0.0
var is_charging: bool = false
var hitbox: Hitbox
## Animation node: rotation is the swing arc, `position.x` the thrust and the recoil.
var arm: Node2D
## Grip node: carries the hand offset and the facing mirror (`scale.y`).
var hand: Node2D
var sprite: Sprite2D

var _cooldown: float = 0.0
var _attack_elapsed: float = -1.0
var _attack_impact_end: float = 0.0
var _combo_timer: float = 0.0
var _pending_release: bool = false
var _pending_aim: Vector2 = Vector2.RIGHT
var _swing_tween: Tween
var _swing_dir: float = 1.0
var _grip: WeaponGrip
## -1 while the character is drawn facing left.
var _mirror: float = 1.0
var _tucked: bool = false
var _hitbox_shape: CollisionShape2D
var _bolt_texture: Texture2D


func _ready() -> void:
	if player == null:
		player = _find_player()
	arm = get_node_or_null("Arm") as Node2D
	if arm == null:
		arm = Node2D.new()
		arm.name = "Arm"
		add_child(arm)
	hand = arm.get_node_or_null("Hand") as Node2D
	if hand == null:
		hand = Node2D.new()
		hand.name = "Hand"
		arm.add_child(hand)
	sprite = hand.get_node_or_null("WeaponSprite") as Sprite2D
	if sprite == null:
		# An older scene keeps the sprite straight under the Arm, where the mirror has nothing
		# to act on; move it into the hand rather than drawing it unanchored.
		sprite = arm.get_node_or_null("WeaponSprite") as Sprite2D
		if sprite != null:
			arm.remove_child(sprite)
			hand.add_child(sprite)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "WeaponSprite"
		hand.add_child(sprite)
	hitbox = get_node_or_null("Hitbox") as Hitbox
	if hitbox == null:
		hitbox = Hitbox.new()
		hitbox.name = "Hitbox"
		hitbox.team = Layers.Team.PLAYER
		_hitbox_shape = CollisionShape2D.new()
		_hitbox_shape.shape = CircleShape2D.new()
		hitbox.add_child(_hitbox_shape)
		add_child(hitbox)
	else:
		_hitbox_shape = hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if _hitbox_shape == null:
			_hitbox_shape = CollisionShape2D.new()
			_hitbox_shape.shape = CircleShape2D.new()
			hitbox.add_child(_hitbox_shape)
	hitbox.team = Layers.Team.PLAYER
	hitbox.collision_mask = Layers.hitbox_mask_for(Layers.Team.PLAYER)
	if player != null:
		hitbox.source = player
	hitbox.hit_dealt.connect(_on_hit_dealt)
	if weapon == null:
		set_weapon(null)
	else:
		_apply_weapon_visuals()


func _find_player() -> Player:
	var node: Node = get_parent()
	while node != null:
		if node is Player:
			return node
		node = node.get_parent()
	return null


## Built-in unarmed weapon used when nothing is equipped.
static func make_fists() -> WeaponBase:
	var fists := WeaponBase.new()
	fists.id = &"fists"
	fists.display_name = "Fists"
	fists.style = WeaponBase.Style.MELEE_ARC
	fists.base_damage = 6.0
	fists.attacks_per_second = 2.5
	fists.range_px = 14.0
	fists.knockback = 40.0
	fists.combo_length = 2
	return fists


## Equips a weapon base (null = fists), its owning item instance and an optional skill copy.
func set_weapon(
	base: WeaponBase, owning_item: RefCounted = null, skill_override: ActiveAbility = null
) -> void:
	weapon = base if base != null else make_fists()
	item = owning_item
	skill = skill_override if skill_override != null else weapon.skill
	combo_index = 0
	is_charging = false
	charge_time = 0.0
	_pending_release = false
	if is_node_ready():
		_apply_weapon_visuals()
	weapon_changed.emit(weapon)


func style() -> WeaponBase.Style:
	return weapon.style if weapon != null else WeaponBase.Style.MELEE_ARC


func is_ranged() -> bool:
	var s := style()
	return (
		s == WeaponBase.Style.RANGED_BOW
		or s == WeaponBase.Style.RANGED_WAND
		or s == WeaponBase.Style.THROWN
	)


func is_ready() -> bool:
	return _cooldown <= 0.0


## Which beat of the current attack is running.
func phase() -> Phase:
	if _attack_elapsed < 0.0:
		return Phase.READY
	if _attack_elapsed < MELEE_ANTICIPATION:
		return Phase.ANTICIPATION
	# The impact window is checked before the cooldown: a weapon fast enough that its interval
	# ends inside its own sweep is still swinging, and must not report a cancellable tail.
	if _attack_elapsed < _attack_impact_end:
		return Phase.IMPACT
	return Phase.READY if is_ready() else Phase.RECOVERY


## True while the attack is in its cancellable tail.
func is_in_recovery() -> bool:
	return phase() == Phase.RECOVERY


## Cuts the recovery short so a dodge or a weapon skill flows straight out of an attack.
## Returns true when there actually was a recovery to cancel.
func cancel_recovery() -> bool:
	if not is_in_recovery():
		return false
	_cooldown = 0.0
	_attack_elapsed = -1.0
	_attack_impact_end = 0.0
	if hitbox != null:
		hitbox.deactivate()
	_return_arm_to_rest()
	return true


## Seconds between attacks: weapon rate scaled by the attack_speed stat.
func attack_interval() -> float:
	var aps := weapon.attacks_per_second if weapon != null else 2.0
	var speed := player.stats.get_value(&"attack_speed") if player != null else 1.0
	return 1.0 / maxf(0.1, aps * maxf(0.2, speed))


## Seconds this bow needs to reach a full draw, shortened by the `attack_speed` stat exactly
## as the attack interval is. `ItemTuning.bow_charge_seconds` is the x1 value.
func full_charge_time() -> float:
	var speed := player.stats.get_value(&"attack_speed") if player != null else 1.0
	return ItemTuning.shared().bow_charge_seconds / maxf(0.2, speed)


func charge_fraction() -> float:
	return clampf(charge_time / maxf(0.01, full_charge_time()), 0.0, 1.0)


## True once the draw is complete: the shot fires on its own from here (docs §4.1).
func is_fully_charged() -> bool:
	return is_charging and charge_fraction() >= 1.0


## Bow damage scaling: taps are weak, a full charge hits hard (and pierces).
static func bow_damage_multiplier(fraction: float) -> float:
	return ItemTuning.shared().bow_damage_multiplier(fraction)


static func bow_speed_multiplier(fraction: float) -> float:
	return ItemTuning.shared().bow_speed_multiplier(fraction)


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0:
			# The attack is over: close the phase timeline instead of letting it run forever.
			_attack_elapsed = -1.0
			_attack_impact_end = 0.0
	if _attack_elapsed >= 0.0:
		_attack_elapsed += delta
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo_index = 0
	if skill != null:
		skill.tick(delta)
	if is_charging:
		var before := charge_fraction()
		charge_time += delta
		var after := charge_fraction()
		if after != before:
			charge_changed.emit(after)
			arm.scale = Vector2.ONE * (1.0 + 0.15 * after)
	if _pending_release and is_ready():
		_pending_release = false
		_fire_bow(_pending_aim)
	_advance_carry(delta)


## Walks the hand towards where the current carry says it should be. Moved rather than snapped
## so sheathing into a dodge and coming back out of one is a motion the eye can follow.
func _advance_carry(delta: float) -> void:
	if hand == null or _grip == null:
		return
	var wanted := _grip.hand_position(_mirror)
	if _tucked:
		wanted = Vector2(_grip.reach * TUCK_REACH, _grip.lateral * _mirror * TUCK_REACH)
	hand.position = hand.position.move_toward(wanted, CARRY_SPEED * delta)


## Mirrors the weapon with the character. `mirrored` is true while the body sprite is flipped,
## and flipping the hand's Y is a reflection about the aim line: the blade keeps its own top
## edge up instead of being carried upside down by a 180-degree aim rotation.
func set_mirrored(mirrored: bool) -> void:
	var wanted := -1.0 if mirrored else 1.0
	if is_equal_approx(wanted, _mirror):
		return
	_mirror = wanted
	if hand != null:
		hand.scale = Vector2(1.0, _mirror)
		hand.position.y = -hand.position.y


## Pulls the weapon in against the body (a dodge) or lets it back out.
func set_tucked(tucked: bool) -> void:
	_tucked = tucked


## The grip data the current weapon is anchored with. Never null once the node is ready.
func grip() -> WeaponGrip:
	return _grip


## Per-frame input hook called by the Player with the current aim and button states.
func handle_input(
	aim: Vector2,
	attack_held: bool,
	attack_pressed: bool,
	attack_released: bool,
	secondary_pressed: bool
) -> void:
	if weapon == null or player == null:
		return
	match weapon.style:
		WeaponBase.Style.RANGED_BOW:
			_handle_bow_input(aim, attack_held or attack_pressed, attack_released)
		_:
			if attack_held or attack_pressed:
				try_attack(aim)
	if secondary_pressed:
		use_skill(aim)


## Bow control model (docs §4.1, "attack is held-to-repeat"): let go and the shot leaves at
## whatever charge it had; keep holding and it leaves by itself the moment the draw tops out,
## then immediately starts the next one. `_pending_release` covers the frames where a shot is
## drawn but the previous one's interval has not run out — nothing re-draws until it flies.
func _handle_bow_input(aim: Vector2, attack_held: bool, attack_released: bool) -> void:
	if is_charging and (attack_released or not attack_held or is_fully_charged()):
		release_charge(aim)
	if attack_held and not is_charging and not _pending_release:
		begin_charge()


## Primary attack for non-charged styles. Returns true when an attack was performed.
func try_attack(aim: Vector2) -> bool:
	if weapon == null or player == null or not is_ready() or not player.can_act():
		return false
	if weapon.style == WeaponBase.Style.RANGED_BOW:
		begin_charge()
		return true
	_cooldown = attack_interval()
	match weapon.style:
		WeaponBase.Style.MELEE_ARC:
			_swing(aim)
		WeaponBase.Style.MELEE_THRUST:
			_thrust(aim)
		WeaponBase.Style.RANGED_WAND:
			_fire_wand(aim)
		WeaponBase.Style.THROWN:
			_throw(aim)
	return true


## Cancels the current combo, any charge and a cancellable recovery (used when the player
## dodges): a committed swing still lands, but its tail never traps the player.
func cancel() -> void:
	interrupt_charge()
	cancel_recovery()
	if hitbox != null:
		hitbox.deactivate()


## Softer than `cancel()`: drops the combo counter and any held charge but leaves an already
## active melee hitbox alive (used when the player is chipped mid-swing).
func interrupt_charge() -> void:
	combo_index = 0
	_combo_timer = 0.0
	is_charging = false
	charge_time = 0.0
	_pending_release = false
	if arm != null:
		arm.scale = Vector2.ONE


func begin_charge() -> void:
	if is_charging or player == null or not player.can_act():
		return
	is_charging = true
	charge_time = 0.0
	charge_changed.emit(0.0)


## Fires the charged shot (or a weak tap shot). Waits for the cooldown if it is still running.
func release_charge(aim: Vector2) -> void:
	if not is_charging:
		return
	is_charging = false
	if is_ready():
		_fire_bow(aim)
	else:
		_pending_release = true
		_pending_aim = aim


## Secondary attack: the weapon skill ActiveAbility, if any.
func use_skill(aim: Vector2) -> bool:
	if skill == null or player == null or not player.can_act():
		return false
	if not skill.try_activate(player, aim):
		return false
	cancel_recovery()
	skill_used.emit(skill)
	return true


# ---------------------------------------------------------------- melee


func _swing(aim: Vector2) -> void:
	var last_hit := is_combo_finisher()
	hitbox.damage_builder = _melee_damage.bind(2.0 if last_hit else 1.0)
	_begin_melee()
	_swing_dir = -_swing_dir
	_animate_swing(aim)
	attacked.emit(weapon.style, combo_index)
	_advance_combo(last_hit)


## Thrust combo: a run of quick pokes, then a lunging finisher that reaches further and throws
## the target twice as far. `combo_length` was dead data on the whole thrust family before this
## — dagger, stiletto, spear and glaive all declare one and all played as a flat repeated poke.
func _thrust(_aim: Vector2) -> void:
	var last_hit := is_combo_finisher()
	hitbox.damage_builder = _melee_damage.bind(2.0 if last_hit else 1.0)
	_begin_melee()
	_animate_thrust(THRUST_FINISHER_REACH if last_hit else 1.0)
	attacked.emit(weapon.style, combo_index)
	_advance_combo(last_hit)


## True when the attack about to land is the last beat of the weapon's combo.
func is_combo_finisher() -> bool:
	return combo_index >= maxi(1, weapon.combo_length) - 1


## Books the combo counter and the recovery after an attack landed. A finisher resets the
## combo and costs extra recovery; everything else queues the next beat.
func _advance_combo(last_hit: bool) -> void:
	if last_hit:
		combo_index = 0
		_combo_timer = 0.0
		_cooldown = attack_interval() * FINISHER_RECOVERY
	else:
		combo_index += 1
		_combo_timer = COMBO_RESET_TIME


## Opens the three-beat melee timeline. The hitbox is armed for the whole anticipation plus
## the sweep, so a point-blank enemy is hit on the first frame and the wind-back is free.
func _begin_melee() -> void:
	_attack_elapsed = 0.0
	_attack_impact_end = MELEE_ANTICIPATION + MELEE_ACTIVE_TIME
	hitbox.activate(_attack_impact_end)
	if hand != null:
		LightEmitter.attach(hand, &"swing")


func _melee_damage(target: Node2D, knockback_mult: float) -> DamageInfo:
	var dir := target.global_position - player.global_position
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT.rotated(global_rotation)
	return player.make_weapon_damage(
		target, weapon.base_damage, weapon.tags, dir, weapon.knockback * knockback_mult
	)


# ---------------------------------------------------------------- ranged


func _fire_bow(aim: Vector2) -> void:
	var fraction := charge_fraction()
	charge_time = 0.0
	arm.scale = Vector2.ONE
	_cooldown = attack_interval()
	var extra_pierce := 1 if fraction >= 0.999 else 0
	_spawn_projectiles(
		aim,
		bow_damage_multiplier(fraction),
		bow_speed_multiplier(fraction),
		extra_pierce,
		0.0,
		-1.0
	)
	_animate_recoil(4.0)
	attacked.emit(weapon.style, 0)
	charge_changed.emit(0.0)


func _fire_wand(aim: Vector2) -> void:
	_spawn_projectiles(aim, 1.0, 1.0, 0, WAND_HOMING, -1.0)
	_animate_recoil(2.0)
	attacked.emit(weapon.style, 0)


func _throw(aim: Vector2) -> void:
	var thrown := _spawn_projectiles(aim, 1.0, 1.0, 0, 0.0, THROWN_LIFETIME, THROWN_GRAVITY)
	for proj: Projectile in thrown:
		_spin(proj, proj.lifetime)
	_animate_swing(aim)
	attacked.emit(weapon.style, 0)


## Thrown weapons tumble instead of pointing along the shot (the arc itself is `arc_gravity`).
func _spin(proj: Projectile, duration: float) -> void:
	proj.rotate_to_direction = false
	var turns := TAU * THROWN_SPIN * duration
	var tween := proj.create_tween()
	tween.tween_property(proj, "rotation", proj.rotation + turns, duration)


## Spawns `projectile_count` projectiles in a fan. Returns them (already in the tree).
## `lifetime` is an upper bound: a shot never outlives the weapon's advertised `range_px`,
## which every weapon card prints and which used to buy the player nothing at all because
## ranged shots simply ran on the Projectile default of two seconds.
func _spawn_projectiles(
	aim: Vector2,
	damage_mult: float,
	speed_mult: float,
	extra_pierce: int,
	homing: float,
	lifetime: float,
	gravity: float = 0.0
) -> Array[Projectile]:
	var out: Array[Projectile] = []
	var parent := _projectile_parent()
	if parent == null:
		return out
	var stats := player.stats
	var count := maxi(1, int(stats.get_value(&"projectile_count")))
	var pierce := extra_pierce + maxi(0, int(stats.get_value(&"pierce")))
	var bounces := int(player.flags.get("projectile_bounces", 0))
	var size := maxf(0.25, stats.get_value(&"projectile_size"))
	var speed := (
		weapon.projectile_speed * speed_mult * maxf(0.2, stats.get_value(&"projectile_speed"))
	)
	var base_dir := aim.normalized() if aim.length_squared() > 0.001 else Vector2.RIGHT
	var target := nearest_enemy(global_position, ENEMY_SEARCH_RADIUS) if homing > 0.0 else null
	var base_damage := weapon.base_damage * damage_mult
	var life := _range_lifetime(speed, lifetime)
	for i in range(count):
		var offset := (float(i) - float(count - 1) * 0.5) * SPREAD_STEP
		var dir := base_dir.rotated(offset)
		var proj := _make_projectile()
		proj.pierce = pierce
		proj.bounces = bounces
		proj.homing_strength = homing
		proj.homing_target = target
		proj.arc_gravity = gravity
		proj.scale = Vector2.ONE * size
		proj.setup(
			player, Layers.Team.PLAYER, dir, _projectile_damage.bind(proj, base_damage), speed, life
		)
		parent.add_child(proj)
		proj.global_position = global_position + dir * 6.0
		proj.hitbox.hit_dealt.connect(_on_hit_dealt)
		projectile_fired.emit(proj)
		out.append(proj)
	return out


## Seconds a shot travelling at `speed` may live before it has covered the weapon's whole
## `range_px`. `cap` (a positive value) shortens it further; a lobbed shot hangs no longer
## than `THROWN_LIFETIME` however far the weapon claims to reach.
func _range_lifetime(speed: float, cap: float) -> float:
	var life := maxf(4.0, weapon.range_px) / maxf(20.0, speed)
	return minf(life, cap) if cap > 0.0 else life


func _projectile_damage(target: Node2D, proj: Projectile, base_damage: float) -> DamageInfo:
	var dir := (
		proj.direction if is_instance_valid(proj) else target.global_position - global_position
	)
	return player.make_weapon_damage(target, base_damage, weapon.tags, dir, weapon.knockback)


func _make_projectile() -> Projectile:
	if weapon.projectile_scene != null:
		var inst := weapon.projectile_scene.instantiate() as Projectile
		if inst != null:
			return inst
	var proj := Projectile.new()
	proj.sprite_texture = _projectile_texture()
	return proj


## The authored art this weapon's shot is drawn with.
##
## No accent modulate: the shot keeps the sheet's own colours, which is both what docs §10
## specifies for projectiles and what every enemy shot already does. It also removes an
## accent-on-floor colour pair that nothing guarded - the UI text/background and danger/floor
## pairs are asserted in `tests/unit/desktop/palette_contrast_test.gd`, this one never was, and
## on the `white` fixture the bolt resolved to a mid grey on a white floor.
func _projectile_texture() -> Texture2D:
	var art := ProjectileSprites.frame(_projectile_frame())
	# A sheet that will not load leaves the old flat bolt rather than an invisible shot.
	return art if art != null else _bolt_texture_shared()


## `ProjectileSprites` frame for this weapon: damage tag first, weapon style second.
func _projectile_frame() -> int:
	for tag: StringName in weapon.tags:
		if TAG_PROJECTILE_FRAME.has(tag):
			return int(TAG_PROJECTILE_FRAME[tag])
	var style := int(weapon.style)
	if style >= 0 and style < STYLE_PROJECTILE_FRAME.size():
		return STYLE_PROJECTILE_FRAME[style]
	return ProjectileSprites.BOLT


func _projectile_parent() -> Node:
	if is_instance_valid(projectile_parent):
		return projectile_parent
	if player != null and player.get_parent() != null:
		return player.get_parent()
	return get_tree().current_scene


## The pre-sheet fallback: a flat 6x3 white rectangle. Only reached when
## `assets/sprites/projectiles.png` cannot be loaded.
func _bolt_texture_shared() -> Texture2D:
	if _bolt_texture == null:
		var img := Image.create(6, 3, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_bolt_texture = ImageTexture.create_from_image(img)
	return _bolt_texture


## Nearest enemy to `origin` within `radius` (group "enemy", else an ENEMY_HURTBOX scan).
func nearest_enemy(origin: Vector2, radius: float) -> Node2D:
	var best: Node2D = null
	var best_d := radius * radius
	for node: Node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var n2 := node as Node2D
		if n2 == null or not is_instance_valid(n2):
			continue
		var d := n2.global_position.distance_squared_to(origin)
		if d < best_d:
			best_d = d
			best = n2
	if best != null:
		return best
	var space := get_world_2d().direct_space_state
	if space == null:
		return null
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, origin)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = Layers.ENEMY_HURTBOX
	for hit: Dictionary in space.intersect_shape(query, 16):
		var area := hit["collider"] as Area2D
		if area == null:
			continue
		var candidate: Node2D = area
		var hb := area as Hurtbox
		if hb != null and hb.entity != null:
			candidate = hb.entity
		var d := candidate.global_position.distance_squared_to(origin)
		if d < best_d:
			best_d = d
			best = candidate
	return best


# ---------------------------------------------------------------- hits & visuals


func _on_hit_dealt(target: Hurtbox, info: DamageInfo) -> void:
	if player == null:
		return
	var node: Node2D = target
	if target.entity != null:
		node = target.entity
	player.on_weapon_hit(node, info)


func _apply_weapon_visuals() -> void:
	var range_px := weapon.range_px
	match weapon.style:
		WeaponBase.Style.MELEE_THRUST:
			var rect := RectangleShape2D.new()
			rect.size = Vector2(range_px * 1.4, maxf(8.0, range_px * 0.6))
			_hitbox_shape.shape = rect
			_hitbox_shape.position = Vector2(range_px * 0.8, 0.0)
		_:
			var circle := CircleShape2D.new()
			circle.radius = maxf(6.0, range_px * 0.75)
			_hitbox_shape.shape = circle
			_hitbox_shape.position = Vector2(range_px * 0.55, 0.0)
	_grip = WeaponGrips.shared().for_weapon(weapon.id, int(weapon.style))
	arm.rotation = 0.0
	arm.position = Vector2.ZERO
	arm.scale = Vector2.ONE
	hand.position = _grip.hand_position(_mirror)
	hand.scale = Vector2(1.0, _mirror)
	hand.rotation = 0.0
	# The grip pixel of the cell sits on the hand's origin, and the weapon's own diagonal is
	# turned to point along +X (the aim). Both belong to the art, so both are data.
	sprite.position = Vector2.ZERO
	sprite.centered = true
	sprite.flip_h = false
	sprite.flip_v = false
	sprite.offset = _grip.sprite_offset(float(ATLAS_FRAME))
	sprite.rotation = _grip.rest_rotation()
	sprite.scale = Vector2.ONE * maxf(0.1, _grip.sprite_scale)
	sprite.texture = _weapon_texture()
	sprite.region_enabled = false
	if sprite.texture != null and sprite.texture.get_size().x > ATLAS_FRAME:
		sprite.region_enabled = true
		sprite.region_rect = Rect2(_atlas_index() * ATLAS_FRAME, 0, ATLAS_FRAME, ATLAS_FRAME)
	sprite.visible = weapon.id != &"fists"


func _weapon_texture() -> Texture2D:
	if weapon.icon != null:
		return weapon.icon
	if item != null and item.get("base") != null:
		var base := item.get("base") as ItemBase
		if base != null and base.icon != null:
			return base.icon
	if ResourceLoader.exists(WEAPON_ATLAS_PATH):
		return load(WEAPON_ATLAS_PATH) as Texture2D
	return null


## Atlas column: matched by the **longest** family word in the weapon id, else by style. Longest
## wins because the short words are prefixes of the long ones - scanning in key order handed
## `longsword` and `greatsword` the rusty sword's cell.
func _atlas_index() -> int:
	var id := String(weapon.id).to_lower()
	var best := -1
	var best_length := 0
	for key: StringName in ATLAS_INDEX.keys():
		var word := String(key)
		if word.length() > best_length and id.contains(word):
			best_length = word.length()
			best = int(ATLAS_INDEX[key])
	if best >= 0:
		return best
	match weapon.style:
		WeaponBase.Style.MELEE_THRUST:
			return int(ATLAS_INDEX[&"spear"])
		WeaponBase.Style.RANGED_BOW:
			return int(ATLAS_INDEX[&"shortbow"])
		WeaponBase.Style.RANGED_WAND:
			return int(ATLAS_INDEX[&"wand"])
		WeaponBase.Style.THROWN:
			return int(ATLAS_INDEX[&"knives"])
	return int(ATLAS_INDEX[&"sword"])


## Ends the running animation without moving the arm. It used to snap rotation and position
## back to zero first, which teleported the weapon across the body one frame before the new
## animation started from somewhere else again; every animation below now tweens out of
## wherever the arm actually is.
func _kill_swing_tween() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	arm.scale = Vector2.ONE


## Seconds the visible recovery lasts: whatever is left of the attack interval after the
## anticipation and the sweep, so the animation never lies about when the player is free.
func _recovery_time() -> float:
	return clampf(attack_interval() - _attack_impact_end, 0.1, 0.4)


## Snaps the arm back to rest when a recovery is cancelled.
func _return_arm_to_rest() -> void:
	if arm == null:
		return
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = create_tween().set_parallel(true)
	_swing_tween.tween_property(arm, "rotation", 0.0, 0.06).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(arm, "position", Vector2.ZERO, 0.06).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(arm, "scale", Vector2.ONE, 0.06).set_ease(Tween.EASE_OUT)


## Three beats: load past the swing arc (anticipation), sweep through it (impact), drift home
## (recovery). The hitbox lives across the first two, so the wind-back costs the player nothing.
## Three beats: wind back past the start of the arc, sweep through it, drift home. The
## wind-back is *tweened* now. It used to be assigned - `arm.rotation = -loaded` - which put the
## weapon on the far side of the character in a single frame, and at the moment of a turn that
## teleport is indistinguishable from the weapon being anchored on the wrong side, because it
## was: one frame of the sword standing behind the shoulder it had just left.
func _animate_swing(_aim: Vector2) -> void:
	_kill_swing_tween()
	var span := SWING_ARC * _swing_dir
	var loaded := -(span + ANTICIPATION_ANGLE * _swing_dir)
	_swing_tween = create_tween()
	_swing_tween.tween_property(arm, "rotation", loaded, MELEE_ANTICIPATION).set_ease(
		Tween.EASE_OUT
	)
	_swing_tween.parallel().tween_property(
		arm, "scale", Vector2.ONE * ANTICIPATION_SCALE, MELEE_ANTICIPATION
	)
	_swing_tween.tween_property(arm, "rotation", span, MELEE_ACTIVE_TIME).set_ease(Tween.EASE_OUT)
	_swing_tween.parallel().tween_property(arm, "scale", Vector2.ONE, MELEE_ACTIVE_TIME)
	_swing_tween.tween_property(arm, "rotation", 0.0, _recovery_time()).set_ease(Tween.EASE_IN_OUT)


func _animate_thrust(reach_mult: float = 1.0) -> void:
	_kill_swing_tween()
	var reach := weapon.range_px * 0.6 * reach_mult
	_swing_tween = create_tween()
	# A thrust is a straight push along the aim; any leftover swing angle is tweened out with it
	# rather than left tilting the weapon through the poke.
	_swing_tween.parallel().tween_property(arm, "rotation", 0.0, MELEE_ANTICIPATION)
	# Anticipation: a short pull back before the stab.
	_swing_tween.tween_property(arm, "position:x", -reach * 0.35, MELEE_ANTICIPATION).set_ease(
		Tween.EASE_OUT
	)
	_swing_tween.tween_property(arm, "position:x", reach, MELEE_ACTIVE_TIME * 0.6).set_ease(
		Tween.EASE_OUT
	)
	_swing_tween.tween_property(arm, "position:x", 0.0, _recovery_time()).set_ease(
		Tween.EASE_IN_OUT
	)


## A ranged weapon kicks back along the aim instead of swinging: the kick is short enough to
## read as recoil and never carries the weapon off the hand.
func _animate_recoil(amount: float) -> void:
	_kill_swing_tween()
	arm.rotation = 0.0
	arm.position.x = -amount
	_swing_tween = create_tween()
	_swing_tween.tween_property(arm, "position:x", 0.0, 0.12).set_ease(Tween.EASE_OUT)
