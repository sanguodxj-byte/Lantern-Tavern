extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")
const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")

const GENERATOR_PATH := "res://tools/generate_voxel_troll.py"
const STATIC_PATH := "res://assets/meshes/characters/voxel_troll_64x.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_troll_64x_rig.glb"
const ENEMY_SCENE_PATH := "res://scenes/characters/enemies/troll.tscn"
const PX_PER_METER := 32.0
const CONTACT_EPSILON := 0.002

const FRONT_SILHOUETTE_PARTS := [
	"shoulder_left_inner", "shoulder_left_outer",
	"shoulder_right_inner", "shoulder_right_outer",
	"upper_arm_left", "forearm_left", "palm_left",
	"upper_arm_right", "forearm_right", "palm_right",
	"thigh_left", "thigh_right", "lower_leg_left", "lower_leg_right",
	"brow_left", "brow_right", "nose_bridge", "nose_bulb",
	"tusk_left_root", "tusk_left_outflare", "tusk_left_forward_tip",
	"tusk_right_root", "tusk_right_outflare", "tusk_right_chipped_tip",
	"loincloth_belt", "loincloth_left_torn", "loincloth_right_torn",
]

const SIDE_DEPTH_PARTS := [
	"pelvis_back", "abdomen_core", "belly_front_lower", "belly_front_upper",
	"chest_core", "pectoral_left", "upper_back_core", "neck_hump",
	"head_cranium", "jaw_core", "eye_socket_left", "lower_lip",
	"dorsal_scute_low_base", "dorsal_scute_low_ridge",
	"dorsal_scute_mid_base", "dorsal_scute_mid_ridge",
	"dorsal_scute_high_base", "dorsal_scute_high_ridge",
]

const TOP_SILHOUETTE_PARTS := [
	"foot_left_core", "foot_right_core", "hip_left", "hip_right",
	"flank_left", "flank_right", "chest_core", "upper_back_core",
	"shoulder_left_outer", "shoulder_right_outer",
	"cheek_left", "cheek_right", "ear_left", "ear_right",
	"nose_bulb", "tusk_left_outflare", "tusk_right_outflare",
	"dorsal_scute_mid_ridge", "dorsal_scute_high_ridge",
]


func test_troll_generator_is_bespoke_and_fixed_to_one_output_identity() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "troll"')
	assert_str(source).contains('TARGET_ENVELOPE_PX = (44.0, 64.0, 24.0)')
	assert_str(source).contains('"voxel_troll_64x.glb"')
	assert_str(source).contains('"voxel_troll_64x_rig.glb"')
	assert_str(source).contains("def build_troll")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap(parts")
	assert_str(source).contains("assert_parts_single_face_connected_component(parts")
	assert_str(source).contains("parts_by_bone")
	for forbidden in [
		"voxel_single_humanoid", "humanoid_core", "generate_single_humanoid",
		"MODEL_REGISTRY", "MODEL_IDS", "CREATURE_CONFIGS", "for model_id in",
		"glob(", "rglob(", "--all", "tier_target", "sys.argv",
	]:
		assert_str(source) \
			.override_failure_message("troll generator contains rejected template/batch marker: %s" % forbidden) \
			.not_contains(forbidden)


func test_troll_generator_owns_authored_palette_and_real_render_contract() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	for material_name in [
		"Troll_Skin_High", "Troll_Skin_Mid", "Troll_Skin_Dark", "Troll_Skin_Moss",
		"Troll_Scute_High", "Troll_Scute_Dark",
		"Troll_Loincloth_High", "Troll_Loincloth_Mid", "Troll_Loincloth_Dark",
	]:
		assert_str(source).contains(material_name)
	assert_str(source).contains("configure_real_render(resolution=1100)")
	assert_str(source).contains('render_real_views(PREVIEW_DIR, "voxel_troll"')


func test_troll_outputs_and_both_capture_classes_follow_distinct_names() -> void:
	var expected_paths: Array[String] = [STATIC_PATH, RIG_PATH]
	for view_name in ["front", "side", "top"]:
		expected_paths.append("res://reports/characters_preview/voxel_troll_%s.png" % view_name)
	for view_name in ["preview", "front", "side", "top"]:
		expected_paths.append("res://reports/characters_preview/voxel_troll_render_%s.png" % view_name)
	var missing_paths: Array[String] = []
	for path in expected_paths:
		if not FileAccess.file_exists(path):
			missing_paths.append(path)
	assert_array(missing_paths) \
		.override_failure_message("troll outputs/captures are not generated yet: %s" % [missing_paths]) \
		.is_empty()
	if not missing_paths.is_empty():
		return
	for view_name in ["front", "side", "top"]:
		_assert_readable_png(
			"res://reports/characters_preview/voxel_troll_%s.png" % view_name,
			256
		)
	for view_name in ["preview", "front", "side", "top"]:
		_assert_readable_png(
			"res://reports/characters_preview/voxel_troll_render_%s.png" % view_name,
			512
		)


func test_troll_has_authored_primary_masses_visible_across_three_views() -> void:
	var inst := _instantiate(STATIC_PATH)
	if inst == null:
		return
	var names: Array[String] = []
	_collect_names(inst, names)
	for required_group in [
		FRONT_SILHOUETTE_PARTS,
		SIDE_DEPTH_PARTS,
		TOP_SILHOUETTE_PARTS,
	]:
		for part_name in required_group:
			assert_bool(names.has(part_name)) \
				.override_failure_message("troll missing authored silhouette part: %s" % part_name) \
				.is_true()
	for rejected_template_part in ["torso_main", "head_main", "generic_body", "signature_plate"]:
		assert_bool(names.has(rejected_template_part)) \
			.override_failure_message("troll reused generic body part: %s" % rejected_template_part) \
			.is_false()
	inst.free()


func test_troll_uses_at_least_three_authored_skin_ramp_materials() -> void:
	var inst := _instantiate(STATIC_PATH)
	if inst == null:
		return
	var material_names: Array[String] = []
	_collect_material_names(inst, material_names)
	for required_name in ["Troll_Skin_High", "Troll_Skin_Mid", "Troll_Skin_Dark"]:
		assert_bool(material_names.has(required_name)) \
			.override_failure_message("troll missing skin ramp material: %s" % required_name) \
			.is_true()
	inst.free()


func test_troll_restores_the_full_44x64x24_pixel_envelope() -> void:
	var inst := _instantiate(STATIC_PATH)
	if inst == null:
		return
	var bounds := _combined_mesh_aabb(inst)
	var size_px := Vector3(bounds.size.x, bounds.size.y, bounds.size.z) * PX_PER_METER
	assert_float(size_px.x).is_between(43.0, 45.0)
	assert_float(size_px.y).is_between(63.0, 65.0)
	assert_float(size_px.z).is_between(23.0, 25.0)
	inst.free()


func test_troll_uses_pixel_aligned_face_connected_non_overlapping_boxes() -> void:
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
		var box_aabb: AABB = boxes[i]["aabb"]
		var size_px := box_aabb.size * PX_PER_METER
		var position_px := box_aabb.position * PX_PER_METER
		for value in [size_px.x, size_px.y, size_px.z]:
			assert_float(absf(value - roundf(value))) \
				.override_failure_message("troll box is not pixel-sized: %s %s" % [boxes[i]["name"], size_px]) \
				.is_less(0.04)
		for value in [position_px.x, position_px.y, position_px.z]:
			assert_float(absf(value * 2.0 - roundf(value * 2.0))) \
				.override_failure_message("troll box is off the half-pixel voxel boundary grid: %s %s" % [boxes[i]["name"], position_px]) \
				.is_less(0.08)
		for j in range(i + 1, boxes.size()):
			var overlaps := _axis_overlaps(box_aabb, boxes[j]["aabb"])
			var has_volume_overlap := overlaps.x > CONTACT_EPSILON \
				and overlaps.y > CONTACT_EPSILON and overlaps.z > CONTACT_EPSILON
			assert_bool(has_volume_overlap).override_failure_message(
				"troll boxes overlap: %s / %s (%s)" % [
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
		.override_failure_message("every troll voxel must belong to one face-connected assembly") \
		.is_equal(boxes.size())
	inst.free()


func test_troll_rig_exports_native_game_actions() -> void:
	var result = VALIDATOR.validate_glb(RIG_PATH, true)
	assert_bool(result.ok) \
		.override_failure_message("troll rig validator errors: %s" % [result.errors]) \
		.is_true()


func test_troll_enemy_scene_uses_accepted_stats_collision_and_axe_without_material_override() -> void:
	assert_bool(FileAccess.file_exists(ENEMY_SCENE_PATH)).is_true()
	var source := FileAccess.get_file_as_string(ENEMY_SCENE_PATH)
	assert_str(source).contains("res://scenes/characters/enemies/goblin.tscn")
	assert_str(source).contains("res://assets/meshes/characters/voxel_troll_64x_rig.glb")
	assert_str(source).contains("res://data/weapons/axe.tres")
	assert_str(source).contains("radius = 0.375")
	assert_str(source).contains("height = 2.0")
	assert_str(source).contains("speed = 1.0")
	assert_str(source).contains("max_life = 20")
	assert_str(source).contains("current_life = 20")
	assert_str(source).not_contains("base_material =")


func test_troll_remains_a_tier_after_individual_acceptance() -> void:
	assert_str(TIERS.tier_for("troll")).is_equal(TIERS.A)
	assert_bool(TIERS.is_accepted("troll")).is_true()


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


func _collect_material_names(node: Node, names: Array[String]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface_index in range(mesh_node.mesh.get_surface_count()):
				var material := mesh_node.get_active_material(surface_index)
				if material != null and not names.has(material.resource_name):
					names.append(material.resource_name)
	for child in node.get_children():
		_collect_material_names(child, names)


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
