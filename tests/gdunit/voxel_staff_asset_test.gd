extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_staff.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_staff.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_staff_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "staff"')
	assert_str(source).contains("WIDTH_PX = 15.0")
	assert_str(source).contains("DEPTH_PX = 9.0")
	assert_str(source).contains("LENGTH_PX = 49.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_staff_registry_keeps_two_hand_spell_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "staff":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("wand")
		assert_str(String(entry.get("attack_type", ""))).is_equal("spell")
		assert_str(String(entry.get("skill_school", ""))).is_equal("enchant_wand")
		assert_str(String(entry.get("hands", ""))).is_equal("two_hand")
		assert_array(entry.get("tags", [])).contains(["magic", "wand", "enchant_wand"])
		var stats: Dictionary = entry.get("stats", {})
		assert_float(float(stats.get("throw_rotation_speed", -1.0))).is_equal_approx(0.0, 0.01)
		assert_float(float(stats.get("throw_movement_speed", -1.0))).is_equal_approx(0.0, 0.01)
		var tiers: Array = entry.get("tiers", [])
		assert_float(float(tiers[0].get("magic_mult", 0.0))).is_equal_approx(0.05, 0.001)
		assert_float(float(tiers[1].get("magic_mult", 0.0))).is_equal_approx(0.10, 0.001)
		assert_float(float(tiers[2].get("magic_mult", 0.0))).is_equal_approx(0.15, 0.001)
		break
	assert_bool(found).is_true()


func test_staff_glb_has_28_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"a_staff_spine_core", "head_socket", "core_pedestal", "magic_core",
		"core_crown", "rune_arm_inner_left", "rune_arm_inner_right",
		"rune_wing_left", "rune_wing_right", "rune_arm_front", "rune_arm_back",
		"rune_collar_left", "rune_collar_right", "rune_collar_front",
		"rune_collar_back", "grip_wrap_upper_left", "grip_wrap_upper_right",
		"grip_wrap_upper_front", "grip_wrap_upper_back", "grip_band_left",
		"grip_band_right", "grip_band_front", "grip_band_back",
		"grip_wrap_lower_left", "grip_wrap_lower_right", "grip_wrap_lower_front",
		"grip_wrap_lower_back", "pommel_cap",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("staff missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(28)
	instance.free()


func test_staff_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(15.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(49.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(9.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, -1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_staff_first_runtime_mesh_is_the_long_spine() -> void:
	var instance := _instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	assert_str(String(meshes[0].name)).is_equal("a_staff_spine_core")
	var size := (meshes[0] as MeshInstance3D).get_aabb().size
	assert_float(size.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(size.y).is_equal_approx(35.0 / 32.0, 0.002)
	assert_float(size.z).is_equal_approx(3.0 / 32.0, 0.002)
	instance.free()


func test_staff_head_has_a_three_axis_rune_core_identity() -> void:
	var instance := _instantiate()
	var core := _find_mesh(instance, "magic_core")
	var left := _find_mesh(instance, "rune_wing_left")
	var right := _find_mesh(instance, "rune_wing_right")
	var front := _find_mesh(instance, "rune_arm_front")
	var back := _find_mesh(instance, "rune_arm_back")
	assert_float(core.get_aabb().size.x).is_equal_approx(5.0 / 32.0, 0.002)
	assert_float(left.position.x).is_equal_approx(-6.5 / 32.0, 0.002)
	assert_float(right.position.x).is_equal_approx(6.5 / 32.0, 0.002)
	assert_float(absf(front.position.z)).is_equal_approx(3.5 / 32.0, 0.002)
	assert_float(absf(back.position.z)).is_equal_approx(3.5 / 32.0, 0.002)
	instance.free()


func test_staff_imported_palette_keeps_oak_leather_brass_iron_and_crystal() -> void:
	var instance := _instantiate()
	var wood := _mesh_material(instance, "a_staff_spine_core")
	var leather := _mesh_material(instance, "grip_wrap_lower_front")
	var brass := _mesh_color(instance, "rune_wing_left")
	var iron := _mesh_color(instance, "head_socket")
	var crystal := _mesh_material(instance, "magic_core")
	assert_object(wood.albedo_texture).is_not_null()
	assert_object(leather.albedo_texture).is_not_null()
	assert_bool(brass.r > brass.g and brass.g > brass.b).is_true()
	assert_bool(iron.b >= iron.r and iron.g >= iron.r).is_true()
	assert_object(crystal.albedo_texture).is_not_null()
	assert_bool(crystal.emission_enabled).is_true()
	instance.free()


func test_staff_embeds_nearest_pixel_textures_and_emissive_core() -> void:
	var instance := _instantiate()
	var wood := _mesh_material(instance, "a_staff_spine_core")
	var leather := _mesh_material(instance, "grip_wrap_upper_front")
	var core := _mesh_material(instance, "magic_core")
	var crown := _mesh_material(instance, "core_crown")
	for material in [wood, leather, core, crown]:
		assert_object(material.albedo_texture).is_not_null()
		assert_int(material.albedo_texture.get_width()).is_equal(8)
		assert_int(material.albedo_texture.get_height()).is_equal(8)
		assert_float(_texture_max_channel(material)).is_greater(0.20)
		assert_float(_texture_color_range(material)).is_greater(0.05)
	assert_bool(core.emission_enabled).is_true()
	assert_bool(crown.emission_enabled).is_true()
	assert_object(core.emission_texture).is_not_null()
	assert_object(crown.emission_texture).is_not_null()
	assert_float(core.emission_energy_multiplier).is_greater(1.0)
	assert_float(crown.emission_energy_multiplier).is_greater(core.emission_energy_multiplier)
	var glb_text := _glb_ascii()
	assert_str(glb_text).contains("TEXCOORD_0")
	assert_str(glb_text).contains("staff_oak_grain_albedo")
	assert_str(glb_text).contains("staff_magic_core_runes_albedo")
	instance.free()


func test_staff_spine_uses_fixed_voxel_scale_uvs_instead_of_stretched_cube_uvs() -> void:
	var instance := _instantiate()
	var spine := _find_mesh(instance, "a_staff_spine_core")
	var arrays := spine.mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_int(uvs.size()).is_greater(0)
	var min_uv := Vector2(INF, INF)
	var max_uv := Vector2(-INF, -INF)
	for uv in uvs:
		min_uv = min_uv.min(uv)
		max_uv = max_uv.max(uv)
	var span := max_uv - min_uv
	assert_float(maxf(span.x, span.y)).is_greater(4.0)
	instance.free()


func test_staff_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"staff": "res://assets/meshes/weapons/weapons_voxel_staff.glb"')


func test_staff_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/staff_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank staff structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_staff_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank staff Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing staff mesh: %s" % part_name).is_true()
	return null


func _mesh_color(root_node: Node, part_name: String) -> Color:
	return _mesh_material(root_node, part_name).albedo_color


func _mesh_material(root_node: Node, part_name: String) -> StandardMaterial3D:
	var mesh := _find_mesh(root_node, part_name)
	var material := mesh.get_active_material(0) as StandardMaterial3D
	assert_object(material).is_not_null()
	return material


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
