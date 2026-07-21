extends RefCounted

const PX_M := 1.0 / 32.0
const CONTACT_EPS_M := PX_M * 0.15
const VOLUME_EPS_M := PX_M * 0.35
const CAPTURE_BACKGROUND := Color(0.018, 0.021, 0.024, 1.0)
const CAPTURE_VIEWS := ["preview", "front", "side", "top"]


static func combined_aabb(root_node: Node3D) -> AABB:
	var entries := _mesh_entries(root_node)
	if entries.is_empty():
		return AABB()
	var result: AABB = entries[0]["box"]
	for index in range(1, entries.size()):
		result = result.merge(entries[index]["box"])
	return result


static func find_unmirrored_parts(
	root_node: Node3D,
	mirror_sign: Vector3,
	symmetry_origin: Vector3 = Vector3.ZERO,
	allowed_asymmetric_names: Array[String] = [],
) -> Array[String]:
	var entries := _mesh_entries(root_node)
	var missing: Array[String] = []
	for source in entries:
		var source_name: String = source["name"]
		if allowed_asymmetric_names.has(source_name):
			continue
		var source_box: AABB = source["box"]
		var offset := source_box.get_center() - symmetry_origin
		var expected_center := symmetry_origin + offset * mirror_sign
		if expected_center.is_equal_approx(source_box.get_center()):
			continue
		var found := false
		for candidate in entries:
			var candidate_box: AABB = candidate["box"]
			if not candidate_box.get_center().is_equal_approx(expected_center):
				continue
			if not candidate_box.size.is_equal_approx(source_box.size):
				continue
			if candidate["material_signature"] == source["material_signature"]:
				found = true
				break
		if not found:
			missing.append(source_name)
	return missing


static func find_positive_volume_overlaps(root_node: Node3D) -> Array[Dictionary]:
	var entries := _mesh_entries(root_node)
	var overlaps: Array[Dictionary] = []
	for left_index in range(entries.size()):
		for right_index in range(left_index + 1, entries.size()):
			var left_box: AABB = entries[left_index]["box"]
			var right_box: AABB = entries[right_index]["box"]
			var amount := _box_overlap(left_box, right_box)
			if amount.x > VOLUME_EPS_M and amount.y > VOLUME_EPS_M and amount.z > VOLUME_EPS_M:
				overlaps.append({
					"left": entries[left_index]["name"],
					"right": entries[right_index]["name"],
					"overlap": amount,
				})
	return overlaps


static func find_face_disconnected_parts(root_node: Node3D) -> Array[String]:
	var entries := _mesh_entries(root_node)
	if entries.is_empty():
		return []
	var visited := {0: true}
	var pending := [0]
	while not pending.is_empty():
		var current: int = pending.pop_back()
		for candidate in range(entries.size()):
			if visited.has(candidate):
				continue
			if _boxes_face_contact(entries[current]["box"], entries[candidate]["box"]):
				visited[candidate] = true
				pending.append(candidate)
	var disconnected: Array[String] = []
	for index in range(entries.size()):
		if not visited.has(index):
			disconnected.append(entries[index]["name"])
	return disconnected


static func inspect_image_file(path: String, background: Variant = null) -> Dictionary:
	var result := {
		"exists": FileAccess.file_exists(path),
		"readable": false,
		"width": 0,
		"height": 0,
		"foreground_samples": 0,
		"luma_range": 0.0,
		"nonblank": false,
	}
	if not result["exists"]:
		return result
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return result
	return _inspect_image(image, background).merged({"exists": true, "readable": true}, true)


static func real_renderer_available() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("headless")


static func capture_ortho_size(bounds: AABB, view_name: String) -> float:
	var projected_span := 0.0
	var padding := 1.35
	match view_name:
		"front":
			projected_span = maxf(bounds.size.x, bounds.size.y)
		"side":
			projected_span = maxf(bounds.size.z, bounds.size.y)
		"top":
			projected_span = maxf(bounds.size.x, bounds.size.z)
		_:
			projected_span = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			padding = 1.48
	return maxf(projected_span * padding, PX_M * 4.0)


static func capture_four_views(
	test_owner: Node,
	packed_scene: PackedScene,
	output_paths: Dictionary,
	prepare_model: Callable = Callable(),
) -> Dictionary:
	if not real_renderer_available():
		return {"error": ERR_UNAVAILABLE, "views": {}}
	if packed_scene == null or test_owner == null:
		return {"error": ERR_INVALID_PARAMETER, "views": {}}
	if output_paths.size() != CAPTURE_VIEWS.size():
		return {"error": ERR_INVALID_PARAMETER, "views": {}}
	for view_name in CAPTURE_VIEWS:
		if not output_paths.has(view_name) or String(output_paths[view_name]).is_empty():
			return {"error": ERR_INVALID_PARAMETER, "views": {}}

	var model := packed_scene.instantiate() as Node3D
	if model == null:
		return {"error": ERR_CANT_CREATE, "views": {}}
	var viewport := SubViewport.new()
	viewport.name = "VoxelModelCaptureViewport"
	viewport.size = Vector2i(640, 640)
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.world_3d = World3D.new()
	test_owner.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	stage.add_child(model)
	if prepare_model.is_valid():
		prepare_model.call(model)
	_add_environment(stage)

	var bounds := combined_aabb(model)
	if bounds.size.is_zero_approx():
		viewport.free()
		return {"error": ERR_CANT_CREATE, "views": {}}
	var target := bounds.get_center()
	var max_dim := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	_add_lights(stage, target, max_dim)
	var distance := maxf(max_dim * 3.0, 2.0)
	var camera_positions := {
		"preview": target + Vector3(distance * 0.65, distance * 0.28, distance),
		"front": target + Vector3(0.0, 0.0, distance),
		"side": target + Vector3(distance, 0.0, 0.0),
		"top": target + Vector3(0.0, distance, 0.001),
	}
	var view_results := {}
	for view_name in CAPTURE_VIEWS:
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = capture_ortho_size(bounds, view_name)
		camera.near = 0.01
		camera.far = distance * 4.0
		camera.position = camera_positions[view_name]
		stage.add_child(camera)
		if view_name == "top":
			camera.look_at(target, Vector3.BACK)
		else:
			camera.look_at(target, Vector3.UP)
		camera.current = true
		for frame in range(5):
			await test_owner.get_tree().process_frame
		RenderingServer.force_draw()
		await test_owner.get_tree().process_frame
		var image := viewport.get_texture().get_image()
		var output_path: String = output_paths[view_name]
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(output_path.get_base_dir())
		)
		var save_error := image.save_png(output_path) if image != null else ERR_CANT_CREATE
		var inspection := _inspect_image(image, CAPTURE_BACKGROUND)
		inspection["path"] = output_path
		inspection["save_error"] = save_error
		view_results[view_name] = inspection
		camera.free()
	viewport.free()
	return {"error": OK, "views": view_results}


static func _mesh_entries(root_node: Node3D) -> Array[Dictionary]:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root_node, meshes)
	var root_inverse := root_node.global_transform.affine_inverse()
	var entries: Array[Dictionary] = []
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		var root_space := root_inverse * mesh.global_transform
		entries.append({
			"name": String(mesh.name),
			"box": root_space * mesh.get_aabb(),
			"material_signature": _material_signature(mesh),
		})
	return entries


static func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, meshes)


static func _material_signature(mesh: MeshInstance3D) -> String:
	if mesh.mesh == null:
		return ""
	var signatures: PackedStringArray = []
	for surface_index in range(mesh.mesh.get_surface_count()):
		var material := mesh.get_surface_override_material(surface_index)
		if material == null:
			material = mesh.mesh.surface_get_material(surface_index)
		if material is BaseMaterial3D:
			var base := material as BaseMaterial3D
			signatures.append("%s|%s|%.4f|%.4f" % [
				base.resource_name,
				base.albedo_color.to_html(true),
				base.metallic,
				base.roughness,
			])
		else:
			signatures.append(str(material))
	return ";".join(signatures)


static func _box_overlap(left: AABB, right: AABB) -> Vector3:
	return Vector3(
		minf(left.end.x, right.end.x) - maxf(left.position.x, right.position.x),
		minf(left.end.y, right.end.y) - maxf(left.position.y, right.position.y),
		minf(left.end.z, right.end.z) - maxf(left.position.z, right.position.z),
	)


static func _boxes_face_contact(left: AABB, right: AABB) -> bool:
	var overlap := _box_overlap(left, right)
	var values := [overlap.x, overlap.y, overlap.z]
	if values.any(func(value: float) -> bool: return value < -CONTACT_EPS_M):
		return false
	var flush := values.filter(
		func(value: float) -> bool:
			return value >= -CONTACT_EPS_M and value <= VOLUME_EPS_M
	).size()
	var solid := values.filter(func(value: float) -> bool: return value > VOLUME_EPS_M).size()
	return flush == 1 and solid == 2


static func _inspect_image(image: Image, background: Variant = null) -> Dictionary:
	var result := {
		"readable": false,
		"width": 0,
		"height": 0,
		"foreground_samples": 0,
		"luma_range": 0.0,
		"nonblank": false,
	}
	if image == null or image.is_empty():
		return result
	var step := maxi(1, mini(image.get_width(), image.get_height()) / 80)
	var opaque_samples := 0
	var foreground_samples := 0
	var min_luma := 1.0
	var max_luma := 0.0
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var color := image.get_pixel(x, y)
			if color.a < 0.2:
				continue
			opaque_samples += 1
			var luma := (color.r + color.g + color.b) / 3.0
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)
			if background is Color:
				var bg := background as Color
				var difference := absf(color.r - bg.r) + absf(color.g - bg.g) + absf(color.b - bg.b)
				if difference > 0.06:
					foreground_samples += 1
			else:
				foreground_samples += 1
	var luma_range := max_luma - min_luma
	result["readable"] = true
	result["width"] = image.get_width()
	result["height"] = image.get_height()
	result["foreground_samples"] = foreground_samples
	result["luma_range"] = luma_range
	result["nonblank"] = opaque_samples > 100 and foreground_samples > 100 and luma_range > 0.08
	return result


static func _add_environment(stage: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = CAPTURE_BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.60, 0.66, 1.0)
	environment.ambient_light_energy = 0.34
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_environment.environment = environment
	stage.add_child(world_environment)


static func _add_lights(stage: Node3D, target: Vector3, max_dim: float) -> void:
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.89, 0.72, 1.0)
	key.light_energy = 2.1
	key.omni_range = maxf(max_dim * 5.0, 4.0)
	key.position = target + Vector3(max_dim * 1.5, max_dim * 1.4, max_dim * 2.0)
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.58, 0.72, 1.0, 1.0)
	fill.light_energy = 0.9
	fill.omni_range = maxf(max_dim * 5.0, 4.0)
	fill.position = target + Vector3(-max_dim * 1.7, max_dim * 0.4, -max_dim * 1.2)
	stage.add_child(fill)
