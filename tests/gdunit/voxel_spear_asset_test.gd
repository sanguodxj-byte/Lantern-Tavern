extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_spear.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_spear.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_spear_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "spear"')
	assert_str(source).contains("WIDTH_PX = 13.0")
	assert_str(source).contains("DEPTH_PX = 9.0")
	assert_str(source).contains("LENGTH_PX = 73.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_spear_registry_keeps_two_hand_reach_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "spear":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("two_hand")
		assert_str(String(entry.get("skill_school", ""))).is_equal("spear")
		assert_array(entry.get("tags", [])).contains(["polearm", "spear", "reach"])
		break
	assert_bool(found).is_true()


func test_spear_glb_has_54_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"body_shaft_core", "head_tip", "head_point_spine", "head_point_edge_left",
		"head_point_edge_right", "head_ridge_front", "head_ridge_back",
		"head_belly_flat_left", "head_belly_flat_right", "socket_crown_core",
		"socket_rivet_front", "socket_rivet_back", "grip_fore_left", "grip_fore_right",
		"grip_rear_front", "grip_rear_back", "butt_cap_left", "butt_cap_right",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("spear missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(54)
	instance.free()


func test_spear_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(13.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(73.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(9.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_spear_first_runtime_mesh_is_the_long_shaft() -> void:
	var instance := _instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	assert_str(String(meshes[0].name)).is_equal("body_shaft_core")
	assert_float((meshes[0] as MeshInstance3D).get_aabb().size.y) \
		.is_equal_approx(48.0 / 32.0, 0.002)
	instance.free()


func test_spear_imported_palette_keeps_steel_bronze_wood_and_leather() -> void:
	var instance := _instantiate()
	var steel := _mesh_color(instance, "head_belly_flat_left")
	var bronze := _mesh_color(instance, "socket_crown_left")
	var wood := _mesh_color(instance, "body_shaft_core")
	var leather := _mesh_color(instance, "grip_rear_front")
	assert_bool(steel.b > steel.r and steel.g > steel.r).is_true()
	assert_bool(bronze.r > bronze.g and bronze.g > bronze.b).is_true()
	assert_bool(wood.r > wood.g and wood.g > wood.b).is_true()
	assert_bool(leather.r > leather.g and leather.r - leather.b > 0.20).is_true()
	instance.free()


func test_spear_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"spear": "res://assets/meshes/weapons/weapons_voxel_spear.glb"')


func test_spear_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/spear_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank spear structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_spear_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank spear Blender view: %s" % view_name).is_true()


func _instantiate() -> Node3D:
	var packed := load(GLB_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	add_child(instance)
	return instance


func _collect_names(node: Node) -> Array[String]:
	var names: Array[String] = [String(node.name)]
	for child in node.get_children():
		names.append_array(_collect_names(child))
	return names


func _mesh_color(root_node: Node, part_name: String) -> Color:
	for child in root_node.find_children(part_name, "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var material := mesh.get_active_material(0) as BaseMaterial3D
		assert_object(material).is_not_null()
		return material.albedo_color
	assert_bool(false).override_failure_message("spear missing palette part: %s" % part_name).is_true()
	return Color.WHITE
