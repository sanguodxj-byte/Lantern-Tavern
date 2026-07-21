extends GdUnitTestSuite

const DRAGON_PATH := "res://assets/meshes/characters/voxel_dragon_256px.glb"
const CONTACT_EPSILON := 0.002


func test_voxel_dragon_generator_is_fixed_and_isolated_from_mixed_creature_sources() -> void:
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_dragon.py")
	assert_bool(source.is_empty()).is_false()
	assert_str(source).contains('MODEL_ID = "dragon"')
	assert_str(source).contains('"voxel_dragon_256px.glb"')
	assert_str(source).contains('"voxel_dragon_256px_rig.glb"')
	assert_str(source).contains("from voxel_dragon_rig import build_dragon_rig")
	assert_str(source).contains("from voxel_model_primitives import")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("reset_scene()")
	assert_str(source).contains("output_path=STATIC_OUTPUT")
	assert_str(source).contains('render_stem="voxel_dragon"')
	assert_str(source).contains("build_dragon_rig(STATIC_OUTPUT, RIG_OUTPUT)")
	for forbidden_dependency in [
		"voxel_remake_lib",
		"from voxel_creature_rig import",
		"from voxel_character_rig import",
		"finish_creature_character",
		"build_creature_rig",
	]:
		assert_str(source) \
			.override_failure_message("dragon generator depends on polluted mixed source: %s" % forbidden_dependency) \
			.not_contains(forbidden_dependency)


func test_voxel_dragon_rig_source_owns_only_dragon_design_and_has_no_batch_entry() -> void:
	var path := "res://tools/voxel_dragon_rig.py"
	assert_bool(FileAccess.file_exists(path)).is_true()
	var source := FileAccess.get_file_as_string(path)
	assert_str(source).contains('EXPECTED_STATIC_NAME = "voxel_dragon_256px.glb"')
	assert_str(source).contains('EXPECTED_RIG_NAME = "voxel_dragon_256px_rig.glb"')
	assert_str(source).contains("DRAGON_BONES")
	assert_str(source).contains("def _assign_dragon_parts")
	assert_str(source).contains("def _build_dragon_actions")
	assert_str(source).contains("def build_dragon_rig")
	for forbidden_marker in [
		"from voxel_creature_rig import",
		"from voxel_character_rig import",
		"from voxel_humanoid_rig import",
		"RAT_",
		"SLIME_",
		"SPIDER_",
		"MODEL_REGISTRY",
		"CREATURE_CONFIGS",
		"sys.argv",
		"if __name__",
		"for model_id in",
		"for creature_id in",
		".glob(",
		".rglob(",
	]:
		assert_str(source) \
			.override_failure_message("dragon rig source contains mixed or batch behavior: %s" % forbidden_marker) \
			.not_contains(forbidden_marker)
	assert_str(source).contains("static_path.name != EXPECTED_STATIC_NAME")
	assert_str(source).contains("rig_path.name != EXPECTED_RIG_NAME")
	assert_str(source).contains("static_path.parent.resolve() != rig_path.parent.resolve()")


func test_voxel_dragon_rig_source_declares_the_complete_dragon_contract() -> void:
	var source := FileAccess.get_file_as_string("res://tools/voxel_dragon_rig.py")
	for bone_name in [
		"Root", "Torso", "Neck1", "Neck2", "Head", "Tail1", "Tail2", "Tail3",
		"Wing.L", "Wing.R", "FrontLeg.L", "FrontLeg.R", "BackLeg.L", "BackLeg.R",
	]:
		assert_str(source).contains('DragonBoneDef("%s"' % bone_name)
	for action_name in [
		"idle", "run", "slash", "block", "hurt", "stunned", "death", "kick",
		"lift", "pickup", "throw_weapon", "throw_furniture", "claw_swipe", "default",
	]:
		assert_str(source).contains('_make_action(armature, "%s"' % action_name)


func test_voxel_dragon_structural_outputs_exist() -> void:
	assert_bool(FileAccess.file_exists(DRAGON_PATH)).is_true()
	for image_name in [
		"voxel_dragon_front.png",
		"voxel_dragon_side.png",
		"voxel_dragon_top.png",
	]:
		assert_bool(FileAccess.file_exists("res://reports/characters_preview/%s" % image_name)).is_true()
	assert_bool(FileAccess.file_exists(
		"res://reports/characters_preview/voxel_dragon_godot_material.png"
	)).is_true()


func test_voxel_dragon_is_registered_for_structural_three_view_capture() -> void:
	var file := FileAccess.open("res://tools/voxel_prop_three_view_capture.gd", FileAccess.READ)
	assert_object(file).is_not_null()
	var source := file.get_as_text()
	file.close()
	assert_str(source).contains('"dragon"')
	assert_str(source).contains('"dragon": "res://assets/meshes/characters/voxel_dragon_256px.glb"')


func test_voxel_dragon_has_real_godot_four_view_capture_path() -> void:
	var file := FileAccess.open("res://tools/voxel_prop_material_render_preview.gd", FileAccess.READ)
	assert_object(file).is_not_null()
	var source := file.get_as_text()
	file.close()
	assert_str(source).contains("--asset=<model_id>")
	assert_str(source).not_contains("--dragon-only")
	assert_str(source).contains("voxel_%s_render_%s.png")
	assert_str(source).contains("voxel_%s_godot_material.png")
	assert_str(source).contains('"dragon": "res://assets/meshes/characters/voxel_dragon_256px.glb"')
	for view_name in ["preview", "front", "side", "top"]:
		assert_str(source).contains('"%s"' % view_name)

func test_voxel_dragon_glb_contains_expected_parts() -> void:
	var packed := load(DRAGON_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var inst := packed.instantiate()
	assert_object(inst).is_not_null()
	
	# 收集所有子孙节点名
	var names: Array[String] = []
	_collect_names(inst, names)
	
	for part_name in [
		"hull_core",
		"prow_chest",
		"stern_hip",
		"prow_keel",
		"hull_belly_0",
		"prow_plate",
		"cervix_base",
		"cervix_top",
		"cranium",
		"muzzle",
		"mandible",
		"left_eye",
		"right_eye",
		"left_horn",
		"right_horn",
		"brow_plate",
		"tooth_0",
		"tooth_1",
		"tooth_2",
		"whip_0",
		"whip_1",
		"whip_2",
		"whip_3",
		"tail_spike",
		"whip_sail_left",
		"whip_sail_right",
		"left_wing_shoulder",
		"left_wing_arm",
		"left_wing_tip",
		"left_wing_membrane_root",
		"left_wing_membrane_a",
		"left_wing_membrane_b",
		"left_wing_membrane_tip",
		"left_front_leg",
		"left_claw_front",
		"left_back_leg",
		"left_claw_back",
		"right_wing_shoulder",
		"right_wing_arm",
		"right_wing_tip",
		"right_wing_membrane_root",
		"right_wing_membrane_a",
		"right_wing_membrane_b",
		"right_wing_membrane_tip",
		"right_front_leg",
		"right_claw_front",
		"right_back_leg",
		"right_claw_back",
		"dorsal_sail_0",
		"dorsal_sail_1",
		"dorsal_sail_2",
		"cervix_glow_0",
		"dorsal_glow_0",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("voxel dragon GLB missing part: %s" % part_name) \
			.is_true()

	inst.free()


func test_voxel_dragon_uses_256px_length_contract() -> void:
	var inst := _instantiate_dragon()
	var bounds := _combined_mesh_aabb(inst)
	assert_float(bounds.size.x) \
		.override_failure_message("dragon nose-to-tail length must be 256px / 8m") \
		.is_equal_approx(8.0, 0.02)
	assert_float(bounds.size.y).is_greater(2.5)
	assert_float(bounds.size.z) \
		.override_failure_message("dragon wing span must be at least 176px / 5.5m") \
		.is_greater_equal(5.5)
	var left_membrane := inst.find_child("left_wing_membrane_root", true, false) as MeshInstance3D
	assert_object(left_membrane).is_not_null()
	assert_float(left_membrane.get_aabb().size.x) \
		.override_failure_message("dragon wing membrane needs a broad visible chord") \
		.is_greater_equal(2.2)
	inst.free()


func test_voxel_dragon_is_mirrored_across_body_axis() -> void:
	var inst := _instantiate_dragon()
	for pair in [
		["left_eye", "right_eye"],
		["left_horn", "right_horn"],
		["left_wing_arm", "right_wing_arm"],
		["left_wing_tip", "right_wing_tip"],
		["left_front_leg", "right_front_leg"],
		["left_back_leg", "right_back_leg"],
	]:
		var left := inst.find_child(pair[0], true, false) as Node3D
		var right := inst.find_child(pair[1], true, false) as Node3D
		assert_object(left).is_not_null()
		assert_object(right).is_not_null()
		assert_float(left.position.x).is_equal_approx(right.position.x, 0.001)
		assert_float(left.position.y).is_equal_approx(right.position.y, 0.001)
		assert_float(left.position.z).is_equal_approx(-right.position.z, 0.001)
	inst.free()


func test_voxel_dragon_static_boxes_are_face_connected_without_volume_overlap() -> void:
	var inst := _instantiate_dragon()
	var boxes: Array[Dictionary] = []
	_collect_mesh_boxes(inst, boxes)
	assert_int(boxes.size()).is_greater(60)

	var adjacency: Array[Array] = []
	for _box in boxes:
		adjacency.append([])
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var aabb_a: AABB = boxes[i]["aabb"]
			var aabb_b: AABB = boxes[j]["aabb"]
			var overlaps := _axis_overlaps(aabb_a, aabb_b)
			var has_volume_overlap := overlaps.x > CONTACT_EPSILON \
				and overlaps.y > CONTACT_EPSILON and overlaps.z > CONTACT_EPSILON
			assert_bool(has_volume_overlap).override_failure_message(
				"dragon boxes overlap: %s / %s (%s)" % [
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
		.override_failure_message("every dragon voxel box must join one face-connected component") \
		.is_equal(boxes.size())
	inst.free()

func _collect_names(node: Node, names: Array[String]) -> void:
	names.append(node.name)
	for child in node.get_children():
		_collect_names(child, names)


func _instantiate_dragon() -> Node3D:
	var packed := load(DRAGON_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var inst := packed.instantiate() as Node3D
	assert_object(inst).is_not_null()
	add_child(inst)
	return inst


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
