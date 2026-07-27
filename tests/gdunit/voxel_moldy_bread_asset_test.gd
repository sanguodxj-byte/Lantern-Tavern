extends GdUnitTestSuite

const MODEL_ID := "moldy_bread"
const GLB_PATH := "res://assets/models/materials/materials_moldy_bread.glb"
const GENERATOR_PATH := "res://tools/generate_voxel_moldy_bread.py"
const MANIFEST_PATH := "res://data/material_model_manifest.json"


func test_moldy_bread_single_model_generator_and_asset() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "moldy_bread"')
	assert_str(source).contains("reject_target_override")
	assert_str(source).not_contains("for material_id in")
	assert_bool(FileAccess.file_exists(GLB_PATH)).is_true()
	var scene := load(GLB_PATH)
	assert_object(scene).is_instanceof(PackedScene)
	var inst := (scene as PackedScene).instantiate()
	assert_int(_count_meshes(inst)).is_greater_equal(4)
	inst.free()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var entry: Dictionary = {}
	for item in parsed.get("materials", []):
		if String(item.get("id", "")) == MODEL_ID:
			entry = item
			break
	assert_bool(not entry.is_empty()).is_true()
	assert_str(String(entry.get("generated_by", ""))).contains("generate_voxel_moldy_bread.py")
	for view in ["front", "side", "top"]:
		var path := "res://reports/materials_preview/voxel_%s_%s.png" % [MODEL_ID, view]
		assert_bool(FileAccess.file_exists(path)).is_true()
		var img := Image.new()
		assert_int(img.load(path)).is_equal(OK)
		assert_int(img.get_width()).is_greater(32)


func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total
