extends GdUnitTestSuite

# 验证火把是动态光源（由 voxel_prop.gd 在运行时 _build_torch() 生成 OmniLight3D），
# 且已被正确标记为 LightingController 可管理的火光（闪烁组 + light_role 元信息）。

func _find_first_omni(node: Node) -> OmniLight3D:
	if node is OmniLight3D:
		return node as OmniLight3D
	for c in node.get_children():
		var found := _find_first_omni(c)
		if found != null:
			return found
	return null


func test_torch_builds_a_dynamic_omni_light() -> void:
	# Act
	var torch_scene := load("res://scenes/props/torch/torch.tscn") as PackedScene
	assert_object(torch_scene).is_not_null()
	var torch: Node = torch_scene.instantiate()
	add_child(torch)  # 进入场景树后 voxel_prop._ready() 才会动态生成火把光
	var light := _find_first_omni(torch)
	# Assert: 火把确实携带一个动态 OmniLight3D 光源
	assert_object(light).is_not_null()
	torch.free()


func test_torch_light_is_registered_for_flicker() -> void:
	# Act
	var torch_scene := load("res://scenes/props/torch/torch.tscn") as PackedScene
	var torch: Node = torch_scene.instantiate()
	add_child(torch)  # 进入场景树后 voxel_prop._ready() 才会动态生成火把光
	var light := _find_first_omni(torch)
	# Assert: 该动态光已加入闪烁组，并标记 light_role=torch 供酒馆档案收束
	assert_object(light).is_not_null()
	assert_bool(light.is_in_group("flicker_light")).is_true()
	assert_str(light.get_meta("light_role", "")).is_equal("torch")
	torch.free()
