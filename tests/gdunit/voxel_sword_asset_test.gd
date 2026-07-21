extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_sword.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_sword.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_sword_generator_is_dedicated_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "sword"')
	assert_str(source).contains("WIDTH_PX = 17.0")
	assert_str(source).contains("DEPTH_PX = 7.0")
	assert_str(source).contains("LENGTH_PX = 43.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("generate_voxel_shortsword")).is_false()
	assert_bool(source.contains("generate_voxel_greatsword")).is_false()
	assert_bool(source.contains("BUILDERS")).is_false()


func test_sword_registry_keeps_one_hand_blade_identity_and_throw_stats() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "sword":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("category", ""))).is_equal("weapons")
		assert_str(String(entry.get("weapon_class", ""))).is_equal("one_hand_melee")
		assert_str(String(entry.get("skill_school", ""))).is_equal("one_hand_sword")
		assert_str(String(entry.get("hands", ""))).is_equal("one_hand")
		assert_array(entry.get("tags", [])).contains(["weapon", "melee", "blade", "one_hand_sword"])
		var stats: Dictionary = entry.get("stats", {})
		assert_float(float(stats.get("throw_rotation_speed", 0.0))).is_equal_approx(40.0, 0.001)
		assert_float(float(stats.get("throw_movement_speed", 0.0))).is_equal_approx(10.0, 0.001)
		break
	assert_bool(found).is_true()


func test_sword_glb_has_exactly_22_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"a_blade_spine_core", "blade_forte_edge_left", "blade_forte_edge_right",
		"blade_mid_edge_left", "blade_mid_edge_right", "blade_tip",
		"blade_ridge_front", "blade_ridge_back", "guard_center",
		"guard_inner_left", "guard_inner_right", "guard_outer_left", "guard_outer_right",
		"guard_tip_left", "guard_tip_right", "grip_collar", "grip_upper",
		"grip_band_upper", "grip_middle", "grip_band_lower", "grip_lower", "pommel_cap",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("sword missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(22)
	instance.free()


func test_sword_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(17.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(43.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(7.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_sword_blade_tapers_7_to_5_to_3_to_1_pixels() -> void:
	var instance := _instantiate()
	var forte_width := _combined_named_width(instance, ["a_blade_spine_core", "blade_forte_edge_left", "blade_forte_edge_right"])
	var mid_width := _combined_named_width(instance, ["a_blade_spine_core", "blade_mid_edge_left", "blade_mid_edge_right"])
	var spine := _find_mesh(instance, "a_blade_spine_core")
	var tip := _find_mesh(instance, "blade_tip")
	assert_float(forte_width).is_equal_approx(7.0 / 32.0, 0.002)
	assert_float(mid_width).is_equal_approx(5.0 / 32.0, 0.002)
	assert_float(spine.get_aabb().size.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(tip.get_aabb().size.x).is_equal_approx(1.0 / 32.0, 0.002)
	instance.free()


func test_sword_first_runtime_mesh_is_the_long_blade_spine() -> void:
	var instance := _instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	assert_str(String(meshes[0].name)).is_equal("a_blade_spine_core")
	var size := (meshes[0] as MeshInstance3D).get_aabb().size
	assert_float(size.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(size.y).is_equal_approx(27.0 / 32.0, 0.002)
	assert_float(size.z).is_equal_approx(3.0 / 32.0, 0.002)
	instance.free()


func test_sword_imported_palette_keeps_steel_brass_and_green_leather() -> void:
	var instance := _instantiate()
	var core := _mesh_color(instance, "a_blade_spine_core")
	var polished := _mesh_color(instance, "blade_ridge_front")
	var brass := _mesh_color(instance, "pommel_cap")
	var leather := _mesh_color(instance, "grip_middle")
	assert_bool(core.b > core.r and core.g > core.r).is_true()
	assert_bool(polished.r > core.r and polished.g > core.g and polished.b > core.b).is_true()
	assert_bool(brass.r > brass.g and brass.g > brass.b).is_true()
	assert_bool(leather.g > leather.r and leather.g > leather.b).is_true()
	instance.free()


func test_sword_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"sword": "res://assets/meshes/weapons/weapons_voxel_sword.glb"')


func test_sword_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/sword_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank sword structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_sword_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank sword Blender view: %s" % view_name).is_true()


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


func _find_mesh(root_node: Node, part_name: String) -> MeshInstance3D:
	for child in root_node.find_children(part_name, "MeshInstance3D", true, false):
		return child as MeshInstance3D
	assert_bool(false).override_failure_message("missing sword mesh: %s" % part_name).is_true()
	return null


func _combined_named_width(root_node: Node, part_names: Array[String]) -> float:
	var first := _find_mesh(root_node, part_names[0])
	var bounds := first.global_transform * first.get_aabb()
	for index in range(1, part_names.size()):
		var mesh := _find_mesh(root_node, part_names[index])
		bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
	return bounds.size.x


func _mesh_color(root_node: Node, part_name: String) -> Color:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as BaseMaterial3D
	assert_object(material).is_not_null()
	return material.albedo_color
