extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")
const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")

const GENERATOR_PATH := "res://tools/generate_voxel_slime.py"
const STATIC_PATH := "res://assets/meshes/characters/voxel_slime_24px.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_slime_24px_rig.glb"
const EXPECTED_PART_COUNT := 51
const EXPECTED_ENVELOPE := Vector3(34.0, 28.0, 24.0)
const GEOMETRY_EPSILON := 0.0001
const PX_PER_METER := 32.0

const EXPECTED_BONES := [
	"Root", "Torso", "Head", "Face", "Core", "Pseudopod.L", "Pseudopod.R",
]

const EXPECTED_ANIMATIONS := [
	"idle", "run", "hurt", "stunned", "death", "kick", "lift", "pickup",
	"throw_weapon", "throw_furniture", "block", "slash", "claw_swipe", "default",
]

const FRONT_SILHOUETTE_PARTS := [
	"puddle_left_lobe", "puddle_right_lobe", "mid_belly_center",
	"upper_belly_left", "upper_belly_right", "amber_core_lower", "amber_core_upper",
	"eye_socket_left", "eye_socket_right", "cap_center_offset", "crown_droop_left",
]

const SIDE_DEPTH_PARTS := [
	"puddle_front_lip", "puddle_back_shelf", "lower_belly_center",
	"mid_back_ridge", "upper_back_left", "upper_back_right", "rear_bubble",
]

const TOP_SILHOUETTE_PARTS := [
	"puddle_left_lobe", "puddle_right_lobe", "puddle_front_lip", "puddle_back_shelf",
	"crown_center", "crown_left_mass", "crown_right_mass", "cap_center_offset",
]

const LEGACY_POLLUTION_PATHS := [
	"res://assets/meshes/characters/voxel_slime_18px.glb",
	"res://assets/meshes/characters/voxel_slime_18px_rig.glb",
	"res://tools/generate_slime.py",
	"res://tools/generate_voxel_slime_legacy.py",
	"res://tools/voxel_slime_rig.py",
]


func test_slime_generator_is_bespoke_and_fixed_to_one_identity() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "slime"')
	assert_str(source).contains('TARGET_ENVELOPE_PX = (34.0, 24.0, 28.0)')
	assert_str(source).contains("FACING_ROT_Z = math.pi")
	assert_str(source).contains('"voxel_slime_24px.glb"')
	assert_str(source).contains('"voxel_slime_24px_rig.glb"')
	assert_str(source).contains("def build_slime")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_single_face_connected_component")
	for forbidden in [
		"voxel_creature_rig", "voxel_dragon_rig", "voxel_humanoid_rig",
		"MODEL_REGISTRY", "CREATURE_CONFIGS", "for model_id in", ".glob(", ".rglob(",
	]:
		assert_str(source) \
			.override_failure_message("slime generator contains mixed/batch marker: %s" % forbidden) \
			.not_contains(forbidden)


func test_slime_source_declares_51_unique_body_only_parts() -> void:
	var parts := _parse_part_specs()
	assert_int(parts.size()).is_equal(EXPECTED_PART_COUNT)
	var names: Array[String] = []
	for part in parts:
		var name: String = part["name"]
		assert_bool(names.has(name)).override_failure_message("duplicate slime part: %s" % name).is_false()
		names.append(name)
		for forbidden in ["weapon", "sword", "axe", "shield", "armor", "staff"]:
			assert_bool(name.contains(forbidden)).is_false()


func test_slime_authored_envelope_is_broad_low_and_pixel_aligned() -> void:
	var parts := _parse_part_specs()
	var bounds := _combined_bounds(parts)
	assert_float(bounds.size.x).is_equal_approx(EXPECTED_ENVELOPE.x, GEOMETRY_EPSILON)
	assert_float(bounds.size.y).is_equal_approx(EXPECTED_ENVELOPE.y, GEOMETRY_EPSILON)
	assert_float(bounds.size.z).is_equal_approx(EXPECTED_ENVELOPE.z, GEOMETRY_EPSILON)
	assert_float(bounds.size.x / bounds.size.z).is_greater_equal(1.4)
	assert_float(bounds.size.y / bounds.size.z).is_greater_equal(1.15)
	for part in parts:
		for value in [part["center"].x, part["center"].y, part["center"].z,
			part["size"].x, part["size"].y, part["size"].z]:
			assert_float(absf(float(value) * 2.0 - roundf(float(value) * 2.0))).is_less(0.001)


func test_slime_static_parts_have_zero_overlap_and_one_face_contact_component() -> void:
	var parts := _parse_part_specs()
	var adjacency: Array[Array] = []
	for _part in parts:
		adjacency.append([])
	for left in range(parts.size()):
		for right in range(left + 1, parts.size()):
			var overlap := _axis_overlaps(parts[left]["aabb"], parts[right]["aabb"])
			var volume_overlap := overlap.x > GEOMETRY_EPSILON \
				and overlap.y > GEOMETRY_EPSILON and overlap.z > GEOMETRY_EPSILON
			assert_bool(volume_overlap).override_failure_message(
				"slime overlap: %s / %s (%s)" % [parts[left]["name"], parts[right]["name"], overlap]
			).is_false()
			if _is_face_contact(overlap):
				adjacency[left].append(right)
				adjacency[right].append(left)
	var visited := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var current := queue.pop_front()
		for neighbour in adjacency[current]:
			if not visited.has(neighbour):
				visited[neighbour] = true
				queue.append(neighbour)
	assert_int(visited.size()).override_failure_message(
		"all 51 slime parts must form one face-connected assembly"
	).is_equal(parts.size())


func test_slime_primary_masses_stay_broad_and_visible_in_three_views() -> void:
	var parts := _parts_by_name()
	for name in ["puddle_center", "lower_belly_center", "mid_belly_center", "upper_belly_center"]:
		var size: Vector3 = parts[name]["size"]
		assert_float(size.x).override_failure_message("slime mass too narrow: %s" % name).is_greater_equal(18.0)
		assert_float(size.y).override_failure_message("slime mass too shallow: %s" % name).is_greater_equal(16.0)
	for group in [FRONT_SILHOUETTE_PARTS, SIDE_DEPTH_PARTS, TOP_SILHOUETTE_PARTS]:
		for name in group:
			assert_bool(parts.has(name)).override_failure_message("missing slime silhouette part: %s" % name).is_true()


func test_slime_material_ramps_and_authored_asymmetry_are_explicit() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	for material_name in [
		"Slime_Gel_Deep", "Slime_Gel_Mid", "Slime_Gel_High", "Slime_Wet_High",
		"Slime_CoreShadow_Deep", "Slime_CoreShadow_Mid",
		"Slime_Core_Deep", "Slime_Core_Mid", "Slime_Core_High",
		"Slime_Eye_Deep", "Slime_Eye_Mid", "Slime_Eye_High",
	]:
		assert_str(source).contains(material_name)
	for anchor in ["crown_droop_left", "droop_tip_left", "cap_center_offset", "rear_bubble"]:
		assert_str(source).contains('PartSpec("%s"' % anchor)
	assert_str(source).not_contains("crown_droop_right")
	assert_str(source).not_contains("import random")


func test_slime_rig_source_owns_seven_bones_and_fourteen_actions() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains("def _create_slime_armature")
	assert_str(source).contains("def _parent_parts_to_slime_bones")
	assert_str(source).contains("def _build_slime_actions")
	for bone_name in EXPECTED_BONES:
		assert_str(source).contains('(\"%s\",' % bone_name)
	var pattern := RegEx.new()
	assert_int(pattern.compile('make_action\\(armature, "([^"]+)"')).is_equal(OK)
	var actions: Array[String] = []
	for match_result in pattern.search_all(source):
		actions.append(match_result.get_string(1))
	assert_int(actions.size()).is_equal(EXPECTED_ANIMATIONS.size())
	for animation_name in EXPECTED_ANIMATIONS:
		assert_bool(actions.has(animation_name)).is_true()
	assert_str(source).not_contains("debug_")


func test_slime_is_accepted_at_a_tier_after_individual_dod() -> void:
	assert_str(TIERS.tier_for("slime")).is_equal(TIERS.A)
	assert_bool(TIERS.is_accepted("slime")).is_true()
	var rig_test_source := FileAccess.get_file_as_string("res://tests/gdunit/voxel_rig_animation_test.gd")
	assert_str(rig_test_source).contains('const CREATURE_IDS := ["dragon", "slime"]')
	assert_str(rig_test_source).contains('"slime": PI')


func test_slime_exports_match_authored_geometry_and_creature_rig_contract() -> void:
	assert_bool(FileAccess.file_exists(STATIC_PATH)).is_true()
	assert_bool(FileAccess.file_exists(RIG_PATH)).is_true()
	if not FileAccess.file_exists(STATIC_PATH) or not FileAccess.file_exists(RIG_PATH):
		return
	var packed := load(STATIC_PATH) as PackedScene
	assert_object(packed).is_not_null()
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	add_child(instance)
	var names: Array[String] = []
	_collect_mesh_names(instance, names)
	assert_int(names.size()).is_equal(EXPECTED_PART_COUNT)
	var size_px := SUPPORT.combined_aabb(instance).size * PX_PER_METER
	var sorted_size := [size_px.x, size_px.y, size_px.z]
	sorted_size.sort()
	assert_float(float(sorted_size[0])).is_between(23.0, 25.0)
	assert_float(float(sorted_size[1])).is_between(27.0, 29.0)
	assert_float(float(sorted_size[2])).is_between(33.0, 35.0)
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()
	var report = VALIDATOR.validate_glb(RIG_PATH, false)
	assert_bool(report.ok).override_failure_message(str(report)).is_true()
	assert_int(report.bone_names.size()).is_equal(EXPECTED_BONES.size())
	assert_int(report.animation_names.size()).is_equal(EXPECTED_ANIMATIONS.size())


func test_slime_structural_and_real_three_view_evidence_is_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		_assert_readable_nonblank_capture(
			"res://reports/characters_preview/voxel_slime_%s.png" % view_name,
			256
		)
	for view_name in ["preview", "front", "side", "top"]:
		_assert_readable_nonblank_capture(
			"res://reports/characters_preview/voxel_slime_render_%s.png" % view_name,
			1000
		)


func test_legacy_slime_pollution_remains_absent() -> void:
	for path in LEGACY_POLLUTION_PATHS:
		assert_bool(FileAccess.file_exists(path)).override_failure_message(
			"legacy slime pollution returned: %s" % path
		).is_false()


func _parse_part_specs() -> Array[Dictionary]:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	var pattern := RegEx.new()
	var expression := 'PartSpec\\("([^"]+)", \\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\), \\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\), "([^"]+)", "([^"]+)"\\)'
	assert_int(pattern.compile(expression)).is_equal(OK)
	var parts: Array[Dictionary] = []
	for match_result in pattern.search_all(source):
		var center := Vector3(match_result.get_string(2).to_float(), match_result.get_string(3).to_float(), match_result.get_string(4).to_float())
		var size := Vector3(match_result.get_string(5).to_float(), match_result.get_string(6).to_float(), match_result.get_string(7).to_float())
		parts.append({
			"name": match_result.get_string(1), "center": center, "size": size,
			"material": match_result.get_string(8), "bone": match_result.get_string(9),
			"aabb": AABB(center - size * 0.5, size),
		})
	return parts


func _parts_by_name() -> Dictionary:
	var result := {}
	for part in _parse_part_specs():
		result[part["name"]] = part
	return result


func _combined_bounds(parts: Array[Dictionary]) -> AABB:
	var bounds: AABB = parts[0]["aabb"]
	for index in range(1, parts.size()):
		bounds = bounds.merge(parts[index]["aabb"])
	return bounds


func _axis_overlaps(first: AABB, second: AABB) -> Vector3:
	return Vector3(
		minf(first.end.x, second.end.x) - maxf(first.position.x, second.position.x),
		minf(first.end.y, second.end.y) - maxf(first.position.y, second.position.y),
		minf(first.end.z, second.end.z) - maxf(first.position.z, second.position.z)
	)


func _is_face_contact(overlap: Vector3) -> bool:
	var flush_axes := 0
	var solid_axes := 0
	for value in [overlap.x, overlap.y, overlap.z]:
		if absf(value) <= GEOMETRY_EPSILON:
			flush_axes += 1
		elif value > GEOMETRY_EPSILON:
			solid_axes += 1
	return flush_axes == 1 and solid_axes == 2


func _collect_mesh_names(node: Node, names: Array[String]) -> void:
	if node is MeshInstance3D:
		names.append(String(node.name))
	for child in node.get_children():
		_collect_mesh_names(child, names)


func _assert_readable_nonblank_capture(path: String, minimum_side: int) -> void:
	var inspection: Dictionary = SUPPORT.inspect_image_file(path)
	assert_bool(bool(inspection["exists"])).override_failure_message(
		"missing slime capture: %s" % path
	).is_true()
	if not bool(inspection["exists"]):
		return
	assert_bool(bool(inspection["readable"])).is_true()
	assert_int(int(inspection["width"])).is_greater_equal(minimum_side)
	assert_int(int(inspection["height"])).is_greater_equal(minimum_side)
	assert_bool(bool(inspection["nonblank"])).override_failure_message(
		"blank slime capture: %s" % path
	).is_true()
