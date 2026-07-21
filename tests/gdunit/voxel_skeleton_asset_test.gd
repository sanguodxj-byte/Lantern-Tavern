extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")
const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")

const GENERATOR_PATH := "res://tools/generate_voxel_skeleton.py"
const STATIC_PATH := "res://assets/meshes/characters/voxel_skeleton_48px.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_skeleton_48px_rig.glb"
const PX_PER_METER := 32.0
const CONTACT_EPSILON := 0.002

const REQUIRED_PARTS := [
	"skull_cranium", "skull_lower_core", "skull_cap", "jaw",
	"eye_socket_left", "eye_socket_right", "soul_eye_left", "soul_eye_right",
	"spine_lumbar", "spine_thoracic", "sternum",
	"rib_left_rear_0", "rib_left_side_0", "rib_left_front_0",
	"rib_right_rear_3", "rib_right_side_3", "rib_right_front_3",
	"sacrum", "pelvis_wing_left", "pelvis_wing_right",
	"clavicle_left", "clavicle_right", "shoulder_joint_left", "shoulder_joint_right",
	"upper_arm_left", "upper_arm_right", "forearm_left", "forearm_right",
	"thigh_left", "thigh_right", "shin_left", "shin_right",
	"foot_left", "foot_right", "grave_cloth_left", "grave_cloth_right",
]


func test_skeleton_generator_is_bespoke_and_fixed_to_one_output_identity() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "skeleton"')
	assert_str(source).contains('TARGET_ENVELOPE_PX = (28.0, 48.0, 11.0)')
	assert_str(source).contains('"voxel_skeleton_48px.glb"')
	assert_str(source).contains('"voxel_skeleton_48px_rig.glb"')
	assert_str(source).contains("def build_skeleton")
	assert_str(source).contains("assert_parts_voxel_assembly_valid")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("parts_by_bone")
	for forbidden in [
		"voxel_single_humanoid", "humanoid_core", "generate_single_humanoid",
		"MODEL_REGISTRY", "CREATURE_CONFIGS", "for model_id in", "sys.argv",
	]:
		assert_str(source) \
			.override_failure_message("skeleton generator contains rejected template/batch marker: %s" % forbidden) \
			.not_contains(forbidden)


func test_skeleton_outputs_and_both_capture_classes_exist() -> void:
	assert_bool(FileAccess.file_exists(STATIC_PATH)).is_true()
	assert_bool(FileAccess.file_exists(RIG_PATH)).is_true()
	for view in ["front", "side", "top"]:
		_assert_readable_png("res://reports/characters_preview/voxel_skeleton_%s.png" % view, 256)
	for view in ["preview", "front", "side", "top"]:
		_assert_readable_png(
			"res://reports/characters_preview/voxel_skeleton_render_%s.png" % view,
			512
		)


func test_skeleton_real_render_contract_is_owned_by_godot_subviewport_tool() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_prop_material_render_preview.gd")
	assert_str(source).contains("SubViewport.new()")
	assert_str(source).contains("voxel_%s_render_%s.png")
	assert_str(source).contains('"skeleton": "res://assets/meshes/characters/voxel_skeleton_48px.glb"')
	for view_name in ["preview", "front", "side", "top"]:
		assert_str(source).contains('"%s"' % view_name)


func test_skeleton_has_authored_open_ribcage_and_identity_parts() -> void:
	var inst := _instantiate(STATIC_PATH)
	if inst == null:
		return
	var names: Array[String] = []
	_collect_names(inst, names)
	for part_name in REQUIRED_PARTS:
		assert_bool(names.has(part_name)) \
			.override_failure_message("skeleton missing authored silhouette part: %s" % part_name) \
			.is_true()
	for rejected_template_part in ["torso_main", "head_main", "torso_chest_panel"]:
		assert_bool(names.has(rejected_template_part)) \
			.override_failure_message("skeleton reused generic solid-body part: %s" % rejected_template_part) \
			.is_false()
	inst.free()


func test_skeleton_restores_the_full_28x48x11_pixel_envelope() -> void:
	var inst := _instantiate(STATIC_PATH)
	if inst == null:
		return
	var bounds := _combined_mesh_aabb(inst)
	var size_px := Vector3(bounds.size.x, bounds.size.y, bounds.size.z) * PX_PER_METER
	assert_float(size_px.x).is_between(27.0, 29.0)
	assert_float(size_px.y).is_between(47.0, 49.0)
	assert_float(size_px.z).is_between(10.0, 12.0)
	inst.free()


func test_skeleton_uses_pixel_aligned_face_connected_non_overlapping_boxes() -> void:
	var inst := _instantiate(STATIC_PATH)
	if inst == null:
		return
	var boxes: Array[Dictionary] = []
	_collect_mesh_boxes(inst, boxes)
	assert_int(boxes.size()).is_greater(0)

	var adjacency: Array[Array] = []
	for _box in boxes:
		adjacency.append([])
	for i in range(boxes.size()):
		var size_px: Vector3 = boxes[i]["aabb"].size * PX_PER_METER
		for value in [size_px.x, size_px.y, size_px.z]:
			assert_float(absf(value - roundf(value))) \
				.override_failure_message("skeleton box is not pixel-sized: %s %s" % [boxes[i]["name"], size_px]) \
				.is_less(0.04)
		for j in range(i + 1, boxes.size()):
			var overlaps := _axis_overlaps(boxes[i]["aabb"], boxes[j]["aabb"])
			var has_volume_overlap := overlaps.x > CONTACT_EPSILON \
				and overlaps.y > CONTACT_EPSILON and overlaps.z > CONTACT_EPSILON
			assert_bool(has_volume_overlap).override_failure_message(
				"skeleton boxes overlap: %s / %s (%s)" % [
					boxes[i]["name"], boxes[j]["name"], overlaps
				]
			).is_false()
			if _is_face_contact(overlaps):
				adjacency[i].append(j)
				adjacency[j].append(i)

	var visited := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var current := queue.pop_front()
		for neighbour in adjacency[current]:
			if not visited.has(neighbour):
				visited[neighbour] = true
				queue.append(neighbour)
	assert_int(visited.size()) \
		.override_failure_message("every skeleton voxel must belong to one face-connected assembly") \
		.is_equal(boxes.size())
	inst.free()


func test_skeleton_rig_exports_native_game_actions() -> void:
	var result = VALIDATOR.validate_glb(RIG_PATH, true)
	assert_bool(result.ok) \
		.override_failure_message("skeleton rig validator errors: %s" % [result.errors]) \
		.is_true()


func test_skeleton_is_accepted_only_after_its_full_contract_exists() -> void:
	assert_bool(TIERS.is_accepted("skeleton")).is_true()


func _assert_readable_png(path: String, minimum_side: int) -> void:
	assert_bool(FileAccess.file_exists(path)) \
		.override_failure_message("missing capture: %s" % path) \
		.is_true()
	if not FileAccess.file_exists(path):
		return
	assert_int(FileAccess.get_file_as_bytes(path).size()).is_greater(1024)
	var image := Image.load_from_file(path)
	assert_object(image).is_not_null()
	if image == null:
		return
	assert_int(image.get_width()).is_greater_equal(minimum_side)
	assert_int(image.get_height()).is_greater_equal(minimum_side)


func _instantiate(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	assert_object(packed).override_failure_message("failed to load %s" % path).is_not_null()
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	assert_object(inst).is_not_null()
	if inst != null:
		add_child(inst)
	return inst


func _collect_names(node: Node, names: Array[String]) -> void:
	names.append(node.name)
	for child in node.get_children():
		_collect_names(child, names)


func _collect_mesh_boxes(node: Node, boxes: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		boxes.append({
			"name": mesh_node.name,
			"aabb": mesh_node.global_transform * mesh_node.get_aabb(),
		})
	for child in node.get_children():
		_collect_mesh_boxes(child, boxes)


func _combined_mesh_aabb(root: Node) -> AABB:
	var boxes: Array[Dictionary] = []
	_collect_mesh_boxes(root, boxes)
	assert_int(boxes.size()).is_greater(0)
	if boxes.is_empty():
		return AABB()
	var result: AABB = boxes[0]["aabb"]
	for index in range(1, boxes.size()):
		result = result.merge(boxes[index]["aabb"])
	return result


func _axis_overlaps(a: AABB, b: AABB) -> Vector3:
	return Vector3(
		minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x),
		minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y),
		minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
	)


func _is_face_contact(overlaps: Vector3) -> bool:
	var values := [overlaps.x, overlaps.y, overlaps.z]
	var touching_axes := 0
	var overlapping_axes := 0
	for value in values:
		if absf(value) <= CONTACT_EPSILON:
			touching_axes += 1
		elif value > CONTACT_EPSILON:
			overlapping_axes += 1
	return touching_axes == 1 and overlapping_axes == 2
