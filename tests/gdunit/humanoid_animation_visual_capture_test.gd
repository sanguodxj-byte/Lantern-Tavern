extends GdUnitTestSuite

const CAPTURE_SCRIPT := "res://tools/humanoid_animation_visual_capture.gd"


func test_capture_requires_one_exact_humanoid_and_one_exact_action() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	assert_str(source).contains("--asset=")
	assert_str(source).contains("--action=")
	assert_str(source).contains('text.contains(",")')
	assert_str(source).contains('text.contains("*")')
	assert_str(source).contains('text == "all"')
	var expected_rigs := {
		"goblin": "voxel_goblin_32px_rig.glb",
		"orc_raider": "voxel_orc_raider_48px_rig.glb",
		"skeleton": "voxel_skeleton_48px_rig.glb",
		"troll": "voxel_troll_64x_rig.glb",
		"minotaur": "voxel_minotaur_72px_rig.glb",
		"drow_blade": "voxel_drow_blade_48px_rig.glb",
	}
	for model_id in expected_rigs:
		assert_str(source).contains('"%s": "res://assets/meshes/characters/%s"' % [model_id, expected_rigs[model_id]])
	assert_str(source).contains("Capture the authored rig directly")
	assert_str(source).contains("mesh_instance.is_inside_tree()")


func test_capture_defines_idle_run_and_action_acceptance_phases() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	for phase_name in ["still", "contact_r", "passing_r", "contact_l", "passing_l", "windup", "action", "recover"]:
		assert_str(source).contains('"name": "%s"' % phase_name)
	assert_str(source).contains('voxel_%s_motion_%s_%s_%s.png')


func test_capture_releases_viewport_before_quitting() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	assert_str(source).contains("func _finish(exit_code: int) -> void:")
	assert_str(source).contains("SubViewport.UPDATE_DISABLED")
	assert_str(source).contains("remove_child(_viewport)")
	assert_str(source).contains("_viewport.free()")
	assert_str(source).contains("await process_frame")
	assert_str(source).contains("quit(exit_code)")
