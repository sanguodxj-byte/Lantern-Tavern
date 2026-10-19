extends GdUnitTestSuite

## 恐狼体素资产回归：GLB、部件、骨骼、动画、三视图预览与固定输出契约。

func test_voxel_dire_wolf_generator_script_exists() -> void:
	assert_bool(FileAccess.file_exists("res://tools/generate_voxel_dire_wolf.py")).is_true()
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_dire_wolf.py")
	assert_bool(source.contains('MODEL_ID = "dire_wolf"')).is_true()
	assert_bool(source.contains("LENGTH_PX = 100.0")).is_true()
	assert_bool(source.contains("HEIGHT_PX = 44.0")).is_true()
	assert_bool(source.contains("reject_target_override(MODEL_ID)")).is_true()
	assert_bool(source.contains("finish_model")).is_true()
	assert_bool(source.contains("build_dire_wolf_rig")).is_true()


func test_voxel_dire_wolf_generator_owns_its_static_and_rig_outputs() -> void:
	var source := FileAccess.get_file_as_string("res://tools/generate_voxel_dire_wolf.py")
	assert_str(source).contains('MODEL_ID = "dire_wolf"')
	assert_str(source).contains("STATIC_OUTPUT")
	assert_str(source).contains("voxel_dire_wolf_100px.glb")
	assert_str(source).contains("RIG_OUTPUT")
	assert_str(source).contains("voxel_dire_wolf_100px_rig.glb")
	assert_str(source).contains("reject_target_override(MODEL_ID)")


func test_voxel_dire_wolf_outputs_exist() -> void:
	assert_bool(FileAccess.file_exists("res://assets/meshes/characters/voxel_dire_wolf_100px.glb")).is_true()
	assert_bool(FileAccess.file_exists("res://assets/meshes/characters/voxel_dire_wolf_100px_rig.glb")).is_true()
	for image_name in [
		"voxel_dire_wolf_render_preview.png",
		"voxel_dire_wolf_render_front.png",
		"voxel_dire_wolf_render_side.png",
		"voxel_dire_wolf_render_top.png",
	]:
		assert_bool(FileAccess.file_exists("res://reports/characters_preview/%s" % image_name)) \
			.override_failure_message("missing dire wolf preview: %s" % image_name) \
			.is_true()


func test_voxel_dire_wolf_render_images_are_readable_and_visible() -> void:
	for view_name in ["front", "side", "top"]:
		var image_path := "res://reports/characters_preview/voxel_dire_wolf_render_%s.png" % view_name
		var image := Image.load_from_file(image_path)
		assert_object(image).override_failure_message("cannot load %s" % image_path).is_not_null()
		assert_int(image.get_width()).is_greater(64)
		assert_int(image.get_height()).is_greater(64)
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


func test_voxel_dire_wolf_glb_contains_expected_parts() -> void:
	var packed := load("res://assets/meshes/characters/voxel_dire_wolf_100px.glb") as PackedScene
	assert_object(packed).is_not_null()
	var inst := auto_free(packed.instantiate()) as Node
	assert_object(inst).is_not_null()

	var names: Array[String] = []
	_collect_names(inst, names)

	for part_name in [
		"chest",
		"body_core",
		"haunch",
		"neck",
		"head",
		"muzzle",
		"jaw",
		"nose",
		"left_eye",
		"right_eye",
		"left_ear",
		"right_ear",
		"left_fang",
		"right_fang",
		"left_front_thigh",
		"left_front_foot",
		"right_front_thigh",
		"right_front_foot",
		"left_back_thigh",
		"left_back_foot",
		"right_back_thigh",
		"right_back_foot",
		"tail_1",
		"tail_2",
		"tail_3",
	]:
		assert_bool(names.has(part_name)) \
			.override_failure_message("voxel dire wolf GLB missing part: %s" % part_name) \
			.is_true()


func test_voxel_dire_wolf_rig_has_expected_bones_and_animations() -> void:
	var packed := load("res://assets/meshes/characters/voxel_dire_wolf_100px_rig.glb") as PackedScene
	assert_object(packed).is_not_null()
	var inst := auto_free(packed.instantiate()) as Node
	assert_object(inst).is_not_null()

	var skeleton := _find_skeleton(inst)
	assert_object(skeleton).is_not_null()
	for bone_name in ["Root", "Torso", "Neck", "Head", "Tail1", "Tail2", "Tail3",
			"FrontLeg.L", "FrontLeg.R", "BackLeg.L", "BackLeg.R"]:
		assert_int(skeleton.find_bone(bone_name)) \
			.override_failure_message("voxel dire wolf Skeleton missing bone: %s" % bone_name) \
			.is_greater(-1)

	var ap := _find_animation_player(inst)
	assert_object(ap).is_not_null()
	for animation_name in ["idle", "run", "slash", "block", "hurt", "stunned", "death",
			"kick", "lift", "pickup", "throw_weapon", "throw_furniture", "claw_swipe", "default"]:
		assert_bool(ap.has_animation(animation_name)) \
			.override_failure_message("voxel dire wolf rig missing animation: %s" % animation_name) \
			.is_true()


func test_model_viewer_localizes_dire_wolf() -> void:
	var source := FileAccess.get_file_as_string("res://scenes/ui/model_viewer.gd")
	assert_bool(source.contains('"dire_wolf": "恐狼"')).is_true()


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
