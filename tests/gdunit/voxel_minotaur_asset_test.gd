extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")
const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")

const GENERATOR_PATH := "res://tools/generate_voxel_minotaur.py"
const STATIC_PATH := "res://assets/meshes/characters/voxel_minotaur_72px.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_minotaur_72px_rig.glb"
const EXPECTED_PART_COUNT := 97
const GEOMETRY_EPSILON := 0.0001
const MIN_SOLID_ENVELOPE_RATIO := 0.14
const PX_PER_METER := 32.0

const LEGACY_POLLUTION_PATHS := [
	"res://assets/meshes/characters/voxel_minotaur.glb",
	"res://assets/meshes/characters/voxel_minotaur_rig.glb",
	"res://assets/meshes/characters/voxel_minotaur_48px.glb",
	"res://assets/meshes/characters/voxel_minotaur_48px_rig.glb",
	"res://tools/generate_minotaur.py",
	"res://tools/generate_voxel_minotaur_legacy.py",
]

const FRONT_SILHOUETTE_PARTS := [
	"horn_left_root", "horn_left_rise", "horn_left_sweep", "horn_left_tip",
	"horn_right_root", "horn_right_break_cap",
	"bull_cranium_side_left", "bull_cranium_side_right",
	"muzzle_cheek_left", "muzzle_cheek_right", "broad_scapular_snout",
	"high_shoulder_yoke", "chest_flank_left", "chest_flank_right",
	"rye_skirt_left_inner", "rye_skirt_right_inner",
	"hoof_left_outer", "hoof_left_inner", "hoof_right_outer", "hoof_right_inner",
]

const SIDE_DEPTH_PARTS := [
	"bull_cranium_core", "muzzle_bridge", "broad_scapular_snout",
	"heavy_lower_jaw", "high_chest_core", "neck_front_step",
	"rear_hock_left", "long_shank_left", "hoof_crown_left",
	"tail_base", "tail_bend", "tail_tip", "tail_tuft",
]

const TOP_SILHOUETTE_PARTS := [
	"horn_left_rise", "horn_left_sweep", "horn_right_break_cap",
	"ear_left", "ear_right", "bull_cranium_core", "broad_scapular_snout",
	"high_shoulder_yoke", "shoulder_cap_left", "shoulder_cap_right",
	"shoulder_strap_left", "shoulder_strap_right", "tail_tuft",
]

const HEAD_MASS_PARTS := [
	"bull_cranium_core", "bull_cranium_side_left", "bull_cranium_side_right",
	"forehead_plane", "brow_left", "brow_right", "muzzle_bridge",
	"muzzle_cheek_left", "muzzle_cheek_right", "broad_scapular_snout",
	"nostril_left", "nose_plane_center", "nostril_right", "heavy_lower_jaw",
]

const ALLOWED_ASYMMETRIC_PARTS := [
	"horn_left_rise", "horn_left_sweep", "horn_left_tip",
	"horn_right_break_cap",
	"moss_knot_left", "moss_twist_left", "moss_tip_left",
]

const MICRO_DETAIL_PARTS := [
	"burgundy_belt_highlight", "forged_belt_buckle", "forged_buckle_glint",
	"strap_buckle_left", "strap_buckle_right",
	"moss_knot_left", "moss_twist_left", "moss_tip_left",
	"brow_left", "brow_right", "nostril_left", "nostril_right",
	"eye_socket_left", "eye_iris_left", "eye_glint_left",
	"eye_socket_right", "eye_iris_right", "eye_glint_right",
	"horn_left_tip", "horn_right_break_cap",
]

const BODY_ONLY_FORBIDDEN_TOKENS := [
	"weapon", "sword", "axe", "shield", "armor", "armour", "staff",
	"backpack", "tankard", "barrel", "bottle", "mug", "cup",
]

const EXPECTED_BONES := [
	"Root", "Pelvis", "Torso", "Neck", "Head",
	"UpperArm.R", "LowerArm.R", "Hand.R",
	"UpperArm.L", "LowerArm.L", "Hand.L",
	"UpperLeg.R", "LowerLeg.R", "Foot.R",
	"UpperLeg.L", "LowerLeg.L", "Foot.L",
]

const EXPECTED_ANIMATIONS := [
	"idle", "run", "slash", "block", "hurt", "stunned", "death", "kick",
	"lift", "pickup", "throw_weapon", "throw_furniture",
	"default", "hold_weapon", "slash_one_hand", "slash_heavy", "slash_dagger",
	"thrust_spear", "bash_shield", "claw_swipe",
]


func test_minotaur_generator_is_bespoke_and_fixed_to_one_identity() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "minotaur"')
	assert_str(source).contains('TARGET_ENVELOPE_PX = (48.0, 72.0, 32.0)')
	assert_str(source).contains('HEAD_ENVELOPE_PX = (22.0, 17.0, 18.0)')
	assert_str(source).contains('AUTHORED_PART_COUNT = 97')
	assert_str(source).contains('MIN_SOLID_ENVELOPE_RATIO = 0.14')
	assert_str(source).contains('"voxel_minotaur_72px.glb"')
	assert_str(source).contains('"voxel_minotaur_72px_rig.glb"')
	assert_str(source).contains("def build_minotaur")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)")
	assert_str(source).contains("assert_parts_single_face_connected_component(parts, label=MODEL_ID)")
	for forbidden in [
		"voxel_single_humanoid", "humanoid_core", "generic_body", "signature_plate",
		"MODEL_REGISTRY", "MODEL_IDS", "CREATURE_CONFIGS", "for model_id in",
		"glob(", "rglob(", "--all", "tier_target", "batch_generate",
	]:
		assert_str(source) \
			.override_failure_message("minotaur generator contains template/batch marker: %s" % forbidden) \
			.not_contains(forbidden)


func test_minotaur_source_declares_97_unique_body_only_parts() -> void:
	var parts := _parse_part_specs()
	assert_int(parts.size()).is_equal(EXPECTED_PART_COUNT)
	var names := {}
	for part in parts:
		var name := String(part["name"])
		assert_bool(names.has(name)) \
			.override_failure_message("duplicate minotaur part name: %s" % name) \
			.is_false()
		names[name] = true
		for token in BODY_ONLY_FORBIDDEN_TOKENS:
			assert_bool(name.to_lower().contains(token)) \
				.override_failure_message("minotaur body bakes forbidden equipment: %s" % name) \
				.is_false()


func test_minotaur_static_ast_has_exact_envelopes_and_pixel_grid() -> void:
	var parts := _parse_part_specs()
	var bounds := _combined_bounds(parts)
	assert_float(bounds.size.x).is_equal_approx(48.0, GEOMETRY_EPSILON)
	assert_float(bounds.size.z).is_equal_approx(72.0, GEOMETRY_EPSILON)
	assert_float(bounds.size.y).is_equal_approx(32.0, GEOMETRY_EPSILON)
	assert_float(bounds.position.x).is_equal_approx(-24.0, GEOMETRY_EPSILON)
	assert_float(bounds.position.y).is_equal_approx(-16.0, GEOMETRY_EPSILON)
	assert_float(bounds.position.z).is_equal_approx(0.0, GEOMETRY_EPSILON)

	var head_parts: Array[Dictionary] = []
	for part in parts:
		if HEAD_MASS_PARTS.has(String(part["name"])):
			head_parts.append(part)
	var head_bounds := _combined_bounds(head_parts)
	assert_float(head_bounds.size.x).is_equal_approx(22.0, GEOMETRY_EPSILON)
	assert_float(head_bounds.size.z).is_equal_approx(17.0, GEOMETRY_EPSILON)
	assert_float(head_bounds.size.y).is_equal_approx(18.0, GEOMETRY_EPSILON)

	for part in parts:
		var box: AABB = part["aabb"]
		for value in [box.position.x, box.position.y, box.position.z,
			box.end.x, box.end.y, box.end.z]:
			assert_float(absf(value * 2.0 - roundf(value * 2.0))) \
				.override_failure_message("minotaur boundary leaves half-pixel grid: %s %s" % [part["name"], box]) \
				.is_less(GEOMETRY_EPSILON)


func test_minotaur_static_ast_has_zero_overlap_and_one_face_contact_component() -> void:
	var parts := _parse_part_specs()
	var adjacency: Array[Array] = []
	for _part in parts:
		adjacency.append([])
	for first_index in range(parts.size()):
		for second_index in range(first_index + 1, parts.size()):
			var overlap := _axis_overlaps(parts[first_index]["aabb"], parts[second_index]["aabb"])
			var positive_volume := overlap.x > GEOMETRY_EPSILON \
				and overlap.y > GEOMETRY_EPSILON and overlap.z > GEOMETRY_EPSILON
			assert_bool(positive_volume).override_failure_message(
				"minotaur static parts overlap: %s / %s (%s)" % [
					parts[first_index]["name"], parts[second_index]["name"], overlap,
				]
			).is_false()
			if _is_face_contact(overlap):
				adjacency[first_index].append(second_index)
				adjacency[second_index].append(first_index)

	var visited := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var current := queue.pop_front()
		for neighbour in adjacency[current]:
			if not visited.has(neighbour):
				visited[neighbour] = true
				queue.append(neighbour)
	assert_int(visited.size()) \
		.override_failure_message("all 97 minotaur parts must form one face-contact component") \
		.is_equal(parts.size())


func test_minotaur_primary_limbs_and_heavy_chest_cannot_collapse_to_thin_rods() -> void:
	var parts := _parse_part_specs()
	var by_name := {}
	for part in parts:
		by_name[String(part["name"])] = part

	var minimum_widths := {
		"hand_left_palm": 9.0,
		"hand_left_fingers": 9.0,
		"wrist_left": 8.0,
		"forearm_high_left": 9.0,
		"forearm_low_left": 9.0,
		"upper_arm_high_left": 9.0,
		"upper_arm_low_left": 9.0,
		"hand_right_palm": 9.0,
		"hand_right_fingers": 9.0,
		"wrist_right": 8.0,
		"forearm_high_right": 9.0,
		"forearm_low_right": 9.0,
		"upper_arm_high_right": 9.0,
		"upper_arm_low_right": 9.0,
		"hoof_left_outer": 7.0,
		"hoof_left_inner": 7.0,
		"hoof_crown_left": 10.0,
		"fetlock_left": 8.0,
		"rear_hock_left": 10.0,
		"long_shank_left": 9.0,
		"knee_left": 10.0,
		"long_thigh_left": 12.0,
		"hoof_right_outer": 7.0,
		"hoof_right_inner": 7.0,
		"hoof_crown_right": 10.0,
		"fetlock_right": 8.0,
		"rear_hock_right": 10.0,
		"long_shank_right": 9.0,
		"knee_right": 10.0,
		"long_thigh_right": 12.0,
	}
	for part_name in minimum_widths:
		assert_bool(by_name.has(part_name)).is_true()
		var size: Vector3 = by_name[part_name]["size"]
		assert_float(size.x) \
			.override_failure_message("minotaur primary block is too narrow: %s %spx" % [part_name, size.x]) \
			.is_greater_equal(float(minimum_widths[part_name]))

	var minimum_depths := {
		"high_chest_core": 14.0,
		"abdomen_keel": 12.0,
		"high_shoulder_yoke": 12.0,
	}
	for part_name in minimum_depths:
		var size: Vector3 = by_name[part_name]["size"]
		assert_float(size.y) \
			.override_failure_message("minotaur heavy torso is too shallow: %s %spx" % [part_name, size.y]) \
			.is_greater_equal(float(minimum_depths[part_name]))

	# Each five-pixel toe remains visibly separate, with an exact one-pixel cleft.
	var left_outer: AABB = by_name["hoof_left_outer"]["aabb"]
	var left_inner: AABB = by_name["hoof_left_inner"]["aabb"]
	var right_inner: AABB = by_name["hoof_right_inner"]["aabb"]
	var right_outer: AABB = by_name["hoof_right_outer"]["aabb"]
	assert_float(left_inner.position.x - left_outer.end.x).is_equal_approx(1.0, GEOMETRY_EPSILON)
	assert_float(right_outer.position.x - right_inner.end.x).is_equal_approx(1.0, GEOMETRY_EPSILON)
	assert_float((by_name["rear_hock_left"]["center"] as Vector3).y) \
		.is_greater((by_name["fetlock_left"]["center"] as Vector3).y)
	assert_float((by_name["rear_hock_right"]["center"] as Vector3).y) \
		.is_greater((by_name["fetlock_right"]["center"] as Vector3).y)

	# The model must carry real mass inside the envelope instead of relying on
	# horn, nose, hand, or tail extrema to report a large bounding box.
	var bounds := _combined_bounds(parts)
	var solid_volume := 0.0
	for part in parts:
		var size: Vector3 = part["size"]
		solid_volume += size.x * size.y * size.z
	var solid_ratio := solid_volume / bounds.get_volume()
	assert_float(solid_ratio).is_greater_equal(MIN_SOLID_ENVELOPE_RATIO)
	var chest_size: Vector3 = by_name["high_chest_core"]["size"]
	var yoke_size: Vector3 = by_name["high_shoulder_yoke"]["size"]
	assert_float(chest_size.x / bounds.size.x).is_greater(0.45)
	assert_float(yoke_size.x / bounds.size.x).is_greater(0.50)
	assert_float(chest_size.y / bounds.size.y).is_greater(0.35)


func test_minotaur_front_belt_straps_and_buckles_follow_the_deeper_hosts() -> void:
	var by_name := {}
	for part in _parse_part_specs():
		by_name[String(part["name"])] = part
	var pelvis: AABB = by_name["pelvis_center"]["aabb"]
	var belt: AABB = by_name["burgundy_belt_center"]["aabb"]
	var belt_highlight: AABB = by_name["burgundy_belt_highlight"]["aabb"]
	var belt_buckle: AABB = by_name["forged_belt_buckle"]["aabb"]
	var belt_glint: AABB = by_name["forged_buckle_glint"]["aabb"]
	assert_float(belt.end.y).is_equal_approx(pelvis.position.y, GEOMETRY_EPSILON)
	assert_float(belt_highlight.end.y).is_equal_approx(belt.position.y, GEOMETRY_EPSILON)
	assert_float(belt_buckle.end.y).is_equal_approx(belt_highlight.position.y, GEOMETRY_EPSILON)
	assert_float(belt_glint.end.y).is_equal_approx(belt_buckle.position.y, GEOMETRY_EPSILON)

	var yoke: AABB = by_name["high_shoulder_yoke"]["aabb"]
	var shoulder_strap: AABB = by_name["shoulder_strap_left"]["aabb"]
	var chest: AABB = by_name["high_chest_core"]["aabb"]
	var chest_strap: AABB = by_name["chest_strap_left"]["aabb"]
	var strap_buckle: AABB = by_name["strap_buckle_left"]["aabb"]
	assert_float(shoulder_strap.end.y).is_equal_approx(yoke.position.y, GEOMETRY_EPSILON)
	assert_float(chest_strap.end.y).is_equal_approx(chest.position.y, GEOMETRY_EPSILON)
	assert_float(strap_buckle.end.y).is_equal_approx(chest_strap.position.y, GEOMETRY_EPSILON)


func test_minotaur_primary_masses_exceed_eighty_percent_and_span_three_views() -> void:
	var parts := _parse_part_specs()
	var names: Array[String] = []
	var total_volume := 0.0
	var micro_volume := 0.0
	for part in parts:
		var name := String(part["name"])
		names.append(name)
		var size: Vector3 = part["size"]
		var volume := size.x * size.y * size.z
		total_volume += volume
		if MICRO_DETAIL_PARTS.has(name):
			micro_volume += volume
	assert_float(total_volume).is_greater(0.0)
	assert_float((total_volume - micro_volume) / total_volume).is_greater(0.80)
	for group in [FRONT_SILHOUETTE_PARTS, SIDE_DEPTH_PARTS, TOP_SILHOUETTE_PARTS]:
		for required_name in group:
			assert_bool(names.has(required_name)) \
				.override_failure_message("minotaur missing three-view anchor: %s" % required_name) \
				.is_true()


func test_minotaur_uses_nine_explicit_three_stage_material_ramps() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	for family in [
		"Fur", "Muzzle", "Horn", "Hoof", "Ryecloth", "Burgundy", "Iron",
		"Rockmoss", "Eye",
	]:
		for stage in ["Deep", "Mid", "High"]:
			assert_str(source).contains("Minotaur_%s_%s" % [family, stage])
	var used_materials := {}
	for part in _parse_part_specs():
		used_materials[String(part["material"])] = true
	for key_prefix in [
		"fur", "muzzle", "horn", "hoof", "cloth", "burgundy", "iron", "moss", "eye",
	]:
		for key_stage in ["deep", "mid", "high"]:
			assert_bool(used_materials.has("%s_%s" % [key_prefix, key_stage])) \
				.override_failure_message("unused minotaur ramp stage: %s_%s" % [key_prefix, key_stage]) \
				.is_true()


func test_minotaur_only_uses_broken_right_horn_and_left_moss_as_asymmetry() -> void:
	var parts := _parse_part_specs()
	var by_name := {}
	for part in parts:
		by_name[String(part["name"])] = part
	for asymmetry_name in ALLOWED_ASYMMETRIC_PARTS:
		assert_bool(by_name.has(asymmetry_name)).is_true()
	for part in parts:
		var name := String(part["name"])
		var center: Vector3 = part["center"]
		if absf(center.x) <= GEOMETRY_EPSILON or ALLOWED_ASYMMETRIC_PARTS.has(name):
			continue
		var mirror_name := ""
		if name.contains("_left"):
			mirror_name = name.replace("_left", "_right")
		elif name.contains("_right"):
			mirror_name = name.replace("_right", "_left")
		assert_bool(not mirror_name.is_empty()) \
			.override_failure_message("undeclared lateral minotaur part: %s" % name) \
			.is_true()
		if mirror_name.is_empty():
			continue
		assert_bool(by_name.has(mirror_name)) \
			.override_failure_message("missing mirror for minotaur part: %s" % name) \
			.is_true()
		if not by_name.has(mirror_name):
			continue
		var mirror: Dictionary = by_name[mirror_name]
		var mirror_center: Vector3 = mirror["center"]
		assert_float(center.x).is_equal_approx(-mirror_center.x, GEOMETRY_EPSILON)
		assert_float(center.y).is_equal_approx(mirror_center.y, GEOMETRY_EPSILON)
		assert_float(center.z).is_equal_approx(mirror_center.z, GEOMETRY_EPSILON)
		assert_vector(part["size"]).is_equal(mirror["size"])
		assert_str(String(part["material"])).is_equal(String(mirror["material"]))


func test_minotaur_hands_are_clean_body_mounts() -> void:
	var hand_names: Array[String] = []
	for part in _parse_part_specs():
		if String(part["bone"]) in ["Hand.L", "Hand.R"]:
			hand_names.append(String(part["name"]))
	var expected_hand_names: Array[String] = [
		"wrist_left", "hand_left_palm", "hand_left_fingers",
		"wrist_right", "hand_right_palm", "hand_right_fingers",
	]
	assert_int(hand_names.size()).is_equal(expected_hand_names.size())
	for expected_name in expected_hand_names:
		assert_bool(hand_names.has(expected_name)).is_true()
	for name in hand_names:
		for token in BODY_ONLY_FORBIDDEN_TOKENS:
			assert_bool(name.contains(token)).is_false()


func test_minotaur_rig_source_locks_unique_armature_17_bones_and_20_actions() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('create_voxel_humanoid_armature(height_px=72.0, name="Armature")')
	assert_str(source).contains("parent_parts_by_bone(parts_by_bone, armature)")
	assert_str(source).contains("build_all_actions(armature)")
	assert_str(source).contains("build_weapon_actions(armature)")
	assert_str(source).contains("bpy.data.objects.remove(root, do_unlink=True)")
	assert_str(source).not_contains("armature.parent = root")
	assert_bool(source.find("bpy.data.objects.remove(root, do_unlink=True)") < source.find("export_rig_glb(RIG_OUTPUT)")) \
		.override_failure_message("static empty must be removed before minotaur rig export") \
		.is_true()
	assert_int(source.count("render_real_views(")) \
		.override_failure_message("minotaur generator must render exactly its own four views") \
		.is_equal(1)

	var rig_source := FileAccess.get_file_as_string("res://tools/voxel_humanoid_rig.py")
	var bone_pattern := RegEx.new()
	assert_int(bone_pattern.compile('BoneDef\\("([^"]+)"')).is_equal(OK)
	var actual_bones: Array[String] = []
	for match_result in bone_pattern.search_all(rig_source):
		actual_bones.append(match_result.get_string(1))
	assert_int(actual_bones.size()).is_equal(17)
	for expected_bone in EXPECTED_BONES:
		assert_bool(actual_bones.has(expected_bone)).is_true()

	var action_source := FileAccess.get_file_as_string("res://tools/voxel_character_rig.py")
	var action_pattern := RegEx.new()
	assert_int(action_pattern.compile('make_action\\(armature, "([^"]+)"')).is_equal(OK)
	var actual_actions: Array[String] = []
	for match_result in action_pattern.search_all(action_source):
		var action_name := match_result.get_string(1)
		if not actual_actions.has(action_name):
			actual_actions.append(action_name)
	assert_int(actual_actions.size()).is_equal(20)
	for expected_action in EXPECTED_ANIMATIONS:
		assert_bool(actual_actions.has(expected_action)).is_true()


func test_minotaur_is_accepted_at_a_tier_after_individual_dod() -> void:
	assert_str(TIERS.tier_for("minotaur")).is_equal(TIERS.A)
	assert_bool(TIERS.is_accepted("minotaur")).is_true()


func test_minotaur_exports_match_authored_geometry_and_rig_contract() -> void:
	assert_bool(FileAccess.file_exists(STATIC_PATH)).is_true()
	assert_bool(FileAccess.file_exists(RIG_PATH)).is_true()
	var packed := load(STATIC_PATH) as PackedScene
	assert_object(packed).is_not_null()
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	if instance == null:
		return
	add_child(instance)
	var mesh_names: Array[String] = []
	_collect_mesh_names(instance, mesh_names)
	assert_int(mesh_names.size()).is_equal(EXPECTED_PART_COUNT)
	for group in [FRONT_SILHOUETTE_PARTS, SIDE_DEPTH_PARTS, TOP_SILHOUETTE_PARTS]:
		for required_name in group:
			assert_bool(mesh_names.has(required_name)) \
				.override_failure_message("exported minotaur missing part: %s" % required_name) \
				.is_true()
	var size_px := SUPPORT.combined_aabb(instance).size * PX_PER_METER
	assert_float(size_px.x).is_between(47.0, 49.0)
	assert_float(size_px.y).is_between(71.0, 73.0)
	assert_float(size_px.z).is_between(27.0, 29.0)
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)).is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)).is_empty()
	instance.free()

	var report = VALIDATOR.validate_glb(RIG_PATH, true)
	assert_bool(report.ok).override_failure_message(str(report)).is_true()
	assert_int(report.bone_names.size()).is_equal(EXPECTED_BONES.size())
	assert_int(report.animation_names.size()) \
		.override_failure_message("minotaur rig must contain only the 20 game actions") \
		.is_equal(EXPECTED_ANIMATIONS.size())
	for animation_name in EXPECTED_ANIMATIONS:
		assert_bool(report.animation_names.has(animation_name)).is_true()
	for animation_name in report.animation_names:
		assert_bool(String(animation_name).begins_with("debug_")) \
			.override_failure_message("debug animation leaked into minotaur rig: %s" % animation_name) \
			.is_false()


func test_minotaur_structural_and_real_three_view_evidence_is_readable_and_nonblank() -> void:
	for view_name in ["front", "side", "top"]:
		_assert_readable_nonblank_capture(
			"res://reports/characters_preview/voxel_minotaur_%s.png" % view_name,
			256
		)
	for view_name in ["preview", "front", "side", "top"]:
		_assert_readable_nonblank_capture(
			"res://reports/characters_preview/voxel_minotaur_render_%s.png" % view_name,
			1000
		)


func test_legacy_minotaur_pollution_remains_absent() -> void:
	for path in LEGACY_POLLUTION_PATHS:
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("legacy minotaur pollution returned: %s" % path) \
			.is_false()


func _parse_part_specs() -> Array[Dictionary]:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	var pattern := RegEx.new()
	var expression := 'PartSpec\\("([^"]+)", \\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\), \\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\), "([^"]+)", "([^"]+)"\\)'
	assert_int(pattern.compile(expression)).is_equal(OK)
	var parts: Array[Dictionary] = []
	for match_result in pattern.search_all(source):
		var center := Vector3(
			match_result.get_string(2).to_float(),
			match_result.get_string(3).to_float(),
			match_result.get_string(4).to_float()
		)
		var size := Vector3(
			match_result.get_string(5).to_float(),
			match_result.get_string(6).to_float(),
			match_result.get_string(7).to_float()
		)
		parts.append({
			"name": match_result.get_string(1),
			"center": center,
			"size": size,
			"material": match_result.get_string(8),
			"bone": match_result.get_string(9),
			"aabb": AABB(center - size * 0.5, size),
		})
	return parts


func _assert_readable_nonblank_capture(path: String, minimum_side: int) -> void:
	var inspection: Dictionary = SUPPORT.inspect_image_file(path)
	assert_bool(bool(inspection["exists"])) \
		.override_failure_message("missing minotaur capture: %s" % path) \
		.is_true()
	if not bool(inspection["exists"]):
		return
	assert_bool(bool(inspection["readable"])) \
		.override_failure_message("unreadable minotaur capture: %s" % path) \
		.is_true()
	assert_int(int(inspection["width"])).is_greater_equal(minimum_side)
	assert_int(int(inspection["height"])).is_greater_equal(minimum_side)
	assert_bool(bool(inspection["nonblank"])) \
		.override_failure_message("blank minotaur capture: %s" % path) \
		.is_true()


func _collect_mesh_names(node: Node, names: Array[String]) -> void:
	if node is MeshInstance3D:
		names.append(String(node.name))
	for child in node.get_children():
		_collect_mesh_names(child, names)


func _combined_bounds(parts: Array[Dictionary]) -> AABB:
	assert_int(parts.size()).is_greater(0)
	if parts.is_empty():
		return AABB()
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
	var values := [overlap.x, overlap.y, overlap.z]
	var flush_axes := 0
	var solid_axes := 0
	for value in values:
		if absf(value) <= GEOMETRY_EPSILON:
			flush_axes += 1
		elif value > GEOMETRY_EPSILON:
			solid_axes += 1
	return flush_axes == 1 and solid_axes == 2
