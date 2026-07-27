extends GdUnitTestSuite

func test_dragon_scale_generator_and_asset() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_dragon_scale.py")).is_true()
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_dragon_scale.py")
	assert_str(source).contains('MODEL_ID = "dragon_scale"')
	assert_str(source).contains("reject_target_override")
	assert_bool(FileAccess.file_exists("res://assets/models/materials/materials_dragon_scale.glb")).is_true()
	assert_object(load("res://assets/models/materials/materials_dragon_scale.glb")).is_instanceof(PackedScene)
	for view in ["front", "side", "top"]:
		assert_bool(FileAccess.file_exists("res://reports/materials_preview/voxel_dragon_scale_%s.png" % view)).is_true()
