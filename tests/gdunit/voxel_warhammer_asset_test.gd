extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_warhammer.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_warhammer.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const FUNCTIONAL_ASYMMETRY: Array[String] = [
	"hammer_neck", "hammer_block", "hammer_face", "hammer_face_plate",
	"armor_spike_root", "armor_spike_mid", "armor_spike_tip",
]


func test_warhammer_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "warhammer"')
	assert_str(source).contains("WIDTH_PX = 25.0")
	assert_str(source).contains("DEPTH_PX = 9.0")
	assert_str(source).contains("LENGTH_PX = 47.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_warhammer_registry_keeps_heavy_blunt_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "warhammer":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("two_hand")
		assert_str(String(entry.get("skill_school", ""))).is_equal("war_hammer")
		assert_array(entry.get("tags", [])).contains(["blunt", "heavy"])
		break
	assert_bool(found).is_true()


func test_warhammer_glb_has_20_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"head_socket_core", "head_cheek_front", "head_cheek_back", "head_crown",
		"hammer_neck", "hammer_block", "hammer_face", "hammer_face_plate",
		"armor_spike_root", "armor_spike_mid", "armor_spike_tip", "haft_neck",
		"haft_upper", "grip_band_upper", "grip_upper", "grip_band_center",
		"grip_lower", "grip_band_lower", "haft_butt", "pommel_cap",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("warhammer missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(20)
	instance.free()


func test_warhammer_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(25.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(47.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(9.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(
		instance, Vector3(-1.0, 1.0, 1.0), Vector3.ZERO, FUNCTIONAL_ASYMMETRY
	)).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_warhammer_asymmetry_is_limited_to_impact_face_and_armor_spike() -> void:
	var instance := _instantiate()
	var face := _find_mesh(instance, "hammer_face_plate")
	var spike := _find_mesh(instance, "armor_spike_tip")
	assert_float(face.position.x).is_less(0.0)
	assert_float(spike.position.x).is_greater(0.0)
	var face_box := face.get_aabb()
	var spike_box := spike.get_aabb()
	assert_float(face_box.size.y * face_box.size.z) \
		.is_greater(spike_box.size.y * spike_box.size.z * 10.0)
	instance.free()


func test_warhammer_imported_palette_keeps_steel_brass_wood_and_green_leather() -> void:
	var instance := _instantiate()
	var steel := _mesh_color(instance, "hammer_block")
	var brass := _mesh_color(instance, "head_cheek_front")
	var wood := _mesh_color(instance, "haft_upper")
	var leather := _mesh_color(instance, "grip_lower")
	assert_bool(steel.b > steel.r and steel.g > steel.r).is_true()
	assert_bool(brass.r > brass.g and brass.g > brass.b).is_true()
	assert_bool(wood.r > wood.g and wood.g > wood.b).is_true()
	assert_bool(leather.g > leather.r and leather.g > leather.b).is_true()
	instance.free()


func test_warhammer_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"warhammer": "res://assets/meshes/weapons/weapons_voxel_warhammer.glb"')


func test_warhammer_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/warhammer_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank warhammer structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_warhammer_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank warhammer Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing warhammer mesh: %s" % part_name).is_true()
	return null


func _mesh_color(root_node: Node, part_name: String) -> Color:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as BaseMaterial3D
	assert_object(material).is_not_null()
	return material.albedo_color
