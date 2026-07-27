extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_chain_armor.py"
const GLB_PATH := "res://assets/meshes/armor/armor_voxel_chain_armor.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const PX := 32.0


func test_chain_armor_generator_is_fixed_identity_and_targets_envelope() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "chain_armor"')
	assert_str(source).contains("TARGET_ENVELOPE_PX = (24.0, 28.0, 14.0)")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_chain_armor_glb_has_primary_hauberk_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"foundation_neck", "foundation_shoulder", "foundation_chest", "foundation_waist", "foundation_skirt",
		"chain_front_chest", "chain_back_chest", "pauldron_base_left", "pauldron_base_right", "coif_rim",
	]:
		assert_bool(names.has(part_name)).override_failure_message("missing %s" % part_name).is_true()
	instance.free()


func test_chain_armor_envelope_is_heavy_oversized() -> void:
	var instance := _instantiate()
	var size_px := _combined_aabb(instance).size * PX
	assert_float(size_px.x).is_greater_equal(22.0)
	assert_float(size_px.y).is_greater_equal(24.0)
	assert_float(size_px.z).is_greater_equal(10.0)
	instance.free()


func test_chain_armor_leather_foundation_has_pixel_texture() -> void:
	var instance := _instantiate()
	var foundation := _mesh_material(instance, "foundation_chest")
	assert_object(foundation.albedo_texture).is_not_null()
	instance.free()


func test_chain_armor_ring_pattern_has_pixel_texture() -> void:
	var instance := _instantiate()
	var rings := _mesh_material(instance, "chain_front_chest")
	assert_object(rings.albedo_texture).is_not_null()
	instance.free()


func test_chain_armor_no_positive_volume_overlap() -> void:
	var instance := _instantiate()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	instance.free()


func test_chain_armor_blender_renders_are_readable() -> void:
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_chain_armor_render_%s.png" % view_name
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


func _find_mesh(root_node: Node, part_name: String) -> MeshInstance3D:
	for child in root_node.find_children(part_name, "MeshInstance3D", true, false):
		return child as MeshInstance3D
	assert_bool(false).override_failure_message("missing mesh %s" % part_name).is_true()
	return null


func _mesh_material(root_node: Node, part_name: String) -> StandardMaterial3D:
	return _find_mesh(root_node, part_name).get_active_material(0) as StandardMaterial3D


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
