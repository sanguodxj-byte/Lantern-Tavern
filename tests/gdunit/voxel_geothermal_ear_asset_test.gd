extends GdUnitTestSuite

func test_geothermal_ear_generator_and_asset() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_geothermal_ear.py")).is_true()
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_geothermal_ear.py")
	assert_str(source).contains('MODEL_ID = "geothermal_ear"')
	assert_str(source).contains("reject_target_override")
	assert_bool(FileAccess.file_exists("res://assets/models/materials/materials_geothermal_ear.glb")).is_true()
	assert_object(load("res://assets/models/materials/materials_geothermal_ear.glb")).is_instanceof(PackedScene)
	for view in ["front", "side", "top"]:
		assert_bool(FileAccess.file_exists("res://reports/materials_preview/voxel_geothermal_ear_%s.png" % view)).is_true()
