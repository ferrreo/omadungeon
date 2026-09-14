class_name WallpaperAnalyzerTest
extends GdUnitTestSuite


func test_analyze_flat_image() -> void:
	var img := Image.create(128, 72, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.4, 0.6))
	var r := WallpaperAnalyzer.analyze_image(img)
	assert_int(r.dominant.size()).is_equal(4)
	assert_float(r.dominant[0].r).is_equal_approx(0.2, 0.02)
	assert_float(r.edge_density).is_equal(0.0)
	assert_float(r.ambient).is_between(0.55, 1.0)


func test_analyze_two_tone_image_finds_both() -> void:
	var img := Image.create(128, 72, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	img.fill_rect(Rect2i(64, 0, 64, 72), Color.WHITE)
	var r := WallpaperAnalyzer.analyze_image(img)
	assert_float(r.dominant[0].get_luminance()).is_greater(0.9)
	assert_float(r.dominant[3].get_luminance()).is_less(0.1)
	assert_float(r.edge_density).is_greater(0.0)


func test_analyze_fixture_preview() -> void:
	var path := ProjectSettings.globalize_path(
		"res://tests/fixtures/omarchy/tokyo-night/state/current/theme/preview.png"
	)
	var r := WallpaperAnalyzer.analyze_file(path)
	assert_object(r).is_not_null()
	assert_int(r.dominant.size()).is_equal(4)
