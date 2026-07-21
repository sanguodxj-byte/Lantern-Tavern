extends GdUnitTestSuite
## Full runtime-scene contract for preview/runtime facing, pose, and hand mounts.

const RIG_PATH := "res://assets/meshes/characters/voxel_goblin_32px_rig.glb"
const RUNTIME_PATH := "res://scenes/characters/enemies/goblin.tscn"
const MAX_PLACEHOLDER_OFFSET_M := 6.0 / 32.0
const GOBLIN_WEAPON_SCALE := 0.45
const GOBLIN_SHIELD_SCALE := 0.4
const WINDUP_PROGRESS := 0.4
const STRIKE_PROGRESS := 0.72
const MIN_SHORTSWORD_CENTER_SPAN_PX := 13.5
const MAX_SHORTSWORD_CENTER_SPAN_PX := 14.5
const RENDER_CAPTURE_PATH := "res://tools/goblin_runtime_render_capture.gd"
const GOBLIN_SCENE_PATH := "res://scenes/characters/enemies/goblin.tscn"


func test_runtime_scene_keeps_raw_rig_facing_and_origin() -> void:
	var raw_rig := auto_free((load(RIG_PATH) as PackedScene).instantiate()) as Node3D
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate()) as CharacterBody3D
	var character := runtime.get_node("character") as Node3D
	assert_bool(character.transform.is_equal_approx(Transform3D.IDENTITY)) \
		.override_failure_message("runtime scene must not add a preview-only model transform") \
		.is_true()

	var raw_forward := _facial_forward(raw_rig)
	var runtime_forward := _facial_forward(character)
	assert_float(runtime_forward.z) \
		.override_failure_message("runtime goblin face must point toward Godot forward (-Z)") \
		.is_less(-0.5)
	assert_float(runtime_forward.dot(raw_forward)) \
		.override_failure_message("runtime scene and raw rig must face the same direction") \
		.is_greater(0.999)


func test_runtime_scene_retains_hand_attachments_under_skeleton() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate())
	var skeleton := _find_skeleton(runtime)
	var weapon_attach := runtime.find_child("WeaponBoneAttachment", true, false) as BoneAttachment3D
	var shield_attach := runtime.find_child("ShieldBoneAttachment", true, false) as BoneAttachment3D
	assert_object(skeleton).is_not_null()
	assert_object(weapon_attach).is_not_null()
	assert_object(shield_attach).is_not_null()
	assert_bool(weapon_attach.get_parent() == skeleton).is_true()
	assert_bool(shield_attach.get_parent() == skeleton).is_true()
	assert_str(weapon_attach.bone_name).is_equal("Hand.R")
	assert_str(shield_attach.bone_name).is_equal("Hand.L")


func test_equipment_placeholders_resolve_to_hand_attachments() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate())
	var equipment := runtime.get_node("EquipmentComponent") as EquipmentComponent
	var weapon_attach := runtime.find_child("WeaponBoneAttachment", true, false) as BoneAttachment3D
	var shield_attach := runtime.find_child("ShieldBoneAttachment", true, false) as BoneAttachment3D
	assert_object(equipment.weapon_placeholder).is_not_null()
	assert_object(equipment.shield_placeholder).is_not_null()
	assert_bool(equipment.weapon_placeholder.get_parent() == weapon_attach).is_true()
	assert_bool(equipment.shield_placeholder.get_parent() == shield_attach).is_true()
	assert_float(equipment.weapon_placeholder.position.length()) \
		.override_failure_message("weapon placeholder is offset too far from Hand.R") \
		.is_less_equal(MAX_PLACEHOLDER_OFFSET_M)


func test_goblin_shield_loadout_uses_a_one_hand_weapon() -> void:
	var source := FileAccess.get_file_as_string(GOBLIN_SCENE_PATH)
	assert_str(source).contains("res://data/weapons/shortsword.tres")
	assert_str(source).not_contains("res://data/weapons/axe.tres")


func test_voxel_weapon_placeholder_uses_goblin_one_hand_scale_without_rotation_or_offset() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate())
	var placeholder := runtime.find_child("WeaponPlaceholder", true, false) as Node3D
	assert_object(placeholder).is_not_null()
	assert_bool(placeholder.position.is_zero_approx()) \
		.override_failure_message("weapon grip origin must stay at Hand.R without positional drift") \
		.is_true()
	assert_bool(placeholder.basis.orthonormalized().is_equal_approx(Basis.IDENTITY)) \
		.override_failure_message("weapon grip axis must stay aligned with Hand.R without legacy rotation") \
		.is_true()
	assert_bool(placeholder.scale.is_equal_approx(Vector3.ONE * GOBLIN_WEAPON_SCALE)) \
		.override_failure_message("33px shortsword must scale to about 15px for the 42px goblin") \
		.is_true()


func test_mounted_shortsword_has_goblin_sized_visible_span() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate()) as CharacterBody3D
	runtime.set_script(null)
	runtime.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(runtime)
	await get_tree().process_frame
	var placeholder := runtime.find_child("WeaponPlaceholder", true, false) as Node3D
	assert_int(placeholder.get_child_count()).is_greater(0)
	var weapon := placeholder.get_child(0)
	var blade_tip := weapon.find_child("blade_tip", true, false) as Node3D
	var pommel := weapon.find_child("pommel_cap", true, false) as Node3D
	assert_object(blade_tip).is_not_null()
	assert_object(pommel).is_not_null()
	var measurement_root := placeholder.get_parent()
	var tip_position := _transform_relative_to(blade_tip, measurement_root).origin
	var pommel_position := _transform_relative_to(pommel, measurement_root).origin
	var center_span_px := tip_position.distance_to(pommel_position) * 32.0
	assert_float(center_span_px) \
		.override_failure_message(
			"mounted shortsword span must read as a compact goblin weapon: %.2fpx"
			% center_span_px
		) \
		.is_between(MIN_SHORTSWORD_CENTER_SPAN_PX, MAX_SHORTSWORD_CENTER_SPAN_PX)


func test_voxel_shield_placeholder_uses_goblin_buckler_scale() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate())
	var placeholder := runtime.find_child("ShieldPlaceholder", true, false) as Node3D
	assert_object(placeholder).is_not_null()
	assert_bool(placeholder.scale.is_equal_approx(Vector3.ONE * GOBLIN_SHIELD_SCALE)) \
		.override_failure_message("goblin buckler must not obscure the whole 44px character") \
		.is_true()


func test_runtime_scene_exposes_required_animations() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate())
	var animation_player := runtime.get_node("character/AnimationPlayer") as AnimationPlayer
	for animation_name in ["idle", "run", "slash_one_hand"]:
		assert_bool(animation_player.has_animation(animation_name)) \
			.override_failure_message("runtime scene missing animation: %s" % animation_name) \
			.is_true()
	for animation_name in animation_player.get_animation_list():
		assert_bool(String(animation_name).begins_with("debug_")) \
			.override_failure_message("runtime rig must not contain temporary search actions") \
			.is_false()


func test_one_hand_slash_authors_wrist_rotation_through_the_full_arc() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate())
	var animation_player := runtime.get_node("character/AnimationPlayer") as AnimationPlayer
	var animation := animation_player.get_animation("slash_one_hand")
	var wrist_key_count := 0
	for track_index in animation.get_track_count():
		var track_path := String(animation.track_get_path(track_index))
		if track_path.contains("Hand.R") and animation.track_get_type(track_index) == Animation.TYPE_ROTATION_3D:
			wrist_key_count = animation.track_get_key_count(track_index)
			break
	assert_int(wrist_key_count) \
		.override_failure_message("slash_one_hand needs Hand.R keys for windup, strike, and recovery") \
		.is_greater_equal(4)


func test_one_hand_slash_moves_blade_from_back_windup_to_front_strike() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate()) as CharacterBody3D
	runtime.set_script(null)
	runtime.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(runtime)
	await get_tree().process_frame
	var equipment := runtime.get_node("EquipmentComponent") as EquipmentComponent
	assert_int(equipment.weapon_placeholder.get_child_count()).is_greater(0)
	var weapon := equipment.weapon_placeholder.get_child(0)
	var blade_tip := weapon.find_child("blade_tip", true, false) as Node3D
	assert_object(blade_tip).is_not_null()
	var animation_player := runtime.get_node("character/AnimationPlayer") as AnimationPlayer
	var attack := animation_player.get_animation("slash_one_hand")
	animation_player.play("slash_one_hand")
	animation_player.seek(attack.length * WINDUP_PROGRESS, true)
	animation_player.advance(0.0)
	await get_tree().process_frame
	var windup_tip := runtime.to_local(blade_tip.global_position)
	var windup_grip := runtime.to_local(equipment.weapon_placeholder.global_position)
	var windup_direction := windup_grip.direction_to(windup_tip)
	animation_player.seek(attack.length * STRIKE_PROGRESS, true)
	animation_player.advance(0.0)
	await get_tree().process_frame
	var strike_tip := runtime.to_local(blade_tip.global_position)
	var strike_grip := runtime.to_local(equipment.weapon_placeholder.global_position)
	var strike_direction := strike_grip.direction_to(strike_tip)
	var windup_target := Vector3(-0.35, 0.75, 0.56).normalized()
	var strike_target := Vector3(0.55, -0.45, -0.70).normalized()
	assert_float(windup_grip.x) \
		.override_failure_message("windup grip must stay outside the goblin's right shoulder") \
		.is_less(-0.2)
	assert_float(strike_grip.x) \
		.override_failure_message("strike grip must cross the body center toward the left") \
		.is_greater(0.05)
	assert_float(windup_direction.dot(windup_target)) \
		.override_failure_message(
			"windup blade must point right, up, and behind the goblin: direction=%s" % windup_direction
		) \
		.is_greater(0.85)
	assert_float(strike_direction.dot(strike_target)) \
		.override_failure_message(
			"strike blade must point across the body, forward, and down: direction=%s" % strike_direction
		) \
		.is_greater(0.9)


func test_one_hand_slash_raises_weapon_hand_to_shoulder_for_windup() -> void:
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate())
	var animation_player := runtime.get_node("character/AnimationPlayer") as AnimationPlayer
	var skeleton := _find_skeleton(runtime)
	var attack := animation_player.get_animation("slash_one_hand")
	animation_player.play("slash_one_hand")
	animation_player.seek(attack.length * WINDUP_PROGRESS, true)
	animation_player.advance(0.0)
	var hand_position := skeleton.get_bone_global_pose(skeleton.find_bone("Hand.R")).origin
	var shoulder_position := skeleton.get_bone_global_pose(skeleton.find_bone("UpperArm.R")).origin
	assert_float(hand_position.y - shoulder_position.y) \
		.override_failure_message(
			"windup hand must reach shoulder height: hand y=%.3f, shoulder y=%.3f"
			% [hand_position.y, shoulder_position.y]
		) \
		.is_greater_equal(0.0)


func test_runtime_scene_pose_matches_raw_rig() -> void:
	var raw_rig := auto_free((load(RIG_PATH) as PackedScene).instantiate())
	var runtime := auto_free((load(RUNTIME_PATH) as PackedScene).instantiate())
	var raw_player := raw_rig.get_node("AnimationPlayer") as AnimationPlayer
	var runtime_player := runtime.get_node("character/AnimationPlayer") as AnimationPlayer
	var raw_skeleton := _find_skeleton(raw_rig)
	var runtime_skeleton := _find_skeleton(runtime)
	var sample_time := raw_player.get_animation("slash_one_hand").length * 0.5
	for player in [raw_player, runtime_player]:
		player.play("slash_one_hand")
		player.seek(sample_time, true)
		player.advance(0.0)

	for bone_name in ["Root", "Torso", "UpperArm.R", "Hand.R"]:
		var raw_pose := raw_skeleton.get_bone_global_pose(raw_skeleton.find_bone(bone_name))
		var runtime_pose := runtime_skeleton.get_bone_global_pose(runtime_skeleton.find_bone(bone_name))
		assert_bool(runtime_pose.is_equal_approx(raw_pose)) \
			.override_failure_message("runtime pose diverged from raw rig at bone: %s" % bone_name) \
			.is_true()


func test_runtime_render_capture_is_single_model_and_uses_runtime_scene() -> void:
	var source := FileAccess.get_file_as_string(RENDER_CAPTURE_PATH)
	assert_bool(source.is_empty()).is_false()
	assert_str(source).contains('const RUNTIME_PATH := "res://scenes/characters/enemies/goblin.tscn"')
	assert_str(source).contains('animation_player.play("slash_one_hand")')
	assert_str(source).contains("const WINDUP_PROGRESS := 0.4")
	assert_str(source).contains("const STRIKE_PROGRESS := 0.72")
	assert_str(source).contains("weapon_placeholder.get_child_count()")
	for phase_name in ["windup", "strike", "recover"]:
		assert_str(source).contains('{"name": "%s"' % phase_name)
	assert_str(source).contains("voxel_goblin_runtime_slash_%s_%s.png")
	assert_str(source).not_contains("shield_placeholder.visible = false")
	assert_str(source).not_contains("for model_id in")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _facial_forward(root: Node) -> Vector3:
	var head := root.find_child("head_main", true, false) as Node3D
	var nose := root.find_child("nose", true, false) as Node3D
	assert_object(head).is_not_null()
	assert_object(nose).is_not_null()
	var head_position := _transform_relative_to(head, root).origin
	var nose_position := _transform_relative_to(nose, root).origin
	return head_position.direction_to(nose_position)


func _transform_relative_to(node: Node3D, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != root and current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
