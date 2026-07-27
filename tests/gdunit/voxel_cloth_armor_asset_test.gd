extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_cloth_armor.py"
const GLB_PATH := "res://assets/meshes/armor/armor_voxel_cloth_armor.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_cloth_armor_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "cloth_armor"')
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_str(source).contains("make_pixel_material")
	assert_str(source).contains("cloth_shadow")
	assert_str(source).contains("cloth_base")
	assert_str(source).contains("cloth_highlight")
	assert_str(source).contains("cloth_texture")
	assert_str(source).contains("stitching")
	assert_str(source).contains("rope_belt")
	assert_bool(source.contains("BUILDERS")).is_false()
	assert_bool(source.contains("--batch")).is_false()
	assert_bool(source.contains("all_models")).is_false()


func test_cloth_armor_registry_keeps_light_body_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("armor", []):
		if String(entry.get("id", "")) != "cloth_armor":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("category", ""))).is_equal("armor_light")
		assert_str(String(entry.get("item_tag", ""))).is_equal("armor")
		assert_str(String(entry.get("armor_slot", ""))).is_equal("body")
		assert_array(entry.get("tags", [])).contains(["armor", "cloth", "light", "body"])
		var tiers: Array = entry.get("tiers", [])
		assert_int(int(tiers[0].get("phys_def", 0))).is_equal(1)
		assert_float(float(tiers[0].get("move_speed_mult", 1.0))).is_equal_approx(1.0, 0.001)
		assert_int(int(tiers[0].get("condition", 0))).is_equal(560)
		break
	assert_bool(found).is_true()


func test_cloth_armor_glb_has_23_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"body_neck", "body_chest", "body_waist", "body_skirt",
		"stitch_front_chest", "stitch_front_waist", "stitch_front_skirt",
		"stitch_back_chest", "stitch_back_waist", "stitch_back_skirt",
		"stitch_front_vertical", "stitch_back_vertical",
		"shoulder_seam_left", "shoulder_seam_right",
		"side_panel_left", "side_panel_right",
		"belt_front", "belt_back",
		"belt_knot",
		"hem_front", "hem_back",
		"neck_trim_front", "neck_trim_back",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("cloth armor missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(23)
	instance.free()


func test_cloth_armor_dimensions_left_right_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	# Blender envelope 20x12x22 (X x Y x Z); Godot Yup swaps Y/Z -> 20x22x12.
	assert_float(bounds.size.x).is_equal_approx(20.0 / 32.0, 0.003)
	assert_float(bounds.size.y).is_equal_approx(22.0 / 32.0, 0.003)
	assert_float(bounds.size.z).is_equal_approx(12.0 / 32.0, 0.003)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_cloth_armor_has_tapered_gambeson_silhouette() -> void:
	var instance := _instantiate()
	var chest := _find_mesh(instance, "body_chest").get_aabb().size
	var waist := _find_mesh(instance, "body_waist").get_aabb().size
	var skirt := _find_mesh(instance, "body_skirt").get_aabb().size
	assert_float(chest.x).is_equal_approx(16.0 / 32.0, 0.003)
	assert_float(waist.x).is_equal_approx(14.0 / 32.0, 0.003)
	assert_float(skirt.x).is_equal_approx(12.0 / 32.0, 0.003)
	assert_bool(chest.x > waist.x and waist.x > skirt.x).is_true()
	instance.free()


func test_cloth_armor_quilt_lines_have_horizontal_stitching() -> void:
	var instance := _instantiate()
	var stitch_chest := _root_box(_find_mesh(instance, "stitch_front_chest"))
	var stitch_waist := _root_box(_find_mesh(instance, "stitch_front_waist"))
	var stitch_skirt := _root_box(_find_mesh(instance, "stitch_front_skirt"))
	assert_float(stitch_chest.size.x).is_equal_approx(14.0 / 32.0, 0.003)
	assert_float(stitch_waist.size.x).is_equal_approx(12.0 / 32.0, 0.003)
	assert_float(stitch_skirt.size.x).is_equal_approx(10.0 / 32.0, 0.003)
	assert_bool(stitch_chest.size.x > stitch_waist.size.x).is_true()
	assert_bool(stitch_waist.size.x > stitch_skirt.size.x).is_true()
	instance.free()


func test_cloth_armor_color_ramp_has_three_distinct_tones() -> void:
	var instance := _instantiate()
	var shadow := _mesh_material(instance, "body_neck")
	var base := _mesh_material(instance, "neck_trim_front")
	var highlight := _mesh_material(instance, "shoulder_seam_left")
	var shadow_luma := (shadow.albedo_color.r + shadow.albedo_color.g + shadow.albedo_color.b) / 3.0
	var base_luma := (base.albedo_color.r + base.albedo_color.g + base.albedo_color.b) / 3.0
	var highlight_luma := (highlight.albedo_color.r + highlight.albedo_color.g + highlight.albedo_color.b) / 3.0
	assert_bool(shadow_luma < base_luma).is_true()
	assert_bool(base_luma < highlight_luma).is_true()
	instance.free()


func test_cloth_armor_body_has_pixel_texture() -> void:
	var instance := _instantiate()
	var body := _mesh_material(instance, "body_chest")
	assert_object(body.albedo_texture).is_not_null()
	assert_int(body.albedo_texture.get_width()).is_equal(8)
	assert_int(body.albedo_texture.get_height()).is_equal(8)
	instance.free()


func test_cloth_armor_exports_color_attribute_and_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"cloth_armor": "res://assets/meshes/armor/armor_voxel_cloth_armor.glb"')


func test_cloth_armor_blender_renders_are_readable_and_nonblank() -> void:
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_cloth_armor_render_%s.png" % view_name
		)
		assert_bool(rendered["exists"]) \
			.override_failure_message("missing cloth armor Blender render: %s" % view_name).is_true()
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank cloth armor Blender render: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing cloth armor mesh: %s" % part_name).is_true()
	return null


func _root_box(mesh: MeshInstance3D) -> AABB:
	return mesh.transform * mesh.get_aabb()


func _mesh_material(root_node: Node, part_name: String) -> StandardMaterial3D:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as StandardMaterial3D
	assert_object(material).is_not_null()
	return material
