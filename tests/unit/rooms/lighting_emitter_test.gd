## Gameplay lights are data (`LightingProfile.emitters`): every kind a swing, a shot, a spell,
## an explosion or a fixture asks for is a row of the table, resolves its colour from the
## theme role on every fixture, rises and fades without a step, hands itself back to the pool,
## and is refused past the cap. The kinds the code asks for are pinned against the table by a
## source scan, so a new spell cannot ask for a light nobody tuned.
class_name LightingEmitterTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
## Files that attach or flash an emitter, and the kinds each asks for.
const ASKERS: Dictionary = {
	"res://src/combat/projectile.gd": ["shot", "enemy_shot"],
	"res://src/player/weapon_controller.gd": ["swing"],
	"res://src/rooms/chest.gd": ["chest"],
	"res://src/abilities/actives/fireball.gd": ["fire", "explosion"],
	"res://src/abilities/actives/frost_nova.gd": ["frost"],
	"res://src/abilities/actives/chain_lightning.gd": ["shock"],
	"res://src/abilities/actives/fork_bomb.gd": ["arcane"],
	"res://src/abilities/actives/stack_smash.gd": ["explosion"],
	"res://src/abilities/actives/warcry.gd": ["danger"],
	"res://src/abilities/actives/shadowstep.gd": ["arcane"],
	"res://src/abilities/actives/reboot.gd": ["heal"],
	"res://src/entities/enemies/attacks/aoe_burst.gd": ["enemy_burst"],
	"res://src/rooms/lighting/light_rig.gd": ["stairs", "altar", "shrine"],
}
## Least a one-shot bloom may take to leave (owner: an explosion is not a flash).
const EXPLOSION_MIN_FADE := 0.3
const FRAME := 1.0 / 60.0

var _floors: Array[FloorRoot] = []


func after_test() -> void:
	for root: FloorRoot in _floors:
		if is_instance_valid(root):
			root.clear_floor()
			root.free()
	_floors.clear()
	await get_tree().process_frame
	await get_tree().process_frame


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _floor(theme: String = "tokyo-night") -> FloorRoot:
	var root := FloorRoot.new()
	_floors.append(root)
	add_child(root)
	root.build_with_biome(
		RoomsTestFixtures.three_rooms(), Biome.load_by_id(&"crypt"), null, _palette(theme)
	)
	return root


## Every kind gameplay asks for is in the table, with a role the palette knows.
func test_every_kind_the_code_asks_for_is_tuned_in_the_table() -> void:
	var profile := LightingProfile.resolve()
	var kinds := profile.emitter_kinds()
	for path: String in ASKERS:
		var source := FileAccess.get_file_as_string(path)
		assert_str(source).override_failure_message("%s unreadable" % path).is_not_empty()
		for kind: String in ASKERS[path]:
			(
				assert_bool(source.contains('&"%s"' % kind))
				. override_failure_message("%s no longer asks for %s" % [path, kind])
				. is_true()
			)
			(
				assert_bool(kinds.has(StringName(kind)))
				. override_failure_message(
					"%s asks for %s, which the table does not tune" % [path, kind]
				)
				. is_true()
			)
	for kind: StringName in kinds:
		var spec := profile.emitter_spec(kind)
		assert_bool(ThemePalette.ROLES.has(String(spec["role"]))).is_true()
		assert_float(float(spec["energy"])).is_greater(0.0)
		assert_float(float(spec["radius"])).is_greater(0.0)
	assert_float(float(profile.emitter_spec(&"explosion")["fade"])).is_greater_equal(
		EXPLOSION_MIN_FADE
	)


## An emitter attached from data carries the row's energy, radius and role, and its colour is
## the theme's role colour on every fixture (fire turned toward the accent like a torch).
func test_emitters_attach_from_data_and_burn_in_the_theme_role_on_every_fixture() -> void:
	for theme: String in THEMES:
		var root := _floor(theme)
		var rig := LightRig.of(root)
		var light := DungeonLight.resolve()
		var pal := root.lit_palette()
		for kind: StringName in rig.profile.emitter_kinds():
			var spec := rig.profile.emitter_spec(kind)
			var host := Node2D.new()
			root.add_child(host)
			var e := LightEmitter.attach(host, kind)
			(
				assert_object(e)
				. override_failure_message("%s: no emitter for %s" % [theme, kind])
				. is_not_null()
			)
			assert_str(String(e.kind)).is_equal(String(kind))
			assert_str(String(e.role)).is_equal(String(spec["role"]))
			assert_float(e.base_energy).is_equal(float(spec["energy"]))
			assert_float(e.texture_scale).is_equal_approx(float(spec["radius"]), 0.001)
			var role: StringName = spec["role"]
			var want: Color = (
				light.torch_color(pal)
				if role == &"heat"
				else Music.mood_state().light_color(light.light_color(pal.get_color(role)))
			)
			(
				assert_bool(e.color.is_equal_approx(want))
				. override_failure_message(
					"%s: %s burns %s, want %s" % [theme, kind, e.color, want]
				)
				. is_true()
			)
			assert_bool(e.visible).is_true()
			assert_float(e.energy).is_greater(0.0)
			e.release()
			host.free()


## A one-shot rises for `ATTACK` seconds, then fades over its row's fade without a reversal
## and without a step, and is parked when it is out.
func test_a_flash_rises_then_fades_monotonically_and_parks_itself() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	var e := LightEmitter.flash(&"explosion", root.player_spawn_position())
	assert_object(e).is_not_null()
	assert_float(e.fade).is_greater_equal(EXPLOSION_MIN_FADE)
	var peak := 0.0
	var last := e.energy
	var rising := true
	var frames := 0
	while e.alive and frames < 600:
		e._process(FRAME)
		frames += 1
		if not e.alive:
			break
		var now := e.energy
		if rising and now < last:
			rising = false
			peak = last
		elif not rising:
			(
				assert_float(now)
				. override_failure_message("frame %d rose again" % frames)
				. is_less_equal(last)
			)
		assert_float(absf(now - last)).is_less(e.base_energy * 0.5)
		last = now
	assert_bool(e.alive).is_false()
	assert_float(peak).is_greater(e.base_energy * 0.9)
	assert_float(float(frames) * FRAME).is_greater_equal(EXPLOSION_MIN_FADE)
	assert_bool(rig.live_emitters().has(e)).is_false()
	# The next request reuses the parked node.
	var again := LightEmitter.flash(&"frost", Vector2.ZERO)
	assert_object(again).is_same(e)


## A host that hides or leaves the tree takes its light out; the node goes back to the pool.
func test_a_light_follows_its_host_and_goes_out_with_it() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	var host := Node2D.new()
	root.add_child(host)
	host.global_position = Vector2(100, 50)
	var e := LightEmitter.attach(host, &"fire")
	assert_object(e).is_not_null()
	host.global_position = Vector2(140, 60)
	e._process(FRAME)
	assert_vector(e.global_position).is_equal(Vector2(140, 60))
	assert_int(rig.live_emitters().size()).is_greater_equal(1)
	# A standing light lights the bodies in its pool with the same pool it puts on the floor,
	# one light on LIT_MASK; a passing one lights the ground only.
	assert_bool(e.lights_bodies()).is_true()
	assert_int(e.range_item_cull_mask).is_equal(LightRig.LIT_MASK)
	assert_int(e.get_child_count()).is_equal(0)
	var passing := LightEmitter.flash(&"explosion", Vector2.ZERO)
	assert_bool(passing.lights_bodies()).is_false()
	assert_int(passing.range_item_cull_mask).is_equal(LightRig.ENV_MASK)
	passing.release()
	host.visible = false
	e._process(FRAME)
	assert_bool(e.alive).is_false()
	host.visible = true
	var second := LightEmitter.attach(host, &"fire")
	assert_object(second).is_same(e)
	host.free()
	e._process(FRAME)
	assert_bool(e.alive).is_false()


## Past the cap a request is dropped, never queued; releasing one frees a slot.
func test_requests_past_the_cap_are_dropped() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	var live := rig.live_emitters().size()
	var made: Array[LightEmitter] = []
	for i in range(rig.profile.emitter_max - live):
		var e := LightEmitter.flash(&"shot", Vector2(i, 0))
		assert_object(e).is_not_null()
		made.append(e)
	assert_object(LightEmitter.flash(&"shot", Vector2.ZERO)).is_null()
	assert_int(rig.emitters.size()).is_equal(rig.profile.emitter_max)
	made[0].release()
	assert_object(LightEmitter.flash(&"shot", Vector2.ZERO)).is_same(made[0])


## A projectile carries the shot light of its team; a chest the loot glow until it opens.
func test_projectiles_and_chests_carry_their_lights() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	var builder := func(_target: Node2D) -> DamageInfo: return DamageInfo.new()
	var shot := Projectile.new()
	shot.setup(root, Layers.Team.PLAYER, Vector2.RIGHT, builder)
	root.add_child(shot)
	var enemy_shot := Projectile.new()
	enemy_shot.setup(root, Layers.Team.ENEMY, Vector2.RIGHT, builder)
	root.add_child(enemy_shot)
	var kinds: Array[StringName] = []
	for e: LightEmitter in rig.live_emitters():
		kinds.append(e.kind)
	assert_array(kinds).contains([&"shot", &"enemy_shot"])
	shot.queue_free()
	enemy_shot.queue_free()
	await get_tree().process_frame
	var chest := root.rooms[1].spawn_chest()
	await get_tree().process_frame
	var chest_lights := 0
	for e: LightEmitter in rig.live_emitters():
		if e.kind == &"chest" and e.host == chest:
			chest_lights += 1
	assert_int(chest_lights).is_equal(1)
	chest.mark_taken()
	chest_lights = 0
	for e: LightEmitter in rig.live_emitters():
		if e.kind == &"chest":
			chest_lights += 1
	assert_int(chest_lights).is_equal(0)


## A theme swap retints every emitter alight to the new theme's role colour.
func test_a_palette_change_retints_every_live_emitter() -> void:
	var root := _floor("tokyo-night")
	var rig := LightRig.of(root)
	var host := Node2D.new()
	root.add_child(host)
	var e := LightEmitter.attach(host, &"fire")
	var before := e.color
	EventBus.palette_changed.emit(_palette("white"))
	assert_bool(e.color.is_equal_approx(before)).is_false()
	assert_bool(e.color.is_equal_approx(rig.light_color_for(&"heat"))).is_true()
	assert_str(root.lit_palette().name).is_equal("white")
	host.free()
