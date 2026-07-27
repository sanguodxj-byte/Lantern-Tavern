extends GdUnitTestSuite

func test_poison_berry_generator_and_asset() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_poison_berry.py")).is_true()
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_poison_berry.py")
	assert_str(source).contains('MODEL_ID = "poison_berry"')
	assert_str(source).contains("reject_target_override")
	assert_bool(FileAccess.file_exists("res://assets/models/materials/materials_poison_berry.glb")).is_true()
	var scene := load("res://assets/models/materials/materials_poison_berry.glb")
	assert_object(scene).is_instanceof(PackedScene)
	var inst := (scene as PackedScene).instantiate()
	assert_int(_count_meshes(inst)).is_greater_equal(2)
	inst.free()
	for view in ["front", "side", "top"]:
		assert_bool(FileAccess.file_exists("res://reports/materials_preview/voxel_poison_berry_%s.png" % view)).is_true()

func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total
