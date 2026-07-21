extends GdUnitTestSuite

func test_voxel_longsword_outputs_exist() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_longsword.py")).is_true()
	assert_bool(FileAccess.file_exists("res://assets/meshes/weapons/weapons_voxel_longsword.glb")).is_true()
	assert_bool(FileAccess.file_exists("res://reports/weapons_preview/voxel_longsword_preview.png")).is_true()
	assert_bool(FileAccess.file_exists("res://reports/weapons_preview/voxel_longsword_front.png")).is_true()
	assert_bool(FileAccess.file_exists("res://reports/weapons_preview/voxel_longsword_side.png")).is_true()
	assert_bool(FileAccess.file_exists("res://reports/weapons_preview/voxel_longsword_top.png")).is_true()

func test_voxel_longsword_glb_contains_expected_parts() -> void:
	var file := FileAccess.open("res://assets/meshes/weapons/weapons_voxel_longsword.glb", FileAccess.READ)
	assert_object(file).is_not_null()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var cleaned := bytes.duplicate()
	for i in range(cleaned.size()):
		if cleaned[i] == 0:
			cleaned[i] = 32
	var text := cleaned.get_string_from_ascii()
	for part_name in ["weapons_voxel_longsword", "blade_base_highlight", "blade_point_shadow", "blade_tip_spark", "crossguard_core", "grip", "pommel_block"]:
		assert_bool(text.contains(part_name)) \
			.override_failure_message("voxel longsword GLB missing part: %s" % part_name) \
			.is_true()
