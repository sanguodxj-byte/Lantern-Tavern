extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_longbow.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_longbow.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_longbow_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "longbow"')
	assert_str(source).contains("WIDTH_PX = 13.0")
	assert_str(source).contains("DEPTH_PX = 7.0")
	assert_str(source).contains("LENGTH_PX = 61.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_longbow_registry_keeps_two_hand_ranged_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "longbow":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("longbow")
		assert_str(String(entry.get("attack_type", ""))).is_equal("ranged")
		assert_str(String(entry.get("hands", ""))).is_equal("two_hand")
		assert_array(entry.get("tags", [])).contains(["bow", "longbow", "two_hand"])
		break
	assert_bool(found).is_true()


func test_longbow_glb_has_26_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"body_stave_grip_core", "grip_wrap_front", "grip_wrap_back",
		"grip_collar_lower", "grip_collar_upper", "lower_limb_root",
		"lower_limb_shoulder", "lower_limb_belly", "lower_limb_belly_front",
		"lower_limb_belly_back", "lower_limb_recurve", "lower_limb_nock",
		"upper_limb_root", "upper_limb_shoulder", "upper_limb_belly",
		"upper_limb_belly_front", "upper_limb_belly_back", "upper_limb_recurve",
		"upper_limb_nock", "nock_bridge_lower", "nock_bridge_upper",
		"string_lower", "string_serving", "string_upper", "tip_cap_lower",
		"tip_cap_upper",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("longbow missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(26)
	instance.free()


func test_longbow_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(13.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(61.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(7.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, -1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, -1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_longbow_functional_x_asymmetry_is_one_curved_stave_against_one_string() -> void:
	var instance := _instantiate()
	var grip := _find_mesh(instance, "body_stave_grip_core")
	var lower_belly := _find_mesh(instance, "lower_limb_belly")
	var upper_belly := _find_mesh(instance, "upper_limb_belly")
	var lower_nock := _find_mesh(instance, "lower_limb_nock")
	var upper_nock := _find_mesh(instance, "upper_limb_nock")
	var serving := _find_mesh(instance, "string_serving")
	assert_float(grip.position.x).is_equal_approx(0.0, 0.002)
	assert_float(lower_belly.position.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(upper_belly.position.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(lower_nock.position.x).is_equal_approx(7.0 / 32.0, 0.002)
	assert_float(upper_nock.position.x).is_equal_approx(7.0 / 32.0, 0.002)
	assert_float(serving.position.x).is_equal_approx(11.0 / 32.0, 0.002)
	assert_float(_root_box(grip).end.x).is_less(_root_box(serving).position.x)
	instance.free()


func test_longbow_first_runtime_mesh_is_a_long_central_grip() -> void:
	var instance := _instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	assert_str(String(meshes[0].name)).is_equal("body_stave_grip_core")
	var size := (meshes[0] as MeshInstance3D).get_aabb().size
	assert_float(size.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(size.y).is_equal_approx(10.0 / 32.0, 0.002)
	assert_float(size.z).is_equal_approx(5.0 / 32.0, 0.002)
	instance.free()


func test_longbow_string_is_segmented_and_face_attached_to_nocks() -> void:
	var instance := _instantiate()
	var lower := _root_box(_find_mesh(instance, "string_lower"))
	var serving := _root_box(_find_mesh(instance, "string_serving"))
	var upper := _root_box(_find_mesh(instance, "string_upper"))
	var lower_bridge := _root_box(_find_mesh(instance, "nock_bridge_lower"))
	var upper_bridge := _root_box(_find_mesh(instance, "nock_bridge_upper"))
	assert_float(lower.size.y).is_equal_approx(24.0 / 32.0, 0.002)
	assert_float(serving.size.y).is_equal_approx(8.0 / 32.0, 0.002)
	assert_float(upper.size.y).is_equal_approx(24.0 / 32.0, 0.002)
	assert_float(lower.end.y).is_equal_approx(serving.position.y, 0.002)
	assert_float(serving.end.y).is_equal_approx(upper.position.y, 0.002)
	assert_float(lower.position.y).is_equal_approx(lower_bridge.end.y, 0.002)
	assert_float(upper.end.y).is_equal_approx(upper_bridge.position.y, 0.002)
	for part_name in ["string_lower", "string_serving", "string_upper"]:
		var string_mesh := _find_mesh(instance, part_name)
		assert_float(string_mesh.position.x).is_equal_approx(11.0 / 32.0, 0.002)
		assert_float(string_mesh.position.z).is_equal_approx(0.0, 0.002)
	instance.free()


func test_longbow_imported_palette_keeps_yew_leather_horn_and_flax() -> void:
	var instance := _instantiate()
	var yew := _mesh_color(instance, "upper_limb_belly")
	var leather := _mesh_color(instance, "grip_wrap_front")
	var horn := _mesh_color(instance, "nock_bridge_upper")
	var string_color := _mesh_color(instance, "string_upper")
	assert_bool(yew.r > yew.g and yew.g > yew.b).is_true()
	assert_bool(leather.r > leather.g and leather.r - leather.b > 0.25).is_true()
	assert_bool(horn.r > horn.b and horn.g > horn.b).is_true()
	assert_bool(string_color.r > string_color.b and string_color.g > string_color.b).is_true()
	instance.free()


func test_longbow_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"longbow": "res://assets/meshes/weapons/weapons_voxel_longbow.glb"')


func test_longbow_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/longbow_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank longbow structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_longbow_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank longbow Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing longbow mesh: %s" % part_name).is_true()
	return null


func _root_box(mesh: MeshInstance3D) -> AABB:
	return mesh.transform * mesh.get_aabb()


func _mesh_color(root_node: Node, part_name: String) -> Color:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as BaseMaterial3D
	assert_object(material).is_not_null()
	return material.albedo_color
