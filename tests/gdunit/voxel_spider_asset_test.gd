extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")
const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")

const GENERATOR_PATH := "res://tools/generate_voxel_spider.py"
const STATIC_PATH := "res://assets/meshes/characters/voxel_spider_30px.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_spider_30px_rig.glb"
const EXPECTED_PART_COUNT := 85
const EXPECTED_ENVELOPE := Vector3(54.0, 50.0, 30.0)
const GEOMETRY_EPSILON := 0.0001
const PX_PER_METER := 32.0

const EXPECTED_BONES := [
	"Root", "Thorax", "Head", "Abdomen", "Venom", "Mandible.L", "Mandible.R",
	"Leg1.L", "Leg1.R", "Leg2.L", "Leg2.R", "Leg3.L", "Leg3.R", "Leg4.L", "Leg4.R",
]

const EXPECTED_ANIMATIONS := [
	"idle", "run", "hurt", "stunned", "death", "kick", "lift", "pickup",
	"throw_weapon", "throw_furniture", "block", "slash", "claw_swipe", "default",
]

const FRONT_SILHOUETTE_PARTS := [
	"leg1_foot_left", "leg1_foot_right", "leg4_foot_left", "leg4_foot_right",
	"thorax_mid_left", "thorax_mid_right", "mandible_root_left", "mandible_root_right",
	"eye_socket_major_left", "eye_socket_major_right", "abdomen_top_venom_ridge",
]

const SIDE_DEPTH_PARTS := [
	"mandible_root_left", "head_mid_center", "thorax_mid_center", "waist_bridge",
	"abdomen_lower_center", "abdomen_mid_center", "spinneret_left", "venom_sac_rear",
]

const TOP_SILHOUETTE_PARTS := [
	"leg1_foot_left", "leg1_foot_right", "leg2_mid_left", "leg2_mid_right",
	"leg3_mid_left", "leg3_mid_right", "leg4_foot_left", "leg4_foot_right",
	"head_upper_center", "abdomen_crown_center",
]

const LEGACY_POLLUTION_PATHS := [
	"res://assets/models/spider.obj",
	"res://assets/models/spider.mtl",
	"res://assets/meshes/characters/voxel_spider_18px.glb",
	"res://assets/meshes/characters/voxel_spider_18px_rig.glb",
	"res://tools/generate_spider.py",
	"res://tools/generate_voxel_spider_legacy.py",
	"res://tools/voxel_spider_rig.py",
]


func test_spider_generator_is_bespoke_and_fixed_to_one_identity() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "spider"')
	assert_str(source).contains('TARGET_ENVELOPE_PX = (54.0, 30.0, 50.0)')
	assert_str(source).contains("FACING_ROT_Z = math.pi")
	assert_str(source).contains('"voxel_spider_30px.glb"')
	assert_str(source).contains('"voxel_spider_30px_rig.glb"')
	assert_str(source).contains("def build_spider")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap")
	assert_str(source).contains("assert_parts_single_face_connected_component")
	for forbidden in [
		"voxel_creature_rig", "voxel_dragon_rig", "voxel_humanoid_rig",
		"MODEL_REGISTRY", "CREATURE_CONFIGS", "for model_id in", ".glob(", ".rglob(",
	]:
		assert_str(source) \
			.override_failure_message("spider generator contains mixed/batch marker: %s" % forbidden) \
			.not_contains(forbidden)


func test_spider_source_declares_85_unique_body_only_parts() -> void:
	var parts := _parse_part_specs()
	assert_int(parts.size()).is_equal(EXPECTED_PART_COUNT)
	var names: Array[String] = []
	for part in parts:
		var name: String = part["name"]
		assert_bool(names.has(name)).override_failure_message("duplicate spider part: %s" % name).is_false()
		names.append(name)
		for forbidden in ["weapon", "sword", "axe", "shield", "armor", "staff"]:
			assert_bool(name.contains(forbidden)).is_false()


func test_spider_authored_envelope_is_broad_low_and_pixel_aligned() -> void:
	var parts := _parse_part_specs()
	var bounds := _combined_bounds(parts)
	assert_float(bounds.size.x).is_equal_approx(EXPECTED_ENVELOPE.x, GEOMETRY_EPSILON)
	assert_float(bounds.size.y).is_equal_approx(EXPECTED_ENVELOPE.y, GEOMETRY_EPSILON)
	assert_float(bounds.size.z).is_equal_approx(EXPECTED_ENVELOPE.z, GEOMETRY_EPSILON)
	assert_float(bounds.size.x / bounds.size.z).is_greater_equal(1.75)
	assert_float(bounds.size.y / bounds.size.z).is_greater_equal(1.6)
	for part in parts:
		for value in [part["center"].x, part["center"].y, part["center"].z,
			part["size"].x, part["size"].y, part["size"].z]:
			assert_float(absf(float(value) * 2.0 - roundf(float(value) * 2.0))).is_less(0.001)


func test_spider_static_parts_have_zero_overlap_and_one_face_contact_component() -> void:
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
				"spider overlap: %s / %s (%s)" % [parts[left]["name"], parts[right]["name"], overlap]
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
		"all 85 spider parts must form one face-connected assembly"
	).is_equal(parts.size())


func test_spider_has_eight_thick_three_segment_legs() -> void:
	var parts := _parse_part_specs()
	var leg_parts: Array[Dictionary] = []
	for part in parts:
		if String(part["name"]).begins_with("leg"):
			leg_parts.append(part)
	assert_int(leg_parts.size()).is_equal(24)
	for side in ["left", "right"]:
		for leg_index in range(1, 5):
			for segment in ["root", "mid", "foot"]:
				assert_bool(_parts_by_name().has("leg%d_%s_%s" % [leg_index, segment, side])).is_true()
	for part in leg_parts:
		var size: Vector3 = part["size"]
		assert_float(size.x).override_failure_message("thin spider leg: %s" % part["name"]).is_greater_equal(5.0)
		assert_float(size.y).override_failure_message("shallow spider leg: %s" % part["name"]).is_greater_equal(5.0)
		assert_float(size.z).override_failure_message("flat spider leg: %s" % part["name"]).is_greater_equal(6.0)


func test_spider_primary_masses_and_identity_anchors_read_in_three_views() -> void:
	var parts := _parts_by_name()
	for name in ["thorax_lower_center", "thorax_mid_center", "abdomen_lower_center", "abdomen_mid_center"]:
		var size: Vector3 = parts[name]["size"]
		assert_float(size.x).override_failure_message("spider mass too narrow: %s" % name).is_greater_equal(12.0)
		assert_float(size.y).override_failure_message("spider mass too shallow: %s" % name).is_greater_equal(12.0)
	for group in [FRONT_SILHOUETTE_PARTS, SIDE_DEPTH_PARTS, TOP_SILHOUETTE_PARTS]:
		for name in group:
			assert_bool(parts.has(name)).override_failure_message("missing spider silhouette part: %s" % name).is_true()
	for eye_name in [
		"eye_socket_major_left", "eye_socket_major_right", "eye_socket_outer_left", "eye_socket_outer_right",
		"eye_socket_lower_left", "eye_socket_lower_right", "eye_socket_upper_left", "eye_socket_upper_right",
	]:
		assert_bool(parts.has(eye_name)).is_true()


func test_spider_material_ramps_and_semantic_accents_are_explicit() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	for material_name in [
		"Spider_Carapace_Deep", "Spider_Carapace_Mid", "Spider_Carapace_High",
		"Spider_Underside_Burgundy", "Spider_Joint_Burgundy", "Spider_Fang_Ivory",
		"Spider_Eye_Deep", "Spider_Eye_Amber", "Spider_Eye_High",
		"Spider_Venom_Deep", "Spider_Venom_Mid", "Spider_Venom_High", "Spider_Spinneret_Ash",
	]:
		assert_str(source).contains(material_name)
	for anchor in ["venom_sac_rear", "abdomen_top_venom_ridge", "spinneret_left", "spinneret_right"]:
		assert_str(source).contains('PartSpec("%s"' % anchor)
	assert_str(source).not_contains("import random")


func test_spider_rig_source_owns_fifteen_bones_and_fourteen_actions() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains("def _create_spider_armature")
	assert_str(source).contains("def _parent_parts_to_spider_bones")
	assert_str(source).contains("def _build_spider_actions")
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


func test_spider_is_accepted_at_a_tier_after_individual_dod() -> void:
	assert_str(TIERS.tier_for("spider")).is_equal(TIERS.A)
	assert_bool(TIERS.is_accepted("spider")).is_true()
	var rig_test_source := FileAccess.get_file_as_string("res://tests/gdunit/voxel_rig_animation_test.gd")
	assert_str(rig_test_source).contains('const CREATURE_IDS := ["dragon", "slime", "spider"]')
	assert_str(rig_test_source).contains('"spider": PI')


func test_spider_exports_match_authored_geometry_and_creature_rig_contract() -> void:
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
	assert_float(float(sorted_size[0])).is_between(29.0, 31.0)
	assert_float(float(sorted_size[1])).is_between(49.0, 51.0)
	assert_float(float(sorted_size[2])).is_between(53.0, 55.0)
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()
	var report = VALIDATOR.validate_glb(RIG_PATH, false)
	assert_bool(report.ok).override_failure_message(str(report)).is_true()
	assert_int(report.bone_names.size()).is_equal(EXPECTED_BONES.size())
	assert_int(report.animation_names.size()).is_equal(EXPECTED_ANIMATIONS.size())


func test_spider_structural_and_real_three_view_evidence_is_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		_assert_readable_nonblank_capture(
			"res://reports/characters_preview/voxel_spider_%s.png" % view_name,
			256
		)
	for view_name in ["preview", "front", "side", "top"]:
		_assert_readable_nonblank_capture(
			"res://reports/characters_preview/voxel_spider_render_%s.png" % view_name,
			1000
		)


func test_legacy_spider_pollution_remains_absent() -> void:
	for path in LEGACY_POLLUTION_PATHS:
		assert_bool(FileAccess.file_exists(path)).override_failure_message(
			"legacy spider pollution returned: %s" % path
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
		"missing spider capture: %s" % path
	).is_true()
	if not bool(inspection["exists"]):
		return
	assert_bool(bool(inspection["readable"])).is_true()
	assert_int(int(inspection["width"])).is_greater_equal(minimum_side)
	assert_int(int(inspection["height"])).is_greater_equal(minimum_side)
	assert_bool(bool(inspection["nonblank"])).override_failure_message(
		"blank spider capture: %s" % path
	).is_true()
