## Screenshot gallery: instantiates every UI screen with fake data, captures each to
## tests/out/ui_<screen>.png and quits. Run with tools/ui-gallery.sh.
## Args: --screenshot-dir <abs dir>, --only <screen>, --hold (do not quit).
##
## Screens whose name ends in `_glyphs` are captured with `colorblind_glyphs` forced on, and
## `accessibility` renders `AccessibilityBoard`, which is the picture
## `tools/colourblind_check.py` samples. The setting is always put back afterwards, so the
## order of SCREENS never changes what a later capture looks like.
class_name UiGallery
extends Control

const SCREENS: PackedStringArray = [
	"title",
	"class_select",
	"hud",
	"chest_item",
	"chest_stat",
	"chest_ability",
	"chest_replace",
	"chest_replace_item",
	"chest_four",
	"chest_shop",
	"hud_tag",
	"hud_tooltip",
	"loadout",
	"pause_build",
	"pause_controls",
	"pause_settings",
	"settings",
	"settings_bindings",
	"settings_capture",
	"settings_advanced",
	"run_summary",
	"run_summary_full",
	"run_death",
	"credits",
	"stats",
	"accessibility",
	"enemy_bars",
	"hud_glyphs",
	"chest_item_glyphs",
	"pause_build_glyphs",
	# Last on purpose: these pin the active device to the gamepad, and the flag lives on the
	# SceneTree for the rest of the process.
	"pause_controls_pad",
	"settings_bindings_pad",
	"pause_settings_pad",
	"settings_capture_pad",
	"settings_audio_pad",
	"chest_item_pad",
	"chest_item_start",
]

## Screens captured with the colour-blind glyph setting forced on.
const GLYPH_SUFFIX := "_glyphs"
## Screens captured with the gamepad as the active device.
const PAD_SUFFIX := "_pad"
## Extra pixels the Audio capture scrolls past the focused row, so the row it is photographing
## is not flush against the bottom of the list. One row plus the gap.
const AUDIO_SCROLL_NUDGE := 24
## Which offer the item trade screen opens on: the ring, because a ring is the one family with
## two slots and therefore the only offer that asks the player *which* piece goes.
const RING_OFFER_INDEX := 2
## Screens that render `ChestUi`. Listed rather than matched inline because the match arm was
## already at the line limit before the item trade got a capture of its own.
const CHEST_SCREENS: PackedStringArray = [
	"chest_item",
	"chest_stat",
	"chest_ability",
	"chest_replace",
	"chest_replace_item",
	"chest_four",
	"chest_shop",
	"chest_item_pad",
	"chest_item_start",
]
const ENEMY_REGISTRY := "res://data/enemies/registry.tres"
## The `enemy_bars` rank: [enemy id, health left, show the notice tell].
const BAR_BOARD: Array[Array] = [
	["honker", 1.0, false],
	["juggler", 0.65, false],
	["vim_zealot", 0.2, false],
	["dotfile_golem", 0.8, false],
	["config_gremlin", 1.0, true],
]
## How long the notice tell is held for the capture (see `_enemy_board`).
const BAR_BOARD_MARK_SECONDS := 6.0
## Gap (px) between two enemies on that rank. Wider than `AwarenessProfile.ally_wake_radius`
## on purpose: at 72 px the one enemy that is meant to be noticing the player passed the word
## down the whole rank and the capture showed a chain of tells instead of one.
const BAR_BOARD_SPACING := 88.0
## Gallery screen -> pause tab, by name: the tab order is not the screen order.
const PAUSE_TABS: Dictionary = {
	"pause_build": PauseMenu.Tab.BUILD,
	"pause_controls": PauseMenu.Tab.CONTROLS,
	"pause_controls_pad": PauseMenu.Tab.CONTROLS,
	"pause_settings": PauseMenu.Tab.SETTINGS,
	"pause_settings_pad": PauseMenu.Tab.SETTINGS,
}

var _out_dir: String = "tests/out"
var _current: Node
var _player: UiFakes.FakePlayer


func _ready() -> void:
	UiTheme.apply(self)
	_out_dir = str(GameState.cli_args.get("screenshot-dir", "tests/out"))
	_player = UiFakes.make_player()
	add_child(_player)
	_run()


func _run() -> void:
	var only := str(GameState.cli_args.get("only", ""))
	var failures := 0
	for screen: String in SCREENS:
		if not only.is_empty() and screen != only:
			continue
		var glyphs := screen.ends_with(GLYPH_SUFFIX) or screen == "accessibility"
		var saved: Variant = GameState.settings.get("colorblind_glyphs", false)
		GameState.settings["colorblind_glyphs"] = glyphs
		EventBus.settings_changed.emit("colorblind_glyphs")
		await _show(screen.trim_suffix(GLYPH_SUFFIX) if glyphs else screen)
		var overflow := panel_overflow()
		if not overflow.is_empty():
			print("UI gallery: FAIL %s: %s" % [screen, overflow])
			failures += 1
		var err := await _capture("ui_%s" % screen)
		if err != OK:
			failures += 1
		GameState.settings["colorblind_glyphs"] = saved
		EventBus.settings_changed.emit("colorblind_glyphs")
		if not bool(GameState.cli_args.get("hold", false)):
			_teardown()
	if bool(GameState.cli_args.get("hold", false)):
		return
	print("UI gallery: done, %d failures" % failures)
	# Through the quit watchdog: Godot 4.7.1's Wayland teardown hangs about one exit in twenty
	# under load (see `QuitGuard`), and a gallery whose pictures all landed must not read as a
	# timeout. `tools/ui-gallery.sh` accepts the watchdog's 143 when every PNG is fresh.
	QuitGuard.request(get_tree(), 0 if failures == 0 else 1)


## The one thing a screenshot harness cannot check for itself: whether what it photographed is
## on screen at all. `ui-gallery.sh` proves a PNG landed, non-empty and newer than the run; it
## cannot see a dialog whose panel has grown out through the top and bottom of the frame, which
## is how a clipped VICTORY heading and an unreachable REUSE SEED button shipped. Returns the
## complaint, or "" when the screen is inside the frame or has no fixed panel to measure (the
## HUD and the title screen lay themselves out against the edges directly).
func panel_overflow() -> String:
	if _current == null:
		return ""
	var panel := _current.get_node_or_null("Panel") as Control
	if panel == null:
		return ""
	var frame := get_viewport_rect()
	var rect := panel.get_global_rect()
	if frame.grow(0.5).encloses(rect):
		return ""
	return "panel %s is outside the %s frame" % [rect, frame.size]


func _teardown() -> void:
	get_tree().paused = false
	if _current != null:
		var doomed := _current
		if doomed.get_parent() is CanvasLayer:
			doomed = doomed.get_parent()
		doomed.queue_free()
		_current = null
	for child in get_children():
		if child != _player:
			child.queue_free()


func _instantiate(path: String, overlay: bool = false) -> Node:
	var node := (load(path) as PackedScene).instantiate()
	if overlay:
		var layer := CanvasLayer.new()
		layer.layer = 20
		add_child(layer)
		layer.add_child(node)
	else:
		add_child(node)
	return node


func _backdrop() -> void:
	var backdrop := ScrollingBackdrop.new()
	add_child(backdrop)


func _hud() -> Hud:
	var hud := _instantiate("res://src/ui/hud.tscn") as Hud
	hud.bind(_player)
	hud.set_floor(2, "Crypt")
	hud.set_seed(20240911)
	hud.set_minimap(UiFakes.minimap_rooms(), UiFakes.minimap_edges())
	hud.show_prompt("Open chest", true)
	_player.status.add(StatusEffect.Kind.BURN)
	_player.status.add(StatusEffect.Kind.FROST, 2)
	_player.status.add(StatusEffect.Kind.POISON, 3, 0.35)
	_player.status.add(StatusEffect.Kind.STUN)
	hud.status_row().bind(_player)
	# Both banner lanes at once: a gameplay message on the one that matters and the radio on
	# its own, which is the whole point of splitting them.
	hud.toast("Room cleared", 4.0)
	hud.toast_widget().push_track("Now playing: No Title Bar - Obstinatus", 8.0)
	EventBus.damage_number.emit(Vector2(300, 140), 24.0, true, UiTheme.color(&"loot"))
	EventBus.damage_number.emit(Vector2(260, 160), 9.0, false, UiTheme.color(&"text_bright"))
	return hud


## A rank of real enemies wearing the states the player reads them by: untouched (no bar at
## all), hurt, nearly dead, an elite that wears its bar from the start, and one on the frame
## it notices you. Every one of them is a live `EnemyBase` damaged through the real hurtbox,
## so what the capture shows is what a fight shows.
func _enemy_board() -> Node2D:
	var board := Node2D.new()
	board.name = "EnemyBoard"
	add_child(board)
	var registry := load(ENEMY_REGISTRY) as EnemyRegistry
	if registry == null:
		return board
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260912
	var y := 150.0
	var x := 90.0
	for spec: Array in BAR_BOARD:
		var def := registry.find(StringName(spec[0]))
		if def == null:
			continue
		var enemy := EnemySpawner.instantiate(def, 0, Vector2(x, y), rng)
		board.add_child(enemy)
		enemy.global_position = Vector2(x, y)
		x += BAR_BOARD_SPACING
		await get_tree().physics_frame
		var fraction := float(spec[1])
		if fraction < 1.0:
			var tags: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
			var amount := enemy.health.max_hp * (1.0 - fraction)
			enemy.hurtbox.receive(DamageInfo.create(amount, tags, null, Layers.Team.PLAYER))
		if bool(spec[2]):
			enemy.alert()
			# Held far longer than the tell really lasts. The gallery renders through llvmpipe
			# and spends most of a second between the board being built and the frame being
			# written, so a 0.7 s tell is always over by then; `awareness_test.gd` is where the
			# real duration is pinned.
			enemy.alert_mark.show_for(BAR_BOARD_MARK_SECONDS)
	return board


func _show(screen: String) -> void:
	match screen:
		"title":
			_current = _instantiate("res://src/ui/title.tscn")
		"class_select":
			var select := _instantiate("res://src/ui/class_select.tscn") as ClassSelect
			select.locked_ids = [&"oligarch"]
			select.select(1)
			_current = select
		"hud":
			_backdrop()
			_current = _hud()
		"hud_tag", "hud_tooltip":
			# A ground drop the player is near: the name tag above it, or the compare card
			# above the interact prompt while the player stands on it.
			_backdrop()
			var hud := _hud()
			var drop := Node2D.new()
			drop.name = "FakeDrop"
			drop.position = Vector2(300, 150)
			add_child(drop)
			var level := ItemTooltip.Level.NEAR if screen == "hud_tag" else ItemTooltip.Level.CLOSE
			await get_tree().process_frame
			hud.item_tooltip().set_band(hud.tooltip_band().x, hud.tooltip_band().y)
			hud.item_tooltip().show_item(
				drop,
				UiFakes.make_offers(ChestUi.Kind.ITEM)[0],
				level,
				UiFakes.worn_gear(_player),
				_player.stats
			)
			_current = hud
		var chest_screen when CHEST_SCREENS.has(chest_screen):
			_backdrop()
			_hud()
			var chest := _instantiate("res://src/ui/chest_ui.tscn", true) as ChestUi
			var kind := ChestUi.Kind.ITEM
			if chest_screen == "chest_stat":
				kind = ChestUi.Kind.STAT
			elif chest_screen == "chest_ability" or chest_screen == "chest_replace":
				kind = ChestUi.Kind.ABILITY
			var fake_offers := UiFakes.make_offers(kind)
			var fake_context := UiFakes.chest_context(_player)
			if chest_screen == "chest_shop":
				fake_context = UiFakes.shop_context(_player)
			if chest_screen == "chest_four":
				fake_offers.append(UiFakes.make_offers(ChestUi.Kind.STAT)[0])
				fake_context["extra_option"] = true
			if chest_screen == "chest_replace_item":
				# A ring offered to a player already wearing two, so this screen shows the
				# case with a choice in it - the pager, and the ring the player would give up
				# on the left. With one ring worn the board simply filled the free slot.
				var two_rings := UiFakes.make_player_two_rings()
				add_child(two_rings)
				fake_context = UiFakes.chest_context(two_rings)
			chest.show_offers(kind, fake_offers, fake_context)
			# The swap view is one activate away: the offer the selection is on displaces
			# something, so confirming it opens the trade rather than taking it.
			if chest_screen == "chest_replace_item":
				chest.select(RING_OFFER_INDEX)
			if chest_screen == "chest_replace" or chest_screen == "chest_replace_item":
				chest.activate()
			if chest_screen == "chest_item_pad":
				# The same board as `chest_item`, on a pad: the prompt line draws the pad's
				# buttons, where it used to type their names ("A pick   B skip").
				InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
				EventBus.input_device_changed.emit(int(InputGlyphs.Device.GAMEPAD))
			if chest_screen == "chest_item_start":
				# Start pressed on an open board. The pause menu refuses to stack over one, so
				# the board answers for it on the hint line rather than leaving the press
				# silent; the capture is of that answer.
				InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
				EventBus.input_device_changed.emit(int(InputGlyphs.Device.GAMEPAD))
				# After the board has laid itself out: Start on a board a player is looking at,
				# not on one that has not been drawn yet.
				await get_tree().process_frame
				chest.answer_pause()
			_current = chest
		"pause_build", "pause_controls", "pause_settings":
			_current = _pause_screen(screen)
		"loadout":
			# The build screen as Tab opens it over the run: the same page the pause menu
			# embeds, with its own frame, footer and the seed tucked into the corner.
			_backdrop()
			_hud()
			var build := _instantiate("res://src/ui/loadout_screen.tscn", true) as LoadoutScreen
			build.bind(_player)
			build.set_context(Hud.floor_text(2, "Crypt"), 20240911)
			build.open()
			_current = build
		"pause_controls_pad":
			# The Controls page is the only place the game teaches its buttons, and it reads
			# completely differently on a pad - which is where it was unreadable: Move as four
			# identical discs, Start and Back as two unlabelled pills of the same shape.
			InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
			EventBus.input_device_changed.emit(int(InputGlyphs.Device.GAMEPAD))
			_current = _pause_screen(screen)
		"pause_settings_pad":
			# The Settings page as a controller meets it, on the panel the pause menu embeds -
			# 96 px narrower than the standalone page, and where the Keyboard column's notice
			# used to run off both ends. `secondary` is the row with the longest label, so this
			# is the widest that line ever gets.
			InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
			EventBus.input_device_changed.emit(int(InputGlyphs.Device.GAMEPAD))
			var paused := _pause_screen(screen)
			await get_tree().process_frame
			(paused.settings_panel()._rebind_buttons[&"secondary"] as Button).grab_focus()
			_current = paused
		"settings":
			_backdrop()
			_current = _instantiate("res://src/ui/settings_panel.tscn")
		"settings_advanced":
			# The seed's new home, scrolled into view the way a curious player reaches it.
			_backdrop()
			var advanced := _instantiate("res://src/ui/settings_panel.tscn") as SettingsPanel
			await get_tree().process_frame
			advanced.get_seed_field().grab_focus()
			await get_tree().process_frame
			# All the way down, so the capture shows the help line under the field too.
			(advanced.get_node("%Scroll") as ScrollContainer).scroll_vertical = 1 << 16
			_current = advanced
		"settings_capture", "settings_capture_pad":
			# A rebind capture open on the Interact row, on each device: the prompt has to name
			# the way out with the button the player is holding, and it is the longest line
			# the settings hint ever wraps.
			if screen.ends_with(PAD_SUFFIX):
				InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
				EventBus.input_device_changed.emit(int(InputGlyphs.Device.GAMEPAD))
			_backdrop()
			var capture := _instantiate("res://src/ui/settings_panel.tscn") as SettingsPanel
			await get_tree().process_frame
			var column: Dictionary = (
				capture._pad_buttons if screen.ends_with(PAD_SUFFIX) else capture._rebind_buttons
			)
			var row := column[&"interact"] as Button
			row.grab_focus()
			row.pressed.emit()
			_current = capture
		"settings_audio_pad":
			# The Audio rows as a controller meets them, sitting on the Music slider. Three
			# near-identical rows in a column, and a focused one used to be indistinguishable
			# from the two beside it: `HSlider` has no `focus` stylebox at all, and the theme
			# handed its one focus-sensitive stylebox (`grabber_area_highlight`) the very same
			# object as the idle one. This is the picture that answers "which slider am I on",
			# and it is captured on a light fixture as well as a dark one because a brighter
			# cue is a darker cue on a light theme.
			InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
			EventBus.input_device_changed.emit(int(InputGlyphs.Device.GAMEPAD))
			_backdrop()
			var audio := _instantiate("res://src/ui/settings_panel.tscn") as SettingsPanel
			await get_tree().process_frame
			(audio._controls["music_volume"] as HSlider).grab_focus()
			await get_tree().process_frame
			# `reveal` brings the focused row to the bottom edge, which is the right thing for a
			# player walking down the list and the wrong thing for a photograph of one row: the
			# slab's lower border lands on the section rule. Nudged down a line so the three
			# volume rows are all in frame and the focused one is between the other two.
			(audio.get_node("%Scroll") as ScrollContainer).scroll_vertical += AUDIO_SCROLL_NUDGE
			_current = audio
		"settings_bindings", "settings_bindings_pad":
			# Focus a rebind row so `follow_focus` scrolls the Input section into view: the
			# two-column binding grid is the part of the panel worth a screenshot. On a pad the
			# Keyboard column is drawn inert and the hint line says why - a keyboard is the only
			# device that can fill it in - so the two captures are two different pages.
			if screen.ends_with(PAD_SUFFIX):
				InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
				EventBus.input_device_changed.emit(int(InputGlyphs.Device.GAMEPAD))
			_backdrop()
			var settings := _instantiate("res://src/ui/settings_panel.tscn") as SettingsPanel
			await get_tree().process_frame
			(settings._rebind_buttons[&"attack"] as Button).grab_focus()
			_current = settings
		"run_summary", "run_summary_full", "run_death":
			var summary := _instantiate("res://src/ui/run_summary.tscn") as RunSummary
			if screen == "run_summary_full":
				summary.show_summary(UiFakes.summary_data_full())
			else:
				summary.show_summary(UiFakes.summary_data(screen == "run_summary"))
			_current = summary
		"credits":
			_current = _instantiate("res://src/ui/credits.tscn")
		"stats":
			var stats := _instantiate("res://src/ui/stats_screen.tscn") as StatsScreen
			stats.show_stats(UiFakes.profile_stats())
			_current = stats
		"accessibility":
			var board := AccessibilityBoard.new()
			add_child(board)
			_current = board
		"enemy_bars":
			_backdrop()
			_current = await _enemy_board()
	for _i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout


func _capture(name: String) -> int:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir.path_join("%s.png" % name)
	var err := image.save_png(path)
	print("UI gallery: %s (%s)" % [path, error_string(err)])
	return err


## The pause menu open on the tab `screen` names, over the HUD and backdrop.
func _pause_screen(screen: String) -> PauseMenu:
	_backdrop()
	_hud()
	var pause := _instantiate("res://src/ui/pause_menu.tscn", true) as PauseMenu
	pause.bind(_player)
	pause.open()
	pause.set_tab(PAUSE_TABS.get(screen, PauseMenu.Tab.BUILD))
	return pause
