extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_crossbow.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_crossbow.glb"
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")


func test_crossbow_generator_is_fixed_identity_guarded_and_pixel_authored() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "crossbow"')
	assert_str(source).contains("WIDTH_PX = 31.0")
	assert_str(source).contains("DEPTH_PX = 9.0")
	assert_str(source).contains("LENGTH_PX = 33.0")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_bool(source.contains("BUILDERS")).is_false()


func test_crossbow_registry_keeps_light_ranged_identity() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "crossbow":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		assert_str(String(entry.get("weapon_class", ""))).is_equal("crossbow")
		assert_str(String(entry.get("attack_type", ""))).is_equal("ranged")
		assert_str(String(entry.get("skill_school", ""))).is_equal("light_crossbow")
		assert_str(String(entry.get("hands", ""))).is_equal("two_hand")
		assert_array(entry.get("tags", [])).contains(["crossbow", "light_crossbow", "two_hand"])
		var stats: Dictionary = entry.get("stats", {})
		assert_float(float(stats.get("throw_rotation_speed", -1.0))).is_equal_approx(0.0, 0.01)
		assert_float(float(stats.get("throw_movement_speed", -1.0))).is_equal_approx(0.0, 0.01)
		break
	assert_bool(found).is_true()


func test_crossbow_glb_has_30_authored_semantic_parts() -> void:
	var instance := _instantiate()
	var names := _collect_names(instance)
	for part_name in [
		"body_stock_core", "stock_lock_housing", "stock_grip_neck", "stock_rear",
		"stock_butt", "stock_cheek_rest", "forestock_nose", "bow_riser",
		"limb_inner_left", "limb_inner_right", "limb_mid_left", "limb_mid_right",
		"limb_tip_left", "limb_tip_right", "bowstring_outer_left",
		"bowstring_outer_right", "bowstring_elbow_left", "bowstring_elbow_right",
		"bowstring_inner_left", "bowstring_inner_right", "bolt_rail_upper",
		"cocking_latch", "lock_plate_left", "lock_plate_right",
		"trigger_pin_left", "trigger_pin_right", "trigger_guard_fore_stem",
		"trigger_guard_rear_stem", "trigger_guard_bridge", "trigger_blade",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("crossbow missing semantic part: %s" % part_name).is_true()
	assert_int(instance.find_children("*", "MeshInstance3D", true, false).size()).is_equal(30)
	instance.free()


func test_crossbow_dimensions_symmetry_overlap_and_attachment() -> void:
	var instance := _instantiate()
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	assert_float(bounds.size.x).is_equal_approx(31.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(33.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(9.0 / 32.0, 0.002)
	assert_array(SUPPORT.find_unmirrored_parts(instance, Vector3(-1.0, 1.0, 1.0))).is_empty()
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()


func test_crossbow_primary_stock_is_stepped_instead_of_one_long_bar() -> void:
	var instance := _instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	assert_str(String(meshes[0].name)).is_equal("body_stock_core")
	var fore_stock_size := (meshes[0] as MeshInstance3D).get_aabb().size
	var housing_size := _find_mesh(instance, "stock_lock_housing").get_aabb().size
	var grip_size := _find_mesh(instance, "stock_grip_neck").get_aabb().size
	var rear_size := _find_mesh(instance, "stock_rear").get_aabb().size
	assert_float(fore_stock_size.y).is_equal_approx(9.0 / 32.0, 0.002)
	assert_float(housing_size.x).is_equal_approx(7.0 / 32.0, 0.002)
	assert_float(grip_size.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(rear_size.y).is_equal_approx(8.0 / 32.0, 0.002)
	assert_float(_find_mesh(instance, "stock_butt").get_aabb().size.x).is_equal_approx(9.0 / 32.0, 0.002)
	var cheek := _root_box(_find_mesh(instance, "stock_cheek_rest"))
	var rear := _root_box(_find_mesh(instance, "stock_rear"))
	assert_float(cheek.end.z).is_equal_approx(rear.position.z, 0.002)
	assert_float(cheek.size.z).is_equal_approx(1.0 / 32.0, 0.002)
	instance.free()


func test_crossbow_lower_lockwork_has_open_guard_trigger_and_cocking_latch() -> void:
	var instance := _instantiate()
	var housing := _root_box(_find_mesh(instance, "stock_lock_housing"))
	var bridge := _root_box(_find_mesh(instance, "trigger_guard_bridge"))
	var trigger := _root_box(_find_mesh(instance, "trigger_blade"))
	var latch := _find_mesh(instance, "cocking_latch").get_aabb().size
	var guard_depth_gap := maxf(housing.position.z, bridge.position.z) \
		- minf(housing.end.z, bridge.end.z)
	assert_float(guard_depth_gap).is_equal_approx(1.0 / 32.0, 0.002)
	assert_float(bridge.size.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_float(bridge.size.y).is_equal_approx(2.0 / 32.0, 0.002)
	assert_float(trigger.size.x).is_equal_approx(1.0 / 32.0, 0.002)
	assert_float(trigger.size.y).is_equal_approx(1.0 / 32.0, 0.002)
	assert_float(latch.x).is_equal_approx(3.0 / 32.0, 0.002)
	assert_bool(_boxes_touch_on_depth_face(trigger, housing)).is_true()
	assert_bool(_boxes_touch_on_depth_face(trigger, bridge)).is_true()
	instance.free()


func test_crossbow_stepped_string_runs_from_limb_tips_to_stock() -> void:
	var instance := _instantiate()
	var outer_left := _root_box(_find_mesh(instance, "bowstring_outer_left"))
	var elbow_left := _root_box(_find_mesh(instance, "bowstring_elbow_left"))
	var inner_left := _root_box(_find_mesh(instance, "bowstring_inner_left"))
	var outer_right := _root_box(_find_mesh(instance, "bowstring_outer_right"))
	var elbow_right := _root_box(_find_mesh(instance, "bowstring_elbow_right"))
	var inner_right := _root_box(_find_mesh(instance, "bowstring_inner_right"))
	var stock := _root_box(_find_mesh(instance, "body_stock_core"))
	assert_float(outer_left.end.x).is_equal_approx(elbow_left.position.x, 0.002)
	assert_float(elbow_left.end.x).is_equal_approx(inner_left.position.x, 0.002)
	assert_float(inner_left.end.x).is_equal_approx(stock.position.x, 0.002)
	assert_float(outer_right.position.x).is_equal_approx(elbow_right.end.x, 0.002)
	assert_float(elbow_right.position.x).is_equal_approx(inner_right.end.x, 0.002)
	assert_float(inner_right.position.x).is_equal_approx(stock.end.x, 0.002)
	instance.free()


func test_crossbow_imported_palette_keeps_wood_steel_brass_and_flax() -> void:
	var instance := _instantiate()
	var wood := _mesh_material(instance, "body_stock_core")
	var lock_housing := _mesh_material(instance, "stock_lock_housing")
	var grip := _mesh_material(instance, "stock_grip_neck")
	var cheek := _mesh_material(instance, "stock_cheek_rest")
	var steel := _mesh_color(instance, "limb_mid_left")
	var brass := _mesh_color(instance, "bolt_rail_upper")
	var string_color := _mesh_color(instance, "bowstring_inner_right")
	assert_object(wood.albedo_texture).is_not_null()
	assert_object(lock_housing.albedo_texture).is_not_null()
	assert_object(grip.albedo_texture).is_not_null()
	assert_object(cheek.albedo_texture).is_not_null()
	assert_bool(steel.b > steel.r and steel.g > steel.r).is_true()
	assert_bool(brass.r > brass.g and brass.g > brass.b).is_true()
	assert_bool(string_color.r > string_color.b and string_color.g > string_color.b).is_true()
	instance.free()


func test_crossbow_embeds_distinct_nonblack_pixel_textures() -> void:
	var instance := _instantiate()
	var stock := _mesh_material(instance, "body_stock_core")
	var butt := _mesh_material(instance, "stock_butt")
	var grip := _mesh_material(instance, "stock_grip_neck")
	for material in [stock, butt, grip]:
		assert_object(material.albedo_texture).is_not_null()
		assert_int(material.albedo_texture.get_width()).is_equal(8)
		assert_int(material.albedo_texture.get_height()).is_equal(8)
		assert_float(_texture_max_channel(material)).is_greater(0.20)
		assert_float(_texture_color_range(material)).is_greater(0.05)
	assert_bool(stock.albedo_texture != butt.albedo_texture).is_true()
	assert_bool(stock.albedo_texture == grip.albedo_texture).is_true()
	var glb_text := _glb_ascii()
	assert_str(glb_text).contains("TEXCOORD_0")
	assert_str(glb_text).contains("crossbow_walnut_grain_albedo")
	assert_str(glb_text).contains("crossbow_dark_endgrain_albedo")
	instance.free()


func test_crossbow_fore_stock_uses_fixed_voxel_scale_uvs() -> void:
	var instance := _instantiate()
	var stock := _find_mesh(instance, "body_stock_core")
	var arrays := stock.mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_int(uvs.size()).is_greater(0)
	var min_uv := Vector2(INF, INF)
	var max_uv := Vector2(-INF, -INF)
	for uv in uvs:
		min_uv = min_uv.min(uv)
		max_uv = max_uv.max(uv)
	var span := max_uv - min_uv
	assert_float(maxf(span.x, span.y)).is_greater(1.0)
	instance.free()


func test_crossbow_exports_color_attribute_and_exact_capture_mapping() -> void:
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	for index in range(bytes.size()):
		if bytes[index] == 0:
			bytes[index] = 32
	assert_bool(bytes.get_string_from_ascii().contains("COLOR_0")).is_true()
	var capture_source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(capture_source).contains('"crossbow": "res://assets/meshes/weapons/weapons_voxel_crossbow.glb"')


func test_crossbow_verification_images_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		var structural := SUPPORT.inspect_image_file(
			"res://reports/props_preview/crossbow_%s.png" % view_name
		)
		assert_bool(structural["nonblank"]) \
			.override_failure_message("blank crossbow structural view: %s" % view_name).is_true()
	for view_name in ["preview", "front", "side", "top"]:
		var rendered := SUPPORT.inspect_image_file(
			"res://reports/props_preview/voxel_crossbow_render_%s.png" % view_name
		)
		assert_bool(rendered["nonblank"]) \
			.override_failure_message("blank crossbow Blender view: %s" % view_name).is_true()


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
	assert_bool(false).override_failure_message("missing crossbow mesh: %s" % part_name).is_true()
	return null


func _root_box(mesh: MeshInstance3D) -> AABB:
	return mesh.transform * mesh.get_aabb()


func _boxes_touch_on_depth_face(a: AABB, b: AABB) -> bool:
	return is_equal_approx(a.position.z, b.end.z) or is_equal_approx(a.end.z, b.position.z)


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
