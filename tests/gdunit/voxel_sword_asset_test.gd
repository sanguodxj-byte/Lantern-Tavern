extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_sword.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_sword.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_sword_generator_is_dedicated_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "sword"')
	assert_str(source).contains("WIDTH_PX = 19.0")
	assert_str(source).contains("DEPTH_PX = 7.0")
	assert_str(source).contains("LENGTH_PX = 95.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_str(source).contains('add("blade_body"')
	assert_str(source).contains('add("blade_taper"')
	assert_bool(source.contains("blade_taper_upper")).is_false()
	assert_bool(source.contains("blade_taper_mid")).is_false()
	assert_bool(source.contains("blade_forte")).is_false()
	assert_bool(source.contains("blade_shoulders")).is_false()
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


func test_sword_glb_has_exactly_17_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"blade_body", "blade_taper", "blade_point", "guard_center",
		"guard_inner_left", "guard_inner_right", "guard_outer_left", "guard_outer_right",
		"guard_tip_left", "guard_tip_right", "grip_collar", "grip_upper",
		"grip_band_upper", "grip_middle", "grip_band_lower", "grip_lower", "pommel_cap",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("sword missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(17)
	instance.free()


func test_sword_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(19.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(95.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(7.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_sword_blade_stays_full_width_until_the_terminal_point() -> void:
	var instance := _instantiate()
	var blade_names := ["blade_body", "blade_taper", "blade_point"]
	var expected_widths := [5.0, 3.0, 1.0]
	var expected_lengths := [77.0, 2.0, 1.0]
	var expected_depths := [1.0, 1.0, 1.0]
	for index in blade_names.size():
		var blade := _find_mesh(instance, blade_names[index])
		var size := blade.get_aabb().size
		assert_float(size.x).is_equal_approx(expected_widths[index] / 32.0, 0.002)
		assert_float(size.y).is_equal_approx(expected_lengths[index] / 32.0, 0.002)
		assert_float(size.z).is_equal_approx(expected_depths[index] / 32.0, 0.002)
		if expected_widths[index] == 1.0:
			assert_str(blade_names[index]).is_equal("blade_point")
			assert_float(expected_lengths[index]).is_equal_approx(1.0, 0.001)
	assert_bool(_collect_names(instance).has("blade_face_front")).is_false()
	assert_bool(_collect_names(instance).has("blade_face_back")).is_false()
	assert_bool(_collect_names(instance).has("blade_taper_upper")).is_false()
	assert_bool(_collect_names(instance).has("blade_taper_mid")).is_false()
	assert_bool(_collect_names(instance).has("blade_profile")).is_false()
	assert_bool(_collect_names(instance).has("blade_wing_left")).is_false()
	assert_bool(_collect_names(instance).has("blade_wing_right")).is_false()
	assert_bool(_collect_names(instance).has("blade_ridge_front")).is_false()
	assert_bool(_collect_names(instance).has("blade_ridge_back")).is_false()
	instance.free()


func test_sword_blade_body_runtime_mesh_is_the_widest_blade_voxel() -> void:
	var instance := _instantiate()
	var mesh := _find_mesh(instance, "blade_body")
	var size := mesh.get_aabb().size
	assert_float(size.x).is_equal_approx(5.0 / 32.0, 0.002)
	assert_float(size.y).is_equal_approx(77.0 / 32.0, 0.002)
	assert_float(size.z).is_equal_approx(1.0 / 32.0, 0.002)
	instance.free()


func test_sword_imported_palette_keeps_steel_brass_and_green_leather() -> void:
	var instance := _instantiate()
	var blade := _mesh_color(instance, "blade_body")
	var brass := _mesh_color(instance, "pommel_cap")
	var leather := _mesh_color(instance, "grip_middle")
	assert_bool(blade.b > blade.r and blade.g > blade.r).is_true()
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


func test_sword_front_projection_keeps_blade_on_one_centerline() -> void:
	var image := Image.load_from_file("res://reports/props_preview/sword_front.png")
	assert_object(image).is_not_null()
	var body_center := _bright_run_center(image, 100)
	var taper_center := _bright_run_center(image, 180)
	assert_float(body_center).is_equal_approx(taper_center, 0.001)


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


func _mesh_color(root_node: Node, part_name: String) -> Color:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as BaseMaterial3D
	assert_object(material).is_not_null()
	return material.albedo_color


func _bright_run_center(image: Image, y: int) -> float:
	var bright_pixels: Array[int] = []
	for x in range(30, 86):
		var color := image.get_pixel(x, y)
		if color.r + color.g + color.b > 1.8:
			bright_pixels.append(x)
	assert_bool(bright_pixels.is_empty()).is_false()
	return (float(bright_pixels.front()) + float(bright_pixels.back())) * 0.5
