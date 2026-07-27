extends GdUnitTestSuite

func test_troll_blood_generator_and_asset() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_troll_blood.py")).is_true()
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_troll_blood.py")
	assert_str(source).contains('MODEL_ID = "troll_blood"')
	assert_str(source).contains("reject_target_override")
	assert_bool(FileAccess.file_exists("res://assets/models/materials/materials_troll_blood.glb")).is_true()
	assert_object(load("res://assets/models/materials/materials_troll_blood.glb")).is_instanceof(PackedScene)
	for view in ["front", "side", "top"]:
		assert_bool(FileAccess.file_exists("res://reports/materials_preview/voxel_troll_blood_%s.png" % view)).is_true()
