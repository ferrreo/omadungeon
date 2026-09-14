## How a weapon sits on the character, driven by a **real controller**.
##
## The owner's report is "weapons sit on the characters weird especially when changing
## direction", and eight rounds of review missed it because a test that calls
## `weapon_controller.handle_input(Vector2.LEFT, ...)` proves nothing about what a player sees:
## it skips the stick, the device detection, the aim, the facing flip and the draw order. So
## every case here pushes a right stick (`InputEventJoypadMotion` on the aim axes), pulls a
## trigger (the attack axis) and presses A (`InputEventJoypadButton`), lets the live `Player`
## run its own physics, and then asks where the weapon's **grip pixel and tip pixel actually
## are in the world** - which is the thing the eye was complaining about.
class_name WeaponAnchorTest
extends GdUnitTestSuite

## Axes the right stick is bound to in project.godot (`aim_left/right/up/down`).
const AIM_X := JOY_AXIS_RIGHT_X
const AIM_Y := JOY_AXIS_RIGHT_Y
## The attack action's gamepad binding is the right trigger.
const ATTACK_AXIS := JOY_AXIS_TRIGGER_RIGHT
## The dodge action's gamepad binding.
const DODGE_BUTTON := JOY_BUTTON_A
## Tip pixel of the spear cell, which is the far end of the weapon's own axis.
const SPEAR_TIP := Vector2(14.0, 2.0)
## Eight stick directions, the four diagonals included: a quadrant-based anchor looks fine on
## the axes and falls apart between them.
const DIRECTIONS: Array[Vector2] = [
	Vector2(1, 0),
	Vector2(1, 1),
	Vector2(0, 1),
	Vector2(-1, 1),
	Vector2(-1, 0),
	Vector2(-1, -1),
	Vector2(0, -1),
	Vector2(1, -1),
]

var _player: Player


func before_test() -> void:
	HitStop.set_enabled(get_tree(), false)
	_player = auto_free(PlayerTestHelpers.make_player())
	add_child(_player)
	_player.apply_class(PlayerTestHelpers.load_class("fighter"))
	_player.global_position = Vector2.ZERO
	await get_tree().physics_frame


func after_test() -> void:
	_axis(AIM_X, 0.0)
	_axis(AIM_Y, 0.0)
	_axis(ATTACK_AXIS, 0.0)
	_button(DODGE_BUTTON, false)
	await _settle()
	HitStop.set_enabled(get_tree(), true)


# ---------------------------------------------------------------- device driving


func _axis(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func _button(button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _settle() -> void:
	Input.flush_buffered_events()
	await get_tree().physics_frame
	await get_tree().physics_frame


## Pushes the right stick to `dir` and lets the player react to it.
func _aim_stick(dir: Vector2) -> void:
	var d := dir.normalized()
	_axis(AIM_X, d.x)
	_axis(AIM_Y, d.y)
	await _settle()


func _equip(item_id: String) -> WeaponBase:
	var weapon := load("res://data/items/%s.tres" % item_id) as WeaponBase
	_player.weapon_controller.set_weapon(weapon)
	return weapon


# ---------------------------------------------------------------- geometry


func _wc() -> WeaponController:
	return _player.weapon_controller


## World position of one pixel of the weapon's atlas cell. The sprite is anchored at its grip,
## so a texture pixel `p` sits at `p - grip` in the sprite's own space.
func _texture_point(pixel: Vector2) -> Vector2:
	var g := _wc().grip()
	return _wc().sprite.global_transform * (pixel - g.grip)


## Where the hand is: the grip pixel, in the world.
func _grip_point() -> Vector2:
	return _wc().sprite.global_position


## Distance from the shoulder (the weapon pivot, which sits at chest height) to the grip. This
## is the number that says "the weapon is in the hand" rather than floating half a cell away.
func _grip_reach() -> float:
	return _grip_point().distance_to(_player.weapon_pivot.global_position)


## Largest `_grip_reach()` the current weapon's grip data allows, plus a pixel of slack.
func _reach_limit() -> float:
	var g := _wc().grip()
	return Vector2(g.reach, absf(g.lateral)).length() + 1.0


# ---------------------------------------------------------------- cases


func test_stick_turns_the_weapon_with_the_character() -> void:
	_equip("spear")
	for dir in DIRECTIONS:
		await _aim_stick(dir)
		var aim := dir.normalized()
		var from_hand := _texture_point(SPEAR_TIP) - _grip_point()
		(
			assert_float(absf(from_hand.angle_to(aim)))
			. override_failure_message(
				(
					"aiming %s the spear points %.0f deg away from the aim"
					% [aim, rad_to_deg(from_hand.angle_to(aim))]
				)
			)
			. is_less(deg_to_rad(12.0))
		)


func test_grip_stays_in_the_hand_in_every_facing() -> void:
	_equip("spear")
	var limit := _reach_limit()
	for dir in DIRECTIONS:
		await _aim_stick(dir)
		(
			assert_float(_grip_reach())
			. override_failure_message(
				"aiming %s the grip is %.1f px from the shoulder" % [dir, _grip_reach()]
			)
			. is_less(limit)
		)
		# And still on the character, not half a cell off the side of them.
		var from_body := _grip_point().distance_to(_player.global_position)
		(
			assert_float(from_body)
			. override_failure_message(
				"aiming %s the grip is %.1f px off the body" % [dir, from_body]
			)
			. is_less(12.0)
		)


func test_body_and_weapon_never_disagree_about_the_facing() -> void:
	_equip("rusty_sword")
	for dir in DIRECTIONS:
		await _aim_stick(dir)
		assert_bool(_player.sprite.flip_h).is_equal(_player.carry.flipped)
		var mirrored := _wc().hand.scale.y < 0.0
		(
			assert_bool(mirrored)
			. override_failure_message(
				(
					"aiming %s the body flip is %s but the weapon mirror is %s"
					% [dir, _player.carry.flipped, mirrored]
				)
			)
			. is_equal(_player.carry.flipped)
		)


## Turning around must *mirror* the weapon, not carry it through 180 degrees: the blade's own
## top edge stays upscreen aiming left exactly as it does aiming right. Checked on a point four
## pixels off the weapon's axis on the icon's upper side.
func test_turning_around_mirrors_the_blade_instead_of_inverting_it() -> void:
	_equip("rusty_sword")
	var g := _wc().grip()
	var up_side := g.grip + Vector2(4.0, 0.0).rotated(deg_to_rad(g.axis_degrees) - PI * 0.5)
	await _aim_stick(Vector2.RIGHT)
	var right_side := _texture_point(up_side) - _grip_point()
	await _aim_stick(Vector2.LEFT)
	var left_side := _texture_point(up_side) - _grip_point()
	(
		assert_float(right_side.y)
		. override_failure_message(
			"aiming right, the blade's top edge points down (%s)" % right_side
		)
		. is_less(0.0)
	)
	(
		assert_float(left_side.y)
		. override_failure_message("aiming left, the blade is upside down (%s)" % left_side)
		. is_less(0.0)
	)


## The strobe: a stick held near the vertical crosses x = 0 constantly, and every crossing used
## to flip the character and the weapon to the other side of the body.
func test_a_stick_hovering_on_the_vertical_does_not_strobe_the_facing() -> void:
	_equip("rusty_sword")
	await _aim_stick(Vector2.RIGHT)
	assert_bool(_player.carry.flipped).is_false()
	var wobbles: Array[float] = [0.05, -0.05, 0.08, -0.08, 0.02]
	for wobble in wobbles:
		await _aim_stick(Vector2(wobble, -1.0))
		(
			assert_bool(_player.carry.flipped)
			. override_failure_message(
				"a stick %.2f off the vertical turned the character around" % wobble
			)
			. is_false()
		)


func test_aiming_upscreen_puts_the_weapon_behind_the_body() -> void:
	_equip("rusty_sword")
	await _aim_stick(Vector2.DOWN)
	assert_bool(_player.weapon_pivot.show_behind_parent).is_false()
	assert_bool(_player.carry.behind).is_false()
	await _aim_stick(Vector2.UP)
	(
		assert_bool(_player.weapon_pivot.show_behind_parent)
		. override_failure_message("aiming up, the weapon still draws over the character's head")
		. is_true()
	)
	await _aim_stick(Vector2.DOWN)
	assert_bool(_player.weapon_pivot.show_behind_parent).is_false()


## The moment the report is about: the frames around a turn. The trigger is held down through a
## full swing while the stick is swung from right to left, and the grip may never leave the
## hand on any frame - which is what the old code did, teleporting the arm to its wind-back
## pose in a single frame.
func test_the_grip_never_leaves_the_hand_through_a_swing_and_a_turn() -> void:
	_equip("rusty_sword")
	var limit := _reach_limit()
	_axis(ATTACK_AXIS, 1.0)
	var worst := 0.0
	for step in range(24):
		var angle := deg_to_rad(float(step) * 15.0)
		_axis(AIM_X, cos(angle))
		_axis(AIM_Y, sin(angle))
		Input.flush_buffered_events()
		await get_tree().physics_frame
		worst = maxf(worst, _grip_reach())
	_axis(ATTACK_AXIS, 0.0)
	(
		assert_float(worst)
		. override_failure_message(
			"mid-swing the grip reached %.1f px from the shoulder (limit %.1f)" % [worst, limit]
		)
		. is_less(limit)
	)


func test_dodging_tucks_the_weapon_against_the_body() -> void:
	_equip("spear")
	await _aim_stick(Vector2.RIGHT)
	var carried := _wc().hand.position.x
	_button(DODGE_BUTTON, true)
	await _settle()
	_button(DODGE_BUTTON, false)
	await _settle()
	assert_int(_player.state).is_not_equal(Player.State.NORMAL)
	(
		assert_float(_wc().hand.position.x)
		. override_failure_message(
			"the weapon stayed out at %.1f px through the dodge" % _wc().hand.position.x
		)
		. is_less(carried)
	)


# ---------------------------------------------------------------- grip table


func test_the_grip_table_matches_the_longest_family_word() -> void:
	var table := WeaponGrips.shared()
	assert_str(String(table.for_weapon(&"rusty_sword", 0).family)).is_equal("sword")
	assert_str(String(table.for_weapon(&"longsword", 0).family)).is_equal("longsword")
	assert_str(String(table.for_weapon(&"greatsword", 0).family)).is_equal("greatsword")
	assert_str(String(table.for_weapon(&"shortbow", 2).family)).is_equal("shortbow")
	assert_str(String(table.for_weapon(&"crossbow", 2).family)).is_equal("crossbow")


func test_an_unknown_weapon_falls_back_to_its_style_family() -> void:
	var table := WeaponGrips.shared()
	(
		assert_str(String(table.for_weapon(&"mystery_pike", WeaponBase.Style.MELEE_THRUST).family))
		. is_equal("spear")
	)
	(
		assert_str(String(table.for_weapon(&"mystery_rod", WeaponBase.Style.RANGED_WAND).family))
		. is_equal("wand")
	)


## Every shipped weapon base has to resolve to a grip whose hand is actually on the body, or a
## new base silently goes back to being pinned by the middle of its icon.
func test_every_shipped_weapon_base_resolves_to_a_sane_grip() -> void:
	var table := WeaponGrips.shared()
	var registry := load("res://data/items/registry.tres") as ItemRegistry
	var checked := 0
	for base: ItemBase in registry.bases:
		var weapon := base as WeaponBase
		if weapon == null:
			continue
		checked += 1
		var g := table.for_weapon(weapon.id, int(weapon.style))
		assert_object(g).override_failure_message("%s has no grip" % weapon.id).is_not_null()
		assert_float(g.grip.x).is_between(0.0, 16.0)
		assert_float(g.grip.y).is_between(0.0, 16.0)
		(
			assert_float(g.reach)
			. override_failure_message(
				"%s is held %.1f px away from the body" % [weapon.id, g.reach]
			)
			. is_between(1.0, 10.0)
		)
	assert_int(checked).is_greater(5)


## Weapons that carry no icon of their own fall back to the shared atlas, and that fallback used
## to scan the family words in declaration order: `longsword` contains `sword`, so it drew the
## rusty sword's cell.
func test_a_longsword_without_an_icon_draws_the_longsword_cell() -> void:
	var weapon := WeaponBase.new()
	weapon.id = &"longsword"
	weapon.style = WeaponBase.Style.MELEE_ARC
	_player.weapon_controller.set_weapon(weapon)
	await get_tree().physics_frame
	assert_bool(_wc().sprite.region_enabled).is_true()
	(
		assert_float(_wc().sprite.region_rect.position.x)
		. override_failure_message(
			(
				"a longsword with no icon drew atlas cell %d"
				% int(_wc().sprite.region_rect.position.x / WeaponController.ATLAS_FRAME)
			)
		)
		. is_equal_approx(float(WeaponController.ATLAS_FRAME), 0.01)
	)
