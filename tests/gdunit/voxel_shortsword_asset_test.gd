extends GdUnitTestSuite

const GENERATOR := "res://tools/generate_voxel_shortsword.py"
const GLB_PATH := "res://assets/meshes/weapons/weapons_voxel_shortsword.glb"
const STRUCTURAL_PREVIEW_DIR := "res://reports/props_preview"
const TRUE_3D_PREVIEW_DIR := "res://reports/props_preview"
const CONTACT_EPS := 0.005
const VOLUME_EPS := 0.01


func test_shortsword_generator_is_fixed_identity_and_documents_pixel_dimensions() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR)
	assert_str(source).contains('MODEL_ID = "shortsword"')
	assert_str(source).contains("WIDTH_PX = 15.0")
	assert_str(source).contains("DEPTH_PX = 6.0")
	assert_str(source).contains("LENGTH_PX = 33.0")
	assert_str(source).contains("PX,")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)")
	assert_bool(source.contains("BUILDERS")).is_false()
	assert_bool(source.contains("remake_all_voxel_weapons")).is_false()


func test_shortsword_is_registered_to_the_dedicated_glb() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/weapons.json"))
	assert_bool(parsed is Dictionary).is_true()
	var found := false
	for entry in parsed.get("weapons", []):
		if String(entry.get("id", "")) != "shortsword":
			continue
		found = true
		assert_str(String(entry.get("glb_path", ""))).is_equal(GLB_PATH)
		break
	assert_bool(found).is_true()


func test_shortsword_glb_loads_with_authored_semantic_parts() -> void:
	assert_bool(FileAccess.file_exists(GLB_PATH)).is_true()
	var packed := load(GLB_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate()
	assert_object(instance).is_not_null()
	var names: Array[String] = []
	_collect_names(instance, names)
	for part_name in [
		"weapons_voxel_shortsword",
		"blade_ricasso",
		"blade_belly_left",
		"blade_belly_right",
		"blade_ridge_front",
		"blade_ridge_back",
		"guard_tip_left",
		"guard_tip_right",
		"ember_stud_front",
		"ember_stud_back",
		"grip_band",
		"pommel_shoulders",
		"pommel_cap",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("shortsword GLB missing semantic part: %s" % part_name) \
			.is_true()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	assert_int(meshes.size()).is_equal(29)
	instance.free()


func test_shortsword_dimensions_match_15x6x33_pixel_envelope() -> void:
	var instance := _instantiate_in_tree()
	var bounds := _mesh_bounds(instance)
	assert_float(bounds.size.x).is_equal_approx(15.0 / 32.0, 0.002)
	assert_float(bounds.size.y).is_equal_approx(33.0 / 32.0, 0.002)
	assert_float(bounds.size.z).is_equal_approx(6.0 / 32.0, 0.002)
	instance.free()


func test_shortsword_geometry_and_materials_are_bilaterally_symmetric() -> void:
	var instance := _instantiate_in_tree()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	for mesh in meshes:
		var center := (mesh.global_transform * mesh.get_aabb()).get_center()
		if not is_zero_approx(center.x):
			assert_bool(_has_visual_mirror(mesh, meshes, Vector3(-1.0, 1.0, 1.0))) \
				.override_failure_message("shortsword part lacks left/right mirror: %s" % mesh.name) \
				.is_true()
		if not is_zero_approx(center.z):
			assert_bool(_has_visual_mirror(mesh, meshes, Vector3(1.0, 1.0, -1.0))) \
				.override_failure_message("shortsword part lacks front/back mirror: %s" % mesh.name) \
				.is_true()
	instance.free()


func test_shortsword_imported_material_palette_keeps_authored_hues() -> void:
	var instance := _instantiate_in_tree()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	var leather := _mesh_color(_find_mesh("grip_upper", meshes))
	var bronze := _mesh_color(_find_mesh("guard_center", meshes))
	var ember := _mesh_color(_find_mesh("ember_stud_front", meshes))
	var steel := _mesh_color(_find_mesh("blade_belly_left", meshes))
	assert_bool(leather.r > leather.g * 2.0 and leather.g > leather.b) \
		.override_failure_message("imported leather hue lost: %s" % leather).is_true()
	assert_bool(bronze.r > bronze.g and bronze.g > bronze.b and bronze.r - bronze.b > 0.25) \
		.override_failure_message("imported bronze hue lost: %s" % bronze).is_true()
	assert_bool(ember.r > ember.g and ember.g > ember.b and ember.r - ember.b > 0.50) \
		.override_failure_message("imported ember hue lost: %s" % ember).is_true()
	assert_bool(steel.b > steel.r and steel.g > steel.r) \
		.override_failure_message("imported steel hue lost: %s" % steel).is_true()
	instance.free()


func test_shortsword_boxes_have_no_positive_overlap_and_are_face_connected() -> void:
	var instance := _instantiate_in_tree()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	var boxes: Array[AABB] = []
	for mesh in meshes:
		boxes.append(mesh.global_transform * mesh.get_aabb())
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			assert_bool(_boxes_positive_overlap(boxes[i], boxes[j])) \
				.override_failure_message("shortsword positive overlap: %s vs %s" % [meshes[i].name, meshes[j].name]) \
				.is_false()
	assert_bool(_is_single_face_connected_component(boxes)) \
		.override_failure_message("shortsword contains a detached or corner-only box") \
		.is_true()
	instance.free()


func test_shortsword_glb_exports_vertex_colors() -> void:
	var file := FileAccess.open(GLB_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var cleaned := bytes.duplicate()
	for index in range(cleaned.size()):
		if cleaned[index] == 0:
			cleaned[index] = 32
	assert_bool(cleaned.get_string_from_ascii().contains("COLOR_0")).is_true()


func test_shortsword_capture_is_registered_for_exact_asset_selection() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_prop_three_view_capture.gd")
	assert_str(source).contains("const WEAPON_SCENES")
	assert_str(source).contains('"shortsword": "res://assets/meshes/weapons/weapons_voxel_shortsword.glb"')
	assert_str(source).contains("WEAPON_SCENES.has(requested_asset)")


func test_pickable_shortsword_relies_on_one_runtime_glb_instance() -> void:
	var scene_source := FileAccess.get_file_as_string("res://scenes/equipment/pickable_sword.tscn")
	assert_bool(scene_source.contains("weapons_voxel_shortsword.glb")).is_false()
	assert_bool(scene_source.contains('mesh_node = NodePath("weapons_voxel_shortsword/Voxel")')).is_false()


func test_shortsword_structural_three_views_are_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		_assert_image_has_visible_color_range(
			"%s/shortsword_%s.png" % [STRUCTURAL_PREVIEW_DIR, view_name]
		)


func test_shortsword_blender_true_3d_views_are_readable_and_nonblank() -> void:
	for view_name in ["preview", "front", "side", "top"]:
		_assert_image_has_visible_color_range(
			"%s/voxel_shortsword_render_%s.png" % [TRUE_3D_PREVIEW_DIR, view_name]
		)


func _instantiate_in_tree() -> Node3D:
	var packed := load(GLB_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	add_child(instance)
	return instance


func _collect_names(node: Node, names: Array[String]) -> void:
	names.append(node.name)
	for child in node.get_children():
		_collect_names(child, names)


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, meshes)


func _mesh_bounds(root_node: Node) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root_node, meshes)
	assert_int(meshes.size()).is_greater(0)
	var result := meshes[0].global_transform * meshes[0].get_aabb()
	for index in range(1, meshes.size()):
		result = result.merge(meshes[index].global_transform * meshes[index].get_aabb())
	return result


func _mesh_color(mesh: MeshInstance3D) -> Color:
	var material := mesh.get_active_material(0)
	if material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		material = mesh.mesh.surface_get_material(0)
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_color
	return Color.WHITE


func _find_mesh(part_name: String, meshes: Array[MeshInstance3D]) -> MeshInstance3D:
	for mesh in meshes:
		if String(mesh.name) == part_name:
			return mesh
	assert_bool(false).override_failure_message("missing shortsword mesh: %s" % part_name).is_true()
	return null


func _has_visual_mirror(
	source: MeshInstance3D,
	meshes: Array[MeshInstance3D],
	axis_sign: Vector3,
) -> bool:
	var source_box := source.global_transform * source.get_aabb()
	var expected_center := source_box.get_center() * axis_sign
	var source_color := _mesh_color(source)
	for candidate in meshes:
		var candidate_box := candidate.global_transform * candidate.get_aabb()
		if not candidate_box.get_center().is_equal_approx(expected_center):
			continue
		if not candidate_box.size.is_equal_approx(source_box.size):
			continue
		if source_color.is_equal_approx(_mesh_color(candidate)):
			return true
	return false


func _axis_overlap(a_min: float, a_max: float, b_min: float, b_max: float) -> float:
	return minf(a_max, b_max) - maxf(a_min, b_min)


func _box_overlaps(a: AABB, b: AABB) -> Array[float]:
	return [
		_axis_overlap(a.position.x, a.end.x, b.position.x, b.end.x),
		_axis_overlap(a.position.y, a.end.y, b.position.y, b.end.y),
		_axis_overlap(a.position.z, a.end.z, b.position.z, b.end.z),
	]


func _boxes_positive_overlap(a: AABB, b: AABB) -> bool:
	var overlaps := _box_overlaps(a, b)
	return overlaps[0] > VOLUME_EPS and overlaps[1] > VOLUME_EPS and overlaps[2] > VOLUME_EPS


func _boxes_face_contact(a: AABB, b: AABB) -> bool:
	var overlaps := _box_overlaps(a, b)
	if overlaps.any(func(value: float) -> bool: return value < -CONTACT_EPS):
		return false
	var flush := overlaps.filter(func(value: float) -> bool: return absf(value) <= CONTACT_EPS).size()
	var solid := overlaps.filter(func(value: float) -> bool: return value > VOLUME_EPS).size()
	return flush == 1 and solid == 2


func _is_single_face_connected_component(boxes: Array[AABB]) -> bool:
	if boxes.is_empty():
		return false
	var visited := {0: true}
	var pending := [0]
	while not pending.is_empty():
		var current: int = pending.pop_back()
		for candidate in range(boxes.size()):
			if visited.has(candidate):
				continue
			if _boxes_face_contact(boxes[current], boxes[candidate]):
				visited[candidate] = true
				pending.append(candidate)
	return visited.size() == boxes.size()


func _has_visible_color_range(image: Image) -> bool:
	var opaque_samples := 0
	var min_luma := 1.0
	var max_luma := 0.0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var color := image.get_pixel(x, y)
			if color.a < 0.2:
				continue
			opaque_samples += 1
			var luma := (color.r + color.g + color.b) / 3.0
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)
	return opaque_samples > 100 and max_luma - min_luma > 0.08


func _assert_image_has_visible_color_range(image_path: String) -> void:
	assert_bool(FileAccess.file_exists(image_path)) \
		.override_failure_message("missing shortsword verification image: %s" % image_path) \
		.is_true()
	var image := Image.load_from_file(image_path)
	assert_object(image).is_not_null()
	assert_int(image.get_width()).is_greater(0)
	assert_int(image.get_height()).is_greater(0)
	assert_bool(_has_visible_color_range(image)) \
		.override_failure_message("shortsword image is blank or mostly uniform: %s" % image_path) \
		.is_true()
