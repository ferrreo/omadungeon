## The live retint is the flagship feature and its confirmation was a queue entry: the world
## changed colour while the banner still read "FLOOR 1 - CRYPT", three to five seconds behind,
## or dropped entirely at the MAX_QUEUED cap.
class_name ToastPriorityTest
extends GdUnitTestSuite

const FIXTURE := "res://tests/fixtures/omarchy/gruvbox/state/current/theme/colors.toml"


func _toast(listen: bool = true) -> Toast:
	var node: Toast = auto_free(Toast.new())
	node.listen_to_bus = listen
	node.size = Vector2(200, 16)
	add_child(node)
	return node


func _palette() -> ThemePalette:
	return ThemePalette.from_colors_toml(ColorsToml.load_file(FIXTURE), "Gruvbox Test")


func after_test() -> void:
	UiTheme.rebuild(Desktop.palette)


func test_a_theme_change_interrupts_the_banner_that_is_up() -> void:
	var toast := _toast()
	toast.push("Floor 1 - Crypt", 4.0)
	toast.push("Now playing: something long", 4.0)
	assert_str(toast.current_text()).is_equal("Floor 1 - Crypt")
	EventBus.palette_changed.emit(_palette())
	assert_str(toast.current_text()).is_equal("Theme: Gruvbox Test")


## `DesktopWatcher` emits the same string on `EventBus.toast` right after `palette_changed`.
## The banner must not play it twice.
func test_the_watcher_duplicate_is_swallowed() -> void:
	var toast := _toast()
	EventBus.palette_changed.emit(_palette())
	assert_str(toast.current_text()).is_equal("Theme: Gruvbox Test")
	EventBus.toast.emit("Theme: Gruvbox Test", 2.5)
	assert_int(toast.queued_count()).is_equal(0)


func test_ordinary_toasts_still_queue_in_order() -> void:
	var toast := _toast(false)
	toast.push("first", 1.0)
	toast.push("second", 1.0)
	assert_str(toast.current_text()).is_equal("first")
	assert_int(toast.queued_count()).is_equal(1)


## ------------------------------------------------------------------ the radio lane
##
## Every message in the game shared one single-slot serial banner, and the radio was on it:
## `Music` pushed a 3.5 s "Now playing" through the same queue as "-1 Might - stolen!", a boss
## phase and the descend warning, and the queue drops its oldest entry at three. A tester
## caught the result in one frame: the stat-steal floater was live over the player while the
## banner read "NOW PLAYING: NO TITLE BAR - OBSTINATUS".


func _settings_guard() -> void:
	GameState.settings.erase(Toast.SETTING_TRACK_BANNER)


func _hud() -> Hud:
	var hud: Hud = auto_free((load("res://src/ui/hud.tscn") as PackedScene).instantiate())
	add_child(hud)
	return hud


func test_the_radio_never_enters_the_gameplay_queue() -> void:
	var toast := _toast(false)
	_settings_guard()
	toast.push("Equipped Sharp Rusty Sword", 4.0)
	assert_bool(toast.push_track("Now playing: No Title Bar - Obstinatus", 3.5)).is_true()
	assert_str(toast.current_text()).is_equal("Equipped Sharp Rusty Sword")
	assert_int(toast.queued_count()).is_equal(0)
	assert_str(toast.track_text()).is_equal("Now playing: No Title Bar - Obstinatus")


## Three gameplay messages plus a track change used to be four entries in a queue of three,
## and the oldest gameplay fact was the one dropped.
func test_a_track_change_cannot_displace_a_gameplay_message() -> void:
	var toast := _toast(false)
	_settings_guard()
	toast.push("Room cleared", 1.0)
	toast.push("Not enough gold", 1.0)
	toast.push("Cursed: Glass Jaw", 1.0)
	toast.push_track("Now playing: Dotfiles - The Greybeards", 3.5)
	assert_int(toast.queued_count()).is_equal(2)
	assert_str(toast.current_text()).is_equal("Room cleared")


## The banner is decoration, so it can be switched off; nothing a player must read goes
## through this lane, so switching it off silences only the radio.
func test_the_now_playing_banner_can_be_switched_off() -> void:
	var toast := _toast(false)
	GameState.settings[Toast.SETTING_TRACK_BANNER] = false
	assert_bool(toast.push_track("Now playing: Rm -rf - Clownware", 3.5)).is_false()
	assert_str(toast.track_text()).is_empty()
	toast.push("Equipped Keen Copper Ring", 2.0)
	assert_str(toast.current_text()).is_equal("Equipped Keen Copper Ring")
	_settings_guard()


## The setting exists on the Audio page, next to the lyrics toggle, and defaults to on.
func test_the_banner_toggle_is_a_real_settings_row() -> void:
	assert_bool(SettingsPanel.DEFAULTS.has(Toast.SETTING_TRACK_BANNER)).is_true()
	assert_bool(bool(SettingsPanel.DEFAULTS[Toast.SETTING_TRACK_BANNER])).is_true()
	var found := false
	for section: Dictionary in SettingsPanel.SECTIONS:
		for row: Dictionary in section["rows"] as Array:
			if str(row["key"]) == Toast.SETTING_TRACK_BANNER:
				found = true
	assert_bool(found).is_true()


## A message with a matching in-world floater has to appear with it. Queued behind a banner
## already up, "-1 Might - stolen!" arrived seconds after the number that explained it.
func test_the_hud_shows_a_stat_loss_at_the_moment_it_floats_it() -> void:
	var hud := _hud()
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	hud.bind(player)
	hud.prime_stats(true)
	hud.toast("Room cleared", 5.0)
	EventBus.stat_changed.emit(&"might", int(player.stats.primary(&"might")) - 1)
	assert_str(hud.toast_widget().current_text()).is_equal("-1 Might - stolen!")


## And the radio, which is what was covering it, is not in that lane at all.
func test_the_hud_puts_the_track_banner_on_the_radio_lane() -> void:
	var hud := _hud()
	_settings_guard()
	hud.toast("Equipped Vital Leather Jerkin", 5.0)
	EventBus.music_track_changed.emit("No Title Bar", "Obstinatus")
	assert_str(hud.toast_widget().current_text()).is_equal("Equipped Vital Leather Jerkin")
	assert_int(hud.toast_widget().queued_count()).is_equal(0)
	assert_str(hud.toast_widget().track_text()).contains("No Title Bar")
