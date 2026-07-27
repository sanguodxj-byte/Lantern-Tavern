extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_leather_armor.py"
const GLB_PATH := "res://assets/meshes/armor/armor_voxel_leather_armor.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const PX := 32.0


func test_leather_armor_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "leather_armor"')
	assert_str(source).contains("TARGET_ENVELOPE_PX = (22.0, 26.0, 14.0)")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("make_pixel_material")
	assert_str(source).contains("pauldron_base")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_leather_armor_registry_keeps_light_body_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("armor", []):
		if String(entry.get("id", "")) != "leather_armor":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("category", ""))).is_equal("armor_light")
		assert_str(String(entry.get("armor_slot", ""))).is_equal("body")
		break
	assert_bool(found).is_true()


func test_leather_armor_glb_has_primary_silhouette_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"neck_guard", "shoulder_band", "chest_band", "waist_band", "skirt_band",
		"breast_upper", "breast_mid", "pauldron_base_left", "pauldron_base_right",
		"belt_buckle",
	]:
		assert_bool(names.has(part_name)).override_failure_message("missing part %s" % part_name).is_true()
	instance.free()


func test_leather_armor_envelope_is_noticeably_larger_than_player_torso() -> void:
	var instance := _instantiate()
	var size_px := _combined_aabb(instance).size * PX
	assert_float(size_px.x).is_greater_equal(20.0)
	assert_float(size_px.y).is_greater_equal(22.0)
	assert_float(size_px.z).is_greater_equal(12.0)
	instance.free()


func test_leather_armor_has_no_positive_volume_overlap() -> void:
	var instance := _instantiate()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	instance.free()


func test_leather_armor_blender_renders_are_readable() -> void:
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_leather_armor_render_%s.png" % view_name
		)
		assert_bool(rendered["exists"]).is_true()
		assert_bool(rendered["nonblank"]).is_true()


func _instantiate() -> Node3D:
	var packed := load(GLB_PATH) as PackedScene
	var instance := packed.instantiate() as Node3D
	add_child(instance)
	return instance


func _collect_names(node: Node) -> Array[String]:
	var names: Array[String] = [String(node.name)]
	for child in node.get_children():
		names.append_array(_collect_names(child))
	return names


func _combined_aabb(node: Node3D) -> AABB:
	var boxes: Array[Dictionary] = []
	_collect_boxes(node, node, boxes)
	var result := AABB()
	var first := true
	for entry in boxes:
		var box: AABB = entry["aabb"]
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result


func _collect_boxes(root_node: Node3D, node: Node, boxes: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var root_space := root_node.global_transform.affine_inverse() * mesh_node.global_transform
			boxes.append({"aabb": root_space * mesh_node.get_aabb()})
	for child in node.get_children():
		_collect_boxes(root_node, child, boxes)
