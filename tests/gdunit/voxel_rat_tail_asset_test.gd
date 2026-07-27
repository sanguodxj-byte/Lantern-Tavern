extends GdUnitTestSuite

const MODEL_ID := "rat_tail"
const GLB_PATH := "res://assets/models/materials/materials_rat_tail.glb"
const GENERATOR_PATH := "res://tools/generate_voxel_rat_tail.py"
const MANIFEST_PATH := "res://data/material_model_manifest.json"
const PREVIEW_DIR := "res://reports/materials_preview"


func test_rat_tail_generator_is_single_model_owned() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "rat_tail"')
	assert_str(source).contains("reject_target_override")
	assert_str(source).contains("finish_model")
	assert_str(source).not_contains("for material_id in")
	assert_str(source).not_contains("MATERIALS =")


func test_rat_tail_glb_exists_and_loads() -> void:
	assert_bool(FileAccess.file_exists(GLB_PATH)).is_true()
	var scene := load(GLB_PATH)
	assert_object(scene).is_instanceof(PackedScene)
	var inst := (scene as PackedScene).instantiate()
	assert_object(inst).is_not_null()
	assert_int(_count_meshes(inst)).is_greater_equal(3)
	inst.free()


func test_rat_tail_manifest_bbox_is_elongated() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var entry: Dictionary = {}
	for item in parsed.get("materials", []):
		if String(item.get("id", "")) == MODEL_ID:
			entry = item
			break
	assert_bool(not entry.is_empty()).is_true()
	var bbox: Array = entry.get("bbox", [])
	assert_array(bbox).has_size(3)
	var values := [float(bbox[0]), float(bbox[1]), float(bbox[2])]
	values.sort()
	assert_float(values[2] / maxf(values[0], 0.0001)).is_greater_equal(4.0)
	assert_str(String(entry.get("generated_by", ""))).contains("generate_voxel_rat_tail.py")


func test_rat_tail_previews_exist_and_are_readable() -> void:
	for view in ["front", "side", "top"]:
		var path := "%s/voxel_%s_%s.png" % [PREVIEW_DIR, MODEL_ID, view]
		assert_bool(FileAccess.file_exists(path)).override_failure_message("missing preview: " + path).is_true()
		var img := Image.new()
		assert_int(img.load(path)).is_equal(OK)
		assert_int(img.get_width()).is_greater(32)
		assert_int(img.get_height()).is_greater(32)
		var lit := 0
		var step_x := maxi(1, img.get_width() / 24)
		var step_y := maxi(1, img.get_height() / 24)
		for y in range(0, img.get_height(), step_y):
			for x in range(0, img.get_width(), step_x):
				var c := img.get_pixel(x, y)
				if c.a > 0.05 and (c.r + c.g + c.b) > 0.08:
					lit += 1
		assert_int(lit).is_greater(3)


func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total
