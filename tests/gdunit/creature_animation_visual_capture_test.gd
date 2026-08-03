extends GdUnitTestSuite

const CAPTURE_SCRIPT := "res://tools/creature_animation_visual_capture.gd"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_capture_requires_one_exact_asset_and_uses_production_creature_scenes() -> void:
	assert_bool(FileAccess.file_exists(CAPTURE_SCRIPT)).is_true()
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	assert_str(source).contains("Exactly one --asset=<slime|spider> selector is required.")
	assert_str(source).contains("Multiple, wildcard, and all asset selectors are forbidden.")
	assert_str(source).contains('"res://scenes/characters/enemies/slime.tscn"')
	assert_str(source).contains('"res://scenes/characters/enemies/spider.tscn"')
	assert_str(source).contains('get_node_or_null("character/AnimationPlayer")')
	assert_str(source).contains('player.get_animation("run")')
	assert_str(source).contains('player.seek(run.length * float(phase["progress"]), true)')
	assert_str(source).contains("Creature animation capture requires a non-headless renderer.")


func test_capture_defines_slime_hop_and_spider_gait_acceptance_phases() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	for phase in ["takeoff", "apex", "landing", "group_a", "contact", "group_b"]:
		assert_str(source).contains('{"name": "%s"' % phase)
	assert_str(source).contains('voxel_%s_motion_%s_%s.png')


func test_generated_creature_motion_captures_are_readable_and_nonblank() -> void:
	var phases := {
		"slime": ["takeoff", "apex", "landing"],
		"spider": ["group_a", "contact", "group_b"],
	}
	for asset in phases:
		for phase in phases[asset]:
			for view in ["front", "top"]:
				var path := "res://reports/characters_preview/voxel_%s_motion_%s_%s.png" % [
					asset, phase, view,
				]
				var inspection: Dictionary = SUPPORT.inspect_image_file(path)
				assert_bool(bool(inspection["exists"])).override_failure_message(
					"missing creature motion capture: %s" % path
				).is_true()
				if not bool(inspection["exists"]):
					continue
				assert_bool(bool(inspection["readable"])).is_true()
				assert_int(int(inspection["width"])).is_greater_equal(900)
				assert_int(int(inspection["height"])).is_greater_equal(900)
				assert_bool(bool(inspection["nonblank"])).override_failure_message(
					"blank creature motion capture: %s" % path
				).is_true()
