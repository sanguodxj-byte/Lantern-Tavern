extends GdUnitTestSuite

const MODEL_ID := "blackberry"


func test_blackberry_generator_and_asset() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_blackberry.py")).is_true()
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_blackberry.py")
	assert_str(source).contains('MODEL_ID = "blackberry"')
	assert_str(source).contains("reject_target_override")
	assert_str(source).not_contains("for material_id in")
	assert_bool(FileAccess.file_exists("res://assets/models/materials/materials_blackberry.glb")).is_true()
	var scene := load("res://assets/models/materials/materials_blackberry.glb")
	assert_object(scene).is_instanceof(PackedScene)
	var inst := (scene as PackedScene).instantiate()
	assert_int(_count_meshes(inst)).is_greater_equal(2)
	inst.free()
	for view in ["front", "side", "top"]:
		assert_bool(FileAccess.file_exists("res://reports/materials_preview/voxel_blackberry_%s.png" % view)).is_true()


func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total
