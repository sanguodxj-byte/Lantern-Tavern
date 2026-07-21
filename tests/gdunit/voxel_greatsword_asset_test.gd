extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_greatsword.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_greatsword.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_greatsword_generator_is_fixed_identity_and_guarded() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "greatsword"')
	assert_str(source).contains("WIDTH_PX = 25.0")
	assert_str(source).contains("DEPTH_PX = 7.0")
	assert_str(source).contains("LENGTH_PX = 61.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_greatsword_registry_keeps_two_hand_heavy_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "greatsword":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("two_hand")
		assert_array(entry.get("tags", [])).contains(["two_hand_sword", "heavy"])
		break
	assert_bool(found).is_true()


func test_greatsword_glb_has_35_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"blade_ricasso_center", "blade_forte_fuller", "blade_forte_left",
		"blade_forte_right", "blade_tip", "guard_center", "guard_tip_left",
		"guard_tip_right", "grip_fore", "grip_middle", "grip_rear",
		"pommel_shoulders_center", "pommel_cap_left", "pommel_cap_right",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("greatsword missing part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(35)
	instance.free()


func test_greatsword_dimensions_symmetry_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(25.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(61.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(7.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_greatsword_imported_palette_keeps_steel_brass_and_leather() -> void:
	var instance := _instantiate()
	var steel := _mesh_color(instance, "blade_forte_left")
	var brass := _mesh_color(instance, "grip_collar")
	var leather := _mesh_color(instance, "grip_fore")
	assert_bool(steel.b > steel.r and steel.g > steel.r).is_true()
	assert_bool(brass.r > brass.g and brass.g > brass.b).is_true()
	assert_bool(leather.r > leather.g and leather.g > leather.b and leather.r - leather.b > 0.20) \
		.override_failure_message("imported greatsword leather hue lost: %s" % leather).is_true()
	instance.free()


func test_greatsword_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"greatsword": "res://assets/meshes/weapons/weapons_voxel_greatsword.glb"')


func test_greatsword_verification_images_are_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/greatsword_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank greatsword structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_greatsword_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank greatsword Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("greatsword missing palette part: %s" % part_name).is_true()
	return Color.WHITE
