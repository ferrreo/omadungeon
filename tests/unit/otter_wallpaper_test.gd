class_name OtterWallpaperTest
extends GdUnitTestSuite


func test_parse_state_primary_first() -> void:
	var text := "# otter-theme-gen-palette: shared-primary\nDP-2=/usr/share/a.jpg\nDP-3=/usr/share/b.jpg\n"
	var parsed := OtterWallpaper.parse_state(text)
	assert_int(parsed.size()).is_equal(2)
	assert_str(parsed.values()[0]).is_equal("/usr/share/a.jpg")


func test_parse_state_rejects_relative_and_dotdot() -> void:
	var parsed := OtterWallpaper.parse_state(
		"DP-1=relative.png\nDP-2=/x/../etc/passwd\nDP-3=/ok.png"
	)
	assert_int(parsed.size()).is_equal(1)
	assert_str(parsed["DP-3"]).is_equal("/ok.png")


func test_parse_conf_and_colors() -> void:
	var path := "user://otter-colors-test.conf"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('background = "#101010FF"\naccent = "#3399ffff"\njunk = "zzz"\n')
	f.close()
	var colors := OtterWallpaper.load_colors(path)
	assert_int(colors.size()).is_equal(2)
	assert_object(colors["accent"]).is_equal(Color("#3399ffff"))


func test_theme_conf_colors_path_resolution() -> void:
	var base := ProjectSettings.globalize_path("user://otter-test-config")
	DirAccess.make_dir_recursive_absolute(base.path_join("otter-shell"))
	var theme_conf := FileAccess.open(base.path_join("otter-shell/theme.conf"), FileAccess.WRITE)
	theme_conf.store_string('colors_path = "my-colors.conf"\nfont_size = 16\n')
	theme_conf.close()
	var colors := FileAccess.open(base.path_join("otter-shell/my-colors.conf"), FileAccess.WRITE)
	colors.store_string(
		'# generated\nbackground = "#140F0DFF"\naccent = "#D4AF97FF"\ndanger = "#FF353AFF"\n'
	)
	colors.close()
	var previous := OS.get_environment("XDG_CONFIG_HOME")
	OS.set_environment("XDG_CONFIG_HOME", base)
	var resolved := OtterWallpaper.theme_colors_path()
	var loaded := OtterWallpaper.load_colors(resolved)
	var sig := OtterWallpaper.signature()
	OS.set_environment("XDG_CONFIG_HOME", previous)
	assert_str(resolved).is_equal(base.path_join("otter-shell/my-colors.conf"))
	assert_bool(OtterWallpaper.is_valid_wallpaper_path(resolved)).is_true()
	assert_object(loaded["background"]).is_equal(Color("#140F0DFF"))
	assert_object(loaded["accent"]).is_equal(Color("#D4AF97FF"))
	assert_int(loaded.size()).is_equal(3)
	assert_str(sig).contains("|")


func test_absolute_colors_path_kept() -> void:
	var base := ProjectSettings.globalize_path("user://otter-test-config2")
	DirAccess.make_dir_recursive_absolute(base.path_join("otter-shell"))
	var theme_conf := FileAccess.open(base.path_join("otter-shell/theme.conf"), FileAccess.WRITE)
	theme_conf.store_string('colors_path = "/usr/share/otter-shell/themes/colors/nord.conf"\n')
	theme_conf.close()
	var previous := OS.get_environment("XDG_CONFIG_HOME")
	OS.set_environment("XDG_CONFIG_HOME", base)
	var resolved := OtterWallpaper.theme_colors_path()
	OS.set_environment("XDG_CONFIG_HOME", previous)
	assert_str(resolved).is_equal("/usr/share/otter-shell/themes/colors/nord.conf")
