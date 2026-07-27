extends GdUnitTestSuite

func test_giant_rat_tail_generator_and_asset() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_giant_rat_tail.py")).is_true()
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_giant_rat_tail.py")
	assert_str(source).contains('MODEL_ID = "giant_rat_tail"')
	assert_str(source).contains("reject_target_override")
	assert_bool(FileAccess.file_exists("res://assets/models/materials/materials_giant_rat_tail.glb")).is_true()
	assert_object(load("res://assets/models/materials/materials_giant_rat_tail.glb")).is_instanceof(PackedScene)
	for view in ["front", "side", "top"]:
		assert_bool(FileAccess.file_exists("res://reports/materials_preview/voxel_giant_rat_tail_%s.png" % view)).is_true()
