extends GdUnitTestSuite

const TIERS := preload("res://data/character_model_tiers.gd")
const VALIDATOR := preload("res://globals/visual/voxel_rig_validator.gd")
const SUPPORT := preload("res://tests/gdunit/support/voxel_model_test_support.gd")

const GENERATOR_PATH := "res://tools/generate_voxel_player.py"
const STATIC_PATH := "res://assets/meshes/characters/voxel_player_54px.glb"
const RIG_PATH := "res://assets/meshes/characters/voxel_player_54px_rig.glb"
const LEGACY_PATHS := [
	"res://assets/meshes/characters/voxel_player_48px.glb",
	"res://assets/meshes/characters/voxel_player_48px.glb.import",
	"res://assets/meshes/characters/voxel_player_48px_rig.glb",
	"res://assets/meshes/characters/voxel_player_48px_rig.glb.import",
]
const PX_PER_METER := 32.0

const FRONT_SILHOUETTE_PARTS := [
	"hair_crown_left", "hair_crown_right", "hair_side_part", "hair_forelock_right",
	"brow_left", "brow_right", "nose_bridge", "nose_tip", "jaw",
	"cellar_vest_front_left", "cellar_vest_front_right",
	"rolled_sleeve_left", "rolled_sleeve_right",
	"cellar_apron_left_panel", "cellar_apron_right_panel", "cellar_apron_right_fold",
	"property_key_bow", "property_key_stem", "property_key_tooth",
	"boot_toe_left", "boot_toe_right",
]

const SIDE_DEPTH_PARTS := [
	"face_cranium", "face_lower", "nose_bridge", "nose_tip", "jaw", "hair_nape",
	"workshirt_lower", "workshirt_rib_center", "cellar_vest_front_left",
	"cellar_vest_back_yoke", "cellar_apron_left_panel", "cellar_apron_tie_back",
	"boot_toe_left", "boot_vamp_left", "boot_heel_left",
]

const TOP_SILHOUETTE_PARTS := [
	"hair_crown_left", "hair_crown_right", "hair_side_part", "hair_nape",
	"shoulder_yoke_left", "shoulder_yoke_right",
	"rolled_sleeve_left", "rolled_sleeve_right",
	"cellar_vest_front_left", "cellar_vest_front_right", "cellar_vest_back_yoke",
	"cellar_apron_side_left", "cellar_apron_side_right", "cellar_apron_tie_back",
	"thumb_left", "thumb_right",
]

const ALLOWED_ASYMMETRIC_PARTS: Array[String] = [
	"hair_side_part",
	"hair_forelock_right",
	"cellar_apron_right_fold",
	"property_key_hanger",
	"property_key_bow",
	"property_key_stem",
	"property_key_tooth",
]

const MICRO_DETAIL_PARTS: Array[String] = [
	"merchant_belt_buckle",
	"cellar_apron_right_fold",
	"property_key_hanger", "property_key_bow", "property_key_stem", "property_key_tooth",
	"cellar_vest_lapel_left", "cellar_vest_lapel_right",
	"thumb_left", "thumb_right",
	"nose_bridge", "nose_tip", "mouth_line",
	"eye_left", "eye_right", "pupil_left", "pupil_right", "brow_left", "brow_right",
	"hair_side_part", "hair_forelock_right",
]

const BODY_ONLY_FORBIDDEN_TOKENS := [
	"weapon_", "shield_", "armor_", "backpack", "tankard", "mug", "cup", "bottle",
	"sword_", "axe_", "staff_",
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


func test_player_generator_is_bespoke_fixed_identity_and_rejects_legacy_output() -> void:
	assert_bool(FileAccess.file_exists(GENERATOR_PATH)).is_true()
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains('MODEL_ID = "player"')
	assert_str(source).contains('TARGET_ENVELOPE_PX = (24.0, 54.0, 14.0)')
	assert_str(source).contains('"voxel_player_54px.glb"')
	assert_str(source).contains('"voxel_player_54px_rig.glb"')
	assert_str(source).contains("def build_player")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)")
	assert_str(source).contains("assert_parts_single_face_connected_component(parts, label=MODEL_ID)")
	assert_str(source).contains("parent_parts_by_bone(parts_by_bone, armature)")
	assert_str(source).contains("build_all_actions(armature)")
	assert_str(source).contains("build_weapon_actions(armature)")
	assert_str(source).contains('create_voxel_humanoid_armature(height_px=54.0, name="Armature")')
	assert_str(source).contains("bpy.data.objects.remove(root, do_unlink=True)")
	assert_str(source).contains("bounds_center_scale(armature)")
	assert_str(source).not_contains("voxel_player_48px")
	for forbidden in [
		"voxel_single_humanoid", "humanoid_core", "generic_body", "signature_plate",
		"MODEL_REGISTRY", "MODEL_IDS", "CREATURE_CONFIGS", "for model_id in",
		"glob(", "rglob(", "--all", "tier_target", "sys.argv",
	]:
		assert_str(source) \
			.override_failure_message("player generator contains template/batch marker: %s" % forbidden) \
			.not_contains(forbidden)


func test_legacy_48px_player_pollution_remains_absent() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).not_contains("voxel_player_48px")
	for path in LEGACY_PATHS:
		assert_bool(FileAccess.file_exists(path)) \
			.override_failure_message("legacy player pollution returned: %s" % path) \
			.is_false()


func test_player_is_accepted_at_a_tier_after_individual_dod() -> void:
	assert_str(TIERS.tier_for("player")).is_equal(TIERS.A)
	assert_bool(TIERS.is_accepted("player")).is_true()


func test_player_generator_owns_body_only_identity_and_controlled_asymmetry() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	assert_str(source).contains("unarmed, unarmoured body and work clothes")
	assert_str(source).contains("gameplay equipment remains external")
	var declared_parts := _declared_part_names(source)
	assert_int(declared_parts.size()).is_greater(50)
	for required_name in ALLOWED_ASYMMETRIC_PARTS:
		assert_bool(declared_parts.has(required_name)) \
			.override_failure_message("missing controlled player asymmetry: %s" % required_name) \
			.is_true()
	_assert_names_are_body_only(declared_parts)


func test_player_generator_owns_three_stage_material_ramps_and_blender_views() -> void:
	var source := FileAccess.get_file_as_string(GENERATOR_PATH)
	for material_name in [
		"Player_Vest_Deep", "Player_Vest_Mid", "Player_Vest_High",
		"Player_Linen_Shadow", "Player_Linen_Mid", "Player_Linen_High",
		"Player_Apron_Deep", "Player_Apron_Mid", "Player_Apron_High",
		"Player_Trouser_Shadow", "Player_Trouser_Mid", "Player_Trouser_High",
		"Player_Leather_Dark", "Player_Leather_Mid", "Player_Leather_High",
		"Player_Skin_Shadow", "Player_Skin_Mid", "Player_Skin_High",
	]:
		assert_str(source).contains(material_name)
	assert_str(source).contains("configure_real_render(resolution=1100)")
	assert_str(source).contains('render_real_views(PREVIEW_DIR, "voxel_player"')
	assert_int(source.count("render_real_views(")) \
		.override_failure_message("player generator must render exactly its own four-view set") \
		.is_equal(1)


func test_player_outputs_and_both_capture_classes_exist() -> void:
	assert_bool(FileAccess.file_exists(STATIC_PATH)).is_true()
	assert_bool(FileAccess.file_exists(RIG_PATH)).is_true()
	for view_name in ["front", "side", "top"]:
		_assert_readable_capture(
			"res://reports/characters_preview/voxel_player_%s.png" % view_name,
			256
		)
	for view_name in ["preview", "front", "side", "top"]:
		_assert_readable_capture(
			"res://reports/characters_preview/voxel_player_render_%s.png" % view_name,
			512
		)


func test_player_has_authored_primary_parts_across_front_side_and_top() -> void:
	var instance := _instantiate(STATIC_PATH)
	if instance == null:
		return
	var names: Array[String] = []
	_collect_names(instance, names)
	for required_group in [FRONT_SILHOUETTE_PARTS, SIDE_DEPTH_PARTS, TOP_SILHOUETTE_PARTS]:
		for part_name in required_group:
			assert_bool(names.has(part_name)) \
				.override_failure_message("player missing authored silhouette part: %s" % part_name) \
				.is_true()
	for rejected_part in ["torso_main", "head_main", "generic_body", "signature_plate"]:
		assert_bool(names.has(rejected_part)).is_false()
	instance.free()


func test_player_primary_masses_own_at_least_eighty_percent_of_volume() -> void:
	var instance := _instantiate(STATIC_PATH)
	if instance == null:
		return
	var boxes: Array[Dictionary] = []
	_collect_mesh_boxes(instance, instance, boxes)
	var total_volume := 0.0
	var micro_volume := 0.0
	for entry in boxes:
		var volume: float = (entry["aabb"] as AABB).get_volume()
		total_volume += volume
		if MICRO_DETAIL_PARTS.has(String(entry["name"])):
			micro_volume += volume
	assert_float(total_volume).is_greater(0.0)
	if total_volume > 0.0:
		assert_float((total_volume - micro_volume) / total_volume).is_greater(0.80)
	instance.free()


func test_player_uses_required_material_ramps_in_exported_body() -> void:
	var instance := _instantiate(STATIC_PATH)
	if instance == null:
		return
	var material_names: Array[String] = []
	_collect_material_names(instance, material_names)
	for required_name in [
		"Player_Vest_Deep", "Player_Vest_Mid", "Player_Vest_High",
		"Player_Linen_Shadow", "Player_Linen_Mid", "Player_Linen_High",
		"Player_Apron_Deep", "Player_Apron_Mid", "Player_Apron_High",
	]:
		assert_bool(material_names.has(required_name)) \
			.override_failure_message("player export missing material ramp stage: %s" % required_name) \
			.is_true()
	instance.free()


func test_player_restores_exact_24x54x14_pixel_envelope() -> void:
	var instance := _instantiate(STATIC_PATH)
	if instance == null:
		return
	var bounds: AABB = SUPPORT.combined_aabb(instance)
	var size_px := bounds.size * PX_PER_METER
	assert_float(size_px.x).is_between(23.0, 25.0)
	assert_float(size_px.y).is_between(53.0, 55.0)
	assert_float(size_px.z).is_between(13.0, 15.0)
	instance.free()


func test_player_is_pixel_aligned_non_overlapping_and_face_connected() -> void:
	var instance := _instantiate(STATIC_PATH)
	if instance == null:
		return
	var boxes: Array[Dictionary] = []
	_collect_mesh_boxes(instance, instance, boxes)
	assert_int(boxes.size()).is_greater(50)
	for entry in boxes:
		var box: AABB = entry["aabb"]
		var size_px := box.size * PX_PER_METER
		var position_px := box.position * PX_PER_METER
		for value in [size_px.x, size_px.y, size_px.z]:
			assert_float(absf(value - roundf(value))) \
				.override_failure_message("player box is not pixel-sized: %s %s" % [entry["name"], size_px]) \
				.is_less(0.04)
		for value in [position_px.x, position_px.y, position_px.z]:
			assert_float(absf(value * 2.0 - roundf(value * 2.0))) \
				.override_failure_message("player box is off half-pixel grid: %s %s" % [entry["name"], position_px]) \
				.is_less(0.08)
	assert_array(SUPPORT.find_positive_volume_overlaps(instance)) \
		.override_failure_message("player has positive-volume box overlaps") \
		.is_empty()
	assert_array(SUPPORT.find_face_disconnected_parts(instance)) \
		.override_failure_message("player is not one face-connected component") \
		.is_empty()
	instance.free()


func test_player_only_uses_declared_local_asymmetry_and_contains_no_baked_equipment() -> void:
	var instance := _instantiate(STATIC_PATH)
	if instance == null:
		return
	var names: Array[String] = []
	_collect_names(instance, names)
	_assert_names_are_body_only(names)
	assert_array(SUPPORT.find_unmirrored_parts(
		instance,
		Vector3(-1.0, 1.0, 1.0),
		Vector3.ZERO,
		ALLOWED_ASYMMETRIC_PARTS
	)).override_failure_message(
		"player has undeclared left/right asymmetry"
	).is_empty()
	instance.free()


func test_player_rig_has_standard_bones_exactly_twenty_actions_and_body_only_meshes() -> void:
	if not FileAccess.file_exists(RIG_PATH):
		assert_bool(false).override_failure_message("missing player rig: %s" % RIG_PATH).is_true()
		return
	var report = VALIDATOR.validate_glb(RIG_PATH, true)
	assert_bool(report.ok).override_failure_message(str(report)).is_true()
	assert_int(report.animation_names.size()).is_equal(EXPECTED_ANIMATIONS.size())
	for animation_name in EXPECTED_ANIMATIONS:
		assert_bool(report.animation_names.has(animation_name)) \
			.override_failure_message("player rig missing animation: %s" % animation_name) \
			.is_true()
	for bone_name in EXPECTED_BONES:
		assert_bool(report.bone_names.has(bone_name)) \
			.override_failure_message("player rig missing bone: %s" % bone_name) \
			.is_true()
	var instance := _instantiate(RIG_PATH)
	if instance == null:
		return
	var names: Array[String] = []
	_collect_names(instance, names)
	_assert_names_are_body_only(names)
	for identity_part in [
		"cellar_vest_front_left", "cellar_apron_left_panel", "property_key_stem",
		"hair_side_part", "rolled_sleeve_right",
	]:
		assert_bool(names.has(identity_part)).is_true()
	instance.free()


func _instantiate(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		assert_bool(false).override_failure_message("missing player asset: %s" % path).is_true()
		return null
	var packed := load(path) as PackedScene
	assert_object(packed).is_not_null()
	if packed == null:
		return null
	var instance := packed.instantiate() as Node3D
	assert_object(instance).is_not_null()
	if instance != null:
		add_child(instance)
	return instance


func _declared_part_names(source: String) -> Array[String]:
	var names: Array[String] = []
	var pattern := RegEx.new()
	if pattern.compile('(?m)^\\s*add\\("([^"]+)"') != OK:
		return names
	for match_result in pattern.search_all(source):
		names.append(match_result.get_string(1))
	return names


func _assert_names_are_body_only(names: Array[String]) -> void:
	for raw_name in names:
		var name := raw_name.to_lower()
		for token in BODY_ONLY_FORBIDDEN_TOKENS:
			assert_bool(name.contains(token)) \
				.override_failure_message("player body bakes forbidden equipment part: %s" % raw_name) \
				.is_false()


func _assert_readable_capture(path: String, minimum_size: int) -> void:
	var inspection: Dictionary = SUPPORT.inspect_image_file(path)
	assert_bool(bool(inspection["exists"])) \
		.override_failure_message("missing player capture: %s" % path) \
		.is_true()
	if not bool(inspection["exists"]):
		return
	assert_bool(bool(inspection["readable"])).is_true()
	assert_int(int(inspection["width"])).is_greater_equal(minimum_size)
	assert_int(int(inspection["height"])).is_greater_equal(minimum_size)
	assert_bool(bool(inspection["nonblank"])) \
		.override_failure_message("player capture is blank or mostly uniform: %s" % path) \
		.is_true()


func _collect_names(node: Node, names: Array[String]) -> void:
	names.append(String(node.name))
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


func _collect_mesh_boxes(root_node: Node3D, node: Node, boxes: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var root_space := root_node.global_transform.affine_inverse() * mesh_node.global_transform
			boxes.append({
				"name": String(mesh_node.name),
				"aabb": root_space * mesh_node.get_aabb(),
			})
	for child in node.get_children():
		_collect_mesh_boxes(root_node, child, boxes)
