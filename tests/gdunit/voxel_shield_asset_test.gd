extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_shield.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_shield.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")
const DEPTH_ASYMMETRY: Array[String] = [
	"front_boss_base", "front_boss_cap", "front_boss_ring_top", "front_boss_ring_bottom",
	"front_boss_ring_left", "front_boss_ring_right", "back_grip_mount_upper",
	"back_grip_mount_lower", "back_grip_bar",
]


func test_shield_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "shield"')
	assert_str(source).contains("WIDTH_PX = 25.0")
	assert_str(source).contains("DEPTH_PX = 9.0")
	assert_str(source).contains("LENGTH_PX = 29.0")
	for material_tier in ["wood", "iron", "steel", "meteoric", "mithril", "adamantite"]:
		assert_str(source).contains('"%s"' % material_tier)
	assert_str(source).contains("make_pixel_material")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_shield_registry_keeps_off_hand_defense_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "shield":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("category", ""))).is_equal("shields")
		assert_str(String(entry.get("item_tag", ""))).is_equal("shield")
		assert_str(String(entry.get("hands", ""))).is_equal("off_hand")
		assert_array(entry.get("tags", [])).contains(["off_hand", "defense", "one_hand_shield"])
		var tiers: Array = entry.get("tiers", [])
		assert_array(tiers.map(func(tier: Dictionary) -> int: return int(tier.get("phys_def", 0)))) \
			.is_equal([1, 3, 8])
		assert_array(tiers.map(func(tier: Dictionary) -> int: return int(tier.get("block_value", 0)))) \
			.is_equal([5, 15, 35])
		break
	assert_bool(found).is_true()


func test_shield_glb_has_57_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"body_panel_upper", "body_panel_mid", "body_panel_lower", "body_top_center",
		"body_top_shoulder_left", "body_top_shoulder_right", "body_top_cap",
		"body_bottom_center", "body_bottom_shoulder_left", "body_bottom_shoulder_right",
		"body_bottom_tip", "body_side_upper_left", "body_side_upper_right",
		"body_side_upper_tip_left", "body_side_upper_tip_right", "body_side_mid_left",
		"body_side_mid_right", "body_side_mid_tip_left", "body_side_mid_tip_right",
		"body_side_lower_left", "body_side_lower_right", "body_side_lower_tip_left",
		"body_side_lower_tip_right", "front_panel_upper_left", "front_panel_upper_center",
		"front_panel_upper_right", "front_panel_mid_left", "front_panel_mid_center",
		"front_panel_mid_right", "front_panel_lower_left", "front_panel_lower_center",
		"front_panel_lower_right", "front_rim_upper_left", "front_rim_upper_right",
		"front_rim_mid_left", "front_rim_mid_right", "front_rim_lower_left",
		"front_rim_lower_right", "front_rim_top_center", "front_rim_top_shoulder_left",
		"front_rim_top_shoulder_right", "front_rim_bottom_center",
		"front_rim_bottom_shoulder_left", "front_rim_bottom_shoulder_right",
		"front_boss_base", "front_boss_cap", "front_boss_ring_top",
		"front_boss_ring_bottom", "front_boss_ring_left", "front_boss_ring_right",
		"front_rivet_upper_left", "front_rivet_upper_right", "front_rivet_lower_left",
		"front_rivet_lower_right", "back_grip_mount_upper", "back_grip_mount_lower",
		"back_grip_bar",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("shield missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(57)
	instance.free()


func test_shield_dimensions_left_right_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(25.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(29.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(9.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_shield_has_stepped_kite_silhouette_not_a_flat_rectangle() -> void:
	var instance := _instantiate()
	var upper := _find_mesh(instance, "body_panel_upper").get_aabb().size
	var middle := _find_mesh(instance, "body_panel_mid").get_aabb().size
	var lower := _find_mesh(instance, "body_panel_lower").get_aabb().size
	var top := _find_mesh(instance, "body_top_cap").get_aabb().size
	var tip := _find_mesh(instance, "body_bottom_tip").get_aabb().size
	assert_float(upper.x).is_equal_approx(19.0 / 32.0, 0.002)
	assert_float(middle.x).is_equal_approx(21.0 / 32.0, 0.002)
	assert_float(lower.x).is_equal_approx(15.0 / 32.0, 0.002)
	assert_float(top.x).is_equal_approx(5.0 / 32.0, 0.002)
	assert_float(tip.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_bool(middle.x > upper.x and upper.x > lower.x and lower.x > top.x).is_true()
	instance.free()


func test_shield_boss_and_rear_grip_have_functional_depth_layers() -> void:
	var instance := _instantiate()
	var boss := _root_box(_find_mesh(instance, "front_boss_cap"))
	var grip := _root_box(_find_mesh(instance, "back_grip_bar"))
	assert_float(boss.position.z).is_equal_approx(-4.5 / 32.0, 0.002)
	assert_float(grip.position.z).is_equal_approx(3.5 / 32.0, 0.002)
	assert_float(grip.size.y).is_equal_approx(8.0 / 32.0, 0.002)
	assert_float(grip.size.z).is_equal_approx(1.0 / 32.0, 0.002)
	assert_bool(DEPTH_ASYMMETRY.has("front_boss_cap")).is_true()
	assert_bool(DEPTH_ASYMMETRY.has("back_grip_bar")).is_true()
	instance.free()


func test_shield_imported_palette_keeps_textured_wood_and_canonical_metal_variants() -> void:
	var instance := _instantiate()
	var upper := _mesh_material(instance, "body_panel_upper")
	var mid := _mesh_material(instance, "body_panel_mid")
	var endgrain := _mesh_material(instance, "body_top_cap")
	var grip := _mesh_material(instance, "back_grip_bar")
	var iron := _mesh_material(instance, "front_boss_base")
	var steel := _mesh_material(instance, "front_rim_top_center")
	var meteoric := _mesh_material(instance, "front_boss_ring_top")
	var mithril := _mesh_material(instance, "front_boss_cap")
	var adamantite := _mesh_material(instance, "front_boss_ring_left")
	assert_object(upper.albedo_texture).is_not_null()
	assert_object(mid.albedo_texture).is_not_null()
	assert_object(endgrain.albedo_texture).is_not_null()
	assert_object(grip.albedo_texture).is_not_null()
	for material in [iron, steel, meteoric, mithril, adamantite]:
		assert_float(material.metallic).is_greater(0.5)
	assert_bool(meteoric.albedo_color != mithril.albedo_color).is_true()
	assert_bool(mithril.albedo_color != adamantite.albedo_color).is_true()
	instance.free()


func test_shield_embeds_distinct_nonblack_pixel_textures() -> void:
	var instance := _instantiate()
	var walnut := _mesh_material(instance, "body_panel_upper")
	var shadow := _mesh_material(instance, "body_panel_mid")
	var endgrain := _mesh_material(instance, "body_top_cap")
	var grip := _mesh_material(instance, "back_grip_bar")
	for material in [walnut, shadow, endgrain, grip]:
		assert_object(material.albedo_texture).is_not_null()
		assert_int(material.albedo_texture.get_width()).is_equal(8)
		assert_int(material.albedo_texture.get_height()).is_equal(8)
		assert_float(_texture_max_channel(material)).is_greater(0.20)
		assert_float(_texture_color_range(material)).is_greater(0.05)
	assert_bool(walnut.albedo_texture != shadow.albedo_texture).is_true()
	assert_bool(shadow.albedo_texture != endgrain.albedo_texture).is_true()
	var glb_text := _glb_ascii()
	assert_str(glb_text).contains("shield_material_wood_grain_albedo")
	assert_str(glb_text).contains("shield_material_wood_shadow_albedo")
	assert_str(glb_text).contains("shield_material_wood_endgrain_albedo")
	assert_str(glb_text).contains("shield_material_wood_leather_grip_albedo")
	instance.free()


func test_shield_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"shield": "res://assets/meshes/weapons/weapons_voxel_shield.glb"')


func test_shield_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/shield_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank shield structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_shield_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank shield Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing shield mesh: %s" % part_name).is_true()
	return null


func _root_box(mesh: MeshInstance3D) -> AABB:
	return mesh.transform * mesh.get_aabb()


func _mesh_material(root_node: Node, part_name: String) -> StandardMaterial3D:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as StandardMaterial3D
	assert_object(material).is_not_null()
	return material


func _mesh_color(root_node: Node, part_name: String) -> Color:
	return _mesh_material(root_node, part_name).albedo_color


func _glb_ascii() -> String:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	return bytes.get_string_from_ascii()


func _texture_max_channel(material: StandardMaterial3D) -> float:
	var image := material.albedo_texture.get_image()
	assert_object(image).is_not_null()
	var maximum := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			maximum = maxf(maximum, maxf(color.r, maxf(color.g, color.b)))
	return maximum


func _texture_color_range(material: StandardMaterial3D) -> float:
	var image := material.albedo_texture.get_image()
	assert_object(image).is_not_null()
	var minimum := 1.0
	var maximum := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			var luma := (color.r + color.g + color.b) / 3.0
			minimum = minf(minimum, luma)
			maximum = maxf(maximum, luma)
	return maximum - minimum
