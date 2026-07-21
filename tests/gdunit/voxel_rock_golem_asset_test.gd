extends GdUnitTestSuite

## 岩石魔像体素资产回归：GLB、部件、骨骼、三视图预览。

func test_voxel_rock_golem_generator_script_exists() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_rock_golem.py")).is_true()
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_rock_golem.py")
	assert_bool(source.contains("GOLEM_HEIGHT_PX = 80.0")).is_true()
	assert_bool(source.contains("1m = 32px") or source.contains("PX")).is_true()
	assert_bool(source.contains("create_voxel_humanoid_armature")).is_true()
	assert_bool(source.contains("GROUND_OFFSET_PX")).is_true()


func test_voxel_rock_golem_outputs_exist() -> void:
	assert_bool(FileAccess.file_exists("res://assets/meshes/characters/voxel_rock_golem_80px.glb")).is_true()
	for image_name in [
		"voxel_rock_golem_preview.png",
		"voxel_rock_golem_front.png",
		"voxel_rock_golem_side.png",
		"voxel_rock_golem_top.png",
	]:
		assert_bool(FileAccess.file_exists("res://reports/characters_preview/%s" % image_name)) \
			.override_failure_message("missing rock golem preview: %s" % image_name) \
			.is_true()


func test_voxel_rock_golem_three_view_images_are_readable_and_visible() -> void:
	for view_name in ["front", "side", "top"]:
		var image_path := "res://reports/characters_preview/voxel_rock_golem_%s.png" % view_name
		var image := Image.load_from_file(image_path)
		assert_object(image).override_failure_message("cannot load %s" % image_path).is_not_null()
		assert_int(image.get_width()).is_greater(64)
		assert_int(image.get_height()).is_greater(64)
		# 非空白：抽样若干像素，至少有非透明或非纯背景色
		var visible := false
		var w := image.get_width()
		var h := image.get_height()
		for y in range(0, h, maxi(1, h / 16)):
			for x in range(0, w, maxi(1, w / 16)):
				var c := image.get_pixel(x, y)
				if c.a > 0.05 and (c.r + c.g + c.b) > 0.05:
					visible = true
					break
			if visible:
				break
		assert_bool(visible).override_failure_message("%s looks blank" % image_path).is_true()


func test_voxel_rock_golem_glb_contains_expected_parts() -> void:
	var packed := load("res://assets/meshes/characters/voxel_rock_golem_80px.glb") as PackedScene
	assert_object(packed).is_not_null()
	var inst := auto_free(packed.instantiate()) as Node
	assert_object(inst).is_not_null()

	var names: Array[String] = []
	_collect_names(inst, names)

	for part_name in [
		"head_main",
		"brow_ridge",
		"jaw_block",
		"eye_left",
		"eye_right",
		"head_crown_slab",
		"torso_main",
		"chest_plate_upper",
		"core_chest_glow",
		"shoulder_bar",
		"pelvis_main",
		"left_upper_arm_main",
		"left_forearm_main",
		"left_hand_fist",
		"right_upper_arm_main",
		"right_forearm_main",
		"right_hand_fist",
		"left_thigh_main",
		"left_shin_main",
		"left_foot_main",
		"right_thigh_main",
		"right_shin_main",
		"right_foot_main",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("voxel rock golem GLB missing part: %s" % part_name) \
			.is_true()

	var skeleton := _find_skeleton(inst)
	assert_object(skeleton).is_not_null()
	for bone_name in [
		"Root", "Pelvis", "Torso", "Neck", "Head",
		"UpperArm.R", "LowerArm.R", "Hand.R",
		"UpperArm.L", "LowerArm.L", "Hand.L",
		"UpperLeg.R", "LowerLeg.R", "Foot.R",
		"UpperLeg.L", "LowerLeg.L", "Foot.L",
	]:
		assert_int(skeleton.find_bone(bone_name)) \
			.override_failure_message("voxel rock golem Skeleton missing bone: %s" % bone_name) \
			.is_greater(-1)


func test_voxel_rock_golem_generator_owns_its_static_and_rig_outputs() -> void:
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_rock_golem.py")
	assert_str(source).contains('MODEL_ID = "rock_golem"')
	assert_str(source).contains("STATIC_OUTPUT")
	assert_str(source).contains("voxel_rock_golem_80px.glb")
	assert_str(source).contains("RIG_OUTPUT")
	assert_str(source).contains("voxel_rock_golem_80px_rig.glb")
	assert_str(source).contains("reject_target_override(MODEL_ID)")
	assert_str(source).contains("build_humanoid_rig")


func test_voxel_rock_golem_rig_outputs_exist_when_generated() -> void:
	# rig 由第二步管线生成；若已存在则校验可加载
	var path := "res://assets/meshes/characters/voxel_rock_golem_80px_rig.glb"
	if not FileAccess.file_exists(path):
		# 仅静态 GLB 阶段也允许通过；注册与静态资产仍由其它用例覆盖
		assert_bool(FileAccess.file_exists("res://assets/meshes/characters/voxel_rock_golem_80px.glb")).is_true()
		return
	var packed := load(path) as PackedScene
	assert_object(packed).override_failure_message("rock golem rig not loadable").is_not_null()
	var inst := auto_free(packed.instantiate()) as Node
	assert_object(inst).is_not_null()
	var ap := _find_animation_player(inst)
	assert_object(ap).override_failure_message("rock golem rig missing AnimationPlayer").is_not_null()


func test_model_viewer_localizes_rock_golem() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/model_viewer.gd")
	assert_bool(source.contains('"rock_golem": "岩石魔像"')).is_true()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var res := _find_skeleton(child)
		if res:
			return res
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var res := _find_animation_player(child)
		if res:
			return res
	return null


func _collect_names(node: Node, names: Array[String]) -> void:
	names.append(node.name)
	for child in node.get_children():
		_collect_names(child, names)
