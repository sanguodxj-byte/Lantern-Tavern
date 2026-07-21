extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_axe.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_axe.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_axe_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "axe"')
	assert_str(source).contains("WIDTH_PX = 23.0")
	assert_str(source).contains("DEPTH_PX = 7.0")
	assert_str(source).contains("LENGTH_PX = 45.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_str(source).contains('ROOT / "reports" / "props_preview"')
	assert_bool(source.contains("BUILDERS")).is_false()


func test_axe_registry_keeps_heavy_two_hand_axe_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "axe":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("two_hand")
		assert_array(entry.get("tags", [])).contains(["two_hand_axe", "heavy"])
		break
	assert_bool(found).is_true()


func test_axe_glb_has_21_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"head_socket_core", "head_cheek_front", "head_cheek_back", "head_crown",
		"blade_root_left", "blade_root_right", "blade_mid_left", "blade_mid_right",
		"blade_outer_left", "blade_outer_right", "blade_edge_left", "blade_edge_right",
		"haft_neck", "haft_upper", "grip_band_upper", "grip_upper",
		"grip_band_center", "grip_lower", "grip_band_lower", "haft_butt", "pommel_cap",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("axe missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(21)
	instance.free()


func test_axe_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(23.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(45.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(7.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_axe_imported_palette_keeps_steel_bronze_wood_and_leather() -> void:
	var instance := _instantiate()
	var steel := _mesh_color(instance, "blade_mid_left")
	var bronze := _mesh_color(instance, "head_cheek_front")
	var wood := _mesh_color(instance, "haft_upper")
	var leather := _mesh_color(instance, "grip_upper")
	assert_bool(steel.b > steel.r and steel.g > steel.r).is_true()
	assert_bool(bronze.r > bronze.g and bronze.g > bronze.b).is_true()
	assert_bool(wood.r > wood.g and wood.g > wood.b).is_true()
	assert_bool(leather.r > leather.g and leather.r - leather.b > 0.12).is_true()
	instance.free()


func test_axe_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"axe": "res://assets/meshes/weapons/weapons_voxel_axe.glb"')


func test_pickable_axe_relies_on_one_runtime_glb_instance() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/equipment/pickable_axe.tscn")
	assert_bool(scene_source.contains("weapons_voxel_axe.glb")).is_false()
	assert_bool(scene_source.contains("mesh_node = NodePath")).is_false()
	assert_str(scene_source).contains('owner_weapon_id = "axe"')


func test_axe_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/axe_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank axe structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_axe_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank axe Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("axe missing palette part: %s" % part_name).is_true()
	return Color.WHITE
