extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_dagger.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_dagger.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_dagger_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "dagger"')
	assert_str(source).contains("WIDTH_PX = 11.0")
	assert_str(source).contains("DEPTH_PX = 5.0")
	assert_str(source).contains("LENGTH_PX = 23.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_dagger_registry_keeps_dual_wield_and_throwing_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "dagger":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("one_hand_melee")
		assert_str(String(entry.get("attack_type", ""))).is_equal("melee")
		assert_str(String(entry.get("hands", ""))).is_equal("one_hand")
		assert_array(entry.get("tags", [])).contains(["dagger", "blade", "dual_wield"])
		assert_array(entry.get("combat_styles", [])).contains(["one_hand", "one_hand_shield", "dual_wield"])
		var stats: Dictionary = entry.get("stats", {})
		assert_float(float(stats.get("throw_rotation_speed", 0.0))).is_equal_approx(60.0, 0.01)
		assert_float(float(stats.get("throw_movement_speed", 0.0))).is_equal_approx(15.0, 0.01)
		break
	assert_bool(found).is_true()


func test_dagger_glb_has_21_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"blade_anchor_core", "blade_ricasso_edge_left", "blade_ricasso_edge_right",
		"blade_forte_edge_left", "blade_forte_edge_right", "blade_mid_edge_left",
		"blade_mid_edge_right", "blade_taper", "blade_tip", "venom_ridge_front",
		"venom_ridge_back", "guard_center", "guard_arm_left", "guard_arm_right",
		"guard_tip_left", "guard_tip_right", "grip_collar", "grip_upper",
		"grip_band", "grip_lower", "pommel_cap",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("dagger missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(21)
	instance.free()


func test_dagger_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(11.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(23.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(5.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_dagger_first_runtime_mesh_is_the_long_blade_core() -> void:
	var instance := _instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	assert_str(String(meshes[0].name)).is_equal("blade_anchor_core")
	var size := (meshes[0] as MeshInstance3D).get_aabb().size
	assert_float(size.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(size.y).is_equal_approx(12.0 / 32.0, 0.002)
	assert_float(size.z).is_equal_approx(3.0 / 32.0, 0.002)
	instance.free()


func test_dagger_leaf_profile_keeps_forte_mid_taper_and_tip_steps() -> void:
	var instance := _instantiate()
	var forte := _find_mesh(instance, "blade_forte_edge_left").get_aabb().size
	var mid := _find_mesh(instance, "blade_mid_edge_left").get_aabb().size
	var taper := _find_mesh(instance, "blade_taper").get_aabb().size
	var tip := _find_mesh(instance, "blade_tip").get_aabb().size
	assert_float(forte.x).is_equal_approx(2.0 / 32.0, 0.002)
	assert_float(mid.x).is_equal_approx(1.0 / 32.0, 0.002)
	assert_float(taper.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(tip.x).is_equal_approx(1.0 / 32.0, 0.002)
	instance.free()


func test_dagger_imported_palette_keeps_steel_venom_bronze_and_wine_leather() -> void:
	var instance := _instantiate()
	var steel := _mesh_color(instance, "blade_mid_edge_left")
	var venom := _mesh_color(instance, "venom_ridge_front")
	var bronze := _mesh_color(instance, "guard_center")
	var leather := _mesh_color(instance, "grip_lower")
	assert_bool(steel.b > steel.r and steel.g > steel.r).is_true()
	assert_bool(venom.g > venom.r and venom.g > venom.b).is_true()
	assert_bool(bronze.r > bronze.g and bronze.g > bronze.b).is_true()
	assert_bool(leather.r > leather.g and leather.r - leather.b > 0.20).is_true()
	instance.free()


func test_dagger_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"dagger": "res://assets/meshes/weapons/weapons_voxel_dagger.glb"')


func test_dagger_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/dagger_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank dagger structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_dagger_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank dagger Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing dagger mesh: %s" % part_name).is_true()
	return null


func _mesh_color(root_node: Node, part_name: String) -> Color:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as BaseMaterial3D
	assert_object(material).is_not_null()
	return material.albedo_color
