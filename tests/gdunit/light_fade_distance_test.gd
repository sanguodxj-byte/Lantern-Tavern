extends GdUnitTestSuite


func test_torch_light_fades_late_enough_for_dungeon_visibility() -> void:
	_assert_scene_fade_budget("res://scenes/props/torch/torch.tscn", 24.0, 10.0)
	var torch_scene := load("res://scenes/props/torch/torch.tscn") as PackedScene
	var torch: Node = torch_scene.instantiate()
	add_child(torch)  # 进入场景树后 voxel_prop._ready() 才会动态生成火把光
	var lights := _collect_fading_lights(torch)
	assert_bool(lights.size() > 0).is_true()
	for light in lights:
		var omni := light as OmniLight3D
		if omni == null:
			continue
		assert_float(omni.light_energy) \
			.override_failure_message("地牢火把亮度不足，远离掉落物光源后整体会过暗") \
			.is_greater_equal(3.2)
		assert_float(omni.omni_range) \
			.override_failure_message("地牢火把照明范围不足，房间中心容易近黑") \
			.is_greater_equal(10.0)
	torch.free()


func test_fireplace_light_fades_late_enough_for_tavern_visibility() -> void:
	_assert_scene_fade_budget("res://scenes/props/decor/fireplace.tscn", 14.0, 8.0)


func test_interaction_hint_lights_keep_larger_fade_distance() -> void:
	for scene_path in [
		"res://scenes/door/door.tscn",
		"res://scenes/characters/enemies/goblin.tscn",
	]:
		_assert_scene_fade_budget(scene_path, 14.0, 8.0)


func test_small_gameplay_hint_lights_keep_larger_fade_distance() -> void:
	for scene_path in [
		"res://scenes/traps/acid_trap.tscn",
		"res://scenes/traps/spikes_trap.tscn",
	]:
		_assert_scene_fade_budget(scene_path, 12.0, 8.0)


func _assert_scene_fade_budget(scene_path: String, min_begin: float, min_length: float) -> void:
	var packed := load(scene_path) as PackedScene
	assert_object(packed) \
		.override_failure_message("缺少光源场景: %s" % scene_path) \
		.is_not_null()
	var instance := packed.instantiate()
	add_child(instance)  # 进入场景树后 voxel_prop._ready() 才会动态生成光源（火把等）

	var fading_lights := _collect_fading_lights(instance)
	assert_bool(fading_lights.size() > 0) \
		.override_failure_message("%s 应至少包含一个启用 distance fade 的光源" % scene_path) \
		.is_true()
	for light in fading_lights:
		assert_float(light.distance_fade_begin) \
			.override_failure_message("%s 的 %s 淡出开始距离过近" % [scene_path, light.name]) \
			.is_greater_equal(min_begin)
		assert_float(light.distance_fade_length) \
			.override_failure_message("%s 的 %s 淡出长度过短" % [scene_path, light.name]) \
			.is_greater_equal(min_length)

	instance.free()


func _collect_fading_lights(root: Node) -> Array[Light3D]:
	var result: Array[Light3D] = []
	_collect_fading_lights_recursive(root, result)
	return result


func _collect_fading_lights_recursive(node: Node, result: Array[Light3D]) -> void:
	if node is Light3D and (node as Light3D).distance_fade_enabled:
		result.append(node as Light3D)
	for child in node.get_children():
		_collect_fading_lights_recursive(child, result)
