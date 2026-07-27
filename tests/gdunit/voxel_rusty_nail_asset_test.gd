extends GdUnitTestSuite

const MODEL_ID := "rusty_nail"
const GLB_PATH := "res://assets/models/materials/materials_rusty_nail.glb"
const GENERATOR_PATH := "res://tools/generate_voxel_rusty_nail.py"
const MANIFEST_PATH := "res://data/material_model_manifest.json"


func test_rusty_nail_single_model_generator_and_asset() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "rusty_nail"')
	assert_str(source).contains("reject_target_override")
	assert_str(source).not_contains("for material_id in")
	assert_bool(FileAccess.file_exists(GLB_PATH)).is_true()
	var scene := load(GLB_PATH)
	assert_object(scene).is_instanceof(PackedScene)
	var inst := (scene as PackedScene).instantiate()
	assert_int(_count_meshes(inst)).is_greater_equal(2)
	inst.free()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var found := false
	for item in parsed.get("materials", []):
		if String(item.get("id", "")) == MODEL_ID:
			found = true
			assert_str(String(item.get("generated_by", ""))).contains("generate_voxel_rusty_nail.py")
			break
	assert_bool(found).is_true()
	for view in ["front", "side", "top"]:
		var path := "res://reports/materials_preview/voxel_%s_%s.png" % [MODEL_ID, view]
		assert_bool(FileAccess.file_exists(path)).is_true()


func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total
