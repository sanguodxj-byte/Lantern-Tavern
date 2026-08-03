extends GdUnitTestSuite

const ACTION_SOURCE := "res://tools/voxel_character_rig.py"
const GENERATORS := {
	"goblin": "res://tools/generate_voxel_goblin.py",
	"orc_raider": "res://tools/generate_voxel_orc_raider.py",
	"skeleton": "res://tools/generate_voxel_skeleton.py",
	"troll": "res://tools/generate_voxel_troll.py",
	"minotaur": "res://tools/generate_voxel_minotaur.py",
	"drow_blade": "res://tools/generate_voxel_drow_blade.py",
}
const RIGS := {
	"goblin": "res://assets/meshes/characters/voxel_goblin_32px_rig.glb",
	"orc_raider": "res://assets/meshes/characters/voxel_orc_raider_48px_rig.glb",
	"skeleton": "res://assets/meshes/characters/voxel_skeleton_48px_rig.glb",
	"troll": "res://assets/meshes/characters/voxel_troll_64x_rig.glb",
	"minotaur": "res://assets/meshes/characters/voxel_minotaur_72px_rig.glb",
	"drow_blade": "res://assets/meshes/characters/voxel_drow_blade_48px_rig.glb",
}
const RUN_LEG_BONES := [
	"UpperLeg.L", "LowerLeg.L", "Foot.L",
	"UpperLeg.R", "LowerLeg.R", "Foot.R",
]
const RUN_PHASES := [0.0, 0.25, 0.5, 0.75]
const MAX_CONTACT_FOOT_GROUND_ERROR_M := 0.035
const MAX_SUPPORT_FOOT_GROUND_ERROR_M := 0.018
const MIN_SWING_FOOT_CLEARANCE_M := 0.012
const MAX_DEATH_GROUND_ERROR_M := 0.04


func test_shared_authoring_declares_static_idle_world_axis_conversion_and_bounded_motion() -> void:
	var source := FileAccess.get_file_as_string(ACTION_SOURCE)
	assert_str(source).contains("class HumanoidMotionProfile")
	assert_str(source).contains("swing_lift_scale")
	assert_str(source).contains("swing_foot_pitch_scale")
	assert_str(source).contains("contact_foot_pitch_scale")
	assert_str(source).contains("contact_lead_knee_scale")
	assert_str(source).contains("contact_height_offset_m")
	assert_str(source).contains("passing_height_offset_m")
	assert_str(source).contains("death_height_offset_m")
	assert_str(source).contains("def _pose_offset_from_blender_world")
	assert_str(source).contains('make_action(armature, "idle", 1')
	assert_str(source).contains("RUN_FRAME_COUNT = 24")
	assert_str(source).contains("RUN_CONTACT_PELVIS_DROP_M")
	assert_str(source).contains("RUN_PASSING_PELVIS_DROP_M")
	assert_str(source).contains("MAX_AUTHORED_ROTATION_DEGREES")
	assert_str(source).contains("def _validate_authored_pose_bounds")
	assert_bool(source.contains("_legacy_build_all_actions")).override_failure_message(
		"obsolete moving-idle action authoring must not remain available"
	).is_false()
	assert_bool(source.contains("_legacy_build_weapon_actions")).override_failure_message(
		"obsolete multi-axis weapon contortions must not remain available"
	).is_false()
	assert_bool(source.contains("(120, 150, -105)")).override_failure_message(
		"the removed elbow inversion pose must not return"
	).is_false()


func test_every_accepted_humanoid_generator_owns_an_explicit_motion_profile() -> void:
	for model_id in GENERATORS:
		var source := FileAccess.get_file_as_string(GENERATORS[model_id])
		assert_str(source).override_failure_message(
			"%s must import HumanoidMotionProfile" % model_id
		).contains("HumanoidMotionProfile")
		assert_str(source).override_failure_message(
			"%s must declare its own motion profile" % model_id
		).contains("MOTION_PROFILE = HumanoidMotionProfile(")
		assert_str(source).override_failure_message(
			"%s must pass its profile to locomotion authoring" % model_id
		).contains("build_all_actions(armature, MOTION_PROFILE)")
		assert_str(source).override_failure_message(
			"%s must pass its profile to weapon authoring" % model_id
		).contains("build_weapon_actions(armature, MOTION_PROFILE)")
		assert_str(source).override_failure_message(
			"%s must export its rig output" % model_id
		).contains("export_rig_glb(RIG_OUTPUT)")
	var orc_source := FileAccess.get_file_as_string(GENERATORS["orc_raider"])
	for view in ["preview", "front", "side", "top"]:
		assert_str(orc_source).override_failure_message(
			"orc real 3D %s must not overwrite its structural projection" % view
		).contains('voxel_orc_raider_render_%s.png' % view)


func test_imported_idle_is_a_single_static_pose_for_every_humanoid() -> void:
	for model_id in RIGS:
		var instance_and_player := _instantiate_player(RIGS[model_id])
		var instance := instance_and_player[0] as Node3D
		var player := instance_and_player[1] as AnimationPlayer
		if instance == null or player == null:
			continue
		var idle := player.get_animation("idle")
		assert_object(idle).override_failure_message("%s missing idle" % model_id).is_not_null()
		if idle != null:
			assert_float(idle.length).override_failure_message(
				"%s idle must be a one-frame static clip" % model_id
			).is_less_equal(0.05)
			for track_index in idle.get_track_count():
				assert_bool(_track_is_static(idle, track_index)).override_failure_message(
					"%s idle track moves: %s" % [model_id, idle.track_get_path(track_index)]
				).is_true()
		instance.free()


func test_imported_run_drives_both_three_joint_leg_chains_and_closes_the_loop() -> void:
	for model_id in RIGS:
		var instance_and_player := _instantiate_player(RIGS[model_id])
		var instance := instance_and_player[0] as Node3D
		var player := instance_and_player[1] as AnimationPlayer
		if instance == null or player == null:
			continue
		var run := player.get_animation("run")
		assert_object(run).override_failure_message("%s missing run" % model_id).is_not_null()
		if run != null:
			assert_float(run.length).is_between(0.95, 1.05)
			for bone_name in RUN_LEG_BONES:
				var track_index := _find_bone_track(run, bone_name, Animation.TYPE_ROTATION_3D)
				assert_int(track_index).override_failure_message(
					"%s run missing %s rotation" % [model_id, bone_name]
				).is_greater_equal(0)
				if track_index >= 0:
					assert_float(_rotation_track_variation(run, track_index)).override_failure_message(
						"%s run leaves %s rigid" % [model_id, bone_name]
					).is_greater(0.03)
					assert_bool(_rotation_track_loops(run, track_index)).override_failure_message(
						"%s run does not close %s" % [model_id, bone_name]
					).is_true()
		instance.free()


func test_imported_death_uses_root_motion_instead_of_folding_only_the_torso() -> void:
	for model_id in RIGS:
		var instance_and_player := _instantiate_player(RIGS[model_id])
		var instance := instance_and_player[0] as Node3D
		var player := instance_and_player[1] as AnimationPlayer
		if instance == null or player == null:
			continue
		var death := player.get_animation("death")
		assert_object(death).override_failure_message("%s missing death" % model_id).is_not_null()
		if death != null:
			var rotation_track := _find_bone_track(death, "Root", Animation.TYPE_ROTATION_3D)
			var position_track := _find_bone_track(death, "Root", Animation.TYPE_POSITION_3D)
			assert_int(rotation_track).override_failure_message(
				"%s death must rotate the whole rig through Root" % model_id
			).is_greater_equal(0)
			assert_int(position_track).override_failure_message(
				"%s death must keep the falling body above the floor through Root" % model_id
			).is_greater_equal(0)
		instance.free()


func test_imported_death_finishes_in_contact_with_the_ground() -> void:
	for model_id in RIGS:
		var instance_and_player := _instantiate_player(RIGS[model_id])
		var instance := instance_and_player[0] as Node3D
		var player := instance_and_player[1] as AnimationPlayer
		if instance == null or player == null:
			continue
		add_child(instance)
		await get_tree().process_frame
		var death := player.get_animation("death")
		assert_object(death).override_failure_message("%s missing death" % model_id).is_not_null()
		if death != null:
			player.play("death")
			player.seek(death.length, true)
			player.advance(0.0)
			await get_tree().process_frame
			var ground_error := _lowest_visible_point_y(instance)
			assert_float(absf(ground_error)).override_failure_message(
				"%s death ends %.3fm from the ground" % [model_id, ground_error]
			).is_less_equal(MAX_DEATH_GROUND_ERROR_M)
		remove_child(instance)
		instance.free()


func test_imported_run_keeps_a_support_foot_at_ground_in_every_authored_phase() -> void:
	for model_id in RIGS:
		var instance_and_player := _instantiate_player(RIGS[model_id])
		var instance := instance_and_player[0] as Node3D
		var player := instance_and_player[1] as AnimationPlayer
		if instance == null or player == null:
			continue
		add_child(instance)
		await get_tree().process_frame
		var run := player.get_animation("run")
		assert_object(run).override_failure_message("%s missing run" % model_id).is_not_null()
		if run != null:
			player.play("run")
			for phase_index in RUN_PHASES.size():
				var progress: float = RUN_PHASES[phase_index]
				player.seek(run.length * progress, true)
				player.advance(0.0)
				await get_tree().process_frame
				var heights := _foot_heights_by_side(instance)
				var grounded_sides: Array[String] = ["left", "right"]
				if phase_index == 1:
					grounded_sides = ["left"]
				elif phase_index == 3:
					grounded_sides = ["right"]
				for side in grounded_sides:
					var support_height := float(heights.get(side, INF))
					var allowed_error := MAX_SUPPORT_FOOT_GROUND_ERROR_M
					if phase_index == 0 or phase_index == 2:
						allowed_error = MAX_CONTACT_FOOT_GROUND_ERROR_M
					assert_float(absf(support_height)).override_failure_message(
						"%s run phase %.2f leaves its %s support foot %.3fm from ground"
						% [model_id, progress, side, support_height]
					).is_less_equal(allowed_error)
				if phase_index == 1 or phase_index == 3:
					var swing_side := "right" if phase_index == 1 else "left"
					var swing_height := float(heights.get(swing_side, -INF))
					assert_float(swing_height).override_failure_message(
						"%s run phase %.2f drags its %s swing foot at %.3fm"
						% [model_id, progress, swing_side, swing_height]
					).is_greater_equal(MIN_SWING_FOOT_CLEARANCE_M)
		remove_child(instance)
		instance.free()


func _instantiate_player(path: String) -> Array:
	var packed := load(path) as PackedScene
	assert_object(packed).override_failure_message("cannot load %s" % path).is_not_null()
	if packed == null:
		return [null, null]
	var instance := packed.instantiate() as Node3D
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(player).override_failure_message("%s missing AnimationPlayer" % path).is_not_null()
	return [instance, player]


func _track_is_static(animation: Animation, track_index: int) -> bool:
	var key_count := animation.track_get_key_count(track_index)
	if key_count <= 1:
		return true
	var first = animation.track_get_key_value(track_index, 0)
	for key_index in range(1, key_count):
		var value = animation.track_get_key_value(track_index, key_index)
		if first is Quaternion and value is Quaternion:
			if (first as Quaternion).angle_to(value as Quaternion) > 0.0001:
				return false
		elif first is Vector3 and value is Vector3:
			if not (first as Vector3).is_equal_approx(value as Vector3):
				return false
		elif first != value:
			return false
	return true


func _find_bone_track(animation: Animation, bone_name: String, track_type: Animation.TrackType) -> int:
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) == track_type \
				and String(animation.track_get_path(track_index)).ends_with(":" + bone_name):
			return track_index
	return -1


func _rotation_track_variation(animation: Animation, track_index: int) -> float:
	var first := animation.track_get_key_value(track_index, 0) as Quaternion
	var maximum := 0.0
	for key_index in animation.track_get_key_count(track_index):
		var value := animation.track_get_key_value(track_index, key_index) as Quaternion
		maximum = maxf(maximum, first.angle_to(value))
	return maximum


func _rotation_track_loops(animation: Animation, track_index: int) -> bool:
	var key_count := animation.track_get_key_count(track_index)
	if key_count < 2:
		return false
	var first := animation.track_get_key_value(track_index, 0) as Quaternion
	var last := animation.track_get_key_value(track_index, key_count - 1) as Quaternion
	return first.angle_to(last) <= 0.001


func _foot_heights_by_side(instance: Node3D) -> Dictionary:
	var heights := {"left": INF, "right": INF}
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var mesh_name := String(mesh_instance.name).to_lower()
		if not (mesh_name.contains("foot") or mesh_name.contains("boot") or mesh_name.contains("hoof")):
			continue
		var side := "left" if mesh_name.contains("left") else "right" if mesh_name.contains("right") else ""
		if side.is_empty():
			continue
		var bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		heights[side] = minf(float(heights[side]), bounds.position.y)
	for side in heights:
		assert_float(float(heights[side])).override_failure_message(
			"rig must expose named %s foot/boot/hoof meshes for grounding verification" % side
		).is_less(INF)
	return heights


func _lowest_visible_point_y(instance: Node3D) -> float:
	var lowest := INF
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		lowest = minf(lowest, bounds.position.y)
	assert_float(lowest).override_failure_message(
		"rig must expose visible mesh bounds for death grounding verification"
	).is_less(INF)
	return lowest
