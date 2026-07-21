extends GdUnitTestSuite

const LIB_PATH := "res://tools/voxel_weapon_model_lib.py"


func test_weapon_generator_library_is_scale_only_and_has_no_model_registry() -> void:
	assert_bool(FileAccess.file_exists(LIB_PATH)).is_true()
	var source := FileAccess.get_file_as_string(LIB_PATH)
	assert_str(source).contains("PX = 1.0 / 32.0")
	assert_str(source).contains("def box_px(")
	assert_str(source).contains("def export_glb(")
	assert_str(source).contains("def render_true_3d_views(")
	assert_str(source).contains("COLOR_0")
	assert_bool(source.contains("BUILDERS")).is_false()
	assert_bool(source.contains("WEAPON_IDS")).is_false()
	assert_bool(source.contains("for weapon_id")).is_false()


func test_weapon_generator_library_writes_four_true_3d_view_names() -> void:
	var source := FileAccess.get_file_as_string(LIB_PATH)
	for view_name in ["preview", "front", "side", "top"]:
		assert_str(source).contains('"%s"' % view_name)
	assert_str(source).contains('f"voxel_{model_id}_render_{view_name}.png"')
