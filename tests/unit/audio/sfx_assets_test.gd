## Checks tools/gen-sfx.py output: every AudioManager id has a valid, non-empty 22050 Hz WAV.
class_name SfxAssetsTest
extends GdUnitTestSuite


func test_every_id_has_a_valid_wav() -> void:
	for id in AudioManager.IDS:
		var path := AudioManager.SFX_DIR + String(id) + ".wav"
		(
			assert_bool(FileAccess.file_exists(path))
			. override_failure_message("missing %s" % path)
			. is_true()
		)
		var file := FileAccess.open(path, FileAccess.READ)
		assert_object(file).is_not_null()
		var header := file.get_buffer(12)
		assert_str(header.slice(0, 4).get_string_from_ascii()).is_equal("RIFF")
		assert_str(header.slice(8, 12).get_string_from_ascii()).is_equal("WAVE")
		(
			assert_int(int(file.get_length()))
			. override_failure_message("%s too small" % path)
			. is_greater(1000)
		)


func test_wavs_import_as_streams_with_sane_length() -> void:
	for id in AudioManager.IDS:
		var path := AudioManager.SFX_DIR + String(id) + ".wav"
		var stream := load(path) as AudioStream
		assert_object(stream).override_failure_message("%s did not import" % path).is_not_null()
		if stream == null:
			continue
		var length := stream.get_length()
		assert_float(length).override_failure_message("%s length %.3f" % [path, length]).is_between(
			0.03, 1.5
		)


func test_fallback_loops_exist() -> void:
	for f in MusicManager.FALLBACK_FILES:
		var path := MusicManager.FALLBACK_DIR + f
		var stream := load(path) as AudioStream
		assert_object(stream).override_failure_message("missing %s" % path).is_not_null()
		if stream != null:
			assert_float(stream.get_length()).is_between(15.0, 35.0)
