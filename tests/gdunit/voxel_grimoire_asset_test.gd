extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_grimoire.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_grimoire.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_grimoire_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "grimoire"')
	assert_str(source).contains("WIDTH_PX = 21.0")
	assert_str(source).contains("DEPTH_PX = 12.0")
	assert_str(source).contains("LENGTH_PX = 22.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_str(source).contains("render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_grimoire_registry_keeps_off_hand_spell_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "grimoire":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("grimoire")
		assert_str(String(entry.get("attack_type", ""))).is_equal("spell")
		assert_str(String(entry.get("skill_school", ""))).is_equal("grimoire")
		assert_str(String(entry.get("hands", ""))).is_equal("off_hand")
		assert_array(entry.get("tags", [])).contains(["magic", "grimoire", "spellbook"])
		var tiers: Array = entry.get("tiers", [])
		assert_int(tiers.size()).is_equal(3)
		assert_str(String(tiers[0].get("name", ""))).is_equal("残破笔记")
		assert_str(String(tiers[1].get("name", ""))).is_equal("学者符文书")
		assert_str(String(tiers[2].get("name", ""))).is_equal("禁忌启示录")
		assert_float(float(tiers[0].get("magic_mult", 0.0))).is_equal_approx(0.02, 0.001)
		assert_float(float(tiers[1].get("magic_mult", 0.0))).is_equal_approx(0.05, 0.001)
		assert_float(float(tiers[2].get("magic_mult", 0.0))).is_equal_approx(0.10, 0.001)
		break
	assert_bool(found).is_true()


func test_grimoire_glb_has_layered_book_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"page_block", "lower_cover", "upper_cover", "spine_core", "fore_edge",
		"page_edge_lower", "page_edge_middle", "page_edge_upper",
		"spine_band_lower", "spine_band_middle", "spine_band_upper",
		"upper_cover_front_panel", "lower_cover_front_panel",
		"upper_corner_left", "upper_corner_right", "lower_corner_left", "lower_corner_right",
		"upper_rune_plate", "upper_rune_core", "upper_rune_tip",
		"lower_clasp", "lower_clasp_lock",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("grimoire missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(22)
	instance.free()


func test_grimoire_dimensions_overlap_and_face_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	# Blender X/Y/Z exports to Godot X/Z/Y, so GLB is width x height x depth.
	assert_float(bounds.size.x).is_equal_approx(21.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(22.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(12.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_grimoire_imported_materials_keep_pages_cover_metal_and_magic_roles() -> void:
	var instance := _instantiate()
	var pages := _mesh_material(instance, "page_block")
	var cover := _mesh_material(instance, "upper_cover")
	var metal := _mesh_material(instance, "upper_cover_front_panel")
	var glyph := _mesh_material(instance, "upper_rune_core")
	assert_object(pages.albedo_texture).is_not_null()
	assert_object(cover.albedo_texture).is_not_null()
	assert_float(metal.metallic).is_greater(0.5)
	assert_bool(glyph.emission_enabled).is_true()
	assert_object(glyph.emission_texture).is_not_null()
	instance.free()


func test_grimoire_embeds_pixel_uvs_color_attribute_and_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	var glb_text := bytes.get_string_from_ascii()
	assert_str(glb_text).contains("COLOR_0")
	assert_str(glb_text).contains("TEXCOORD_0")
	assert_str(glb_text).contains("grimoire_walnut_cover_albedo")
	assert_str(glb_text).contains("grimoire_magic_glyph_albedo")
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"grimoire": "res://assets/meshes/weapons/weapons_voxel_grimoire.glb"')


func test_grimoire_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/grimoire_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank grimoire structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_grimoire_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank grimoire Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing grimoire mesh: %s" % part_name).is_true()
	return null


func _mesh_material(root_node: Node, part_name: String) -> StandardMaterial3D:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as StandardMaterial3D
	assert_object(material).is_not_null()
	return material
