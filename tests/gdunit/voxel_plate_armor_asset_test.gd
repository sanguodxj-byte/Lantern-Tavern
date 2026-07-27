extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_plate_armor.py"
const GLB_PATH := "res://assets/meshes/armor/armor_voxel_plate_armor.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_plate_armor_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "plate_armor"')
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_str(source).contains("make_pixel_material")
	assert_str(source).contains("steel_shadow")
	assert_str(source).contains("steel_base")
	assert_str(source).contains("steel_highlight")
	assert_str(source).contains("meteoric_trim")
	assert_str(source).contains("leather_dark")
	assert_bool(source.contains("BUILDERS")).is_false()
	assert_bool(source.contains("--batch")).is_false()
	assert_bool(source.contains("all_models")).is_false()


func test_plate_armor_registry_keeps_heavy_body_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("armor", []):
		if String(entry.get("id", "")) != "plate_armor":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("category", ""))).is_equal("armor_heavy")
		assert_str(String(entry.get("item_tag", ""))).is_equal("armor")
		assert_str(String(entry.get("armor_slot", ""))).is_equal("body")
		assert_array(entry.get("tags", [])).contains(["armor", "plate", "heavy", "body"])
		var tiers: Array = entry.get("tiers", [])
		assert_int(int(tiers[0].get("phys_def", 0))).is_equal(10)
		assert_float(float(tiers[0].get("move_speed_mult", 1.0))).is_equal_approx(0.88, 0.001)
		assert_int(int(tiers[0].get("condition", 0))).is_equal(1520)
		var perks: Array = entry.get("proficiency_perks", [])
		assert_int(perks.size()).is_equal(2)
		break
	assert_bool(found).is_true()


func test_plate_armor_glb_has_39_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"neck_guard", "shoulder_band", "chest_band", "waist_band",
		"fauld_upper", "fauld_lower",
		"breast_upper", "breast_mid", "breast_upper_outer", "breast_mid_outer",
		"belt_front", "fauld_front_upper", "fauld_front_lower", "fauld_lower_front",
		"back_shoulder", "back_upper", "back_shoulder_outer", "back_upper_outer",
		"belt_back", "fauld_back_upper", "fauld_back_lower", "fauld_lower_back",
		"pauldron_base_left", "pauldron_base_right",
		"pauldron_cap_left", "pauldron_cap_right",
		"pauldron_ridge_left", "pauldron_ridge_right",
		"side_trim_left", "side_trim_right",
		"neck_trim", "emblem", "seam",
		"rivet_breast_upper_left", "rivet_breast_upper_right",
		"rivet_breast_mid_left", "rivet_breast_mid_right",
		"rivet_belt_left", "rivet_belt_right",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("plate armor missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(39)
	instance.free()


func test_plate_armor_dimensions_left_right_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(30.0 / 32.0, 0.003)
	assert_float(bounds.size.y).is_equal_approx(32.0 / 32.0, 0.003)
	assert_float(bounds.size.z).is_equal_approx(19.0 / 32.0, 0.003)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_plate_armor_has_stepped_tapered_cuirass_silhouette() -> void:
	var instance := _instantiate()
	var shoulder := _find_mesh(instance, "shoulder_band").get_aabb().size
	var chest := _find_mesh(instance, "chest_band").get_aabb().size
	var waist := _find_mesh(instance, "waist_band").get_aabb().size
	var fauld_upper := _find_mesh(instance, "fauld_upper").get_aabb().size
	var fauld_lower := _find_mesh(instance, "fauld_lower").get_aabb().size
	assert_float(shoulder.x).is_equal_approx(22.0 / 32.0, 0.003)
	assert_float(chest.x).is_equal_approx(20.0 / 32.0, 0.003)
	assert_float(waist.x).is_equal_approx(16.0 / 32.0, 0.003)
	assert_float(fauld_upper.x).is_equal_approx(14.0 / 32.0, 0.003)
	assert_float(fauld_lower.x).is_equal_approx(12.0 / 32.0, 0.003)
	assert_bool(shoulder.x > chest.x and chest.x > waist.x and waist.x > fauld_upper.x and fauld_upper.x > fauld_lower.x).is_true()
	instance.free()


func test_plate_armor_pauldrons_have_stepped_dome_volume() -> void:
	var instance := _instantiate()
	var base := _root_box(_find_mesh(instance, "pauldron_base_left"))
	var cap := _root_box(_find_mesh(instance, "pauldron_cap_left"))
	var ridge := _root_box(_find_mesh(instance, "pauldron_ridge_left"))
	assert_float(base.size.x).is_equal_approx(4.0 / 32.0, 0.003)
	assert_float(base.size.z).is_equal_approx(10.0 / 32.0, 0.003)
	assert_float(cap.size.x).is_equal_approx(4.0 / 32.0, 0.003)
	assert_float(cap.size.z).is_equal_approx(6.0 / 32.0, 0.003)
	assert_float(ridge.size.x).is_equal_approx(2.0 / 32.0, 0.003)
	assert_bool(cap.size.z < base.size.z).is_true()
	assert_bool(ridge.size.z < cap.size.z).is_true()
	instance.free()


func test_plate_armor_breastplate_has_stepped_depth_protrusion() -> void:
	var instance := _instantiate()
	var breast_mid := _root_box(_find_mesh(instance, "breast_mid"))
	var breast_mid_outer := _root_box(_find_mesh(instance, "breast_mid_outer"))
	var back_upper := _root_box(_find_mesh(instance, "back_upper"))
	var back_upper_outer := _root_box(_find_mesh(instance, "back_upper_outer"))
	assert_float(breast_mid.position.z).is_less(-4.0 / 32.0)
	assert_float(breast_mid_outer.position.z).is_less(breast_mid.position.z)
	assert_float(back_upper.position.z).is_greater(4.0 / 32.0)
	assert_float(back_upper_outer.position.z).is_greater(back_upper.position.z)
	instance.free()


func test_plate_armor_steel_color_ramp_has_three_distinct_tones() -> void:
	var instance := _instantiate()
	var shadow := _mesh_material(instance, "neck_guard")
	var base := _mesh_material(instance, "shoulder_band")
	var highlight := _mesh_material(instance, "breast_upper")
	assert_float(shadow.metallic).is_greater(0.5)
	assert_float(base.metallic).is_greater(0.5)
	assert_float(highlight.metallic).is_greater(0.5)
	var shadow_luma := (shadow.albedo_color.r + shadow.albedo_color.g + shadow.albedo_color.b) / 3.0
	var base_luma := (base.albedo_color.r + base.albedo_color.g + base.albedo_color.b) / 3.0
	var highlight_luma := (highlight.albedo_color.r + highlight.albedo_color.g + highlight.albedo_color.b) / 3.0
	assert_bool(shadow_luma < base_luma).is_true()
	assert_bool(base_luma < highlight_luma).is_true()
	instance.free()


func test_plate_armor_leather_belt_has_pixel_texture() -> void:
	var instance := _instantiate()
	var belt := _mesh_material(instance, "belt_front")
	assert_object(belt.albedo_texture).is_not_null()
	assert_int(belt.albedo_texture.get_width()).is_equal(8)
	assert_int(belt.albedo_texture.get_height()).is_equal(8)
	instance.free()


func test_plate_armor_exports_color_attribute_and_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"plate_armor": "res://assets/meshes/armor/armor_voxel_plate_armor.glb"')


func test_plate_armor_blender_renders_are_readable_and_nonblank() -> void:
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_plate_armor_render_%s.png" % view_name
		)
		assert_bool(rendered["exists"]) \
			.override_failure_message("missing plate armor Blender render: %s" % view_name).is_true()
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank plate armor Blender render: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing plate armor mesh: %s" % part_name).is_true()
	return null


func _root_box(mesh: MeshInstance3D) -> AABB:
	return mesh.transform * mesh.get_aabb()


func _mesh_material(root_node: Node, part_name: String) -> StandardMaterial3D:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as StandardMaterial3D
	assert_object(material).is_not_null()
	return material
